// Repro for "video > 10 MB force-closes" + "download doesn't work":
// real satshd over SFTP, MediaServer serving a big file the way ExoPlayer
// reads it (open-ended range, abort, seek to the tail, read on).
// Measures event-loop stalls (= UI freezes on Android, where Dart runs on the
// platform thread) and peak RSS.
import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/media_server.dart';
import 'package:satsh/phone_server.dart';
import 'package:satsh/sftp_download.dart';
import 'package:satsh/ssh_manager.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ssh_integration_test.dart' show FakePrompts, waitFor;

class LoopProbe {
  final _sw = Stopwatch()..start();
  Timer? _t;
  int maxLagMs = 0;
  int peakRss = 0;
  int _last = 0;
  void start() {
    _last = _sw.elapsedMilliseconds;
    _t = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = _sw.elapsedMilliseconds;
      final lag = now - _last - 10;
      if (lag > maxLagMs) maxLagMs = lag;
      _last = now;
      final r = ProcessInfo.currentRss;
      if (r > peakRss) peakRss = r;
    });
  }

  void stop() => _t?.cancel();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late File big;
  const size = 60 * 1024 * 1024;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    SshManager.i.prompts = FakePrompts();
    tmp = await Directory.systemTemp.createTemp('media');
    PhoneServer.binaryOverride = '/tmp/satshd-x86';
    PhoneServer.dirOverride = tmp.path;
    PhoneServer.shellOverride = '/bin/sh';
    Store.i.set('srvPort', 22111);
    await PhoneServer.i.start();
  });

  tearDownAll(() async => PhoneServer.i.stop());

  test('ExoPlayer-like reads of a 60 MB video', () async {
    final code = PairCode.parse(await PhoneServer.i.startPairing())!;
    final host = (await PairClient.pair(code, deviceName: 'tester')).host;
    final sftp = await SshManager.i.sftp(host);
    final home = await sftp.absolute('.');
    big = File('$home/big.mp4');
    final raf = big.openSync(mode: FileMode.write);
    raf.setPositionSync(size - 1);
    raf.writeByteSync(1);
    raf.closeSync();

    final probe = LoopProbe()..start();
    final base = await MediaServer.i.mount(sftp);
    final url = Uri.parse(MediaServer.urlFor(base, big.path));
    final http = HttpClient();
    final rss0 = ProcessInfo.currentRss;
    final sw = Stopwatch()..start();

    Future<int> get(String range, {int? stopAfter}) async {
      final rq = await http.getUrl(url);
      rq.headers.set('Range', range);
      final rs = await rq.close();
      var got = 0;
      final done = Completer<int>();
      late StreamSubscription sub;
      sub = rs.listen((d) {
        got += d.length;
        if (stopAfter != null && got >= stopAfter) {
          sub.cancel();
          rs.detachSocket().then((s) => s.destroy()).catchError((_) {});
          if (!done.isCompleted) done.complete(got);
        }
      }, onDone: () => done.isCompleted ? null : done.complete(got), onError: (_) {
        if (!done.isCompleted) done.complete(got);
      });
      return done.future;
    }

    // ExoPlayer: open-ended from 0, bails after the header, jumps to the tail
    // (moov atom), then streams the body, plus a couple of seeks.
    Future<int> step(String r, {int? stopAfter}) async {
      probe.maxLagMs = 0;
      final t = sw.elapsedMilliseconds;
      final n = await get(r, stopAfter: stopAfter);
      // ignore: avoid_print
      print('  $r stop=$stopAfter -> $n B in ${sw.elapsedMilliseconds - t} ms, stall ${probe.maxLagMs} ms');
      return n;
    }
    await step('bytes=0-', stopAfter: 1 << 20);
    await step('bytes=${size - 2 * 1024 * 1024}-');
    await step('bytes=0-', stopAfter: 20 << 20);
    await step('bytes=${size ~/ 2}-', stopAfter: 10 << 20);
    final tail = await step('bytes=${size - 4096}-');
    expect(tail, 4096);
    final mediaStall = probe.maxLagMs;

    // Download the whole thing to disk.
    probe.maxLagMs = 0;
    final t1 = sw.elapsedMilliseconds;
    final out = await SftpDownload.fetch(sftp, big.path, SftpDownload.freeName(tmp, 'copy.mp4'));
    expect(out.lengthSync(), size);
    expect(File('${out.path}.part').existsSync(), isFalse);
    // ignore: avoid_print
    print('  download 60 MB: ${sw.elapsedMilliseconds - t1} ms, stall ${probe.maxLagMs} ms');
    expect(probe.maxLagMs, lessThan(1000), reason: 'download must not freeze the UI');
    expect(mediaStall, lessThan(1000), reason: 'media must not freeze the UI');

    // Cancel mid-way leaves nothing behind.
    final cancel = Completer<void>();
    final f2 = SftpDownload.freeName(tmp, 'copy.mp4');
    expect(f2.path, endsWith('copy (1).mp4'));
    final fut = SftpDownload.fetch(sftp, big.path, f2, cancel: cancel.future, onProgress: (n) {
      if (n > (5 << 20) && !cancel.isCompleted) cancel.complete();
    });
    await expectLater(fut, throwsA('Dibatalin'));
    expect(f2.existsSync() || File('${f2.path}.part').existsSync(), isFalse);
    probe.stop();
    // ignore: avoid_print
    print('media: ${sw.elapsedMilliseconds} ms, max loop stall ${probe.maxLagMs} ms, '
        'rss +${(probe.peakRss - rss0) >> 20} MB');
    MediaServer.i.unmount(base);
    http.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('terminal survives a 400k-line flood', () async {
    final code = PairCode.parse(await PhoneServer.i.startPairing())!;
    final host = (await PairClient.pair(code, deviceName: 'flood')).host;
    final s = SshManager.i.openTerminal(host);
    await waitFor(() => s.state == ConnState.ready);
    final probe = LoopProbe()..start();
    final sw = Stopwatch()..start();
    s.runCommand('seq 1 400000; echo FLOOD_\$((6*7))');
    // Last lines only (getText over 10k lines each poll is itself slow).
    String tail() {
      final b = s.terminal.buffer;
      final n = b.lines.length;
      return [for (var i = n > 40 ? n - 40 : 0; i < n; i++) b.lines[i].toString()].join('\n');
    }
    await waitFor(() => tail().contains('FLOOD_42'), ms: 120000);
    probe.stop();
    // ignore: avoid_print
    print('  terminal flood: ${sw.elapsedMilliseconds} ms, stall ${probe.maxLagMs} ms, '
        'scrollback ${s.terminal.buffer.lines.length}');
    expect(tail(), contains('400000'));
    expect(probe.maxLagMs, lessThan(1000));
    await SshManager.i.closeSession(s);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
