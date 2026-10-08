import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../phone_server.dart';
import 'server_page.dart';
import '../ssh_manager.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class ForwardsPage extends StatelessWidget {
  const ForwardsPage({super.key});

  static Future<void> edit(BuildContext context, [Forward? f]) async {
    if (Store.i.hosts.isEmpty) {
      toast('Tambahin host dulu', error: true);
      return;
    }
    final label = TextEditingController(text: f?.label);
    final local = TextEditingController(text: f == null ? '' : '${f.localPort}');
    final rhost = TextEditingController(text: f?.remoteHost ?? '127.0.0.1');
    final rport = TextEditingController(text: f == null ? '' : '${f.remotePort}');
    var hostId = f?.hostId ?? Store.i.hostsSorted.first.id;
    await showSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(f == null ? 'Tunnel baru' : 'Edit tunnel', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Buka port di HP (localhost) yang nyambung ke port di server.',
                style: TextStyle(color: C.muted)),
            const SizedBox(height: 16),
            TextField(controller: label, decoration: const InputDecoration(hintText: 'Nama (mis. GUI Leo)')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: hostId,
              dropdownColor: C.surface2,
              borderRadius: BorderRadius.circular(14),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.dns_rounded)),
              items: [
                for (final h in Store.i.hostsSorted) DropdownMenuItem(value: h.id, child: Text('${h.label}  ·  ${h.address}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => set(() => hostId = v!),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: local,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontFamily: monoFont),
                  decoration: const InputDecoration(labelText: 'Port HP'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, color: C.cyan),
              ),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: rhost,
                  style: const TextStyle(fontFamily: monoFont),
                  decoration: const InputDecoration(labelText: 'Host tujuan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: rport,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontFamily: monoFont),
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            GradientButton(
              label: 'Simpan',
              onTap: () {
                final rp = int.tryParse(rport.text.trim());
                final lp = int.tryParse(local.text.trim()) ?? rp;
                if (rp == null || lp == null || lp < 1024 || lp > 65535) {
                  toast('Port HP harus 1024–65535', error: true);
                  return;
                }
                Store.i.saveForward(Forward(
                  id: f?.id ?? newId(),
                  label: label.text.trim().isEmpty ? 'Port $rp' : label.text.trim(),
                  hostId: hostId,
                  localPort: lp,
                  remoteHost: rhost.text.trim().isEmpty ? '127.0.0.1' : rhost.text.trim(),
                  remotePort: rp,
                ));
                Navigator.pop(c);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _toggle(Forward f, bool on) async {
    HapticFeedback.mediumImpact();
    try {
      on ? await SshManager.i.startForward(f) : await SshManager.i.stopForward(f.id);
      if (on) toast('Tunnel nyala → localhost:${f.localPort}');
    } catch (e) {
      SshManager.i.forwardErrors[f.id] = '$e';
      toast('$e', error: true);
    }
  }

  String _bytes(int b) => b > 1 << 20
      ? '${(b / (1 << 20)).toStringAsFixed(1)} MB'
      : b > 1024
          ? '${(b / 1024).toStringAsFixed(0)} KB'
          : '$b B';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Store.i, SshManager.i, PhoneServer.i]),
      builder: (context, _) {
        final list = Store.i.forwards;
        return SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(children: [
                const Text('Tunnel', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
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
              child: Text('Port forwarding: buka web/GUI di server lewat localhost HP, tanpa expose ke internet.',
                  style: TextStyle(color: C.muted)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: _ServerCard(),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.swap_horiz_rounded,
                      title: 'Belum ada tunnel',
                      subtitle: 'Contoh: port HP 8770 → 127.0.0.1:8770\nbuat buka GUI yang jalan di server.')
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final f = list[i];
                        final h = Store.i.host(f.hostId);
                        final af = SshManager.i.forwards[f.id];
                        final on = af != null;
                        final err = SshManager.i.forwardErrors[f.id];
                        return StaggerIn(
                          index: i,
                          child: Pressable(
                            scale: 0.98,
                            onTap: () => edit(context, f),
                            onLongPress: () async {
                              if (await confirm(context, 'Hapus tunnel ${f.label}?', '')) {
                                await SshManager.i.stopForward(f.id);
                                Store.i.deleteForward(f.id);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: C.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: on ? C.cyan.withValues(alpha: 0.5) : C.stroke),
                                boxShadow: on
                                    ? [BoxShadow(color: C.cyan.withValues(alpha: 0.15), blurRadius: 24)]
                                    : null,
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  StatusDot(on ? ConnState.ready : null),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                  ),
                                  Switch(value: on, onChanged: (v) => _toggle(f, v)),
                                ]),
                                const SizedBox(height: 8),
                                Text('localhost:${f.localPort}  →  ${f.remoteHost}:${f.remotePort}',
                                    style: const TextStyle(fontFamily: monoFont, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text('via ${h?.label ?? '(host kehapus)'}',
                                    style: TextStyle(color: C.muted, fontSize: 12)),
                                if (err != null && !on) ...[
                                  const SizedBox(height: 6),
                                  Text(err, style: const TextStyle(color: C.red, fontSize: 12)),
                                ],
                                if (on) ...[
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Text('${af.connections} koneksi · ${_bytes(af.bytes)}',
                                        style: TextStyle(color: C.muted, fontSize: 12)),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () => launchUrl(Uri.parse('http://127.0.0.1:${f.localPort}'),
                                          mode: LaunchMode.externalApplication),
                                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                                      label: const Text('Buka di browser'),
                                    ),
                                  ]),
                                ],
                              ]),
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

class _ServerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = PhoneServer.i;
    final on = s.running;
    final sub = on
        ? [
            'port ${s.port}',
            if (s.relayStatus == 'on') 'relay aktif',
            '${s.paired.length} HP terpasang',
          ].join(' · ')
        : 'Biar HP lain bisa SSH ke HP ini';
    return Pressable(
      scale: 0.98,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServerPage())),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? C.violet.withValues(alpha: 0.6) : C.stroke),
          boxShadow: on ? [BoxShadow(color: C.violet.withValues(alpha: 0.18), blurRadius: 24)] : null,
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: on ? C.accent : null,
              color: on ? null : C.surface2,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.cell_tower_rounded, color: on ? Colors.white : C.muted, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(on ? 'Mode Server · nyala' : 'Mode Server', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: C.muted, fontSize: 12.5)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: C.muted),
        ]),
      ),
    );
  }
}
