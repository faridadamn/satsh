// Mode Server end-to-end: real satshd (host build) + local OpenSSH as "VPS".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/models.dart';
import 'package:satsh/phone_server.dart';
import 'package:satsh/ssh_manager.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ssh_integration_test.dart' show FakePrompts, waitFor, screen;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final srv = PhoneServer.i;
  late Directory tmp;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    SshManager.i.prompts = FakePrompts();
    tmp = await Directory.systemTemp.createTemp('srv');
    PhoneServer.binaryOverride = '/tmp/satshd-x86';
    PhoneServer.dirOverride = tmp.path;
    PhoneServer.shellOverride = '/bin/sh';
    Store.i.set('srvPort', 22099);
    Store.i.set('srvName', 'hp-test');
  });

  tearDownAll(() async {
    await srv.stop();
  });

  test('server starts and reports fingerprint', () async {
    await srv.start();
    expect(srv.error, isNull);
    expect(srv.running, isTrue);
    expect(srv.fingerprint, startsWith('SHA256:'));
  });

  late Host direct;
  test('pair directly, then terminal + sftp with the new key', () async {
    final code = PairCode.parse(await srv.startPairing())!;
    expect(code.name, 'hp-test');
    expect(code.relay, isNull);
    final steps = <String>[];
    final r = await PairClient.pair(code, deviceName: 'Pixel 9', progress: steps.add);
    direct = r.host;
    expect(r.route, startsWith('langsung'));
    expect(direct.auth, 'key');
    await waitFor(() => srv.paired.length == 1);
    expect(srv.paired.first.name, 'Pixel_9');
    // token is one-time
    await expectLater(PairClient.pair(code), throwsA(contains('kadaluarsa')));

    final s = SshManager.i.openTerminal(direct);
    await waitFor(() => s.state == ConnState.ready);
    s.runCommand('echo PHONE_\$((40+2))');
    await waitFor(() => screen(s).contains('PHONE_42'));
    final sftp = await SshManager.i.sftp(direct);
    final names = (await sftp.listdir('.')).map((e) => e.filename).toList();
    expect(names, contains('storage'));
    await SshManager.i.closeSession(s);
  });

  test('relay through VPS + pairing via jump host', () async {
    final vps = Host(id: 'vps', label: 'VPS', host: '127.0.0.1', port: 2222, username: 'tester');
    await Store.i.saveHost(vps, password: 'rahasia123');
    await srv.setConfig(relayHostId: 'vps', relayPort: 22777);
    await waitFor(() => srv.relayStatus == 'on' || srv.relayStatus == 'error');
    expect(srv.relayError, isNull);

    final raw = await srv.startPairing();
    final code = PairCode.parse(raw)!;
    expect(code.relay?['p'], 22777);
    code.raw['a'] = <String>[]; // pretend we're on a different network
    final r = await PairClient.pair(code, deviceName: 'hp-jauh');
    expect(r.route, contains('VPS'));
    expect(r.host.via, 'vps');
    expect(r.host.host, '127.0.0.1');
    expect(r.host.port, 22777);

    final s = SshManager.i.openTerminal(r.host);
    await waitFor(() => s.state == ConnState.ready);
    s.runCommand('echo VIA_RELAY_OK');
    await waitFor(() => screen(s).contains('VIA_RELAY_OK'));
    expect(srv.relayConnections, greaterThan(0));
    await SshManager.i.closeSession(s);
    // VPS stays pinned by the relay
    expect(SshManager.i.isConnected('vps'), isTrue);
  });

  test('revoked device can no longer log in', () async {
    final k = srv.paired.firstWhere((k) => k.name == 'Pixel_9');
    await srv.revoke(k);
    SshManager.i.disconnect(direct.id);
    await expectLater(SshManager.i.client(direct), throwsA(anything));
  });

  test('pair code survives round trip, rejects junk', () {
    expect(PairCode.parse('halo'), isNull);
    expect(PairCode.parse('satsh://pair/!!!'), isNull);
    final enc = base64Url.encode(utf8.encode(jsonEncode({'t': 'abcdefgh12', 'n': 'x', 'p': 1}))).replaceAll('=', '');
    expect(PairCode.parse('cek ini satsh://pair/$enc ya')!.token, 'abcdefgh12');
  });

  test('stop kills server and relay', () async {
    await srv.stop();
    expect(srv.running, isFalse);
    expect(srv.relayStatus, '');
    await expectLater(Socket.connect('127.0.0.1', 22099), throwsA(isA<SocketException>()));
  });
}
