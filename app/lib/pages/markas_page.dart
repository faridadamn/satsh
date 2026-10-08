import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../agent/brain.dart';
import '../markas.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Switches the bottom-nav tab (set by the shell).
final shellTab = ValueNotifier<int>(0);
const agentTabIndex = 1;

/// Markas: shared targets, achievements and chat with all of Adam's agents.
class MarkasPage extends StatefulWidget {
  const MarkasPage({super.key});

  @override
  State<MarkasPage> createState() => _MarkasPageState();
}

class _MarkasPageState extends State<MarkasPage> {
  final m = Markas.i;
  final _say = TextEditingController();
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    if (m.configured && m.snap == null) m.refresh();
  }

  List<Map<String, dynamic>> _list(String k) => ((m.snap?[k] as List?) ?? const []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> _install(String hostId) async {
    final h = Store.i.host(hostId);
    if (h == null) return;
    setState(() => _installing = true);
    try {
      final out = await m.install(h);
      toast([
        'Markas kepasang di ${h.label}',
        if (out.contains('HERMES_SKILL_OK')) 'skill Hermes dipasang',
        if (out.contains('HERMES_CLI_OK')) 'Hermes CLI ketemu',
      ].join(' · '));
    } catch (e) {
      toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _do(Future<void> Function() f) async {
    try {
      await f();
      await m.refresh();
    } catch (e) {
      toast('$e', error: true);
    }
  }

  void _rapat() {
    final a = AgentController.i;
    if (a.busy) return toast('Agent lagi kerja, tunggu bentar', error: true);
    if (Brain.i.activeId != 'default') a.switchProfile('default');
    a.newChat();
    a.send(Markas.rapatPrompt);
    shellTab.value = agentTabIndex;
  }

  Future<void> _schedule() async {
    final pick = await showSheet<String>(
      context: context,
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Jadwal rapat Markas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
        ListTile(leading: const Icon(Icons.wb_sunny_rounded), title: const Text('Tiap hari jam 08:00'), onTap: () => Navigator.pop(c, 'daily')),
        ListTile(leading: const Icon(Icons.date_range_rounded), title: const Text('Tiap minggu (mulai seminggu dari sekarang)'), onTap: () => Navigator.pop(c, 'weekly')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Rapat jalan di background: nanya Hermes & agy, nyatet ke Markas, terus ngirim rangkuman ke lu. '
              'Muse cuma ikut kalau lu izinin aksi berisiko di jadwalnya (kontrol HP).',
              style: TextStyle(color: C.muted, fontSize: 12)),
        ),
      ]),
    );
    if (pick == null) return;
    final b = Brain.i;
    b.jobs.removeWhere((j) => j.name == 'Rapat Markas');
    b.jobs.add(CronJob(
      id: newId(),
      name: 'Rapat Markas',
      prompt: Markas.rapatPrompt,
      dailyAt: pick == 'daily' ? '08:00' : null,
      everyMinutes: pick == 'weekly' ? 7 * 24 * 60 : null,
      profile: 'default',
    ));
    await b.saveJobs();
    toast(pick == 'daily' ? 'Rapat tiap hari 08:00 dijadwalin' : 'Rapat mingguan dijadwalin');
  }

  Future<void> _addTarget() async {
    final title = TextEditingController(), metric = TextEditingController();
    String owner = 'adam', deadline = '';
    final members = _list('members').map((e) => '${e['name']}').toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Target baru'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Target', hintText: 'mis. Payu: 10 UMKM pakai QRIS')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: owner,
                decoration: const InputDecoration(labelText: 'PIC (yang pegang)'),
                items: [for (final n in members.isEmpty ? ['adam'] : members) DropdownMenuItem(value: n, child: Text(n))],
                onChanged: (v) => set(() => owner = v ?? 'adam'),
              ),
              const SizedBox(height: 10),
              TextField(controller: metric, decoration: const InputDecoration(labelText: 'Ukuran sukses (opsional)', hintText: 'mis. 10 merchant aktif')),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text(deadline.isEmpty ? 'Tanpa tenggat' : 'Tenggat $deadline', style: TextStyle(color: C.muted))),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: c, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)), initialDate: DateTime.now().add(const Duration(days: 7)));
                    if (d != null) set(() => deadline = d.toIso8601String().substring(0, 10));
                  },
                  child: const Text('Pilih tanggal'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bikin')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await _do(() => m.run([
          'target', 'add', title.text.trim(), '--owner', owner,
          if (deadline.isNotEmpty) ...['--deadline', deadline],
          if (metric.text.trim().isNotEmpty) ...['--metric', metric.text.trim()],
        ]));
  }

  Future<void> _editTarget(Map<String, dynamic> t) async {
    var p = (t['progress'] as num? ?? 0).toDouble();
    String status = '${t['status']}';
    final note = TextEditingController();
    final ok = await showSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(c).viewInsets.bottom + 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#${t['id']} ${t['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 12),
            Text('Progress ${p.round()}%', style: TextStyle(color: C.muted)),
            Slider(value: p, min: 0, max: 100, divisions: 20, onChanged: (v) => set(() => p = v)),
            Wrap(spacing: 6, children: [
              for (final s in ['aktif', 'ditunda', 'selesai', 'batal'])
                ChoiceChip(label: Text(s), selected: status == s, onSelected: (_) => set(() => status = s)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Simpan'))),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await _do(() => m.run([
          'target', 'update', '${t['id']}', '--progress', '${p.round()}',
          if (status != t['status']) ...['--status', status],
          if (note.text.trim().isNotEmpty) ...['--note', note.text.trim()],
        ]));
  }

  Future<void> _send() async {
    final t = _say.text.trim();
    if (t.isEmpty) return;
    _say.clear();
    final to = RegExp(r'^@([a-z0-9_-]+)').firstMatch(t)?.group(1);
    await _do(() => m.run(['say', t, if (to != null) ...['--to', to]]));
  }

  static Color _who(String n) => switch (n) {
        'adam' => C.pink,
        'satsh' => C.cyan,
        'hermes' => C.amber,
        'muse' => C.violet,
        'agy' => C.green,
        _ => C.muted,
      };

  Widget _setup() {
    final hosts = Store.i.hostsSorted;
    var pick = hosts.where((h) => h.label.toLowerCase().contains('adamn')).firstOrNull?.id ?? hosts.firstOrNull?.id;
    return StatefulBuilder(
      builder: (context, set) => ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 120), children: [
        const GradientText('Markas', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
        const SizedBox(height: 8),
        Text('Workspace bareng lu & semua agent: target, pencapaian, obrolan. Datanya disimpen di server lu sendiri '
            '(program kecil `markas`, diakses lewat SSH — ga buka port apa-apa). Kalau Hermes ada di server itu, skill-nya ikut dipasang.',
            style: TextStyle(color: C.muted, height: 1.4)),
        const SizedBox(height: 18),
        if (hosts.isEmpty)
          Text('Tambah server dulu di tab Host.', style: TextStyle(color: C.amber))
        else ...[
          DropdownButtonFormField<String>(
            initialValue: pick,
            decoration: const InputDecoration(labelText: 'Server buat Markas'),
            items: [for (final h in hosts) DropdownMenuItem(value: h.id, child: Text(h.label))],
            onChanged: (v) => set(() => pick = v),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: _installing ? 'Masang…' : 'Pasang Markas',
            icon: Icons.rocket_launch_rounded,
            onTap: _installing || pick == null ? null : () => _install(pick!),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([m, Store.i]),
        builder: (context, _) {
          if (!m.configured) return SafeArea(bottom: false, child: _setup());
          final targets = _list('targets'), logs = _list('logs'), msgs = _list('messages');
          return SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: m.refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 120), children: [
                Row(children: [
                  const GradientText('Markas', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(m.host?.label ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontFamily: monoFont, fontSize: 12))),
                  IconButton(tooltip: 'Refresh', onPressed: m.loading ? null : m.refresh, icon: const Icon(Icons.refresh_rounded)),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'jadwal') await _schedule();
                      if (v == 'update' && m.host != null) await _install(m.host!.id);
                      if (v == 'ganti') m.hostId = '';
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'jadwal', child: Text('Jadwalkan rapat')),
                      PopupMenuItem(value: 'update', child: Text('Pasang ulang / update di server')),
                      PopupMenuItem(value: 'ganti', child: Text('Ganti server')),
                    ],
                  ),
                ]),
                if (m.error != null)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(m.error!, style: const TextStyle(color: C.red))),
                if (m.loading && m.snap == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
                Row(children: [
                  Expanded(child: GradientButton(label: 'Mulai rapat', icon: Icons.groups_rounded, onTap: _rapat)),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(onPressed: _addTarget, icon: const Icon(Icons.add_rounded), label: const Text('Target')),
                ]),
                const SizedBox(height: 18),
                _h('Target aktif', '${targets.length} · selesai ${m.snap?['selesai'] ?? 0}'),
                if (targets.isEmpty) Text('Belum ada target. Bikin satu, atau suruh agent: "bikin target …".', style: TextStyle(color: C.muted)),
                for (final t in targets) _targetCard(t),
                const SizedBox(height: 18),
                _h('Pencapaian terbaru', ''),
                for (final l in logs.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: _who('${l['who']}')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${l['who']} ', style: TextStyle(fontWeight: FontWeight.w700, color: _who('${l['who']}'))),
                          TextSpan(text: '${l['text']}'),
                          if (l['target_id'] != null) TextSpan(text: '  #${l['target_id']}', style: TextStyle(color: C.muted)),
                          TextSpan(text: '  ${'${l['at']}'.length >= 16 ? '${l['at']}'.substring(5, 16) : l['at']}', style: TextStyle(color: C.muted, fontSize: 11)),
                        ])),
                      ),
                    ]),
                  ),
                const SizedBox(height: 18),
                _h('Obrolan', 'ketik @nama buat nyolek'),
                for (final msg in msgs)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: msg['who'] == 'adam' ? C.violet.withValues(alpha: 0.12) : C.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: C.stroke),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${msg['who']}${'${msg['to_name'] ?? ''}'.isEmpty ? '' : ' → ${msg['to_name']}'}',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: _who('${msg['who']}'))),
                      const SizedBox(height: 2),
                      SelectableText('${msg['text']}'),
                    ]),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _say,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Tulis ke markas… (@hermes, @satsh)'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded, color: C.cyan)),
                ]),
              ]),
            ),
          );
        },
      );

  Widget _h(String t, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(width: 8),
          Text(sub, style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );

  Widget _targetCard(Map<String, dynamic> t) {
    final p = (t['progress'] as num? ?? 0).toInt();
    final owner = '${t['owner'] ?? ''}';
    return Pressable(
      onTap: () => _editTarget(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.stroke)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Text('$p%', style: TextStyle(fontFamily: monoFont, fontWeight: FontWeight.w700, color: p >= 100 ? C.green : C.cyan)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: p / 100, minHeight: 6, color: p >= 100 ? C.green : C.cyan, backgroundColor: C.surface2),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 4, children: [
            if (owner.isNotEmpty) Text('PIC $owner', style: TextStyle(color: _who(owner), fontSize: 12, fontWeight: FontWeight.w600)),
            if ('${t['deadline'] ?? ''}'.isNotEmpty) Text('tenggat ${t['deadline']}', style: TextStyle(color: C.muted, fontSize: 12)),
            if ('${t['metric'] ?? ''}'.isNotEmpty) Text('${t['metric']}', style: TextStyle(color: C.muted, fontSize: 12)),
            if (t['status'] != 'aktif') Text('${t['status']}', style: const TextStyle(color: C.amber, fontSize: 12)),
          ]),
        ]),
      ),
    );
  }
}
