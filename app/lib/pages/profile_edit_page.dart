import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../agent/brain.dart';
import '../agent/providers.dart';
import '../theme.dart';
import '../widgets.dart';
import 'brain_page.dart';

const profileEmojis = ['⚡', '🤖', '🧠', '🛠️', '🛵', '💼', '🎬', '🎨', '📈', '🧾', '🌙', '🦊', '🚀', '📚'];

const _groups = [
  ('phone', 'File HP'),
  ('device', 'Clipboard, URL, info HP'),
  ('ssh', 'Server SSH'),
  ('supabase', 'Supabase'),
  ('web', 'HTTP GET'),
  ('browser', 'Browser agen'),
  ('control', 'Kontrol app lain'),
];

/// Name, look, model and tools of one agent profile.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.id});
  final String id;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final AgentProfile p = Brain.i.profile(widget.id)!;
  late final _name = TextEditingController(text: p.name);
  late final _desc = TextEditingController(text: p.desc);

  Future<void> _save() async {
    p
      ..name = _name.text.trim().isEmpty ? p.name : _name.text.trim()
      ..desc = _desc.text.trim();
    await Brain.i.saveProfiles();
  }

  Future<void> _openBrain() async {
    await _save();
    await AgentController.i.switchProfile(p.id);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BrainPage()));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Hapus profil ${p.name}?'),
        content: const Text('Soul, memori & skill profil ini dihapus. Riwayat chat-nya pindah ke profil utama.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus', style: TextStyle(color: C.red))),
        ],
      ),
    );
    if (ok != true) return;
    await Brain.i.deleteProfile(p.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final providers = Providers.all().where((x) => !x.isExternal).toList();
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: Scaffold(
        appBar: AppBar(title: Text('${p.emoji} ${p.name}')),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in profileEmojis)
              ChoiceChip(
                label: Text(e, style: const TextStyle(fontSize: 18)),
                selected: p.emoji == e,
                onSelected: (_) => setState(() => p.emoji = e),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama')),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Buat apa (opsional)', hintText: 'mis. ngurus server Payu'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: providers.any((x) => x.id == p.provider) ? p.provider : '',
            decoration: const InputDecoration(labelText: 'Model utama'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Ikut urutan provider')),
              for (final x in providers) DropdownMenuItem(value: x.id, child: Text('${x.name} · ${x.model}')),
            ],
            onChanged: (v) => setState(() => p.provider = v ?? ''),
          ),
          const SizedBox(height: 16),
          Text('Tools yang boleh dipakai profil ini', style: TextStyle(color: C.muted, fontSize: 13)),
          for (final g in _groups)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(g.$2),
              value: !p.toolsOff.contains(g.$1),
              onChanged: (v) => setState(() => v ? p.toolsOff.remove(g.$1) : p.toolsOff.add(g.$1)),
            ),
          const SizedBox(height: 12),
          GradientButton(label: 'Atur soul, memori & skill', icon: Icons.psychology_rounded, onTap: _openBrain),
          if (p.id != 'default') ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: C.red),
              label: const Text('Hapus profil', style: TextStyle(color: C.red)),
            ),
          ],
        ]),
      ),
    );
  }
}
