import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pinenacl/x25519.dart' show SecretBox, EncryptedMessage;

/// Password-locked backups: PBKDF2-HMAC-SHA256 → 32-byte key →
/// XSalsa20-Poly1305 (NaCl secretbox). The whole backup JSON is sealed, so a
/// backup "with secrets" that ends up in Drive / WhatsApp / Download doesn't
/// hand out every SSH key and API key in plain text.
class BackupCrypto {
  BackupCrypto._();

  static const kdf = 'pbkdf2-sha256';
  static const defaultIterations = 310000;

  static bool isLocked(Map<String, dynamic> j) => j['enc'] is Map;

  /// Seals [plain] (the normal backup JSON) under [password].
  static Future<String> lock(String plain, String password, {int iterations = defaultIterations}) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final key = await compute(_derive, (password, salt, iterations));
    final box = SecretBox(key).encrypt(Uint8List.fromList(utf8.encode(plain)));
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'satsh',
      'version': 1,
      'enc': {
        'v': 1,
        'kdf': kdf,
        'iter': iterations,
        'salt': base64.encode(salt),
        'box': base64.encode(Uint8List.fromList(box)), // nonce (24) + ciphertext
      },
    });
  }

  /// Opens a locked backup; throws a user-facing String on a wrong password.
  static Future<String> unlock(Map<String, dynamic> j, String password) async {
    final e = Map<String, dynamic>.from(j['enc'] as Map);
    if (e['v'] != 1 || e['kdf'] != kdf) throw 'Format backup terkunci ini ga dikenal (update satsh dulu)';
    final iter = (e['iter'] as num).toInt();
    if (iter < 10000 || iter > 10000000) throw 'File backup rusak';
    final List<int> salt = base64.decode(e['salt'] as String);
    final key = await compute(_derive, (password, salt, iter));
    try {
      final plain = SecretBox(key).decrypt(EncryptedMessage.fromList(base64.decode(e['box'] as String)));
      return utf8.decode(plain);
    } catch (_) {
      throw 'Password salah (atau file-nya rusak)';
    }
  }

  static Uint8List _derive((String, List<int>, int) a) => pbkdf2Sha256(utf8.encode(a.$1), a.$2, a.$3, 32);

  /// RFC 8018 PBKDF2 with HMAC-SHA256.
  @visibleForTesting
  static Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder(copy: false);
    for (var block = 1; out.length < length; block++) {
      final u0 = hmac.convert([...salt, block >> 24 & 0xff, block >> 16 & 0xff, block >> 8 & 0xff, block & 0xff]).bytes;
      final t = Uint8List.fromList(u0);
      var u = u0;
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      out.add(t);
    }
    return Uint8List.sublistView(out.takeBytes(), 0, length);
  }
}
