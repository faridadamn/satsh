/// Turns a pasted connection line into host form fields:
///   ssh -p 2222 user@host · ssh user@host -p2222 · ssh -l user host
///   ssh -o Port=2222 -o User=user host · ssh://user@host:2222
///   user@host:2222 · host:2222 · [::1]:2222
///   mosh --ssh="ssh -p 2222" user@host   (connects over plain SSH)
///   sshpass -p 'pw' ssh -p 2222 user@host (password goes to the form)
class ParsedSsh {
  ParsedSsh({required this.host, this.port, this.user, this.password, this.command, this.notes = const []});
  final String host;
  final int? port;
  final String? user;
  final String? password;

  /// Remote command after the host (`ssh host -t "tmux attach"`).
  final String? command;

  /// Things we couldn't carry over, in plain words for the user.
  final List<String> notes;

  @override
  String toString() => 'ParsedSsh(${user ?? '-'}@$host:${port ?? '-'}${command == null ? '' : ' cmd="$command"'}, notes=$notes)';
}

class SshCommand {
  SshCommand._();

  // OpenSSH flags that take a value (`ssh -h` / man page).
  static const _withArg = {'b', 'B', 'c', 'D', 'E', 'e', 'F', 'I', 'i', 'J', 'L', 'l', 'm', 'O', 'o', 'p', 'P', 'Q', 'R', 'S', 'W', 'w'};

  /// True when [s] looks like more than a bare host name (so the host field
  /// should be split up instead of taken literally).
  static bool looksLikeCommand(String s) {
    final t = s.trim();
    return t.contains(' ') || t.contains('@') || t.startsWith('ssh://') || RegExp(r':\d+$').hasMatch(t);
  }

  /// Null when nothing usable was found.
  static ParsedSsh? parse(String input) {
    var text = input.trim();
    // A pasted shell prompt ("$ ssh …", "> ssh …") or a multi-line snippet: take the first ssh-ish line.
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return null;
    text = lines.firstWhere((l) => RegExp(r'(^|\s)(ssh|mosh|sshpass)(\s|$)|^ssh://').hasMatch(l), orElse: () => lines.first);
    text = text.replaceFirst(RegExp(r'^[$#>%]\s+'), '');

    final List<String> t;
    try {
      t = _split(text);
    } catch (_) {
      return null;
    }
    if (t.isEmpty) return null;

    final notes = <String>[];
    String? password;
    var i = 0;

    // sshpass -p PW … / sshpass -e …
    if (t[i] == 'sshpass') {
      i++;
      while (i < t.length && t[i].startsWith('-')) {
        final f = t[i];
        if (f == '-p' && i + 1 < t.length) {
          password = t[i + 1];
          i += 2;
        } else if (f.startsWith('-p') && f.length > 2) {
          password = f.substring(2);
          i++;
        } else if ((f == '-f' || f == '-d') && i + 1 < t.length) {
          i += 2;
        } else {
          i++;
        }
      }
    }

    // mosh: its own options, plus --ssh="ssh -p 2222 …" that we read like an ssh line.
    if (i < t.length && t[i] == 'mosh') {
      i++;
      ParsedSsh? inner;
      String? target;
      while (i < t.length) {
        final a = t[i];
        if (a == '--') break;
        if (a.startsWith('--ssh=') || a == '--ssh') {
          final v = a == '--ssh' ? (i + 1 < t.length ? t[++i] : '') : a.substring(6);
          inner = _parseSsh(_split(v), 1, notes, allowNoHost: true);
        } else if (a == '-p' || a == '--port' || a == '--server' || a == '--client' || a == '--predict' || a == '--bind-server') {
          i++; // value belongs to mosh (UDP port etc.), not to SSH
        } else if (a.startsWith('-')) {
          // --port=60001, -4, --no-init…
        } else {
          target ??= a;
        }
        i++;
      }
      if (target == null) return null;
      final base = _parseTarget(target);
      if (base == null) return null;
      notes.insert(0, 'satsh belum bisa mosh — nyambungnya pakai SSH biasa');
      return ParsedSsh(
        host: base.host,
        port: base.port ?? inner?.port,
        user: base.user ?? inner?.user,
        password: password,
        notes: notes,
      );
    }

    if (i < t.length && (t[i] == 'ssh' || t[i].endsWith('/ssh') || t[i] == 'ssh.exe')) {
      final r = _parseSsh(t, i + 1, notes);
      if (r == null) return null;
      return ParsedSsh(host: r.host, port: r.port, user: r.user, password: password, command: r.command, notes: notes);
    }

    // Bare forms: ssh://…, user@host:port, host:port
    if (t.length == 1) return _parseTarget(t.first);
    return null;
  }

  static ParsedSsh? _parseSsh(List<String> t, int i, List<String> notes, {bool allowNoHost = false}) {
    int? port;
    String? user;
    String? target;
    var rest = <String>[];
    while (i < t.length) {
      final a = t[i];
      if (target != null) {
        // OpenSSH also accepts options after the destination (`ssh host -p 22`).
        if (a.startsWith('-') && a.length > 1 && rest.isEmpty) {
          final consumed = _option(t, i, notes, (p) => port = p, (u) => user = u);
          if (consumed > 0) {
            i += consumed;
            continue;
          }
        }
        rest = t.sublist(i);
        break;
      }
      if (a == '--') {
        i++;
        if (i < t.length) target = t[i];
        i++;
        continue;
      }
      if (a.startsWith('-') && a.length > 1) {
        final consumed = _option(t, i, notes, (p) => port = p, (u) => user = u);
        i += consumed > 0 ? consumed : 1;
        continue;
      }
      target = a;
      i++;
    }
    if (target == null) {
      return allowNoHost ? ParsedSsh(host: '', port: port, user: user, notes: notes) : null;
    }
    final base = _parseTarget(target);
    if (base == null) return null;
    final cmd = rest.join(' ').trim();
    return ParsedSsh(
      host: base.host,
      port: port ?? base.port,
      user: base.user ?? user,
      command: cmd.isEmpty ? null : cmd,
      notes: notes,
    );
  }

  /// Handles one option at t[i]; returns how many tokens it used (0 = not an option we know).
  static int _option(List<String> t, int i, List<String> notes, void Function(int) setPort, void Function(String) setUser) {
    final a = t[i];
    if (a.startsWith('--')) return 1;
    // Bundled no-arg flags like -tt, -vA, -4
    final f = a[1];
    if (!_withArg.contains(f)) {
      var j = 1;
      while (j < a.length && !_withArg.contains(a[j])) {
        j++;
      }
      if (j == a.length) return 1;
      // e.g. "-tp2222": flags then an option with a value
      return _option([...t.sublist(0, i), '-${a.substring(j)}', ...t.sublist(i + 1)], i, notes, setPort, setUser);
    }
    final inline = a.length > 2 ? a.substring(2) : null;
    final v = inline ?? (i + 1 < t.length ? t[i + 1] : null);
    final used = inline != null ? 1 : 2;
    if (v == null) return 1;
    switch (f) {
      case 'p':
        final p = int.tryParse(v);
        if (p != null && p > 0 && p < 65536) setPort(p);
      case 'l':
        setUser(v);
      case 'i':
        notes.add('Key "$v" ada di komputer — ambil file-nya lewat "Ambil dari file" di bawah');
      case 'J':
        notes.add('Lewat jump host "$v": tambahin host itu dulu, terus pilih di "Nyambung lewat"');
      case 'L' || 'R' || 'D':
        notes.add('Port forward -$f $v: bikin di tab Tunnel');
      case 'o':
        final m = RegExp(r'^\s*(\w+)\s*[= ]\s*(.+?)\s*$').firstMatch(v);
        if (m != null) {
          final k = m[1]!.toLowerCase(), val = m[2]!;
          if (k == 'port') {
            final p = int.tryParse(val);
            if (p != null && p > 0 && p < 65536) setPort(p);
          } else if (k == 'user') {
            setUser(val);
          } else if (k == 'proxyjump') {
            notes.add('Lewat jump host "$val": tambahin host itu dulu, terus pilih di "Nyambung lewat"');
          } else if (k == 'identityfile') {
            notes.add('Key "$val" ada di komputer — ambil file-nya lewat "Ambil dari file" di bawah');
          }
        }
    }
    return used;
  }

  /// `ssh://user@host:port`, `user@host:port`, `user@host`, `host:port`, `[v6]:port`, `host`.
  static ParsedSsh? _parseTarget(String s) {
    var x = s.trim();
    if (x.isEmpty) return null;
    int? port;
    if (x.toLowerCase().startsWith('ssh://')) {
      x = x.substring(6);
      final slash = x.indexOf('/');
      if (slash >= 0) x = x.substring(0, slash);
    }
    String? user;
    final at = x.lastIndexOf('@');
    if (at >= 0) {
      user = x.substring(0, at);
      x = x.substring(at + 1);
      // ssh://user;fingerprint=…@host — keep the user name only
      final semi = user.indexOf(';');
      if (semi >= 0) user = user.substring(0, semi);
      if (user.isEmpty) user = null;
    }
    final v6 = RegExp(r'^\[([0-9a-fA-F:.%a-zA-Z]+)\](?::(\d+))?$').firstMatch(x);
    if (v6 != null) {
      x = v6[1]!;
      if (v6[2] != null) port = int.tryParse(v6[2]!);
    } else {
      final m = RegExp(r'^([^:\s]+):(\d+)$').firstMatch(x);
      if (m != null) {
        x = m[1]!;
        port = int.tryParse(m[2]!);
      }
    }
    if (port != null && (port <= 0 || port >= 65536)) port = null;
    if (!RegExp(r'^[A-Za-z0-9._\-:%]+$').hasMatch(x)) return null;
    return ParsedSsh(host: x, port: port, user: user);
  }

  /// POSIX-ish word splitting: '…', "…", backslash escapes.
  static List<String> _split(String s) {
    final out = <String>[];
    final cur = StringBuffer();
    var has = false;
    String? q;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (q == "'") {
        if (c == "'") {
          q = null;
        } else {
          cur.write(c);
        }
      } else if (q == '"') {
        if (c == '"') {
          q = null;
        } else if (c == r'\' && i + 1 < s.length && r'"\$`'.contains(s[i + 1])) {
          cur.write(s[++i]);
        } else {
          cur.write(c);
        }
      } else if (c == "'" || c == '"') {
        q = c;
        has = true;
      } else if (c == r'\' && i + 1 < s.length) {
        cur.write(s[++i]);
        has = true;
      } else if (c == ' ' || c == '\t') {
        if (has || cur.isNotEmpty) out.add(cur.toString());
        cur.clear();
        has = false;
      } else {
        cur.write(c);
        has = true;
      }
    }
    if (q != null) throw const FormatException('kutip ga ketutup');
    if (has || cur.isNotEmpty) out.add(cur.toString());
    return out;
  }
}
