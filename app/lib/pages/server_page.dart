import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../phone_server.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'hosts_page.dart';

/// "Mode Server" — let other phones SSH into this one.
class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 0, 8),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(color: C.muted, fontSize: 11.5, letterSpacing: 1.3, fontWeight: FontWeight.w600),
    ),
  );

  Widget _box({required Widget child, EdgeInsets? padding}) => Material(
    color: C.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: C.stroke),
    ),
    child: padding == null ? child : Padding(padding: padding, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final s = PhoneServer.i;
    return Scaffold(
      appBar: AppBar(title: const Text('Mode Server')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, Store.i]),
        builder: (context, _) {
          final on = s.running;
          return SafeArea(
            top: false,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                // ---------------------------------------------------- hero
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: on ? C.accent : null,
                    color: on ? null : C.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: on ? Colors.transparent : C.stroke),
                    boxShadow: on ? [BoxShadow(color: C.violet.withValues(alpha: 0.35), blurRadius: 28)] : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cell_tower_rounded, color: on ? Colors.white : C.muted, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  on ? 'HP ini lagi jadi server' : 'HP ini jadi server',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                    color: on ? Colors.white : C.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.starting
                                      ? 'Nyalain…'
                                      : on
                                      ? '${s.name} · port ${s.port}'
                                      : 'HP lain bisa SSH & buka file HP ini',
                                  style: TextStyle(color: on ? Colors.white70 : C.muted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: on || s.starting,
                            activeThumbColor: Colors.white,
                            onChanged: s.starting
                                ? null
                                : (v) {
                                    HapticFeedback.mediumImpact();
                                    v ? s.start() : s.stop();
                                  },
                          ),
                        ],
                      ),
                      if (s.error != null && !on) ...[
                        const SizedBox(height: 10),
                        Text(s.error!, style: const TextStyle(color: C.red, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: GradientButton(
                        label: 'Pasangin HP',
                        icon: Icons.qr_code_2_rounded,
                        onTap: on ? () => showPairQr(context) : () => toast('Nyalain Mode Server dulu', error: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairScanPage())),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Atau: sambung HP ini ke HP lain (scan)'),
                  ),
                ),

                // -------------------------------------------------- route
                _label('Dijangkau lewat'),
                _box(
                  child: Column(
                    children: [
                      FutureBuilder<List<String>>(
                        future: PhoneServer.localAddresses(),
                        builder: (_, snap) {
                          final ips = snap.data ?? const [];
                          return ListTile(
                            leading: const Icon(Icons.wifi_rounded, color: C.cyan),
                            title: const Text('Wi-Fi / Tailscale'),
                            subtitle: Text(
                              ips.isEmpty ? 'Ga ada jaringan lokal' : ips.map((e) => '$e:${s.port}').join('\n'),
                              style: const TextStyle(fontFamily: monoFont, fontSize: 12),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: C.stroke),
                      _RelayTile(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Satu Wi-Fi atau sama-sama pakai Tailscale → langsung. '
                    'Beda jaringan (pakai kuota) → nyalain Relay lewat VPS.',
                    style: TextStyle(color: C.muted, fontSize: 12, height: 1.4),
                  ),
                ),

                // ------------------------------------------------- paired
                _label('HP yang boleh masuk'),
                _box(
                  child: s.paired.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'Belum ada. Tap "Pasangin HP", terus scan dari HP lain.',
                            style: TextStyle(color: C.muted),
                          ),
                        )
                      : Column(
                          children: [
                            for (final k in s.paired)
                              ListTile(
                                leading: const Icon(Icons.smartphone_rounded, color: C.green),
                                title: Text(k.name),
                                subtitle: Text(k.line.split(' ').first, style: TextStyle(color: C.muted, fontSize: 12)),
                                trailing: IconButton(
                                  tooltip: 'Cabut akses',
                                  icon: const Icon(Icons.link_off_rounded, color: C.red),
                                  onPressed: () async {
                                    if (await confirm(
                                      context,
                                      'Cabut akses ${k.name}?',
                                      'HP itu ga bisa masuk lagi sampai dipasangin ulang.',
                                      ok: 'Cabut',
                                    )) {
                                      s.revoke(k);
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                ),

                // ------------------------------------------------ settings
                _label('Pengaturan'),
                _box(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge_rounded),
                        title: const Text('Nama HP ini'),
                        subtitle: Text(s.name, style: const TextStyle(fontFamily: monoFont)),
                        onTap: () async {
                          final v = await askText(context, 'Nama HP ini', initial: s.name, hint: 'mis. hp-kantor');
                          final clean = (v ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '-');
                          if (clean.isNotEmpty) s.setConfig(name: clean);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.numbers_rounded),
                        title: const Text('Port'),
                        subtitle: Text('${s.port}', style: const TextStyle(fontFamily: monoFont)),
                        onTap: () async {
                          final v = int.tryParse(
                            (await askText(context, 'Port server', initial: '${s.port}', hint: '1024–65535')) ?? '',
                          );
                          if (v == null) return;
                          if (v < 1024 || v > 65535) {
                            toast('Port harus 1024–65535', error: true);
                            return;
                          }
                          s.setConfig(port: v);
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.power_settings_new_rounded),
                        title: const Text('Nyala otomatis'),
                        subtitle: Text('Tiap satsh dibuka', style: TextStyle(color: C.muted, fontSize: 12)),
                        value: s.autoStart,
                        onChanged: (v) => s.setConfig(autoStart: v),
                      ),
                    ],
                  ),
                ),

                // ----------------------------------------------------- log
                if (s.log.isNotEmpty) ...[
                  _label('Aktivitas'),
                  _box(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (final e in s.log.take(12))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(fontFamily: monoFont, fontSize: 12, color: C.muted),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(e.text, style: TextStyle(fontSize: 13, color: e.error ? C.red : C.text)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                _label('Perlu tau'),
                _box(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '• Yang masuk cuma bisa akses folder satsh + memori HP (Download, DCIM, dll) lewat folder "storage". '
                    'Ga bisa ngontrol aplikasi lain.\n'
                    '• Perintah yang ada: perintah bawaan Android (ls, cp, mv, cat, ping…).\n'
                    '• Login cuma pakai kunci dari pairing. Password ga bisa dipake.\n'
                    '• Selama nyala ada notifikasi satsh. Baterai kepake dikit lebih banyak.',
                    style: TextStyle(color: C.muted, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RelayTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = PhoneServer.i;
    final h = Store.i.host(s.relayHostId);
    final (color, status) = switch (s.relayStatus) {
      'on' => (C.green, 'Aktif · port VPS ${s.relayPort}'),
      'connecting' => (C.amber, s.relayError ?? 'Nyambung ke VPS…'),
      'error' => (C.red, s.relayError ?? 'Gagal'),
      _ => (
        C.muted,
        h == null
            ? 'Mati'
            : s.running
            ? 'Siap'
            : 'Nyala bareng server',
      ),
    };
    return ListTile(
      leading: Icon(Icons.public_rounded, color: h == null ? C.muted : color),
      title: Text(h == null ? 'Relay lewat VPS' : 'Relay lewat ${h.label}'),
      subtitle: Text(status, style: TextStyle(color: color, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _pickRelay(context),
    );
  }

  Future<void> _pickRelay(BuildContext context) async {
    final s = PhoneServer.i;
    final hosts = Store.i.hostsSorted.where((h) => h.via.isEmpty && h.username != 'satsh').toList();
    await showSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Relay lewat VPS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'HP ini nyambung ke VPS lu dan buka "pintu" di sana. HP lain masuk lewat pintu itu, '
                'dari jaringan mana aja. Port-nya cuma kebuka di dalam VPS (127.0.0.1), ga ke internet.',
                style: TextStyle(color: C.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              if (hosts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Belum ada host VPS. Tambahin dulu di tab Host.', style: TextStyle(color: C.muted)),
                ),
              for (final h in hosts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns_rounded, color: h.id == s.relayHostId ? C.cyan : C.muted),
                  title: Text(h.label),
                  subtitle: Text(h.address, style: const TextStyle(fontFamily: monoFont, fontSize: 12)),
                  trailing: h.id == s.relayHostId ? const Icon(Icons.check_rounded, color: C.cyan) : null,
                  onTap: () {
                    Navigator.pop(c);
                    s.setConfig(relayHostId: h.id);
                  },
                ),
              if (s.relayHostId.isNotEmpty) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.numbers_rounded),
                  title: const Text('Port di VPS'),
                  subtitle: Text(
                    s.relayPort > 0 ? '${s.relayPort}' : 'otomatis',
                    style: const TextStyle(fontFamily: monoFont),
                  ),
                  onTap: () async {
                    Navigator.pop(c);
                    final v = int.tryParse(
                      (await askText(
                            context,
                            'Port relay di VPS',
                            initial: s.relayPort > 0 ? '${s.relayPort}' : '',
                            hint: '1024–65535',
                          )) ??
                          '',
                    );
                    if (v != null && v >= 1024 && v <= 65535) {
                      await s.setConfig(relayPort: v);
                      if (s.running) await s.setConfig(relayHostId: s.relayHostId);
                    }
                  },
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    s.setConfig(relayHostId: '');
                  },
                  icon: const Icon(Icons.close_rounded, color: C.red),
                  label: const Text('Matiin relay', style: TextStyle(color: C.red)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- QR sheet
Future<void> showPairQr(BuildContext context) async {
  final s = PhoneServer.i;
  String code;
  try {
    code = await s.startPairing();
  } catch (e) {
    toast('$e', error: true);
    return;
  }
  if (!context.mounted) return;
  var done = false;
  s.waitForPair().then((who) {
    done = true;
    final ctx = navKey.currentContext;
    // ignore: use_build_context_synchronously
    if (ctx != null && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
    toast('✓ $who udah dipasangin');
  }).ignore();
  await showSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) => _QrSheet(code: code),
  );
  if (!done) await s.cancelPairing();
}

class _QrSheet extends StatefulWidget {
  const _QrSheet({required this.code});
  final String code;
  @override
  State<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<_QrSheet> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final exp = PhoneServer.i.tokenExpiry;
      if (exp == null || DateTime.now().isAfter(exp)) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exp = PhoneServer.i.tokenExpiry;
    final left = exp == null ? Duration.zero : exp.difference(DateTime.now());
    final relay = widget.code.isNotEmpty && PhoneServer.i.relayStatus == 'on';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Scan dari HP lain', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Di HP lain: satsh → Tunnel → Mode Server → "sambung HP ini ke HP lain"',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
            child: QrImageView(data: widget.code, size: 230, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(
                'Nunggu… ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(color: C.muted, fontFamily: monoFont),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            relay ? 'Bisa dari jaringan mana aja (lewat VPS)' : 'Tanpa relay: HP lain harus satu Wi-Fi / Tailscale',
            style: TextStyle(color: relay ? C.green : C.amber, fontSize: 12),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.code));
              toast('Kode disalin — kirim ke HP lain (sekali pakai, 10 menit)');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Salin kode (kalau ga bisa scan)'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ scan & pair
class PairScanPage extends StatefulWidget {
  const PairScanPage({super.key});
  @override
  State<PairScanPage> createState() => _PairScanPageState();
}

class _PairScanPageState extends State<PairScanPage> {
  final _cam = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _busy = false;
  String _progress = '';

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  Future<void> _handle(String text) async {
    if (_busy) return;
    final code = PairCode.parse(text);
    if (code == null) {
      toast('Itu bukan kode pairing satsh', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _progress = 'Mulai…';
    });
    _cam.stop().ignore();
    try {
      var me = Store.i.get<String>('srvName', '');
      if (me.isEmpty || me == 'hp') {
        try {
          me = (await DeviceInfoPlugin().androidInfo).model;
        } catch (_) {
          me = 'hp-lain';
        }
      }
      final r = await PairClient.pair(
        code,
        deviceName: me,
        progress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      toast('✓ ${r.host.label} ditambahin (${r.route})');
      Navigator.pop(context);
      openTerminal(context, r.host);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Gagal masangin'),
          content: Text('$e'.replaceFirst('Exception: ', '')),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Oke'))],
        ),
      );
      _cam.start().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sambung ke HP lain'),
        actions: [
          TextButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final d = await Clipboard.getData('text/plain');
                    final t = d?.text ?? '';
                    if (!mounted) return;
                    if (t.isEmpty) {
                      final v = await askText(this.context, 'Tempel kode', hint: 'satsh://pair/…');
                      if (v != null) _handle(v);
                    } else {
                      _handle(t);
                    }
                  },
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: const Text('Tempel'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _cam,
                        onDetect: (cap) {
                          for (final b in cap.barcodes) {
                            final v = b.rawValue;
                            if (v != null && v.startsWith('satsh://pair/')) {
                              HapticFeedback.mediumImpact();
                              _handle(v);
                              return;
                            }
                          }
                        },
                        errorBuilder: (c, e) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Kamera ga bisa dibuka (${e.errorCode.name}).\nPakai tombol "Tempel" di atas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: C.muted),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 230,
                          height: 230,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      if (_busy)
                        Container(
                          color: Colors.black.withValues(alpha: 0.7),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: Colors.white),
                                const SizedBox(height: 16),
                                Text(_progress, style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
              child: Text(
                'Di HP satunya: Mode Server → nyalain → "Pasangin HP". Arahin kamera ke QR-nya.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
