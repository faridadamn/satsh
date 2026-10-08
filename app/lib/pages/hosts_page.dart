import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../ssh_manager.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'host_edit_page.dart';
import 'settings_page.dart';
import 'sftp_page.dart';
import 'terminal_page.dart';

void openTerminal(BuildContext context, Host h) {
  final s = SshManager.i.openTerminal(h);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TerminalPage(session: s)));
}

class HostsPage extends StatefulWidget {
  const HostsPage({super.key});

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> {
  final _quick = TextEditingController();
  String _q = '';

  void _quickConnect() {
    final h = Host.parse(_quick.text, newId());
    if (h == null) {
      toast('Format: user@host:port', error: true);
      return;
    }
    // Reuse a saved host with the same address if there is one.
    final saved = Store.i.hosts
        .where((e) => e.host == h.host && e.port == h.port && e.username == h.username)
        .firstOrNull;
    _quick.clear();
    FocusScope.of(context).unfocus();
    if (saved != null) {
      openTerminal(context, saved);
      return;
    }
    h.color = Store.i.hosts.length;
    Store.i.saveHost(h);
    openTerminal(context, h);
  }

  void _hostMenu(Host h) {
    showSheet(
      useSafeArea: true,
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(children: [
              _Avatar(h: h, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(h.address, style: TextStyle(color: C.muted, fontFamily: monoFont, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          _SheetItem(Icons.terminal_rounded, 'Buka terminal', () {
            Navigator.pop(c);
            openTerminal(context, h);
          }),
          _SheetItem(Icons.folder_open_rounded, 'File (SFTP)', () {
            Navigator.pop(c);
            Navigator.push(context, MaterialPageRoute(builder: (_) => SftpPage(host: h)));
          }),
          _SheetItem(Icons.edit_rounded, 'Edit', () {
            Navigator.pop(c);
            Navigator.push(context, MaterialPageRoute(builder: (_) => HostEditPage(host: h)));
          }),
          _SheetItem(Icons.copy_rounded, 'Copy "ssh ${h.address}"', () {
            Clipboard.setData(ClipboardData(text: 'ssh ${h.username}@${h.host} -p ${h.port}'));
            Navigator.pop(c);
            toast('Ke-copy');
          }),
          if (SshManager.i.isConnected(h.id))
            _SheetItem(Icons.link_off_rounded, 'Putusin koneksi', () {
              SshManager.i.disconnect(h.id);
              Navigator.pop(c);
            }),
          _SheetItem(Icons.delete_outline_rounded, 'Hapus', () async {
            Navigator.pop(c);
            if (await confirm(context, 'Hapus ${h.label}?', 'Password & key yang tersimpan ikut kehapus.')) {
              SshManager.i.disconnect(h.id);
              Store.i.deleteHost(h.id);
            }
          }, color: C.red),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Store.i, SshManager.i]),
      builder: (context, _) {
        final hosts = Store.i.hostsSorted
            .where((h) =>
                _q.isEmpty ||
                h.label.toLowerCase().contains(_q) ||
                h.host.toLowerCase().contains(_q))
            .toList();
        final sessions = SshManager.i.sessions;
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(children: [
                    const GradientText('satsh',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: C.surface2, borderRadius: BorderRadius.circular(8)),
                      child: Text('sat-set ssh', style: TextStyle(fontSize: 11, color: C.muted)),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.settings_rounded, color: C.muted),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                    ),
                    const SizedBox(width: 4),
                    Pressable(
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const HostEditPage())),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.add_rounded, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            // Quick connect
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: TextField(
                  controller: _quick,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _quickConnect(),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  style: const TextStyle(fontFamily: monoFont, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'root@192.168.1.10:22  —  atau cari host',
                    prefixIcon: const Icon(Icons.bolt_rounded, color: C.cyan),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: _quickConnect,
                    ),
                  ),
                ),
              ),
            ),
            if (sessions.isNotEmpty) ...[
              const _Header('Lagi jalan'),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _SessionChip(s: sessions[i]),
                  ),
                ),
              ),
            ],
            _Header(hosts.isEmpty ? '' : 'Host (${hosts.length})'),
            if (Store.i.hosts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.dns_rounded,
                  title: 'Belum ada server',
                  subtitle: 'Ketik user@ip di atas buat langsung masuk,\natau tap + buat nyimpen host.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => StaggerIn(
                      index: i,
                      child: _HostCard(
                        h: hosts[i],
                        connected: SshManager.i.isConnected(hosts[i].id),
                        onTap: () => openTerminal(context, hosts[i]),
                        onLong: () => _hostMenu(hosts[i]),
                      ),
                    ),
                    childCount: hosts.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 20, 10),
          child: Text(text.toUpperCase(),
              style: TextStyle(color: C.muted, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.h, this.size = 40});
  final Host h;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = (h.label.isEmpty ? h.host : h.label).characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: C.hostGradient(h.color), borderRadius: BorderRadius.circular(size * 0.32)),
      alignment: Alignment.center,
      child: Text(letter,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.45)),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.h, required this.connected, required this.onTap, required this.onLong});
  final Host h;
  final bool connected;
  final VoidCallback onTap;
  final VoidCallback onLong;

  @override
  Widget build(BuildContext context) {
    final g = C.hostGradients[h.color % C.hostGradients.length];
    return Pressable(
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: C.stroke),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [g[0].withValues(alpha: 0.18), C.surface, C.surface],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Avatar(h: h),
            const Spacer(),
            if (connected) const StatusDot(ConnState.ready),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onLong,
              child: Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.more_horiz_rounded, color: C.muted),
              ),
            ),
          ]),
          const Spacer(),
          Text(h.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(h.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: C.muted, fontSize: 11.5, fontFamily: monoFont)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(h.auth == 'key' ? Icons.key_rounded : Icons.password_rounded, size: 14, color: g[1]),
            const SizedBox(width: 4),
            Text(h.auth == 'key' ? 'key' : 'password', style: TextStyle(fontSize: 11, color: g[1])),
            if (h.startup.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.play_arrow_rounded, size: 14, color: g[0]),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _SessionChip extends StatelessWidget {
  const _SessionChip({required this.s});
  final TermSession s;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) => Pressable(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TerminalPage(session: s))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.stroke),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              StatusDot(s.state),
              const SizedBox(width: 10),
              Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => SshManager.i.closeSession(s),
                child: Icon(Icons.close_rounded, size: 16, color: C.muted),
              ),
            ]),
          ),
        ),
      );
}

class _SheetItem extends StatelessWidget {
  const _SheetItem(this.icon, this.label, this.onTap, {this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: Icon(icon, color: color ?? C.text),
        title: Text(label, style: TextStyle(color: color ?? C.text, fontWeight: FontWeight.w500)),
        onTap: onTap,
      );
}
