import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../agent/agent_zip.dart';
import '../agent/brain.dart';
import '../widgets.dart';

/// Save the agent brain as a zip (same format as satsh desktop).
Future<void> exportAgentZip(BuildContext context) async {
  var withSessions = false, withJobs = false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Ekspor otak agent (.zip)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Semua profil: soul, memori, skill, plus profil user. Bisa diimpor di satsh HP lain atau satsh desktop (Win 7/10).'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: withSessions,
            onChanged: (v) => set(() => withSessions = v ?? false),
            title: const Text('Ikutin riwayat chat'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: withJobs,
            onChanged: (v) => set(() => withJobs = v ?? false),
            title: const Text('Ikutin jadwal'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ekspor')),
        ],
      ),
    ),
  );
  if (go != true) return;
  try {
    final bytes = await AgentZip.export(Brain.i, sessions: withSessions, jobs: withJobs);
    final d = DateTime.now();
    final name = 'satsh-agent-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.zip';
    final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/zip');
    if (uri != null) toast('Kesimpen: $name');
  } catch (e) {
    toast('Gagal ekspor: $e', error: true);
  }
}

/// Merge a satsh-agent zip in (from phone or desktop).
Future<void> importAgentZip(BuildContext context) async {
  try {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final summary = await AgentZip.import(Brain.i, await files.first.readAsBytes());
    AgentController.i.refresh();
    toast('Impor beres — $summary');
  } catch (e) {
    toast('Gagal impor: $e', error: true);
  }
}
