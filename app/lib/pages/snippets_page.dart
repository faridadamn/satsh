import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class SnippetsPage extends StatelessWidget {
  const SnippetsPage({super.key});

  static Future<void> edit(BuildContext context, [Snippet? s]) async {
    final name = TextEditingController(text: s?.name);
    final cmd = TextEditingController(text: s?.command);
    var auto = s?.autoRun ?? true;
    await showSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s == null ? 'Snippet baru' : 'Edit snippet',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(controller: name, autofocus: s == null, decoration: const InputDecoration(hintText: 'Nama tombol (mis. restart leo)')),
            const SizedBox(height: 10),
            TextField(
              controller: cmd,
              minLines: 2,
              maxLines: 6,
              autocorrect: false,
              style: const TextStyle(fontFamily: monoFont, fontSize: 13),
              decoration: const InputDecoration(hintText: 'perintah, mis. pm2 restart leo && pm2 logs'),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: auto,
              onChanged: (v) => set(() => auto = v),
              title: const Text('Langsung Enter'),
              subtitle: Text('Matiin kalau mau diedit dulu sebelum jalan', style: TextStyle(color: C.muted)),
            ),
            const SizedBox(height: 10),
            GradientButton(
              label: 'Simpan',
              onTap: () {
                if (cmd.text.trim().isEmpty) return;
                Store.i.saveSnippet(Snippet(
                  id: s?.id ?? newId(),
                  name: name.text.trim().isEmpty ? cmd.text.trim().split(' ').first : name.text.trim(),
                  command: cmd.text.trim(),
                  autoRun: auto,
                ));
                Navigator.pop(c);
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final list = Store.i.snippets;
        return SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(children: [
                const Text('Snippet', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
                const Spacer(),
                Pressable(
                  onTap: () => edit(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.add_rounded, color: Colors.white),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Muncul jadi tombol di atas keyboard terminal. Tahan & geser buat ngurutin.',
                  style: TextStyle(color: C.muted)),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.bolt_rounded,
                      title: 'Belum ada snippet',
                      subtitle: 'Simpen perintah yang sering lu ketik, tinggal tap.')
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                      itemCount: list.length,
                      onReorderItem: Store.i.reorderSnippets,
                      proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                      itemBuilder: (_, i) {
                        final s = list[i];
                        return Padding(
                          key: ValueKey(s.id),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: StaggerIn(
                            index: i,
                            child: Dismissible(
                              key: ValueKey('d${s.id}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                decoration: BoxDecoration(color: C.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(18)),
                                child: const Icon(Icons.delete_rounded, color: C.red),
                              ),
                              onDismissed: (_) => Store.i.deleteSnippet(s.id),
                              child: Pressable(
                                scale: 0.98,
                                onTap: () => edit(context, s),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                      color: C.surface,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: C.stroke)),
                                  child: Row(children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [
                                          C.violet.withValues(alpha: 0.3),
                                          C.cyan.withValues(alpha: 0.2)
                                        ]),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(s.autoRun ? Icons.bolt_rounded : Icons.edit_note_rounded, color: C.cyan),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                        const SizedBox(height: 2),
                                        Text(s.command,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: C.muted, fontFamily: monoFont, fontSize: 12)),
                                      ]),
                                    ),
                                    Icon(Icons.drag_indicator_rounded, color: C.muted),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}
