// Agent picks its own model: list what's configured, switch this chat's model,
// or call a special model once (image generation).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../store.dart';
import '../vision.dart';
import 'brain.dart';
import 'llm.dart';
import 'providers.dart';
import 'tools.dart';

class GeneratedImage {
  GeneratedImage(this.bytes, this.mime, [this.note = '']);
  final Uint8List bytes;
  final String mime;
  final String note; // text the model sent alongside
  String get ext => mime.contains('png') ? 'png' : mime.contains('webp') ? 'webp' : 'jpg';
}

class ImageGen {
  ImageGen._();
  static http.Client client = http.Client();

  static final _dataUri = RegExp(r'data:(image/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=_-]+)');
  static final _httpImg = RegExp(r'!\[[^\]]*\]\((https?://[^)\s]+)\)');

  /// One picture from [model] on provider [p]. OpenAI-compat: /images/generations first,
  /// then chat completions (9router/OpenRouter put the picture in the reply). Gemini: inline image.
  static Future<GeneratedImage> generate(ProviderCfg p, String model, String prompt, {String size = '1024x1024'}) async {
    if (p.kind == 'codex' || p.isExternal) throw '${p.name} ga bisa bikin gambar lewat API. Pilih provider OpenAI-compat atau Gemini.';
    final key = await Store.i.secret(p.keyName) ?? '';
    if (key.isEmpty) throw 'API key ${p.name} belum diisi';
    if (p.kind == 'gemini') return _gemini(key, model, prompt);
    final base = (p.base.isEmpty ? 'https://api.openai.com/v1' : p.base).replaceAll(RegExp(r'/+$'), '');
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $key', 'X-Title': 'satsh'};
    String? firstErr;
    try {
      final r = await client
          .post(Uri.parse('$base/images/generations'),
              headers: headers, body: jsonEncode({'model': model, 'prompt': prompt, 'n': 1, 'size': size, 'response_format': 'b64_json'}))
          .timeout(const Duration(seconds: 180));
      if (r.statusCode == 200) {
        final d = ((jsonDecode(utf8.decode(r.bodyBytes)) as Map)['data'] as List?)?.firstOrNull as Map?;
        if (d?['b64_json'] is String) return GeneratedImage(base64Decode(d!['b64_json']), 'image/png', '${d['revised_prompt'] ?? ''}');
        if (d?['url'] is String) return await _download(d!['url']);
      }
      firstErr = 'images/generations HTTP ${r.statusCode}';
    } on FormatException catch (e) {
      firstErr = 'images/generations: $e';
    }
    // chat-completions route
    final r = await client
        .post(Uri.parse('$base/chat/completions'),
            headers: headers,
            body: jsonEncode({
              'model': model,
              'stream': false,
              'modalities': ['image', 'text'],
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            }))
        .timeout(const Duration(seconds: 240));
    if (r.statusCode != 200) {
      throw 'Model "$model" ga bisa bikin gambar ($firstErr; chat HTTP ${r.statusCode}: ${_short(utf8.decode(r.bodyBytes, allowMalformed: true))})';
    }
    final j = decodeCompletion(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (j['error'] != null) throw 'Provider: ${j['error'] is Map ? j['error']['message'] : j['error']}';
    final choice = normalizeCompletion(j);
    final msg = (choice['message'] ?? const {}) as Map;
    // OpenRouter: message.images[].image_url.url
    for (final im in (msg['images'] as List? ?? const [])) {
      final u = (im is Map ? (im['image_url'] is Map ? im['image_url']['url'] : im['url']) : null) as String?;
      if (u != null) return _fromUrl(u, '${msg['content'] ?? ''}');
    }
    // content as parts
    final c = msg['content'];
    if (c is List) {
      for (final part in c) {
        if (part is Map && part['image_url'] != null) {
          final u = part['image_url'] is Map ? part['image_url']['url'] : part['image_url'];
          if (u is String) return _fromUrl(u, '');
        }
      }
    }
    // 9router: markdown ![image](data:…) / ![](https://…) in the text
    final text = c is String ? c : '';
    final m = _dataUri.firstMatch(text);
    if (m != null) return GeneratedImage(base64Decode(base64.normalize(m.group(2)!.replaceAll('-', '+').replaceAll('_', '/'))), m.group(1)!, text.replaceAll(_dataUri, '').trim());
    final h = _httpImg.firstMatch(text);
    if (h != null) return _download(h.group(1)!, text);
    throw 'Model "$model" ga ngirim gambar. Balasannya: ${_short(text.isEmpty ? '(kosong)' : text)}. Coba model khusus gambar (cek model_list).';
  }

  static Future<GeneratedImage> _gemini(String key, String model, String prompt) async {
    final r = await client
        .post(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'responseModalities': ['TEXT', 'IMAGE']
              },
            }))
        .timeout(const Duration(seconds: 240));
    if (r.statusCode != 200) throw 'Gemini HTTP ${r.statusCode}: ${_short(r.body)}';
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final cand = (j['candidates'] as List?)?.firstOrNull as Map?;
    if (cand == null) throw 'Ditolak Gemini (${j['promptFeedback']?['blockReason'] ?? 'kosong'})';
    final note = StringBuffer();
    for (final p in (cand['content']?['parts'] as List? ?? const [])) {
      final d = p['inlineData'] ?? p['inline_data'];
      if (d is Map && d['data'] is String) return GeneratedImage(base64Decode(d['data']), '${d['mimeType'] ?? d['mime_type'] ?? 'image/png'}', note.toString());
      if (p['text'] is String) note.write(p['text']);
    }
    throw 'Model "$model" ga ngirim gambar (${cand['finishReason'] ?? ''}). ${_short(note.toString())}';
  }

  static Future<GeneratedImage> _fromUrl(String u, String note) async {
    final m = _dataUri.firstMatch(u);
    if (m != null) return GeneratedImage(base64Decode(m.group(2)!), m.group(1)!, note);
    return _download(u, note);
  }

  static Future<GeneratedImage> _download(String url, [String note = '']) async {
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw 'Gagal download gambar (HTTP ${r.statusCode})';
    return GeneratedImage(r.bodyBytes, r.headers['content-type'] ?? 'image/png', note);
  }

  static String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

/// Where generated pictures land on the phone (gallery-visible).
String generatedDir() => '$phoneBase/Pictures/satsh';

/// Tools for [session]; [onSwitch] gets the new model (null = back to default).
List<AgentTool> modelTools({
  required AgentSession? session,
  required Future<void> Function(LlmProvider? llm, String label) onSwitch,
  Future<String> Function(Uint8List bytes, String ext)? saveImage,
}) {
  String label(ProviderCfg p, String model) => '${p.name} / ${model.isEmpty ? p.model : model}';
  return [
    AgentTool(
      const ToolSpec(
        name: 'model_list',
        description:
            'Lihat provider & model yang udah diset user (dan model yang lagi dipake chat ini). Kasih "provider" buat ambil daftar model yang tersedia di provider itu (opsional "filter", mis. "image").',
        params: {
          'provider': {'type': 'string', 'description': 'nama/id provider (opsional)'},
          'filter': {'type': 'string', 'description': 'saring nama model, mis. "image", "flash", "pro"'},
        },
      ),
      group: 'brain',
      (a) async {
        final list = Providers.all().where((p) => !p.isExternal).toList();
        if (list.isEmpty) return 'Belum ada provider model API.';
        final q = (a['provider'] as String?)?.trim() ?? '';
        if (q.isEmpty) {
          final cur = session?.model;
          return [
            'Provider (urutan = urutan fallback):',
            for (final p in list) '- ${p.name} [${p.label}] model: ${p.model.isEmpty ? '(default)' : p.model}${p.disabled ? ' (mati)' : ''} id=${p.id}',
            cur == null ? 'Chat ini: pakai model default profil.' : 'Chat ini lagi pakai: ${Providers.find(cur['provider']!)?.name ?? cur['provider']} / ${cur['model']}',
          ].join('\n');
        }
        final p = Providers.find(q);
        if (p == null) throw 'Provider "$q" ga ada. Yang ada: ${list.map((e) => e.name).join(', ')}';
        final models = await Providers.models(p);
        final f = (a['filter'] as String?)?.toLowerCase().trim() ?? '';
        final hit = f.isEmpty ? models : models.where((m) => m.toLowerCase().contains(f)).toList();
        if (hit.isEmpty) return 'Ga ada model${f.isEmpty ? '' : ' yang cocok "$f"'} di ${p.name}.';
        return clip('Model di ${p.name} (${hit.length}${f.isEmpty ? '' : ' cocok "$f"'}):\n${hit.take(200).join('\n')}', 6000);
      },
    ),
    AgentTool(
      const ToolSpec(
        name: 'model_switch',
        description:
            'Ganti model yang kamu pakai buat sisa chat ini (mulai langkah berikutnya) kalau tugasnya butuh model lain — mis. yang lebih pinter buat analisa berat, yang lebih murah/cepat buat kerjaan ringan, atau yang bisa lihat gambar. Ga ngubah pengaturan user. reset=true balik ke default. Buat BIKIN gambar pakai image_generate, bukan ini.',
        params: {
          'provider': {'type': 'string', 'description': 'nama/id provider (dari model_list)'},
          'model': {'type': 'string', 'description': 'nama model persis (kosong = model bawaan provider itu)'},
          'reason': {'type': 'string', 'description': 'kenapa ganti (ditampilin ke user)'},
          'reset': {'type': 'boolean'},
        },
      ),
      group: 'brain',
      (a) async {
        if (a['reset'] == true) {
          session?.model = null;
          await onSwitch(null, 'default');
          return 'Balik ke model default profil mulai langkah berikutnya.';
        }
        final p = Providers.find('${a['provider'] ?? ''}');
        if (p == null) throw 'Provider "${a['provider']}" ga ada. Cek model_list.';
        if (p.disabled) throw '${p.name} lagi dimatiin user.';
        final model = '${a['model'] ?? ''}'.trim();
        final llm = await Providers.chain(prefer: p.id, model: model);
        session?.model = {'provider': p.id, 'model': model.isEmpty ? p.model : model};
        await onSwitch(llm, label(p, model));
        return 'Oke, mulai langkah berikutnya pakai ${label(p, model)}${a['reason'] != null ? ' (${a['reason']})' : ''}. Kalau model ini error, provider lain tetep jadi cadangan.';
      },
    ),
    AgentTool(
      const ToolSpec(
        name: 'image_generate',
        description:
            'Bikin gambar dari teks pakai model khusus gambar (mis. gemini-*-image, gpt-image-*, dall-e-3, flux). Cek dulu model yang ada pakai model_list(provider, filter:"image"). Gambar disimpen ke galeri HP (Pictures/satsh) dan kamu bisa lihat hasilnya.',
        params: {
          'prompt': {'type': 'string', 'description': 'deskripsi gambar yang detail'},
          'provider': {'type': 'string', 'description': 'nama/id provider'},
          'model': {'type': 'string', 'description': 'model gambar'},
          'size': {'type': 'string', 'description': 'mis. 1024x1024 (opsional)'},
        },
        required: ['prompt', 'provider', 'model'],
      ),
      group: 'brain',
      (a) async {
        final p = Providers.find('${a['provider'] ?? ''}');
        if (p == null) throw 'Provider "${a['provider']}" ga ada. Cek model_list.';
        final img = await ImageGen.generate(p, '${a['model']}', '${a['prompt']}', size: '${a['size'] ?? '1024x1024'}');
        final path = await (saveImage ?? _saveToPhone)(img.bytes, img.ext);
        try {
          Vision.attach(await Vision.save((await Vision.jpeg(bytes: img.bytes, maxW: 768)).bytes, 'gen'));
        } catch (_) {
          // no native resizer (tests/desktop) → model just gets the path
        }
        return 'Gambar jadi: $path (${(img.bytes.length / 1024).round()} KB, ${p.name}/${a['model']})${img.note.isEmpty ? '' : '\nCatatan model: ${img.note}'}';
      },
    ),
  ];
}

Future<String> _saveToPhone(Uint8List bytes, String ext) async {
  final d = Directory(generatedDir());
  await d.create(recursive: true);
  final f = File('${d.path}/satsh_${DateTime.now().millisecondsSinceEpoch}.$ext');
  await f.writeAsBytes(bytes);
  return f.path;
}
