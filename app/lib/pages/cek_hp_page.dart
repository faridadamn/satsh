import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../agent/agent.dart';
import '../diag.dart';
import '../native.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_page.dart' show MessageBody;
import '../nav.dart';

/// Saved results of the manual tests (Store 'diagManual' = {at, r: {id: bool}}), valid for 24 h.
Map<String, bool?> savedManual() {
  final raw = Store.i.get<Map>('diagManual', const {});
  final at = (raw['at'] as num?)?.toInt() ?? 0;
  if (DateTime.now().millisecondsSinceEpoch - at > const Duration(hours: 24).inMilliseconds) return {};
  return {for (final e in Map<String, dynamic>.from(raw['r'] as Map? ?? const {}).entries) e.key: e.value as bool?};
}

void saveManual(Map<String, bool?> r) =>
    Store.i.set('diagManual', {'at': DateTime.now().millisecondsSinceEpoch, 'r': {for (final e in r.entries) if (e.value != null) e.key: e.value}});

/// "Cek HP": automatic diagnosis + hands-on tests (screen, touch, speaker, mic, camera…) → one report.
class CekHpPage extends StatefulWidget {
  const CekHpPage({super.key});

  @override
  State<CekHpPage> createState() => _CekHpPageState();
}

class _CekHpPageState extends State<CekHpPage> {
  Map<String, bool?> _r = savedManual();
  DiagReport? _rep;
  bool _busy = false;

  Future<void> _auto() async {
    setState(() => _busy = true);
    try {
      final d = await DiagSource.read();
      _rep = buildReport(d, manual: _r);
    } catch (e) {
      toast('Gagal diagnosa: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _set(String id, bool? ok) {
    setState(() => _r[id] = ok);
    saveManual(_r);
    if (_rep != null) _auto();
  }

  Future<bool?> _ask(String title, String q, {String yes = 'Iya, normal', String no = 'Ada masalah'}) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(q, style: TextStyle(color: C.muted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no, style: const TextStyle(color: C.red))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
          ],
        ),
      );

  Future<void> _run(String id) async {
    bool? ok;
    switch (id) {
      case 'layar':
        await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScreenTest()));
        if (!mounted) return;
        ok = await _ask('Layar', 'Tadi ada titik mati, garis, warna belang, atau bayangan (burn-in) di salah satu warna?', yes: 'Bersih', no: 'Ada');
      case 'sentuh':
        ok = await Navigator.push<bool>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _TouchTest()));
      case 'multitouch':
        ok = await Navigator.push<bool>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _MultiTouchTest()));
      case 'speaker':
        await Native.speak('Tes speaker. Satu, dua, tiga. Suara ini harus jelas, ga pecah.');
        if (!mounted) return;
        ok = await _ask('Speaker', 'Suaranya kedengeran jelas & ga pecah? (naikin volume dulu)');
      case 'mic':
        toast('Ngomong: "satu dua tiga empat lima"');
        final heard = await Native.listen();
        if (!mounted) return;
        ok = heard != null && heard.trim().isNotEmpty
            ? await _ask('Mikrofon', 'Kedengeran: "$heard"\nCocok sama yang lu omongin?', yes: 'Cocok', no: 'Ngaco')
            : await _ask('Mikrofon', 'Ga ada suara yang ketangkep. Coba sekali lagi deket mic — atau mic-nya rusak?', yes: 'Coba lagi nanti', no: 'Rusak') == true
                ? null
                : false;
      case 'getar':
        await Native.vibrate(700);
        if (!mounted) return;
        ok = await _ask('Getar', 'HP-nya getar?');
      case 'kamera_belakang':
      case 'kamera_depan':
        final x = await ImagePicker().pickImage(
            source: ImageSource.camera, preferredCameraDevice: id == 'kamera_depan' ? CameraDevice.front : CameraDevice.rear, imageQuality: 70);
        if (!mounted) return;
        ok = x == null
            ? await _ask('Kamera', 'Kamera ga kebuka / dibatalin. Kamera ${id == 'kamera_depan' ? 'depan' : 'belakang'} rusak?', yes: 'Coba lagi nanti', no: 'Rusak') == true
                ? null
                : false
            : await _ask('Kamera', 'Fotonya fokus, jernih, ga ada bercak / garis / buram di satu sisi?', yes: 'Bagus', no: 'Ada masalah');
      case 'ngecas':
        if (await _ask('Port ngecas', 'Colok charger sekarang, terus klik "Udah".', yes: 'Udah', no: 'Batal') != true) return;
        await Future.delayed(const Duration(seconds: 2));
        final b = Map<String, dynamic>.from((await DiagSource.read())['battery'] as Map? ?? const {});
        if (!mounted) return;
        if (b['plugged'] != null && b['plugged'] != 'none') {
          ok = true;
          toast('Kebaca ngecas (${b['plugged']}${b['currentMa'] != null ? ', arus ${(b['currentMa'] as num).abs().round()} mA' : ''})');
        } else {
          ok = await _ask('Port ngecas', 'HP ga kebaca lagi ngecas. Coba goyang dikit kabelnya — tetep ga ngecas?', yes: 'Sekarang ngecas', no: 'Ga ngecas');
        }
      case 'tombol':
        ok = await _ask('Tombol', 'Pencet volume naik, volume turun, dan power (layar mati-nyala). Semua responsif & ga keras / nyangkut?');
      case 'sinyal':
        ok = await _ask('Sinyal / SIM', 'Masukin SIM lu: sinyal muncul, bisa telepon & data jalan? (cek juga IMEI di *#06# cocok sama kardus)');
      case 'sidik_jari':
        ok = await _ask('Sidik jari / face unlock', 'Daftarin sidik jari / wajah lu di Pengaturan HP, terus coba buka kunci 3×. Lancar?');
    }
    if (ok != null || id == 'mic' || id.startsWith('kamera')) _set(id, ok);
  }

  String get _reportText {
    final r = _rep;
    if (r == null) return '';
    return r.text;
  }

  @override
  Widget build(BuildContext context) {
    final done = _r.values.where((v) => v != null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Cek HP')),
      body: SafeArea(
        top: false,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text('Buat cek HP bekas sebelum beli (pasang satsh di HP itu), atau kesehatan HP sendiri. Hasilnya bisa dianalisa agent.',
              style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _auto,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.health_and_safety_rounded),
            label: Text(_rep == null ? 'Jalanin diagnosa otomatis' : 'Diagnosa ulang'),
          ),
          if (_rep != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.stroke)),
              child: MessageBody(_reportText),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _reportText));
                    toast('Laporan ke-copy');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Salin laporan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.popUntil(context, (r) => r.isFirst);
                    shellTab.value = agentTabIndex;
                    AgentController.i.send('Jalanin diagnosa_hp (logs=crash kalau bisa), terus analisa: layak beli / harga wajar buat kondisi ini / apa aja yang harus dicek atau ditanyain ke penjual.');
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Analisa agent'),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Text('Tes manual', style: TextStyle(color: C.muted, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$done/${manualTests.length}', style: TextStyle(color: C.muted, fontFamily: monoFont, fontSize: 12)),
            if (done > 0)
              TextButton(
                onPressed: () {
                  setState(() => _r = {});
                  saveManual(_r);
                },
                child: const Text('Reset'),
              ),
          ]),
          for (final e in manualTests.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _r[e.key] == null ? Icons.radio_button_unchecked_rounded : (_r[e.key]! ? Icons.check_circle_rounded : Icons.cancel_rounded),
                color: _r[e.key] == null ? C.muted : (_r[e.key]! ? C.green : C.red),
              ),
              title: Text(e.value),
              trailing: const Icon(Icons.play_arrow_rounded),
              onTap: () => _run(e.key),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ tests
class _ScreenTest extends StatefulWidget {
  const _ScreenTest();

  @override
  State<_ScreenTest> createState() => _ScreenTestState();
}

class _ScreenTestState extends State<_ScreenTest> {
  static const colors = [Colors.white, Colors.black, Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF), Color(0xFF808080)];
  int i = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => i == colors.length - 1 ? Navigator.pop(context) : setState(() => i++),
        child: Container(
          color: colors[i],
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 40),
          child: i == 0
              ? Text('Perhatiin tiap warna. Tap buat warna berikutnya (${colors.length} warna).',
                  style: const TextStyle(color: Colors.black54, fontSize: 13, decoration: TextDecoration.none))
              : const SizedBox.shrink(),
        ),
      );
}

class _TouchTest extends StatefulWidget {
  const _TouchTest();

  @override
  State<_TouchTest> createState() => _TouchTestState();
}

class _TouchTestState extends State<_TouchTest> {
  static const cols = 6, rows = 12;
  final _hit = <int>{};
  Size _size = Size.zero;

  void _touch(Offset p) {
    if (_size == Size.zero) return;
    final c = (p.dx / _size.width * cols).floor().clamp(0, cols - 1), r = (p.dy / _size.height * rows).floor().clamp(0, rows - 1);
    if (_hit.add(r * cols + c)) {
      setState(() {});
      if (_hit.length == cols * rows) Future.delayed(const Duration(milliseconds: 300), () => mounted ? Navigator.pop(context, true) : null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('Usap semua kotak (${_hit.length}/${cols * rows})'),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ada yang ga respon', style: TextStyle(color: C.red)))],
        ),
        body: LayoutBuilder(builder: (context, box) {
          _size = box.biggest;
          return Listener(
            onPointerDown: (e) => _touch(e.localPosition),
            onPointerMove: (e) => _touch(e.localPosition),
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              childAspectRatio: (box.maxWidth / cols) / (box.maxHeight / rows),
              children: [
                for (var k = 0; k < cols * rows; k++)
                  Container(margin: const EdgeInsets.all(1), color: _hit.contains(k) ? C.green : const Color(0xFF2A2D38)),
              ],
            ),
          );
        }),
      );
}

class _MultiTouchTest extends StatefulWidget {
  const _MultiTouchTest();

  @override
  State<_MultiTouchTest> createState() => _MultiTouchTestState();
}

class _MultiTouchTestState extends State<_MultiTouchTest> {
  final _down = <int, Offset>{};
  int _max = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text('Tempel ≥ 3 jari bareng (maks: $_max)'), actions: [
          TextButton(onPressed: () => Navigator.pop(context, _max >= 3), child: const Text('Selesai')),
        ]),
        body: Listener(
          onPointerDown: (e) => setState(() {
            _down[e.pointer] = e.localPosition;
            if (_down.length > _max) _max = _down.length;
          }),
          onPointerMove: (e) => setState(() => _down[e.pointer] = e.localPosition),
          onPointerUp: (e) => setState(() => _down.remove(e.pointer)),
          onPointerCancel: (e) => setState(() => _down.remove(e.pointer)),
          child: Stack(children: [
            Positioned.fill(child: Container(color: Colors.black)),
            Center(child: Text('${_down.length}', style: const TextStyle(fontSize: 96, color: Colors.white24, fontWeight: FontWeight.w800))),
            for (final p in _down.values)
              Positioned(
                left: p.dx - 40,
                top: p.dy - 40,
                child: Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: C.violet.withValues(alpha: 0.5))),
              ),
          ]),
        ),
      );
}
