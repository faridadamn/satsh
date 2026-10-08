import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../models.dart';
import '../ssh_manager.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'sftp_page.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.session});
  final TermSession session;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _viewKey = GlobalKey<TerminalViewState>();
  TermSession get s => widget.session;
  bool _showSnippets = true;

  void _key(TerminalKey k) {
    HapticFeedback.selectionClick();
    final c = s.ctrl, a = s.alt;
    s.ctrl = false;
    s.alt = false;
    s.terminal.keyInput(k, ctrl: c, alt: a);
    if (c || a) setState(() {});
  }

  void _text(String t) {
    HapticFeedback.selectionClick();
    s.terminal.textInput(t);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null && d!.text!.isNotEmpty) s.terminal.paste(d.text!);
  }

  void _copy() {
    final sel = s.controller.selection;
    if (sel == null) {
      toast('Tahan & geser di terminal buat milih teks dulu', error: true);
      return;
    }
    Clipboard.setData(ClipboardData(text: s.terminal.buffer.getText(sel)));
    s.controller.clearSelection();
    toast('Ke-copy');
  }

  void _runSnippet(Snippet sn) {
    HapticFeedback.lightImpact();
    s.runCommand(sn.command, enter: sn.autoRun);
    _viewKey.currentState?.requestKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s, Store.i]),
      builder: (context, _) {
        final dead = s.state == ConnState.failed || s.state == ConnState.closed;
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(children: [
              StatusDot(s.state),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(s.host.address,
                      style: TextStyle(fontSize: 11, color: C.muted, fontFamily: monoFont)),
                ]),
              ),
            ]),
            actions: [
              IconButton(
                tooltip: 'File',
                icon: const Icon(Icons.folder_open_rounded),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => SftpPage(host: s.host))),
              ),
              PopupMenuButton<String>(
                color: C.surface2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (v) {
                  switch (v) {
                    case 'copy':
                      _copy();
                    case 'paste':
                      _paste();
                    case 'bigger':
                      Store.i.setFontSize(Store.i.fontSize + 1);
                    case 'smaller':
                      Store.i.setFontSize(Store.i.fontSize - 1);
                    case 'snip':
                      setState(() => _showSnippets = !_showSnippets);
                    case 'reconnect':
                      SshManager.i.reconnect(s);
                    case 'close':
                      SshManager.i.closeSession(s);
                      Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => [
                  _mi('copy', Icons.copy_rounded, 'Copy pilihan'),
                  _mi('paste', Icons.paste_rounded, 'Paste'),
                  _mi('bigger', Icons.text_increase_rounded, 'Font gedein'),
                  _mi('smaller', Icons.text_decrease_rounded, 'Font kecilin'),
                  _mi('snip', Icons.bolt_rounded, _showSnippets ? 'Sembunyiin snippet' : 'Tampilin snippet'),
                  _mi('reconnect', Icons.refresh_rounded, 'Reconnect'),
                  _mi('close', Icons.power_settings_new_rounded, 'Tutup sesi', color: C.red),
                ],
              ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: Stack(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                  child: TerminalView(
                    s.terminal,
                    key: _viewKey,
                    controller: s.controller,
                    theme: termTheme,
                    autofocus: true,
                    backgroundOpacity: 1,
                    keyboardType: TextInputType.visiblePassword,
                    textStyle: TerminalStyle(fontSize: Store.i.fontSize, fontFamily: monoFont),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: AnimatedSlide(
                    offset: dead ? Offset.zero : const Offset(0, 2),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: dead ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Center(
                        child: IgnorePointer(
                          ignoring: !dead,
                          child: SizedBox(
                            width: 200,
                            child: GradientButton(
                              label: 'Sambung lagi',
                              icon: Icons.refresh_rounded,
                              onTap: () => SshManager.i.reconnect(s),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: _showSnippets && Store.i.snippets.isNotEmpty
                  ? SizedBox(
                      height: 42,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                        scrollDirection: Axis.horizontal,
                        itemCount: Store.i.snippets.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final sn = Store.i.snippets[i];
                          return Pressable(
                            onTap: () => _runSnippet(sn),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: LinearGradient(colors: [
                                  C.violet.withValues(alpha: 0.22),
                                  C.cyan.withValues(alpha: 0.16),
                                ]),
                                border: Border.all(color: C.violet.withValues(alpha: 0.35)),
                              ),
                              alignment: Alignment.center,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(sn.autoRun ? Icons.bolt_rounded : Icons.edit_note_rounded,
                                    size: 14, color: C.cyan),
                                const SizedBox(width: 4),
                                Text(sn.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          );
                        },
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            _ExtraKeys(
              ctrl: s.ctrl,
              alt: s.alt,
              onCtrl: s.toggleCtrl,
              onAlt: s.toggleAlt,
              onKey: _key,
              onText: _text,
              onPaste: _paste,
              onKeyboard: () => _viewKey.currentState?.requestKeyboard(),
            ),
          ]),
        );
      },
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String t, {Color? color}) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(i, size: 20, color: color ?? C.text),
          const SizedBox(width: 12),
          Text(t, style: TextStyle(color: color ?? C.text)),
        ]),
      );
}

class _ExtraKeys extends StatelessWidget {
  const _ExtraKeys({
    required this.ctrl,
    required this.alt,
    required this.onCtrl,
    required this.onAlt,
    required this.onKey,
    required this.onText,
    required this.onPaste,
    required this.onKeyboard,
  });
  final bool ctrl, alt;
  final VoidCallback onCtrl, onAlt, onPaste, onKeyboard;
  final void Function(TerminalKey) onKey;
  final void Function(String) onText;

  @override
  Widget build(BuildContext context) {
    final keys = <Widget>[
      _K('ESC', onTap: () => onKey(TerminalKey.escape)),
      _K('TAB', onTap: () => onKey(TerminalKey.tab)),
      _K('CTRL', active: ctrl, onTap: onCtrl),
      _K('ALT', active: alt, onTap: onAlt),
      _K('', icon: Icons.keyboard_arrow_up_rounded, onTap: () => onKey(TerminalKey.arrowUp), repeat: true),
      _K('', icon: Icons.keyboard_arrow_down_rounded, onTap: () => onKey(TerminalKey.arrowDown), repeat: true),
      _K('', icon: Icons.keyboard_arrow_left_rounded, onTap: () => onKey(TerminalKey.arrowLeft), repeat: true),
      _K('', icon: Icons.keyboard_arrow_right_rounded, onTap: () => onKey(TerminalKey.arrowRight), repeat: true),
      _K('^C', accent: true, onTap: () => onText('\x03')),
      _K('/', onTap: () => onText('/')),
      _K('-', onTap: () => onText('-')),
      _K('|', onTap: () => onText('|')),
      _K('~', onTap: () => onText('~')),
      _K('HOME', onTap: () => onKey(TerminalKey.home)),
      _K('END', onTap: () => onKey(TerminalKey.end)),
      _K('PGUP', onTap: () => onKey(TerminalKey.pageUp)),
      _K('PGDN', onTap: () => onKey(TerminalKey.pageDown)),
      _K('', icon: Icons.content_paste_rounded, onTap: onPaste),
      _K('', icon: Icons.keyboard_rounded, onTap: onKeyboard),
    ];
    return Container(
      color: C.bg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            scrollDirection: Axis.horizontal,
            itemCount: keys.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) => keys[i],
          ),
        ),
      ),
    );
  }
}

class _K extends StatefulWidget {
  const _K(this.label, {required this.onTap, this.icon, this.active = false, this.accent = false, this.repeat = false});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool active, accent, repeat;

  @override
  State<_K> createState() => _KState();
}

class _KState extends State<_K> {
  bool _down = false;
  bool _holding = false;

  Future<void> _repeatLoop() async {
    _holding = true;
    await Future.delayed(const Duration(milliseconds: 350));
    while (_holding && mounted) {
      widget.onTap();
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.active;
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _down = true);
        widget.onTap();
        if (widget.repeat) _repeatLoop();
      },
      onTapUp: (_) => setState(() {
        _down = false;
        _holding = false;
      }),
      onTapCancel: () => setState(() {
        _down = false;
        _holding = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: on ? C.accent : null,
          color: on ? null : (_down ? C.surface2.withValues(alpha: 0.6) : C.surface2),
          borderRadius: BorderRadius.circular(10),
          border: widget.accent ? Border.all(color: C.pink.withValues(alpha: 0.5)) : null,
        ),
        transform: Matrix4.identity()..scaleByDouble(_down ? 0.92 : 1, _down ? 0.92 : 1, 1, 1),
        transformAlignment: Alignment.center,
        alignment: Alignment.center,
        child: widget.icon != null
            ? Icon(widget.icon, size: 20, color: C.text)
            : Text(widget.label,
                style: TextStyle(
                  fontFamily: monoFont,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : (widget.accent ? C.pink : C.text),
                )),
      ),
    );
  }
}
