// OpenAI-compatible routers (9router…) that answer with an SSE stream even when we didn't ask.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:satsh/agent/llm.dart';

String sse(List<Map<String, dynamic>> chunks) => '${chunks.map((c) => 'data: ${jsonEncode(c)}\n\n').join()}data: [DONE]\n\n';

void main() {
  late Map<String, dynamic> sent;
  OpenAiCompat provider(String body, {int status = 200}) => OpenAiCompat(
        baseUrl: 'https://9router.example/v1',
        apiKey: 'k',
        model: 'ag/gemini-3.8-flash-high',
        client: MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(body, status, headers: {'content-type': 'text/event-stream; charset=utf-8'});
        }),
      );
  final hist = [Msg(role: 'user', text: 'halo')];
  const tools = [ToolSpec(name: 'shell_run', description: 'x', params: {'command': {'type': 'string'}})];

  test('asks for a non-streamed answer', () async {
    await provider('{"choices":[{"message":{"content":"ok"}}]}').chat('sys', hist, tools);
    expect(sent['stream'], false);
  });

  test('streamed text is joined (the 9router FormatException)', () async {
    final r = await provider(sse([
      {'id': 'chatcmpl-1', 'object': 'chat.completion.chunk', 'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': 'Halo '}}]},
      {'id': 'chatcmpl-1', 'object': 'chat.completion.chunk', 'choices': [{'index': 0, 'delta': {'content': 'bre!'}}]},
      {'id': 'chatcmpl-1', 'object': 'chat.completion.chunk', 'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]},
    ])).chat('sys', hist, tools);
    expect(r.text, 'Halo bre!');
    expect(r.calls, isEmpty);
  });

  test('streamed tool calls: arguments split across chunks, several calls', () async {
    final r = await provider(sse([
      {'choices': [{'delta': {'tool_calls': [{'index': 0, 'id': 'call_a', 'type': 'function', 'function': {'name': 'shell_run', 'arguments': '{"comm'}}]}}]},
      {'choices': [{'delta': {'tool_calls': [{'index': 0, 'function': {'arguments': 'and": "df -h"}'}}]}}]},
      {'choices': [{'delta': {'tool_calls': [{'index': 1, 'id': 'call_b', 'function': {'name': 'shell_run', 'arguments': '{"command":"free -m"}'}}]}}]},
      {'choices': [{'delta': {}, 'finish_reason': 'tool_calls'}]},
    ])).chat('sys', hist, tools);
    expect(r.calls.map((c) => c.id), ['call_a', 'call_b']);
    expect(r.calls.first.args, {'command': 'df -h'});
    expect(r.calls.last.args, {'command': 'free -m'});
  });

  test('error inside the stream becomes a readable error (so fallback kicks in)', () async {
    expect(() => provider('data: {"error":{"message":"quota habis"}}\n\ndata: [DONE]\n\n').chat('sys', hist, tools),
        throwsA(isA<LlmError>().having((e) => e.message, 'message', 'quota habis')));
  });

  test('garbage body gives a clear error instead of a raw FormatException', () async {
    expect(() => provider('<html>502 Bad Gateway</html>').chat('sys', hist, tools),
        throwsA(isA<LlmError>().having((e) => e.message, 'message', contains('bukan JSON'))));
  });

  test('plain JSON answers still work', () async {
    final r = await provider(jsonEncode({
      'choices': [
        {
          'message': {
            'content': null,
            'tool_calls': [
              {'id': 't1', 'type': 'function', 'function': {'name': 'shell_run', 'arguments': '{"command":"ls"}'}}
            ]
          }
        }
      ]
    })).chat('sys', hist, tools);
    expect(r.calls.single.args, {'command': 'ls'});
  });

  group('9router passes Gemini/Antigravity bodies through when there are no candidates', () {
    late List<Map<String, dynamic>> bodies;
    OpenAiCompat seq(List<String> replies) {
      bodies = [];
      var i = 0;
      return OpenAiCompat(
        baseUrl: 'https://9router.example/v1',
        apiKey: 'k',
        model: 'ag/gemini-3.8-flash-high',
        client: MockClient((req) async {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(replies[i++ < replies.length - 1 ? i - 1 : replies.length - 1], 200,
              headers: {'content-type': 'application/json'});
        }),
      );
    }

    late String img;
    setUpAll(() {
      img = '${Directory.systemTemp.createTempSync('satshimg').path}/a.jpg';
      File(img).writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    });
    List<Msg> withPic() => [Msg(role: 'user', text: 'ini error apa?', images: [img])];
    bool hasImage(Map<String, dynamic> b) => jsonEncode(b).contains('image_url');

    test('blocked prompt → readable reason, then answered without the picture', () async {
      final p = seq([
        '{"response":{"promptFeedback":{"blockReason":"OTHER"},"usageMetadata":{"promptTokenCount":9}}}',
        '{"choices":[{"message":{"content":"gambarnya ga bisa diproses model ini"},"finish_reason":"stop"}]}',
      ]);
      final r = await p.chat('sys', withPic(), tools);
      expect(r.text, contains('ga bisa diproses'));
      expect(bodies, hasLength(2));
      expect(hasImage(bodies.first), isTrue);
      expect(hasImage(bodies.last), isFalse, reason: 'refused picture is never resent');
      expect(jsonEncode(bodies.last), contains('provider nolak gambarnya'));
      expect(jsonEncode(bodies.last), contains('OTHER'));
    });

    test('no picture: block is a clear error, not "Respon kosong"', () async {
      final p = seq(['{"response":{"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"}}}']);
      expect(() => p.chat('sys', hist, tools),
          throwsA(isA<LlmBlocked>().having((e) => e.message, 'message', contains('PROHIBITED_CONTENT'))));
    });

    test('raw Gemini candidates are read (text + function calls, thoughts skipped)', () async {
      final p = seq([
        jsonEncode({
          'response': {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'mikir…', 'thought': true},
                    {'text': 'Cek dulu'},
                    {'functionCall': {'name': 'shell_run', 'args': {'command': 'uptime'}}},
                  ]
                },
                'finishReason': 'STOP'
              }
            ]
          }
        })
      ]);
      final r = await p.chat('sys', hist, tools);
      expect(r.text, 'Cek dulu');
      expect(r.calls.single.args, {'command': 'uptime'});
    });

    test('candidate stopped by SAFETY with nothing in it → blocked', () async {
      final p = seq(['{"candidates":[{"finishReason":"IMAGE_SAFETY"}]}']);
      expect(() => p.chat('sys', hist, tools), throwsA(isA<LlmBlocked>()));
    });

    test('OpenAI content_filter with empty message → blocked', () async {
      final p = seq(['{"choices":[{"message":{"content":""},"finish_reason":"content_filter"}]}']);
      expect(() => p.chat('sys', hist, tools), throwsA(isA<LlmBlocked>()));
    });

    test('unknown empty body shows what came back', () async {
      final p = seq(['{"weird":true}']);
      expect(() => p.chat('sys', hist, tools),
          throwsA(isA<LlmError>().having((e) => e.message, 'message', contains('"weird":true'))));
    });

    test('plain stop with empty text is still fine', () async {
      final r = await seq(['{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}']).chat('sys', hist, tools);
      expect(r.text, '');
    });
  });
}
