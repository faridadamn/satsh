// Agent switches its own model and generates pictures with an image model.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/agent/model_tools.dart';
import 'package:satsh/agent/providers.dart';
import 'package:satsh/agent/tools.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AgentSession s;
  late List<(LlmProvider?, String)> switched;
  late List<String> saved;
  late List<AgentTool> tools;
  Future<String> run(String name, Map<String, dynamic> a) => tools.firstWhere((t) => t.spec.name == name).run(a);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'sec_key_r9': 'k9', 'sec_key_gm': 'kg'});
    await Store.i.load();
    Providers.saveAll([
      ProviderCfg(id: 'r9', kind: 'openai', name: '9router', base: 'https://r9.example/v1', model: 'ag/gemini-3.8-flash-high'),
      ProviderCfg(id: 'gm', kind: 'gemini', name: 'Gemini', model: 'gemini-2.5-flash'),
    ]);
    s = AgentSession(id: 's1');
    switched = [];
    saved = [];
    tools = modelTools(
      session: s,
      onSwitch: (llm, label) async => switched.add((llm, label)),
      saveImage: (b, ext) async {
        final f = File('${Directory.systemTemp.createTempSync('gen').path}/x.$ext')..writeAsBytesSync(b);
        saved.add(f.path);
        return f.path;
      },
    );
  });

  test('model_list shows providers and what this chat uses', () async {
    final out = await run('model_list', {});
    expect(out, contains('9router'));
    expect(out, contains('ag/gemini-3.8-flash-high'));
    expect(out, contains('default profil'));
  });

  test('model_switch remembers the pick on the chat, only for this chat', () async {
    final out = await run('model_switch', {'provider': '9router', 'model': 'cx/gpt-5.5', 'reason': 'analisa berat'});
    expect(out, contains('cx/gpt-5.5'));
    expect(s.model, {'provider': 'r9', 'model': 'cx/gpt-5.5'});
    expect(switched.single.$1, isNotNull);
    expect(switched.single.$2, '9router / cx/gpt-5.5');
    expect(Providers.find('r9')!.model, 'ag/gemini-3.8-flash-high', reason: 'user settings untouched');
    expect(AgentSession.fromJson(jsonDecode(jsonEncode(s.toJson()))).model, s.model, reason: 'survives restart');
    await run('model_switch', {'reset': true});
    expect(s.model, isNull);
    expect(switched.last.$1, isNull);
  });

  test('model_switch: unknown provider is a clear error', () async {
    expect(() => run('model_switch', {'provider': 'nope'}), throwsA(contains('ga ada')));
  });

  test('chain uses the switched model on that provider', () async {
    final sent = <Map>[];
    // chain() builds real clients; check the override through the cfg it builds instead
    final llm = await Providers.chain(prefer: 'r9', model: 'cx/gpt-5.5');
    expect(llm, isA<FallbackProvider>());
    final first = (llm as FallbackProvider).items.first;
    expect(first.$1, contains('cx/gpt-5.5'));
    expect((first.$2 as OpenAiCompat).model, 'cx/gpt-5.5');
    expect(sent, isEmpty);
  });

  test('image_generate: /images/generations b64', () async {
    ImageGen.client = MockClient((r) async {
      expect(r.url.path, '/v1/images/generations');
      expect(jsonDecode(r.body)['model'], 'gpt-image-1');
      return http.Response(jsonEncode({'data': [{'b64_json': base64Encode(png)}]}), 200);
    });
    final out = await run('image_generate', {'prompt': 'kucing', 'provider': '9router', 'model': 'gpt-image-1'});
    expect(out, startsWith('Gambar jadi:'));
    expect(File(saved.single).readAsBytesSync(), png);
  });

  test('image_generate: 9router answers in chat with a markdown data URI', () async {
    final paths = <String>[];
    ImageGen.client = MockClient((r) async {
      paths.add(r.url.path);
      if (r.url.path.endsWith('/images/generations')) return http.Response('{"error":{"message":"not found"}}', 404);
      expect(jsonDecode(r.body)['stream'], false);
      return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'Nih\n![image](data:image/png;base64,${base64Encode(png)})\n'}, 'finish_reason': 'stop'}
            ]
          }),
          200);
    });
    final out = await run('image_generate', {'prompt': 'logo', 'provider': '9router', 'model': 'ag/gemini-3.1-flash-image'});
    expect(paths, ['/v1/images/generations', '/v1/chat/completions']);
    expect(saved.single, endsWith('.png'));
    expect(File(saved.single).readAsBytesSync(), png);
    expect(out, contains('Nih'));
  });

  test('image_generate: OpenRouter style message.images', () async {
    ImageGen.client = MockClient((r) async => r.url.path.endsWith('/images/generations')
        ? http.Response('', 404)
        : http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '',
                    'images': [
                      {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,${base64Encode(png)}'}}
                    ]
                  },
                  'finish_reason': 'stop'
                }
              ]
            }),
            200));
    await run('image_generate', {'prompt': 'x', 'provider': '9router', 'model': 'google/gemini-2.5-flash-image'});
    expect(File(saved.single).readAsBytesSync(), png);
  });

  test('image_generate: text-only model says so', () async {
    ImageGen.client = MockClient((r) async => r.url.path.endsWith('/images/generations')
        ? http.Response('', 404)
        : http.Response('{"choices":[{"message":{"content":"aku cuma bisa teks"},"finish_reason":"stop"}]}', 200));
    expect(() => run('image_generate', {'prompt': 'x', 'provider': '9router', 'model': 'ag/gemini-3.8-flash-high'}),
        throwsA(contains('ga ngirim gambar')));
  });

  test('image_generate: Gemini inline image', () async {
    ImageGen.client = MockClient((r) async {
      expect(r.url.path, contains('gemini-2.5-flash-image:generateContent'));
      expect(jsonDecode(r.body)['generationConfig']['responseModalities'], contains('IMAGE'));
      return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'ok'},
                    {'inlineData': {'mimeType': 'image/png', 'data': base64Encode(png)}}
                  ]
                }
              }
            ]
          }),
          200);
    });
    await run('image_generate', {'prompt': 'x', 'provider': 'Gemini', 'model': 'gemini-2.5-flash-image'});
    expect(File(saved.single).readAsBytesSync(), png);
  });
}
