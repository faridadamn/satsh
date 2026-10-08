import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Images the agent sees: browser screenshots, photos the user attaches,
/// image files it opens. Stored as small JPEGs on disk; messages keep paths.
class Vision {
  Vision._();
  static const _ch = MethodChannel('satsh/native');
  static const _zoneKey = #satshToolImages;

  /// For tests / desktop.
  static String? dirOverride;
  static Directory? _dir;

  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final d = Directory(dirOverride ?? '${(await getApplicationDocumentsDirectory()).path}/agent/shots');
    await d.create(recursive: true);
    unawaited(_prune(d));
    return _dir = d;
  }

  /// Keep the folder from growing forever: newest 300 stay.
  static Future<void> _prune(Directory d) async {
    try {
      final files = d.listSync().whereType<File>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in files.skip(300)) {
        await f.delete();
      }
    } catch (_) {}
  }

  static Future<String> save(Uint8List jpeg, String tag) async {
    final d = await dir();
    final f = File('${d.path}/${DateTime.now().millisecondsSinceEpoch}_$tag.jpg');
    await f.writeAsBytes(jpeg);
    return f.path;
  }

  /// Shrinks any image (file path or bytes) to a JPEG ≤ [maxW] px wide.
  static Future<({Uint8List bytes, int w, int h})> jpeg({String? path, Uint8List? bytes, int maxW = 1280, int q = 75}) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('jpeg', {'path': path, 'bytes': bytes, 'maxW': maxW, 'q': q});
    return (bytes: r!['bytes'] as Uint8List, w: r['w'] as int, h: r['h'] as int);
  }

  /// Screenshot of the agent browser's WebView.
  static Future<({Uint8List bytes, int w, int h, int vw, int vh})> webshot(int id, {int maxW = 900, int q = 70}) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('webshot', {'id': id, 'maxW': maxW, 'q': q});
    return (bytes: r!['bytes'] as Uint8List, w: r['w'] as int, h: r['h'] as int, vw: r['vw'] as int, vh: r['vh'] as int);
  }

  /// Base64 of a stored image, or null if it's gone.
  static String? b64(String path) {
    try {
      return base64Encode(File(path).readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------- tool → message
  /// A tool calls this to hand an image to the model with its result.
  static void attach(String path) {
    final l = Zone.current[_zoneKey];
    if (l is List<String>) l.add(path);
  }

  /// Runs a tool and collects any images it attached.
  static Future<(String, List<String>)> collect(Future<String> Function() f) async {
    final imgs = <String>[];
    final out = await runZoned(f, zoneValues: {_zoneKey: imgs});
    return (out, imgs);
  }
}
