import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

/// Tiny HTTP server on 127.0.0.1 that streams files straight from SFTP,
/// with HTTP Range support — so video/audio can seek without downloading the
/// whole file, and HTML pages load their relative CSS/JS/images.
class MediaServer {
  MediaServer._();
  static final MediaServer i = MediaServer._();

  HttpServer? _server;
  final Map<String, SftpClient> _mounts = {};
  final _rnd = Random.secure();

  Future<int> _ensure() async {
    final s = _server;
    if (s != null) return s.port;
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen(_handle);
    _server = srv;
    return srv.port;
  }

  /// Returns a base URL that maps to the remote filesystem root.
  Future<String> mount(SftpClient sftp) async {
    final port = await _ensure();
    final token = List.generate(32, (_) => _rnd.nextInt(16).toRadixString(16)).join();
    _mounts[token] = sftp;
    return 'http://127.0.0.1:$port/$token';
  }

  void unmount(String baseUrl) {
    final token = Uri.parse(baseUrl).pathSegments.first;
    _mounts.remove(token);
  }

  /// Full URL for a remote absolute path.
  static String urlFor(String base, String remotePath) =>
      base + remotePath.split('/').map(Uri.encodeComponent).join('/');

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final segs = req.uri.pathSegments;
      final sftp = segs.isEmpty ? null : _mounts[segs.first];
      // Only GET/HEAD, and only for our own host name (blocks DNS rebinding).
      final hostOk = (req.headers.host ?? '') == '127.0.0.1';
      if (sftp == null || !hostOk || (req.method != 'GET' && req.method != 'HEAD')) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      var path = '/${segs.skip(1).join('/')}';
      var st = await sftp.stat(path);
      if (st.isDirectory) {
        path = path.endsWith('/') ? '${path}index.html' : '$path/index.html';
        st = await sftp.stat(path);
      }
      final size = st.size ?? 0;
      final mime = mimeFor(path);
      res.headers.contentType = ContentType.parse(mime);
      res.headers.set('X-Content-Type-Options', 'nosniff');
      if (mime.startsWith('text/html') || mime.startsWith('image/svg')) {
        // Pages from the server run in an opaque origin: scripts work, but they
        // can't read other files through this mount (the token in the URL maps
        // to the server's whole filesystem — think ~/.ssh/id_rsa). Same as the
        // desktop app.
        res.headers.set('Content-Security-Policy', 'sandbox allow-scripts allow-forms allow-popups allow-modals allow-downloads');
      }
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

      var start = 0;
      var end = size - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.startsWith('bytes=')) {
        final parts = range.substring(6).split(',').first.split('-');
        if (parts[0].isEmpty) {
          start = max(0, size - int.parse(parts[1]));
        } else {
          start = int.parse(parts[0]);
          if (parts.length > 1 && parts[1].isNotEmpty) end = min(int.parse(parts[1]), size - 1);
        }
        if (start >= size) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
          await res.close();
          return;
        }
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
      }
      final length = size == 0 ? 0 : end - start + 1;
      res.contentLength = length;
      if (req.method == 'HEAD' || length == 0) {
        await res.close();
        return;
      }
      final f = await sftp.open(path);
      try {
        // Small, bounded read-ahead: ExoPlayer opens and drops ranges a lot, and
        // each stream should hold at most ~512 KB in flight.
        await res.addStream(f.read(offset: start, length: length, chunkSize: 32 * 1024, maxPendingRequests: 16));
      } finally {
        await f.close();
      }
      await res.close();
    } on SftpStatusError {
      res.statusCode = HttpStatus.notFound;
      await res.close().catchError((_) {});
    } catch (_) {
      // Client hung up mid-stream (seeking) — normal for media players.
      try {
        await res.close();
      } catch (_) {}
    }
  }
}

const _mime = {
  'html': 'text/html; charset=utf-8',
  'htm': 'text/html; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'js': 'application/javascript; charset=utf-8',
  'mjs': 'application/javascript; charset=utf-8',
  'json': 'application/json; charset=utf-8',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'ico': 'image/x-icon',
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'mov': 'video/quicktime',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/ogg',
  'flac': 'audio/flac',
  'pdf': 'application/pdf',
  'txt': 'text/plain; charset=utf-8',
  'md': 'text/markdown; charset=utf-8',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'ttf': 'font/ttf',
};

String extOf(String path) {
  final name = path.split('/').last;
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
}

String mimeFor(String path) => _mime[extOf(path)] ?? 'application/octet-stream';

enum FileKind { text, markdown, html, image, video, audio, other }

const _textExt = {
  'txt', 'log', 'conf', 'cfg', 'ini', 'env', 'sh', 'bash', 'zsh', 'py', 'js', 'mjs', 'ts', 'tsx', 'jsx',
  'json', 'yaml', 'yml', 'toml', 'xml', 'css', 'scss', 'dart', 'go', 'rs', 'c', 'h', 'cpp', 'java', 'kt',
  'php', 'rb', 'sql', 'csv', 'service', 'gitignore', 'dockerfile', 'lock', 'properties', 'gradle', 'vue', 'svelte',
};

FileKind kindOf(String path) {
  final e = extOf(path);
  final name = path.split('/').last.toLowerCase();
  if (e == 'md' || e == 'markdown') return FileKind.markdown;
  if (e == 'html' || e == 'htm') return FileKind.html;
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'ico', 'bmp'}.contains(e)) return FileKind.image;
  if (const {'mp4', 'm4v', 'webm', 'mkv', 'mov', '3gp'}.contains(e)) return FileKind.video;
  if (const {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'}.contains(e)) return FileKind.audio;
  if (_textExt.contains(e) || e.isEmpty || name.startsWith('.') || name == 'makefile' || name == 'dockerfile') {
    return FileKind.text;
  }
  return FileKind.other;
}
