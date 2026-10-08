import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Everything persistent lives here. Non-secret data in SharedPreferences,
/// passwords / private keys in the Android Keystore-backed secure storage.
class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  late SharedPreferences _p;
  final _secure = const FlutterSecureStorage();

  List<Host> hosts = [];
  List<Snippet> snippets = [];
  List<Forward> forwards = [];
  Map<String, String> knownHosts = {};
  double fontSize = 13;

  /// Free-form settings (theme, agent provider, connectors…).
  Map<String, dynamic> cfg = {};

  T get<T>(String k, T def) => (cfg[k] as T?) ?? def;

  void set(String k, Object? v) {
    if (v == null) {
      cfg.remove(k);
    } else {
      cfg[k] = v;
    }
    _p.setString('cfg', jsonEncode(cfg));
    notifyListeners();
  }

  Future<String?> secret(String k) => _secure.read(key: 'sec_$k');
  Future<void> setSecret(String k, String? v) async {
    if (v == null || v.isEmpty) {
      await _secure.delete(key: 'sec_$k');
    } else {
      await _secure.write(key: 'sec_$k', value: v);
    }
    notifyListeners();
  }

  /// Full backup as JSON. Secrets only if [withSecrets].
  Future<String> exportJson({bool withSecrets = false}) async {
    final secrets = <String, String>{};
    if (withSecrets) {
      final all = await _secure.readAll();
      secrets.addAll(all);
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'satsh',
      'version': 1,
      'hosts': hosts.map((e) => e.toJson()).toList(),
      'snippets': snippets.map((e) => e.toJson()).toList(),
      'forwards': forwards.map((e) => e.toJson()).toList(),
      'known': knownHosts,
      'cfg': cfg,
      if (withSecrets) 'secrets': secrets,
    });
  }

  /// Merges a backup in (same ids get replaced). Returns count of hosts.
  Future<int> importJson(String text) async {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['app'] != 'satsh') throw 'Bukan file backup satsh';
    void merge<T>(List<T> into, List src, T Function(Map<String, dynamic>) f, String Function(T) id) {
      for (final raw in src.cast<Map<String, dynamic>>()) {
        final item = f(raw);
        into.removeWhere((e) => id(e) == id(item));
        into.add(item);
      }
    }

    merge<Host>(hosts, j['hosts'] ?? [], Host.fromJson, (e) => e.id);
    merge<Snippet>(snippets, j['snippets'] ?? [], Snippet.fromJson, (e) => e.id);
    merge<Forward>(forwards, j['forwards'] ?? [], Forward.fromJson, (e) => e.id);
    knownHosts.addAll(Map<String, String>.from(j['known'] ?? {}));
    cfg.addAll(Map<String, dynamic>.from(j['cfg'] ?? {}));
    for (final e in Map<String, String>.from(j['secrets'] ?? {}).entries) {
      await _secure.write(key: e.key, value: e.value);
    }
    _save('hosts', hosts.map((e) => e.toJson()));
    _save('snippets', snippets.map((e) => e.toJson()));
    _save('forwards', forwards.map((e) => e.toJson()));
    _p.setString('known', jsonEncode(knownHosts));
    _p.setString('cfg', jsonEncode(cfg));
    notifyListeners();
    return (j['hosts'] as List?)?.length ?? 0;
  }

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    cfg = Map<String, dynamic>.from(jsonDecode(_p.getString('cfg') ?? '{}'));
    hosts = _list('hosts').map(Host.fromJson).toList();
    snippets = _list('snippets').map(Snippet.fromJson).toList();
    forwards = _list('forwards').map(Forward.fromJson).toList();
    knownHosts = Map<String, String>.from(jsonDecode(_p.getString('known') ?? '{}'));
    fontSize = _p.getDouble('fontSize') ?? 13;
    if (!(_p.getBool('seeded') ?? false)) {
      snippets = [
        Snippet(id: newId(), name: 'htop', command: 'htop'),
        Snippet(id: newId(), name: 'disk', command: 'df -h'),
        Snippet(id: newId(), name: 'ram', command: 'free -h'),
        Snippet(id: newId(), name: 'ports', command: 'ss -tulpn'),
        Snippet(id: newId(), name: 'tmux', command: 'tmux new -A -s main'),
        Snippet(id: newId(), name: 'update', command: 'sudo apt update && sudo apt upgrade -y'),
        Snippet(id: newId(), name: 'logs', command: 'journalctl -f -n 100', autoRun: false),
      ];
      await _p.setBool('seeded', true);
      _save('snippets', snippets.map((e) => e.toJson()));
    }
  }

  List<Map<String, dynamic>> _list(String k) =>
      (jsonDecode(_p.getString(k) ?? '[]') as List).cast<Map<String, dynamic>>();

  void _save(String k, Iterable<Map<String, dynamic>> v) =>
      _p.setString(k, jsonEncode(v.toList()));

  // ---------- hosts ----------
  List<Host> get hostsSorted {
    final l = [...hosts];
    l.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    return l;
  }

  Host? host(String id) => hosts.where((h) => h.id == id).firstOrNull;

  Future<void> saveHost(Host h, {String? password, String? key, String? passphrase}) async {
    final idx = hosts.indexWhere((e) => e.id == h.id);
    if (idx >= 0) {
      hosts[idx] = h;
    } else {
      hosts.add(h);
    }
    if (password != null) await _secure.write(key: 'pw_${h.id}', value: password);
    if (key != null) await _secure.write(key: 'key_${h.id}', value: key);
    if (passphrase != null) await _secure.write(key: 'pp_${h.id}', value: passphrase);
    _save('hosts', hosts.map((e) => e.toJson()));
    notifyListeners();
  }

  void touch(Host h) {
    h.lastUsed = DateTime.now().millisecondsSinceEpoch;
    if (hosts.any((e) => e.id == h.id)) {
      _save('hosts', hosts.map((e) => e.toJson()));
      notifyListeners();
    }
  }

  Future<void> deleteHost(String id) async {
    hosts.removeWhere((e) => e.id == id);
    forwards.removeWhere((f) => f.hostId == id);
    for (final k in ['pw_', 'key_', 'pp_']) {
      await _secure.delete(key: '$k$id');
    }
    _save('hosts', hosts.map((e) => e.toJson()));
    _save('forwards', forwards.map((e) => e.toJson()));
    notifyListeners();
  }

  Future<String?> password(String id) => _secure.read(key: 'pw_$id');
  Future<String?> privateKey(String id) => _secure.read(key: 'key_$id');
  Future<String?> passphrase(String id) => _secure.read(key: 'pp_$id');

  // ---------- snippets ----------
  void saveSnippet(Snippet s) {
    final idx = snippets.indexWhere((e) => e.id == s.id);
    if (idx >= 0) {
      snippets[idx] = s;
    } else {
      snippets.add(s);
    }
    _save('snippets', snippets.map((e) => e.toJson()));
    notifyListeners();
  }

  void deleteSnippet(String id) {
    snippets.removeWhere((e) => e.id == id);
    _save('snippets', snippets.map((e) => e.toJson()));
    notifyListeners();
  }

  void reorderSnippets(int oldI, int newI) {
    final s = snippets.removeAt(oldI);
    snippets.insert(newI, s);
    _save('snippets', snippets.map((e) => e.toJson()));
    notifyListeners();
  }

  // ---------- forwards ----------
  void saveForward(Forward f) {
    final idx = forwards.indexWhere((e) => e.id == f.id);
    if (idx >= 0) {
      forwards[idx] = f;
    } else {
      forwards.add(f);
    }
    _save('forwards', forwards.map((e) => e.toJson()));
    notifyListeners();
  }

  void deleteForward(String id) {
    forwards.removeWhere((e) => e.id == id);
    _save('forwards', forwards.map((e) => e.toJson()));
    notifyListeners();
  }

  // ---------- misc ----------
  void trustHostKey(String hostKeyId, String fp) {
    knownHosts[hostKeyId] = fp;
    _p.setString('known', jsonEncode(knownHosts));
  }

  void setFontSize(double v) {
    fontSize = v.clamp(8, 24);
    _p.setDouble('fontSize', fontSize);
    notifyListeners();
  }
}
