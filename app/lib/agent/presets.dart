import 'package:flutter/services.dart';

/// Built-in agent profiles shipped inside the app (assets/presets/ID/…).
/// Same files ship with satsh desktop (desktop/satsh/presets/ID/…).
class Presets {
  Presets._();
  static const ids = ['web-designer', 'cybersecurity', 'devops', 'code-reviewer'];
  static const _base = 'assets/presets';

  static const names = {
    'web-designer': '🎨 Web Designer — UI web anti-slop (AGENTS.md + DESIGN.md + gambar referensi)',
    'cybersecurity': '🛡️ Cyber Security — audit & hardening server, cek secret bocor, keamanan web app, triase insiden',
    'devops': '🚀 DevOps — rilis aman + rollback, backup & restore, Docker, Nginx + SSL',
    'code-reviewer': '🔍 Code Reviewer — review diff dengan bukti, jalanin tes, audit dependency',
  };

  /// All files of preset [id], keyed by path relative to the preset folder.
  static Future<Map<String, String>> load(String id, {AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final prefix = '$_base/$id/';
    final out = <String, String>{};
    for (final a in manifest.listAssets().where((a) => a.startsWith(prefix))) {
      out[a.substring(prefix.length)] = await b.loadString(a, cache: false);
    }
    if (!out.containsKey('profile.json')) throw 'Preset $id ga ada';
    return out;
  }

  static Map<String, Future<Map<String, String>> Function()> all({AssetBundle? bundle}) =>
      {for (final id in ids) id: () => load(id, bundle: bundle)};
}
