import 'dart:io';

/// Serves one folder on the phone over http://127.0.0.1 so the agent browser
/// can open (and screenshot) web pages the agent just built.
class PreviewServer {
  PreviewServer._();
  static final PreviewServer i = PreviewServer._();

  HttpServer? _srv;
  Directory? _root;

  static const _types = {
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
    'webp': 'image/webp',
    'gif': 'image/gif',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'txt': 'text/plain; charset=utf-8',
    'md': 'text/markdown; charset=utf-8',
  };

  /// Serves [dir]; returns the base URL (ends with "/").
  Future<String> serve(Directory dir) async {
    _root = Directory(dir.absolute.path);
    final s = _srv ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen(_handle);
    return 'http://127.0.0.1:${s.port}/';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final root = _root;
      if (root == null) throw const FileSystemException('belum ada folder');
      var rel = Uri.decodeComponent(req.uri.path);
      if (rel.endsWith('/')) rel = '${rel}index.html';
      final segs = rel.split('/').where((e) => e.isNotEmpty && e != '.').toList();
      if (segs.contains('..')) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      var f = File([root.path, ...segs].join('/'));
      if (await FileSystemEntity.isDirectory(f.path)) f = File('${f.path}/index.html');
      if (!await f.exists()) {
        res.statusCode = HttpStatus.notFound;
        res.write('404: ${segs.join('/')}');
        return;
      }
      final ext = f.path.split('.').last.toLowerCase();
      res.headers
        ..set(HttpHeaders.contentTypeHeader, _types[ext] ?? 'application/octet-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      await res.addStream(f.openRead());
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      res.write('$e');
    } finally {
      await res.close();
    }
  }

  Future<void> stop() async {
    await _srv?.close(force: true);
    _srv = null;
  }
}
