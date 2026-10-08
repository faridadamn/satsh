import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'models.dart';
import 'store.dart';

enum ConnState { connecting, ready, failed, closed }

/// UI hooks the manager needs (host-key trust, password prompts).
abstract class Prompts {
  Future<bool> trustHostKey(Host h, String type, String fp, String? oldFp);
  Future<String?> askPassword(Host h, {String? reason});
}

class TermSession extends ChangeNotifier {
  TermSession(this.host) : id = newId();

  final String id;
  final Host host;
  final terminal = Terminal(maxLines: 10000);
  final controller = TerminalController();
  SSHSession? shell;
  ConnState state = ConnState.connecting;
  String? error;
  bool ctrl = false;
  bool alt = false;
  StreamSubscription? _out, _err;

  String get title => host.label.isEmpty ? host.host : host.label;

  void _set(ConnState s, [String? e]) {
    state = s;
    error = e;
    notifyListeners();
  }

  /// Raw send (already-encoded terminal data).
  void sendRaw(String data) {
    final s = shell;
    if (s == null || state != ConnState.ready) return;
    s.write(Uint8List.fromList(utf8.encode(data)));
  }

  /// Applies sticky CTRL / ALT modifiers from the extra-keys bar.
  void sendInput(String data) {
    var out = data;
    if (ctrl && data.length == 1) {
      final c = data.toUpperCase().codeUnitAt(0);
      if (c >= 64 && c <= 95) out = String.fromCharCode(c - 64);
      if (data == ' ') out = '\x00';
      ctrl = false;
      notifyListeners();
    }
    if (alt) {
      out = '\x1b$out';
      alt = false;
      notifyListeners();
    }
    sendRaw(out);
  }

  void runCommand(String cmd, {bool enter = true}) {
    sendRaw(enter ? '$cmd\r' : cmd);
  }

  void toggleCtrl() {
    ctrl = !ctrl;
    notifyListeners();
  }

  void toggleAlt() {
    alt = !alt;
    notifyListeners();
  }

  Future<void> _dispose() async {
    await _out?.cancel();
    await _err?.cancel();
    shell?.close();
    shell = null;
  }
}

class ActiveForward {
  ActiveForward(this.server);
  final ServerSocket server;
  int connections = 0;
  int bytes = 0;
}

class SshManager extends ChangeNotifier {
  SshManager._();
  static final SshManager i = SshManager._();

  Prompts? prompts;

  final Map<String, SSHClient> _clients = {};
  final Map<String, Future<SSHClient>> _pending = {};
  final List<TermSession> sessions = [];
  final Map<String, ActiveForward> forwards = {};
  final Map<String, String> forwardErrors = {};

  /// Hosts kept connected by something other than a terminal/tunnel
  /// (jump hosts, the phone-server relay). closeSession won't drop these.
  final Set<String> pinned = {};

  bool isConnected(String hostId) =>
      _clients[hostId] != null && !_clients[hostId]!.isClosed;

  // ---------------------------------------------------------------- client
  Future<SSHClient> client(Host h) {
    final c = _clients[h.id];
    if (c != null && !c.isClosed) return Future.value(c);
    return _pending[h.id] ??= _connectWithRetry(h).whenComplete(() {
      _pending.remove(h.id);
    });
  }

  /// Wrong password → ask again (max 3x). A password that works gets saved.
  Future<SSHClient> _connectWithRetry(Host h) async {
    String? typed;
    for (var attempt = 0;; attempt++) {
      try {
        final c = await _connect(h, typedPw: typed);
        if (typed != null && Store.i.host(h.id) != null) {
          await Store.i.saveHost(h, password: typed);
        }
        return c;
      } on SSHAuthFailError {
        if (h.auth != 'password' || attempt >= 2) rethrow;
        typed = await prompts?.askPassword(h, reason: 'Password salah, coba lagi');
        if (typed == null) throw 'Login dibatalin';
      }
    }
  }

  Future<SSHClient> _connect(Host h, {String? typedPw}) async {
    final store = Store.i;
    List<SSHKeyPair>? identities;
    String? pw = typedPw ?? await store.password(h.id);

    if (h.auth == 'key') {
      final pem = await store.privateKey(h.id);
      if (pem != null && pem.trim().isNotEmpty) {
        final pp = await store.passphrase(h.id);
        identities = await compute(_parseKey, (pem, pp));
      }
    } else if (pw == null || pw.isEmpty) {
      pw = await prompts?.askPassword(h);
      if (pw == null) throw 'Dibatalin';
    }

    final SSHSocket socket;
    final jump = h.via.isEmpty || h.via == h.id ? null : Store.i.host(h.via);
    if (h.via.isNotEmpty && jump == null) throw 'Host perantara (via) udah kehapus';
    if (jump != null) {
      if (jump.via == h.id) throw 'Host perantara muter-muter (via saling nunjuk)';
      final jc = await this.client(jump);
      try {
        socket = await jc.forwardLocal(h.host, h.port);
      } on SSHChannelOpenError catch (e) {
        throw 'Lewat ${jump.label}: ${h.host}:${h.port} ga bisa dijangkau (${e.description})';
      }
    } else {
      socket = await SSHSocket.connect(h.host, h.port, timeout: const Duration(seconds: 12));
    }
    var askedPw = false;
    var keyRejected = false;
    final client = SSHClient(
      socket,
      username: h.username,
      identities: identities,
      keepAliveInterval: const Duration(seconds: 15),
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 60),
      onVerifyHostKey: (type, fpBytes) async {
        final fp = '$type ${utf8.decode(fpBytes)}';
        final known = store.knownHosts[h.hostKeyId];
        if (known == fp) return true;
        final ok = await prompts?.trustHostKey(h, type, utf8.decode(fpBytes), known) ?? false;
        if (ok) store.trustHostKey(h.hostKeyId, fp);
        keyRejected = !ok;
        return ok;
      },
      onPasswordRequest: () async {
        if (askedPw) return null; // wrong → handled by _connectWithRetry
        askedPw = true;
        // Key host whose key got rejected: offer password as a fallback.
        return pw ?? await prompts?.askPassword(h, reason: 'Key ditolak, coba pakai password');
      },
      onUserInfoRequest: (req) async {
        final answers = <String>[];
        for (final p in req.prompts) {
          if (!p.echo && pw != null && !askedPw) {
            askedPw = true;
            answers.add(pw);
          } else {
            answers.add(await prompts?.askPassword(h, reason: p.promptText) ?? '');
          }
        }
        return answers;
      },
    );
    try {
      await client.authenticated;
    } catch (e) {
      client.close();
      if (keyRejected) throw 'Host key ditolak — koneksi dibatalin';
      rethrow;
    }
    _clients[h.id] = client;
    Store.i.touch(h);
    client.done.whenComplete(() {
      if (_clients[h.id] == client) _clients.remove(h.id);
      _onClientGone(h.id);
    }).ignore();
    notifyListeners();
    return client;
  }

  void _onClientGone(String hostId) {
    for (final dep in Store.i.hosts.where((x) => x.via == hostId)) {
      _clients.remove(dep.id)?.close();
    }
    for (final s in sessions.where((s) => s.host.id == hostId)) {
      if (s.state == ConnState.ready) {
        s.terminal.write('\r\n\x1b[38;5;203m● koneksi putus\x1b[0m\r\n');
        s._set(ConnState.closed);
      }
    }
    for (final f in Store.i.forwards.where((f) => f.hostId == hostId).toList()) {
      if (forwards.containsKey(f.id)) stopForward(f.id);
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- terminals
  TermSession openTerminal(Host h) {
    final s = TermSession(h);
    sessions.add(s);
    notifyListeners();
    _startShell(s);
    return s;
  }

  Future<void> reconnect(TermSession s) async {
    await s._dispose();
    s.terminal.write('\r\n\x1b[38;5;45m↻ nyambung ulang…\x1b[0m\r\n');
    _startShell(s);
  }

  Future<void> _startShell(TermSession s) async {
    final h = s.host;
    s._set(ConnState.connecting);
    s.terminal.write('\x1b[38;5;99m⚡ satsh\x1b[0m → \x1b[1m${h.address}\x1b[0m\r\n');
    try {
      final c = await client(h);
      final shell = await c.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: s.terminal.viewWidth,
          height: s.terminal.viewHeight,
        ),
      );
      s.shell = shell;
      final dec1 = const Utf8Decoder(allowMalformed: true);
      final dec2 = const Utf8Decoder(allowMalformed: true);
      s._out = shell.stdout.cast<List<int>>().transform(dec1).listen(s.terminal.write);
      s._err = shell.stderr.cast<List<int>>().transform(dec2).listen(s.terminal.write);
      s.terminal.onOutput = s.sendInput;
      s.terminal.onResize = (w, hgt, pw, ph) {
        if (s.shell == shell) shell.resizeTerminal(w, hgt, pw, ph);
      };
      shell.resizeTerminal(s.terminal.viewWidth, s.terminal.viewHeight);
      s._set(ConnState.ready);
      if (h.startup.trim().isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 350), () => s.runCommand(h.startup.trim()));
      }
      shell.done.whenComplete(() {
        if (s.shell == shell && s.state == ConnState.ready) {
          s.terminal.write('\r\n\x1b[38;5;245m● sesi selesai\x1b[0m\r\n');
          s._set(ConnState.closed);
        }
      }).ignore();
    } catch (e) {
      final msg = _friendly(e);
      s.terminal.write('\r\n\x1b[38;5;203m✕ $msg\x1b[0m\r\n');
      s._set(ConnState.failed, msg);
    }
  }

  Future<void> closeSession(TermSession s) async {
    await s._dispose();
    sessions.remove(s);
    notifyListeners();
    releaseIfUnused(s.host.id);
  }

  bool inUse(String hostId) =>
      sessions.any((x) => x.host.id == hostId) ||
      Store.i.forwards.any((f) => f.hostId == hostId && forwards.containsKey(f.id)) ||
      pinned.contains(hostId) ||
      _clients.keys.any((id) => Store.i.host(id)?.via == hostId);

  /// Drop the connection if nothing else uses it (and its jump host too).
  void releaseIfUnused(String hostId) {
    if (inUse(hostId)) return;
    final via = Store.i.host(hostId)?.via ?? '';
    disconnect(hostId);
    if (via.isNotEmpty && via != hostId) releaseIfUnused(via);
  }

  void disconnect(String hostId) {
    pinned.remove(hostId);
    _clients.remove(hostId)?.close();
    notifyListeners();
  }

  // ------------------------------------------------------------------ sftp
  Future<SftpClient> sftp(Host h) async => (await client(h)).sftp();

  // -------------------------------------------------------------- forwards
  Future<void> startForward(Forward f) async {
    final h = Store.i.host(f.hostId);
    if (h == null) throw 'Host-nya udah kehapus';
    forwardErrors.remove(f.id);
    final c = await client(h);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, f.localPort, shared: false);
    final af = ActiveForward(server);
    forwards[f.id] = af;
    notifyListeners();
    server.listen((sock) async {
      af.connections++;
      notifyListeners();
      try {
        final ch = await c.forwardLocal(f.remoteHost, f.remotePort);
        final down = ch.stream.cast<List<int>>().map((d) {
          af.bytes += d.length;
          return d;
        }).pipe(sock).catchError((_) {});
        final up = sock.cast<List<int>>().pipe(ch.sink).catchError((_) {});
        await Future.any([down, up]);
        sock.destroy();
        ch.close().ignore();
      } catch (e) {
        forwardErrors[f.id] = _friendly(e);
        sock.destroy();
      } finally {
        af.connections--;
        notifyListeners();
      }
    }, onDone: () {
      forwards.remove(f.id);
      notifyListeners();
    });
  }

  Future<void> stopForward(String id) async {
    final af = forwards.remove(id);
    await af?.server.close();
    notifyListeners();
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (e is SocketException) {
      if (s.contains('Connection refused')) return 'Port ditolak (SSH-nya nyala belum?)';
      if (s.contains('timed out') || s.contains('Timeout')) return 'Timeout — server ga kejangkau';
      if (s.contains('Failed host lookup')) return 'Host ga ketemu (cek alamatnya)';
      if (s.contains('Address already in use')) return 'Port lokal udah kepake';
      return 'Jaringan error: ${e.message}';
    }
    if (e is SSHAuthFailError) return 'Login gagal — user/password/key salah';
    if (e is SSHHostkeyError) return 'Host key ditolak';
    if (e is SSHAuthAbortError) return 'Login dibatalin';
    if (e is SSHKeyDecryptError) return 'Passphrase key salah';
    if (e is SSHKeyDecodeError) return 'Format private key ga kebaca';
    if (e is SSHChannelOpenError) return 'Server nolak buka channel (${e.description})';
    return s.replaceFirst('Exception: ', '');
  }
}

List<SSHKeyPair> _parseKey((String, String?) a) =>
    SSHKeyPair.fromPem(a.$1, (a.$2 == null || a.$2!.isEmpty) ? null : a.$2);
