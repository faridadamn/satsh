import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'keygen.dart';
import 'models.dart';
import 'ssh_manager.dart';
import 'store.dart';

/// A device allowed to log in to this phone.
class PairedKey {
  PairedKey(this.line, this.name);
  final String line;
  final String name;
}

class ServerEvent {
  ServerEvent(this.text, {this.error = false}) : at = DateTime.now();
  final String text;
  final bool error;
  final DateTime at;
}

/// "Mode Server": runs satshd (bundled SSH server) so other phones can SSH
/// into this one, plus an optional reverse tunnel through a VPS ("relay")
/// so it's reachable from anywhere, even behind mobile-carrier NAT.
class PhoneServer extends ChangeNotifier {
  PhoneServer._();
  static final PhoneServer i = PhoneServer._();

  static const _native = MethodChannel('satsh/native');

  /// For tests: run a host-built satshd instead of the bundled one.
  @visibleForTesting
  static String? binaryOverride;
  @visibleForTesting
  static String? dirOverride;
  @visibleForTesting
  static String shellOverride = '/system/bin/sh';

  Process? _proc;
  bool starting = false;
  String? fingerprint; // SHA256:… of our host key
  String? error;
  final List<ServerEvent> log = [];
  List<PairedKey> paired = [];
  String? _token;
  DateTime? tokenExpiry;
  Completer<String>? _pairWaiter;

  // relay
  SSHRemoteForward? _rf;
  SSHClient? _relayClient;
  String relayStatus = ''; // '' off · 'connecting' · 'on' · 'error'
  String? relayError;
  Timer? _relayRetry;
  int _relayConns = 0;

  bool get running => _proc != null && fingerprint != null;
  int get port => Store.i.get<int>('srvPort', 2222);
  String get name => Store.i.get<String>('srvName', 'hp');
  String get relayHostId => Store.i.get<String>('srvRelayHost', '');
  int get relayPort => Store.i.get<int>('srvRelayPort', 0);
  bool get autoStart => Store.i.get<bool>('srvAuto', false);
  int get relayConnections => _relayConns;

  Future<String> get dir async {
    final d = dirOverride ?? '${(await getApplicationSupportDirectory()).path}/satshd';
    await Directory(d).create(recursive: true);
    return d;
  }

  void _event(String t, {bool error = false}) {
    log.insert(0, ServerEvent(t, error: error));
    if (log.length > 50) log.removeLast();
    notifyListeners();
  }

  /// Called once at app start.
  Future<void> init() async {
    await loadPaired();
    if (autoStart) start().ignore();
  }

  // ------------------------------------------------------------------ server
  Future<void> start() async {
    if (_proc != null || starting) return;
    starting = true;
    error = null;
    notifyListeners();
    try {
      final d = await dir;
      final bin = binaryOverride ?? '${await _native.invokeMethod<String>('nativeLibDir')}/libsatshd.so';
      if (!await File(bin).exists()) throw 'Server ga ada di APK ini (arsitektur HP ga didukung)';
      final p = await Process.start(bin, [
        '-dir', d,
        '-port', '$port',
        '-name', name,
        '-shell', shellOverride,
      ]);
      _proc = p;
      final ready = Completer<void>();
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => _onLine(l, ready));
      p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        if (l.trim().isNotEmpty) _event(l, error: true);
      });
      p.exitCode.then((code) {
        if (_proc != p) return;
        _proc = null;
        fingerprint = null;
        if (!ready.isCompleted) ready.completeError(error ?? 'Server berhenti (kode $code)');
        _stopRelay().ignore();
        _event('Server mati (kode $code)', error: code != 0);
      });
      await ready.future.timeout(const Duration(seconds: 8));
      _event('Server nyala di port $port');
      if (relayHostId.isNotEmpty) startRelay().ignore();
    } catch (e) {
      error = '$e'.replaceFirst('Exception: ', '');
      _proc?.kill();
      _proc = null;
      fingerprint = null;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  void _onLine(String l, Completer<void> ready) {
    final parts = l.split(' ');
    switch (parts.first) {
      case 'READY':
        fingerprint = parts.length > 2 ? parts[2] : '';
        if (!ready.isCompleted) ready.complete();
      case 'ERR':
        error = l.contains('address already in use')
            ? 'Port $port udah dipake aplikasi lain, ganti port'
            : l.substring(4);
        _event(error!, error: true);
      case 'LOGIN':
        _event('${parts.length > 1 ? parts[1] : '?'} masuk');
      case 'PAIRED':
        final who = parts.length > 1 ? parts[1] : 'device';
        _token = null;
        tokenExpiry = null;
        _event('$who dipasangin');
        loadPaired();
        _pairWaiter?.complete(who);
        _pairWaiter = null;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _stopRelay();
    final p = _proc;
    _proc = null;
    fingerprint = null;
    await cancelPairing();
    if (p != null) {
      p.kill();
      try {
        await p.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        p.kill(ProcessSignal.sigkill);
      }
    }
    notifyListeners();
  }

  Future<void> setConfig({int? port, String? name, String? relayHostId, int? relayPort, bool? autoStart}) async {
    final restart = running && (port != null && port != this.port || name != null && name != this.name);
    if (port != null) Store.i.set('srvPort', port);
    if (name != null) Store.i.set('srvName', name);
    if (relayHostId != null) Store.i.set('srvRelayHost', relayHostId);
    if (relayPort != null) Store.i.set('srvRelayPort', relayPort);
    if (autoStart != null) Store.i.set('srvAuto', autoStart);
    notifyListeners();
    if (restart) {
      await stop();
      await start();
    } else if (running && relayHostId != null) {
      await _stopRelay();
      if (relayHostId.isNotEmpty) startRelay().ignore();
    }
  }

  // ------------------------------------------------------------- paired keys
  Future<void> loadPaired() async {
    try {
      final f = File('${await dir}/authorized_keys');
      paired = !await f.exists()
          ? []
          : (await f.readAsLines())
              .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
              .map((l) {
              final p = l.trim().split(RegExp(r'\s+'));
              return PairedKey(l.trim(), p.length > 2 ? p.sublist(2).join(' ') : 'device');
            }).toList();
    } catch (_) {
      paired = [];
    }
    notifyListeners();
  }

  Future<void> revoke(PairedKey k) async {
    final f = File('${await dir}/authorized_keys');
    final lines = (await f.readAsLines()).where((l) => l.trim() != k.line).toList();
    await f.writeAsString(lines.isEmpty ? '' : '${lines.join('\n')}\n');
    _event('${k.name} dicabut');
    await loadPaired();
  }

  // ----------------------------------------------------------------- pairing
  /// Creates a one-time token (10 min) and returns the pairing code
  /// (`satsh://pair/<base64>`) for the QR.
  Future<String> startPairing() async {
    const abc = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    _token = List.generate(14, (_) => abc[r.nextInt(abc.length)]).join();
    tokenExpiry = DateTime.now().add(const Duration(minutes: 10));
    await File('${await dir}/pair_token')
        .writeAsString('$_token ${tokenExpiry!.millisecondsSinceEpoch ~/ 1000}\n', flush: true);
    notifyListeners();
    final relay = Store.i.host(relayHostId);
    final payload = {
      'v': 1,
      'n': name,
      'p': port,
      'a': await localAddresses(),
      'f': fingerprint,
      't': _token,
      if (relay != null && relayPort > 0 && relayStatus == 'on')
        'r': {'h': relay.host, 'P': relay.port, 'u': relay.username, 'p': relayPort},
    };
    return 'satsh://pair/${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
  }

  /// Completes with the paired device's name.
  Future<String> waitForPair() => (_pairWaiter ??= Completer<String>()).future;

  Future<void> cancelPairing() async {
    _token = null;
    tokenExpiry = null;
    try {
      final f = File('${await dir}/pair_token');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }

  static Future<List<String>> localAddresses() async {
    final out = <String>[];
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      // Tailscale (100.64/10) first: works from anywhere.
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) out.add(a.address);
        }
      }
      out.sort((a, b) => (_isTailscale(b) ? 1 : 0) - (_isTailscale(a) ? 1 : 0));
    } catch (_) {}
    return out;
  }

  static bool _isTailscale(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    return p.length == 4 && p[0] == 100 && (p[1] ?? 0) >= 64 && (p[1] ?? 0) < 128;
  }

  // ------------------------------------------------------------------- relay
  /// Reverse tunnel: VPS 127.0.0.1:relayPort → this phone's server.
  Future<void> startRelay() async {
    _relayRetry?.cancel();
    final h = Store.i.host(relayHostId);
    if (h == null || !running) return;
    var rp = relayPort;
    if (rp <= 0) {
      rp = 22000 + Random().nextInt(900);
      Store.i.set('srvRelayPort', rp);
    }
    relayStatus = 'connecting';
    relayError = null;
    notifyListeners();
    try {
      SshManager.i.pinned.add(h.id);
      final c = await SshManager.i.client(h);
      final rf = await c.forwardRemote(host: '127.0.0.1', port: rp);
      if (rf == null) throw 'VPS nolak buka port $rp (udah kepake? ganti port relay)';
      _rf = rf;
      _relayClient = c;
      relayStatus = 'on';
      _event('Relay aktif lewat ${h.label}');
      notifyListeners();
      rf.connections.listen(_pipeRelay);
      c.done.whenComplete(() {
        if (_rf != rf) return;
        _rf = null;
        if (running && relayHostId == h.id) {
          relayStatus = 'connecting';
          relayError = 'Koneksi ke VPS putus, nyoba lagi…';
          notifyListeners();
          _relayRetry = Timer(const Duration(seconds: 8), () => startRelay().ignore());
        }
      }).ignore();
    } catch (e) {
      relayStatus = 'error';
      relayError = '$e'.replaceFirst('Exception: ', '');
      _event('Relay gagal: $relayError', error: true);
      notifyListeners();
      if (running && relayHostId == h.id) {
        _relayRetry = Timer(const Duration(seconds: 30), () => startRelay().ignore());
      }
    }
  }

  Future<void> _pipeRelay(SSHForwardChannel ch) async {
    _relayConns++;
    notifyListeners();
    Socket? sock;
    try {
      sock = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 5));
      final down = ch.stream.cast<List<int>>().pipe(sock).catchError((_) {});
      final up = sock.cast<List<int>>().pipe(ch.sink).catchError((_) {});
      await Future.any([down, up]);
    } catch (_) {
    } finally {
      sock?.destroy();
      ch.destroy();
      _relayConns--;
      notifyListeners();
    }
  }

  Future<void> _stopRelay() async {
    _relayRetry?.cancel();
    _relayRetry = null;
    final rf = _rf, c = _relayClient;
    _rf = null;
    _relayClient = null;
    if (rf != null && c != null && !c.isClosed) {
      try {
        await c.cancelForwardRemote(rf).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    if (relayStatus.isNotEmpty) relayStatus = '';
    final id = relayHostId;
    if (id.isNotEmpty) {
      SshManager.i.pinned.remove(id);
      SshManager.i.releaseIfUnused(id);
    }
    notifyListeners();
  }
}

// ======================================================================
// Client side: pair THIS phone with another phone's server.
// ======================================================================

class PairCode {
  PairCode(this.raw);
  final Map<String, dynamic> raw;
  String get name => raw['n'] ?? 'hp';
  int get port => raw['p'] ?? 2222;
  List<String> get addresses => (raw['a'] as List? ?? []).cast<String>();
  String get fingerprint => raw['f'] ?? '';
  String get token => raw['t'] ?? '';
  Map<String, dynamic>? get relay => (raw['r'] as Map?)?.cast<String, dynamic>();

  static PairCode? parse(String text) {
    final m = RegExp(r'satsh://pair/([A-Za-z0-9_\-]+)').firstMatch(text.trim());
    if (m == null) return null;
    try {
      var b = m.group(1)!;
      b = b.padRight((b.length + 3) ~/ 4 * 4, '=');
      final j = jsonDecode(utf8.decode(base64Url.decode(b)));
      if (j is! Map || j['t'] == null) return null;
      return PairCode(j.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}

class PairResult {
  PairResult(this.host, this.route);
  final Host host;
  final String route; // human description
}

class PairClient {
  /// Pairs with the phone in [code]. Tries direct addresses (Wi-Fi /
  /// Tailscale) first, then the VPS relay if the code has one.
  static Future<PairResult> pair(PairCode code, {String deviceName = 'hp-lain', void Function(String)? progress}) async {
    final store = Store.i;
    // 1. Route
    String? addr;
    for (final a in code.addresses) {
      progress?.call('Nyoba langsung ke $a…');
      try {
        final s = await Socket.connect(a, code.port, timeout: const Duration(seconds: 3));
        s.destroy();
        addr = a;
        break;
      } catch (_) {}
    }
    Host? relayHost;
    final r = code.relay;
    if (addr == null) {
      if (r == null) {
        throw 'HP itu ga kejangkau langsung (beda jaringan) dan belum nyalain relay VPS. '
            'Nyalain "Relay lewat VPS" di HP itu, atau pakai Tailscale di dua-duanya.';
      }
      relayHost = store.hosts.where((h) =>
          h.host == r['h'] && h.port == (r['P'] ?? 22) && h.username == r['u'] && h.via.isEmpty).firstOrNull;
      if (relayHost == null) {
        throw 'HP itu nyambung lewat VPS ${r['u']}@${r['h']}. Tambahin dulu VPS itu di tab Host (login yang sama), terus scan lagi.';
      }
      progress?.call('Lewat VPS ${relayHost.label}…');
    }

    // 2. Key for this device
    progress?.call('Bikin kunci khusus…');
    final safe = deviceName.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final key = generateEd25519(comment: safe.isEmpty ? 'hp-lain' : safe);

    // 3. One-time login with the token, register our key
    progress?.call('Masangin…');
    final SSHSocket socket;
    if (relayHost != null) {
      final jc = await SshManager.i.client(relayHost);
      try {
        socket = await jc.forwardLocal('127.0.0.1', r!['p']);
      } on SSHChannelOpenError {
        throw 'Relay di VPS ga nyambung. Pastiin Mode Server di HP itu masih nyala.';
      }
    } else {
      socket = await SSHSocket.connect(addr!, code.port, timeout: const Duration(seconds: 10));
    }
    String? hostKeyType;
    final client = SSHClient(
      socket,
      username: 'satsh',
      onVerifyHostKey: (type, fp) {
        hostKeyType = type;
        return code.fingerprint.isEmpty || utf8.decode(fp) == code.fingerprint;
      },
      onPasswordRequest: () => code.token,
    );
    try {
      await client.authenticated.timeout(const Duration(seconds: 20));
    } on SSHHostkeyError {
      client.close();
      throw 'Kunci server beda sama QR — jangan-jangan bukan HP yang bener. Dibatalin.';
    } on SSHAuthFailError {
      client.close();
      throw 'Kode pairing udah kepake / kadaluarsa. Bikin kode baru di HP itu.';
    }
    final res = await client.run('satsh-pair ${key.publicLine}', stderr: true);
    client.close();
    final out = utf8.decode(res);
    if (!out.startsWith('ok')) throw 'Pairing ditolak: ${out.trim()}';

    // 4. Save host
    final h = Host(
      id: newId(),
      label: code.name,
      host: relayHost != null ? '127.0.0.1' : addr!,
      port: relayHost != null ? r!['p'] as int : code.port,
      username: 'satsh',
      auth: 'key',
      color: store.hosts.length,
      via: relayHost?.id ?? '',
    );
    await store.saveHost(h, key: key.privatePem);
    if (hostKeyType != null && code.fingerprint.isNotEmpty) {
      store.trustHostKey(h.hostKeyId, '$hostKeyType ${code.fingerprint}');
    }
    return PairResult(h, relayHost != null ? 'lewat VPS ${relayHost.label}' : 'langsung ke $addr');
  }
}
