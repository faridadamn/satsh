import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/providers.dart';
import 'package:satsh/pages/brain_page.dart';
import 'package:satsh/agent/mission.dart';
import 'package:satsh/pages/missions_page.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/main.dart';
import 'package:satsh/pages/agent_page.dart';
import 'package:satsh/pages/file_viewer_page.dart';
import 'package:satsh/pages/settings_page.dart';
import 'package:satsh/pages/server_page.dart';
import 'package:satsh/pages/error_log_page.dart';
import 'package:satsh/pages/profiles_sheet.dart';
import 'package:satsh/pages/markas_page.dart';
import 'package:satsh/markas.dart';
import 'dart:convert';
import 'package:satsh/error_log.dart';
import 'package:satsh/browser.dart';
import 'browser_test.dart' show FakeBackend;
import 'package:satsh/models.dart';
import 'package:satsh/pages/forwards_page.dart';
import 'package:satsh/diag.dart';
import 'package:satsh/pages/cek_hp_page.dart';
import 'diag_test.dart' show phone;
import 'package:satsh/pages/host_edit_page.dart';
import 'package:satsh/pages/snippets_page.dart';
import 'package:satsh/pages/terminal_page.dart';
import 'package:satsh/ssh_manager.dart';
import 'package:satsh/store.dart';
import 'package:satsh/theme.dart';
import 'package:satsh/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await l.load();
}

Future<void> loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await l.load();
}

Widget app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      theme: buildTheme(),
      home: home,
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await loadFont(uiFont, ['SpaceGrotesk-Regular.ttf', 'SpaceGrotesk-Medium.ttf', 'SpaceGrotesk-Bold.ttf']);
    await loadFont(monoFont, ['JetBrainsMono-Regular.ttf', 'JetBrainsMono-Bold.ttf']);
    await loadMaterialIcons();
    await Store.i.load();
    Brain.rootOverride = Directory.systemTemp.createTempSync('gb').path;
    await Brain.i.load();
    Providers.saveAll([ProviderCfg(id: 'a', kind: 'codex', name: 'ChatGPT', model: 'gpt-5.5'), ProviderCfg(id: 'b', kind: 'openai', name: 'DeepSeek', base: 'https://api.deepseek.com/v1', model: 'deepseek-chat'), ProviderCfg(id: 'c', kind: 'gemini', name: 'Gemini', model: 'gemini-2.5-pro', disabled: true)]);
    await Brain.i.setEntries('user', ['Adam, driver ojol & motion designer. Suka jawaban singkat, bahasa santai.', 'Lagi bangun Payu (SaaS UMKM) dan agent Leo.']);
    await Brain.i.setEntries('memory', ['Leo jalan di laptop Win7, GUI di port 8770.', 'VPS Jakarta: app Payu di /var/www/payu, restart pakai pm2 restart payu.']);
    CronJob.clock = () => DateTime(2026, 10, 5, 6); // golden shows "berikutnya 10-05 07:00"
    Brain.i.jobs.add(CronJob(id: 'j1', name: 'Cek server pagi', prompt: 'Cek disk & RAM semua server, kabarin kalau ada yang > 85%', dailyAt: '07:00', lastResult: 'Semua aman, disk VPS 30%.'));
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final (i, h) in [
      Host(id: 'a', label: 'VPS Jakarta', host: '103.152.10.7', username: 'root', color: 0, startup: 'tmux a', lastUsed: now),
      Host(id: 'b', label: 'Laptop Leo', host: '192.168.1.20', port: 2222, username: 'adam', auth: 'key', color: 1, lastUsed: now - 1),
      Host(id: 'c', label: 'Payu prod', host: 'payu.id', username: 'deploy', auth: 'key', color: 2, lastUsed: now - 2),
      Host(id: 'd', label: 'Raspberry', host: '10.0.0.5', username: 'pi', color: 3, lastUsed: now - 3),
    ].indexed) {
      i;
      await Store.i.saveHost(h);
    }
    Store.i.saveForward(Forward(id: 'f', label: 'GUI Leo', hostId: 'a', localPort: 8770, remotePort: 8770));
    markasSnap = await _markasSample();
    Store.i.saveForward(Forward(id: 'g', label: 'Postgres', hostId: 'c', localPort: 15432, remotePort: 5432));
  });

  Future<void> shot(WidgetTester t, Widget w, String name, {Future<void> Function()? after}) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    await t.pumpWidget(app(w));
    await t.pump(const Duration(seconds: 2));
    if (after != null) await after();
    await t.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('hosts', (t) async {
    final s = TermSession(Store.i.host('a')!)..state = ConnState.ready;
    SshManager.i.sessions.add(s);
    await shot(t, const Shell(), 'hosts');
    SshManager.i.sessions.clear();
  });

  testWidgets('markas setup', (t) async {
    Markas.i.hostId = '';
    Markas.i.snap = null;
    await shot(t, const Scaffold(body: MarkasPage()), 'markas_setup');
  });
  testWidgets('markas', (t) async {
    Markas.i.hostId = 'a';
    Markas.i.snap = markasSnap;
    await shot(t, const Shell(), 'markas', after: () async {
      shellTab.value = 2;
      await t.pump(const Duration(seconds: 1));
    });
    shellTab.value = 0;
    Markas.i.hostId = '';
    Markas.i.snap = null;
  });
  testWidgets('snippets', (t) => shot(t, const Scaffold(body: SnippetsPage()), 'snippets'));
  testWidgets('forwards', (t) => shot(t, const Scaffold(body: ForwardsPage()), 'forwards'));
  testWidgets('edit', (t) => shot(t, HostEditPage(host: Store.i.host('b')), 'edit'));
  testWidgets('server', (t) => shot(t, const ServerPage(), 'server'));
  testWidgets('profiles sheet', (t) async {
    if (Brain.i.profile('web-designer') == null) {
      await t.runAsync(() async => Brain.i.profiles.add(AgentProfile(id: 'web-designer', name: 'Web Designer', emoji: '🎨', desc: 'Bikin UI web anti-slop')));
    }
    await shot(t, const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: ProfilesSheet())), 'profiles_sheet');
  });
  testWidgets('error log', (t) async {
    ErrorLog.dirOverride = Directory.systemTemp.createTempSync('el').path;
    await t.runAsync(() => ErrorLog.i.clear());
    ErrorLog.i.add('cron', 'Null check operator used on a null value',
        StackTrace.fromString('#0      Brain.view (package:satsh/agent/brain.dart:495:53)\n#1      CronRunner.run (package:satsh/agent/agent.dart:912:30)'),
        context: {'jadwal': 'like-feed-hourly', 'id': '72a1edf4', 'profil': 'default'});
    ErrorLog.i.add('tool', 'RangeError (index): Invalid value', null, context: {'tool': 'browser_read', 'argumen': 'part'});
    await shot(t, const ErrorLogPage(), 'error_log', after: () async {
      await t.tap(find.text('Null check operator used on a null value'));
      await t.pumpAndSettle();
    });
  });

  testWidgets('terminal', (t) async {
    final s = TermSession(Store.i.host('a')!)..state = ConnState.ready;
    s.terminal.write('\x1b[38;5;99m⚡ satsh\x1b[0m → \x1b[1mroot@103.152.10.7\x1b[0m\r\n'
        'Welcome to Ubuntu 24.04 LTS\r\n\r\n'
        '\x1b[32mroot@vps\x1b[0m:\x1b[34m~\x1b[0m# df -h\r\n'
        'Filesystem      Size  Used Avail Use% Mounted on\r\n'
        '/dev/vda1        40G   12G   28G  30% /\r\n'
        'tmpfs           2.0G     0  2.0G   0% /dev/shm\r\n'
        '\x1b[32mroot@vps\x1b[0m:\x1b[34m~\x1b[0m# ');
    s.ctrl = true;
    await shot(t, TerminalPage(session: s), 'terminal');
  });

  testWidgets('agent browser panel', (t) async {
    ResearchBrowser.i.backendFactory = () => FakeBackend();
    await t.runAsync(() => ResearchBrowser.i.open('https://a.test/'));
    await shot(t, const Scaffold(body: AgentPage()), 'agent_browser');
    ResearchBrowser.i.close();
  });
  testWidgets('agent empty', (t) => shot(t, const Scaffold(body: AgentPage()), 'agent_empty'));

  testWidgets('agent chat', (t) async {
    final a = AgentController.i;
    a.messages.addAll([
      Msg(role: 'user', text: 'Cek disk VPS sama cari invoice di Download'),
      Msg(role: 'assistant', text: 'Siap, gw cek dulu.', calls: [
        ToolCall(id: '1', name: 'ssh_exec', args: {'host': 'VPS Jakarta', 'command': 'df -h /'}),
        ToolCall(id: '2', name: 'phone_search', args: {'query': 'invoice'}),
      ]),
      Msg(role: 'tool', callId: '1', name: 'ssh_exec', text: 'exit: 0\nstdout:\n/dev/vda1 40G 12G 28G 30% /'),
      Msg(role: 'tool', callId: '2', name: 'phone_search', text: 'Download/invoice-mei.pdf'),
      Msg(role: 'event', text: '🧠 memori diupdate · skill "cek-server" diperbaiki'),
      Msg(role: 'assistant', text: '**Disk VPS** aman: kepake `30%` (12G dari 40G).\n\nInvoice ketemu 1:\n- `Download/invoice-mei.pdf`\n\nMau gw kirim ke server?'),
    ]);
    a.session.todos = [
      {'content': 'Cek disk VPS', 'status': 'done'},
      {'content': 'Cari invoice di HP', 'status': 'done'},
      {'content': 'Upload invoice ke server', 'status': 'in_progress'},
    ];
    await shot(t, const Scaffold(body: AgentPage()), 'agent_chat');
    a.messages.clear();
    a.session.todos = [];
  });

  testWidgets('agent chat never shows secrets: narration, final answer, events, plan, status', (t) async {
    final a = AgentController.i;
    a.messages.addAll([
      Msg(role: 'user', text: 'cek vps'),
      Msg(role: 'assistant', text: 'Login pakai DB_PASSWORD=hunter22 dulu', calls: [
        ToolCall(id: '1', name: 'ssh_exec', args: {'host': 'vps', 'command': 'mysql -u root -pRahasia123', 'password': 'x'}),
      ]),
      Msg(role: 'tool', callId: '1', name: 'ssh_exec', text: 'API_KEY=sk-proj-ABCDEFGHIJKLMNOPQRSTUV'),
      Msg(role: 'event', text: '⚠️ HTTP 401 key sk-proj-ABCDEFGHIJKLMNOPQRSTUV'),
      Msg(role: 'assistant', text: 'Beres. Server 103.45.67.89, passwordnya rahasia99, key sk-proj-ABCDEFGHIJKLMNOPQRSTUV'),
    ]);
    a.session.todos = [{'content': 'restart 103.45.67.89', 'status': 'pending'}];
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    await t.pumpWidget(app(const Scaffold(body: AgentPage())));
    await t.pump(const Duration(seconds: 2));
    // expand the tool chip too
    await t.tap(find.textContaining('ssh_exec').first, warnIfMissed: false);
    await t.pump(const Duration(seconds: 1));
    final shown = [
      for (final r in t.widgetList<RichText>(find.byType(RichText))) r.text.toPlainText(),
      for (final e in t.widgetList<EditableText>(find.byType(EditableText))) e.controller.text,
    ].join('\n');
    expect(shown, contains('Beres'));
    for (final secret in ['hunter22', 'Rahasia123', 'ABCDEFGHIJKLMNOP', '103.45.67.89', 'rahasia99']) {
      expect(shown, isNot(contains(secret)), reason: '$secret leaked into the chat UI');
    }
    a.messages.clear();
    a.session.todos = [];
  });

  Mission sampleMission() => Mission(
        id: 'm1',
        goal: 'Bikin produk SaaS buat UMKM dari nol sampai menghasilkan profit',
        criteria: 'Pembayaran masuk > biaya server per bulan',
        status: 'running',
        statusNote: 'Iterasi 7: Jalanin di VPS Jakarta…',
        iteration: 7,
        lastIterAt: DateTime.now().subtract(const Duration(minutes: 4)).millisecondsSinceEpoch,
        lastReport: '**Iterasi 6**: landing page *Kasirku* udah live di VPS, form daftar nyimpen ke Supabase.\nBerikutnya: halaman harga + checkout.',
        journal: '## Tahap 3/7 — MVP\n- [x] Riset: 3 ide divalidasi → pilih **kasir UMKM**\n- [x] Landing live (cek: HTTP 200)\n- [ ] Checkout (butuh Midtrans)\n\n**Pelajaran**: build Flutter web kegedean buat VPS 1GB → pakai HTML statis.',
        asks: [
          MissionAsk(id: 'a1', text: 'Daftar akun Midtrans pakai KTP & rekening lu, terus kirim server key-nya ke gw', why: 'buat nerima pembayaran'),
          MissionAsk(id: 'a2', text: 'Beli domain kasirku.id (± Rp200rb/thn)?', why: 'biar keliatan serius'),
        ],
      );

  testWidgets('missions list', (t) async {
    MissionRunner.i.missions = [
      sampleMission(),
      Mission(id: 'm2', goal: 'Jagain semua server tetap nyala, benerin sendiri kalau down', status: 'waiting', iteration: 31,
          statusNote: 'Provider error: HTTP 503 overloaded\nNyoba lagi 2 menit lagi (percobaan 3).'),
      Mission(id: 'm3', goal: 'Riset 20 produk affiliate paling laku minggu ini', status: 'done', iteration: 4, lastReport: 'Beres: 20 produk + link di Download/affiliate.md'),
    ];
    await shot(t, const MissionsPage(), 'missions');
  });

  testWidgets('mission detail', (t) async {
    MissionRunner.i.missions = [sampleMission()];
    await shot(t, const MissionDetailPage(id: 'm1'), 'mission_detail');
    MissionRunner.i.missions = [];
  });

  testWidgets('settings', (t) => shot(t, const SettingsPage(), 'settings'));
  testWidgets('add provider sheet reaches Antigravity', (t) => shot(t, const SettingsPage(), 'provider_add', after: () async {
        final add = find.text('Tambah provider');
        await t.ensureVisible(add.first);
        await t.pump(const Duration(milliseconds: 500));
        await t.tap(add.first);
        await t.pump(const Duration(seconds: 1));
        final ag = find.text('Antigravity (Termux)');
        expect(ag, findsOneWidget);
        await t.ensureVisible(ag);
        await t.pump(const Duration(milliseconds: 500));
        await t.tap(ag);
        await t.pump(const Duration(seconds: 1));
        expect(find.text('Perintah'), findsOneWidget);
      }));

  testWidgets('editor', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    final ctl = TextEditingController(text: 'server {\n  listen 80;\n  server_name payu.id;\n  root /var/www/payu;\n}\n');
    await t.pumpWidget(app(Scaffold(appBar: AppBar(title: const Text('nginx.conf')), body: CodeEditor(controller: ctl, undo: UndoHistoryController()))));
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/editor.png'));
  });

  testWidgets('hosts light', (t) async {
    C.light = true;
    await shot(t, const Shell(), 'hosts_light');
    C.light = false;
  });

  testWidgets('brain memory', (t) => shot(t, const BrainPage(initialTab: 1), 'brain_memory'));
  testWidgets('brain skills', (t) => shot(t, const BrainPage(initialTab: 2), 'brain_skills'));
  testWidgets('cek hp', (t) async {
    DiagSource.read = () async => phone(health: 76);
    saveManual({'layar': true, 'sentuh': true, 'speaker': true, 'mic': false});
    await shot(t, const CekHpPage(), 'cek_hp', after: () async {
      await t.tap(find.text('Jalanin diagnosa otomatis'));
      await t.pump(const Duration(seconds: 1));
    });
    saveManual({});
  });
  testWidgets('brain jobs', (t) => shot(t, const BrainPage(initialTab: 3), 'brain_jobs'));
}

Map<String, dynamic>? markasSnap;

Future<Map<String, dynamic>> _markasSample() async {
  final home = Directory.systemTemp.createTempSync('mk').path;
  Future<String> r(List<String> a, [String who = 'adam']) async =>
      '${(await Process.run('python3', ['../markas/markas.py', ...a, '--as', who], environment: {'MARKAS_HOME': home})).stdout}';
  await r(['init']);
  await r(['target', 'add', 'Payu: 10 UMKM bayar langganan', '--owner', 'hermes', '--deadline', '2026-11-30', '--metric', '10 invoice lunas']);
  await r(['target', 'add', 'Landing page Payu versi anti-slop', '--owner', 'web-designer', '--deadline', '2026-10-20']);
  await r(['target', 'add', '3 video motion buat portofolio', '--owner', 'adam', '--metric', '3 video di IG']);
  await r(['target', 'add', 'Konten IG Payu 2x/minggu', '--owner', 'muse']);
  await r(['target', 'update', '1', '--progress', '40'], 'hermes');
  await r(['target', 'update', '2', '--progress', '75'], 'web-designer');
  await r(['target', 'update', '3', '--progress', '100']);
  await r(['log', 'Hero + pricing section jadi, skor anti-slop 9/10', '--target', '2'], 'web-designer');
  await r(['log', '4 UMKM udah trial, 2 minta demo', '--target', '1'], 'hermes');
  await r(['say', 'Rapat pagi: 2 target jalan, Payu butuh keputusan harga paket.', '--to', 'adam'], 'satsh');
  await r(['say', 'oke, harga 49rb dulu']);
  final snap = jsonDecode(await r(['status', '--json'])) as Map<String, dynamic>;
  for (final k in ['logs', 'messages', 'targets']) {
    for (final e in (snap[k] as List? ?? const [])) {
      for (final f in ['at', 'created', 'updated']) {
        if ((e as Map).containsKey(f)) e[f] = '2026-10-05 08:00:00';
      }
    }
  }
  return snap;
}
