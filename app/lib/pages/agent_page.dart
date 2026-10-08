import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agent/mission.dart';
import 'missions_page.dart';
import '../agent/agent.dart';
import '../agent/brain.dart';
import '../agent/llm.dart';
import '../agent/tools.dart';
import '../store.dart';
import '../theme.dart';
import '../md_blocks.dart';
import '../vision.dart';
import '../native.dart';
import '../redact.dart';
import 'browser_panel.dart';
import '../widgets.dart';
import 'file_viewer_page.dart';
import 'brain_page.dart';
import 'profiles_sheet.dart';
import 'error_log_page.dart';
import 'settings_page.dart';

Future<String> askApproval(BuildContext context, AgentTool tool, Map<String, dynamic> args) async {
  HapticFeedback.heavyImpact();
  final pretty = const JsonEncoder.withIndent('  ').convert(Redact.args(args));
  final r = await showSheet<String>(
      useSafeArea: true,
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.shield_rounded, color: C.amber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Agent minta izin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(tool.spec.name, style: TextStyle(color: C.muted, fontFamily: monoFont, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
              child: SingleChildScrollView(
                child: SelectableText(pretty, style: TextStyle(fontFamily: monoFont, fontSize: 12, color: C.text)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () => Navigator.pop(c, 'no'),
                child: const Text('Tolak', style: TextStyle(color: C.red)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: GradientButton(label: 'Izinin', icon: Icons.check_rounded, onTap: () => Navigator.pop(c, 'yes'))),
          ]),
          TextButton(onPressed: () => Navigator.pop(c, 'all'), child: Text('Izinin semua di chat ini', style: TextStyle(color: C.muted))),
        ]),
      ),
    ),
  );
  return r ?? 'no';
}

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  AgentController get a => AgentController.i;

  static const _ideas = [
    'Cek disk, RAM, dan uptime semua server gw',
    'Cari file PDF terbaru di folder Download',
    'Ada proses apa yang makan CPU paling gede di VPS?',
    'Rangkum isi file catatan.md di HP',
    'Riset harga hosting murah di Indonesia, bandingin 3 teratas + link sumbernya',
  ];

  @override
  void initState() {
    super.initState();
    a.addListener(_toBottom);
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    a.removeListener(_toBottom);
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  final List<String> _pending = [];
  bool _picking = false;

  void _send([String? t]) {
    final text = t ?? _input.text;
    if (text.trim().isEmpty && _pending.isEmpty) return;
    if (a.busy) return;
    final imgs = List<String>.of(_pending);
    _input.clear();
    setState(_pending.clear);
    HapticFeedback.lightImpact();
    a.send(text, images: imgs);
  }

  Future<void> _attach() async {
    if (_picking) return;
    final src = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: C.cyan),
              title: const Text('Kamera'),
              subtitle: Text('Foto langsung', style: TextStyle(color: C.muted, fontSize: 12)),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: C.violet),
              title: const Text('Galeri / file'),
              subtitle: Text('Pilih gambar yang udah ada', style: TextStyle(color: C.muted, fontSize: 12)),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
          ]),
        ),
      ),
    );
    if (src == null) return;
    setState(() => _picking = true);
    try {
      if (src == 'camera') {
        final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 90);
        if (shot != null) {
          final img = await Vision.jpeg(path: shot.path);
          _pending.add(await Vision.save(img.bytes, 'cam'));
          try {
            await File(shot.path).delete();
          } catch (_) {}
        }
      } else {
        final files = await FilePicker.pickFiles(type: FileType.image);
        for (final f in files.take(6)) {
          final img = await Vision.jpeg(bytes: await f.readAsBytes());
          _pending.add(await Vision.save(img.bytes, 'user'));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal ambil gambar: $e')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Talk to the agent; the answer gets read back.
  Future<void> _voice() async {
    if (a.busy) return;
    await Native.stopSpeak().catchError((_) {});
    String? heard;
    try {
      heard = await Native.listen();
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Mic ga bisa dipake')));
      return;
    }
    if (heard == null || heard.trim().isEmpty) return;
    a.speakNext = true;
    _send(heard);
  }



  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([a, Store.i, Brain.i, MissionRunner.i]),
      builder: (context, _) {
        final unread = Brain.i.sessions.where((m) => m.unread).length;
        // tool results indexed by call id
        final results = {for (final m in a.messages.where((m) => m.role == 'tool')) m.callId: m};
        final visible = a.messages.where((m) => m.role != 'tool').toList();
        final todos = a.session.todos;
        return SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 4, 6),
              child: Row(children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Sesi',
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    backgroundColor: C.pink,
                    child: const Icon(Icons.history_rounded),
                  ),
                  onPressed: () => showSessions(context),
                ),
                const GradientText('Agent', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: a.busy ? null : () => showProfiles(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(Brain.i.activeProfile.emoji, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(Brain.i.activeProfile.name,
                                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.muted, fontFamily: monoFont)),
                          ),
                          Icon(Icons.expand_more_rounded, size: 14, color: C.muted),
                        ]),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Chat baru',
                  icon: const Icon(Icons.add_comment_rounded),
                  onPressed: a.busy ? null : a.newChat,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Misi',
                  icon: Badge(
                    isLabelVisible: MissionRunner.i.openAsks > 0,
                    label: Text('${MissionRunner.i.openAsks}'),
                    backgroundColor: C.pink,
                    child: Icon(Icons.rocket_launch_rounded, color: MissionRunner.i.anyActive ? C.green : null),
                  ),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MissionsPage())),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Otak: soul, memori, skill, jadwal',
                  icon: const Icon(Icons.psychology_rounded),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrainPage())),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Pengaturan agent',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage(section: 'agent'))),
                ),
              ]),
            ),
            const BrowserPanel(),
            Expanded(
              child: visible.isEmpty
                  ? ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 20), children: [
                      StaggerIn(
                        index: 0,
                        child: Column(children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(26)),
                            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
                          ),
                          const SizedBox(height: 16),
                          const Text('Mau dibantuin apa?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('Gw bisa ngoprek file HP, jalanin perintah di server lu, dan query Supabase.',
                              textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
                        ]),
                      ),
                      const SizedBox(height: 24),
                      for (var i = 0; i < _ideas.length; i++)
                        StaggerIn(
                          index: i + 1,
                          child: Pressable(
                            scale: 0.98,
                            onTap: () => _send(_ideas[i]),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.stroke)),
                              child: Row(children: [
                                const Icon(Icons.bolt_rounded, color: C.cyan, size: 18),
                                const SizedBox(width: 10),
                                Expanded(child: Text(_ideas[i])),
                              ]),
                            ),
                          ),
                        ),
                    ])
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                      itemCount: visible.length + (a.busy ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == visible.length) return _Thinking(status: Redact.text(a.status), onStop: a.stop);
                        final m = visible[i];
                        if (m.role == 'event') return _EventPill(Redact.text(m.text));
                        return m.role == 'user' ? _UserBubble(m.text, images: m.images) : _AssistantBlock(m: m, results: results);
                      },
                    ),
            ),
            if (todos.isNotEmpty && todos.any((t) => t['status'] != 'done' ) || (todos.isNotEmpty && a.busy)) _TodoCard(todos),
            if (_input.text.startsWith('/') && !_input.text.contains(' ')) _SlashBar(query: _input.text.substring(1), onPick: (v) {
              _input.text = v;
              _input.selection = TextSelection.collapsed(offset: v.length);
            }),
            if (_pending.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(14, 0, 14, 6), children: [
                  for (final p in _pending)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(p), width: 66, height: 66, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _pending.remove(p)),
                            child: Container(
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: Native.speaking,
              builder: (_, talking, _) => !talking
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.volume_off_rounded, size: 16, color: C.cyan),
                        label: const Text('Diem dulu'),
                        onPressed: () => Native.stopSpeak(),
                      ),
                    ),
            ),
            _Composer(
              controller: _input,
              busy: a.busy,
              onSend: _send,
              onStop: a.stop,
              onAttach: _attach,
              onVoice: _voice,
              hasDraft: _input.text.trim().isNotEmpty || _pending.isNotEmpty,
              picking: _picking,
            ),
          ]),
        );
      },
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.raw, {this.images = const []});
  final String raw;
  final List<String> images;

  @override
  Widget build(BuildContext context) {
    var text = raw;
    String? skill;
    final m = RegExp(r'^\[Pakai skill "([^"]+)"\][\s\S]*\nPermintaan user: ([\s\S]*)$').firstMatch(raw);
    if (m != null) {
      skill = m.group(1);
      text = m.group(2)!;
    }
    final cron = RegExp(r'^\[Jadwal "([^"]+)"').firstMatch(raw);
    if (cron != null) skill = '⏰ ${cron.group(1)}';
    return _bubble(context, text, skill);
  }

  Widget _bubble(BuildContext context, String text, String? skill) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            gradient: C.accent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (skill != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                  child: Text(skill.startsWith('⏰') ? skill : '📘 /$skill',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            if (images.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: text.isEmpty ? 0 : 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [for (final p in images) _Thumb(p, size: images.length == 1 ? 180 : 86)]),
              ),
            if (text.isNotEmpty) SelectableText(text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
          ]),
        ),
      );
}

class _EventPill extends StatelessWidget {
  const _EventPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: StaggerIn(
          index: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [C.violet.withValues(alpha: 0.18), C.cyan.withValues(alpha: 0.14)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.text)),
          ),
        ),
      );
}

class _TodoCard extends StatelessWidget {
  const _TodoCard(this.todos);
  final List<Map<String, dynamic>> todos;

  @override
  Widget build(BuildContext context) {
    final done = todos.where((t) => t['status'] == 'done').length;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.stroke)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.checklist_rounded, size: 16, color: C.cyan),
          const SizedBox(width: 6),
          Text('Rencana', style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
          const Spacer(),
          Text('$done/${todos.length}', style: TextStyle(color: C.muted, fontSize: 12, fontFamily: monoFont)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: todos.isEmpty ? 0 : done / todos.length),
            duration: const Duration(milliseconds: 400),
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 4, color: C.cyan, backgroundColor: C.surface2),
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 110),
          child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
            for (final t in todos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(
                    switch (t['status']) {
                      'done' => Icons.check_circle_rounded,
                      'in_progress' => Icons.timelapse_rounded,
                      _ => Icons.radio_button_unchecked_rounded,
                    },
                    size: 15,
                    color: switch (t['status']) { 'done' => C.green, 'in_progress' => C.amber, _ => C.muted },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(Redact.text('${t['content']}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: t['status'] == 'done' ? C.muted : C.text,
                          decoration: t['status'] == 'done' ? TextDecoration.lineThrough : null,
                        )),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _SlashBar extends StatelessWidget {
  const _SlashBar({required this.query, required this.onPick});
  final String query;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('/new', 'chat baru'),
      ('/compress', 'ringkas konteks'),
      for (final s in Brain.i.skills) ('/${s.name}', s.description),
    ].where((e) => e.$1.substring(1).startsWith(query.toLowerCase())).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.stroke)),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
        for (final it in items)
          InkWell(
            onTap: () => onPick(it.$1 == '/new' || it.$1 == '/compress' ? it.$1 : '${it.$1} '),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                Text(it.$1, style: const TextStyle(fontFamily: monoFont, fontWeight: FontWeight.w700, color: C.cyan)),
                const SizedBox(width: 10),
                Expanded(child: Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12))),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Bottom sheet listing sessions with search.
Future<void> showSessions(BuildContext context) => showSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => SizedBox(height: MediaQuery.of(c).size.height * 0.8, child: const _SessionsSheet()),
    );

class _SessionsSheet extends StatefulWidget {
  const _SessionsSheet();

  @override
  State<_SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends State<_SessionsSheet> {
  String _q = '';
  List<Map<String, dynamic>>? _hits;

  Future<void> _search(String q) async {
    setState(() => _q = q);
    if (q.trim().length < 2) {
      setState(() => _hits = null);
      return;
    }
    final h = await Brain.i.searchSessions(q, limit: 20);
    if (mounted && q == _q) setState(() => _hits = h);
  }

  String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'barusan';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}j';
    if (d.inDays < 7) return '${d.inDays}h';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.day}/${t.month}';
  }

  void _open(String id) {
    AgentController.i.openSession(id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Brain.i,
        builder: (context, _) {
          final cur = AgentController.i.session.id;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(children: [
                const Text('Sesi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    AgentController.i.newChat();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Baru'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: _search,
                decoration: const InputDecoration(hintText: 'Cari di semua obrolan…', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _hits != null
                  ? (_hits!.isEmpty
                      ? Center(child: Text('Ga ketemu', style: TextStyle(color: C.muted)))
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
                          for (final h in _hits!)
                            ListTile(
                              title: Text(h['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text((h['snippets'] as List).join('\n'),
                                  maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12)),
                              onTap: () => _open(h['id']),
                            ),
                        ]))
                  : Brain.i.sessions.isEmpty
                      ? Center(child: Text('Belum ada sesi', style: TextStyle(color: C.muted)))
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
                          for (final m in Brain.i.sessions)
                            ListTile(
                              selected: m.id == cur,
                              selectedTileColor: C.violet.withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              leading: Brain.i.profiles.length > 1
                                  ? Text(Brain.i.profile(m.profile)?.emoji ?? '⚡', style: const TextStyle(fontSize: 20))
                                  : Icon(m.cron ? Icons.schedule_rounded : Icons.chat_bubble_outline_rounded,
                                      color: m.unread ? C.pink : C.muted, size: 20),
                              title: Text(m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: m.unread ? FontWeight.w700 : FontWeight.w500)),
                              trailing: Text(_ago(m.updated), style: TextStyle(color: C.muted, fontSize: 12)),
                              onTap: () => _open(m.id),
                              onLongPress: () async {
                                final act = await showSheet<String>(
      useSafeArea: true,
                                  context: context,
                                  builder: (c) => SafeArea(
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Ganti judul'), onTap: () => Navigator.pop(c, 'rename')),
                                      ListTile(
                                          leading: const Icon(Icons.delete_outline_rounded, color: C.red),
                                          title: const Text('Hapus', style: TextStyle(color: C.red)),
                                          onTap: () => Navigator.pop(c, 'delete')),
                                    ]),
                                  ),
                                );
                                if (!context.mounted) return;
                                if (act == 'rename') {
                                  final t = await askText(context, 'Judul sesi', initial: m.title);
                                  if (t != null && t.trim().isNotEmpty) {
                                    if (m.id == cur) {
                                      AgentController.i.session.title = t.trim();
                                      await Brain.i.saveSession(AgentController.i.session);
                                    } else {
                                      await Brain.i.renameSession(m.id, t.trim());
                                    }
                                  }
                                } else if (act == 'delete') {
                                  await Brain.i.deleteSession(m.id);
                                  if (m.id == cur) AgentController.i.newChat();
                                }
                              },
                            ),
                        ]),
            ),
          ]);
        },
      );
}

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({required this.m, required this.results});
  final Msg m;
  final Map<String?, Msg> results;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: m.isError ? C.red.withValues(alpha: 0.12) : C.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: C.stroke),
            ),
            child: MessageBody(Redact.text(m.text)),
          ),
        if (m.isError)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: C.red, visualDensity: VisualDensity.compact),
            onPressed: () => openErrorLog(context),
            icon: const Icon(Icons.bug_report_rounded, size: 16),
            label: const Text('Lihat log error / kirim laporan'),
          ),
        for (final c in m.calls) _ToolChip(call: c, result: results[c.id]),
      ]),
    );
  }
}

class _ToolChip extends StatefulWidget {
  const _ToolChip({required this.call, this.result});
  final ToolCall call;
  final Msg? result;

  @override
  State<_ToolChip> createState() => _ToolChipState();
}

class _ToolChipState extends State<_ToolChip> {
  bool _open = false;

  String get _summary {
    final a = Redact.args(widget.call.args);
    final v = a['command'] ?? a['path'] ?? a['query'] ?? a['table'] ?? a['url'] ?? a['phone_path'] ?? a['text'] ?? a['name'] ?? a['key'] ??
        a['direction'] ?? (a['n'] != null ? '[${a['n']}]' : (a['x'] != null ? '(${a['x']}, ${a['y']})' : ''));
    final host = a['host'] != null ? '${a['host']} · ' : '';
    return '$host$v'.replaceAll('\n', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final color = r == null ? C.amber : (r.isError ? C.red : C.green);
    return Pressable(
      scale: 0.99,
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: C.surface2.withValues(alpha: _open ? 1 : 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            r == null
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                : Icon(r.isError ? Icons.error_rounded : Icons.check_circle_rounded, size: 15, color: color),
            const SizedBox(width: 8),
            Text(widget.call.name, style: TextStyle(fontFamily: monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_summary,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 12, color: C.muted)),
            ),
            Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: C.muted),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      '${const JsonEncoder.withIndent('  ').convert(Redact.args(widget.call.args))}\n\n→ ${r == null ? '…' : Redact.text(r.text)}',
                      style: TextStyle(fontFamily: monoFont, fontSize: 11.5, color: C.text, height: 1.45),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (r != null && r.images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [for (final p in r.images) _Thumb(p, size: _open ? 260 : 120)]),
            ),
        ]),
      ),
    );
  }
}

class _Thinking extends StatefulWidget {
  const _Thinking({required this.status, required this.onStop});
  final String status;
  final VoidCallback onStop;

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              children: List.generate(3, (i) {
                final t = ((_c.value * 3 - i) % 3);
                final up = t < 1 ? (1 - (t - 0.5).abs() * 2) : 0.0;
                return Container(
                  margin: const EdgeInsets.only(right: 4),
                  width: 8,
                  height: 8,
                  transform: Matrix4.translationValues(0, -5 * up, 0),
                  decoration: BoxDecoration(
                      color: Color.lerp(C.violet, C.cyan, i / 2)!.withValues(alpha: 0.5 + 0.5 * up), shape: BoxShape.circle),
                );
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.status, style: TextStyle(color: C.muted, fontSize: 13))),
        ]),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onVoice,
    this.hasDraft = false,
    this.picking = false,
  });
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onAttach;
  final VoidCallback onVoice;
  final bool hasDraft;
  final bool picking;
  final void Function([String?]) onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom > 0;
    return Padding(
      // leave room for the floating nav bar when keyboard is closed
      padding: EdgeInsets.fromLTRB(14, 6, 14, kb ? 10 : 92),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: C.stroke),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
            tooltip: 'Kirim gambar',
            onPressed: busy || picking ? null : onAttach,
            icon: picking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.add_photo_alternate_rounded, color: C.muted),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Suruh agent ngapain…',
                filled: false,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Pressable(
              onTap: busy ? onStop : (hasDraft ? () => onSend() : onVoice),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: busy ? null : C.accent,
                  color: busy ? C.red.withValues(alpha: 0.18) : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    busy ? Icons.stop_rounded : (hasDraft ? Icons.arrow_upward_rounded : Icons.mic_rounded),
                    key: ValueKey('$busy$hasDraft'),
                    color: busy ? C.red : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Tap to view full screen.
class _Thumb extends StatelessWidget {
  const _Thumb(this.path, {this.size = 120});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final f = File(path);
    if (!f.existsSync()) {
      return Container(
        width: size * 0.6,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.broken_image_rounded, size: 18, color: Colors.white54),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: InteractiveViewer(maxScale: 6, child: Center(child: Image.file(f))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: size, maxHeight: size * 1.4),
          child: Image.file(f, fit: BoxFit.cover, cacheWidth: (size * 3).round()),
        ),
      ),
    );
  }
}

void _copy(String text, String what) {
  Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.selectionClick();
  toast('$what disalin');
}

/// Agent answer: prose stays selectable; every code block and quote gets its own copy button.
class MessageBody extends StatelessWidget {
  const MessageBody(this.text, {super.key});
  final String text;

  void _link(String? href) {
    if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = splitBlocks(text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final b in blocks)
        switch (b.kind) {
          'code' => _CodeCard(b),
          'quote' => _QuoteCard(b, onLink: _link),
          _ => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: MarkdownBody(data: b.text, selectable: true, styleSheet: mdStyle(context), onTapLink: (_, h, _) => _link(h)),
            ),
        },
      if (blocks.length > 1 || text.length > 200)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: C.muted),
            onPressed: () => _copy(text, 'Jawaban'),
            icon: const Icon(Icons.copy_all_rounded, size: 16),
            label: const Text('Salin semua', style: TextStyle(fontSize: 12)),
          ),
        ),
    ]);
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard(this.b);
  final MdBlock b;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.stroke)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
            decoration: BoxDecoration(
              color: C.surface2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Text(b.lang.isEmpty ? 'kode' : b.lang, style: TextStyle(fontFamily: monoFont, fontSize: 11.5, color: C.muted)),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: C.cyan),
                onPressed: () => _copy(b.text, 'Kode'),
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Salin', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SelectableText(b.text, style: TextStyle(fontFamily: monoFont, fontSize: 12.5, height: 1.45, color: C.text)),
          ),
        ]),
      );
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard(this.b, {required this.onLink});
  final MdBlock b;
  final void Function(String?) onLink;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
        decoration: BoxDecoration(
          color: C.violet.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: const Border(left: BorderSide(color: C.violet, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: MarkdownBody(data: b.text, selectable: true, styleSheet: mdStyle(context), onTapLink: (_, h, _) => onLink(h)),
          ),
          IconButton(
            tooltip: 'Salin kutipan',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: C.muted,
            onPressed: () => _copy(b.text, 'Kutipan'),
            icon: const Icon(Icons.copy_rounded),
          ),
        ]),
      );
}
