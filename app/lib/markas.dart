import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'ssh_manager.dart';
import 'store.dart';

/// Markas = shared workspace (targets, achievements, chat) for Adam and his agents.
/// It lives on one of his servers as the `markas` CLI (SQLite); satsh talks to it over SSH.
class Markas extends ChangeNotifier {
  Markas._();
  static final Markas i = Markas._();

  static const cli = r'"$HOME/.local/bin/markas"';
  static const files = ['markas.py', 'hermes-SKILL.md', 'install.sh'];

  /// For tests: run [cmd] somewhere else (returns exit code, stdout, stderr).
  @visibleForTesting
  static Future<(int, String, String)> Function(String cmd, int timeoutS)? execOverride;

  String get hostId => Store.i.get<String>('markasHost', '');
  set hostId(String v) {
    Store.i.set('markasHost', v);
    notifyListeners();
  }

  Host? get host => Store.i.host(hostId);
  bool get configured => execOverride != null || host != null;

  /// Last snapshot (for the page).
  Map<String, dynamic>? snap;
  String? error;
  bool loading = false;

  /// Single-quote for POSIX sh.
  static String q(String s) => "'${s.replaceAll("'", "'\\''")}'";

  Future<(int, String, String)> exec(String cmd, {int timeoutS = 60}) async {
    final o = execOverride;
    if (o != null) return o(cmd, timeoutS);
    final h = host;
    if (h == null) throw 'Markas belum dipasang. Buka tab Markas → pilih server → Pasang.';
    final c = await SshManager.i.client(h);
    final s = await c.execute(cmd);
    final out = BytesBuilder(copy: false), err = BytesBuilder(copy: false);
    final a = s.stdout.listen((d) => out.length < 400000 ? out.add(d) : null);
    final b = s.stderr.listen((d) => err.length < 50000 ? err.add(d) : null);
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

  /// Runs `markas <args> --as <who>`; returns stdout (throws stderr on failure).
  Future<String> run(List<String> args, {String who = 'adam', bool json = false}) async {
    final cmd = [cli, ...args.map(q), '--as', q(who), if (json) '--json'].join(' ');
    final (code, so, se) = await exec(cmd);
    if (code == 127 || se.contains('markas: not found') || se.contains('No such file')) {
      throw 'Markas belum kepasang di server. Buka tab Markas → Pasang.';
    }
    if (code != 0) throw se.trim().isEmpty ? 'markas gagal (exit $code)' : se.trim().replaceFirst('markas: ', '');
    return so.trim();
  }

  Future<Map<String, dynamic>> status() async => jsonDecode(await run(['status'], json: true)) as Map<String, dynamic>;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      snap = await status();
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Uploads the CLI (+ Hermes skill) to [h] and runs the installer. Returns the installer output.
  Future<String> install(Host h, {Future<String> Function(String name)? load}) async {
    final get = load ?? (n) => rootBundle.loadString('assets/markas/$n');
    final sftp = await SshManager.i.sftp(h);
    try {
      final home = (await sftp.absolute('.'));
      final dir = '$home/.markas';
      try {
        await sftp.mkdir(dir);
      } catch (_) {}
      for (final n in files) {
        final f = await sftp.open('$dir/$n', mode: SftpFileOpenMode.create | SftpFileOpenMode.truncate | SftpFileOpenMode.write);
        await f.writeBytes(Uint8List.fromList(utf8.encode(await get(n))));
        await f.close();
      }
    } finally {
      sftp.close();
    }
    hostId = h.id;
    final (code, so, se) = await exec(r'sh "$HOME/.markas/install.sh"', timeoutS: 60);
    if (code != 0 || !so.contains('MARKAS_OK')) throw 'Pasang gagal: ${se.isEmpty ? so : se}';
    await refresh();
    return so;
  }

  static const rapatPrompt = '''[Rapat Markas]
Lu ketua rapat. Langkah:
1. markas brief → lihat target aktif & PIC-nya.
2. Buat tiap target aktif, minta update ke PIC-nya: hermes / agy → tanya_agent (pertanyaan singkat: target #ID, progress %, yang udah, kendala); muse → tanya_agent agent=muse lalu ikutin langkahnya (kalau kontrol HP ditolak/HP kekunci, lewatin Muse); satsh / web-designer → jawab sendiri dari riwayat & memori; adam → jangan ditanya, catat aja "nunggu update Adam".
3. Catat tiap jawaban ke markas: log (target=ID) dan target_update kalau progress-nya jelas berubah.
4. markas say rangkuman rapat (maks 8 baris) to=adam.
5. Jawaban akhir: rangkuman yang sama — target mana yang jalan, yang mandek, dan 1-3 hal yang butuh keputusan Adam.''';

  /// Asks Hermes (on the Markas server) one question via its one-shot CLI.
  Future<String> askHermes(String prompt, {int timeoutS = 300}) async {
    final full = '[Dari satsh lewat Markas — jawab singkat & jujur. Kalau ini soal progress, catat juga pakai skill markas.]\n$prompt';
    final (code, so, se) = await exec('bash -lc ${q('hermes -z ${q(full)}')} </dev/null', timeoutS: timeoutS);
    if (code == 127 || se.contains('command not found')) throw 'Hermes ga ketemu di server Markas (perintah `hermes`).';
    if (code != 0 && so.trim().isEmpty) throw 'Hermes error (exit $code): ${se.trim()}';
    return so.trim().isEmpty ? '(Hermes ga jawab apa-apa)' : so.trim();
  }
}
