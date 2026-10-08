// Markas: runs the real markas.py locally through Markas.execOverride (no SSH needed).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/tools.dart';
import 'package:satsh/error_log.dart';
import 'package:satsh/markas.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final home = Directory.systemTemp.createTempSync('markas').path;
  final py = File('../markas/markas.py').absolute.path;
  final cmds = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    Brain.rootOverride = Directory.systemTemp.createTempSync('mbrain').path;
    ErrorLog.dirOverride = Directory.systemTemp.createTempSync('mlog').path;
    await AgentController.i.load();
    Markas.execOverride = (cmd, t) async {
      cmds.add(cmd);
      if (cmd.contains('hermes -z')) return (0, 'Target #1 udah 40%, kendala: belum ada domain.\n', '');
      final r = await Process.run('sh', ['-c', cmd.replaceAll(Markas.cli, 'python3 ${Markas.q(py)}')],
          environment: {'MARKAS_HOME': home}, stdoutEncoding: utf8, stderrEncoding: utf8);
      return (r.exitCode, '${r.stdout}', '${r.stderr}');
    };
    expect((await Process.run('python3', [py, 'init'], environment: {'MARKAS_HOME': home})).exitCode, 0);
  });

  AgentTool tool(String n) => AgentController.i.brainTools(RunCtx()).firstWhere((t) => t.spec.name == n);

  test('Markas.run quotes args safely', () async {
    await Markas.i.run(['target', 'add', "Launch Payu'; rm -rf / #", '--owner', 'hermes', '--metric', '10 user bayar']);
    final s = await Markas.i.status();
    final t = (s['targets'] as List).first as Map;
    expect(t['title'], "Launch Payu'; rm -rf / #");
    expect(t['owner'], 'hermes');
  });

  test('markas tool: agent writes as its own profile name', () async {
    final m = tool('markas');
    expect(m.group, 'markas');
    final brief = await m.run({'action': 'brief'});
    expect(brief, contains('Launch Payu'));
    await m.run({'action': 'target_update', 'id': 1, 'progress': 40, 'note': 'landing page jadi'});
    await m.run({'action': 'log', 'text': 'deploy staging', 'target': 1});
    await m.run({'action': 'say', 'text': 'rapat beres', 'to': 'adam'});
    final s = await Markas.i.status();
    final t = (s['targets'] as List).first as Map;
    expect(t['progress'], 40);
    expect(jsonEncode(s), contains('deploy staging'));
    final chat = await Markas.i.run(['read']);
    expect(chat, contains('satsh'));
    expect(chat, contains('rapat beres'));
    expect(await Markas.i.run(['inbox', '--for', 'adam']), contains('rapat beres'));
    await expectLater(m.run({'action': 'target_update'}), throwsA('id wajib'));
  });

  test('tanya_agent: hermes via CLI, muse via phone steps', () async {
    final a = tool('tanya_agent');
    final h = await a.run({'agent': 'hermes', 'message': 'progress target #1?'});
    expect(h, contains('40%'));
    expect(cmds.last, contains('hermes -z'));
    expect(cmds.last, contains('</dev/null'));
    final mu = await a.run({'agent': 'muse', 'message': 'ide konten minggu ini?'});
    expect(mu, contains('phone_open_app'));
    expect(mu, contains('ide konten minggu ini?'));
  });

  test('refresh fills snapshot; bad command gives friendly error', () async {
    await Markas.i.refresh();
    expect(Markas.i.error, isNull);
    expect((Markas.i.snap!['members'] as List).map((m) => (m as Map)['name']), containsAll(['adam', 'hermes', 'muse', 'agy']));
    await expectLater(Markas.i.run(['target', 'update', '999', '--progress', '5']), throwsA(isA<String>()));
  });

  test('rapat prompt mentions every step', () {
    for (final w in ['brief', 'tanya_agent', 'muse', 'target_update', 'say']) {
      expect(Markas.rapatPrompt, contains(w));
    }
  });
}
