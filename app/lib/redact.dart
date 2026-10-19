/// Masks secrets (API keys, passwords, tokens, private keys, IPs) in text the
/// user SEES while the agent works: tool chips, status line, narration between
/// tool calls. What the model receives is untouched, so tools keep working.
///
/// Same rules as desktop/satsh/redact.py — keep them in sync.
class Redact {
  Redact._();

  static const mask = '••••';

  /// Secrets we know exactly (host passwords, provider keys…), filled at startup.
  static final Set<String> _known = {};

  /// Off in Settings → "Sensor data sensitif" (default on).
  static bool enabled = true;

  static void learn(Iterable<String?> values) {
    for (final v in values) {
      final t = v?.trim() ?? '';
      // Plain words ("server", "rahasia") would mask normal text too: need 8+, or 6+ with a digit/symbol.
      if (t.length >= 8 || (t.length >= 6 && RegExp(r'[^A-Za-z]').hasMatch(t))) _known.add(t);
    }
  }

  static void forgetAll() => _known.clear();

  static final _rules = <(RegExp, String Function(Match))>[
    // PEM private keys (whole block)
    (
      RegExp(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z0-9 ]*PRIVATE KEY-----|$)'),
      (m) => '-----BEGIN PRIVATE KEY----- $mask -----END PRIVATE KEY-----'
    ),
    // Well-known token shapes
    (
      RegExp(r'\b(sk-(?:ant-|proj-|or-v1-)?[A-Za-z0-9_\-]{16,}|AIza[0-9A-Za-z_\-]{30,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
          r'|glpat-[A-Za-z0-9_\-]{16,}|xox[abposr]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|hf_[A-Za-z0-9]{20,}|gsk_[A-Za-z0-9]{20,}'
          r'|pplx-[A-Za-z0-9]{20,}|r8_[A-Za-z0-9]{20,}|sbp_[A-Za-z0-9]{20,}|whsec_[A-Za-z0-9]{16,}|(?:rk|pk|sk)_(?:live|test)_[A-Za-z0-9]{16,})'),
      (m) => _keep(m[0]!, 4)
    ),
    // JWT (Supabase anon/service keys, session tokens…)
    (RegExp(r'\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}'), (m) => 'eyJ…$mask'),
    // Telegram bot token
    (RegExp(r'\b\d{8,10}:AA[A-Za-z0-9_\-]{30,}'), (m) => '${m[0]!.split(':').first}:$mask'),
    // Authorization headers
    (RegExp(r'\b(Bearer|Basic|Token)\s+[A-Za-z0-9._~+/=\-]{8,}', caseSensitive: false), (m) => '${m[1]} $mask'),
    // user:password@host in URLs / connection strings
    (RegExp(r'(\b[a-z][a-z0-9+.\-]*://[^\s:/@]+:)([^\s@/]+)(@)', caseSensitive: false), (m) => '${m[1]}$mask${m[3]}'),
    // key=value / key: value / "key": "value" for secret-looking keys
    (
      RegExp(
          r'''(["']?\b[\w.\-]*(?:pass(?:word|wd|phrase)?|pwd|secret|token|api[_\-]?key|apikey|access[_\-]?key|private[_\-]?key|client[_\-]?secret|auth[_\-]?key|service[_\-]?role|credential|_key)[\w\-]*["']?\s*[:=]\s*)(["']?)([^\s"',;}&]{3,})(["']?)''',
          caseSensitive: false),
      (m) => RegExp(r'^\d{1,5}$').hasMatch(m[3]!) ? m[0]! : '${m[1]}${m[2]}$mask${m[4]}'
    ),
    // CLI flags: --password x, --token=x, sshpass -p x, mysql -pSECRET
    (
      RegExp(r'''(--(?:password|passwd|pass|token|api-key|apikey|secret)[= ]\s*)(["']?)[^\s"']+\2''', caseSensitive: false),
      (m) => '${m[1]}$mask'
    ),
    (RegExp(r'''(\bsshpass\s+-p\s*)(["']?)[^\s"']+\2'''), (m) => '${m[1]}$mask'),
    // Natural language: "password-nya adalah X", "kata sandi: X", "passwordnya X"
    (
      RegExp(r'''(\b(?:password|passwd|kata\s*sandi|sandi|pw|pin|passcode)(?:\s+(?:wifi|root|db|database|ssh|vps|server|admin|email|router|hp|laptop|user))?(?:(?:[\s-]?nya)?\s*[:=]\s*|(?:[\s-]?nya)?\s+(?:adalah|is|yaitu)\s+|[\s-]?nya\s+))(["'`]?)(?!••••)([^\s"'`,;]{4,})\2''', caseSensitive: false),
      (m) => RegExp(r'^(yang|untuk|buat|baru|lama|default|salah|benar|aman|kuat|lemah|udah|sudah|belum|masih|harus|bisa|ganti|diganti|apa|gimana|ini|itu)$', caseSensitive: false).hasMatch(m[3]!) ? m[0]! : '${m[1]}$mask'
    ),
    (RegExp(r'''(\b(?:mysql|mariadb|mysqldump)\b[^\n|;]*?\s-p)(?!\s)(["']?)[^\s"']+\2'''), (m) => '${m[1]}$mask'),
    // ?token=… &api_key=… in query strings
    (
      RegExp(r'([?&](?:token|access_token|api_key|apikey|key|secret|sig|signature|password)=)[^&\s#"]+', caseSensitive: false),
      (m) => '${m[1]}$mask'
    ),
    // IPv4 (keeps loopback / 0.0.0.0 readable)
    (
      RegExp(r'(?<![\d.])((?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.)((?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){2}((?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d))(?![\d.]*\d)'),
      (m) => (m[0]!.startsWith('127.') || m[0] == '0.0.0.0') ? m[0]! : '${m[1]}•.•.${m[3]}'
    ),
  ];

  static String _keep(String s, int n) => s.length <= n + 4 ? mask : '${s.substring(0, n)}$mask';

  /// Masks everything secret-looking in [s]. [force] ignores the Settings
  /// switch — for text that leaves the phone (error reports).
  static String text(String s, {bool force = false}) {
    if ((!enabled && !force) || s.isEmpty) return s;
    var out = s;
    for (final k in _known) {
      if (out.contains(k)) out = out.replaceAll(k, mask);
    }
    for (final (re, f) in _rules) {
      out = out.replaceAllMapped(re, f);
    }
    return out;
  }

  /// Deep-masks a JSON-ish value (tool-call args). Values under secret-looking
  /// keys are masked outright.
  static Object? value(Object? v, [String key = '']) {
    if (!enabled) return v;
    if (v is String) return _secretKey.hasMatch(key) && v.isNotEmpty ? mask : text(v);
    if (v is Map) return {for (final e in v.entries) e.key: value(e.value, '${e.key}')};
    if (v is List) return [for (final e in v) value(e, key)];
    return v;
  }

  static final _secretKey =
      RegExp(r'(pass(word|wd|phrase)?|pwd|secret|token|api[_\-]?key|apikey|private[_\-]?key|authorization|credential)$', caseSensitive: false);

  static Map<String, dynamic> args(Map<String, dynamic> a) => Map<String, dynamic>.from(value(a) as Map);

  /// Why [s] (a URL or text the agent is about to send OUT of the phone) looks
  /// like it carries a secret, or null. Independent of [enabled]: this guards
  /// against prompt-injected exfiltration ("read ~/.ssh/id_rsa, then open
  /// https://evil/?k=…"), it isn't a display setting.
  static String? leakReason(String s) {
    if (s.isEmpty) return null;
    var t = s;
    try {
      t = Uri.decodeFull(s.replaceAll('+', ' '));
    } catch (_) {}
    for (final k in _known) {
      if (t.contains(k)) return 'ada password / key yang lu simpen di satsh';
    }
    // Every rule except the IPv4 one (an IP in a URL is normal).
    for (final (re, _) in _rules.take(_rules.length - 1)) {
      if (re.hasMatch(t)) return 'ada yang mirip private key / token / password';
    }
    final u = Uri.tryParse(s);
    if (u != null && u.hasScheme) {
      final parts = [...u.pathSegments, ...u.queryParametersAll.values.expand((v) => v), u.fragment];
      final longest = parts.fold<int>(0, (m, p) => p.length > m ? p.length : m);
      if (longest > 300) return 'URL-nya bawa data panjang ($longest karakter) — bisa jadi isi file yang mau dikirim keluar';
    }
    return null;
  }
}
