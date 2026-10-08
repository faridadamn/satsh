import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'brain.dart';

/// Portable "agent brain" zip — the SAME format satsh desktop (Windows 7/10)
/// reads and writes, so profiles move freely between phone and laptop.
///
/// ```
/// satsh-agent.json                 manifest (format, version, profiles…)
/// USER.md                          shared "about the user"
/// profiles/ID/SOUL.md
/// profiles/ID/MEMORY.md
/// profiles/ID/skills/NAME/SKILL.md
/// sessions/ID.json                 (optional)
/// cron.json                        (optional; imported paused)
/// ```
class AgentZip {
  static const format = 'satsh-agent';
  static const version = 1;
  static final _sessionRe = RegExp(r'^[0-9A-Za-z_-]{6,64}$');

  static Future<Uint8List> export(Brain b, {List<String>? profiles, bool sessions = false, bool jobs = false, String from = 'android'}) async {
    final ids = profiles ?? b.profiles.map((p) => p.id).toList();
    final a = Archive();
    void put(String name, String text) => a.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
    final metas = [for (final id in ids) if (b.profile(id) != null) b.profile(id)!.toJson()];
    final sessionIds = <String>[];
    for (final id in ids) {
      final v = await b.view(id);
      put('profiles/$id/SOUL.md', v.soul);
      put('profiles/$id/MEMORY.md', v.memory);
      for (final s in v.skills) {
        put('profiles/$id/skills/${s.name}/SKILL.md', s.raw.isEmpty ? s.body : s.raw);
      }
    }
    put('USER.md', b.user);
    if (sessions) {
      for (final m in b.sessions) {
        if (!ids.contains(m.profile ?? 'default')) continue;
        final f = File('${b.root.path}/sessions/${m.id}.json');
        if (!await f.exists()) continue;
        put('sessions/${m.id}.json', await f.readAsString());
        sessionIds.add(m.id);
      }
    }
    if (jobs) {
      put('cron.json', jsonEncode([for (final j in b.jobs) if (ids.contains(j.profile ?? 'default')) j.toJson()]));
    }
    put(
        'satsh-agent.json',
        const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'version': version,
          'from': from,
          'exported': DateTime.now().toIso8601String(),
          'profiles': metas,
          'sessions': sessionIds.length,
          'jobs': jobs,
        }));
    return ZipEncoder().encodeBytes(a);
  }

  /// Merges a zip in. Returns a human summary.
  static Future<String> import(Brain b, Uint8List bytes) async {
    final Archive a;
    try {
      a = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw 'Bukan file zip';
    }
    String? text(String name) {
      final f = a.findFile(name);
      if (f == null || !f.isFile) return null;
      return utf8.decode(f.content, allowMalformed: true);
    }

    final manRaw = text('satsh-agent.json');
    if (manRaw == null) throw 'Bukan zip otak agent satsh (satsh-agent.json ga ada)';
    final man = jsonDecode(manRaw) as Map<String, dynamic>;
    if (man['format'] != format) throw 'Format zip bukan $format';
    if ((man['version'] as num? ?? 1) > version) throw 'Zip dari satsh versi lebih baru — update app dulu';

    final notes = <String>[];
    final providerIds = <String>{}; // provider ids are device-specific
    try {
      for (final p in (await _providers())) {
        providerIds.add(p);
      }
    } catch (_) {}

    var memSkipped = 0;
    for (final raw in (man['profiles'] as List? ?? []).cast<Map>()) {
      final inc = AgentProfile.fromJson(Map<String, dynamic>.from(raw));
      if (!AgentProfile.idRe.hasMatch(inc.id)) continue;
      if (!providerIds.contains(inc.provider)) inc.provider = '';
      final existing = b.profile(inc.id);
      if (existing == null) {
        b.profiles.add(inc);
      } else {
        existing
          ..name = inc.name
          ..emoji = inc.emoji
          ..desc = inc.desc
          ..toolsOff = inc.toolsOff;
        if (inc.provider.isNotEmpty) existing.provider = inc.provider;
      }
      final dir = b.dirOf(inc.id);
      await Directory('${dir.path}/skills').create(recursive: true);
      final soul = text('profiles/${inc.id}/SOUL.md');
      if (soul != null && soul.trim().isNotEmpty) await File('${dir.path}/SOUL.md').writeAsString(soul);
      // memory: merge entries, never drop what's already here
      final memIn = text('profiles/${inc.id}/MEMORY.md') ?? '';
      final mf = File('${dir.path}/MEMORY.md');
      final (merged, skipped) = mergeEntries(await mf.exists() ? await mf.readAsString() : '', memIn, memoryLimit);
      memSkipped += skipped;
      await mf.writeAsString(merged);
      var skills = 0;
      for (final f in a.files) {
        final m = RegExp('^profiles/${RegExp.escape(inc.id)}/skills/([a-z0-9][a-z0-9-]{1,48})/SKILL\\.md\$').firstMatch(f.name);
        if (m == null || !f.isFile) continue;
        final raw = utf8.decode(f.content, allowMalformed: true);
        if (Brain.parseSkill(raw) == null) continue;
        await Directory('${dir.path}/skills/${m.group(1)}').create(recursive: true);
        await File('${dir.path}/skills/${m.group(1)}/SKILL.md').writeAsString(raw);
        skills++;
      }
      await b.reloadProfile(inc.id);
      notes.add('${inc.emoji} ${inc.name} ($skills skill)');
    }
    await b.saveProfiles();

    final userIn = text('USER.md');
    if (userIn != null) {
      final (merged, skipped) = mergeEntries(b.user, userIn, userLimit);
      memSkipped += skipped;
      await b.active.setEntries('user', merged.split(entrySep).where((e) => e.trim().isNotEmpty).toList());
    }

    var sess = 0;
    for (final f in a.files) {
      final m = RegExp(r'^sessions/([^/]+)\.json$').firstMatch(f.name);
      if (m == null || !f.isFile || !_sessionRe.hasMatch(m.group(1)!) || m.group(1) == 'index') continue;
      try {
        final s = AgentSession.fromJson(jsonDecode(utf8.decode(f.content)) as Map<String, dynamic>);
        if (s.id != m.group(1)) continue;
        if (s.profile != null && b.profile(s.profile) == null) s.profile = null;
        final local = b.sessions.where((x) => x.id == s.id).firstOrNull;
        if (local != null && local.updated >= s.updated) continue;
        // keep its timestamp: saveSession would bump it
        await File('${b.root.path}/sessions/${s.id}.json').writeAsString(jsonEncode(s.toJson()));
        if (local == null) {
          b.sessions.add(SessionMeta(s.id, s.title, s.updated, cron: s.cronJobId != null, profile: s.profile));
        } else {
          local
            ..title = s.title
            ..updated = s.updated
            ..profile = s.profile;
        }
        sess++;
      } catch (_) {}
    }
    if (sess > 0) await b.saveIndexPublic();

    var jobs = 0;
    final cron = text('cron.json');
    if (cron != null) {
      try {
        for (final e in (jsonDecode(cron) as List).cast<Map>()) {
          final j = CronJob.fromJson(Map<String, dynamic>.from(e));
          if (b.jobs.any((x) => x.id == j.id)) continue;
          j
            ..enabled = false
            ..lastRun = null
            ..sessionId = null;
          if (j.profile != null && b.profile(j.profile) == null) j.profile = null;
          b.jobs.add(j);
          jobs++;
        }
        if (jobs > 0) await b.saveJobs();
      } catch (_) {}
    }

    return [
      if (notes.isNotEmpty) 'Profil: ${notes.join(', ')}',
      if (userIn != null) 'Profil user digabung',
      if (sess > 0) '$sess sesi',
      if (jobs > 0) '$jobs jadwal (di-pause, nyalain manual)',
      if (memSkipped > 0) '$memSkipped entri memori ga muat (kepenuhan)',
      'dari ${man['from'] ?? '?'}',
    ].join(' · ');
  }

  /// Adds entries of [incoming] that [current] doesn't have yet, up to [limit] chars.
  static (String, int) mergeEntries(String current, String incoming, int limit) {
    List<String> split(String t) => t.split(entrySep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final out = split(current);
    var skipped = 0;
    for (final e in split(incoming)) {
      if (out.contains(e)) continue;
      if ([...out, e].join(entrySep).length > limit) {
        skipped++;
        continue;
      }
      out.add(e);
    }
    return (out.join(entrySep), skipped);
  }

  /// Hook for tests / the app to say which provider ids exist here.
  static Future<Iterable<String>> Function() providerIds = () async => const [];
  static Future<Iterable<String>> _providers() => providerIds();
}
