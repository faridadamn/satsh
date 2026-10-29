// Misi: an autonomous goal the agent keeps working on, iteration after
// iteration, while the phone is on. Each iteration: read the journal → check
// the previous work against reality → do the next most useful step that
// doesn't need the user → update the journal → report. Things only the user
// can do become questions that never block the loop. Provider trouble puts the
// mission to sleep and it wakes itself up once the provider answers again.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../error_log.dart';
import '../redact.dart';
import '../store.dart' show newId;
import 'agent.dart';
import 'brain.dart';
import 'llm.dart';
import 'tools.dart';

class MissionAsk {
  MissionAsk({required this.id, required this.text, this.why = '', int? created, this.answer, this.answeredAt, this.delivered = false})
      : created = created ?? DateTime.now().millisecondsSinceEpoch;
  final String id;
  final String text;
  final String why;
  final int created;
  String? answer;
  int? answeredAt;

  /// The answer has been handed to the agent in an iteration brief.
  bool delivered;

  bool get open => answer == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (why.isNotEmpty) 'why': why,
        'created': created,
        if (answer != null) 'answer': answer,
        if (answeredAt != null) 'answeredAt': answeredAt,
        if (delivered) 'delivered': true,
      };
  factory MissionAsk.fromJson(Map<String, dynamic> j) => MissionAsk(
        id: j['id'],
        text: j['text'] ?? '',
        why: j['why'] ?? '',
        created: j['created'],
        answer: j['answer'],
        answeredAt: j['answeredAt'],
        delivered: j['delivered'] ?? false,
      );
}

class Mission {
  Mission({
    required this.id,
    required this.goal,
    this.criteria = '',
    this.profile,
    this.status = 'paused',
    this.statusNote = '',
    this.iteration = 0,
    this.journal = '',
    List<MissionAsk>? asks,
    List<String>? inbox,
    this.sessionId,
    int? created,
    this.lastReport = '',
    this.lastIterAt,
    this.lastTail = '',
    this.maxSteps = 80,
    this.maxIterPerDay = 0,
    this.gapSeconds = 0,
    this.autoRisky = true,
    this.sleepUntil,
    this.doneSummary = '',
    this.dayKey = '',
    this.dayCount = 0,
    this.failStreak = 0,
  })  : asks = asks ?? [],
        inbox = inbox ?? [],
        created = created ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String goal;
  String criteria;
  String? profile;

  /// running | waiting (provider down / daily quota / agent asked to sleep) | paused | done | error
  String status;
  String statusNote;
  int iteration;

  /// The agent's own notes, carried from iteration to iteration.
  String journal;
  final List<MissionAsk> asks;

  /// Messages the user sent to the mission, not yet read by the agent.
  final List<String> inbox;
  String? sessionId;
  final int created;
  String lastReport;
  int? lastIterAt;

  /// What the last iteration did (tool calls + last words) — helps after a cut-off.
  String lastTail;

  // ---- limits (user can tighten these when tokens are tight; 0 = no limit)
  int maxSteps;
  int maxIterPerDay;
  int gapSeconds;
  bool autoRisky;

  /// Agent asked to sleep until this time (nothing to do yet).
  int? sleepUntil;
  String doneSummary;
  String dayKey;
  int dayCount;
  int failStreak;

  bool get active => status == 'running' || status == 'waiting';
  int get openAsks => asks.where((a) => a.open).length;
  String get title => goal.length > 48 ? '${goal.substring(0, 48)}…' : goal;

  Map<String, dynamic> toJson() => {
        'id': id,
        'goal': goal,
        'criteria': criteria,
        if (profile != null) 'profile': profile,
        'status': status,
        'statusNote': statusNote,
        'iteration': iteration,
        'journal': journal,
        'asks': asks.map((a) => a.toJson()).toList(),
        'inbox': inbox,
        if (sessionId != null) 'sessionId': sessionId,
        'created': created,
        'lastReport': lastReport,
        if (lastIterAt != null) 'lastIterAt': lastIterAt,
        'lastTail': lastTail,
        'maxSteps': maxSteps,
        'maxIterPerDay': maxIterPerDay,
        'gapSeconds': gapSeconds,
        'autoRisky': autoRisky,
        if (sleepUntil != null) 'sleepUntil': sleepUntil,
        'doneSummary': doneSummary,
        'dayKey': dayKey,
        'dayCount': dayCount,
        'failStreak': failStreak,
      };

  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        id: j['id'],
        goal: j['goal'] ?? '',
        criteria: j['criteria'] ?? '',
        profile: j['profile'],
        status: j['status'] ?? 'paused',
        statusNote: j['statusNote'] ?? '',
        iteration: j['iteration'] ?? 0,
        journal: j['journal'] ?? '',
        asks: (j['asks'] as List? ?? []).map((e) => MissionAsk.fromJson(Map<String, dynamic>.from(e))).toList(),
        inbox: (j['inbox'] as List? ?? []).cast<String>(),
        sessionId: j['sessionId'],
        created: j['created'],
        lastReport: j['lastReport'] ?? '',
        lastIterAt: j['lastIterAt'],
        lastTail: j['lastTail'] ?? '',
        maxSteps: j['maxSteps'] ?? 80,
        maxIterPerDay: j['maxIterPerDay'] ?? 0,
        gapSeconds: j['gapSeconds'] ?? 0,
        autoRisky: j['autoRisky'] ?? true,
        sleepUntil: j['sleepUntil'],
        doneSummary: j['doneSummary'] ?? '',
        dayKey: j['dayKey'] ?? '',
        dayCount: j['dayCount'] ?? 0,
        failStreak: j['failStreak'] ?? 0,
      );
}

class _Run {
  bool cancel = false;
  Completer<void> wake = Completer<void>();
  AgentSession? session;
  void poke() {
    if (!wake.isCompleted) wake.complete();
  }
}

/// Provider/network trouble that fixes itself → wait and retry, don't count as the agent failing.
bool isProviderTrouble(Object e) {
  if (e is TimeoutException || e is SocketException || e is HttpException || e is HandshakeException) return true;
  final s = '$e'.toLowerCase();
  if (e is LlmBlocked) return false;
  return e is LlmError ||
      RegExp(r'clientexception|connection|socket|timed? ?out|http (408|409|425|429|5\d\d)|rate.?limit|quota|limit|overload|unavailable|busy|kosong|try again|capacity')
          .hasMatch(s);
}

class MissionRunner extends ChangeNotifier {
  MissionRunner._();
  static final MissionRunner i = MissionRunner._();

  List<Mission> missions = [];
  final Map<String, _Run> _runs = {};
  bool _loaded = false;

  /// Waits between retries while the provider is down (tests shrink these).
  static List<Duration> backoff = const [
    Duration(seconds: 20),
    Duration(seconds: 45),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  /// Smallest pause between iterations, so a mission that finds nothing to do can't spin.
  static Duration minGap = const Duration(seconds: 5);

  /// Report / question notifications (wired to the phone in main.dart).
  void Function(String title, String body, int id)? notifier;

  static String Function() idGen = newId;

  // ------------------------------------------------------------ storage
  File get _file => File('${Brain.i.root.path}/missions.json');

  Future<void> load() async {
    await _saving;
    try {
      final f = _file;
      missions = await f.exists()
          ? (jsonDecode(await f.readAsString()) as List).map((e) => Mission.fromJson(Map<String, dynamic>.from(e))).toList()
          : [];
    } catch (e, st) {
      ErrorLog.i.add('misi', e, st);
      missions = [];
    }
    // The phone/app was off: missions don't restart on their own — the user decides.
    for (final m in missions.where((m) => m.active)) {
      m.status = 'paused';
      m.statusNote = 'Berhenti karena HP/app sempat mati. Tap Lanjut buat nerusin.';
    }
    _loaded = true;
    await save();
    notifyListeners();
  }

  Future<void> _saving = Future.value();

  /// Saves are queued (the loop, the UI and tools all save) and atomic, so the file never ends up half-written.
  Future<void> save() {
    if (!_loaded) return Future.value();
    final json = const JsonEncoder.withIndent(' ').convert(missions.map((m) => m.toJson()).toList());
    return _saving = _saving.then((_) async {
      try {
        final tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(_file.path);
      } catch (_) {}
    });
  }

  Mission? byId(String id) => missions.where((m) => m.id == id || m.id.startsWith(id)).firstOrNull;
  bool get anyActive => missions.any((m) => m.active);
  int get openAsks => missions.fold(0, (n, m) => n + (m.status == 'done' ? 0 : m.openAsks));

  /// The live chat object of a running mission (so the chat screen shows it as it happens).
  AgentSession? liveSession(String sessionId) =>
      _runs.values.map((r) => r.session).whereType<AgentSession>().where((s) => s.id == sessionId).firstOrNull;

  bool isLive(String sessionId) => liveSession(sessionId) != null;

  // ------------------------------------------------------------ control
  Future<Mission> create({
    required String goal,
    String criteria = '',
    String? profile,
    int maxSteps = 80,
    int maxIterPerDay = 0,
    int gapSeconds = 0,
    bool autoRisky = true,
    bool start = true,
  }) async {
    final m = Mission(
      id: idGen(),
      goal: goal.trim(),
      criteria: criteria.trim(),
      profile: profile,
      maxSteps: maxSteps,
      maxIterPerDay: maxIterPerDay,
      gapSeconds: gapSeconds,
      autoRisky: autoRisky,
    );
    missions.insert(0, m);
    await save();
    if (start) {
      resume(m);
    } else {
      notifyListeners();
    }
    return m;
  }

  /// Starts (or continues) the loop.
  void resume(Mission m) {
    final old = _runs[m.id];
    if (old != null && !old.cancel) return;
    m.status = 'running';
    m.statusNote = 'Mulai…';
    m.failStreak = 0;
    m.sleepUntil = null;
    final run = _Run();
    _runs[m.id] = run;
    notifyListeners();
    unawaited(_loop(m, run));
  }

  /// Stops after the current step; work so far stays in the journal.
  Future<void> pause(Mission m, {String note = 'Dijeda sama lu.'}) async {
    final r = _runs[m.id];
    r?.cancel = true;
    r?.poke();
    if (m.status != 'done') m.status = 'paused';
    m.statusNote = note;
    await save();
    notifyListeners();
  }

  Future<void> delete(Mission m) async {
    await pause(m);
    missions.remove(m);
    await save();
    notifyListeners();
  }

  Future<void> update(Mission m) async {
    await save();
    _runs[m.id]?.poke();
    notifyListeners();
  }

  Future<void> answer(Mission m, String askId, String text) async {
    final a = m.asks.where((x) => x.id == askId).firstOrNull;
    if (a == null || text.trim().isEmpty) return;
    a
      ..answer = text.trim()
      ..answeredAt = DateTime.now().millisecondsSinceEpoch
      ..delivered = false;
    _wakeForUser(m);
    await save();
    notifyListeners();
  }

  /// A message from the user to the mission (read at the start of the next iteration).
  Future<void> note(Mission m, String text) async {
    if (text.trim().isEmpty) return;
    m.inbox.add(text.trim());
    _wakeForUser(m);
    await save();
    notifyListeners();
  }

  void _wakeForUser(Mission m) {
    // a sleeping mission wakes up when the user says something
    if (m.sleepUntil != null) m.sleepUntil = null;
    _runs[m.id]?.poke();
  }

  // ------------------------------------------------------------ the loop
  Future<void> _sleep(_Run run, Duration d) async {
    if (run.cancel || d <= Duration.zero) return;
    run.wake = Completer<void>();
    await Future.any([Future.delayed(d), run.wake.future]);
  }

  static String _day(DateTime t) => '${t.year}-${t.month}-${t.day}';

  Future<void> _loop(Mission m, _Run run) async {
    final a = AgentController.i;
    var tries = 0;
    var providerDown = false;
    try {
      while (!run.cancel && m.active) {
        final now = DateTime.now();
        // the agent said there's nothing to do until later
        if (m.sleepUntil != null && m.sleepUntil! > now.millisecondsSinceEpoch) {
          m.status = 'waiting';
          final until = DateTime.fromMillisecondsSinceEpoch(m.sleepUntil!);
          m.statusNote = 'Tidur sampai ${until.toString().substring(11, 16)} (nunggu sesuatu). Kirim pesan buat bangunin.';
          notifyListeners();
          await _sleep(run, until.difference(now));
          m.sleepUntil = null;
          continue;
        }
        // daily quota (only when the user set one)
        if (m.dayKey != _day(now)) {
          m.dayKey = _day(now);
          m.dayCount = 0;
        }
        if (m.maxIterPerDay > 0 && m.dayCount >= m.maxIterPerDay) {
          m.status = 'waiting';
          m.statusNote = 'Jatah ${m.maxIterPerDay} iterasi hari ini habis, lanjut besok.';
          await save();
          notifyListeners();
          await _sleep(run, DateTime(now.year, now.month, now.day + 1).difference(now));
          continue;
        }
        try {
          // honours a model the agent switched to earlier in this mission (model_switch)
          final sess = run.session ?? (m.sessionId == null ? null : await Brain.i.openSession(m.sessionId!));
          final llm = await a.provider(profile: m.profile, session: sess);
          if (providerDown) {
            // cheap check before spending a whole iteration
            m.statusNote = 'Ngecek provider udah normal belum…';
            notifyListeners();
            await llm.chat('Jawab satu kata: ok', [Msg(role: 'user', text: 'ping')], const []);
            providerDown = false;
            _notify(m, '🟢 Misi lanjut', 'Provider udah normal lagi, gw lanjut kerja.');
          }
          await _iterate(m, llm, run);
          tries = 0;
          m.failStreak = 0;
        } catch (e, st) {
          if (run.cancel) break;
          final provider = isProviderTrouble(e);
          if (!provider) {
            m.failStreak++;
            ErrorLog.i.add('misi', e, st, context: {'misi': m.title, 'iterasi': '${m.iteration}'});
          }
          if (!provider && m.failStreak >= 5) {
            m.status = 'error';
            m.statusNote = 'Berhenti: error yang sama terus (${Redact.text('$e')}). Cek lalu tap Lanjut.';
            _notify(m, '🔴 Misi berhenti', m.statusNote);
            break;
          }
          final wait = backoff[min(tries, backoff.length - 1)];
          tries++;
          if (!providerDown && provider) _notify(m, '🟡 Misi nunggu provider', 'Provider lagi error, gw tidur dulu dan nyoba lagi otomatis.\n${Redact.text('$e')}');
          providerDown = provider || providerDown;
          m.status = 'waiting';
          m.statusNote = '${provider ? 'Provider error' : 'Error'}: ${_short(Redact.text('$e'), 160)}\nNyoba lagi ${_dur(wait)} lagi (percobaan $tries).';
          await save();
          notifyListeners();
          await _sleep(run, wait);
          if (!run.cancel && m.status == 'waiting') m.status = 'running';
          continue;
        }
        if (!m.active || run.cancel) break;
        m.status = 'running';
        final gap = Duration(seconds: m.gapSeconds) > minGap ? Duration(seconds: m.gapSeconds) : minGap;
        m.statusNote = 'Iterasi berikutnya ${_dur(gap)} lagi…';
        notifyListeners();
        await _sleep(run, gap);
      }
    } finally {
      if (identical(_runs[m.id], run)) _runs.remove(m.id);
      await save();
      notifyListeners();
    }
  }

  Future<void> _iterate(Mission m, LlmProvider llm, _Run run) async {
    final a = AgentController.i;
    final brain = Brain.i;
    final pb = await brain.view(m.profile);
    var s = run.session ?? (m.sessionId == null ? null : await brain.openSession(m.sessionId!));
    s ??= AgentSession(id: m.sessionId ?? idGen(), title: '🎯 ${m.title}')..profile = pb.id;
    // the chat screen may hold this session already
    if (a.session.id == s.id && !identical(a.session, s)) s = a.session;
    m.sessionId = s.id;
    run.session = s;

    m.iteration++;
    m.dayCount++;
    m.status = 'running';
    m.statusNote = 'Iterasi ${m.iteration}: analisa kerjaan sebelumnya…';
    m.sleepUntil = null;
    notifyListeners();

    final start = s.messages.length;
    s.messages.add(Msg(role: 'user', text: brief(m)));
    final handed = m.asks.where((x) => !x.open && !x.delivered).toList();
    final inbox = List.of(m.inbox);
    for (final x in handed) {
      x.delivered = true;
    }
    m.inbox.clear();
    final state = _IterState();
    await save();

    final ctx = RunCtx(
      session: s,
      profile: pb,
      autoApprove: m.autoRisky,
      denyRisky: !m.autoRisky,
      maxSteps: m.maxSteps <= 0 ? 400 : m.maxSteps,
      isCancelled: () => run.cancel,
      onStatus: (t) {
        m.statusNote = 'Iterasi ${m.iteration}: $t';
        notifyListeners();
      },
      onChange: () {
        if (identical(a.session, s)) a.refresh();
        notifyListeners();
      },
    );
    List<Msg> window() => s!.messages.sublist(start).where((x) => x.role != 'event').toList();
    final tools = [
      ...a.baseTools(profile: pb.id),
      ...a.brainTools(ctx).where((t) => t.spec.name != 'mission_start'),
      ..._missionTools(m, state),
    ];
    final system = '${a.systemPrompt(profile: pb)}\n\n$missionRules';
    String out;
    try {
      out = await a.runLoop(llm: llm, history: s.messages, ctx: ctx, system: system, tools: tools, contextOf: window);
    } catch (e) {
      // the user's answers/messages weren't really handled: hand them over again next time
      for (final x in handed) {
        x.delivered = false;
      }
      m.inbox.insertAll(0, inbox);
      if (!s.messages.skip(start).any((x) => x.role == 'assistant')) {
        // failed before doing anything: this attempt doesn't count as an iteration
        s.messages.removeRange(start, s.messages.length);
        m.iteration--;
        m.dayCount--;
        rethrow;
      }
      // provider died mid-iteration: keep what happened so the next iteration can pick it up
      m.lastTail = _tail(s.messages.sublist(start));
      m.lastReport = 'Iterasi ${m.iteration} kepotong di tengah (${_short('$e', 120)}). Cek jejaknya, lanjutin yang belum beres.';
      s.messages.add(Msg(role: 'event', text: '⚠️ Iterasi ${m.iteration} kepotong: ${_short(Redact.text('$e'), 200)}'));
      await brain.saveSession(s);
      rethrow;
    }
    final ranOut = isLoopStop(out);
    if (!run.cancel && (ranOut || !state.journal)) {
      // out of steps or forgot the journal: one short wrap-up so the next iteration knows where it stands
      s.messages.add(Msg(
          role: 'user',
          text: ranOut
              ? '[Langkah iterasi ini habis] Jangan kerja lagi. Sekarang: update mission_journal (yang udah beres, yang setengah jalan, rencana berikutnya), lalu tulis laporan singkat buat user.'
              : '[Sebelum tutup iterasi] Kamu belum update jurnal. Panggil mission_journal sekarang, lalu tulis laporan singkat buat user.'));
      final wrapTools = _missionTools(m, state).where((t) => t.spec.name != 'mission_done').toList();
      final w = await a.runLoop(
          llm: llm,
          history: s.messages,
          ctx: RunCtx(session: s, profile: pb, maxSteps: 4, isCancelled: () => run.cancel, onChange: ctx.onChange),
          system: system,
          tools: wrapTools,
          contextOf: window);
      if (w.trim().isNotEmpty) out = w;
    }
    m.lastTail = _tail(s.messages.sublist(start));
    m.lastReport = (state.report ?? out).trim();
    m.lastIterAt = DateTime.now().millisecondsSinceEpoch;
    if (state.sleepUntil != null && m.status != 'done') m.sleepUntil = state.sleepUntil;
    s.messages.add(Msg(role: 'event', text: '📋 Iterasi ${m.iteration} selesai'));
    trimLog(s);
    s.unread = !identical(a.session, s);
    await brain.saveSession(s);
    await save();
    if (m.status == 'done') {
      _notify(m, '🏁 Misi tercapai', m.doneSummary.isEmpty ? m.lastReport : m.doneSummary);
      run.cancel = true;
    } else {
      _notify(m, '🎯 Iterasi ${m.iteration}: ${m.title}', m.lastReport.isEmpty ? 'Selesai.' : m.lastReport);
    }
    notifyListeners();
  }

  /// A mission can run for days: keep its chat log from growing without end
  /// (the agent only ever reads the current iteration + its journal).
  static int maxLog = 800;
  static void trimLog(AgentSession s) {
    if (s.messages.length <= maxLog) return;
    var cut = s.messages.length - (maxLog * 3 ~/ 4);
    // don't split a tool call from its result
    while (cut < s.messages.length && s.messages[cut].role == 'tool') {
      cut++;
    }
    s.messages.removeRange(0, cut);
    s.messages.insert(0, Msg(role: 'event', text: '✂️ Log iterasi lama dipangkas (jurnal tetap utuh)'));
    s.contextStart = 0;
  }

  void _notify(Mission m, String title, String body) {
    try {
      notifier?.call(title, Redact.text(body).replaceAll(RegExp(r'[*_`#>]'), ''), 300 + m.id.hashCode % 1000);
    } catch (_) {}
  }

  static String _short(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
  static String _dur(Duration d) => d.inMinutes >= 1 ? '${d.inMinutes} menit' : '${d.inSeconds} detik';

  static String _tail(List<Msg> msgs) {
    final lines = <String>[];
    for (final x in msgs) {
      if (x.role == 'assistant') {
        for (final c in x.calls) {
          final arg = jsonEncode(c.args);
          lines.add('- ${c.name} ${_short(arg, 120)}');
        }
      } else if (x.role == 'tool' && x.isError) {
        lines.add('  ↳ ERROR ${_short(x.text.replaceAll('\n', ' '), 160)}');
      }
    }
    final last = msgs.lastWhere((x) => x.role == 'assistant' && x.text.trim().isNotEmpty, orElse: () => Msg(role: 'assistant')).text;
    final t = [...lines.length > 40 ? lines.sublist(lines.length - 40) : lines, if (last.isNotEmpty) 'Kata terakhir: ${_short(last, 600)}'].join('\n');
    return _short(t, 4000);
  }

  // ------------------------------------------------------------ prompts
  static const missionRules = '''## MODE MISI (otonom)
Kamu lagi jalanin misi jangka panjang sendirian. User TIDAK nungguin kamu di chat — dia cuma baca laporan.
- Jangan pernah berhenti/nunggu user. Yang butuh user (duit, akun/KYC, tanda tangan, login pribadi, posting atas nama user, keputusan besar) → mission_ask, lalu langsung kerjain hal lain yang bisa jalan tanpa dia.
- Jangan keluar duit, jangan transaksi/daftar akun atas nama user, jangan hapus data tanpa backup, jangan spam orang.
- Verifikasi hasil kerja pakai tools (cek URL nyala, test lolos, file ada). Jangan ngaku beres tanpa bukti.
- Kalau cara yang sama gagal 2x, ganti pendekatan dan catat pelajarannya di jurnal.
- Kalau lagi nunggu sesuatu dari luar (user daftar, DNS nyebar, review), pakai mission_sleep biar ga buang token.
- Tutup tiap iterasi dengan mission_journal + laporan singkat (apa yang dikerjain, hasil, berikutnya).''';

  static String brief(Mission m) {
    final b = StringBuffer('[MISI · iterasi ${m.iteration} · ${DateTime.now().toString().substring(0, 16)}]\n')
      ..writeln('Tujuan: ${m.goal}')
      ..writeln(m.criteria.isEmpty
          ? 'Kriteria sukses: belum ditentuin user — tentuin sendiri yang terukur, tulis di jurnal.'
          : 'Kriteria sukses: ${m.criteria}');
    b
      ..writeln()
      ..writeln('## Jurnal kamu')
      ..writeln(m.journal.trim().isEmpty
          ? '(kosong — ini iterasi pertama. Bikin rencana tahapan misi dari awal sampai tujuan, tiap tahap dengan kriteria lulusnya, lalu mulai tahap 1.)'
          : m.journal.trim());
    if (m.lastReport.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Laporan iterasi sebelumnya')
        ..writeln(m.lastReport);
    }
    if (m.lastTail.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Jejak iterasi sebelumnya (tool yang dipanggil)')
        ..writeln(m.lastTail);
    }
    final fresh = m.asks.where((x) => !x.open && !x.delivered).toList();
    if (fresh.isNotEmpty || m.inbox.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## BARU dari user');
      for (final x in fresh) {
        b.writeln('- Kamu nanya: ${x.text}\n  Jawaban user: ${x.answer}');
      }
      for (final n in m.inbox) {
        b.writeln('- Pesan user: $n');
      }
    }
    final open = m.asks.where((x) => x.open).toList();
    if (open.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Masih nunggu jawaban user (JANGAN ditunggu, kerjain yang lain)');
      for (final x in open) {
        b.writeln('- [${x.id}] ${x.text}');
      }
    }
    b
      ..writeln()
      ..writeln('## Iterasi ini')
      ..writeln('1. Analisa: cek hasil iterasi sebelumnya ke kenyataan pakai tools. Ada yang salah/rusak? Benerin dulu.')
      ..writeln('2. Kerjain 1–3 langkah paling berdampak yang bisa jalan tanpa user, sampai beres dan terverifikasi.')
      ..writeln('3. mission_journal: tahap sekarang + kriteria lulus, yang beres (dengan bukti), yang gagal + pelajaran, rencana berikutnya.')
      ..writeln('4. Laporan singkat buat user. Kalau kriteria sukses misi kebukti tercapai → mission_done dengan buktinya.')
      ..writeln(m.maxSteps > 0 ? 'Batas iterasi ini ${m.maxSteps} langkah — sisain 2 buat jurnal & laporan.' : '');
    return b.toString().trim();
  }
}

class _IterState {
  bool journal = false;
  String? report;
  int? sleepUntil;
}

List<AgentTool> _missionTools(Mission m, _IterState st) {
  final r = MissionRunner.i;
  return [
    AgentTool(
      const ToolSpec(
        name: 'mission_journal',
        description:
            'Tulis ulang jurnal misi (markdown, ganti total). Ini satu-satunya ingatan kamu ke iterasi berikutnya: tahapan + kriteria lulus, tahap sekarang, yang udah beres (dengan bukti: URL, path, hasil cek), yang gagal & pelajarannya, info penting (server, repo, akun), rencana iterasi berikutnya.',
        params: {
          'content': {'type': 'string'},
        },
        required: ['content'],
      ),
      group: 'brain',
      (a) async {
        final c = '${a['content'] ?? ''}'.trim();
        if (c.isEmpty) throw 'content kosong';
        m.journal = c.length > 12000 ? '${c.substring(0, 12000)}\n…[jurnal kepanjangan, ringkas di iterasi berikutnya]' : c;
        st.journal = true;
        await r.update(m);
        return 'Jurnal disimpen (${m.journal.length} karakter).';
      },
    ),
    AgentTool(
      const ToolSpec(
        name: 'mission_ask',
        description:
            'Catat hal yang cuma bisa dikerjain/diputusin user (bayar, daftar akun/KYC, login pribadi, posting atas nama dia, keputusan besar). User dapet notifikasi. JANGAN nunggu jawabannya — langsung lanjut kerja lain; jawabannya muncul di iterasi berikutnya.',
        params: {
          'question': {'type': 'string', 'description': 'apa yang perlu user lakuin/jawab, jelas & bisa langsung dikerjain'},
          'why': {'type': 'string', 'description': 'kenapa perlu, singkat'},
        },
        required: ['question'],
      ),
      group: 'brain',
      (a) async {
        final q = '${a['question'] ?? ''}'.trim();
        if (q.isEmpty) throw 'question kosong';
        final dup = m.asks.where((x) => x.open && x.text.toLowerCase() == q.toLowerCase()).firstOrNull;
        if (dup != null) return 'Udah pernah ditanyain [${dup.id}], masih nunggu. Lanjut kerja lain.';
        final ask = MissionAsk(id: MissionRunner.idGen().substring(0, 6), text: q, why: '${a['why'] ?? ''}'.trim());
        m.asks.add(ask);
        await r.update(m);
        r._notify(m, '🙋 Misi butuh lu', q);
        return 'Dicatat [${ask.id}], user udah dikabarin. Jangan nunggu — kerjain langkah lain yang bisa jalan tanpa ini.';
      },
    ),
    AgentTool(
      const ToolSpec(
        name: 'mission_sleep',
        description:
            'Tidur dulu kalau lagi nunggu hal dari luar dan belum ada yang bisa dikerjain (mis. nunggu user daftar, DNS, review). Bangun otomatis setelah X menit, atau lebih cepet kalau user kirim pesan.',
        params: {
          'minutes': {'type': 'integer', 'description': '5–1440'},
          'reason': {'type': 'string'},
        },
        required: ['minutes'],
      ),
      group: 'brain',
      (a) async {
        final mins = ((a['minutes'] as num?)?.toInt() ?? 30).clamp(5, 1440);
        st.sleepUntil = DateTime.now().add(Duration(minutes: mins)).millisecondsSinceEpoch;
        return 'Oke, abis iterasi ini tidur $mins menit${a['reason'] != null ? ' (${a['reason']})' : ''}. Tutup iterasi: jurnal + laporan.';
      },
    ),
    AgentTool(
      const ToolSpec(
        name: 'mission_done',
        description: 'Tandai misi TERCAPAI. Cuma kalau kriteria sukses udah kebukti (kasih buktinya). Loop berhenti setelah iterasi ini.',
        params: {
          'evidence': {'type': 'string', 'description': 'bukti konkret kriteria sukses tercapai'},
        },
        required: ['evidence'],
      ),
      group: 'brain',
      (a) async {
        final ev = '${a['evidence'] ?? ''}'.trim();
        if (ev.length < 20) throw 'Kasih bukti yang konkret (angka, URL, hasil cek).';
        m.status = 'done';
        m.doneSummary = ev;
        m.statusNote = 'Tercapai di iterasi ${m.iteration}.';
        await r.update(m);
        return 'Misi ditandai tercapai. Tulis laporan penutup buat user.';
      },
    ),
    AgentTool(
        const ToolSpec(
          name: 'mission_report',
          description: 'Laporan iterasi ini buat user (dikirim jadi notifikasi). Singkat: apa yang dikerjain, hasilnya, berikutnya mau apa.',
          params: {
            'text': {'type': 'string'},
          },
          required: ['text'],
        ),
        group: 'brain',
        (a) async {
          st.report = '${a['text'] ?? ''}'.trim();
          return 'Laporan dicatat.';
        },
      ),
  ];
}
