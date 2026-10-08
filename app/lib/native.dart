import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Thin wrapper over the Android side: voice in/out, notifications,
/// phone-screen capture, WebView cookies.
class Native {
  Native._();
  static const _ch = MethodChannel('satsh/native');

  /// True while text-to-speech is talking.
  static final speaking = ValueNotifier<bool>(false);

  /// User hit the floating STOP pill while the agent was driving the phone.
  static VoidCallback? onControlStopped;
  static bool _wired = false;

  static void init() {
    if (_wired) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'speaking') speaking.value = call.arguments == true;
      if (call.method == 'controlStopped') onControlStopped?.call();
      return null;
    });
  }

  // ------------------------------------------------------- diagnostics
  /// Battery capacity estimate, real specs, root hints (android/…/DeviceDiag.kt).
  static Future<Map<String, dynamic>> deviceDiag() async =>
      Map<String, dynamic>.from(_deep(await _ch.invokeMethod('deviceDiag')) as Map);

  /// "crash" | "battery" | "batterystats" — needs the one-time adb grant, else starts with NEED_GRANT.
  static Future<String> deviceLogs(String what) async => await _ch.invokeMethod<String>('deviceLogs', {'what': what}) ?? '';

  static Future<bool> vibrate([int ms = 400]) async => await _ch.invokeMethod<bool>('vibrate', {'ms': ms}) ?? false;

  static Object? _deep(Object? v) => v is Map
      ? {for (final e in v.entries) '${e.key}': _deep(e.value)}
      : v is List
          ? [for (final x in v) _deep(x)]
          : v;

  // ------------------------------------------------------------- voice
  /// Opens Android's speech dialog. Null = cancelled / nothing heard.
  static Future<String?> listen({String lang = 'id-ID'}) => _ch.invokeMethod<String>('listen', {'lang': lang});

  static Future<void> speak(String text) async {
    final t = speakable(text);
    if (t.isEmpty) return;
    speaking.value = true;
    await _ch.invokeMethod('speak', {'text': t});
  }

  static Future<void> stopSpeak() async {
    speaking.value = false;
    await _ch.invokeMethod('stopSpeak');
  }

  /// Markdown → something that sounds OK read aloud.
  static String speakable(String md) {
    var s = md;
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' (ada kode, cek di layar) ');
    s = s.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!);
    s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!);
    s = s.replaceAll(RegExp(r'https?://\S+'), 'link');
    s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
    s = s.replaceAll(RegExp(r'[*_`~|]'), '');
    s = s.replaceAll(RegExp(r'\n{2,}'), '. ').replaceAll('\n', ', ');
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  // ----------------------------------------------------- notifications
  /// Only shows when the app isn't on screen — no point otherwise.
  static Future<void> notifyIfAway(String title, String body, {int id = 1}) async {
    try {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return;
      await _ch.invokeMethod('notify', {'title': title, 'body': body.length > 400 ? '${body.substring(0, 400)}…' : body, 'id': id});
    } catch (_) {}
  }

  // ------------------------------------------------------ phone screen
  static Future<bool> screenOn() async => (await _ch.invokeMethod<bool>('screenStatus')) ?? false;

  /// Shows Android's "start recording/casting" consent (once per session).
  static Future<void> screenStart() => _ch.invokeMethod('screenStart');
  static Future<void> screenStop() => _ch.invokeMethod('screenStop');

  static Future<({Uint8List bytes, int w, int h})> screenShot({int maxW = 720, int q = 70}) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('screenShot', {'maxW': maxW, 'q': q});
    return (bytes: r!['bytes'] as Uint8List, w: r['w'] as int, h: r['h'] as int);
  }

  // ----------------------------------------------------------- browser
  static Future<String> cookies(String url) async => (await _ch.invokeMethod<String>('cookies', {'url': url})) ?? '';
}
