import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../ssh_manager.dart';
import 'brain.dart';

/// Where a skill can be pushed to (an agent that reads SKILL.md folders on a server).
class SkillTarget {
  const SkillTarget(this.id, this.name, this.root, this.dirFor);
  final String id;
  final String name;

  /// Skills root on the server (shell path, `$HOME` allowed).
  final String root;

  /// Folder (relative to [root]) a pushed skill goes into.
  final String Function(String skill) dirFor;
}

/// Skill state on the server compared to satsh.
enum PushState { same, differs, missing }

class RemoteSkill {
  RemoteSkill(this.name, this.path, this.hash);
  final String name;
  final String path; // relative to the target root
  final String hash;
}

class PushStatus {
  PushStatus({required this.hasAgent, required this.remote});

  /// The target agent's folder exists on that server.
  final bool hasAgent;
  final List<RemoteSkill> remote;

  RemoteSkill? find(String name) => remote.where((r) => r.name == name).firstOrNull;

  PushState of(Skill s) {
    final r = find(s.name);
    if (r == null) return PushState.missing;
    return r.hash == SkillPush.hashOf(SkillPush.prepare(s.raw.isEmpty ? s.body : s.raw)) ? PushState.same : PushState.differs;
  }

  /// Skills that only live on the server (made by that agent) — can be pulled.
  List<RemoteSkill> onlyRemote(Iterable<String> local) => remote.where((r) => !local.contains(r.name)).toList();
}

/// Pushes satsh skills to other agents over SSH (and pulls theirs back).
/// Hermes Agent reads `~/.hermes/skills/<category>/<name>/SKILL.md` and picks up
/// new skills on its next session.
class SkillPush {
  SkillPush._();

  static final hermes = SkillTarget('hermes', 'Hermes', r'$HOME/.hermes/skills', (n) => n == 'markas' ? 'markas' : 'satsh/$n');
  static final targets = {hermes.id: hermes};

  /// For tests: run [cmd] somewhere else (exit code, stdout, stderr).
  @visibleForTesting
  static Future<(int, String, String)> Function(String cmd)? execOverride;

  static Future<(int, String, String)> _exec(Host h, String cmd, {int timeoutS = 45}) async {
    final o = execOverride;
    if (o != null) return o(cmd);
    final c = await SshManager.i.client(h);
    final s = await c.execute(cmd);
    final out = BytesBuilder(copy: false), err = BytesBuilder(copy: false);
    final a = s.stdout.listen(out.add), b = s.stderr.listen((d) => err.length < 20000 ? err.add(d) : null);
    try {
      await s.done.timeout(Duration(seconds: timeoutS));
    } on TimeoutException {
      s.kill(SSHSignal.KILL);
      s.close();
      throw 'Kelamaan (>${timeoutS}s) di ${h.label}';
    } finally {
      await a.cancel();
      await b.cancel();
    }
    return (s.exitCode ?? -1, utf8.decode(out.takeBytes(), allowMalformed: true), utf8.decode(err.takeBytes(), allowMalformed: true));
  }

  /// The Markas skill for Hermes that ships with satsh (assets/markas/hermes-SKILL.md).
  static Future<Skill?> markasSkill() async {
    try {
      return Brain.parseSkill(await rootBundle.loadString('assets/markas/hermes-SKILL.md'), fallbackName: 'markas');
    } catch (_) {
      return null;
    }
  }

  static String q(String s) => "'${s.replaceAll("'", "'\\''")}'";

  static String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();

  /// What actually lands on the server: same SKILL.md, plus the `version`
  /// field Hermes expects when it's missing.
  static String prepare(String raw) {
    final t = raw.trim();
    final m = RegExp(r'^---\s*\n([\s\S]*?)\n---').firstMatch(t);
    if (m == null || RegExp(r'^version\s*:', multiLine: true).hasMatch(m.group(1)!)) return '$t\n';
    return '${t.substring(0, m.end - 3)}version: 1.0.0\n${t.substring(m.end - 3)}\n';
  }

  /// Lists skills on the server with their hashes.
  static Future<PushStatus> status(Host h, {SkillTarget? target}) async {
    final t = target ?? hermes;
    final cmd = 'R="${t.root}"; [ -d "\$R" ] || [ -d "\$(dirname "\$R")" ] || { echo NOAGENT; exit 0; }; '
        'echo AGENT; [ -d "\$R" ] || exit 0; cd "\$R" && '
        'find . -maxdepth 4 -name SKILL.md -not -path "./.hub/*" -not -path "*/node_modules/*" 2>/dev/null | '
        'while IFS= read -r f; do printf "%s\\t%s\\n" "\$(sha256sum "\$f" 2>/dev/null | cut -c1-64)" "\$f"; done';
    final (code, so, se) = await _exec(h, cmd);
    if (code != 0) throw 'Gagal baca skill di ${h.label}: ${se.trim().isEmpty ? 'exit $code' : se.trim()}';
    final lines = const LineSplitter().convert(so);
    if (lines.isEmpty || lines.first.trim() == 'NOAGENT') return PushStatus(hasAgent: false, remote: []);
    final remote = <RemoteSkill>[];
    for (final l in lines.skip(1)) {
      final i = l.indexOf('\t');
      if (i < 0) continue;
      final path = l.substring(i + 1).replaceFirst(RegExp(r'^\./'), '');
      final parts = path.split('/');
      if (parts.length < 2) continue;
      remote.add(RemoteSkill(parts[parts.length - 2], path, l.substring(0, i).trim()));
    }
    return PushStatus(hasAgent: true, remote: remote);
  }

  /// Writes [skill] to the server. Returns the remote path.
  static Future<String> push(Host h, Skill skill, {SkillTarget? target}) async {
    final t = target ?? hermes;
    final text = prepare(skill.raw.isEmpty ? skill.body : skill.raw);
    final dir = '${t.root}/${t.dirFor(skill.name)}';
    final b64 = base64.encode(utf8.encode(text));
    final cmd = 'D="$dir"; mkdir -p "\$D" && printf %s ${q(b64)} | base64 -d > "\$D/SKILL.md.tmp" && mv "\$D/SKILL.md.tmp" "\$D/SKILL.md" && '
        'printf %s ${q(jsonEncode({'from': 'satsh', 'name': skill.name, 'sha256': hashOf(text), 'at': DateTime.now().toIso8601String().substring(0, 19)}))} > "\$D/.satsh-push.json" && echo PUSHED';
    final (code, so, se) = await _exec(h, cmd);
    if (code != 0 || !so.contains('PUSHED')) throw 'Push "${skill.name}" gagal: ${se.trim().isEmpty ? 'exit $code' : se.trim()}';
    return '${t.root.replaceFirst(r'$HOME', '~')}/${t.dirFor(skill.name)}/SKILL.md';
  }

  /// Reads a skill from the server (to save it into satsh — user action).
  static Future<String> pull(Host h, RemoteSkill r, {SkillTarget? target}) async {
    final t = target ?? hermes;
    if (r.path.contains('..')) throw 'Path aneh';
    final (code, so, se) = await _exec(h, 'cat "${t.root}"/${q(r.path)}');
    if (code != 0) throw 'Gagal baca ${r.path}: ${se.trim()}';
    return so;
  }
}
