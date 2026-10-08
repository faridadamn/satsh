/// Turns DeviceDiag.kt's raw data (+ the manual "Cek HP" tests) into a readable report with a
/// verdict — for checking a phone before buying it, or your own phone's health.
library;

import 'native.dart';

/// Where the agent tool gets its data (tests swap these).
class DiagSource {
  static Future<Map<String, dynamic>> Function() read = _native;
  static Future<String> Function(String what) logs = _nativeLogs;

  /// Last manual test results saved by the "Cek HP" page (only if from the last 24 hours).
  static Map<String, bool?> Function() manual = () => const {};

  static Future<Map<String, dynamic>> _native() => Native.deviceDiag();
  static Future<String> _nativeLogs(String w) => Native.deviceLogs(w);
}

/// Manual tests on the "Cek HP" page: id → label.
const manualTests = {
  'layar': 'Layar (dead pixel / garis / burn-in)',
  'sentuh': 'Sentuh semua area',
  'multitouch': 'Multitouch (≥ 3 jari)',
  'speaker': 'Speaker',
  'mic': 'Mikrofon',
  'getar': 'Getar',
  'kamera_belakang': 'Kamera belakang',
  'kamera_depan': 'Kamera depan',
  'ngecas': 'Port ngecas',
  'tombol': 'Tombol power & volume',
  'sinyal': 'Sinyal / SIM',
  'sidik_jari': 'Sidik jari / face unlock',
};

class Finding {
  Finding(this.level, this.text);

  /// 3 = 🔴 bahaya, 2 = 🟠 cek lagi, 1 = 🟡 catatan, 0 = ✅ oke
  final int level;
  final String text;

  String get icon => const ['✅', '🟡', '🟠', '🔴'][level];
}

class DiagReport {
  DiagReport(this.findings, this.text);
  final List<Finding> findings;
  final String text;

  int get worst => findings.fold(0, (m, f) => f.level > m ? f.level : m);

  String get verdict => switch (worst) {
        3 => '🔴 WASPADA — ada masalah serius, tawar keras atau skip',
        2 => '🟠 CEK LAGI — ada yang perlu dipastiin / jadi bahan nego',
        _ => '✅ LAYAK — ga ada masalah besar yang kedeteksi',
      };
}

num? _n(Object? v) => v is num ? v : null;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
String _f(num? v, [int d = 1]) => v == null ? '?' : v.toStringAsFixed(d);

/// Nearest marketing size (7.6 GB RAM → 8, 119 GB → 128).
int marketing(num gb, List<int> sizes) => sizes.firstWhere((s) => gb <= s * 1.02, orElse: () => sizes.last);

DiagReport buildReport(Map<String, dynamic> d, {Map<String, bool?> manual = const {}, DateTime? now}) {
  now ??= DateTime.now();
  final f = <Finding>[];
  final b = _m(d['battery']), dev = _m(d['device']), soc = _m(d['soc']), mem = _m(d['memory']), st = _m(d['storage']);
  final disp = _m(d['display']), sec = _m(d['security']), sens = _m(d['sensors']), th = _m(d['thermal']);
  final lines = <String>[];

  // ------------------------------------------------------------- battery
  final hp = _n(b['healthPct']), full = _n(b['fullEstimateMah']), design = _n(b['designMah']), pct = _n(b['percent']);
  final cycles = _n(b['cycles']) ?? _n(_m(b['sysfs'])['cycle_count']);
  lines.add('## Baterai');
  lines.add('- Sekarang: ${_f(pct, 0)}%${b['plugged'] != null && b['plugged'] != 'none' ? ' (lagi ngecas: ${b['plugged']})' : ''}'
      ', suhu ${_f(_n(b['tempC']))}°C, ${_f((_n(b['voltageMv']) ?? 0) / 1000, 2)} V, status "${b['health'] ?? '?'}"');
  if (full != null) {
    lines.add('- Kapasitas penuh (perkiraan): ~${_f(full, 0)} mAh${design != null ? ' dari desain ${_f(design, 0)} mAh' : ''}'
        '${hp != null ? ' → kesehatan ~${_f(hp, 0)}%' : ''}');
  } else {
    lines.add('- Kapasitas penuh: ga bisa diperkirain${(pct ?? 0) < 15 ? ' (baterai < 15% — cas dulu ke > 50% terus cek lagi)' : ' (HP ini ga ngasih data muatan mAh)'}');
  }
  if (cycles != null) lines.add('- Cycle: $cycles kali');
  if (hp != null) {
    if (hp < 65) {
      f.add(Finding(3, 'Baterai drop parah (~${_f(hp, 0)}% dari desain) — siap-siap ganti baterai'));
    } else if (hp < 78) {
      f.add(Finding(2, 'Baterai udah turun (~${_f(hp, 0)}% dari desain) — bahan nego / ganti dalam setahun'));
    } else if (hp < 88) {
      f.add(Finding(1, 'Baterai normal pemakaian (~${_f(hp, 0)}% dari desain)'));
    } else {
      f.add(Finding(0, 'Baterai sehat (~${_f(hp, 0)}% dari desain)'));
    }
    if (hp > 110) f.add(Finding(1, 'Angka kapasitas > desain: chip baterai HP ini kurang akurat / baterai bukan ori — anggap kira-kira'));
  } else {
    f.add(Finding(1, 'Kesehatan baterai ga bisa dihitung otomatis di HP ini — tes manual: dari 100% dipakai nonton YouTube 1 jam, normalnya turun ≤ 15%'));
  }
  if (cycles != null && cycles > 800) f.add(Finding(2, 'Cycle baterai tinggi ($cycles×)'));
  if (b['health'] != null && b['health'] != 'good' && b['health'] != 'unknown') f.add(Finding(3, 'Android lapor baterai "${b['health']}"'));
  if ((_n(b['tempC']) ?? 0) > 45) f.add(Finding(2, 'Baterai panas (${_f(_n(b['tempC']))}°C) pas dicek'));

  // ------------------------------------------------------------- specs
  lines.add('\n## Spek asli (dari sistem, bukan dari kardus)');
  lines.add('- ${dev['brand'] ?? ''} ${dev['model'] ?? ''} (${dev['device'] ?? ''}) · Android ${dev['android'] ?? '?'} · patch ${dev['securityPatch'] ?? '?'}');
  lines.add('- Chipset: ${soc['model'] ?? '?'} · ${soc['cores'] ?? '?'} core${soc['maxGhz'] != null ? ' · maks ${_f(_n(soc['maxGhz']), 2)} GHz' : ''}');
  final ram = _n(mem['totalGb']), sto = _n(st['totalGb']);
  if (ram != null) lines.add('- RAM: ${_f(ram)} GB terbaca → kelas ${marketing(ram, [1, 2, 3, 4, 6, 8, 12, 16, 24])} GB (sisa ${_f(_n(mem['availGb']))} GB)');
  if (sto != null) lines.add('- Storage: ${_f(sto, 0)} GB terbaca → kelas ${marketing(sto, [16, 32, 64, 128, 256, 512, 1024])} GB (kosong ${_f(_n(st['freeGb']), 0)} GB)');
  lines.add('- Layar: ${disp['px'] ?? '?'} · ~${_f(_n(disp['inchApprox']))}" · ${(disp['refreshHz'] as List?)?.join('/') ?? '?'} Hz${disp['hdr'] == true ? ' · HDR' : ''}');
  final cams = (d['cameras'] as List? ?? const []).map(_m).toList();
  if (cams.isNotEmpty) {
    lines.add('- Kamera: ${cams.map((c) => '${c['facing']} ${_f(_n(c['mp']), 0)}MP').join(', ')}');
  }
  final have = [for (final e in sens.entries) if (e.value == true) e.key];
  if (have.isNotEmpty) lines.add('- Fitur: ${have.join(', ')}');
  lines.add('_Cocokin RAM / storage / kamera di atas sama klaim penjual. Beda = HP dioprek / KW._');

  // ------------------------------------------------------------- security
  final su = (sec['suFound'] as List? ?? const []), apps = (sec['rootApps'] as List? ?? const []);
  if (su.isNotEmpty || apps.isNotEmpty) {
    f.add(Finding(3, 'HP ke-ROOT (${[...su, ...apps].join(', ')}) — keamanan & garansi bermasalah, tanya penjual'));
  }
  if (sec['testKeys'] == true || sec['debuggable'] == true) f.add(Finding(2, 'ROM bukan ROM resmi (test-keys / userdebug) — kemungkinan custom ROM'));
  final vb = '${sec['verifiedBoot'] ?? ''}';
  if (vb == 'orange') f.add(Finding(2, 'Bootloader ke-unlock (verified boot: orange)'));
  if (vb == 'yellow' || vb == 'red') f.add(Finding(3, 'Verified boot "$vb" — sistem ga lolos verifikasi'));
  final patch = DateTime.tryParse('${dev['securityPatch'] ?? ''}');
  if (patch != null && now.difference(patch).inDays > 730) {
    f.add(Finding(1, 'Patch keamanan udah tua (${dev['securityPatch']}) — HP udah ga dapet update'));
  }
  final ts = '${th['status'] ?? ''}';
  if (ts.isNotEmpty && ts != 'normal') f.add(Finding(ts == 'hangat' ? 1 : 2, 'Suhu sistem "$ts" pas dicek'));
  if (sto != null && _n(st['freeGb']) != null && _n(st['freeGb'])! / sto < 0.05) f.add(Finding(1, 'Storage hampir penuh'));

  // ------------------------------------------------------------- manual tests
  final done = manual.entries.where((e) => e.value != null).toList();
  if (done.isNotEmpty) {
    lines.add('\n## Tes manual');
    for (final e in done) {
      lines.add('- ${e.value! ? '✅' : '❌'} ${manualTests[e.key] ?? e.key}');
      if (e.value == false) f.add(Finding(3, 'Tes ${manualTests[e.key] ?? e.key} GAGAL'));
    }
    final skipped = manualTests.keys.where((k) => manual[k] == null).toList();
    if (skipped.isNotEmpty) f.add(Finding(1, 'Belum dites: ${skipped.map((k) => manualTests[k]).join(', ')}'));
  } else {
    f.add(Finding(1, 'Tes manual (layar, sentuh, speaker, mic, kamera…) belum dijalanin — buka Pengaturan → Cek HP'));
  }

  f.sort((a, b) => b.level.compareTo(a.level));
  final r = DiagReport(f, '');
  final text = StringBuffer()
    ..writeln('# Diagnosa ${dev['brand'] ?? ''} ${dev['model'] ?? ''}'.trim())
    ..writeln('**${r.verdict}**\n')
    ..writeln('## Temuan')
    ..writeln(f.map((x) => '- ${x.icon} ${x.text}').join('\n'))
    ..writeln()
    ..writeln(lines.join('\n'));
  return DiagReport(f, text.toString().trim());
}
