import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../agent/agent.dart';
import '../agent/brain.dart';
import '../store.dart';
import '../theme.dart';
import 'error_log_page.dart';
import '../widgets.dart';
import 'file_viewer_page.dart';
import 'skill_push_sheet.dart';

/// Soul · Memori · Skill · Jadwal
class BrainPage extends StatefulWidget {
  const BrainPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<BrainPage> createState() => _BrainPageState();
}

class _BrainPageState extends State<BrainPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: GradientText('Otak ${Brain.i.activeProfile.emoji} ${Brain.i.activeProfile.name}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: false,
            indicatorColor: C.violet,
            labelColor: C.text,
            unselectedLabelColor: C.muted,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w700),
            tabs: const [Tab(text: 'Soul'), Tab(text: 'Memori'), Tab(text: 'Skill'), Tab(text: 'Jadwal')],
          ),
        ),
        body: SafeArea(top: false, child: TabBarView(controller: _tabs, children: const [_SoulTab(), _MemoryTab(), _SkillsTab(), _JobsTab()])),
      );
}

// ------------------------------------------------------------------- Soul
class _SoulTab extends StatefulWidget {
  const _SoulTab();

  @override
  State<_SoulTab> createState() => _SoulTabState();
}

class _SoulTabState extends State<_SoulTab> {
  late final _ctl = TextEditingController(text: Brain.i.soul);
  final _undo = UndoHistoryController();
  bool _preview = true;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _ctl.text != Brain.i.soul;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
        child: Row(children: [
          Expanded(
            child: Text('Kepribadian & prinsip agent. Selalu jadi bagian paling atas prompt-nya.',
                style: TextStyle(color: C.muted, fontSize: 13)),
          ),
          IconButton(
            tooltip: _preview ? 'Edit' : 'Preview',
            icon: Icon(_preview ? Icons.edit_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => _preview = !_preview),
          ),
          PopupMenuButton<String>(
            onSelected: (_) async {
              if (await confirm(context, 'Reset SOUL?', 'Balik ke kepribadian bawaan satsh.', ok: 'Reset')) {
                await Brain.i.saveSoul(defaultSoul);
                _ctl.text = Brain.i.soul;
              }
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'reset', child: Text('Reset ke bawaan'))],
          ),
        ]),
      ),
      Expanded(
        child: _preview
            ? Markdown(data: _ctl.text, styleSheet: mdStyle(context), padding: const EdgeInsets.fromLTRB(20, 4, 20, 100))
            : CodeEditor(controller: _ctl, undo: _undo),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        child: dirty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: GradientButton(
                    label: 'Simpan soul',
                    icon: Icons.save_rounded,
                    onTap: () async {
                      await Brain.i.saveSoul(_ctl.text);
                      setState(() {});
                      toast('Soul kesimpen');
                    },
                  ),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

// ----------------------------------------------------------------- Memory
class _MemoryTab extends StatelessWidget {
  const _MemoryTab();

  Future<void> _edit(BuildContext context, String target, [int? index]) async {
    final list = Brain.i.entries(target);
    final ctl = TextEditingController(text: index == null ? '' : list[index]);
    final r = await showSheet<String>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(index == null ? 'Entri baru' : 'Edit entri', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: ctl, autofocus: true, minLines: 2, maxLines: 6),
          const SizedBox(height: 12),
          GradientButton(label: 'Simpan', onTap: () => Navigator.pop(c, ctl.text.trim())),
        ]),
      ),
    );
    if (r == null || r.isEmpty) return;
    if (index == null) {
      list.add(r);
    } else {
      list[index] = r;
    }
    final size = list.join(entrySep).length;
    if (size > Brain.i.limitOf(target)) {
      toast('Kepenuhan ($size/${Brain.i.limitOf(target)}), ringkas dulu', error: true);
      return;
    }
    await Brain.i.setEntries(target, list);
  }

  Widget _section(BuildContext context, String target, String title, String hint, IconData icon) {
    final list = Brain.i.entries(target);
    final used = list.join(entrySep).length;
    final limit = Brain.i.limitOf(target);
    final pct = (used / limit).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.stroke)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: C.violet, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Spacer(),
          Text('$used/$limit', style: TextStyle(fontFamily: monoFont, fontSize: 12, color: pct > 0.85 ? C.amber : C.muted)),
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _edit(context, target)),
        ]),
        Text(hint, style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: pct, minHeight: 5, backgroundColor: C.surface2, color: pct > 0.85 ? C.amber : C.cyan),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Masih kosong — agent bakal ngisi sendiri seiring ngobrol.', style: TextStyle(color: C.muted, fontSize: 13)),
          ),
        for (var i = 0; i < list.length; i++)
          Dismissible(
            key: ValueKey('$target$i${list[i]}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete_rounded, color: C.red),
            ),
            onDismissed: (_) => Brain.i.setEntries(target, list..removeAt(i)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _edit(context, target, i),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
                child: Text(list[i], style: TextStyle(fontSize: 13.5, color: C.text, height: 1.4)),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Brain.i, Store.i]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
          children: [
            _section(context, 'user', 'Tentang lu', 'Preferensi, kebiasaan, gaya kerja lu.', Icons.person_rounded),
            _section(context, 'memory', 'Catatan agent', 'Fakta lingkungan, path project, cara restart, pelajaran.',
                Icons.sticky_note_2_rounded),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.stroke)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Refleksi otomatis', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Tiap N pesan, agent review obrolan di background & nyimpen memori/skill yang berguna.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  for (final n in [0, 4, 6, 10])
                    ChoiceChip(
                      label: Text(n == 0 ? 'Mati' : 'tiap $n'),
                      selected: Store.i.get<int>('reviewEvery', 6) == n,
                      onSelected: (_) => Store.i.set('reviewEvery', n),
                    ),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final a = AgentController.i;
                      if (a.messages.isEmpty) {
                        toast('Buka sesi yang ada isinya dulu', error: true);
                        return;
                      }
                      toast('Lagi refleksi…');
                      try {
                        final notes = await a.review(a.session, await a.provider());
                        toast(notes.isEmpty ? 'Ga ada yang perlu disimpen' : notes.join(', '));
                      } catch (e) {
                        toast('$e', error: true);
                      }
                    },
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('Refleksi sesi sekarang'),
                  ),
                ),
              ]),
            ),
          ],
        ),
      );
}

// ----------------------------------------------------------------- Skills
const _skillTemplate = '''---
name: nama-skill
description: Kapan skill ini dipakai (agent baca ini buat mutusin)
---
# Judul

1. Langkah pertama
2. Langkah kedua
''';

class _SkillsTab extends StatelessWidget {
  const _SkillsTab();

  Future<void> _import(BuildContext context) async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    try {
      final name = await Brain.i.saveSkill(utf8.decode(await files.first.readAsBytes()));
      toast('Skill "$name" masuk');
    } catch (e) {
      toast('$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Brain.i,
        builder: (context, _) {
          final skills = Brain.i.skills;
          final pb = Brain.i.active;
          final changed = skills.where(pb.isModified).length, gone = pb.missingBuiltins.length;
          return Stack(children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Text('Prosedur yang bisa dipanggil agent (atau lu lewat /nama-skill di chat). Agent bisa bikin & benerin skill sendiri — '
                    'kecuali skill BAWAAN: itu cuma lu yang bisa ubah.',
                    style: TextStyle(color: C.muted, fontSize: 13)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => openSkillPush(context),
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: const Text('Push ke Hermes'),
                  ),
                ),
                if (changed + gone > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.restore_rounded, color: C.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            'Skill bawaan: ${[if (changed > 0) '$changed diubah', if (gone > 0) '$gone kehapus'].join(', ')}',
                            style: const TextStyle(fontSize: 13)),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (!await confirm(context, 'Kembaliin skill bawaan?',
                              'Semua skill bawaan balik ke versi asli dari app. Skill buatan lu/agent ga kesentuh.', ok: 'Kembaliin')) {
                            return;
                          }
                          final n = await pb.resetAllBuiltins();
                          toast('$n skill bawaan dikembaliin');
                        },
                        child: const Text('Kembaliin default'),
                      ),
                    ]),
                  ),
                const SizedBox(height: 12),
                for (var i = 0; i < skills.length; i++)
                  StaggerIn(
                    index: i,
                    child: Pressable(
                      scale: 0.98,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SkillEditor(skill: skills[i]))),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.stroke)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(gradient: C.hostGradient(i), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(
                                    child: Text('/${skills[i].name}',
                                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: monoFont, fontWeight: FontWeight.w700))),
                                if (pb.isBuiltin(skills[i].name)) ...[
                                  const SizedBox(width: 6),
                                  _Tag(pb.isModified(skills[i]) ? 'bawaan · diubah' : 'bawaan', pb.isModified(skills[i]) ? C.amber : C.cyan),
                                ],
                              ]),
                              const SizedBox(height: 3),
                              Text(skills[i].description,
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12.5)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                TextButton.icon(onPressed: () => _import(context), icon: const Icon(Icons.file_open_rounded), label: const Text('Import SKILL.md dari file')),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 24,
              child: SafeArea(
                child: Pressable(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SkillEditor())),
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(18)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_rounded, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Skill baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}

class SkillEditor extends StatefulWidget {
  const SkillEditor({super.key, this.skill});
  final Skill? skill;

  @override
  State<SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends State<SkillEditor> {
  late final _ctl = TextEditingController(text: widget.skill?.raw ?? _skillTemplate);
  final _undo = UndoHistoryController();

  Future<void> _save() async {
    try {
      final old = widget.skill?.name;
      final name = await Brain.i.saveSkill(_ctl.text);
      if (old != null && old != name) await Brain.i.deleteSkill(old);
      if (mounted) Navigator.pop(context);
      toast('Skill "$name" kesimpen');
    } catch (e) {
      toast('$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.skill == null ? 'Skill baru' : '/${widget.skill!.name}'),
          actions: [
            if (widget.skill != null) ...[
              if (Brain.i.active.isModified(widget.skill!))
                IconButton(
                  tooltip: 'Kembaliin ke bawaan',
                  icon: const Icon(Icons.restore_rounded, color: C.amber),
                  onPressed: () async {
                    if (!await confirm(context, 'Kembaliin ke bawaan?', 'Perubahan lu di /${widget.skill!.name} bakal ilang.', ok: 'Kembaliin')) return;
                    await Brain.i.active.resetSkill(widget.skill!.name);
                    if (context.mounted) Navigator.pop(context);
                    toast('/${widget.skill!.name} balik ke versi bawaan');
                  },
                ),
              IconButton(
                tooltip: 'Push ke Hermes',
                icon: const Icon(Icons.cloud_upload_rounded),
                onPressed: () => openSkillPush(context, only: widget.skill!.name),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _ctl.text));
                  toast('SKILL.md ke-copy');
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: C.red),
                onPressed: () async {
                  if (await confirm(context, 'Hapus skill?', '/${widget.skill!.name} bakal hilang.')) {
                    await Brain.i.deleteSkill(widget.skill!.name);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
            IconButton(icon: const Icon(Icons.save_rounded, color: C.cyan), onPressed: _save),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(children: [
            if (widget.skill != null && Brain.i.active.isBuiltin(widget.skill!.name))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                color: C.cyan.withValues(alpha: 0.08),
                child: Text('Skill bawaan — agent cuma bisa baca. Lu bebas edit; tombol ↺ buat balik ke versi asli.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
              ),
            Expanded(child: CodeEditor(controller: _ctl, undo: _undo)),
          ]),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );
}

// ------------------------------------------------------------------- Jobs
class _JobsTab extends StatelessWidget {
  const _JobsTab();

  Future<void> _edit(BuildContext context, [CronJob? j]) async {
    final name = TextEditingController(text: j?.name);
    final prompt = TextEditingController(text: j?.prompt);
    var daily = j?.dailyAt != null;
    var every = j?.everyMinutes ?? 60;
    var time = j?.dailyAt ?? '07:00';
    var risky = j?.allowRisky ?? false;
    await showSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(j == null ? 'Jadwal baru' : 'Edit jadwal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(controller: name, decoration: const InputDecoration(hintText: 'Nama, mis. Cek server pagi')),
              const SizedBox(height: 10),
              TextField(
                controller: prompt,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Instruksi buat agent, mis. "Cek disk & RAM semua server, kasih tau kalau ada yang > 85%"'),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Interval')), ButtonSegment(value: true, label: Text('Harian'))],
                selected: {daily},
                onSelectionChanged: (v) => set(() => daily = v.first),
              ),
              const SizedBox(height: 10),
              if (!daily)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in [15, 30, 60, 180, 360, 720])
                    ChoiceChip(
                      label: Text(m < 60 ? '$m mnt' : '${m ~/ 60} jam'),
                      selected: every == m,
                      onSelected: (_) => set(() => every = m),
                    ),
                ])
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time_rounded),
                  label: Text('Jam $time'),
                  onPressed: () async {
                    final p = time.split(':');
                    final t = await showTimePicker(
                        context: c, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
                    if (t != null) {
                      set(() => time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                    }
                  },
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: risky,
                onChanged: (v) => set(() => risky = v),
                title: const Text('Izinin aksi berisiko'),
                subtitle: Text('Jalan tanpa lu, jadi ga bisa nanya. Matiin = aksi berisiko otomatis ditolak.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
              ),
              const SizedBox(height: 10),
              GradientButton(
                label: 'Simpan',
                onTap: () async {
                  if (prompt.text.trim().isEmpty) return;
                  final job = j ?? CronJob(id: newId(), name: '', prompt: '');
                  job
                    ..name = name.text.trim().isEmpty ? 'Tugas' : name.text.trim()
                    ..prompt = prompt.text.trim()
                    ..everyMinutes = daily ? null : every
                    ..dailyAt = daily ? time : null
                    ..allowRisky = risky;
                  if (j == null) Brain.i.jobs.add(job);
                  await Brain.i.saveJobs();
                  if (c.mounted) Navigator.pop(c);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Brain.i,
        builder: (context, _) {
          final jobs = Brain.i.jobs;
          return Stack(children: [
            jobs.isEmpty
                ? const EmptyState(
                    icon: Icons.schedule_rounded,
                    title: 'Belum ada jadwal',
                    subtitle: 'Suruh agent kerja otomatis, mis. cek server tiap pagi.\nBisa juga minta langsung di chat: "tiap jam 7 cek disk VPS".')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      Text('Jalan selama app/servis background nyala. Hasilnya masuk ke sesi ⏰ di daftar sesi.',
                          style: TextStyle(color: C.muted, fontSize: 13)),
                      const SizedBox(height: 12),
                      for (final j in jobs)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.stroke)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(Icons.schedule_rounded, color: j.enabled ? C.cyan : C.muted, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(j.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                              Switch(
                                value: j.enabled,
                                onChanged: (v) {
                                  j.enabled = v;
                                  Brain.i.saveJobs();
                                },
                              ),
                            ]),
                            Text(j.prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13)),
                            const SizedBox(height: 8),
                            Text(
                                '${j.scheduleLabel} · berikutnya ${j.nextRun().toString().substring(5, 16)}${j.allowRisky ? ' · aksi berisiko ON' : ''}',
                                style: TextStyle(fontFamily: monoFont, fontSize: 11.5, color: C.muted)),
                            if (j.lastResult.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('Terakhir: ${j.lastResult}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: j.lastResult.startsWith('GAGAL') ? C.red : C.text)),
                              if (j.lastResult.startsWith('GAGAL'))
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: C.red, visualDensity: VisualDensity.compact),
                                  onPressed: () => openErrorLog(context),
                                  icon: const Icon(Icons.bug_report_rounded, size: 16),
                                  label: const Text('Lihat log error'),
                                ),
                            ],
                            Row(children: [
                              TextButton.icon(
                                onPressed: () {
                                  CronRunner.i.run(j);
                                  toast('Jalan di background…');
                                },
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Jalanin'),
                              ),
                              if (j.sessionId != null)
                                TextButton(
                                  onPressed: () {
                                    AgentController.i.openSession(j.sessionId!);
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Lihat hasil'),
                                ),
                              const Spacer(),
                              IconButton(icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => _edit(context, j)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: C.red),
                                onPressed: () async {
                                  if (await confirm(context, 'Hapus jadwal?', j.name)) {
                                    Brain.i.jobs.remove(j);
                                    await Brain.i.saveJobs();
                                  }
                                },
                              ),
                            ]),
                          ]),
                        ),
                    ],
                  ),
            Positioned(
              right: 20,
              bottom: 24,
              child: SafeArea(
                child: Pressable(
                  onTap: () => _edit(context),
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(18)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_alarm_rounded, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Jadwal baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}
