// Built-in "Web Designer" preset, agent_profile tool, web_preview server.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/presets.dart';
import 'package:satsh/agent/tools.dart';
import 'package:satsh/browser.dart';
import 'package:satsh/preview_server.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_test.dart' show FakeBackend;

Future<Brain> fresh() async {
  Brain.rootOverride = Directory.systemTemp.createTempSync('pre').path;
  await Brain.i.load();
  return Brain.i;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
  });

  test('web-designer preset ships soul, antislop skills (with MIT notice) and own skills', () async {
    final f = await Presets.load('web-designer');
    expect(f['profile.json'], contains('"web-designer"'));
    expect(f['SOUL.md'], contains('antislop'));
    for (final s in ['antislop', 'antislop-ui', 'antislop-copywriting', 'antislop-human', 'antislop-layoutmobile', 'antislop-code', 'design-md', 'agents-md', 'web-build', 'web-resources']) {
      final raw = f['skills/$s/SKILL.md'];
      expect(raw, isNotNull, reason: s);
      expect(Brain.parseSkill(raw!)?.name, s, reason: s);
      expect(Brain.parseSkill(raw)!.description, isNotEmpty, reason: s);
      if (s.startsWith('antislop')) expect(raw, contains('Copyright (c) 2026 Miqdad Badjuber'), reason: s);
    }
    expect(f['LICENSE-antislop.txt'], contains('MIT License'));
  });

  test('auto-installed once; deleting it sticks', () async {
    final b = await fresh();
    expect(await b.autoInstallPresets(Presets.all()), ['web-designer', 'cybersecurity', 'devops', 'code-reviewer']);
    final v = await b.view('web-designer');
    expect(b.profile('web-designer')!.emoji, '🎨');
    expect(b.profile('web-designer')!.toolsOff, containsAll(['control', 'supabase']));
    expect(v.skill('antislop-ui'), isNotNull);
    expect(v.soul, startsWith('# SOUL — Web Designer'));
    expect(b.activeId, 'default'); // general agent stays the main one
    await b.deleteProfile('web-designer');
    await b.load();
    expect(await b.autoInstallPresets(Presets.all()), isEmpty);
    expect(b.profile('web-designer'), isNull);
    // …but can be added back by hand
    await b.installPreset(await Presets.load('web-designer'));
    expect(b.profile('web-designer'), isNotNull);
  });

  test('agent_profile builds a new agent from what it read', () async {
    final b = await fresh();
    final a = AgentController.i;
    final tool = a.brainTools(RunCtx(autoApprove: true)).firstWhere((t) => t.spec.name == 'agent_profile');
    expect(tool.risky, isTrue);
    final out = await tool.run({
      'action': 'create',
      'name': 'Copywriter',
      'emoji': '✍️',
      'desc': 'nulis caption & landing page',
      'soul': '# SOUL — Copywriter\nKamu copywriter.',
      'skills': [
        {'name': 'Caption IG', 'description': 'bikin caption', 'content': '1. hook\n2. isi\n3. CTA'},
      ],
      'memory': ['referensi: github.com/miqdadbadjuber/anti-slop'],
      'tools_off': ['ssh', 'control'],
      'copy_skills_from': 'preset:web-designer',
    });
    expect(out, contains('id=copywriter'));
    final v = await b.view('copywriter');
    expect(v.soul, contains('Kamu copywriter'));
    expect(v.skill('caption-ig'), isNotNull); // name normalised
    expect(v.skill('antislop-copywriting'), isNotNull); // copied from preset
    expect(v.memory, contains('anti-slop'));
    expect(b.profile('copywriter')!.toolsOff, ['ssh', 'control']);
    expect(await tool.run({'action': 'list'}), contains('✍️ Copywriter'));
    await tool.run({'action': 'update', 'id': 'copywriter', 'desc': 'baru'});
    expect(b.profile('copywriter')!.desc, 'baru');
    expect(() => tool.run({'action': 'update', 'id': 'ga-ada'}), throwsA(contains('ga ada')));
  });

  test('web_preview serves the project folder and opens it in the agent browser', () async {
    final root = Directory.systemTemp.createTempSync('phone');
    phoneBase = root.path;
    final proj = Directory('${root.path}/Download/satsh-web/kopi')..createSync(recursive: true);
    File('${proj.path}/index.html').writeAsStringSync('<h1>Kopi</h1><link rel=stylesheet href=s.css>');
    File('${proj.path}/s.css').writeAsStringSync('h1{color:red}');
    final fake = FakeBackend();
    ResearchBrowser.i.backendFactory = () => fake;
    final out = await toolByName('web_preview')!.run({'path': 'Download/satsh-web/kopi'});
    expect(out, contains('Judul:'));
    final url = fake.loaded.last;
    expect(url, startsWith('http://127.0.0.1:'));
    final base = Uri.parse(url).replace(query: '').toString().replaceAll('?', '');
    HttpOverrides.global = null; // flutter_test fakes HttpClient; talk to the real local server
    final c = HttpClient();
    Future<(int, String)> get(String u) async {
      final r = await (await c.getUrl(Uri.parse(u))).close();
      return (r.statusCode, await r.transform(const SystemEncoding().decoder).join());
    }

    expect((await get(base)).$2, contains('<h1>Kopi</h1>'));
    expect((await get('${base}s.css')).$2, contains('color:red'));
    expect((await get('$base../../../etc/passwd')).$1, isNot(200));
    expect((await get('${base}nope.js')).$1, 404);
    expect(await toolByName('web_preview')!.run({'path': 'Download/ga-ada'}), contains('Ga ada'));
    c.close();
    await PreviewServer.i.stop();
  });
}
