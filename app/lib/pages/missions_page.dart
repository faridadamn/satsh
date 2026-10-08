import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../agent/agent.dart';
import '../agent/brain.dart';
import '../agent/mission.dart';
import '../redact.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_page.dart' show MessageBody;

Color _statusColor(String s) => switch (s) {
      'running' => C.green,
      'waiting' => C.amber,
      'done' => C.cyan,
      'error' => C.red,
      _ => C.muted,
    };

String _statusLabel(String s) => switch (s) {
      'running' => 'jalan',
      'waiting' => 'nunggu',
      'done' => 'tercapai',
      'error' => 'berhenti (error)',
      _ => 'dijeda',
    };

String _ago(int? ms) {
  if (ms == null) return '-';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'barusan';
  if (d.inHours < 1) return '${d.inMinutes} mnt lalu';
  if (d.inDays < 1) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

class _Chip extends StatelessWidget {
  const _Chip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: _statusColor(status), shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(_statusLabel(status), style: TextStyle(fontSize: 11, color: _statusColor(status), fontWeight: FontWeight.w700)),
        ]),
      );
}

/// List of missions.
class MissionsPage extends StatelessWidget {
  const MissionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final r = MissionRunner.i;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const GradientText('Misi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: C.violet,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.rocket_launch_rounded),
          label: const Text('Misi baru'),
          onPressed: () => newMission(context),
        ),
        body: r.missions.isEmpty
            ? const EmptyState(
                icon: Icons.rocket_launch_rounded,
                title: 'Belum ada misi',
                subtitle:
                    'Kasih tujuan besar, agent kerja sendiri iterasi demi iterasi selama HP nyala: analisa → kerja → lapor, sampai tercapai.')
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
                for (final (i, m) in r.missions.indexed)
                  StaggerIn(
                    index: i,
                    child: Pressable(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MissionDetailPage(id: m.id))),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: C.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: m.openAsks > 0 && m.status != 'done' ? C.pink.withValues(alpha: 0.5) : C.stroke),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            _Chip(m.status),
                            const SizedBox(width: 8),
                            Text('iterasi ${m.iteration}', style: TextStyle(fontSize: 11, color: C.muted, fontFamily: monoFont)),
                            const Spacer(),
                            if (m.openAsks > 0 && m.status != 'done')
                              Badge(label: Text('${m.openAsks} nanya'), backgroundColor: C.pink),
                          ]),
                          const SizedBox(height: 8),
                          Text(m.goal, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 6),
                          Text(
                            Redact.text(m.statusNote.isNotEmpty ? m.statusNote : m.lastReport),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: C.muted, fontSize: 12.5),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }
}

Future<void> newMission(BuildContext context) async {
  final goal = TextEditingController();
  final crit = TextEditingController();
  var steps = 80;
  var auto = true;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Misi baru', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Agent kerja sendiri selama HP nyala. Yang butuh lu dicatat jadi pertanyaan, dia ga nunggu.',
                style: TextStyle(color: C.muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: goal,
              minLines: 3,
              maxLines: 6,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Tujuan', hintText: 'mis. Bikin produk SaaS dari nol sampai menghasilkan profit'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: crit,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Kriteria sukses (opsional)', hintText: 'mis. Ada pembayaran masuk > biaya server'),
            ),
            const SizedBox(height: 14),
            _StepsPicker(value: steps, onChanged: (v) => set(() => steps = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: auto,
              onChanged: (v) => set(() => auto = v),
              title: const Text('Aksi berisiko tanpa nanya'),
              subtitle: Text(auto ? 'Jalanin perintah server, tulis file, dll. sendiri' : 'Aksi berisiko ditolak otomatis & dicatat jadi pertanyaan',
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ),
            const SizedBox(height: 10),
            GradientButton(label: 'Mulai misi', icon: Icons.rocket_launch_rounded, onTap: () => Navigator.pop(c, true)),
          ]),
        ),
      ),
    ),
  );
  if (ok != true || goal.text.trim().length < 5) return;
  // Android's battery saver would freeze the mission while the screen is off
  try {
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  } catch (_) {}
  final m = await MissionRunner.i.create(goal: goal.text, criteria: crit.text, profile: Brain.i.activeId, maxSteps: steps, autoRisky: auto);
  if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => MissionDetailPage(id: m.id)));
}

class _StepsPicker extends StatelessWidget {
  const _StepsPicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  static const opts = [(20, 'Hemat'), (40, 'Sedang'), (80, 'Normal'), (0, 'Bebas')];

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Batas langkah per iterasi', style: TextStyle(fontSize: 12.5, color: C.muted)),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (final (v, l) in opts) ButtonSegment(value: v, label: Text(v == 0 ? l : '$l\n$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)))],
          selected: {opts.any((o) => o.$1 == value) ? value : 80},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ]);
}

/// One mission: status, questions for the user, last report, journal, limits.
class MissionDetailPage extends StatefulWidget {
  const MissionDetailPage({super.key, required this.id});
  final String id;

  @override
  State<MissionDetailPage> createState() => _MissionDetailPageState();
}

class _MissionDetailPageState extends State<MissionDetailPage> {
  final _msg = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final r = MissionRunner.i;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        final m = r.byId(widget.id);
        if (m == null) return const Scaffold(body: Center(child: Text('Misi udah dihapus')));
        final open = m.asks.where((a) => a.open).toList();
        final answered = m.asks.where((a) => !a.open).toList().reversed.take(5).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Misi'),
            actions: [
              if (m.sessionId != null)
                IconButton(
                  tooltip: 'Lihat log kerja',
                  icon: const Icon(Icons.forum_rounded),
                  onPressed: () async {
                    await AgentController.i.openSession(m.sessionId!);
                    if (context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                  },
                ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete' && await confirm(context, 'Hapus misi?', 'Jurnal & pertanyaannya ilang. Log chatnya tetep ada di riwayat sesi.')) {
                    await r.delete(m);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Hapus misi'))],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
            Row(children: [
              _Chip(m.status),
              const SizedBox(width: 8),
              Text('iterasi ${m.iteration} · terakhir ${_ago(m.lastIterAt)}', style: TextStyle(fontSize: 11.5, color: C.muted, fontFamily: monoFont)),
            ]),
            const SizedBox(height: 10),
            SelectableText(m.goal, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
            if (m.criteria.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Sukses kalau: ${m.criteria}', style: TextStyle(color: C.muted, fontSize: 12.5)),
            ],
            if (m.statusNote.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(Redact.text(m.statusNote), style: TextStyle(color: _statusColor(m.status), fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: m.active
                    ? OutlinedButton.icon(onPressed: () => r.pause(m), icon: const Icon(Icons.pause_rounded), label: const Text('Jeda'))
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: C.violet),
                        onPressed: () => r.resume(m),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(m.status == 'done' ? 'Lanjut lagi' : 'Lanjut')),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(tooltip: 'Batas & aturan', onPressed: () => _limits(context, m), icon: const Icon(Icons.tune_rounded)),
            ]),
            if (m.status == 'done' && m.doneSummary.isNotEmpty) _Section('🏁 Tercapai', child: MessageBody(Redact.text(m.doneSummary))),
            if (open.isNotEmpty)
              _Section('🙋 Butuh lu (${open.length})', accent: C.pink, child: Column(children: [for (final a in open) _AskTile(m: m, ask: a)])),
            _Section('📋 Laporan terakhir',
                child: m.lastReport.isEmpty ? Text('Belum ada.', style: TextStyle(color: C.muted)) : MessageBody(Redact.text(m.lastReport))),
            _Section('✉️ Pesan ke misi',
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _msg,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Arahan, info, koreksi… dibaca di iterasi berikutnya', isDense: true),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send_rounded, color: C.violet),
                    onPressed: () async {
                      final t = _msg.text.trim();
                      if (t.isEmpty) return;
                      await r.note(m, t);
                      _msg.clear();
                      toast(m.active ? 'Dikirim, dibaca di iterasi berikutnya' : 'Disimpen. Misi lagi berhenti — tap Lanjut.');
                    },
                  ),
                ])),
            if (m.inbox.isNotEmpty) Text('${m.inbox.length} pesan belum dibaca agent', style: TextStyle(fontSize: 11.5, color: C.muted)),
            _Section('📓 Jurnal agent',
                child: m.journal.isEmpty ? Text('Belum ada.', style: TextStyle(color: C.muted)) : MessageBody(Redact.text(m.journal))),
            if (answered.isNotEmpty)
              _Section('✅ Udah lu jawab',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final a in answered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${a.text}\n→ ${a.answer}${a.delivered ? '' : '  (belum dibaca)'}', style: TextStyle(fontSize: 12.5, color: C.muted)),
                      ),
                  ])),
          ]),
        );
      },
    );
  }

  Future<void> _limits(BuildContext context, Mission m) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          void save(void Function() f) {
            set(f);
            MissionRunner.i.update(m);
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Batas & aturan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Default-nya bebas. Ketatin kalau lagi hemat token. Berlaku mulai iterasi berikutnya.', style: TextStyle(color: C.muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              _StepsPicker(value: m.maxSteps, onChanged: (v) => save(() => m.maxSteps = v)),
              const SizedBox(height: 14),
              Text('Maksimal iterasi per hari', style: TextStyle(fontSize: 12.5, color: C.muted)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Bebas')),
                  ButtonSegment(value: 50, label: Text('50')),
                  ButtonSegment(value: 20, label: Text('20')),
                  ButtonSegment(value: 5, label: Text('5')),
                ],
                selected: {[0, 50, 20, 5].contains(m.maxIterPerDay) ? m.maxIterPerDay : 0},
                onSelectionChanged: (s) => save(() => m.maxIterPerDay = s.first),
              ),
              const SizedBox(height: 14),
              Text('Jeda antar iterasi', style: TextStyle(fontSize: 12.5, color: C.muted)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Langsung')),
                  ButtonSegment(value: 300, label: Text('5 mnt')),
                  ButtonSegment(value: 1800, label: Text('30 mnt')),
                  ButtonSegment(value: 3600, label: Text('1 jam')),
                ],
                selected: {[0, 300, 1800, 3600].contains(m.gapSeconds) ? m.gapSeconds : 0},
                onSelectionChanged: (s) => save(() => m.gapSeconds = s.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: m.autoRisky,
                onChanged: (v) => save(() => m.autoRisky = v),
                title: const Text('Aksi berisiko tanpa nanya'),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child, this.accent});
  final String title;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent?.withValues(alpha: 0.5) ?? C.stroke),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: accent ?? C.text)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

class _AskTile extends StatefulWidget {
  const _AskTile({required this.m, required this.ask});
  final Mission m;
  final MissionAsk ask;

  @override
  State<_AskTile> createState() => _AskTileState();
}

class _AskTileState extends State<_AskTile> {
  final _ctl = TextEditingController();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(Redact.text(widget.ask.text), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (widget.ask.why.isNotEmpty) Text(widget.ask.why, style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctl,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Jawab / "udah gw kerjain" / "skip"', isDense: true),
              ),
            ),
            IconButton(
              icon: Icon(Icons.check_circle_rounded, color: C.green),
              onPressed: () {
                final t = _ctl.text.trim();
                if (t.isEmpty) return;
                MissionRunner.i.answer(widget.m, widget.ask.id, t);
              },
            ),
          ]),
        ]),
      );
}
