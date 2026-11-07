import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Statistik prompt cache dari provider (OpenAI-compatible & Gemini).
///
/// Sebelumnya angka cache hit cuma bisa dilihat di dashboard provider.
/// Kelas ini nyatet `cached_tokens` tiap request biar ketahuan dari sisi app:
/// kalau `hitRate` rendah, berarti prefix prompt kita berubah-ubah.
class CacheStats extends ChangeNotifier {
  CacheStats._();
  static final CacheStats i = CacheStats._();

  int promptTokens = 0;
  int cachedTokens = 0;
  int requests = 0;

  /// Request terakhir: berapa token prompt & berapa yang kena cache.
  int lastPrompt = 0;
  int lastCached = 0;

  double get hitRate => promptTokens == 0 ? 0 : cachedTokens / promptTokens;

  String get summary {
    if (requests == 0) return 'cache: belum ada data';
    final pct = (hitRate * 100).toStringAsFixed(0);
    return 'cache $pct% ($cachedTokens/$promptTokens token, ${requests}x request)';
  }

  /// Dipanggil tiap balasan model. Nilai 0/0 diabaikan (provider ga lapor).
  void add(int prompt, int cached) {
    if (prompt <= 0) return;
    requests++;
    final c = cached < 0 ? 0 : (cached > prompt ? prompt : cached);
    promptTokens += prompt;
    cachedTokens += c;
    lastPrompt = prompt;
    lastCached = c;
    notifyListeners();
    unawaited(_append(prompt, lastCached));
  }

  void reset() {
    promptTokens = 0;
    cachedTokens = 0;
    requests = 0;
    lastPrompt = 0;
    lastCached = 0;
    notifyListeners();
  }

  /// Simpan 1 baris JSON per request ke logs/cache.jsonl (buat audit).
  Future<void> _append(int prompt, int cached) async {
    try {
      final d = Directory('${(await getApplicationDocumentsDirectory()).path}/logs');
      await d.create(recursive: true);
      await File('${d.path}/cache.jsonl').writeAsString(
        '${jsonEncode({'t': DateTime.now().toIso8601String(), 'prompt': prompt, 'cached': cached})}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {
      // instrumentasi ga boleh pernah bikin chat gagal
    }
  }
}
