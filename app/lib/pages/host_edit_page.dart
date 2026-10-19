import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../ssh_command.dart';
import '../ssh_manager.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'hosts_page.dart';

class HostEditPage extends StatefulWidget {
  const HostEditPage({super.key, this.host});
  final Host? host;

  @override
  State<HostEditPage> createState() => _HostEditPageState();
}

class _HostEditPageState extends State<HostEditPage> {
  late final Host h = widget.host == null
      ? Host(id: newId(), label: '', host: '', username: 'root', color: Store.i.hosts.length)
      : Host.fromJson(widget.host!.toJson());
  late final _label = TextEditingController(text: h.label);
  late final _host = TextEditingController(text: h.host);
  late final _port = TextEditingController(text: '${h.port}');
  late final _user = TextEditingController(text: h.username);
  late final _startup = TextEditingController(text: h.startup);
  final _pw = TextEditingController();
  final _key = TextEditingController();
  final _pp = TextEditingController();
  bool _obscure = true;
  bool _hasSavedPw = false;
  bool _hasSavedKey = false;
  List<String> _notes = const [];
  String? _filledFrom; // what the form got filled from (shown as a hint)

  bool get _isNew => widget.host == null;

  @override
  void initState() {
    super.initState();
    if (!_isNew) {
      Store.i.password(h.id).then((v) => setState(() => _hasSavedPw = (v ?? '').isNotEmpty));
      Store.i.privateKey(h.id).then((v) => setState(() => _hasSavedKey = (v ?? '').isNotEmpty));
    }
  }

  /// Fills the form from a pasted `ssh …` / `mosh …` / `user@host:port` line.
  bool _fill(String text, {bool quiet = false}) {
    final r = SshCommand.parse(text);
    if (r == null || r.host.isEmpty) {
      if (!quiet) toast('Ga nemu host di situ. Contoh: ssh -p 2222 user@host', error: true);
      return false;
    }
    setState(() {
      _host.text = r.host;
      _port.text = '${r.port ?? 22}';
      if (r.user != null) _user.text = r.user!;
      if (r.password != null) {
        h.auth = 'password';
        _pw.text = r.password!;
      }
      if (r.command != null && _startup.text.trim().isEmpty) _startup.text = r.command!;
      if (r.notes.any((n) => n.contains('Ambil dari file'))) h.auth = 'key';
      _notes = r.notes;
      _filledFrom = '${r.user ?? _user.text}@${r.host}${(r.port ?? 22) == 22 ? '' : ':${r.port}'}';
    });
    HapticFeedback.lightImpact();
    return true;
  }

  Future<void> _pasteCommand() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (clip.trim().isNotEmpty && _fill(clip, quiet: true)) return;
    if (!mounted) return;
    final typed = await askText(context, 'Tempel perintah SSH', hint: 'ssh -p 2222 user@host');
    if (typed != null && typed.trim().isNotEmpty) _fill(typed);
  }

  /// Pasting a whole command into the host field splits it up.
  void _onHostChanged(String v) {
    if (!SshCommand.looksLikeCommand(v)) return;
    final r = SshCommand.parse(v);
    if (r == null || r.host.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fill(v, quiet: true);
      _host.selection = TextSelection.collapsed(offset: _host.text.length);
    });
  }

  Future<void> _importKey() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    setState(() => _key.text = utf8.decode(bytes, allowMalformed: true).trim());
  }

  Future<void> _save({bool connect = false}) async {
    if (_host.text.trim().isEmpty) {
      toast('Alamat host wajib diisi', error: true);
      return;
    }
    if (h.auth == 'key' && _key.text.trim().isNotEmpty && !_key.text.contains('PRIVATE KEY')) {
      toast('Itu bukan private key (harus ada "PRIVATE KEY")', error: true);
      return;
    }
    h
      ..host = _host.text.trim()
      ..label = _label.text.trim().isEmpty ? _host.text.trim() : _label.text.trim()
      ..port = int.tryParse(_port.text.trim()) ?? 22
      ..username = _user.text.trim().isEmpty ? 'root' : _user.text.trim()
      ..startup = _startup.text;
    await Store.i.saveHost(
      h,
      password: _pw.text.isEmpty ? null : _pw.text,
      key: _key.text.trim().isEmpty ? null : _key.text.trim(),
      passphrase: _pp.text.isEmpty ? null : _pp.text,
    );
    // Settings changed → drop the old live connection so the next one uses them.
    if (!_isNew) SshManager.i.disconnect(h.id);
    if (!mounted) return;
    Navigator.pop(context);
    if (connect) openTerminal(context, h);
  }

  Widget _label2(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(color: C.muted, fontSize: 11.5, letterSpacing: 1.3, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Host baru' : 'Edit host'),
        actions: [TextButton(onPressed: _save, child: const Text('Simpan'))],
      ),
      body: SafeArea(top: false, child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          const SizedBox(height: 16),
          Pressable(
            onTap: _pasteCommand,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [C.violet.withValues(alpha: 0.18), C.cyan.withValues(alpha: 0.12)]),
                border: Border.all(color: C.violet.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.content_paste_go_rounded, color: C.cyan, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Tempel perintah SSH', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_filledFrom == null ? 'mis. ssh -p 2222 user@host' : 'Keisi: $_filledFrom',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: monoFont, fontSize: 11.5, color: _filledFrom == null ? C.muted : C.cyan)),
                  ]),
                ),
              ]),
            ),
          ),
          if (_notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final n in _notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.info_outline_rounded, size: 15, color: C.amber)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(n, style: TextStyle(fontSize: 12.5, color: C.muted, height: 1.35))),
                    ]),
                  ),
              ]),
            ),
          _label2('Server'),
          TextField(controller: _label, decoration: const InputDecoration(hintText: 'Nama (mis. VPS, Laptop Leo)')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: _host,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: _onHostChanged,
                style: const TextStyle(fontFamily: monoFont),
                decoration: const InputDecoration(hintText: 'IP / domain'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: monoFont),
                decoration: const InputDecoration(hintText: '22'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _user,
            autocorrect: false,
            style: const TextStyle(fontFamily: monoFont),
            decoration: const InputDecoration(hintText: 'username', prefixIcon: Icon(Icons.person_rounded)),
          ),
          if (Store.i.hosts.any((x) => x.id != h.id)) ...[
            _label2('Nyambung lewat'),
            DropdownButtonFormField<String>(
              initialValue: Store.i.host(h.via) == null ? '' : h.via,
              dropdownColor: C.surface2,
              borderRadius: BorderRadius.circular(14),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.alt_route_rounded)),
              items: [
                const DropdownMenuItem(value: '', child: Text('Langsung')),
                for (final x in Store.i.hostsSorted.where((x) => x.id != h.id && x.via != h.id))
                  DropdownMenuItem(value: x.id, child: Text('lewat ${x.label}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => h.via = v ?? ''),
            ),
          ],
          _label2('Login pakai'),
          _Segmented(
            value: h.auth,
            onChanged: (v) => setState(() => h.auth = v),
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: h.auth == 'password'
                ? TextField(
                    controller: _pw,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: _hasSavedPw ? '•••••• (tersimpan, isi buat ganti)' : 'Password (kosongin = ditanya tiap connect)',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  )
                : Column(children: [
                    TextField(
                      controller: _key,
                      maxLines: 5,
                      minLines: 3,
                      style: const TextStyle(fontFamily: monoFont, fontSize: 11),
                      decoration: InputDecoration(
                        hintText: _hasSavedKey
                            ? 'Key tersimpan. Paste baru buat ganti.'
                            : '-----BEGIN OPENSSH PRIVATE KEY-----\n…',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      TextButton.icon(
                        onPressed: _importKey,
                        icon: const Icon(Icons.file_open_rounded),
                        label: const Text('Ambil dari file'),
                      ),
                    ]),
                    TextField(
                      controller: _pp,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Passphrase (kalau ada)'),
                    ),
                  ]),
          ),
          _label2('Auto-run pas masuk'),
          TextField(
            controller: _startup,
            autocorrect: false,
            style: const TextStyle(fontFamily: monoFont, fontSize: 13),
            decoration: const InputDecoration(hintText: 'mis. cd ~/leo && tmux new -A -s leo'),
          ),
          _label2('Warna'),
          Wrap(spacing: 12, children: [
            for (var i = 0; i < C.hostGradients.length; i++)
              Pressable(
                onTap: () => setState(() => h.color = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: C.hostGradient(i),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: h.color % C.hostGradients.length == i ? Colors.white : Colors.transparent, width: 2.5),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 30),
          GradientButton(label: 'Simpan & connect', icon: Icons.bolt_rounded, onTap: () => _save(connect: true)),
        ],
      )),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const opts = [('password', 'Password', Icons.password_rounded), ('key', 'SSH Key', Icons.key_rounded)];
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / 2;
        final idx = value == 'key' ? 1 : 0;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            left: w * idx,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(11))),
          ),
          Row(children: [
            for (final o in opts)
              Expanded(
                child: Pressable(
                  onTap: () => onChanged(o.$1),
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(o.$3, size: 18, color: value == o.$1 ? Colors.white : C.muted),
                      const SizedBox(width: 6),
                      Text(o.$2,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: value == o.$1 ? Colors.white : C.muted)),
                    ]),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}
