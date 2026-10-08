import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../error_log.dart';
import '../store.dart';
import 'llm.dart';

/// One saved provider profile. Several can be kept; the enabled ones form a
/// fallback chain in list order.
class ProviderCfg {
  ProviderCfg({
    required this.id,
    required this.kind,
    required this.name,
    this.base = '',
    this.model = '',
    this.disabled = false,
    this.distro = '',
  });
  final String id;
  String kind; // openai | gemini | codex | external (base = hostId, model = command)
  String name;
  String base;
  String model;
  bool disabled;

  /// external only: proot-distro to hop into if the SSH login lands outside it ('' = never).
  String distro;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'base': base,
        'model': model,
        'disabled': disabled,
        if (distro.isNotEmpty) 'distro': distro,
      };
  factory ProviderCfg.fromJson(Map<String, dynamic> j) => ProviderCfg(
        id: j['id'],
        kind: j['kind'] ?? 'openai',
        name: j['name'] ?? 'Provider',
        base: j['base'] ?? '',
        model: j['model'] ?? '',
        disabled: j['disabled'] ?? false,
        distro: j['distro'] ?? '',
      );

  String get keyName => 'key_$id';
  String get label => kind == 'codex'
      ? 'ChatGPT login'
      : kind == 'gemini'
          ? 'Gemini'
          : kind == 'external'
              ? 'Agent eksternal (SSH)'
              : 'OpenAI-compat';
  bool get isExternal => kind == 'external';
}

const providerPresets = <(String, String, String, String)>[
  ('OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-4.1-mini'),
  ('DeepSeek', 'openai', 'https://api.deepseek.com/v1', 'deepseek-chat'),
  ('OpenRouter', 'openai', 'https://openrouter.ai/api/v1', 'openai/gpt-4.1-mini'),
  ('Groq', 'openai', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile'),
  ('Gemini (API key)', 'gemini', '', 'gemini-2.5-pro'),
  ('ChatGPT (login Codex)', 'codex', '', 'gpt-6.1-sol'),
  ('Antigravity (Termux)', 'external', '', 'agy --output-format stream-json {resume} -p {prompt}'),
  ('Custom', 'openai', '', ''),
];

class Providers {
  Providers._();

  static List<ProviderCfg> all() {
    final raw = Store.i.get<List>('providers', const []);
    return raw.map((e) => ProviderCfg.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static void saveAll(List<ProviderCfg> list) => Store.i.set('providers', list.map((p) => p.toJson()).toList());

  static String newPid() => Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');

  /// v3 → v4: turn the old single OpenAI/Gemini settings into saved profiles.
  static Future<void> migrate() async {
    final s = Store.i;
    if (s.cfg.containsKey('providers')) return;
    final list = <ProviderCfg>[];
    final oKey = await s.secret('openaiKey'), gKey = await s.secret('geminiKey');
    final usedGemini = s.get<String>('llm', 'openai') == 'gemini';
    if (oKey != null) {
      final base = s.get<String>('openaiBase', 'https://api.openai.com/v1');
      final name = providerPresets.where((p) => p.$3 == base).map((p) => p.$1).firstOrNull ?? 'OpenAI-compat';
      final p = ProviderCfg(id: newPid(), kind: 'openai', name: name, base: base, model: s.get<String>('openaiModel', 'gpt-4.1-mini'));
      await s.setSecret(p.keyName, oKey);
      list.add(p);
    }
    if (gKey != null) {
      final p = ProviderCfg(id: newPid(), kind: 'gemini', name: 'Gemini', model: s.get<String>('geminiModel', 'gemini-2.5-flash'));
      await s.setSecret(p.keyName, gKey);
      usedGemini ? list.insert(0, p) : list.add(p);
    }
    saveAll(list);
  }

  /// Provider by id, or by name (case-insensitive, exact first then contains).
  static ProviderCfg? find(String q) {
    final list = all().where((p) => !p.isExternal).toList();
    final l = q.trim().toLowerCase();
    if (l.isEmpty) return null;
    return list.where((p) => p.id == q.trim()).firstOrNull ??
        list.where((p) => p.name.toLowerCase() == l).firstOrNull ??
        list.where((p) => p.name.toLowerCase().contains(l)).firstOrNull;
  }

  static ProviderCfg? get primary => all().where((p) => !p.disabled).firstOrNull;

  static Future<LlmProvider> build(ProviderCfg p) async {
    if (p.isExternal) throw LlmError('${p.name} itu agent eksternal, bukan model API');
    if (p.kind == 'codex') return CodexProvider(p);
    final key = await Store.i.secret(p.keyName);
    if (key == null || key.isEmpty) throw LlmError('API key ${p.name} belum diisi');
    if (p.kind == 'gemini') return Gemini(apiKey: key, model: p.model.isEmpty ? 'gemini-2.5-flash' : p.model);
    return OpenAiCompat(baseUrl: p.base.isEmpty ? 'https://api.openai.com/v1' : p.base, apiKey: key, model: p.model.isEmpty ? 'gpt-4.1-mini' : p.model);
  }

  /// All enabled API providers in order; [prefer] (a provider id) goes first.
  /// [model] overrides the model of the [prefer]red provider (agent switched it for this chat).
  static Future<LlmProvider> chain({String? prefer, String? model}) async {
    final built = <(String, LlmProvider)>[];
    String? firstErr;
    final list = all().where((p) => !p.disabled && !p.isExternal).toList();
    if (prefer != null && prefer.isNotEmpty) {
      final i = list.indexWhere((p) => p.id == prefer);
      if (i > 0) list.insert(0, list.removeAt(i));
      if (i >= 0 && model != null && model.isNotEmpty) {
        final p = list.first;
        list[0] = ProviderCfg(id: p.id, kind: p.kind, name: '${p.name} · $model', base: p.base, model: model);
      }
    }
    for (final p in list) {
      try {
        built.add((p.name, await build(p)));
      } catch (e) {
        firstErr ??= '$e';
      }
    }
    if (built.isEmpty) {
      throw LlmError(firstErr ??
          (all().any((p) => p.isExternal && !p.disabled)
              ? 'Fitur ini butuh provider model API (OpenAI/Gemini/ChatGPT), agent eksternal ga bisa dipake di sini.'
              : 'Belum ada provider. Buka Pengaturan → Agent → Tambah provider.'));
    }
    return built.length == 1 ? built.first.$2 : FallbackProvider(built);
  }

  static Future<List<String>> models(ProviderCfg p) async {
    if (p.isExternal) return const [];
    if (p.kind == 'codex') return const ['gpt-6.1-sol', 'gpt-6-luna', 'gpt-6-astra', 'gpt-6-sol', 'gpt-5.5'];
    final key = await Store.i.secret(p.keyName) ?? '';
    if (p.kind == 'gemini') {
      final r = await http.get(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200'), headers: {'x-goog-api-key': key});
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      return [
        for (final m in jsonDecode(r.body)['models'] as List)
          if ((m['supportedGenerationMethods'] as List?)?.contains('generateContent') ?? false) (m['name'] as String).replaceFirst('models/', '')
      ];
    }
    final r = await http.get(Uri.parse('${(p.base.isEmpty ? 'https://api.openai.com/v1' : p.base).replaceAll(RegExp(r'/+$'), '')}/models'),
        headers: {'Authorization': 'Bearer $key'});
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return [for (final m in jsonDecode(r.body)['data'] as List) m['id'] as String]..sort();
  }
}

/// Tries each provider in order; the next one answers if one errors or hits a limit.
class FallbackProvider implements LlmProvider {
  FallbackProvider(this.items);
  final List<(String, LlmProvider)> items;
  String? lastUsed;

  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools) async {
    final errs = <String>[];
    for (final (name, p) in items) {
      try {
        final r = await p.chat(system, history, tools);
        lastUsed = name;
        return r;
      } catch (e, st) {
        // HTTP/limit errors are expected; anything else (e.g. a parsing crash) is a bug
        if (e is! LlmError && e is! TimeoutException && e is! SocketException) {
          ErrorLog.i.add('llm', e, st, context: {'provider': name});
        }
        errs.add('$name: $e');
      }
    }
    throw LlmError(errs.join(' | '));
  }
}

// =========================================================== ChatGPT / Codex
/// "Sign in with ChatGPT" the way Codex CLI does it (OAuth + PKCE), so the
/// agent runs on the user's ChatGPT plan instead of an API key.
class CodexAuth {
  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const issuer = 'https://auth.openai.com';
  static const port = 1455;
  static const redirect = 'http://localhost:$port/auth/callback';

  static http.Client client = http.Client();

  static String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  static Map<String, dynamic> jwtClaims(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return {};
    return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>?> tokens(String pid) async {
    final raw = await Store.i.secret('codex_$pid');
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> _save(String pid, Map<String, dynamic> t) => Store.i.setSecret('codex_$pid', jsonEncode(t));
  static Future<void> logout(String pid) => Store.i.setSecret('codex_$pid', null);

  /// Opens the browser, waits for the localhost callback, exchanges the code.
  static Future<Map<String, dynamic>> login(String pid, {Duration timeout = const Duration(minutes: 5)}) async {
    final rnd = Random.secure();
    final verifier = _b64url(List.generate(64, (_) => rnd.nextInt(256)));
    final challenge = _b64url(sha256.convert(utf8.encode(verifier)).bytes);
    final state = _b64url(List.generate(24, (_) => rnd.nextInt(256)));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
    final codeC = Completer<String>();
    server.listen((req) async {
      final q = req.uri.queryParameters;
      final ok = req.uri.path == '/auth/callback' && q['state'] == state && q['code'] != null;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html><body style="font-family:sans-serif;background:#0c0d12;color:#edeef3;display:grid;place-items:center;height:100vh;margin:0">'
          '<div style="text-align:center"><h1 style="color:${ok ? '#34d399' : '#ff5d5d'}">${ok ? 'Login berhasil ✓' : 'Login gagal'}</h1>'
          '<p>${ok ? 'Balik ke satsh ya bre.' : (q['error_description'] ?? q['error'] ?? 'Coba lagi dari satsh.')}</p></div></body></html>');
      await req.response.close();
      if (ok && !codeC.isCompleted) codeC.complete(q['code']!);
      if (!ok && q['error'] != null && !codeC.isCompleted) codeC.completeError(LlmError('Login ditolak: ${q['error_description'] ?? q['error']}'));
    });
    try {
      final url = Uri.parse('$issuer/oauth/authorize').replace(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'scope': 'openid profile email offline_access',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'id_token_add_organizations': 'true',
        'codex_cli_simplified_flow': 'true',
        'state': state,
        'originator': 'codex_cli_rs',
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw LlmError('Ga bisa buka browser');
      final code = await codeC.future.timeout(timeout, onTimeout: () => throw LlmError('Login kelamaan (5 menit), coba lagi'));
      final r = await client.post(Uri.parse('$issuer/oauth/token'), headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      }, body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirect,
        'client_id': clientId,
        'code_verifier': verifier,
      });
      if (r.statusCode != 200) throw LlmError('Tuker token gagal: HTTP ${r.statusCode} ${r.body}');
      final t = Map<String, dynamic>.from(jsonDecode(r.body));
      _decorate(t);
      await _save(pid, t);
      return t;
    } finally {
      await server.close(force: true);
    }
  }

  static void _decorate(Map<String, dynamic> t) {
    final id = jwtClaims(t['id_token'] ?? '');
    final auth = Map<String, dynamic>.from(id['https://api.openai.com/auth'] ?? {});
    t['email'] = id['email'] ?? t['email'];
    t['account_id'] = auth['chatgpt_account_id'] ?? t['account_id'];
    t['plan'] = auth['chatgpt_plan_type'] ?? t['plan'];
    final exp = jwtClaims(t['access_token'] ?? '')['exp'];
    t['expires_at'] = exp is int ? exp * 1000 : DateTime.now().millisecondsSinceEpoch + ((t['expires_in'] ?? 3600) as int) * 1000;
  }

  /// Valid access token, refreshing when it's about to expire.
  static Future<Map<String, dynamic>> fresh(String pid) async {
    final t = await tokens(pid);
    if (t == null) throw LlmError('ChatGPT belum login (Pengaturan → Agent → provider ChatGPT → Login)');
    if ((t['expires_at'] ?? 0) - DateTime.now().millisecondsSinceEpoch > 120000) return t;
    final r = await client.post(Uri.parse('$issuer/oauth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': clientId, 'grant_type': 'refresh_token', 'refresh_token': t['refresh_token'], 'scope': 'openid profile email'}));
    if (r.statusCode != 200) throw LlmError('Sesi ChatGPT habis, login ulang ya (HTTP ${r.statusCode})');
    final n = Map<String, dynamic>.from(jsonDecode(r.body));
    final merged = {...t, ...n};
    _decorate(merged);
    await _save(pid, merged);
    return merged;
  }
}

class CodexProvider implements LlmProvider {
  CodexProvider(this.cfg, {http.Client? client}) : _http = client ?? http.Client();
  final ProviderCfg cfg;
  final http.Client _http;
  static const endpoint = 'https://chatgpt.com/backend-api/codex/responses';
  static String? _officialPrompt;

  /// For tests.
  List<Map<String, dynamic>> debugInput(List<Msg> history) => _input(history);

  List<Map<String, dynamic>> _input(List<Msg> history) {
    final out = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> imgParts(List<String> b64s) =>
        [for (final b in b64s) {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,$b'}];
    withToolImages(history, (m) {
      switch (m.role) {
        case 'user':
          out.add({
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': m.text.isEmpty ? '(gambar)' : m.text},
              ...imgParts(imageB64s(m)),
            ]
          });
        case 'assistant':
          if (m.text.isNotEmpty) out.add({'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': m.text}]});
          for (final c in m.calls) {
            out.add({'type': 'function_call', 'call_id': c.id, 'name': c.name, 'arguments': jsonEncode(c.args)});
          }
        case 'tool':
          out.add({'type': 'function_call_output', 'call_id': m.callId, 'output': m.text});
      }
    }, (imgs) {
      out.add({
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': imageLabel(imgs)},
          ...imgParts([for (final (_, b) in imgs) b]),
        ]
      });
    });
    return out;
  }

  Future<String> _codexPrompt() async {
    if (_officialPrompt != null) return _officialPrompt!;
    for (final path in ['codex-rs/core/prompt.md', 'codex-rs/core/gpt_5_codex_prompt.md']) {
      final r = await _http.get(Uri.parse('https://raw.githubusercontent.com/openai/codex/main/$path'));
      if (r.statusCode == 200 && r.body.length > 200) return _officialPrompt = r.body;
    }
    throw LlmError('Server ChatGPT nolak instruksi custom & prompt Codex ga bisa diambil');
  }

  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools, {bool officialInstr = false}) async {
    final t = await CodexAuth.fresh(cfg.id);
    final input = _input(history);
    String instructions = system;
    if (officialInstr) {
      instructions = await _codexPrompt();
      input.insert(0, {'type': 'message', 'role': 'developer', 'content': [{'type': 'input_text', 'text': system}]});
    }
    final body = {
      'model': cfg.model.isEmpty ? 'gpt-6.1-sol' : cfg.model,
      'instructions': instructions,
      'input': input,
      'tools': [
        for (final s in tools) {'type': 'function', 'name': s.name, 'description': s.description, 'parameters': s.schema(), 'strict': false}
      ],
      'tool_choice': 'auto',
      'parallel_tool_calls': false,
      'store': false,
      'stream': true,
      'include': ['reasoning.encrypted_content'],
    };
    final req = http.Request('POST', Uri.parse(endpoint))
      ..headers.addAll({
        'Authorization': 'Bearer ${t['access_token']}',
        'chatgpt-account-id': '${t['account_id'] ?? ''}',
        'OpenAI-Beta': 'responses=experimental',
        'originator': 'codex_cli_rs',
        'session_id': Providers.newPid() + Providers.newPid(),
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(body);
    final res = await _http.send(req).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      final err = await res.stream.bytesToString();
      if (res.statusCode == 400 && !officialInstr && err.toLowerCase().contains('instruction')) {
        return chat(system, history, tools, officialInstr: true);
      }
      if (res.statusCode == 401) throw LlmError('Sesi ChatGPT ditolak (401), login ulang ya');
      if (res.statusCode == 429) throw LlmError('Limit ChatGPT kena (429): ${err.length > 200 ? err.substring(0, 200) : err}');
      throw LlmError('ChatGPT HTTP ${res.statusCode}: ${err.length > 300 ? err.substring(0, 300) : err}');
    }
    return parseSse(res.stream.transform(utf8.decoder).transform(const LineSplitter()));
  }

  /// Reads the Responses-API event stream into text + tool calls.
  static Future<LlmReply> parseSse(Stream<String> lines) async {
    final items = <Map<String, dynamic>>[];
    final text = StringBuffer();
    List? completedOutput;
    await for (final line in lines.timeout(const Duration(seconds: 180))) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      Map<String, dynamic> ev;
      try {
        ev = Map<String, dynamic>.from(jsonDecode(data));
      } catch (_) {
        continue;
      }
      switch (ev['type']) {
        case 'response.output_text.delta':
          text.write(ev['delta'] ?? '');
        case 'response.output_item.done':
          items.add(Map<String, dynamic>.from(ev['item'] ?? {}));
        case 'response.completed':
          completedOutput = (ev['response']?['output'] as List?);
        case 'response.failed':
        case 'error':
          final e = ev['response']?['error'] ?? ev['error'] ?? ev;
          throw LlmError('ChatGPT error: ${e is Map ? (e['message'] ?? e) : e}');
      }
    }
    final out = (completedOutput != null && completedOutput.isNotEmpty) ? completedOutput.map((e) => Map<String, dynamic>.from(e)).toList() : items;
    final calls = <ToolCall>[];
    final msgText = StringBuffer();
    for (final it in out) {
      if (it['type'] == 'function_call') {
        Map<String, dynamic> args = {};
        try {
          args = Map<String, dynamic>.from(jsonDecode(it['arguments'] ?? '{}'));
        } catch (_) {
          args = {'_raw': it['arguments']};
        }
        calls.add(ToolCall(id: it['call_id'] ?? it['id'] ?? 'c${calls.length}', name: it['name'], args: args));
      } else if (it['type'] == 'message') {
        for (final c in (it['content'] as List? ?? [])) {
          if (c['type'] == 'output_text') msgText.write(c['text'] ?? '');
        }
      }
    }
    return LlmReply(msgText.isNotEmpty ? msgText.toString() : text.toString(), calls);
  }
}
