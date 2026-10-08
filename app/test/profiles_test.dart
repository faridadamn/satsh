// Multi-profile brain, portable agent zip, copyable answer blocks.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/agent_zip.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/md_blocks.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('md blocks', () {
    test('prose, code and quotes come apart', () {
      final b = splitBlocks('Cek ini:\n\n```bash\ndf -h\nfree -m\n```\n\n> kata orang\n> bijak\n\nSelesai.');
      expect(b.map((e) => e.kind).toList(), ['text', 'code', 'quote', 'text']);
      expect(b[1].lang, 'bash');
      expect(b[1].text, 'df -h\nfree -m');
      expect(b[2].text, 'kata orang\nbijak');
    });

    test('unclosed fence (still streaming) and tilde fences', () {
      expect(splitBlocks('```py\nprint(1)').single.text, 'print(1)');
      final t = splitBlocks('~~~\na ``` b\n~~~\nx');
      expect(t.first.text, 'a ``` b');
      expect(t.last.text, 'x');
    });
  });

  group('profiles', () {
    test('default keeps the old folder layout; new profiles get their own brain', () async {
      final b = await fresh();
      expect(b.activeId, 'default');
      expect(File('${b.root.path}/SOUL.md').existsSync(), isTrue);
      await b.memoryOp('add', 'memory', content: 'server utama: vps-jkt');
      await b.memoryOp('add', 'user', content: 'Adam suka jawaban singkat');

      final p = await b.createProfile('Payu Ops', emoji: '💼', copyFrom: 'default');
      expect(p.id, 'payu-ops');
      await b.setActive(p.id);
      expect(b.memory, isEmpty); // memory is per profile
      expect(b.entries('user'), ['Adam suka jawaban singkat']); // user profile is shared
      expect(b.skills.map((s) => s.name), contains('cek-server')); // skills copied
      await b.saveSoul('# Payu ops agent');
      await b.memoryOp('add', 'memory', content: 'payu di /srv/payu');

      final def = await b.view('default');
      expect(def.memory, contains('vps-jkt'));
      expect(def.memory, isNot(contains('payu')));
      expect(def.soul, isNot(contains('Payu ops')));

      // survives a reload
      await b.load();
      expect(b.activeId, 'payu-ops');
      expect(b.soul, '# Payu ops agent');
      expect((await b.createProfile('Payu Ops')).id, 'payu-ops-2');
    });

    test('system prompt and tools follow the profile', () async {
      final b = await fresh();
      final p = await b.createProfile('Riset', emoji: '📚');
      p
        ..desc = 'cuma browsing'
        ..toolsOff = ['ssh', 'control'];
      await b.saveProfiles();
      final pb = await b.view(p.id);
      await pb.saveSoul('# Kamu peneliti');
      final a = AgentController.i;
      final prompt = a.systemPrompt(profile: pb);
      expect(prompt, startsWith('# Kamu peneliti'));
      expect(prompt, contains('📚 Riset'));
      final names = a.baseTools(profile: p.id).map((t) => t.group).toSet();
      expect(names.contains('ssh'), isFalse);
      expect(names.contains('control'), isFalse);
      expect(a.baseTools(profile: 'default').any((t) => t.group == 'ssh'), isTrue);
    });

    test('deleting a profile moves its chats to the default one', () async {
      final b = await fresh();
      final p = await b.createProfile('Sementara');
      final s = AgentSession(id: 'sess-1234', title: 'x', messages: [Msg(role: 'user', text: 'hai')])..profile = p.id;
      await b.saveSession(s);
      await b.setActive(p.id);
      await b.deleteProfile(p.id);
      expect(b.profile(p.id), isNull);
      expect(b.activeId, 'default');
      expect(b.sessions.single.profile, isNull);
      expect(Directory('${b.root.path}/profiles/${p.id}').existsSync(), isFalse);
    });
  });

  group('agent zip', () {
    test('roundtrip between two devices, merging instead of overwriting', () async {
      final b = await fresh();
      await b.memoryOp('add', 'user', content: 'Adam driver ojol');
      final p = await b.createProfile('Payu', emoji: '💼', copyFrom: 'default');
      final pb = await b.view(p.id);
      await pb.saveSoul('# soul payu');
      await pb.memoryOp('add', 'memory', content: 'repo payu di github');
      await pb.saveSkill('---\nname: deploy-payu\ndescription: deploy payu\n---\nlangkah');
      await b.saveSession(AgentSession(id: 'aaaa-bbbb-1', title: 'chat payu', messages: [Msg(role: 'user', text: 'halo')])..profile = p.id);
      b.jobs.add(CronJob(id: 'job1', name: 'cek', prompt: 'cek server', everyMinutes: 60, profile: p.id));
      await b.saveJobs();

      final zip = await AgentZip.export(b, sessions: true, jobs: true);
      final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name).toSet();
      expect(names, containsAll(['satsh-agent.json', 'USER.md', 'profiles/default/SOUL.md', 'profiles/payu/SOUL.md',
          'profiles/payu/skills/deploy-payu/SKILL.md', 'sessions/aaaa-bbbb-1.json', 'cron.json']));

      // "other device"
      final b2 = await fresh();
      await b2.memoryOp('add', 'user', content: 'suka kopi');
      final summary = await AgentZip.import(b2, zip);
      expect(summary, contains('💼 Payu'));
      expect(b2.entries('user'), containsAll(['suka kopi', 'Adam driver ojol'])); // merged
      final v = await b2.view('payu');
      expect(v.soul, '# soul payu');
      expect(v.memory, contains('repo payu'));
      expect(v.skill('deploy-payu'), isNotNull);
      expect(b2.sessions.single.profile, 'payu');
      expect(b2.jobs.single.enabled, isFalse); // imported paused
      // importing twice doesn't duplicate anything
      await AgentZip.import(b2, zip);
      expect(b2.entries('user').where((e) => e == 'Adam driver ojol'), hasLength(1));
      expect(b2.jobs, hasLength(1));
    });

    test('rejects other zips and unsafe paths', () async {
      final b = await fresh();
      expect(() => AgentZip.import(b, utf8.encode('nope')), throwsA(anything));
      final a = Archive()..addFile(ArchiveFile.bytes('hello.txt', utf8.encode('x')));
      expect(() => AgentZip.import(b, ZipEncoder().encodeBytes(a)), throwsA(contains('satsh-agent.json')));
      final evil = Archive()
        ..addFile(ArchiveFile.bytes('satsh-agent.json', utf8.encode(jsonEncode({
          'format': 'satsh-agent',
          'version': 1,
          'profiles': [{'id': '../../etc', 'name': 'x'}, {'id': 'ok', 'name': 'ok'}],
        }))))
        ..addFile(ArchiveFile.bytes('profiles/ok/skills/../../../pwn/SKILL.md', utf8.encode('---\nname: pwn\ndescription: x\n---')))
        ..addFile(ArchiveFile.bytes('sessions/../../x.json', utf8.encode('{}')));
      await AgentZip.import(b, ZipEncoder().encodeBytes(evil));
      expect(b.profile('../../etc'), isNull);
      expect(b.profile('ok'), isNotNull);
      expect((await b.view('ok')).skill('pwn'), isNull);
      expect(File('${b.root.path}/pwn/SKILL.md').existsSync(), isFalse);
      expect(File('${Directory(b.root.path).parent.path}/x.json').existsSync(), isFalse);
    });

    test('memory merge respects the size limit', () {
      final (m, skipped) = AgentZip.mergeEntries('a', ['b' * 50, 'c' * 50].join(entrySep), 60);
      expect(m, contains('b'));
      expect(m, isNot(contains('c')));
      expect(skipped, 1);
    });
  });
}
