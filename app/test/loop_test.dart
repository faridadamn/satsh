// Agent loop limits: step cap, "no limit", and the going-in-circles detector.
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/agent/tools.dart';

class Fake implements LlmProvider {
  Fake(this.script);
  final LlmReply Function(int n) script;
  int n = 0;
  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools) async => script(++n);
}

var _id = 0;
LlmReply call(String name, Map<String, dynamic> args) => LlmReply('', [ToolCall(id: 'c${_id++}', name: name, args: args)]);

AgentTool tool(String name, {bool fail = false}) => AgentTool(
      ToolSpec(name: name, description: '', params: {'x': {'type': 'string'}}),
      (a) async => fail ? throw 'gagal' : 'ok',
    );

Future<(String, int, List<Msg>)> run(LlmReply Function(int) script, int maxSteps, List<AgentTool> tools) async {
  final llm = Fake(script);
  final h = [Msg(role: 'user', text: 'kerjain')];
  final out = await AgentController.i.runLoop(llm: llm, history: h, ctx: RunCtx(maxSteps: maxSteps), system: 'sys', tools: tools);
  return (out, llm.n, h);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cap: stops after exactly maxSteps model calls', () async {
    final (out, n, _) = await run((i) => call('a', {'x': '$i'}), 30, [tool('a')]);
    expect(out, stepLimitText);
    expect(n, 30);
    expect(isLoopStop(out), isTrue);
  });

  test('maxSteps 0: no cap, finishes when the model does', () async {
    final (out, n, _) = await run((i) => i < 300 ? call('a', {'x': '$i'}) : LlmReply('beres', []), 0, [tool('a')]);
    expect(out, 'beres');
    expect(n, 300);
  });

  test('same call over and over → stops itself', () async {
    final (out, n, h) = await run((i) => call('a', {'x': 'sama', 'y': {'b': 1, 'a': 2}}), 0, [tool('a')]);
    expect(out, startsWith(stuckPrefix));
    expect(out, contains('`a`'));
    expect(n, sameCallLimit);
    expect(h.last.text, out);
    expect(isLoopStop(out), isTrue);
  });

  test('arg key order does not matter for the signature', () {
    final a = [ToolCall(id: '1', name: 't', args: {'a': 1, 'b': {'y': 2, 'x': 3}})];
    final b = [ToolCall(id: '2', name: 't', args: {'b': {'x': 3, 'y': 2}, 'a': 1})];
    expect(callSignature(a), callSignature(b));
  });

  test('repeats broken up by another call are fine', () async {
    const seq = ['p', 'p', 'p', 'q', 'p', 'p', 'p'];
    final (out, _, _) = await run((i) => i <= seq.length ? call('a', {'x': seq[i - 1]}) : LlmReply('done', []), 0, [tool('a')]);
    expect(out, 'done');
  });

  test('every tool failing step after step → stops itself', () async {
    final (out, n, _) = await run((i) => call('b', {'x': '$i'}), 0, [tool('b', fail: true)]);
    expect(out, startsWith(stuckPrefix));
    expect(n, errorStreakLimit);
  });

  test('cap message wins when both happen on the last step', () async {
    final (out, _, _) = await run((i) => call('a', {'x': 'sama'}), sameCallLimit, [tool('a')]);
    expect(out, stepLimitText);
  });
}
