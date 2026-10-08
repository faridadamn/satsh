import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../browser.dart';
import '../theme.dart';
import '../widgets.dart';

/// Live view of the agent's research browser, shown on top of the chat.
class BrowserPanel extends StatelessWidget {
  const BrowserPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final b = ResearchBrowser.i;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) {
        if (!b.active) return const SizedBox.shrink();
        final h = MediaQuery.of(context).size.height;
        final c = b.controller;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.cyan.withValues(alpha: 0.45)),
            boxShadow: [BoxShadow(color: C.cyan.withValues(alpha: 0.12), blurRadius: 20)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 2, 4),
              child: Row(children: [
                const Icon(Icons.travel_explore_rounded, size: 18, color: C.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      b.title.isEmpty ? 'Browser agen' : b.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      b.action.isEmpty ? b.url : b.action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: C.muted, fontSize: 11, fontFamily: monoFont),
                    ),
                  ]),
                ),
                IconButton(
                  tooltip: 'Sumber yang dibuka',
                  visualDensity: VisualDensity.compact,
                  icon: Badge(
                    isLabelVisible: b.trail.isNotEmpty,
                    label: Text('${b.trail.length}'),
                    backgroundColor: C.violet,
                    child: const Icon(Icons.link_rounded, size: 20),
                  ),
                  onPressed: () => _sources(context),
                ),
                IconButton(
                  tooltip: b.expanded ? 'Kecilin' : 'Gedein',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(b.expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded, size: 20),
                  onPressed: b.toggleExpanded,
                ),
                IconButton(
                  tooltip: 'Hapus data browser (logout semua sesi)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Hapus data browser?'),
                        content: const Text('Cookies, cache, dan data situs dihapus. Semua sesi login di browser ini berakhir.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
                          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Hapus')),
                        ],
                      ),
                    );
                    if (ok == true) await b.clearData();
                  },
                ),
                IconButton(
                  tooltip: 'Tutup browser',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: b.close,
                ),
              ]),
            ),
            if (b.tabs.length > 1)
              SizedBox(
                height: 34,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(10, 0, 10, 6), children: [
                  for (final (k, t) in b.tabs.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => b.switchTab(k + 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          constraints: const BoxConstraints(maxWidth: 150),
                          decoration: BoxDecoration(
                            color: k == b.cur ? C.cyan.withValues(alpha: 0.2) : C.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: k == b.cur ? C.cyan : Colors.transparent),
                          ),
                          child: Text('${k + 1}. ${t.title.isEmpty ? (Uri.tryParse(t.url)?.host ?? '…') : t.title}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: k == b.cur ? C.text : C.muted)),
                        ),
                      ),
                    ),
                ]),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              height: b.expanded ? h * 0.55 : 190,
              color: Colors.white,
              child: c == null
                  ? Center(child: Text(b.url, style: const TextStyle(color: Colors.black54, fontSize: 12)))
                  : WebViewWidget(key: ObjectKey(c), controller: c),
            ),
          ]),
        );
      },
    );
  }

  void _sources(BuildContext context) {
    final b = ResearchBrowser.i;
    showSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text('Jejak browsing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (b.trail.isEmpty)
            Padding(padding: const EdgeInsets.all(12), child: Text('Belum ada halaman.', style: TextStyle(color: C.muted))),
          for (final (i, v) in b.trail.reversed.indexed)
            ListTile(
              dense: true,
              leading: Text('${b.trail.length - i}', style: TextStyle(color: C.muted, fontFamily: monoFont)),
              title: Text(v.title.isEmpty ? v.url : v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(v.url,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 11, fontFamily: monoFont)),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => launchUrl(Uri.parse(v.url), mode: LaunchMode.externalApplication),
            ),
        ]),
      ),
    );
  }
}
