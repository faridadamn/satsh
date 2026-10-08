import 'package:flutter/material.dart';

import '../agent/external.dart';
import '../agent/llm.dart';
import '../agent/providers.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Saved LLM providers: keep many, order = fallback chain.
class ProvidersSection extends StatefulWidget {
  const ProvidersSection({super.key});

  @override
  State<ProvidersSection> createState() => _ProvidersSectionState();
}

class _ProvidersSectionState extends State<ProvidersSection> {
  final Map<String, String> _status = {};

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    for (final p in Providers.all()) {
      if (p.isExternal) {
        final h = Store.i.host(p.base);
        _status[p.id] = h == null ? 'host belum dipilih' : 'via ${h.label}';
      } else if (p.kind == 'codex') {
        final t = await CodexAuth.tokens(p.id);
        _status[p.id] = t == null
            ? 'belum login'
            : '${t['email'] ?? 'login'}${t['plan'] != null ? ' · ${t['plan']}' : ''}';
      } else {
        _status[p.id] = await Store.i.secret(p.keyName) == null ? 'API key belum diisi' : 'API key tersimpan';
      }
    }
    if (mounted) setState(() {});
  }

  void _save(List<ProviderCfg> l) {
    Providers.saveAll(l);
    setState(() {});
  }

  Future<void> _add() async {
    final pick = await showSheet<(String, String, String, String)>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Tambah provider', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                for (final p in providerPresets)
                  ListTile(
                    leading: Icon(
                      p.$2 == 'codex'
                          ? Icons.login_rounded
                          : p.$2 == 'gemini'
                          ? Icons.auto_awesome
                          : p.$2 == 'external'
                          ? Icons.terminal_rounded
                          : Icons.key_rounded,
                      color: C.violet,
                    ),
                    title: Text(p.$1),
                    subtitle: Text(
                      p.$2 == 'codex'
                          ? 'Pakai langganan ChatGPT (Plus/Pro), tanpa API key'
                          : p.$2 == 'external'
                          ? 'Agent CLI (agy) di Termux/server lewat SSH — soul tetap di sana'
                          : p.$3.isEmpty
                          ? 'API key'
                          : p.$3,
                      style: TextStyle(color: C.muted, fontSize: 12),
                    ),
                    onTap: () => Navigator.pop(c, p),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (pick == null) return;
    final p = ProviderCfg(
      distro: pick.$2 == 'external' ? 'ubuntu' : '',
      id: Providers.newPid(),
      kind: pick.$2,
      name: pick.$1.replaceAll(RegExp(r' \(.*\)'), ''),
      base: pick.$3,
      model: pick.$4,
    );
    _save([...Providers.all(), p]);
    if (mounted) await _edit(p);
  }

  Future<void> _edit(ProviderCfg p) async {
    final name = TextEditingController(text: p.name);
    final base = TextEditingController(text: p.base);
    final model = TextEditingController(text: p.model);
    final key = TextEditingController();
    var busy = false;
    var hostId = p.base;
    final distro = TextEditingController(text: p.distro);
    await showSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          Future<void> persist() async {
            p
              ..name = name.text.trim().isEmpty ? p.name : name.text.trim()
              ..base = p.isExternal ? hostId : base.text.trim()
              ..distro = distro.text.trim()
              ..model = model.text.trim();
            _save(Providers.all().map((x) => x.id == p.id ? p : x).toList());
            if (key.text.trim().isNotEmpty) {
              await Store.i.setSecret(p.keyName, key.text.trim());
            }
            key.clear();
            await _loadStatus();
          }

          Future<void> test() async {
            set(() => busy = true);
            try {
              await persist();
              if (p.isExternal) {
                final h = <Msg>[];
                await ExternalAgent.run(cfg: p, prompt: 'Jawab super singkat: bilang "siap bre" aja', history: h);
                final t = h
                    .where((m) => m.role == 'assistant' && m.text.trim().isNotEmpty)
                    .map((m) => m.text.trim())
                    .join(' ');
                toast('Nyambung: ${t.isEmpty ? '(jawaban kosong)' : t}');
              } else {
                final r = await (await Providers.build(p))
                    .chat('Jawab super singkat.', [Msg(role: 'user', text: 'Bilang "siap bre" aja')], []);
                toast('Nyambung: ${r.text.trim()}');
              }
            } catch (e) {
              toast('$e', error: true);
            }
            set(() => busy = false);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        p.label,
                        style: TextStyle(color: C.muted, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: C.red),
                        onPressed: () async {
                          if (!await confirm(c, 'Hapus ${p.name}?', 'Key/login-nya ikut dihapus.')) {
                            return;
                          }
                          await Store.i.setSecret(p.keyName, null);
                          await CodexAuth.logout(p.id);
                          _save(Providers.all().where((x) => x.id != p.id).toList());
                          if (c.mounted) Navigator.pop(c);
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nama'),
                  ),
                  const SizedBox(height: 10),
                  if (p.kind == 'openai') ...[
                    TextField(
                      controller: base,
                      keyboardType: TextInputType.url,
                      style: const TextStyle(fontFamily: monoFont, fontSize: 13),
                      decoration: const InputDecoration(labelText: 'Base URL'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (p.isExternal) ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: Store.i.host(hostId) == null ? null : hostId,
                      dropdownColor: C.surface2,
                      borderRadius: BorderRadius.circular(14),
                      hint: const Text('Pilih host (Termux)'),
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.dns_rounded)),
                      items: [
                        for (final h in Store.i.hostsSorted)
                          DropdownMenuItem(
                            value: h.id,
                            child: Text('${h.label}  ·  ${h.address}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => set(() => hostId = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: model,
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(fontFamily: monoFont, fontSize: 12.5),
                      decoration: const InputDecoration(labelText: 'Perintah'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: distro,
                      autocorrect: false,
                      style: const TextStyle(fontFamily: monoFont, fontSize: 12.5),
                      decoration: const InputDecoration(
                        labelText: 'Distro proot (Termux)',
                        hintText: 'ubuntu — kosongin kalau bukan Termux',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '{prompt} = pesan lu, {resume} = lanjutin obrolan yang sama. '
                      'Mau kerja di folder tertentu? Tambahin depannya, mis. cd ~/payu && agy …',
                      style: TextStyle(color: C.muted, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => set(() => model.text = ExternalAgent.defaultCommand),
                        child: const Text('Balikin ke default'),
                      ),
                    ),
                  ] else if (p.kind != 'codex')
                    TextField(
                      controller: key,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _status[p.id] == 'API key tersimpan'
                            ? 'API key (tersimpan — isi buat ganti)'
                            : 'API key',
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.account_circle_rounded,
                                color: _status[p.id] == 'belum login' ? C.muted : C.green,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_status[p.id] ?? '…', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Login pakai akun ChatGPT (Plus/Pro) lewat browser, sama kayak Codex CLI. Pemakaian ngikut kuota langganan lu.',
                            style: TextStyle(color: C.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: GradientButton(
                                  label: _status[p.id] == 'belum login' ? 'Login ChatGPT' : 'Login ulang',
                                  icon: Icons.login_rounded,
                                  busy: busy,
                                  onTap: () async {
                                    set(() => busy = true);
                                    try {
                                      final t = await CodexAuth.login(p.id);
                                      toast('Login sebagai ${t['email'] ?? 'ChatGPT'}');
                                    } catch (e) {
                                      toast('$e', error: true);
                                    }
                                    await _loadStatus();
                                    set(() => busy = false);
                                  },
                                ),
                              ),
                              if (_status[p.id] != 'belum login') ...[
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () async {
                                    await CodexAuth.logout(p.id);
                                    await _loadStatus();
                                    set(() {});
                                  },
                                  child: const Text('Logout'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (!p.isExternal) const SizedBox(height: 10),
                  if (!p.isExternal)
                    TextField(
                      controller: model,
                      style: const TextStyle(fontFamily: monoFont, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Model',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.list_rounded),
                          onPressed: () async {
                            await persist();
                            try {
                              final ms = await Providers.models(p);
                              if (!c.mounted) return;
                              final m = await showSheet<String>(
                                useSafeArea: true,
                                context: c,
                                isScrollControlled: true,
                                builder: (cc) => SizedBox(
                                  height: MediaQuery.of(cc).size.height * 0.6,
                                  child: ListView(
                                    children: [
                                      for (final id in ms)
                                        ListTile(
                                          title: Text(id, style: const TextStyle(fontFamily: monoFont, fontSize: 13)),
                                          onTap: () => Navigator.pop(cc, id),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                              if (m != null) set(() => model.text = m);
                            } catch (e) {
                              toast('Gagal ambil daftar model: $e', error: true);
                            }
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await persist();
                            if (c.mounted) Navigator.pop(c);
                          },
                          child: const Text('Simpan'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GradientButton(label: 'Tes', busy: busy, onTap: test),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = Providers.all();
    return Material(
      color: C.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: C.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Provider (fallback berurutan)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'Semua provider yang pernah ditambah tetap kesimpen. Yang nyala dipakai dari atas; kalau #1 error/limit, otomatis pindah ke berikutnya.',
              style: TextStyle(color: C.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty) Text('Belum ada provider.', style: TextStyle(color: C.muted)),
            for (var i = 0; i < list.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Pressable(
                  scale: 0.98,
                  onTap: () => _edit(list[i]),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: list[i].disabled ? null : C.accent,
                            color: list[i].disabled ? C.surface : null,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: list[i].disabled ? C.muted : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                list[i].name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: list[i].disabled ? C.muted : C.text,
                                ),
                              ),
                              Text(
                                '${list[i].isExternal
                                    ? 'agent eksternal'
                                    : list[i].model.isEmpty
                                    ? '-'
                                    : list[i].model} · ${_status[list[i].id] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: C.muted, fontSize: 11.5, fontFamily: monoFont),
                              ),
                            ],
                          ),
                        ),
                        if (i > 0)
                          IconButton(
                            tooltip: 'Naikin',
                            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                            onPressed: () {
                              final l = Providers.all();
                              l.insert(i - 1, l.removeAt(i));
                              _save(l);
                            },
                          ),
                        Switch(
                          value: !list[i].disabled,
                          onChanged: (v) {
                            final l = Providers.all();
                            l[i].disabled = !v;
                            _save(l);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah provider'),
            ),
          ],
        ),
      ),
    );
  }
}
