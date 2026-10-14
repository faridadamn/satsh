import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../store.dart';
import 'llm.dart';

const memoryLimit = 2200;
const userLimit = 1375;
const entrySep = '\n§\n';

/// A chat session with the agent.
class AgentSession {
  AgentSession({required this.id, this.title = 'Chat baru', int? created, List<Msg>? messages})
      : created = created ?? DateTime.now().millisecondsSinceEpoch,
        updated = created ?? DateTime.now().millisecondsSinceEpoch,
        messages = messages ?? [];

  final String id;
  String title;
  final int created;
  int updated;
  final List<Msg> messages;

  /// Context compression: everything before [contextStart] is represented by [summary].
  int contextStart = 0;
  String summary = '';
  List<Map<String, dynamic>> todos = [];
  int userTurns = 0;
  String? cronJobId;
  bool unread = false;

  /// External agents: provider id → their own conversation id.
  Map<String, String> ext = {};

  /// Agent profile this chat belongs to (null = default).
  String? profile;

  /// Model the agent switched this chat to: {'provider': id, 'model': name} (null = profile default).
  Map<String, String>? model;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created': created,
        'updated': updated,
        'contextStart': contextStart,
        'summary': summary,
        'todos': todos,
        'userTurns': userTurns,
        if (cronJobId != null) 'cronJobId': cronJobId,
        'unread': unread,
        if (ext.isNotEmpty) 'ext': ext,
        if (profile != null) 'profile': profile,
        if (model != null) 'model': model,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory AgentSession.fromJson(Map<String, dynamic> j) {
    final s = AgentSession(
      id: j['id'],
      title: j['title'] ?? 'Chat',
      created: j['created'],
      messages: (j['messages'] as List? ?? []).map((e) => Msg.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
    s.updated = j['updated'] ?? s.created;
    s.contextStart = j['contextStart'] ?? 0;
    s.summary = j['summary'] ?? '';
    s.todos = (j['todos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    s.userTurns = j['userTurns'] ?? 0;
    s.cronJobId = j['cronJobId'];
    s.unread = j['unread'] ?? false;
    s.ext = Map<String, String>.from(j['ext'] ?? const {});
    s.profile = j['profile'];
    s.model = j['model'] is Map ? Map<String, String>.from(j['model']) : null;
    return s;
  }
}

class SessionMeta {
  SessionMeta(this.id, this.title, this.updated, {this.unread = false, this.cron = false, this.profile});
  final String id;
  String title;
  int updated;
  bool unread;
  final bool cron;
  String? profile;
}

/// One agent persona: its own soul, memory, skills, model and tools.
/// USER.md (who the user is) is shared by all profiles.
class AgentProfile {
  AgentProfile({required this.id, required this.name, this.emoji = '⚡', this.desc = '', this.provider = '', List<String>? toolsOff})
      : toolsOff = toolsOff ?? [];
  final String id;
  String name;
  String emoji;
  String desc;

  /// Provider id to try first ('' = the normal order).
  String provider;

  /// Tool groups this profile can't use (on top of the global switches).
  List<String> toolsOff;

  static final idRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'emoji': emoji, 'desc': desc, 'provider': provider, 'toolsOff': toolsOff};

  factory AgentProfile.fromJson(Map<String, dynamic> j) => AgentProfile(
        id: j['id'],
        name: j['name'] ?? j['id'],
        emoji: j['emoji'] ?? '⚡',
        desc: j['desc'] ?? '',
        provider: j['provider'] ?? '',
        toolsOff: (j['toolsOff'] as List? ?? []).cast<String>(),
      );
}

class Skill {
  Skill({required this.name, required this.description, required this.body, this.raw = ''});
  final String name;
  final String description;
  final String body;
  final String raw;
}

class CronJob {
  CronJob({
    required this.id,
    required this.name,
    required this.prompt,
    this.everyMinutes,
    this.dailyAt,
    this.enabled = true,
    this.allowRisky = false,
    this.lastRun,
    this.lastResult = '',
    this.sessionId,
    this.profile,
  });

  final String id;
  String name;
  String prompt;
  String? profile;
  int? everyMinutes; // interval schedule
  String? dailyAt; // "HH:MM" schedule
  bool enabled;
  bool allowRisky;
  int? lastRun;
  String lastResult;
  String? sessionId;

  String get scheduleLabel => dailyAt != null ? 'tiap hari $dailyAt' : 'tiap ${_mins(everyMinutes ?? 60)}';

  static String _mins(int m) => m % 1440 == 0
      ? '${m ~/ 1440} hari'
      : m % 60 == 0
          ? '${m ~/ 60} jam'
          : '$m menit';

  /// Clock for [nextRun] without an explicit time (tests pin it).
  static DateTime Function() clock = DateTime.now;

  DateTime nextRun([DateTime? now]) {
    now ??= clock();
    final last = lastRun == null ? null : DateTime.fromMillisecondsSinceEpoch(lastRun!);
    final created = DateTime.fromMillisecondsSinceEpoch(createdAt);
    if (dailyAt != null) {
      final p = dailyAt!.split(':');
      final slot = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      final ranToday = last != null && !last.isBefore(slot);
      final createdAfter = created.isAfter(slot);
      if (slot.isAfter(now)) return slot;
      if (ranToday || createdAfter) return slot.add(const Duration(days: 1));
      return slot; // missed today's slot → due now
    }
    final every = Duration(minutes: everyMinutes ?? 60);
    return (last ?? created).add(every);
  }

  bool isDue(DateTime now) => enabled && !nextRun(now).isAfter(now);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'everyMinutes': everyMinutes,
        'dailyAt': dailyAt,
        'enabled': enabled,
        'allowRisky': allowRisky,
        'lastRun': lastRun,
        'lastResult': lastResult,
        'sessionId': sessionId,
        if (profile != null) 'profile': profile,
        'created': createdAt,
      };

  int createdAt = DateTime.now().millisecondsSinceEpoch;

  factory CronJob.fromJson(Map<String, dynamic> j) => CronJob(
        id: j['id'],
        name: j['name'],
        prompt: j['prompt'],
        everyMinutes: j['everyMinutes'],
        dailyAt: j['dailyAt'],
        enabled: j['enabled'] ?? true,
        allowRisky: j['allowRisky'] ?? false,
        lastRun: j['lastRun'],
        lastResult: j['lastResult'] ?? '',
        sessionId: j['sessionId'],
        profile: j['profile'],
      )..createdAt = j['created'] ?? DateTime.now().millisecondsSinceEpoch;
}

const defaultSoul = '''# SOUL — siapa kamu

Kamu **satsh agent**: partner ngoprek yang hidup di HP Android user. Kamu bisa megang file HP, server SSH user, Supabase, dan internet.

## Gaya
- Bahasa Indonesia santai (gw/lu), to the point, ga bertele-tele. Boleh bercanda dikit.
- Jawab singkat dulu; detail kalau diminta.
- Kalau bisa dikerjain sendiri pakai tools, kerjain. Jangan nyuruh user ngetik perintah.

## Prinsip
- Teliti sebelum aksi destruktif. Cek dulu, baru eksekusi.
- Jujur kalau gagal atau ga yakin.
- Ingat hal penting tentang user & lingkungannya pakai memori, dan simpan cara kerja yang kepake berulang jadi skill.
''';

/// Working rules every newly summoned agent gets (adapted, lightly, from the
/// "7 bagian CLAUDE.md" checklist: plan → verify → learn).
const workPrinciples = r'''## Cara kerja (berlaku buat semua tugas)
- **Sederhana dulu, tapi tuntas.** Ukurannya: bakal di-approve senior engineer ga? Kalau rumit, sederhanain. Kalau setengah jadi, belum selesai.
- **Rencana dulu** buat tugas 3+ langkah: tulis pakai todo_write, update statusnya sambil jalan. Rencana yang NGUBAH sistem (hapus, deploy, ubah config, restart) → tunjukin dulu & tunggu "oke" user.
- **Bukti, bukan klaim.** Jangan bilang "beres" sebelum ada bukti: output perintah, log, hasil tes, atau diff. Taruh buktinya (singkat) di laporan.
- **Bug/error: telusuri sendiri dulu.** Baca log, cari akar masalah, coba perbaiki. Nanya user cuma kalau bener-bener buntu atau butuh keputusan.
- **Belajar dari koreksi.** Tiap dikoreksi user, catat pelajarannya ke memori (target=memory, awali "Pelajaran:") biar ga ngulang.
- **Konteks tetap bersih.** Riset/eksplorasi panjang yang bisa dipisah → delegate_task.''';

/// Soul for a brand-new agent profile: who it is + [workPrinciples].
String newAgentSoul(String name, String desc, [String body = '']) {
  final b = body.trim().isEmpty ? '# SOUL — $name\n\n${desc.trim().isEmpty ? 'Kamu agent $name.' : desc.trim()}\n' : body.trim();
  return b.contains('## Cara kerja') ? '$b\n' : '$b\n\n$workPrinciples\n';
}

const _defaultSkills = {
  'cek-server': '''---
name: cek-server
description: Health check cepat server SSH — disk, RAM, CPU load, uptime, service gagal, port terbuka. Pakai kalau user minta cek/monitor kondisi server.
---
# Cek kesehatan server

1. Kalau user ga nyebut server, pakai `ssh_hosts` lalu cek semua yang ada (atau tanya kalau banyak).
2. Jalanin satu perintah gabungan biar hemat:
   ```
   echo "== uptime"; uptime; echo "== disk"; df -h -x tmpfs -x devtmpfs | head -20; echo "== ram"; free -h; echo "== top cpu"; ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -6; echo "== failed"; systemctl --failed --no-legend 2>/dev/null | head; echo "== ports"; ss -tulpn 2>/dev/null | head -20
   ```
3. Rangkum dalam tabel kecil per server: Disk (paling penuh), RAM kepake, load, service gagal.
4. Tandai ⚠️ kalau disk > 85%, RAM available < 10%, load > jumlah core, atau ada service failed. Kasih saran 1 baris buat tiap masalah.
''',
  'deploy-git': '''---
name: deploy-git
description: Deploy app dari git di server — pull, install dependency, build, restart (pm2/systemd/docker). Pakai kalau user bilang deploy/update app di server.
---
# Deploy dari git

1. Pastiin server & folder project (tanya kalau belum jelas, atau cek memori — mungkin udah pernah dicatat).
2. Cek status dulu: `cd <dir> && git status --short && git log -1 --oneline`. Kalau ada perubahan lokal yang belum di-commit, STOP dan kasih tau user.
3. `git pull --ff-only`.
4. Deteksi tipe project dari file yang ada:
   - `package.json` → `npm ci` (atau `pnpm i --frozen-lockfile` kalau ada pnpm-lock) lalu `npm run build` kalau script build ada.
   - `requirements.txt` → `pip install -r requirements.txt` (pakai venv kalau ada).
   - `docker-compose.yml` → `docker compose up -d --build`.
5. Restart: cek `pm2 ls`, `systemctl list-units --type=service | grep <nama>`, pilih yang cocok.
6. Verifikasi: cek log 20 baris terakhir + curl health endpoint kalau ada.
7. Simpan ke memori: folder project + cara restart, biar deploy berikutnya lebih cepat.
''',
  'rapihin-download': '''---
name: rapihin-download
description: Beresin folder Download di HP — kelompokin file per jenis (Dokumen, Gambar, Video, APK, Arsip) dan laporin file gede/duplikat. Pakai kalau user minta rapihin/bersihin file HP.
---
# Rapihin folder Download

1. `phone_list` folder `Download`.
2. Rencanain pemindahan ke subfolder: Dokumen (pdf, doc, xls, ppt, txt, csv), Gambar (jpg, png, webp, heic), Video (mp4, mkv, mov), APK, Arsip (zip, rar, 7z), Lainnya.
3. Tampilin ringkasan rencana (jumlah file per folder) dan MINTA KONFIRMASI user dulu sebelum mindahin.
4. Pindahin pakai `phone_move` satu-satu. Jangan timpa file yang udah ada.
5. Laporin: file > 100MB dan nama yang mirip duplikat (mis. `x (1).pdf`). Jangan hapus apa pun tanpa izin.
''',
  'cek-hp-bekas': r'''---
name: cek-hp-bekas
description: Cek kondisi HP — HP bekas yang mau dibeli atau HP sendiri — pakai diagnosa_hp + tes manual di halaman Cek HP + cek harga wajar. Pakai kalau user mau beli HP bekas, nanya kesehatan baterai, atau kondisi HP-nya.
---
# Cek HP bekas

1. satsh harus jalan DI HP yang dicek. HP orang: pasang APK satsh sebentar, uninstall lagi abis cek.
2. Baterai < 50%? Minta cas dulu sampai > 50% — perkiraan kapasitas lebih akurat.
3. `diagnosa_hp` (HP sendiri yang udah dikasih izin adb: `logs=crash`, lalu `logs=battery`).
4. Suruh user buka **Pengaturan → Cek HP** dan jalanin semua tes manual (layar, sentuh, multitouch, speaker, mic, getar, 2 kamera, port cas, tombol, sinyal/SIM, sidik jari). Abis itu `diagnosa_hp` lagi biar hasilnya ikut.
5. Kasih checklist yang ga bisa dites app:
   - IMEI: ketik `*#06#`, harus sama kayak kardus/nota. Cek di imei.kemenperin.go.id — HP luar yang ga terdaftar sinyalnya diblokir.
   - Akun Google/Mi/Samsung/iCloud udah logout & HP di-reset depan lu (biar ga kekunci FRP).
   - Fisik: baterai kembung (layar/tutup belakang keangkat), bekas bongkar (baut lecet, lem layar), bekas kena air, layar ganti (warna/kecerahan beda, touch telat).
6. Harga: `browser_open` cari "harga <model> bekas" (marketplace, kondisi mirip) → rentang wajar, lalu potongan per temuan (baterai < 80% ≈ biaya ganti baterai; kamera/layar bermasalah ≈ biaya servisnya).
7. Laporan: vonis (layak / cek lagi / waspada), temuan + bukti dari tool, harga wajar, dan 3–5 pertanyaan buat penjual.
''',
};

/// The parts of the brain that belong to one profile: SOUL.md, MEMORY.md, skills/.
/// The default profile lives in the agent root (same layout as before
/// profiles existed); others live in agent/profiles/ID/.
class ProfileBrain {
  ProfileBrain(this.brain, this.id, this.dir);
  final Brain brain;
  final String id;
  final Directory dir;
  String soul = defaultSoul;
  String memory = '';
  List<Skill> skills = [];

  AgentProfile get meta => brain.profile(id) ?? AgentProfile(id: id, name: id);

  /// Default skills that shipped before `.defaults-seen` existed (old installs already had their chance).
  static const _oldDefaults = ['cek-server', 'deploy-git', 'rapihin-download'];

  Future<void> load({bool seed = true}) async {
    await Directory('${dir.path}/skills').create(recursive: true);
    final soulF = File('${dir.path}/SOUL.md');
    final fresh = !await soulF.exists();
    if (fresh && seed) await soulF.writeAsString(defaultSoul);
    if (seed && id == 'default') await _seedNewDefaults(fresh);
    soul = await soulF.exists() ? await soulF.readAsString() : defaultSoul;
    final memF = File('${dir.path}/MEMORY.md');
    memory = await memF.exists() ? await memF.readAsString() : '';
    await _loadSkills();
  }

  /// Writes built-in skills this install hasn't been offered yet (a skill the user deleted stays deleted).
  Future<void> _seedNewDefaults(bool fresh) async {
    final f = File('${dir.path}/.defaults-seen');
    var seen = <String>[];
    try {
      seen = (jsonDecode(await f.readAsString()) as List).cast<String>();
    } catch (_) {
      if (!fresh) seen = List.of(_oldDefaults);
    }
    var changed = false;
    for (final e in _defaultSkills.entries) {
      if (seen.contains(e.key)) continue;
      final sk = File('${dir.path}/skills/${e.key}/SKILL.md');
      if (!await sk.exists()) {
        await sk.parent.create(recursive: true);
        await sk.writeAsString(e.value);
      }
      seen.add(e.key);
      changed = true;
    }
    if (changed || !await f.exists()) await f.writeAsString(jsonEncode(seen));
  }

  // ---------------------------------------------------------------- soul
  Future<void> saveSoul(String text) async {
    soul = text.trim().isEmpty ? defaultSoul : text;
    await File('${dir.path}/SOUL.md').writeAsString(soul);
    brain._changed();
  }

  // -------------------------------------------------------------- memory
  List<String> entries(String target) =>
      (target == 'user' ? brain.user : memory).split(entrySep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  int limitOf(String target) => target == 'user' ? userLimit : memoryLimit;

  Future<void> setEntries(String target, List<String> list) async {
    final text = list.join(entrySep);
    if (target == 'user') {
      brain.user = text;
      await File('${brain.root.path}/USER.md').writeAsString(text);
    } else {
      memory = text;
      await File('${dir.path}/MEMORY.md').writeAsString(text);
    }
    brain._changed();
  }

  /// add / replace / remove — returns a message for the agent.
  Future<String> memoryOp(String action, String target, {String? content, String? oldText}) async {
    if (target != 'user' && target != 'memory') throw 'target harus "memory" atau "user"';
    final list = entries(target);
    final limit = limitOf(target);
    int find() {
      final q = (oldText ?? '').trim();
      if (q.isEmpty) throw 'old_text wajib buat $action';
      final hits = [for (var i = 0; i < list.length; i++) if (list[i].contains(q)) i];
      if (hits.isEmpty) throw 'Ga ada entri yang mengandung "$q"';
      if (hits.length > 1) throw 'Ada ${hits.length} entri yang cocok, pakai old_text yang lebih spesifik';
      return hits.first;
    }

    switch (action) {
      case 'add':
        final c = (content ?? '').trim();
        if (c.isEmpty) throw 'content kosong';
        if (list.any((e) => e == c)) return 'Udah ada, ga ditambah.';
        list.add(c);
      case 'replace':
        final c = (content ?? '').trim();
        if (c.isEmpty) throw 'content kosong';
        list[find()] = c;
      case 'remove':
        list.removeAt(find());
      default:
        throw 'action harus add/replace/remove';
    }
    final size = list.join(entrySep).length;
    if (size > limit) {
      throw '${target.toUpperCase()} bakal $size/$limit karakter — kepenuhan. Gabungin/ringkas atau hapus entri lama dulu (replace/remove), lalu coba lagi.';
    }
    await setEntries(target, list);
    return 'OK. ${target.toUpperCase()} sekarang $size/$limit karakter, ${list.length} entri.';
  }

  // -------------------------------------------------------------- skills
  Future<void> _loadSkills() async {
    final list = <Skill>[];
    final d0 = Directory('${dir.path}/skills');
    if (await d0.exists()) {
      await for (final d in d0.list()) {
        final f = File('${d.path}/SKILL.md');
        if (d is Directory && await f.exists()) {
          final s = Brain.parseSkill(await f.readAsString(), fallbackName: d.uri.pathSegments.where((e) => e.isNotEmpty).last);
          if (s != null) list.add(s);
        }
      }
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    skills = list;
  }

  Skill? skill(String name) => skills.where((s) => s.name == name.trim().toLowerCase()).firstOrNull;

  // ------------------------------------------------------- built-in skills
  /// Skills that ship with the app for this profile (name → SKILL.md).
  /// Only the USER may change them; the agent gets read-only access.
  Map<String, String> get builtins => brain.builtinSkills[id] ?? const {};
  bool isBuiltin(String name) => builtins.containsKey(name.trim().toLowerCase());

  /// Built-in skill whose file no longer matches what ships with the app.
  bool isModified(Skill s) => isBuiltin(s.name) && s.raw.trim() != builtins[s.name]!.trim();

  /// Built-in skills the user deleted.
  List<String> get missingBuiltins => [for (final n in builtins.keys) if (skill(n) == null) n];

  static String lockedMsg(String name) =>
      'Skill "$name" itu skill BAWAAN — cuma user yang boleh ubah/hapus (Otak → Skill). '
      'Kalau butuh versi lain, bikin skill baru dengan nama beda (mis. "$name-custom").';

  /// Puts built-in skill [name] back to how it ships (user action).
  Future<void> resetSkill(String name) async {
    final raw = builtins[name];
    if (raw == null) throw 'Skill "$name" bukan skill bawaan';
    await Directory('${dir.path}/skills/$name').create(recursive: true);
    await File('${dir.path}/skills/$name/SKILL.md').writeAsString(raw.trim());
    await _loadSkills();
    brain._changed();
  }

  /// Restores every built-in skill (edited or deleted). Returns how many changed.
  Future<int> resetAllBuiltins() async {
    var n = 0;
    for (final name in builtins.keys) {
      final s = skill(name);
      if (s != null && !isModified(s)) continue;
      await resetSkill(name);
      n++;
    }
    return n;
  }

  /// [byAgent]: the call comes from the agent (tools / background review) —
  /// built-in skills are refused.
  Future<String> saveSkill(String raw, {String? expectName, bool byAgent = false}) async {
    final s = Brain.parseSkill(raw);
    if (s == null) throw 'SKILL.md wajib punya frontmatter:\n---\nname: nama-skill\ndescription: kapan dipakai\n---';
    if (!Brain._nameRe.hasMatch(s.name)) throw 'Nama skill harus huruf kecil/angka/strip, mis. "cek-server"';
    if (s.description.isEmpty) throw 'description wajib diisi (dipakai buat nentuin kapan skill relevan)';
    if (expectName != null && expectName != s.name) throw 'name di frontmatter ("${s.name}") beda sama "$expectName"';
    if (byAgent && isBuiltin(s.name)) throw lockedMsg(s.name);
    await Directory('${dir.path}/skills/${s.name}').create(recursive: true);
    await File('${dir.path}/skills/${s.name}/SKILL.md').writeAsString(raw.trim());
    await _loadSkills();
    brain._changed();
    return s.name;
  }

  Future<void> deleteSkill(String name, {bool byAgent = false}) async {
    if (byAgent && isBuiltin(name)) throw lockedMsg(name);
    final d = Directory('${dir.path}/skills/$name');
    if (await d.exists()) await d.delete(recursive: true);
    await _loadSkills();
    brain._changed();
  }

  // ------------------------------------------------------------- prompt
  String memoryBlock() {
    final m = memory.trim(), u = brain.user.trim();
    return """
## MEMORI KAMU (${m.length}/$memoryLimit karakter) — catatan lingkungan, fakta proyek, pelajaran
${m.isEmpty ? '(kosong)' : m}

## PROFIL USER (${u.length}/$userLimit karakter) — siapa user, preferensi, gaya kerja
${u.isEmpty ? '(kosong)' : u}""";
  }

  String skillsIndex() => skills.isEmpty
      ? '(belum ada skill)'
      : skills.map((s) => '- ${s.name}${isBuiltin(s.name) ? ' [bawaan, read-only]' : ''}: ${s.description}').join('\n');
}

/// File-backed "brain": profiles (SOUL.md, MEMORY.md, skills/), shared USER.md,
/// sessions/, cron.json. The getters below act on the ACTIVE profile.
class Brain extends ChangeNotifier {
  Brain._();
  static final Brain i = Brain._();

  late Directory root;
  final List<SessionMeta> sessions = [];
  List<CronJob> jobs = [];
  String user = '';
  List<AgentProfile> profiles = [];
  String activeId = 'default';

  /// Built-in presets already offered once (so a deleted preset stays deleted).
  List<String> presetsSeen = [];

  /// Built-in skills per profile id (default profile + each shipped preset).
  final Map<String, Map<String, String>> builtinSkills = {'default': Map.of(_defaultSkills)};

  /// Remembers which skills of preset [profileId] are built-in (from its files).
  void registerPresetSkills(String profileId, Map<String, String> files) {
    final re = RegExp(r'^skills/([a-z0-9][a-z0-9-]{1,48})/SKILL\.md$');
    builtinSkills[profileId] = {
      for (final e in files.entries)
        if (re.firstMatch(e.key) case final m?) m.group(1)!: e.value,
    };
  }
  final Map<String, ProfileBrain> _views = {};
  late ProfileBrain active;

  @visibleForTesting
  static String? rootOverride;

  void _changed() => notifyListeners();

  // ----- active-profile shortcuts (old API keeps working)
  String get soul => active.soul;
  String get memory => active.memory;
  List<Skill> get skills => active.skills;
  Future<void> saveSoul(String text) => active.saveSoul(text);
  List<String> entries(String target) => active.entries(target);
  int limitOf(String target) => active.limitOf(target);
  Future<void> setEntries(String target, List<String> list) => active.setEntries(target, list);
  Future<String> memoryOp(String action, String target, {String? content, String? oldText}) =>
      active.memoryOp(action, target, content: content, oldText: oldText);
  Skill? skill(String name) => active.skill(name);
  Future<String> saveSkill(String raw, {String? expectName}) => active.saveSkill(raw, expectName: expectName);
  Future<void> deleteSkill(String name) => active.deleteSkill(name);
  String memoryBlock() => active.memoryBlock();
  String skillsIndex() => active.skillsIndex();
  AgentProfile get activeProfile => profile(activeId)!;

  Future<void> load() async {
    root = Directory(rootOverride ?? '${(await getApplicationDocumentsDirectory()).path}/agent');
    await Directory('${root.path}/sessions').create(recursive: true);
    _views.clear();
    final uf = File('${root.path}/USER.md');
    user = await uf.exists() ? await uf.readAsString() : '';
    await _loadProfiles();
    active = await view(activeId);
    await _loadSessions();
    await _loadJobs();
    notifyListeners();
  }

  Directory dirOf(String id) => Directory(id == 'default' ? root.path : '${root.path}/profiles/$id');

  // ------------------------------------------------------------ profiles
  AgentProfile? profile(String? id) => profiles.where((p) => p.id == (id ?? 'default')).firstOrNull;

  Future<void> _loadProfiles() async {
    final f = File('${root.path}/profiles.json');
    profiles = [];
    activeId = 'default';
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map;
        profiles = (j['profiles'] as List).map((e) => AgentProfile.fromJson(Map<String, dynamic>.from(e))).toList();
        activeId = j['active'] ?? 'default';
        presetsSeen = (j['presetsSeen'] as List? ?? []).cast<String>();
      } catch (_) {}
    }
    if (profile('default') == null) profiles.insert(0, AgentProfile(id: 'default', name: 'satsh', emoji: '⚡'));
    if (profile(activeId) == null) activeId = 'default';
  }

  Future<void> saveProfiles() async {
    await File('${root.path}/profiles.json')
        .writeAsString(const JsonEncoder.withIndent(' ').convert(
            {'active': activeId, 'profiles': profiles.map((p) => p.toJson()).toList(), 'presetsSeen': presetsSeen}));
    notifyListeners();
  }

  /// Brain parts of profile [id], loaded once and cached.
  Future<ProfileBrain> view(String? id) async {
    final pid = (id != null && profile(id) != null) ? id : 'default';
    final v = _views[pid];
    if (v != null) return v;
    final pb = ProfileBrain(this, pid, dirOf(pid));
    await pb.load();
    return _views[pid] = pb;
  }

  Future<void> setActive(String id) async {
    if (profile(id) == null || id == activeId) return;
    activeId = id;
    active = await view(id);
    await saveProfiles();
  }

  static String slug(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'agent' : (s.length > 24 ? s.substring(0, 24) : s);
  }

  /// New profile. [copyFrom] clones that profile's soul & skills (not memory).
  Future<AgentProfile> createProfile(String name, {String emoji = '🤖', String desc = '', String? copyFrom}) async {
    var id = slug(name);
    if (id == 'default') id = 'default-2';
    for (var k = 2; profile(id) != null; k++) {
      id = '${slug(name)}-$k';
    }
    final p = AgentProfile(id: id, name: name.trim().isEmpty ? id : name.trim(), emoji: emoji, desc: desc);
    final d = dirOf(id);
    await Directory('${d.path}/skills').create(recursive: true);
    if (copyFrom != null) {
      final src = await view(copyFrom);
      await File('${d.path}/SOUL.md').writeAsString(src.soul);
      for (final sk in src.skills) {
        await Directory('${d.path}/skills/${sk.name}').create(recursive: true);
        await File('${d.path}/skills/${sk.name}/SKILL.md').writeAsString(sk.raw.isEmpty ? sk.body : sk.raw);
      }
    }
    profiles.add(p);
    await saveProfiles();
    return p;
  }

  /// Removes a profile (not the default). Its chats move to the default profile.
  Future<void> deleteProfile(String id) async {
    if (id == 'default' || profile(id) == null) return;
    profiles.removeWhere((p) => p.id == id);
    _views.remove(id);
    final d = dirOf(id);
    if (await d.exists()) await d.delete(recursive: true);
    for (final m in sessions.where((m) => m.profile == id)) {
      m.profile = null;
    }
    for (final j in jobs.where((j) => j.profile == id)) {
      j.profile = null;
    }
    await _saveIndex();
    await saveJobs();
    if (activeId == id) {
      activeId = 'default';
      active = await view('default');
    }
    await saveProfiles();
  }

  /// Installs a built-in preset: [files] maps paths like `profile.json`,
  /// `SOUL.md`, `skills/<name>/SKILL.md` to their text. Returns the profile.
  /// An existing profile with the same id is refreshed (soul + preset skills), memory kept.
  Future<AgentProfile> installPreset(Map<String, String> files) async {
    final meta = AgentProfile.fromJson(jsonDecode(files['profile.json']!) as Map<String, dynamic>);
    if (!AgentProfile.idRe.hasMatch(meta.id) || meta.id == 'default') throw 'id preset ga valid';
    registerPresetSkills(meta.id, files);
    final d = dirOf(meta.id);
    await Directory('${d.path}/skills').create(recursive: true);
    for (final e in files.entries) {
      final rel = e.key;
      final ok = rel == 'SOUL.md' ||
          RegExp(r'^LICENSE[\w.-]*$').hasMatch(rel) ||
          RegExp(r'^skills/[a-z0-9][a-z0-9-]{1,48}/SKILL\.md$').hasMatch(rel);
      if (!ok) continue;
      final f = File('${d.path}/$rel');
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value);
    }
    final cur = profile(meta.id);
    if (cur == null) {
      profiles.add(meta);
    } else {
      cur
        ..name = meta.name
        ..emoji = meta.emoji
        ..desc = meta.desc;
    }
    if (!presetsSeen.contains(meta.id)) presetsSeen.add(meta.id);
    await reloadProfile(meta.id);
    await saveProfiles();
    return profile(meta.id)!;
  }

  /// First run of a version that ships [ids]: install the ones never offered before.
  Future<List<String>> autoInstallPresets(Map<String, Future<Map<String, String>> Function()> presets) async {
    final added = <String>[];
    for (final e in presets.entries) {
      try {
        final files = await e.value();
        registerPresetSkills(e.key, files); // even if installed earlier: its skills stay read-only for the agent
        if (presetsSeen.contains(e.key)) continue;
        await installPreset(files);
        added.add(e.key);
      } catch (_) {
        if (!presetsSeen.contains(e.key)) presetsSeen.add(e.key); // broken preset: don't retry every start
        await saveProfiles();
      }
    }
    return added;
  }

  /// After files of a profile changed on disk (import), reload it.
  Future<void> reloadProfile(String id) async {
    _views.remove(id);
    if (id == activeId) active = await view(id);
  }

  // -------------------------------------------------------------- skills
  static final _nameRe = RegExp(r'^[a-z0-9][a-z0-9-]{1,48}$');

  static Skill? parseSkill(String raw, {String? fallbackName}) {
    final m = RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n?([\s\S]*)$').firstMatch(raw.trimLeft());
    String name = fallbackName ?? '', desc = '', body = raw;
    if (m != null) {
      for (final line in m.group(1)!.split('\n')) {
        final i = line.indexOf(':');
        if (i < 0) continue;
        final k = line.substring(0, i).trim();
        var v = line.substring(i + 1).trim();
        if (v.length >= 2 && (v.startsWith('"') && v.endsWith('"') || v.startsWith("'") && v.endsWith("'"))) {
          v = v.substring(1, v.length - 1);
        }
        if (k == 'name') name = v;
        if (k == 'description') desc = v;
      }
      body = m.group(2)!;
    }
    if (name.isEmpty) return null;
    return Skill(name: name, description: desc, body: body.trim(), raw: raw);
  }

  // ------------------------------------------------------------ sessions
  File _sf(String id) => File('${root.path}/sessions/$id.json');

  Future<void> _loadSessions() async {
    sessions.clear();
    final idx = File('${root.path}/sessions/index.json');
    if (await idx.exists()) {
      try {
        for (final e in jsonDecode(await idx.readAsString()) as List) {
          sessions.add(SessionMeta(e['id'], e['title'], e['updated'], unread: e['unread'] ?? false, cron: e['cron'] ?? false, profile: e['profile']));
        }
      } catch (_) {}
    }
    sessions.sort((a, b) => b.updated.compareTo(a.updated));
  }

  Future<void> _saveIndex() async {
    sessions.sort((a, b) => b.updated.compareTo(a.updated));
    await File('${root.path}/sessions/index.json').writeAsString(jsonEncode([
      for (final s in sessions)
        {'id': s.id, 'title': s.title, 'updated': s.updated, 'unread': s.unread, 'cron': s.cron, if (s.profile != null) 'profile': s.profile}
    ]));
  }

  /// Rewrites sessions/index.json (after an import wrote session files directly).
  Future<void> saveIndexPublic() async {
    await _saveIndex();
    notifyListeners();
  }

  Future<AgentSession?> openSession(String id) async {
    final f = _sf(id);
    if (!await f.exists()) return null;
    return AgentSession.fromJson(jsonDecode(await f.readAsString()));
  }

  Future<void> saveSession(AgentSession s) async {
    if (s.messages.isEmpty) return;
    s.updated = DateTime.now().millisecondsSinceEpoch;
    await _sf(s.id).writeAsString(jsonEncode(s.toJson()));
    final meta = sessions.where((m) => m.id == s.id).firstOrNull;
    if (meta == null) {
      sessions.add(SessionMeta(s.id, s.title, s.updated, unread: s.unread, cron: s.cronJobId != null, profile: s.profile));
    } else {
      meta
        ..title = s.title
        ..updated = s.updated
        ..unread = s.unread
        ..profile = s.profile;
    }
    await _saveIndex();
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    final s = await openSession(id);
    if (s == null) return;
    s.title = title;
    await saveSession(s);
  }

  Future<void> deleteSession(String id) async {
    final f = _sf(id);
    if (await f.exists()) await f.delete();
    sessions.removeWhere((m) => m.id == id);
    await _saveIndex();
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final m = sessions.where((m) => m.id == id).firstOrNull;
    if (m == null || !m.unread) return;
    m.unread = false;
    await _saveIndex();
    notifyListeners();
  }

  /// Keyword search across all sessions. Returns ranked hits with snippets.
  Future<List<Map<String, dynamic>>> searchSessions(String query, {String? excludeId, int limit = 5}) async {
    final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length > 1).toList();
    if (terms.isEmpty) return [];
    final hits = <Map<String, dynamic>>[];
    for (final meta in sessions) {
      if (meta.id == excludeId) continue;
      final s = await openSession(meta.id);
      if (s == null) continue;
      var score = 0;
      final snippets = <String>[];
      for (final m in s.messages) {
        if (m.role == 'tool' || m.text.isEmpty) continue;
        final low = m.text.toLowerCase();
        final matched = terms.where(low.contains).length;
        if (matched == 0) continue;
        score += matched * matched;
        if (snippets.length < 3) {
          final pos = low.indexOf(terms.firstWhere(low.contains));
          final a = (pos - 120).clamp(0, m.text.length);
          final b = (pos + 200).clamp(0, m.text.length);
          snippets.add('${m.role == 'user' ? 'User' : 'Agent'}: ${a > 0 ? '…' : ''}${m.text.substring(a, b).replaceAll('\n', ' ')}${b < m.text.length ? '…' : ''}');
        }
      }
      if (s.title.toLowerCase().contains(terms.first)) score += 3;
      if (score > 0) {
        hits.add({
          'id': s.id,
          'title': s.title,
          'date': DateTime.fromMillisecondsSinceEpoch(s.updated).toIso8601String().substring(0, 16),
          'score': score,
          'snippets': snippets,
        });
      }
    }
    hits.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return hits.take(limit).toList();
  }

  // ---------------------------------------------------------------- cron
  Future<void> _loadJobs() async {
    final f = File('${root.path}/cron.json');
    jobs = await f.exists()
        ? (jsonDecode(await f.readAsString()) as List).map((e) => CronJob.fromJson(Map<String, dynamic>.from(e))).toList()
        : [];
    // Markas was removed in 2.7.0; its scheduled meeting would only call tools
    // that no longer exist.
    final before = jobs.length;
    jobs.removeWhere((j) => j.name == 'Rapat Markas');
    if (jobs.length != before) await saveJobs();
  }

  Future<void> saveJobs() async {
    await File('${root.path}/cron.json').writeAsString(jsonEncode(jobs.map((j) => j.toJson()).toList()));
    notifyListeners();
  }

  /// Imports the single chat from v2 as the first session.
  Future<void> migrateLegacy(List<Msg> old) async {
    if (old.isEmpty || sessions.isNotEmpty) return;
    final first = old.firstWhere((m) => m.role == 'user', orElse: () => old.first);
    final s = AgentSession(id: newId(), title: titleFrom(first.text), messages: old);
    await saveSession(s);
  }
}

String titleFrom(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= 42 ? (t.isEmpty ? 'Chat baru' : t) : '${t.substring(0, 40)}…';
}
