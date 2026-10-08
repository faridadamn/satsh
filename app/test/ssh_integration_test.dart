// Integration test against a local OpenSSH server on 127.0.0.1:2222.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/markas.dart';
import 'package:satsh/models.dart';
import 'package:satsh/ssh_manager.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePrompts implements Prompts {
  List<String?> passwords = [];
  int pwAsked = 0;
  int trustAsked = 0;
  String? lastOld;
  bool trust = true;

  @override
  Future<String?> askPassword(Host h, {String? reason}) async {
    pwAsked++;
    return passwords.isEmpty ? null : passwords.removeAt(0);
  }

  @override
  Future<bool> trustHostKey(Host h, String type, String fp, String? oldFp) async {
    trustAsked++;
    lastOld = oldFp;
    return trust;
  }
}

Future<void> waitFor(bool Function() cond, {int ms = 15000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) throw 'timeout';
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

String screen(TermSession s) => s.terminal.buffer.getText();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePrompts p;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    p = FakePrompts();
    SshManager.i.prompts = p;
  });

  final pwHost = Host(id: 'h1', label: 'local', host: '127.0.0.1', port: 2222, username: 'tester', startup: 'echo STARTUP_OK');

  test('password login, host-key TOFU, shell + startup + ctrl key', () async {
    await Store.i.saveHost(pwHost, password: 'rahasia123');
    final s = SshManager.i.openTerminal(pwHost);
    await waitFor(() => s.state == ConnState.ready);
    expect(p.trustAsked, 1);
    s.runCommand('echo hi_\$((1+2))');
    await waitFor(() => screen(s).contains('hi_3'));
    await waitFor(() => screen(s).contains('STARTUP_OK'));
    // sticky CTRL + c should interrupt sleep
    s.runCommand('sleep 30; echo NOPE');
    await Future.delayed(const Duration(milliseconds: 300));
    s.ctrl = true;
    s.sendInput('c');
    s.runCommand('echo AFTER_INT');
    await waitFor(() => screen(s).contains('AFTER_INT'), ms: 5000);
    expect(RegExp(r'^NOPE\s*\$', multiLine: true).hasMatch(screen(s)), isFalse);
    // second session reuses the connection — no new trust prompt
    final s2 = SshManager.i.openTerminal(pwHost);
    await waitFor(() => s2.state == ConnState.ready);
    expect(p.trustAsked, 1);
    await SshManager.i.closeSession(s2);
    await SshManager.i.closeSession(s);
  });

  test('sftp upload / list / download', () async {
    final sftp = await SshManager.i.sftp(pwHost);
    final home = await sftp.absolute('.');
    final data = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    final f = await sftp.open('$home/up.bin',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    await f.write(Stream.value(data));
    await f.close();
    final names = (await sftp.listdir(home)).map((e) => e.filename);
    expect(names, contains('up.bin'));
    final r = await sftp.open('$home/up.bin');
    final b = BytesBuilder();
    await for (final c in r.read()) {
      b.add(c);
    }
    expect(b.takeBytes(), data);
    await sftp.mkdir('$home/newdir');
    await sftp.rename('$home/up.bin', '$home/newdir/up2.bin');
    await sftp.remove('$home/newdir/up2.bin');
    await sftp.rmdir('$home/newdir');
    sftp.close();
  });

  test('local port forward to remote http server', () async {
    final fw = Forward(id: 'f1', label: 'web', hostId: 'h1', localPort: 18080, remotePort: 9876);
    Store.i.saveForward(fw);
    await SshManager.i.startForward(fw);
    for (var i = 0; i < 3; i++) {
      final sock = await Socket.connect('127.0.0.1', 18080);
      sock.write('GET / HTTP/1.0\r\nHost: x\r\n\r\n');
      final resp = await utf8.decoder.bind(sock).join();
      expect(resp, startsWith('HTTP/1.0 200'));
    }
    await waitFor(() => SshManager.i.forwards['f1']!.connections == 0, ms: 3000);
    expect(SshManager.i.forwards['f1']!.bytes, greaterThan(100));
    await SshManager.i.stopForward('f1');
    expect(SshManager.i.forwards.containsKey('f1'), isFalse);
  });

  test('key login with passphrase', () async {
    SshManager.i.disconnect('h1');
    final pem = File('/tmp/claude-0/testkey').readAsStringSync();
    final kh = Host(id: 'h2', label: 'key', host: '127.0.0.1', port: 2222, username: 'tester', auth: 'key');
    await Store.i.saveHost(kh, key: pem, passphrase: 'pp123');
    final s = SshManager.i.openTerminal(kh);
    await waitFor(() => s.state == ConnState.ready || s.state == ConnState.failed);
    expect(s.state, ConnState.ready, reason: s.error);
    s.runCommand('whoami');
    await waitFor(() => screen(s).contains('tester'));
    await SshManager.i.closeSession(s);
  });

  test('wrong password -> re-prompt -> cancel = failed', () async {
    final bad = Host(id: 'h3', label: 'bad', host: '127.0.0.1', port: 2222, username: 'tester');
    await Store.i.saveHost(bad, password: 'salah');
    p.pwAsked = 0;
    p.passwords = ['masih salah', 'rahasia123'];
    final s = SshManager.i.openTerminal(bad);
    await waitFor(() => s.state == ConnState.ready || s.state == ConnState.failed, ms: 30000);
    expect(s.state, ConnState.ready, reason: s.error);
    expect(p.pwAsked, 2);
    expect(await Store.i.password('h3'), 'rahasia123'); // fixed password got saved
    await SshManager.i.closeSession(s);
    // cancel path
    await Store.i.saveHost(bad, password: 'salah');
    p.passwords = [null];
    final s2 = SshManager.i.openTerminal(bad);
    await waitFor(() => s2.state == ConnState.failed, ms: 30000);
    // ignore: avoid_print
    print('cancel error: ${s2.error}');
    await SshManager.i.closeSession(s2);
    // ignore: avoid_print
    print('error shown: ${s.error}');
    await SshManager.i.closeSession(s);
  });

  test('changed host key is flagged', () async {
    Store.i.trustHostKey('127.0.0.1:2222', 'ssh-ed25519 SHA256:fake');
    p.trust = false;
    final s = SshManager.i.openTerminal(pwHost);
    await waitFor(() => s.state == ConnState.failed);
    expect(p.lastOld, 'ssh-ed25519 SHA256:fake');
    // ignore: avoid_print
    print('error shown: ${s.error}');
  });

  test('unreachable port gives friendly error', () async {
    final h = Host(id: 'h4', label: 'x', host: '127.0.0.1', port: 2299, username: 'tester');
    await Store.i.saveHost(h, password: 'x');
    final s = SshManager.i.openTerminal(h);
    await waitFor(() => s.state == ConnState.failed);
    // ignore: avoid_print
    print('error shown: ${s.error}');
    expect(s.error, contains('ditolak'));
  });

  test('Markas: install over SFTP, then talk to it + Hermes', () async {
    p.trust = true;
    await Store.i.saveHost(pwHost, password: 'rahasia123');
    final out = await Markas.i.install(pwHost, load: (n) async => File('../markas/$n').readAsString());
    expect(out, contains('MARKAS_OK'));
    expect(Markas.i.hostId, pwHost.id);
    await Markas.i.run(['target', 'add', 'Tes dari HP', '--owner', 'satsh']);
    await Markas.i.refresh();
    expect(Markas.i.error, isNull);
    expect((Markas.i.snap!['targets'] as List).map((t) => (t as Map)['title']), contains('Tes dari HP'));
    if (out.contains('HERMES_CLI_OK')) expect(await Markas.i.askHermes('progress?'), contains('HERMES'));
  });
}
