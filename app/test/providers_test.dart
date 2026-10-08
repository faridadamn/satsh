import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/agent/providers.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String jwt(Map<String, dynamic> claims) =>
    'x.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.y';

class Boom implements LlmProvider {
  @override
  Future<LlmReply> chat(String s, List<Msg> h, List<ToolSpec> t) async => throw LlmError('limit');
}

class Ok implements LlmProvider {
  @override
  Future<LlmReply> chat(String s, List<Msg> h, List<ToolSpec> t) async => LlmReply('dari cadangan', []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'cfg': jsonEncode({'llm': 'gemini', 'openaiBase': 'https://api.deepseek.com/v1', 'openaiModel': 'deepseek-chat', 'geminiModel': 'gemini-2.5-pro'}),
    });
    FlutterSecureStorage.setMockInitialValues({'sec_openaiKey': 'sk-old', 'sec_geminiKey': 'g-old'});
    await Store.i.load();
  });

  test('v3 settings migrate into saved profiles, keys kept, active one first', () async {
    await Providers.migrate();
    final l = Providers.all();
    expect(l.map((p) => p.name), ['Gemini', 'DeepSeek']);
    expect(l[0].model, 'gemini-2.5-pro');
    expect(l[1].base, 'https://api.deepseek.com/v1');
    expect(await Store.i.secret(l[1].keyName), 'sk-old');
    // second run is a no-op
    await Providers.migrate();
    expect(Providers.all().length, 2);
    // switching = reordering/toggling, nothing is lost
    l[0].disabled = true;
    Providers.saveAll(l);
    expect(Providers.primary!.name, 'DeepSeek');
    expect(Providers.all().length, 2);
  });

  test('fallback goes to the next provider on error', () async {
    final f = FallbackProvider([('A', Boom()), ('B', Ok())]);
    final r = await f.chat('s', [Msg(role: 'user', text: 'hi')], []);
    expect(r.text, 'dari cadangan');
    expect(f.lastUsed, 'B');
    await expectLater(FallbackProvider([('A', Boom())]).chat('s', [], []), throwsA(isA<LlmError>()));
  });

  test('codex: request shape, SSE tool call parsing, instructions retry', () async {
    final far = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
    final p = ProviderCfg(id: 'cx', kind: 'codex', name: 'ChatGPT', model: 'gpt-5.5');
    await Store.i.setSecret('codex_cx', jsonEncode({'access_token': jwt({'exp': far}), 'refresh_token': 'r', 'account_id': 'acc-1', 'expires_at': far * 1000}));
    final bodies = <Map<String, dynamic>>[];
    var calls = 0;
    final client = MockClient.streaming((req, body) async {
      final url = req.url.toString();
      if (url.contains('raw.githubusercontent.com')) {
        return http.StreamedResponse(Stream.value(utf8.encode('You are Codex. ' * 40)), 200);
      }
      calls++;
      final b = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      bodies.add(b);
      expect(req.headers['chatgpt-account-id'], 'acc-1');
      expect(req.headers['originator'], 'codex_cli_rs');
      if (calls == 1) return http.StreamedResponse(Stream.value(utf8.encode('{"detail":"Instructions are not valid"}')), 400);
      final sse = [
        {'type': 'response.output_item.done', 'item': {'type': 'reasoning', 'id': 'rs_1'}},
        {'type': 'response.output_text.delta', 'delta': 'Cek '},
        {'type': 'response.output_text.delta', 'delta': 'dulu.'},
        {'type': 'response.output_item.done', 'item': {'type': 'message', 'content': [{'type': 'output_text', 'text': 'Cek dulu.'}]}},
        {'type': 'response.output_item.done', 'item': {'type': 'function_call', 'call_id': 'call_9', 'name': 'ssh_exec', 'arguments': '{"host":"vps","command":"df -h"}'}},
        {'type': 'response.completed', 'response': {'output': []}},
      ].map((e) => 'event: x\ndata: ${jsonEncode(e)}\n\n').join();
      return http.StreamedResponse(Stream.fromIterable([utf8.encode(sse.substring(0, 50)), utf8.encode(sse.substring(50))]), 200);
    });
    final cp = CodexProvider(p, client: client);
    final hist = [
      Msg(role: 'user', text: 'cek disk'),
      Msg(role: 'assistant', text: '', calls: [ToolCall(id: 'call_1', name: 'phone_list', args: {'path': 'Download'})]),
      Msg(role: 'tool', callId: 'call_1', name: 'phone_list', text: 'a.pdf'),
    ];
    final r = await cp.chat('SYSTEM satsh', hist, [const ToolSpec(name: 'ssh_exec', description: 'd', params: {'host': {'type': 'string'}})]);
    expect(r.text, 'Cek dulu.');
    expect(r.calls.single.id, 'call_9');
    expect(r.calls.single.args['command'], 'df -h');
    // first try uses our system prompt as instructions; retry moves it to a developer message
    expect(bodies[0]['instructions'], 'SYSTEM satsh');
    expect(bodies[1]['instructions'], startsWith('You are Codex'));
    final input = bodies[1]['input'] as List;
    expect(input[0]['role'], 'developer');
    expect(input[2], {'type': 'function_call', 'call_id': 'call_1', 'name': 'phone_list', 'arguments': '{"path":"Download"}'});
    expect(input[3], {'type': 'function_call_output', 'call_id': 'call_1', 'output': 'a.pdf'});
    expect(bodies[1]['stream'], true);
    expect(bodies[1]['store'], false);
    expect((bodies[1]['tools'] as List).single['name'], 'ssh_exec');
  });

  test('codex: expired token gets refreshed and account info decoded', () async {
    final past = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
    await Store.i.setSecret('codex_r1', jsonEncode({'access_token': 'old', 'refresh_token': 'rt-1', 'expires_at': past}));
    final newExp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
    CodexAuth.client = MockClient((req) async {
      final b = jsonDecode(req.body);
      expect(b['grant_type'], 'refresh_token');
      expect(b['refresh_token'], 'rt-1');
      return http.Response(
          jsonEncode({
            'access_token': jwt({'exp': newExp}),
            'id_token': jwt({
              'email': 'adam@contoh.id',
              'https://api.openai.com/auth': {'chatgpt_account_id': 'acc-9', 'chatgpt_plan_type': 'plus'}
            }),
          }),
          200);
    });
    final t = await CodexAuth.fresh('r1');
    expect(t['email'], 'adam@contoh.id');
    expect(t['account_id'], 'acc-9');
    expect(t['plan'], 'plus');
    expect(t['refresh_token'], 'rt-1'); // kept when server doesn't rotate it
    expect(t['expires_at'], newExp * 1000);
    expect((await CodexAuth.tokens('r1'))!['plan'], 'plus');
  });
}
