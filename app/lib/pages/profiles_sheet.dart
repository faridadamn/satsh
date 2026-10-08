import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../agent/brain.dart';
import '../agent/presets.dart';
import '../agent/providers.dart';
import '../vision.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_zip_ui.dart';
import 'profile_edit_page.dart';

Future<void> showProfiles(BuildContext context) => showSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
        child: const ProfilesSheet(),
      ),
    );

class ProfilesSheet extends StatelessWidget {
  const ProfilesSheet({super.key});

  static String _model(String pref) {
    final all = Providers.all().where((x) => !x.disabled && !x.isExternal);
    final p = all.where((x) => x.id == pref).firstOrNull ?? all.firstOrNull;
    if (p == null) return 'belum ada provider';
    return p.model.isEmpty ? p.name : p.model;
  }

  /// Screenshots of a thread/post/repo → the agent designs a new profile from them.
  Future<void> _fromImages(BuildContext context) async {
    final a = AgentController.i;
    if (a.busy) return;
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final imgs = <String>[];
    for (final f in files.take(8)) {
      try {
        final j = await Vision.jpeg(bytes: await f.readAsBytes(), maxW: 1400);
        imgs.add(await Vision.save(j.bytes, 'agentref'));
      } catch (e) {
        toast('Gambar ${f.name} ga kebaca: $e', error: true);
      }
    }
    if (imgs.isEmpty || !context.mounted) return;
    Navigator.pop(context);
    a.newChat();
    a.send(
      'Bikinin profil agent baru berdasarkan ${imgs.length} gambar ini (screenshot thread/postingan/repo soal cara kerja agent yang gw mau). '
      'Baca semua isinya, buka link/repo yang disebut kalau perlu, tanya gw kalau ada yang bener-bener belum jelas, '
      'terus bikin pakai tool agent_profile: soul yang jelas, skill dari aturan/prosedurnya, memori berisi link referensinya, '
      'dan matiin tools yang ga kepake. Kasih tau ringkasannya.',
      images: imgs,
    );
  }

  Future<void> _preset(BuildContext context, String id) async {
    try {
      final p = await Brain.i.installPreset(await Presets.load(id));
      await AgentController.i.switchProfile(p.id);
      toast('${p.emoji} ${p.name} kepasang');
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      toast('Gagal pasang preset: $e', error: true);
    }
  }

  Future<void> _add(BuildContext context) async {
    final name = await askText(context, 'Nama profil baru');
    if (name == null || name.trim().isEmpty) return;
    final p = await Brain.i.createProfile(name.trim(), copyFrom: Brain.i.activeId);
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditPage(id: p.id)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Brain.i,
        builder: (context, _) {
          final b = Brain.i;
          return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text('Profil agent', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            for (final p in b.profiles)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                selected: p.id == b.activeId,
                selectedTileColor: C.violet.withValues(alpha: 0.12),
                leading: Text(p.emoji, style: const TextStyle(fontSize: 24)),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [if (p.desc.isNotEmpty) p.desc, _model(p.provider)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: C.muted),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditPage(id: p.id))),
                ),
                onTap: () async {
                  await AgentController.i.switchProfile(p.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline_rounded, color: C.cyan),
              title: const Text('Profil baru'),
              subtitle: Text('Mulai dari soul & skill profil yang aktif', style: TextStyle(color: C.muted, fontSize: 12)),
              onTap: () => _add(context),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_rounded, color: C.violet),
              title: const Text('Bikin agent dari gambar'),
              subtitle: Text('Kirim screenshot thread / postingan / repo — agent yang nyusun profilnya',
                  style: TextStyle(color: C.muted, fontSize: 12)),
              onTap: () => _fromImages(context),
            ),
            for (final id in Presets.ids.where((id) => b.profile(id) == null))
              ListTile(
                leading: const Icon(Icons.auto_awesome_motion_rounded, color: C.cyan),
                title: Text('Pasang preset: ${Presets.names[id] ?? id}', maxLines: 2),
                onTap: () => _preset(context, id),
              ),
            const Divider(),
            Row(children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => exportAgentZip(context),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Ekspor zip'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => importAgentZip(context),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Impor zip'),
                ),
              ),
            ]),
          ]);
        },
      );
}
