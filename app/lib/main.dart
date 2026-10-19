import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agent/agent.dart';
import 'agent/mission.dart';
import 'agent/providers.dart';
import 'error_log.dart';
import 'keepalive.dart';
import 'native.dart';
import 'phone_control.dart';
import 'agent/agent_zip.dart';
import 'phone_server.dart';
import 'diag.dart';
import 'pages/cek_hp_page.dart' show savedManual;
import 'pages/agent_page.dart';
import 'pages/forwards_page.dart';
import 'pages/hosts_page.dart';
import 'nav.dart';
import 'pages/snippets_page.dart';
import 'ssh_manager.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorLog.i.init();
  ErrorLog.i.installGlobalHandlers();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0C0D12),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Store.i.load();
  await Providers.migrate();
  await AgentController.i.load();
  await MissionRunner.i.load();
  C.light = Store.i.get<String>('theme', 'dark') == 'light';
  SshManager.i.prompts = UiPrompts();
  KeepAliveService.i.init();
  Native.init();
  Native.onControlStopped = AgentController.i.stop;
  PhoneControl.i.configure();
  DiagSource.manual = savedManual;
  AgentZip.providerIds = () async => Providers.all().map((p) => p.id);
  AgentController.i.approver = (tool, args) async {
    final ctx = navKey.currentContext;
    return ctx == null ? 'no' : askApproval(ctx, tool, args);
  };
  CronRunner.i.onDone = KeepAliveService.i.notify;
  CronRunner.i.start();
  MissionRunner.i.notifier = (title, body, id) {
    KeepAliveService.i.notify(title, body);
    Native.notifyIfAway(title, body, id: id);
  };
  PhoneServer.i.init().ignore();
  runApp(const SatshApp());
}

class SatshApp extends StatefulWidget {
  const SatshApp({super.key});

  @override
  State<SatshApp> createState() => _SatshAppState();
}

class _SatshAppState extends State<SatshApp> {
  @override
  void initState() {
    super.initState();
    Store.i.addListener(_onStore);
  }

  void _onStore() {
    final light = Store.i.get<String>('theme', 'dark') == 'light';
    if (light == C.light) return;
    C.light = light;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: C.bg,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
    setState(() {});
    // Colors are read straight from C everywhere, so repaint the whole tree
    // (keeps navigation + terminal state, unlike remounting).
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => (context as Element).visitChildren(rebuild));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'satsh',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        theme: buildTheme(),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int get _tab => shellTab.value;
  set _tab(int v) => shellTab.value = v;

  @override
  void initState() {
    super.initState();
    shellTab.addListener(_onTab);
  }

  @override
  void dispose() {
    shellTab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  static const _items = [
    (Icons.dns_rounded, 'Host'),
    (Icons.auto_awesome_rounded, 'Agent'),
    (Icons.bolt_rounded, 'Snippet'),
    (Icons.swap_horiz_rounded, 'Tunnel'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: switch (_tab) {
            0 => const HostsPage(),
            1 => const AgentPage(),
            2 => const SnippetsPage(),
            _ => const ForwardsPage(),
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 62,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: C.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: C.stroke),
              boxShadow: [BoxShadow(color: C.light ? Colors.black12 : Colors.black54, blurRadius: 30, offset: const Offset(0, 10))],
            ),
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / _items.length;
              return Stack(children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  left: w * _tab,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: Container(
                    decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => setState(() => _tab = i),
                        child: Center(
                          child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_items[i].$1, size: 20, color: i == _tab ? Colors.white : C.muted),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              child: i == _tab
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(_items[i].$2,
                                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ])),
                        ),
                      ),
                    ),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
