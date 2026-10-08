// Cross-platform zip check against satsh desktop. Runs only when the files exist:
//   python desktop/tests/test_profiles.py export /home/claude/interop/from_windows.zip
//   flutter test test/interop_test.dart   → writes from_android.zip
//   python desktop/tests/test_profiles.py import /home/claude/interop/from_android.zip
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent_zip.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dir = String.fromEnvironment('INTEROP', defaultValue: '/home/claude/interop');

Future<Brain> fresh() async {
  Brain.rootOverride = Directory.systemTemp.createTempSync('brain').path;
  await Brain.i.load();
  return Brain.i;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
  });

  test('imports a zip made by satsh desktop', () async {
    final f = File('$dir/from_windows.zip');
    if (!f.existsSync()) return markTestSkipped('no desktop zip');
    final b = await fresh();
    final summary = await AgentZip.import(b, await f.readAsBytes());
    expect(summary, contains('dari windows'));
    final v = await b.view('payu');
    expect(v.soul, '# soul payu');
    expect(v.skill('deploy-payu'), isNotNull);
    expect(b.entries('user'), contains('Adam driver ojol'));
    final m = b.sessions.firstWhere((m) => m.title == 'chat payu');
    final s = await b.openSession(m.id);
    expect(s!.profile, 'payu');
    expect(s.messages.first.text, 'halo');
    expect(b.jobs.single.enabled, isFalse);
    expect(b.jobs.single.nextRun(), isNotNull);
  });

  test('writes a zip for satsh desktop', () async {
    if (!Directory(dir).existsSync()) return markTestSkipped('no interop dir');
    final b = await fresh();
    await b.memoryOp('add', 'user', content: 'Adam driver ojol');
    final p = await b.createProfile('Payu', emoji: '💼', copyFrom: 'default');
    final v = await b.view(p.id);
    await v.saveSoul('# soul payu');
    await v.saveSkill('---\nname: deploy-payu\ndescription: deploy payu\n---\nlangkah');
    await b.saveSession(AgentSession(id: newId(), title: 'chat payu', messages: [Msg(role: 'user', text: 'halo')])..profile = p.id);
    b.jobs.add(CronJob(id: 'jobandroid1', name: 'cek', prompt: 'cek server', dailyAt: '07:30', profile: p.id));
    await b.saveJobs();
    await File('$dir/from_android.zip').writeAsBytes(await AgentZip.export(b, sessions: true, jobs: true));
  });
}
