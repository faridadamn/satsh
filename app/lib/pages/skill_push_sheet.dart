import 'package:flutter/material.dart';

import '../agent/brain.dart';
import '../agent/skill_push.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Push skills of the active profile to Hermes on a server, or pull Hermes' own skills in.
Future<void> openSkillPush(BuildContext context, {String? only}) => showSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SkillPushSheet(only: only),
    );

class SkillPushSheet extends StatefulWidget {
  const SkillPushSheet({super.key, this.only});

  /// Pre-select just this skill.
  final String? only;

  @override
  State<SkillPushSheet> createState() => _SkillPushSheetState();
}

class _SkillPushSheetState extends State<SkillPushSheet> {
  Host? _host;
  PushStatus? _st;
  String? _err;
  bool _busy = false;
  final _pick = <String>{};

  List<Skill> get _skills => Brain.i.skills;

  @override
  void initState() {
    super.initState();
    final hosts = Store.i.hosts;
    final last = Store.i.get<String>('skillPushHost', '');
    _host = Store.i.host(last) ?? hosts.firstOrNull;
    if (widget.only != null) _pick.add(widget.only!);
    _load();
  }

  Future<void> _load() async {
    final h = _host;
    if (h == null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final st = await SkillPush.status(h);
      if (!mounted) return;
      setState(() => _st = st);
      if (widget.only == null && _pick.isEmpty) {
        // Pre-tick what's out of date.
        _pick.addAll(_skills.where((s) => st.of(s) != PushState.same).map((s) => s.name));
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    final h = _host!;
    setState(() => _busy = true);
    final ok = <String>[], bad = <String>[];
    for (final s in _skills.where((s) => _pick.contains(s.name))) {
      try {
        await SkillPush.push(h, s);
        ok.add(s.name);
      } catch (e) {
        bad.add('$e');
      }
    }
    Store.i.set('skillPushHost', h.id);
    toast(bad.isEmpty ? '${ok.length} skill ke-push ke Hermes · kepakai di sesi Hermes berikutnya' : bad.join('\n'), error: bad.isNotEmpty);
    _pick.clear();
    await _load();
  }

  Future<void> _pull(RemoteSkill r) async {
    try {
      final raw = await SkillPush.pull(_host!, r);
      final name = await Brain.i.saveSkill(raw);
      toast('Skill "$name" ditarik ke ${Brain.i.activeProfile.name}');
      setState(() {});
    } catch (e) {
      toast('$e', error: true);
    }
  }

  Widget _state(PushState s) {
    final (txt, col) = switch (s) {
      PushState.same => ('sinkron', C.green),
      PushState.differs => ('beda', C.amber),
      PushState.missing => ('belum ada', C.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(txt, style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hosts = Store.i.hosts;
    final st = _st;
    final only = st?.onlyRemote(_skills.map((s) => s.name)) ?? const <RemoteSkill>[];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        const Text('Push skill ke Hermes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Skill profil ${Brain.i.activeProfile.emoji} ${Brain.i.activeProfile.name} dikirim lewat SSH ke ~/.hermes/skills/satsh/<nama>/. '
            'Hermes pakai mulai sesi berikutnya. Tool khusus satsh (phone_*, browser_*) ga ada di Hermes — skill yang isinya prosedur shell/CLI paling cocok.',
            style: TextStyle(color: C.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        if (hosts.isEmpty)
          Text('Belum ada host. Tambahin server tempat Hermes jalan dulu di tab Host.', style: TextStyle(color: C.amber))
        else
          DropdownButtonFormField<String>(
            initialValue: _host?.id,
            decoration: const InputDecoration(labelText: 'Server Hermes'),
            items: [for (final h in hosts) DropdownMenuItem(value: h.id, child: Text('${h.label} · ${h.address}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              _host = Store.i.host(v ?? '');
              _st = null;
              _pick.clear();
              _load();
            },
          ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: C.red))),
        if (st != null && !st.hasAgent)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Hermes ga ketemu di ${_host?.label} (~/.hermes ga ada). Pasang Hermes dulu, atau pilih server lain.',
                style: const TextStyle(color: C.amber)),
          ),
        if (st != null && st.hasAgent) ...[
          for (final s in _skills)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _pick.contains(s.name),
              onChanged: _busy ? null : (v) => setState(() => v == true ? _pick.add(s.name) : _pick.remove(s.name)),
              title: Row(children: [
                Flexible(child: Text('/${s.name}', style: const TextStyle(fontFamily: monoFont, fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                _state(st.of(s)),
              ]),
              subtitle: Text(s.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || _pick.isEmpty ? null : _push,
            icon: const Icon(Icons.upload_rounded),
            label: Text('Push ${_pick.length} skill'),
          ),
          if (only.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Cuma ada di Hermes', style: TextStyle(color: C.muted, fontWeight: FontWeight.w700)),
            for (final r in only)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.name, style: const TextStyle(fontFamily: monoFont)),
                subtitle: Text(r.path, style: TextStyle(color: C.muted, fontSize: 11.5)),
                trailing: TextButton.icon(onPressed: _busy ? null : () => _pull(r), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Tarik')),
              ),
          ],
        ],
      ]),
    );
  }
}
