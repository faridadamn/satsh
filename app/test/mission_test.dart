// Misi: the agent keeps working on its own, iteration after iteration; questions
// for the user never block; provider errors put it to sleep and it wakes itself up.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/agent/mission.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Script = FutureOr<LlmReply> Function(List<Msg> h, List<ToolSpec> tools);

class Fake implements LlmProvider {
  Fake(this.script);
  Script script;
  final calls = <List<Msg>>[];
  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools) async {
    calls.add(List.of(history));
    return script(history, tools);
  }
}

LlmReply say(String t) => LlmReply(t, []);
LlmReply call(String name, Map<String, dynamic> args) => LlmReply('', [ToolCall(id: 'c${DateTime.now().microsecondsSinceEpoch}', name: name, args: args)]);
String lastUser(List<Msg> h) => h.lastWhere((m) => m.role == 'user').text;
bool calledIn(List<Msg> h, String tool) => h.any((m) => m.role == 'tool' && m.name == tool);

Future<void> until(bool Function() f, {int ms = 8000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!f()) {
    if (DateTime.now().isAfter(end)) {
      final m = MissionRunner.i.missions.firstOrNull;
      throw TimeoutException('condition not met — ${m?.status} it=${m?.iteration} note=${m?.statusNote} report=${m?.lastReport}');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final r = MissionRunner.i;
  final notes = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    Brain.rootOverride = Directory.systemTemp.createTempSync('mission').path;
    await Brain.i.load();
    await r.load();
    MissionRunner.backoff = const [Duration(milliseconds: 400)];
    MissionRunner.minGap = const Duration(milliseconds: 10);
    r.notifier = (t, b, _) => notes.add('$t | $b');
  });

  tearDown(() async {
    for (final m in r.missions.toList()) {
      await r.delete(m);
    }
    AgentController.i.providerOverride = null;
    notes.clear();
  });

  test('iterates, journals, asks without waiting, reports; provider error → sleeps → wakes; done stops it', () async {
    var phase = 0;
    late Fake fake;
    fake = Fake((h, tools) {
      final u = lastUser(h);
      if (u == 'ping') return say('ok');
      if (u.startsWith('[MISI · iterasi 1')) {
        if (!calledIn(h, 'mission_journal')) {
          return LlmReply('Rencana dulu', [
            ToolCall(id: 'j1', name: 'mission_journal', args: {'content': '# Tahap 1: riset ide\n- lulus kalau ada 3 ide tervalidasi'}),
            ToolCall(id: 'a1', name: 'mission_ask', args: {'question': 'Daftar Midtrans pakai KTP lu', 'why': 'buat terima bayaran'}),
          ]);
        }
        return say('Iterasi 1: bikin rencana 7 tahap, mulai riset. Nanya soal Midtrans.');
      }
      if (u.startsWith('[MISI · iterasi 2')) {
        if (phase == 0) {
          phase = 1;
          throw LlmError('HTTP 503: model overloaded');
        }
        expect(u, contains('Jawaban user: udah daftar, id M123'), reason: 'answer reaches the agent');
        expect(u, contains('Pesan user: fokus ke UMKM'));
        expect(u, contains('# Tahap 1'), reason: 'journal carried over');
        expect(u, contains('Iterasi 1: bikin rencana'), reason: 'last report carried over');
        if (!calledIn(h, 'mission_done')) {
          return LlmReply('', [
            ToolCall(id: 'j2', name: 'mission_journal', args: {'content': '# Beres\nPembayaran pertama masuk Rp49.000 (order #1)'}),
            ToolCall(id: 'd1', name: 'mission_done', args: {'evidence': 'Order #1 dibayar Rp49.000 via Midtrans, server Rp30.000/bln → profit'}),
          ]);
        }
        return say('Misi tercapai: order pertama masuk.');
      }
      return say('?');
    });
    AgentController.i.providerOverride = fake;

    final m = await r.create(goal: 'Bikin produk SaaS dari nol sampai profit', criteria: 'ada pembayaran > biaya server', maxSteps: 10);
    await until(() => notes.any((n) => n.startsWith('🎯 Iterasi 1')));
    expect(m.journal, contains('Tahap 1'));
    expect(m.asks.single.open, isTrue);
    expect(notes.any((n) => n.startsWith('🙋') && n.contains('Midtrans')), isTrue, reason: 'user notified of the question');
    expect(notes.any((n) => n.startsWith('🎯 Iterasi 1')), isTrue, reason: 'iteration report notified');

    // it went on to iteration 2 without waiting for the answer, hit the provider error and went to sleep
    await until(() => m.status == 'waiting' && m.statusNote.contains('Provider error'));
    expect(notes.any((n) => n.startsWith('🟡')), isTrue);
    // user answers + sends a note while it sleeps
    // both land before the sleeping loop gets to run again
    await Future.wait([r.answer(m, m.asks.single.id, 'udah daftar, id M123'), r.note(m, 'fokus ke UMKM')]);

    await until(() => notes.any((n) => n.startsWith('🏁')), ms: 10000);
    expect(m.status, 'done');
    expect(fake.calls.any((h) => lastUser(h) == 'ping'), isTrue, reason: 'cheap probe before resuming');
    expect(notes.any((n) => n.startsWith('🟢')), isTrue, reason: 'told the user it is back');
    expect(notes.any((n) => n.startsWith('🏁')), isTrue);
    expect(m.doneSummary, contains('Order #1'));
    expect(m.asks.single.delivered, isTrue);
    expect(m.inbox, isEmpty);
    await until(() => !r.anyActive);

    // everything is in the mission's own chat, and survives a restart
    final s = await Brain.i.openSession(m.sessionId!);
    expect(s!.messages.where((x) => x.role == 'event' && x.text.contains('Iterasi')).length, greaterThanOrEqualTo(2));
    final again = Mission.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(again.journal, m.journal);
    expect(again.asks.single.answer, 'udah daftar, id M123');
  });

  test('forgot the journal → short wrap-up asks for it', () async {
    final fake = Fake((h, tools) {
      final u = lastUser(h);
      if (u.contains('belum update jurnal')) {
        return calledIn(h.sublist(h.lastIndexWhere((m) => m.role == 'user')), 'mission_journal')
            ? say('Laporan: cek server')
            : call('mission_journal', {'content': 'catatan iterasi'});
      }
      return say('udah kerja dikit');
    });
    AgentController.i.providerOverride = fake;
    final m = await r.create(goal: 'Jagain server tetap nyala terus');
    await until(() => notes.any((n) => n.startsWith('🎯 Iterasi 1')));
    await r.pause(m);
    expect(notes.firstWhere((n) => n.startsWith('🎯 Iterasi 1')), contains('Laporan: cek server'));
    expect(m.journal, 'catatan iterasi');
    expect(m.status, 'paused');
  });

  test('step limit per iteration: out of steps → wrap-up, then keeps going', () async {
    var tick = 0;
    final fake = Fake((h, tools) {
      final u = lastUser(h);
      if (u.contains('Langkah iterasi ini habis')) {
        expect(tools.map((t) => t.name), isNot(contains('ssh_exec')), reason: 'wrap-up can only journal/report');
        return calledIn(h.sublist(h.lastIndexWhere((m) => m.role == 'user')), 'mission_journal')
            ? say('kepotong batas langkah, lanjut nanti')
            : call('mission_journal', {'content': 'setengah jalan ${tick++}'});
      }
      return call('mission_report', {'text': 'kerja…'}); // never finishes on its own
    });
    AgentController.i.providerOverride = fake;
    final m = await r.create(goal: 'Riset kompetitor sampai lengkap', maxSteps: 3);
    await until(() => m.iteration >= 2 && m.journal.startsWith('setengah jalan'));
    await r.pause(m);
    final firstIter = fake.calls.where((h) => lastUser(h).startsWith('[MISI · iterasi 1')).length;
    expect(firstIter, 3, reason: 'exactly maxSteps model calls before the wrap-up');
  });

  test('agent can sleep while waiting for something; a user message wakes it', () async {
    final fake = Fake((h, tools) {
      final u = lastUser(h);
      if (u.startsWith('[MISI · iterasi 1')) {
        return calledIn(h, 'mission_sleep')
            ? (calledIn(h, 'mission_journal') ? say('nunggu user daftar') : call('mission_journal', {'content': 'nunggu signup'}))
            : call('mission_sleep', {'minutes': 600, 'reason': 'nunggu signup'});
      }
      return say('bangun');
    });
    AgentController.i.providerOverride = fake;
    final m = await r.create(goal: 'Dapet 10 user pertama buat app');
    await until(() => m.status == 'waiting' && m.statusNote.startsWith('Tidur'));
    expect(m.iteration, 1);
    await r.note(m, 'udah gw share di grup');
    await until(() => fake.calls.any((h) => lastUser(h).contains('Pesan user: udah gw share di grup')));
    await r.pause(m);
    expect(m.iteration, greaterThanOrEqualTo(2));
  });

  test('risky actions off → denied without a dialog (never blocks)', () async {
    final fake = Fake((h, tools) {
      if (!h.any((m) => m.role == 'tool' && m.name == 'phone_delete')) return call('phone_delete', {'path': 'Download/sampah'});
      return calledIn(h, 'mission_journal') ? say('dicatat') : call('mission_journal', {'content': 'butuh izin'});
    });
    AgentController.i.providerOverride = fake;
    final m = await r.create(goal: 'Beresin folder sampah di server', autoRisky: false);
    await until(() => m.journal == 'butuh izin');
    await r.pause(m);
    final denied = fake.calls.expand((h) => h).where((x) => x.role == 'tool' && x.name == 'phone_delete').toList();
    expect(denied, isNotEmpty);
    expect(denied.first.text, contains('Ditolak otomatis'));
    expect(denied.first.text, contains('mission_ask'));
  });

  test('app restart: running missions come back paused (phone was off)', () async {
    AgentController.i.providerOverride = Fake((h, t) => Completer<LlmReply>().future); // hangs
    final m = await r.create(goal: 'Misi yang lagi jalan pas HP mati');
    await until(() => m.status == 'running');
    await r.save();
    await r.load(); // like a cold start
    final back = r.byId(m.id)!;
    expect(back.status, 'paused');
    expect(back.statusNote, contains('HP/app sempat mati'));
  });

  test('chatting in a mission chat sends the message to the mission', () async {
    AgentController.i.providerOverride = Fake((h, t) => say('ok'));
    final m = await r.create(goal: 'Tes kirim pesan ke misi', start: false);
    final a = AgentController.i;
    m.sessionId = a.session.id;
    await a.send('tambahin fitur export');
    expect(m.inbox, ['tambahin fitur export']);
    expect(a.messages.last.text, contains('dikirim ke misi'));
    a.newChat();
  });

  test('long-running mission log is trimmed, never splitting a tool result from its call', () {
    final s = AgentSession(id: 'log');
    for (var i = 0; i < 300; i++) {
      s.messages
        ..add(Msg(role: 'user', text: 'brief $i'))
        ..add(Msg(role: 'assistant', text: '', calls: [ToolCall(id: 'c$i', name: 'x', args: {})]))
        ..add(Msg(role: 'tool', callId: 'c$i', name: 'x', text: 'ok'));
    }
    MissionRunner.trimLog(s);
    expect(s.messages.length, lessThanOrEqualTo(MissionRunner.maxLog));
    expect(s.messages.first.role, 'event');
    expect(s.messages[1].role, isNot('tool'));
    expect(s.messages.last.text, 'ok');
  });

  test('provider trouble vs real errors', () {
    expect(isProviderTrouble(LlmError('HTTP 503: overloaded')), isTrue);
    expect(isProviderTrouble(LlmError('9router: HTTP 429: rate limit')), isTrue);
    expect(isProviderTrouble(TimeoutException('x')), isTrue);
    expect(isProviderTrouble(const SocketException('Failed host lookup')), isTrue);
    expect(isProviderTrouble(LlmBlocked('Ditolak filter provider (OTHER)')), isFalse);
    expect(isProviderTrouble(StateError('bug')), isFalse);
  });
}
