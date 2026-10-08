import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'ssh_manager.dart';
import 'theme.dart';

final navKey = GlobalKey<NavigatorState>();

/// Squishy press feedback — the app's signature micro-interaction.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) => setState(() => _down = v);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Fade + slide up, delayed by index — for lists.
class StaggerIn extends StatelessWidget {
  const StaggerIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 10)) * 0.06;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + (delay * 1000).round()),
      curve: Interval(delay / (0.42 + delay), 1, curve: Curves.easeOutCubic),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style, this.gradient = C.accent});
  final String text;
  final TextStyle? style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => gradient.createShader(r),
        blendMode: BlendMode.srcIn,
        child: Text(text, style: style),
      );
}

class StatusDot extends StatefulWidget {
  const StatusDot(this.state, {super.key, this.size = 8});
  final ConnState? state;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      ConnState.ready => C.green,
      ConnState.connecting => C.amber,
      ConnState.failed => C.red,
      _ => C.muted,
    };
    final pulse = widget.state == ConnState.connecting || widget.state == ConnState.ready;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: pulse
              ? [BoxShadow(color: color.withValues(alpha: 0.6 * _c.value), blurRadius: 8, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.icon, this.onTap, this.busy = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: busy ? null : onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: C.accent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: StaggerIn(
            index: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(gradient: C.accent, borderRadius: BorderRadius.circular(28)),
                child: Icon(icon, color: Colors.white, size: 38),
              ),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.4)),
            ]),
          ),
        ),
      );
}

void toast(String msg, {bool error = false}) {
  final ctx = navKey.currentContext;
  if (ctx == null) return;
  ScaffoldMessenger.of(ctx)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: error ? C.red : C.green, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      duration: const Duration(milliseconds: 2200),
    ));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Hapus'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body, style: TextStyle(color: C.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.red),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('OK')),
      ],
    ),
  );
}

/// Dialog implementations for the SSH manager.
class UiPrompts implements Prompts {
  @override
  Future<bool> trustHostKey(Host h, String type, String fp, String? oldFp) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return false;
    final changed = oldFp != null;
    final r = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: Icon(changed ? Icons.warning_amber_rounded : Icons.fingerprint_rounded,
            color: changed ? C.red : C.cyan, size: 36),
        title: Text(changed ? 'Host key BERUBAH!' : 'Server baru nih'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            changed
                ? 'Fingerprint ${h.host} beda dari sebelumnya. Bisa karena server di-reinstall, atau ada yang nyadap. Lanjut cuma kalau lu yakin.'
                : 'Pertama kali connect ke ${h.host}. Cocokin fingerprint ini kalau mau aman:',
            style: TextStyle(color: C.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
            child: SelectableText('$type\n$fp',
                style: TextStyle(fontFamily: monoFont, fontSize: 12, color: C.text)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Tolak')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: changed ? C.red : C.violet),
            onPressed: () => Navigator.pop(c, true),
            child: Text(changed ? 'Tetap percaya' : 'Percaya & lanjut'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Future<String?> askPassword(Host h, {String? reason}) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return null;
    final ctl = TextEditingController();
    var obscure = true;
    return showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(h.address, style: const TextStyle(fontSize: 18)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(reason, style: const TextStyle(color: C.amber)),
              ),
            TextField(
              controller: ctl,
              autofocus: true,
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => set(() => obscure = !obscure),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(c, v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Masuk')),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that never hides its last row behind Android's gesture/nav bar
/// (edge-to-edge on Android 15+).
Future<T?> showSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      useSafeArea: useSafeArea,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewPadding.bottom + 8),
        child: builder(c),
      ),
    );
