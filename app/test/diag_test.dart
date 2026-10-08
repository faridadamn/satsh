// Diagnosa HP: report/verdict rules, the diagnosa_hp tool, the Cek HP page, and new default skills
// reaching old installs without resurrecting ones the user deleted.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/tools.dart';
import 'package:satsh/diag.dart';
import 'package:satsh/pages/cek_hp_page.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> phone({double? health = 92, int pct = 70, bool root = false, String vb = 'green', String patch = '2026-08-01'}) {
  const design = 5000.0;
  final full = health == null ? null : design * health / 100;
  return {
    'battery': {
      'percent': pct,
      'chargeNowMah': full == null ? null : full * pct / 100,
      'fullEstimateMah': full,
      'designMah': design,
      'healthPct': health,
      'cycles': 420,
      'health': 'good',
      'tempC': 31.5,
      'voltageMv': 4012,
      'plugged': 'none',
    },
    'device': {'brand': 'Xiaomi', 'model': 'Redmi Note 13', 'device': 'sapphire', 'android': '15', 'securityPatch': patch},
    'soc': {'model': 'Qualcomm SM6225', 'cores': 8, 'maxGhz': 2.4},
    'memory': {'totalGb': 7.6, 'availGb': 2.9},
    'storage': {'totalGb': 119.2, 'freeGb': 40},
    'display': {'px': '1080x2400', 'inchApprox': 6.67, 'refreshHz': [60, 120]},
    'cameras': [
      {'facing': 'belakang', 'mp': 108.0},
      {'facing': 'depan', 'mp': 16.0},
    ],
    'sensors': {'gyroscope': true, 'nfc': false, 'fingerprint': true},
    'security': {'suFound': root ? ['/system/bin/su'] : [], 'rootApps': root ? ['com.topjohnwu.magisk'] : [], 'verifiedBoot': vb},
    'thermal': {'status': 'normal'},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
  });

  group('laporan & vonis', () {
    final now = DateTime(2026, 10, 6);
    test('healthy phone, all manual tests passed → layak', () {
      final r = buildReport(phone(), manual: {for (final k in manualTests.keys) k: true}, now: now);
      expect(r.verdict, startsWith('✅ LAYAK'));
      expect(r.text, contains('~4600 mAh dari desain 5000 mAh → kesehatan ~92%'));
      expect(r.text, contains('kelas 8 GB'));
      expect(r.text, contains('kelas 128 GB'));
      expect(r.text, contains('belakang 108MP'));
      expect(r.text, contains('Cycle: 420'));
    });

    test('worn battery → cek lagi; very worn or rooted → waspada', () {
      expect(buildReport(phone(health: 74), now: now).verdict, startsWith('🟠'));
      expect(buildReport(phone(health: 60), now: now).verdict, startsWith('🔴'));
      final rooted = buildReport(phone(root: true), now: now);
      expect(rooted.verdict, startsWith('🔴'));
      expect(rooted.text, contains('ke-ROOT'));
      expect(buildReport(phone(vb: 'orange'), now: now).text, contains('Bootloader ke-unlock'));
    });

    test('failed manual test, old patch, no capacity data', () {
      final r = buildReport(phone(health: null, patch: '2022-01-05'), manual: {'layar': false, 'speaker': true}, now: now);
      expect(r.verdict, startsWith('🔴'));
      expect(r.text, contains('Tes Layar (dead pixel / garis / burn-in) GAGAL'));
      expect(r.text, contains('Patch keamanan udah tua'));
      expect(r.text, contains('ga bisa diperkirain'));
      expect(r.text, contains('Belum dites:'));
      final low = buildReport(phone(health: null, pct: 9), now: now);
      expect(low.text, contains('cas dulu ke > 50%'));
    });

    test('marketing sizes', () {
      expect(marketing(3.7, [1, 2, 3, 4, 6, 8]), 4);
      expect(marketing(11.2, [8, 12, 16]), 12);
      expect(marketing(238, [64, 128, 256, 512]), 256);
    });
  });

  group('tool diagnosa_hp', () {
    late AgentTool tool;
    setUp(() {
      tool = allTools.firstWhere((t) => t.spec.name == 'diagnosa_hp');
      DiagSource.read = () async => phone(health: 76);
      DiagSource.manual = () => {'layar': true};
    });

    test('report + verdict + manual results', () async {
      final out = await tool.run({});
      expect(tool.group, 'device');
      expect(out, contains('🟠 CEK LAGI'));
      expect(out, contains('✅ Layar'));
      expect(out, contains('Data mentah'));
    });

    test('logs without adb grant explain how; with grant they are included', () async {
      DiagSource.logs = (w) async => 'NEED_GRANT: adb shell pm grant id.adam.satsh android.permission.READ_LOGS';
      expect(await tool.run({'logs': 'crash'}), contains('adb shell pm grant'));
      DiagSource.logs = (w) async => '10-06 07:24 E AndroidRuntime: FATAL EXCEPTION: main';
      expect(await tool.run({'logs': 'crash'}), contains('FATAL EXCEPTION'));
    });
  });

  testWidgets('Cek HP page runs the diagnosis and shows the verdict', (t) async {
    DiagSource.read = () async => phone(health: 60);
    await t.pumpWidget(const MaterialApp(home: CekHpPage()));
    expect(find.text('Sentuh semua area'), findsOneWidget);
    await t.tap(find.text('Jalanin diagnosa otomatis'));
    await t.pumpAndSettle();
    expect(find.textContaining('WASPADA'), findsWidgets);
    await t.scrollUntilVisible(find.text('Analisa agent'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Analisa agent'), findsOneWidget);
  });

  test('manual results persist for 24h', () {
    saveManual({'layar': true, 'mic': false, 'getar': null});
    expect(savedManual(), {'layar': true, 'mic': false});
    Store.i.set('diagManual', {'at': DateTime.now().subtract(const Duration(hours: 25)).millisecondsSinceEpoch, 'r': {'layar': true}});
    expect(savedManual(), isEmpty);
  });

  group('skill bawaan baru', () {
    test('fresh install gets all; old install gets only the new one', () async {
      Brain.rootOverride = Directory.systemTemp.createTempSync('fresh').path;
      await Brain.i.load();
      expect(Brain.i.skill('cek-hp-bekas'), isNotNull);
      expect(Brain.i.active.isBuiltin('cek-hp-bekas'), isTrue);
      expect(Brain.i.skill('cek-hp-bekas')!.description, contains('HP bekas'));

      final root = Directory.systemTemp.createTempSync('old').path;
      File('$root/SOUL.md').writeAsStringSync('# soul lama');
      Directory('$root/skills/deploy-git').createSync(recursive: true);
      File('$root/skills/deploy-git/SKILL.md').writeAsStringSync('---\nname: deploy-git\ndescription: punya gw\n---\nx');
      Brain.rootOverride = root;
      await Brain.i.load();
      expect(Brain.i.skill('cek-hp-bekas'), isNotNull, reason: 'new default arrives');
      expect(Brain.i.skill('cek-server'), isNull, reason: 'deleted default stays deleted');
      expect(Brain.i.skill('deploy-git')!.description, 'punya gw', reason: 'edits kept');
      expect(Brain.i.soul, '# soul lama');

      await Brain.i.deleteSkill('cek-hp-bekas');
      await Brain.i.load();
      expect(Brain.i.skill('cek-hp-bekas'), isNull);
    });
  });
}
