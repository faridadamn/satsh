// Runs scheduled jobs end-to-end with a fake model so crashes surface with a stack trace.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/browser.dart';
import 'package:satsh/error_log.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBrowser implements BrowserBackend {
  @override
  bool navigating = false;
  @override
  Future<void> load(String url) async {}
  @override
  Future<Object?> js(String code) async =>
      jsonEncode(jsonEncode({'url': 'https://linkedin.test/feed', 'title': 'Feed', 'text': 'post satu', 'els': [], 'pw': false}));
  @override
  Future<bool> back() async => false;
  @override
  Future<void> clearData() async {}
  @override
  Future<void> settled({Duration timeout = const Duration(seconds: 25)}) async {}
  @override
  Future<Shot> shot() async => throw UnsupportedError('x');
}

/// Calls a list of tools one per turn, then answers.
class ScriptLlm implements LlmProvider {
  ScriptLlm(this.calls);
  final List<(String, Map<String, dynamic>)> calls;
  int i = 0;
  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools) async {
    if (i < calls.length) {
      final (n, a) = calls[i++];
      expect(tools.map((t) => t.name), contains(n), reason: 'tool $n not offered');
      return LlmReply('', [ToolCall(id: 'c$i', name: n, args: a)]);
    }
    return LlmReply('beres', []);
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    Brain.rootOverride = Directory.systemTemp.createTempSync('cron').path;
    ErrorLog.dirOverride = Directory.systemTemp.createTempSync('log').path;
    await AgentController.i.load();
    ResearchBrowser.i.backendFactory = () => FakeBrowser();
  });

  Future<CronJob> job(String name, {String? profile, bool risky = false}) async {
    final j = CronJob(id: newId(), name: name, prompt: 'cek linkedin', everyMinutes: 60, allowRisky: risky, profile: profile);
    Brain.i.jobs.add(j);
    await Brain.i.saveJobs();
    return j;
  }

  for (final risky in [false, true]) {
    test('cron job with browser + brain tools runs clean (risky=$risky)', () async {
      AgentController.i.providerOverride = ScriptLlm([
        ('todo_write', {'items': [{'content': 'buka feed', 'status': 'in_progress'}]}),
        ('browser_open', {'url': 'https://linkedin.test/feed'}),
        ('browser_read', {}),
        ('browser_find', {'text': 'post'}),
        ('memory', {'action': 'add', 'target': 'memory', 'content': 'feed dicek $risky'}),
        ('cron_list', {}),
        ('session_search', {'query': 'linkedin'}),
        ('browser_scroll', {'direction': 'down'}),
      ]);
      final j = await job('like-feed-$risky', risky: risky);
      await CronRunner.i.run(j);
      expect(j.lastResult, isNot(startsWith('GAGAL')), reason: '${j.lastResult}\n${ErrorLog.i.report()}');
      // run again: re-opens the existing cron session
      AgentController.i.providerOverride = ScriptLlm([('browser_read', {})]);
      await CronRunner.i.run(j);
      expect(j.lastResult, isNot(startsWith('GAGAL')), reason: '${j.lastResult}\n${ErrorLog.i.report()}');
    });
  }

  test('cron job of a deleted profile / while UI shows that session', () async {
    final p = await Brain.i.createProfile('LinkedIn');
    final j = await job('loker', profile: p.id);
    AgentController.i.providerOverride = ScriptLlm([('browser_open', {'url': 'loker'})]);
    await CronRunner.i.run(j);
    await AgentController.i.openSession(j.sessionId!);
    AgentController.i.providerOverride = ScriptLlm([('todo_write', {'items': []})]);
    await CronRunner.i.run(j);
    await Brain.i.deleteProfile(p.id);
    AgentController.i.providerOverride = ScriptLlm([]);
    await CronRunner.i.run(j);
    expect(j.lastResult, isNot(startsWith('GAGAL')), reason: '${j.lastResult}\n${ErrorLog.i.report()}');
  });

  test('a crash inside a job is logged with its stack', () async {
    AgentController.i.providerOverride = _Boom();
    final j = await job('boom');
    await CronRunner.i.run(j);
    expect(j.lastResult, startsWith('GAGAL'));
    final e = ErrorLog.i.entries.last;
    expect(e.source, 'cron');
    expect(e.context['jadwal'], 'boom');
    expect(e.stack, contains('_Boom'));
    expect(ErrorLog.i.report(), contains('versi: $appVersion'));
  });
}

class _Boom implements LlmProvider {
  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools) async {
    String? x;
    return LlmReply(x!, []);
  }
}
