import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../agent/agent.dart';
import '../error_log.dart';
import '../theme.dart';
import '../widgets.dart';

void openErrorLog(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ErrorLogPage()));

/// Every captured crash/bug with its stack trace — copy or send it as a bug report.
class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({super.key});

  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  final _open = <int>{};

  Future<void> _send() async {
    try {
      final f = await ErrorLog.i.reportFile();
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Log error satsh $appVersion'));
    } catch (e) {
      toast('Gagal kirim: $e', error: true);
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: ErrorLog.i.report()));
    toast('Log disalin — tempel ke chat buat lapor bug');
  }

  void _askAgent() {
    final last = ErrorLog.i.entries.reversed.take(3).map((e) => e.toText()).join('\n---\n');
    Navigator.pop(context);
    AgentController.i.newChat();
    AgentController.i.send('Tolong baca log error satsh ini dan jelasin kira-kira apa penyebabnya (bug app, provider, atau jaringan) '
        'dan apa yang bisa gw lakuin sekarang:\n\n```\n$last\n```');
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus semua log?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus', style: TextStyle(color: C.red))),
        ],
      ),
    );
    if (ok == true) await ErrorLog.i.clear();
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'barusan';
    if (d.inHours < 1) return '${d.inMinutes} mnt lalu';
    if (d.inDays < 1) return '${d.inHours} jam lalu';
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  static const _labels = {
    'agent': ('Agent', Icons.auto_awesome_rounded),
    'cron': ('Jadwal', Icons.schedule_rounded),
    'tool': ('Tool', Icons.build_rounded),
    'llm': ('Provider AI', Icons.cloud_rounded),
    'flutter': ('Tampilan', Icons.phone_android_rounded),
    'async': ('Latar', Icons.bug_report_rounded),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ErrorLog.i,
        builder: (context, _) {
          final list = ErrorLog.i.entries.reversed.toList();
          return Scaffold(
            appBar: AppBar(
              title: const Text('Log error'),
              actions: [
                if (list.isNotEmpty) IconButton(tooltip: 'Hapus semua', onPressed: _clear, icon: const Icon(Icons.delete_sweep_rounded)),
              ],
            ),
            body: list.isEmpty
                ? const EmptyState(icon: Icons.verified_rounded, title: 'Belum ada error', subtitle: 'Kalau ada yang crash atau gagal aneh, detailnya muncul di sini.')
                : ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 120), children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                      child: Text('${list.length} error · versi $appVersion. Kirim log ke yang benerin app biar ketahuan baris kodenya.',
                          style: TextStyle(color: C.muted, fontSize: 12.5)),
                    ),
                    for (final (k, e) in list.indexed)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(_labels[e.source]?.$2 ?? Icons.error_outline_rounded, size: 16, color: C.red),
                                const SizedBox(width: 6),
                                Text(_labels[e.source]?.$1 ?? e.source, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                if (e.context['jadwal'] ?? e.context['tool'] case final String w) ...[
                                  Text(' · ', style: TextStyle(color: C.muted)),
                                  Flexible(child: Text(w, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13))),
                                ],
                                const Spacer(),
                                Text(_when(e.time), style: TextStyle(color: C.muted, fontSize: 12)),
                              ]),
                              const SizedBox(height: 6),
                              Text(e.message, maxLines: _open.contains(k) ? null : 2, overflow: _open.contains(k) ? null : TextOverflow.ellipsis),
                              if (_open.contains(k)) ...[
                                const SizedBox(height: 8),
                                for (final c in e.context.entries)
                                  Text('${c.key}: ${c.value}', style: TextStyle(color: C.muted, fontSize: 12)),
                                if (e.stack.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SelectableText(e.stack, style: TextStyle(fontFamily: monoFont, fontSize: 11, color: C.text)),
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: e.toText()));
                                      toast('Error ini disalin');
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 16),
                                    label: const Text('Salin'),
                                  ),
                                ),
                              ],
                            ]),
                          ),
                        ),
                      ),
                  ]),
            bottomNavigationBar: list.isEmpty
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)), onPressed: _copy, icon: const Icon(Icons.copy_all_rounded), label: const Text('Salin')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)), onPressed: _askAgent, icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Tanya')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)), onPressed: _send, icon: const Icon(Icons.send_rounded), label: const Text('Kirim')),
                        ),
                      ]),
                    ),
                  ),
          );
        },
      );
}
