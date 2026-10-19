import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'redact.dart';

const appVersion = '2.7.2 (27)';

/// One captured error with enough context to find the bug.
class ErrorEntry {
  ErrorEntry({required this.time, required this.source, required this.message, this.stack = '', Map<String, String>? context})
      : context = context ?? {};
  final DateTime time;
  final String source; // agent | cron | tool | llm | flutter | async | native
  final String message;
  final String stack;
  final Map<String, String> context;

  Map<String, dynamic> toJson() =>
      {'t': time.toIso8601String(), 'src': source, 'msg': message, 'stack': stack, if (context.isNotEmpty) 'ctx': context};

  factory ErrorEntry.fromJson(Map<String, dynamic> j) => ErrorEntry(
        time: DateTime.tryParse('${j['t']}') ?? DateTime.now(),
        source: '${j['src'] ?? '?'}',
        message: '${j['msg'] ?? ''}',
        stack: '${j['stack'] ?? ''}',
        context: Map<String, String>.from((j['ctx'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {}),
      );

  String toText() {
    final b = StringBuffer()
      ..writeln('[${time.toIso8601String().substring(0, 19)}] $source')
      ..writeln(message);
    for (final e in context.entries) {
      b.writeln('  ${e.key}: ${e.value}');
    }
    if (stack.trim().isNotEmpty) b.writeln(stack.trim());
    return Redact.text(b.toString(), force: true); // reports get shared — never leak keys/passwords, even with the sensor off
  }
}

/// Keeps the last [max] errors on disk (logs/errors.jsonl) so a bug report
/// carries the real stack trace, not just "Null check operator…".
class ErrorLog extends ChangeNotifier {
  ErrorLog._();
  static final ErrorLog i = ErrorLog._();
  static const max = 200;

  @visibleForTesting
  static String? dirOverride;

  final List<ErrorEntry> entries = [];
  File? _file;
  String _device = '';
  Future<void>? _loading;

  Future<void> init() => _loading ??= _init();

  Future<void> _init() async {
    try {
      final d = Directory(dirOverride ?? '${(await getApplicationDocumentsDirectory()).path}/logs');
      await d.create(recursive: true);
      _file = File('${d.path}/errors.jsonl');
      if (await _file!.exists()) {
        for (final line in await _file!.readAsLines()) {
          try {
            entries.add(ErrorEntry.fromJson(jsonDecode(line) as Map<String, dynamic>));
          } catch (_) {}
        }
      }
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        _device = '${a.manufacturer} ${a.model}, Android ${a.version.release} (SDK ${a.version.sdkInt})';
      }
    } catch (_) {}
  }

  /// Hooks Flutter + async errors so nothing slips by silently.
  void installGlobalHandlers() {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      add('flutter', d.exception, d.stack, context: {if (d.library != null) 'library': d.library!, if (d.context != null) 'saat': '${d.context}'});
      prev?.call(d);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      add('async', e, st);
      return true;
    };
  }

  /// Records an error. Never throws.
  void add(String source, Object error, StackTrace? stack, {Map<String, String>? context}) {
    try {
      final e = ErrorEntry(
        time: DateTime.now(),
        source: source,
        message: '$error'.length > 2000 ? '${'$error'.substring(0, 2000)}…' : '$error',
        stack: _trim(stack),
        context: {...?context},
      );
      entries.add(e);
      if (entries.length > max) entries.removeRange(0, entries.length - max);
      notifyListeners();
      unawaited(_save());
    } catch (_) {}
  }

  /// Keep the frames that matter (app code first), max ~40 lines.
  static String _trim(StackTrace? st) {
    if (st == null) return '';
    final lines = '$st'.split('\n').where((l) => l.trim().isNotEmpty).map((l) => l.replaceAll(RegExp(r' {2,}'), ' ')).toList();
    return lines.take(40).join('\n');
  }

  Future<void> _save() async {
    await init();
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString('${entries.map((e) => jsonEncode(e.toJson())).join('\n')}\n');
    } catch (_) {}
  }

  Future<void> clear() async {
    entries.clear();
    notifyListeners();
    await _save();
  }

  /// Plain-text report to paste into a chat / bug report. Secrets never get logged here.
  String report({int last = 30}) {
    final pick = entries.length > last ? entries.sublist(entries.length - last) : entries;
    final b = StringBuffer()
      ..writeln('=== satsh error log ===')
      ..writeln('versi: $appVersion')
      ..writeln('perangkat: ${_device.isEmpty ? Platform.operatingSystem : _device}')
      ..writeln('dibuat: ${DateTime.now().toIso8601String().substring(0, 19)}')
      ..writeln('jumlah error: ${pick.length}${entries.length > pick.length ? ' (dari ${entries.length})' : ''}')
      ..writeln();
    for (final e in pick.reversed) {
      b
        ..writeln(e.toText())
        ..writeln('---');
    }
    return b.toString();
  }

  Future<File> reportFile() async {
    final d = await getTemporaryDirectory();
    final f = File('${d.path}/satsh-error-log-${DateTime.now().millisecondsSinceEpoch}.txt');
    await f.writeAsString(report(last: max));
    return f;
  }
}
