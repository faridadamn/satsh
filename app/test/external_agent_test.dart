// External agent (agy stream-json over SSH) against local OpenSSH + fake agy.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/external.dart';
import 'package:satsh/agent/providers.dart';
import 'package:satsh/models.dart';
import 'package:satsh/ssh_manager.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ssh_integration_test.dart' show FakePrompts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final a = AgentController.i;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    SshManager.i.prompts = FakePrompts();
    await Store.i.saveHost(Host(id: 'tmx', label: 'Termux', host: '127.0.0.1', port: 2222, username: 'tester'),
        password: 'rahasia123');
    Providers.saveAll([
      ProviderCfg(id: 'ag', kind: 'external', name: 'Antigravity', base: 'tmx', model: ExternalAgent.defaultCommand),
    ]);
    Brain.rootOverride = (await Directory.systemTemp.createTemp('brain')).path;
    await a.load();
  });

  test('quoting survives shell', () {
    final c = ExternalAgent.buildCommand(ExternalAgent.defaultCommand, "it's \$HOME `x`", null);
    expect(c, startsWith("bash -lc '"));
    expect(c, isNot(contains('{resume}')));
  });

  test('streams answer, keeps conversation id, resumes next turn', () async {
    a.newChat();
    await a.send('halo "bre" it\'s \$HOME');
    final asst = a.messages.where((m) => m.role == 'assistant' && m.text.isNotEmpty).toList();
    expect(asst, hasLength(1), reason: a.messages.map((m) => '${m.role}:${m.text}').join('\n'));
    expect(asst.first.text, contains('Halo bre!'));
    expect(asst.first.text, contains('echo=halo "bre" it\'s \$HOME'));
    expect(asst.first.isError, isFalse);
    expect(a.session.ext['ag'], 'a44ebd4e-0000-4739-acb1-f6ad6d7703c7');

    await a.send('lanjut');
    final last = a.messages.lastWhere((m) => m.role == 'assistant');
    expect(last.text, contains('[lanjut a44ebd4e-0000-4739-acb1-f6ad6d7703c7]'));
  });

  test('tool steps become chips with results', () async {
    a.newChat();
    await a.send('pakai tool dong');
    final call = a.messages.where((m) => m.calls.isNotEmpty).single.calls.single;
    expect(call.name, 'run_command');
    expect(call.args['command'], 'ls ~');
    final res = a.messages.singleWhere((m) => m.role == 'tool');
    expect(res.callId, call.id);
    expect(res.text, contains('payu'));
  });

  test('hops into proot distro when outside it, prompt quoting intact', () async {
    final l = Providers.all();
    l.first.distro = 'ubuntu';
    Providers.saveAll(l);
    a.newChat();
    await a.send('it\'s "dobel" \$HOME');
    final t = a.messages.lastWhere((m) => m.role == 'assistant').text;
    expect(t, contains('[proot:ubuntu]'));
    expect(t, contains('echo=it\'s "dobel" \$HOME'));
    l.first.distro = '';
    Providers.saveAll(l);
    a.newChat();
    await a.send('tanpa proot');
    expect(a.messages.lastWhere((m) => m.role == 'assistant').text, isNot(contains('[proot')));
  });

  test('missing command gives a friendly error', () async {
    final l = Providers.all();
    l.first.model = 'agy-ga-ada --output-format stream-json -p {prompt}';
    Providers.saveAll(l);
    a.newChat();
    await a.send('halo');
    final err = a.messages.last;
    expect(err.isError, isTrue);
    expect(err.text, contains('ga ketemu'));
  });
}
