import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Streams a remote file to disk instead of collecting it in RAM.
///
/// The old download read the whole file into a BytesBuilder and then pushed
/// it through FilePicker.saveFile(bytes:) — i.e. the file sat in memory twice
/// and crossed the platform channel in one message, so anything big failed or
/// killed the app. Now chunks go straight into a `.part` file (with
/// backpressure) that is renamed when complete.
class SftpDownload {
  SftpDownload._();

  /// Asked once per app run: on Android 11+ the request opens system Settings,
  /// so asking on every download after a "no" would be a nag.
  static bool _asked = false;

  /// Public Download/satsh on the phone, or null when we can't write there.
  static Future<Directory?> publicDir({bool ask = true}) async {
    if (!Platform.isAndroid) return null;
    try {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final perm = sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
      var st = await perm.status;
      if (!st.isGranted && ask && !_asked) {
        _asked = true;
        st = await perm.request();
      }
      if (!st.isGranted) return null;
      final d = Directory('/storage/emulated/0/Download/satsh');
      await d.create(recursive: true);
      return d;
    } catch (_) {
      return null;
    }
  }

  /// App-private fallback (no permission needed); the caller can share it.
  static Future<Directory> privateDir() async {
    final base = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final d = Directory('${(base ?? await getApplicationDocumentsDirectory()).path}/Download');
    await d.create(recursive: true);
    // These only exist to be handed to the share sheet: drop day-old ones.
    final old = DateTime.now().subtract(const Duration(days: 1));
    for (final e in d.listSync().whereType<File>()) {
      try {
        if (e.lastModifiedSync().isBefore(old)) e.deleteSync();
      } catch (_) {}
    }
    return d;
  }

  /// `name`, `name (1)`, `name (2)`… — never overwrite an existing file.
  static File freeName(Directory dir, String name) {
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'download';
    var f = File('${dir.path}/$name');
    final dot = name.lastIndexOf('.');
    for (var k = 1; f.existsSync() || File('${f.path}.part').existsSync(); k++) {
      f = File('${dir.path}/${dot > 0 ? '${name.substring(0, dot)} ($k)${name.substring(dot)}' : '$name ($k)'}');
    }
    return f;
  }

  /// Downloads [remotePath] into [dest]. [onProgress] gets bytes so far and is
  /// throttled to ~10 calls a second. Completes [cancel] to abort; the partial
  /// file is removed on error/cancel.
  static Future<File> fetch(
    SftpClient sftp,
    String remotePath,
    File dest, {
    void Function(int done)? onProgress,
    Future<void>? cancel,
  }) async {
    final part = File('${dest.path}.part');
    final rf = await sftp.open(remotePath);
    final sink = part.openWrite();
    var done = 0;
    var lastTick = DateTime.fromMillisecondsSinceEpoch(0);
    var cancelled = false;
    cancel?.then((_) => cancelled = true);
    try {
      // addStream pauses the SFTP read whenever the disk falls behind, and
      // takeWhile drops the subscription (stopping the reads) on cancel.
      await sink.addStream(rf
          .read(chunkSize: 32 * 1024, maxPendingRequests: 32)
          .takeWhile((_) => !cancelled)
          .map((chunk) {
        done += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastTick).inMilliseconds >= 100) {
          lastTick = now;
          onProgress?.call(done);
        }
        return chunk;
      }));
      await sink.close();
      if (cancelled) throw 'Dibatalin';
      onProgress?.call(done);
      return await part.rename(dest.path);
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (part.existsSync()) await part.delete();
      rethrow;
    } finally {
      await rf.close().catchError((_) {});
    }
  }
}
