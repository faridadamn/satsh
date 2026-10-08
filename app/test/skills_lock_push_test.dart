// Built-in skills are read-only for the agent (user can edit + reset),
// the 3 new presets, work principles for new agents, and pushing skills to Hermes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/presets.dart';
import 'package:satsh/agent/skill_push.dart';
import 'package:satsh/agent/tools.dart';
import 'package:satsh/models.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Brain> fresh() async {
  Brain.rootOverride = Directory.systemTemp.createTempSync('lock').path;
  await Brain.i.load();
  return Brain.i;
}

AgentTool tool(String name) => AgentController.i.brainTools(RunCtx(autoApprove: true)).firstWhere((t) => t.spec.name == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
  });

  group('skill bawaan', () {
    test('agent cannot edit, patch, delete or recreate a built-in skill', () async {
      final b = await fresh();
      final pb = b.active;
      expect(pb.isBuiltin('cek-server'), isTrue);
      final manage = tool('skill_manage');
      final before = pb.skill('cek-server')!.raw;
      for (final args in [
        {'action': 'edit', 'name': 'cek-server', 'content': '---\nname: cek-server\ndescription: x\n---\nhack'},
        {'action': 'patch', 'name': 'cek-server', 'old_text': 'Health check', 'new_text': 'Hacked'},
        {'action': 'delete', 'name': 'cek-server'},
      ]) {
        await expectLater(manage.run(args), throwsA(contains('BAWAAN')), reason: '${args['action']}');
      }
      expect(pb.skill('cek-server')!.raw, before);
      await pb.deleteSkill('cek-server');
      await expectLater(
          manage.run({'action': 'create', 'name': 'cek-server', 'content': '---\nname: cek-server\ndescription: x\n---\ny'}), throwsA(contains('BAWAAN')));
      expect(await manage.run({'action': 'create', 'name': 'punyaku', 'content': '---\nname: punyaku\ndescription: d\n---\n1'}), contains('kesimpen'));
      expect(await manage.run({'action': 'delete', 'name': 'punyaku'}), contains('dihapus'));
      expect(pb.skillsIndex(), contains('[bawaan, read-only]'));
    });

    test('user can edit; reset and reset-all bring the shipped version back', () async {
      final b = await fresh();
      final pb = b.active;
      await pb.saveSkill('---\nname: deploy-git\ndescription: versi gw\n---\nlangkah gw');
      expect(pb.isModified(pb.skill('deploy-git')!), isTrue);
      await pb.deleteSkill('rapihin-download');
      expect(pb.missingBuiltins, ['rapihin-download']);
      await pb.resetSkill('deploy-git');
      expect(pb.isModified(pb.skill('deploy-git')!), isFalse);
      await pb.saveSkill('---\nname: deploy-git\ndescription: lagi\n---\nx');
      expect(await pb.resetAllBuiltins(), 2);
      expect(pb.missingBuiltins, isEmpty);
      expect(pb.skills.where(pb.isModified), isEmpty);
      await expectLater(pb.resetSkill('ga-ada'), throwsA(contains('bukan skill bawaan')));
    });

    test('preset skills are built-in for their profile, even after a restart', () async {
      final b = await fresh();
      await b.autoInstallPresets(Presets.all());
      b.builtinSkills.removeWhere((k, _) => k != 'default');
      await b.autoInstallPresets(Presets.all());
      final v = await b.view('cybersecurity');
      expect(v.isBuiltin('audit-server'), isTrue);
      await expectLater(v.saveSkill('---\nname: audit-server\ndescription: x\n---\ny', byAgent: true), throwsA(contains('BAWAAN')));
      final out = await tool('agent_profile').run({
        'action': 'add_skill',
        'id': 'cybersecurity',
        'skills': [
          {'name': 'audit-server', 'description': 'palsu', 'content': 'x'},
          {'name': 'cek-cron', 'description': 'cek cron', 'content': '1. crontab -l'},
        ],
      });
      expect(out, contains('Gagal'));
      final v2 = await b.view('cybersecurity');
      expect(v2.isModified(v2.skill('audit-server')!), isFalse);
      expect(v2.skill('cek-cron'), isNotNull);
    });
  });

  group('preset baru', () {
    test('cybersecurity, devops, code-reviewer ship soul + valid skills + work principles', () async {
      for (final (id, emoji, skills) in [
        ('cybersecurity', '🛡️', ['audit-server', 'cek-bocor-secret', 'cek-web-app', 'insiden-login']),
        ('devops', '🚀', ['rilis-aman', 'backup-restore', 'docker-beres', 'nginx-ssl']),
        ('code-reviewer', '🔍', ['review-diff', 'cek-test', 'audit-dependency']),
      ]) {
        final f = await Presets.load(id);
        final meta = jsonDecode(f['profile.json']!) as Map;
        expect(meta['id'], id);
        expect(meta['emoji'], emoji);
        expect((meta['toolsOff'] as List), contains('control'), reason: id);
        expect(f['SOUL.md'], contains('## Cara kerja'), reason: id);
        expect(f['SOUL.md'], contains('Bukti, bukan klaim'), reason: id);
        for (final s in skills) {
          final sk = Brain.parseSkill(f['skills/$s/SKILL.md'] ?? '');
          expect(sk?.name, s, reason: '$id/$s');
          expect(sk!.description.length, greaterThan(40), reason: '$id/$s');
        }
        expect(Presets.names[id], startsWith(emoji));
      }
      expect((await Presets.load('cybersecurity'))['SOUL.md'], contains('Jangan pernah jalanin exploit'));
    });

    test('agents made with agent_profile get the work principles once', () async {
      final b = await fresh();
      await tool('agent_profile').run({'action': 'create', 'name': 'Riset Pasar', 'desc': 'riset kompetitor'});
      final v = await b.view('riset-pasar');
      expect(v.soul, contains('# SOUL — Riset Pasar'));
      expect(v.soul, contains('## Cara kerja'));
      await tool('agent_profile').run({'action': 'create', 'name': 'Kedua', 'soul': '# SOUL — Kedua\n\n$workPrinciples'});
      expect('## Cara kerja'.allMatches((await b.view('kedua')).soul).length, 1);
    });
  });

  group('push skill ke Hermes', () {
    late Directory home;
    final h = Host(id: 'vps', label: 'VPS', host: '127.0.0.1', port: 22, username: 'adam');

    setUp(() {
      home = Directory.systemTemp.createTempSync('home');
      SkillPush.execOverride = (cmd) async {
        final r = await Process.run('sh', ['-c', cmd], environment: {'HOME': home.path});
        return (r.exitCode, '${r.stdout}', '${r.stderr}');
      };
    });
    tearDown(() => SkillPush.execOverride = null);

    test('prepare adds version only when missing', () {
      expect(SkillPush.prepare('---\nname: a\ndescription: b\n---\nisi'), '---\nname: a\ndescription: b\nversion: 1.0.0\n---\nisi\n');
      expect(SkillPush.prepare('---\nname: a\nversion: 2.0.0\n---\nisi'), '---\nname: a\nversion: 2.0.0\n---\nisi\n');
    });

    test('no Hermes → says so', () async {
      final st = await SkillPush.status(h);
      expect(st.hasAgent, isFalse);
    });

    test('push, status, change, pull', () async {
      final b = await fresh();
      Directory('${home.path}/.hermes').createSync();
      final pb = b.active;
      var st = await SkillPush.status(h);
      expect(st.hasAgent, isTrue);
      expect(st.of(pb.skill('cek-server')!), PushState.missing);

      final path = await SkillPush.push(h, pb.skill('cek-server')!);
      expect(path, '~/.hermes/skills/satsh/cek-server/SKILL.md');
      final f = File('${home.path}/.hermes/skills/satsh/cek-server/SKILL.md');
      expect(f.readAsStringSync(), contains('version: 1.0.0'));
      expect(jsonDecode(File('${home.path}/.hermes/skills/satsh/cek-server/.satsh-push.json').readAsStringSync())['from'], 'satsh');

      st = await SkillPush.status(h);
      expect(st.of(pb.skill('cek-server')!), PushState.same);
      await pb.saveSkill('${pb.skill('cek-server')!.raw}\n6. tambahan');
      expect(st.of(pb.skill('cek-server')!), PushState.differs);

      Directory('${home.path}/.hermes/skills/devops/cek-log').createSync(recursive: true);
      File('${home.path}/.hermes/skills/devops/cek-log/SKILL.md')
          .writeAsStringSync("---\nname: cek-log\ndescription: baca log yang ada 'kutip'-nya\n---\n1. journalctl\n");
      st = await SkillPush.status(h);
      final only = st.onlyRemote(pb.skills.map((s) => s.name));
      expect(only.map((r) => r.name), ['cek-log']);
      expect(only.single.path, 'devops/cek-log/SKILL.md');
      final raw = await SkillPush.pull(h, only.single);
      expect(await pb.saveSkill(raw), 'cek-log');
    });

    test('skill_push tool: status + push, risky', () async {
      final b = await fresh();
      Directory('${home.path}/.hermes').createSync();
      await Store.i.saveHost(h, password: 'x');
      final t = tool('skill_push');
      expect(t.risky, isTrue);
      final st = await t.run({'action': 'status', 'host': 'VPS'});
      expect(st, contains('cek-server: belum ada'));
      final out = await t.run({'action': 'push', 'host': 'VPS', 'names': ['cek-server', 'deploy-git', 'ga-ada']});
      expect(out, contains('cek-server → ~/.hermes/skills/satsh/cek-server/SKILL.md'));
      expect(out, contains('ga-ada: ga ada'));
      expect(File('${home.path}/.hermes/skills/satsh/deploy-git/SKILL.md').existsSync(), isTrue);
      expect(await t.run({'action': 'status', 'host': 'VPS'}), contains('cek-server: sama'));
      expect(b.active.skill('cek-server'), isNotNull);
    });
  });
}
