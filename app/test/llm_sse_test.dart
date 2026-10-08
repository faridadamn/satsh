// OpenAI-compatible routers (9router…) that answer with an SSE stream even when we didn't ask.
import 'dart:convert';

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
}
