// Hermes-style brain: memory, skills, sessions, compression, delegate, todo, cron, review.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/models.dart';
import 'package:satsh/ssh_manager.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrustAll implements Prompts {
  @override
  Future<String?> askPassword(Host h, {String? reason}) async => null;
  @override
  Future<bool> trustHostKey(Host h, String type, String fp, String? oldFp) async => true;
}

typedef Router = LlmReply Function(String system, List<Msg> history, List<String> tools);

class FakeLlm implements LlmProvider {
  FakeLlm(this.route);
  Router route;
  final systems = <String>[];
  final histories = <List<Msg>>[];
  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools) async {
    systems.add(system);
    histories.add(List.of(history));
    await Future.delayed(const Duration(milliseconds: 5));
    return route(system, history, tools.map((t) => t.name).toList());
  }
}

int _n = 0;
ToolCall call(String name, Map<String, dynamic> args) => ToolCall(id: 'c${_n++}', name: name, args: args);
List<Msg> toolResults(List<Msg> h) => h.where((m) => m.role == 'tool').toList();
bool lastIsUser(List<Msg> h) => h.last.role == 'user';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final a = AgentController.i;
  late String root;
  final host = Host(id: 'h1', label: 'local', host: '127.0.0.1', port: 2222, username: 'tester');

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'agent_chat': '[{"role":"user","text":"chat lama dari v2"},{"role":"assistant","text":"halo"}]',
    });
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    root = (await Directory.systemTemp.createTemp('brain')).path;
    Brain.rootOverride = root;
    await a.load();
    Store.i.set('reviewEvery', 0);
    await Store.i.saveHost(host, password: 'rahasia123');
    SshManager.i.prompts = TrustAll();
    a.approver = (_, _) async => 'yes';
  });

  test('defaults + legacy chat migrated', () async {
    expect(Brain.i.skills.map((s) => s.name), containsAll(['cek-server', 'deploy-git', 'rapihin-download']));
    expect(Brain.i.soul, contains('satsh agent'));
    expect(Brain.i.sessions.single.title, 'chat lama dari v2');
    expect(File('$root/SOUL.md').existsSync(), isTrue);
  });

  test('memory tool: add / replace / remove / limit, shows up in prompt', () async {
    a.newChat();
    final llm = FakeLlm((sys, h, tools) {
      if (!lastIsUser(h)) {
        final r = toolResults(h);
        if (r.length == 4) {
          expect(r[0].text, startsWith('OK'));
          expect(r[1].text, startsWith('OK'));
          expect(r[2].isError, isTrue); // too long
          expect(r[3].text, startsWith('OK'));
          return LlmReply('dicatat', []);
        }
      }
      return LlmReply('', [
        call('memory', {'action': 'add', 'target': 'user', 'content': 'Adam driver ojol, suka jawaban singkat'}),
        call('memory', {'action': 'add', 'target': 'memory', 'content': 'Leo ada di ~/leo, restart: pm2 restart leo'}),
        call('memory', {'action': 'add', 'target': 'memory', 'content': 'x' * 3000}),
        call('memory', {'action': 'replace', 'target': 'memory', 'old_text': 'pm2 restart', 'content': 'Leo ada di ~/leo, restart: systemctl restart leo'}),
      ]);
    });
    a.providerOverride = llm;
    await a.send('inget ya');
    expect(Brain.i.entries('user'), ['Adam driver ojol, suka jawaban singkat']);
    expect(Brain.i.entries('memory').single, contains('systemctl'));
    expect(File('$root/MEMORY.md').readAsStringSync(), contains('systemctl'));
    // next prompt contains memory
    llm.route = (s, h, t) => LlmReply('ok', []);
    await a.send('tes');
    expect(llm.systems.last, contains('systemctl restart leo'));
    expect(llm.systems.last, contains('PROFIL USER'));
    // remove
    expect(await Brain.i.memoryOp('remove', 'memory', oldText: 'systemctl'), contains('0 entri'));
  });

  test('skills: create via tool, slash command, patch, delete, validation', () async {
    a.newChat();
    const good = '---\nname: restart-leo\ndescription: Restart agent Leo di laptop\n---\n1. jalanin `pm2 restart leo`\n2. cek log';
    final llm = FakeLlm((sys, h, tools) {
      if (lastIsUser(h)) {
        return LlmReply('', [
          call('skill_manage', {'action': 'create', 'name': 'jelek', 'content': 'tanpa frontmatter'}),
          call('skill_manage', {'action': 'create', 'name': 'restart-leo', 'content': good}),
          call('skill_manage', {'action': 'patch', 'name': 'restart-leo', 'old_text': 'cek log', 'new_text': 'cek log 50 baris'}),
          call('skill_view', {'name': 'restart-leo'}),
        ]);
      }
      final r = toolResults(h);
      expect(r[0].isError, isTrue);
      expect(r[1].text, contains('kesimpen'));
      expect(r[3].text, contains('50 baris'));
      return LlmReply('skill jadi', []);
    });
    a.providerOverride = llm;
    await a.send('simpen jadi skill');
    expect(Brain.i.skill('restart-leo'), isNotNull);
    expect(File('$root/skills/restart-leo/SKILL.md').readAsStringSync(), contains('50 baris'));
    // slash command injects skill body
    llm.route = (s, h, t) => LlmReply('oke', []);
    await a.send('/restart-leo sekarang ya');
    expect(llm.systems.last, contains('restart-leo: Restart agent Leo'));
    expect(a.messages.where((m) => m.role == 'user').last.text, allOf(contains('pm2 restart leo'), contains('sekarang ya')));
    await Brain.i.deleteSkill('restart-leo');
    expect(Brain.i.skill('restart-leo'), isNull);
  });

  test('sessions: persist, search across chats, reopen', () async {
    a.newChat();
    a.providerOverride = FakeLlm((s, h, t) => LlmReply('Sertifikat SSL nginx buat payu.id udah gw perpanjang pakai certbot.', []));
    await a.send('tolong perpanjang ssl nginx payu');
    final firstId = a.session.id;
    a.newChat();
    final llm = FakeLlm((sys, h, tools) {
      if (lastIsUser(h)) return LlmReply('', [call('session_search', {'query': 'ssl payu'})]);
      final r = toolResults(h).last;
      expect(r.text, contains('perpanjang ssl nginx payu'));
      expect(r.text, contains('id=$firstId'));
      return LlmReply('Kemarin pakai certbot', []);
    });
    a.providerOverride = llm;
    await a.send('kemarin ssl payu diperpanjang pakai apa?');
    expect(a.messages.last.text, 'Kemarin pakai certbot');
    // reload brain from disk
    await Brain.i.load();
    expect(Brain.i.sessions.map((m) => m.id), contains(firstId));
    await a.openSession(firstId);
    expect(a.messages.first.text, 'tolong perpanjang ssl nginx payu');
  });

  test('context compression keeps recent turns and a summary', () async {
    a.newChat();
    Store.i.set('ctxChars', 3000);
    var summarized = 0;
    final llm = FakeLlm((sys, h, tools) {
      if (sys.startsWith('Kamu peringkas')) {
        summarized++;
        return LlmReply('RINGKASAN: user lagi setup server.', []);
      }
      return LlmReply('jawaban panjang ${'bla ' * 150}', []);
    });
    a.providerOverride = llm;
    for (var i = 0; i < 8; i++) {
      await a.send('pertanyaan ke-$i ${'detail ' * 60}');
    }
    expect(summarized, greaterThan(0));
    expect(a.session.contextStart, greaterThan(0));
    final lastHist = llm.histories.last;
    expect(lastHist.first.text, contains('RINGKASAN'));
    expect(a.messages.first.text, startsWith('pertanyaan ke-0')); // full history still visible
    Store.i.set('ctxChars', 80000);
  });

  test('todo + delegate to parallel sub-agents', () async {
    a.newChat();
    final llm = FakeLlm((sys, h, tools) {
      if (sys.contains('sub-agent satsh')) {
        expect(tools, isNot(contains('delegate_task')));
        final goal = h.first.text;
        if (lastIsUser(h)) return LlmReply('', [call('ssh_exec', {'host': 'local', 'command': 'echo ${goal.split(' ').last}'})]);
        return LlmReply('laporan: ${toolResults(h).last.text.split('\n').last}', []);
      }
      if (lastIsUser(h)) {
        return LlmReply('', [
          call('todo_write', {
            'items': [
              {'content': 'cek A', 'status': 'in_progress'},
              {'content': 'cek B', 'status': 'pending'},
            ]
          }),
          call('delegate_task', {
            'tasks': [
              {'goal': 'cek server ALFA'},
              {'goal': 'cek server BRAVO'},
            ]
          }),
        ]);
      }
      final r = toolResults(h).last.text;
      expect(r, allOf(contains('ALFA'), contains('BRAVO'), contains('Tugas 2')));
      return LlmReply('', [
        call('todo_write', {
          'items': [
            {'content': 'cek A', 'status': 'done'},
            {'content': 'cek B', 'status': 'done'},
          ]
        })
      ]);
    });
    a.providerOverride = llm;
    final asked = <String>[];
    a.approver = (t, _) async {
      asked.add(t.spec.name);
      return 'yes';
    };
    // stop after second todo
    var calls = 0;
    final base = llm.route;
    llm.route = (s, h, t) => (++calls > 6 && !s.contains('sub-agent')) ? LlmReply('beres', []) : base(s, h, t);
    await a.send('cek dua server paralel');
    expect(a.session.todos.every((t) => t['status'] == 'done'), isTrue);
    expect(asked.where((e) => e == 'ssh_exec').length, 2); // sub-agents still ask permission
    a.approver = (_, _) async => 'yes';
  });

  test('cron: create via tool, run headless into its own session, risky denied', () async {
    a.newChat();
    final llm = FakeLlm((sys, h, tools) {
      final lastUser = h.lastWhere((m) => m.role == 'user').text;
      if (lastUser.startsWith('[Jadwal')) {
        if (lastIsUser(h)) {
          return LlmReply('', [
            call('ssh_exec', {'host': 'local', 'command': 'uptime'}),
            call('sftp_list', {'host': 'local'}),
          ]);
        }
        final r = toolResults(h);
        expect(r[r.length - 2].text, contains('Ditolak otomatis'));
        return LlmReply('Server aman, ${r.last.text.split('\n').first}', []);
      }
      if (lastIsUser(h)) {
        return LlmReply('', [
          call('cron_manage', {'action': 'create', 'name': 'Cek pagi', 'prompt': 'cek server', 'daily_at': '7:00'}),
        ]);
      }
      return LlmReply('jadwal dibikin', []);
    });
    a.providerOverride = llm;
    await a.send('tiap jam 7 cek server');
    final job = Brain.i.jobs.single;
    expect(job.dailyAt, '07:00');
    expect(job.allowRisky, isFalse);
    final done = <String>[];
    CronRunner.i.onDone = (t, b) => done.add('$t|$b');
    await CronRunner.i.run(job);
    expect(done.single, contains('Server aman'));
    final s = await Brain.i.openSession(job.sessionId!);
    expect(s!.title, '⏰ Cek pagi');
    expect(s.unread, isTrue);
    expect(Brain.i.sessions.firstWhere((m) => m.id == s.id).cron, isTrue);
    expect(job.lastRun, isNotNull);
    // schedule math
    final j = CronJob(id: 'x', name: 'n', prompt: 'p', dailyAt: '07:00')..createdAt = DateTime(2026, 1, 1, 6).millisecondsSinceEpoch;
    expect(j.isDue(DateTime(2026, 1, 1, 6, 59)), isFalse);
    expect(j.isDue(DateTime(2026, 1, 1, 7, 1)), isTrue);
    j.lastRun = DateTime(2026, 1, 1, 7, 1).millisecondsSinceEpoch;
    expect(j.isDue(DateTime(2026, 1, 1, 20)), isFalse);
    expect(j.nextRun(DateTime(2026, 1, 1, 20)), DateTime(2026, 1, 2, 7));
    final iv = CronJob(id: 'y', name: 'n', prompt: 'p', everyMinutes: 30)..createdAt = DateTime(2026, 1, 1, 6).millisecondsSinceEpoch;
    expect(iv.isDue(DateTime(2026, 1, 1, 6, 29)), isFalse);
    expect(iv.isDue(DateTime(2026, 1, 1, 6, 31)), isTrue);
    Brain.i.jobs.clear();
    await Brain.i.saveJobs();
  });

  test('background review saves memory and leaves an event', () async {
    a.newChat();
    Store.i.set('reviewEvery', 2);
    var reviewed = 0;
    final llm = FakeLlm((sys, h, tools) {
      if (sys.contains('modul refleksi')) {
        expect(tools, unorderedEquals(['memory', 'skill_view', 'skill_manage']));
        if (lastIsUser(h)) {
          reviewed++;
          expect(h.first.text, contains('bahasa jawa'));
          return LlmReply('', [call('memory', {'action': 'add', 'target': 'user', 'content': 'Suka dijawab campur bahasa jawa'})]);
        }
        return LlmReply('ga ada lagi', []);
      }
      return LlmReply('siap', []);
    });
    a.providerOverride = llm;
    await a.send('mulai sekarang jawab campur bahasa jawa ya');
    await a.send('oke lanjut');
    await Future.delayed(const Duration(milliseconds: 300));
    expect(reviewed, 1);
    expect(Brain.i.entries('user').last, contains('bahasa jawa'));
    expect(a.messages.last.role, 'event');
    expect(a.messages.last.text, contains('profil ditambah'));
    Store.i.set('reviewEvery', 0);
  });
}
