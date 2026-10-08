// Images on the wire: user photos + tool screenshots, for every provider.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/agent/providers.dart';

void main() {
  late String img1, img2;
  setUpAll(() {
    final d = Directory.systemTemp.createTempSync('vis');
    img1 = '${d.path}/a.jpg';
    img2 = '${d.path}/b.jpg';
    File(img1).writeAsBytesSync([1, 2, 3]);
    File(img2).writeAsBytesSync([4, 5, 6]);
  });
  final b1 = base64Encode([1, 2, 3]), b2 = base64Encode([4, 5, 6]);

  List<Msg> history() => [
        Msg(role: 'user', text: 'ini apa?', images: [img1]),
        Msg(role: 'assistant', text: '', calls: [
          ToolCall(id: 'c1', name: 'browser_look', args: {}),
          ToolCall(id: 'c2', name: 'browser_read', args: {}),
        ]),
        Msg(role: 'tool', callId: 'c1', name: 'browser_look', text: 'shot', images: [img2]),
        Msg(role: 'tool', callId: 'c2', name: 'browser_read', text: 'teks'),
        Msg(role: 'user', text: 'lanjut'),
      ];

  http.Response okOpenAi() => http.Response(jsonEncode({'choices': [{'message': {'content': 'ok'}}]}), 200);

  test('OpenAI: user image parts + screenshot in a user turn after ALL tool results', () async {
    late Map<String, dynamic> sent;
    final p = OpenAiCompat(
      baseUrl: 'https://x/v1',
      apiKey: 'k',
      model: 'm',
      client: MockClient((req) async {
        sent = jsonDecode(req.body);
        return okOpenAi();
      }),
    );
    await p.chat('sys', history(), const []);
    final m = sent['messages'] as List;
    expect(m[1]['content'][0], {'type': 'text', 'text': 'ini apa?'});
    expect(m[1]['content'][1]['image_url']['url'], 'data:image/jpeg;base64,$b1');
    expect(m[3]['role'], 'tool');
    expect(m[4]['role'], 'tool'); // tool results stay contiguous
    expect(m[5]['role'], 'user');
    expect(m[5]['content'][0]['text'], contains('browser_look'));
    expect(m[5]['content'][1]['image_url']['url'], 'data:image/jpeg;base64,$b2');
    expect(m[6], {'role': 'user', 'content': 'lanjut'});
  });

  test('OpenAI: text-only model rejects images → retried without them', () async {
    final bodies = <Map<String, dynamic>>[];
    final p = OpenAiCompat(
      baseUrl: 'https://x/v1',
      apiKey: 'k',
      model: 'deepseek-chat',
      client: MockClient((req) async {
        bodies.add(jsonDecode(req.body));
        if (bodies.length == 1) {
          return http.Response(jsonEncode({'error': {'message': 'unknown variant `image_url`, expected `text`'}}), 400);
        }
        return okOpenAi();
      }),
    );
    final r = await p.chat('sys', history(), const []);
    expect(r.text, 'ok');
    expect(bodies, hasLength(2));
    final m = bodies[1]['messages'] as List;
    expect(m[1]['content'], contains('ga bisa lihat gambar'));
    expect(m[5]['content'], contains('ga bisa lihat gambar'));
  });

  test('Gemini: inlineData for user photo and screenshot', () async {
    late Map<String, dynamic> sent;
    final p = Gemini(
      apiKey: 'k',
      model: 'g',
      client: MockClient((req) async {
        sent = jsonDecode(req.body);
        return http.Response(jsonEncode({'candidates': [{'content': {'parts': [{'text': 'ok'}]}}]}), 200);
      }),
    );
    await p.chat('sys', history(), const []);
    final c = sent['contents'] as List;
    expect(c[0]['parts'][1]['inlineData'], {'mimeType': 'image/jpeg', 'data': b1});
    final toolTurn = c[2]['parts'] as List;
    expect(toolTurn[0]['functionResponse']['name'], 'browser_look');
    expect(toolTurn[1]['functionResponse']['name'], 'browser_read');
    expect(toolTurn[3]['inlineData']['data'], b2);
  });

  test('ChatGPT/Codex: input_image parts', () async {
    final p = CodexProvider(ProviderCfg(id: 'x', kind: 'codex', name: 'ChatGPT'));
    final input = p.debugInput(history());
    expect(input[0]['content'][1], {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,$b1'});
    expect(input[3]['type'], 'function_call_output');
    expect(input[4]['type'], 'function_call_output');
    expect(input[5]['role'], 'user');
    expect(input[5]['content'][1]['image_url'], 'data:image/jpeg;base64,$b2');
  });

  test('missing image file is skipped, not a crash', () async {
    late Map<String, dynamic> sent;
    final p = OpenAiCompat(
      baseUrl: 'https://x/v1',
      apiKey: 'k',
      model: 'm',
      client: MockClient((req) async {
        sent = jsonDecode(req.body);
        return okOpenAi();
      }),
    );
    await p.chat('sys', [Msg(role: 'user', text: 'x', images: ['/nope.jpg'])], const []);
    expect((sent['messages'] as List)[1]['content'], contains('x'));
  });

  test('images survive save/load', () {
    final m = Msg.fromJson(jsonDecode(jsonEncode(Msg(role: 'tool', text: 't', images: [img1]).toJson())));
    expect(m.images, [img1]);
  });
}
