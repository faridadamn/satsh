import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../agent/tools.dart';
import '../keygen.dart';
import '../models.dart';
import '../store.dart';
import '../error_log.dart';
import 'error_log_page.dart';
import '../phone_control.dart';
import '../theme.dart';
import '../widgets.dart';
import 'providers_section.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.section});
  final String? section;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  final s = Store.i;
  late final _prompt = TextEditingController(text: s.get<String>('agentPrompt', ''));
  late final _supaUrl = TextEditingController(text: s.get<String>('supabaseUrl', ''));
  final _supaKey = TextEditingController();
  bool _hasSupa = false;
  PermissionStatus? _files;
  bool _control = false;
  late final _block = TextEditingController(text: PhoneControl.i.block.join(', '));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkControl();
    s.secret('supabaseKey').then((v) => setState(() => _hasSupa = v != null));
    Permission.manageExternalStorage.status.then((v) => setState(() => _files = v)).catchError((_) {});
  }

  Future<void> _saveSupa() async {
    s.set('supabaseUrl', _supaUrl.text.trim());
    if (_supaKey.text.isNotEmpty) await s.setSecret('supabaseKey', _supaKey.text.trim());
    _supaKey.clear();
    _hasSupa = await s.secret('supabaseKey') != null;
    setState(() {});
    if (_supaUrl.text.trim().isEmpty || !_hasSupa) return;
    try {
      final r = await http.get(Uri.parse('${_supaUrl.text.trim().replaceAll(RegExp(r'/+$'), '')}/rest/v1/'),
          headers: {'apikey': (await s.secret('supabaseKey'))!, 'Authorization': 'Bearer ${(await s.secret('supabaseKey'))!}'});
      toast(r.statusCode < 300 ? 'Supabase nyambung' : 'Supabase jawab HTTP ${r.statusCode}', error: r.statusCode >= 300);
    } catch (e) {
      toast('Supabase gagal: $e', error: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkControl();
  }

  Future<void> _checkControl() async {
    final on = await PhoneControl.i.enabled();
    if (mounted) setState(() => _control = on);
  }

  Future<void> _askFiles() async {
    final r = await Permission.manageExternalStorage.request();
    setState(() => _files = r);
    if (!r.isGranted) await openAppSettings();
  }

  Future<void> _genKey() async {
    final k = generateEd25519();
    final hostId = await showSheet<String>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('SSH key baru (ed25519)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(k.publicLine, style: TextStyle(fontFamily: monoFont, fontSize: 11, color: C.text)),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: k.publicLine));
                toast('Public key ke-copy');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy public key'),
            ),
            const SizedBox(height: 6),
            Text('Pasang ke server (pakai login yang sekarang), lalu host itu otomatis pindah ke login key:',
                style: TextStyle(color: C.muted)),
            const SizedBox(height: 8),
            for (final h in s.hostsSorted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_rounded),
                title: Text(h.label),
                subtitle: Text(h.address, style: const TextStyle(fontFamily: monoFont, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(c, h.id),
              ),
          ]),
        ),
      ),
    );
    if (hostId == null) return;
    final h = s.host(hostId)!;
    try {
      final line = k.publicLine.replaceAll("'", '');
      final out = await runSsh(h,
          "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF '$line' ~/.ssh/authorized_keys || echo '$line' >> ~/.ssh/authorized_keys) && echo KEY_OK");
      if (!out.contains('KEY_OK')) throw out;
      final updated = Host.fromJson(h.toJson())..auth = 'key';
      await s.saveHost(updated, key: k.privatePem);
      toast('Key kepasang di ${h.label}, login sekarang pakai key');
    } catch (e) {
      toast('Gagal pasang key: $e', error: true);
    }
  }

  Future<void> _export() async {
    final withSecrets = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Backup'),
        content: const Text('Ikutin password, private key & API key? File-nya jadi sensitif — simpen di tempat aman.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Tanpa rahasia')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ikutin semua')),
        ],
      ),
    );
    if (withSecrets == null) return;
    final json = await s.exportJson(withSecrets: withSecrets);
    final d = DateTime.now();
    final uri = await FilePicker.saveFile(
      fileName: 'satsh-backup-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.json',
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
    );
    if (uri != null) toast('Backup kesimpen');
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    try {
      final n = await s.importJson(utf8.decode(await files.first.readAsBytes()));
      toast('Restore beres: $n host');
    } catch (e) {
      toast('Gagal restore: $e', error: true);
    }
  }

  Widget _h(String t, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 0, 10),
        child: Row(children: [
          Icon(icon, size: 18, color: C.violet),
          const SizedBox(width: 8),
          Text(t.toUpperCase(),
              style: TextStyle(color: C.muted, fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _card(List<Widget> children) => Material(
        color: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: C.stroke)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  Widget _seg(String key, String def, List<(String, String)> opts, {ValueChanged<String>? after}) {
    final v = s.get<String>(key, def);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in opts)
        Pressable(
          onTap: () {
            s.set(key, o.$1);
            after?.call(o.$1);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: v == o.$1 ? C.accent : null,
              color: v == o.$1 ? null : C.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(o.$2, style: TextStyle(fontWeight: FontWeight.w600, color: v == o.$1 ? Colors.white : C.text)),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final off = s.get<List>('toolGroupsOff', const []).cast<String>();
        return Scaffold(
          appBar: AppBar(title: const Text('Pengaturan')),
          body: SafeArea(top: false, child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
            children: [
              _h('Agent', Icons.auto_awesome_rounded),
              const ProvidersSection(),
              const SizedBox(height: 12),
              _card([
                TextField(
                  controller: _prompt,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Instruksi tambahan (opsional)', hintText: 'mis. Leo ada di ~/leo, dijalanin pakai pm2'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                    onPressed: () {
                      s.set('agentPrompt', _prompt.text);
                      toast('Kesimpen');
                    },
                    child: const Text('Simpan instruksi')),
              ]),
              const SizedBox(height: 12),
              _card([
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-izinin semua aksi'),
                  subtitle: Text('Agent ga nanya dulu sebelum hapus file / jalanin perintah. Hati-hati.',
                      style: TextStyle(color: C.muted, fontSize: 12)),
                  value: s.get<bool>('autoApprove', false),
                  onChanged: (v) => s.set('autoApprove', v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sensor data sensitif di proses agent'),
                  subtitle: Text('API key, password, token, private key & IP disamarin (••••) di langkah tool, status, dan dialog izin.',
                      style: TextStyle(color: C.muted, fontSize: 12)),
                  value: s.get<bool>('redact', true),
                  onChanged: (v) => s.set('redact', v),
                ),
                const Divider(),
                for (final g in [
                  ('phone', 'File HP', Icons.phone_android_rounded),
                  ('device', 'Clipboard, URL, info HP', Icons.devices_rounded),
                  ('ssh', 'Server SSH', Icons.dns_rounded),
                  ('supabase', 'Supabase', Icons.storage_rounded),
                  ('web', 'HTTP GET', Icons.public_rounded),
                  ('browser', 'Browser agen (bisa dipantau)', Icons.travel_explore_rounded),
                  ('control', 'Kontrol app lain (tap/ketik)', Icons.touch_app_rounded),
                ])
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(g.$3, color: C.muted),
                    title: Text(g.$2),
                    subtitle: Text(
                        '${allTools.where((t) => t.group == g.$1).length} tools',
                        style: TextStyle(color: C.muted, fontSize: 12)),
                    value: !off.contains(g.$1),
                    onChanged: (v) => s.set('toolGroupsOff', v ? (off.toList()..remove(g.$1)) : [...off, g.$1]),
                  ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder_special_rounded, color: _files?.isGranted == true ? C.green : C.amber),
                  title: const Text('Akses semua file HP'),
                  subtitle: Text(_files?.isGranted == true ? 'Diizinin' : 'Belum diizinin — agent ga bisa baca file HP',
                      style: TextStyle(color: C.muted, fontSize: 12)),
                  trailing: _files?.isGranted == true ? null : TextButton(onPressed: _askFiles, child: const Text('Izinin')),
                ),
              ]),
              _h('Kontrol HP', Icons.touch_app_rounded),
              _card([
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_control ? Icons.check_circle_rounded : Icons.toggle_off_rounded, color: _control ? C.green : C.amber),
                  title: Text(_control ? 'Agent bisa ngontrol app lain' : 'Belum nyala'),
                  subtitle: Text(
                      _control
                          ? 'Tiap aksi tetap minta izin. Selama agent gerak ada tombol STOP mengambang.'
                          : 'Nyalain "satsh · kontrol agent" di Aksesibilitas biar agent bisa tap/ketik di app lain.',
                      style: TextStyle(color: C.muted, fontSize: 12)),
                ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => PhoneControl.i.openSettings(),
                      child: Text(_control ? 'Matiin' : 'Nyalain'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => PhoneControl.i.openAppInfo(),
                      child: const Text('Info aplikasi'),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text('Tombolnya abu-abu? (Android 13+) Info aplikasi → menu ⋮ kanan atas → "Izinkan setelan terbatas", terus nyalain lagi.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
                const Divider(height: 28),
                TextField(
                  controller: _block,
                  minLines: 2,
                  maxLines: 6,
                  style: const TextStyle(fontFamily: monoFont, fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'App yang DIBLOKIR dari agent (potongan nama paket, pisah koma)',
                    hintText: 'bca, id.dana, ovo.id, …',
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  TextButton(
                    onPressed: () {
                      _block.text = PhoneControl.defaultBlock.join(', ');
                      PhoneControl.i.block = PhoneControl.defaultBlock;
                      toast('Balik ke default');
                    },
                    child: const Text('Default'),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () {
                      PhoneControl.i.block = _block.text.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      toast('Daftar blokir kesimpen');
                    },
                    child: const Text('Simpan'),
                  ),
                ]),
              ]),
              _h('Konektor', Icons.cable_rounded),
              _card([
                const Row(children: [
                  Icon(Icons.bolt_rounded, color: C.green),
                  SizedBox(width: 8),
                  Text('Supabase', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _supaUrl,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(fontFamily: monoFont, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Project URL', hintText: 'https://xxxx.supabase.co'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _supaKey,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: _hasSupa ? 'Key (tersimpan — isi buat ganti)' : 'anon / service_role key'),
                ),
                const SizedBox(height: 6),
                Text('service_role = akses penuh (lewatin RLS). Pakai anon kalau mau aman.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(height: 10),
                GradientButton(label: 'Simpan & tes', onTap: _saveSupa),
              ]),
              _h('SSH key', Icons.key_rounded),
              _card([
                Text('Bikin key ed25519 di HP terus pasang otomatis ke server — abis itu ga perlu password lagi.',
                    style: TextStyle(color: C.muted)),
                const SizedBox(height: 12),
                GradientButton(label: 'Bikin & pasang key', icon: Icons.vpn_key_rounded, onTap: _genKey),
              ]),
              _h('Background', Icons.battery_charging_full_rounded),
              _card([
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Jaga koneksi tetap nyala'),
                  subtitle: Text('Sesi & tunnel ga putus pas app di background (ada notifikasi).',
                      style: TextStyle(color: C.muted, fontSize: 12)),
                  value: s.get<bool>('keepAlive', true),
                  onChanged: (v) => s.set('keepAlive', v),
                ),
                TextButton(
                  onPressed: () => Permission.ignoreBatteryOptimizations.request(),
                  child: const Text('Matiin optimasi baterai buat satsh'),
                ),
              ]),
              _h('Tampilan', Icons.palette_rounded),
              _card([
                _seg('theme', 'dark', [('dark', 'Gelap'), ('light', 'Terang')]),
              ]),
              _h('Log error', Icons.bug_report_rounded),
              _card([
                ListenableBuilder(
                  listenable: ErrorLog.i,
                  builder: (context, _) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bug_report_rounded, color: ErrorLog.i.entries.isEmpty ? C.green : C.amber),
                    title: Text(ErrorLog.i.entries.isEmpty ? 'Belum ada error' : '${ErrorLog.i.entries.length} error kecatat'),
                    subtitle: Text('Lihat detail + stack trace, salin, atau kirim laporan bug. Versi $appVersion',
                        style: TextStyle(color: C.muted, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openErrorLog(context),
                  ),
                ),
              ]),
              _h('Backup', Icons.cloud_sync_rounded),
              _card([
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.upload_file_rounded), label: const Text('Export'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.download_rounded), label: const Text('Restore'))),
                ]),
              ]),
            ],
          )),
        );
      },
    );
  }
}
