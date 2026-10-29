# satsh — sat-set SSH

SSH client Android yang "gw banget": terminal, SFTP, tunnel, agent AI di dalam aplikasi, Mode Server (HP lain bisa SSH ke HP ini), plus versi desktop buat Windows 7 / 10 / 11.

Versi app: **2.6.0** · desktop **2.4.6**

## Isi repo

| Folder | Apa | Bahasa |
|---|---|---|
| `app/` | Aplikasi Android satsh | Flutter / Dart |
| `satshd/` | SSH server mini yang ditanam di APK buat **Mode Server** | Go |
| `markas/` | **Markas**: workspace bareng Adam & semua agent (CLI kecil + SQLite di server, skill Hermes) | Python 3.6+ / sh |
| `desktop/` | satsh desktop buat Windows 7/10/11 (agent + SSH + browser agen + remote dari HP) | Python 3.8–3.14 |

## Fitur app

- **Host & terminal**: password / SSH key (+ bikin key ed25519), auto-run pas masuk, host key TOFU, "Nyambung lewat" (jump host)
- **SFTP**: file manager, edit file, buka HTML / Markdown / gambar / video / audio
- **Snippet**: tombol perintah cepat di atas keyboard
- **Tunnel**: port forwarding (localhost HP → port di server)
- **Mode Server**: HP jadi SSH server (`satshd`), pairing pakai QR sekali pakai, relay lewat VPS (reverse tunnel) biar bisa diakses dari jaringan mana aja
- **Agent**: tool HP / SSH / SFTP / Supabase / HTTP / **browser riset** (bisa dipantau live, tanpa login)
  - Otak ala Hermes: soul, memori, skill, sesi, todo, sub-agent, jadwal (cron), review, kompresi konteks
  - Provider berurutan + fallback: OpenAI-compatible, Gemini (API key), ChatGPT (login Codex)
  - **Misi (otonom)**: kasih tujuan besar (mis. "bikin SaaS sampai profit"), agent kerja sendiri iterasi demi iterasi selama HP nyala — analisa kerjaan sebelumnya → kerja → jurnal → lapor (notifikasi). Yang butuh lu jadi pertanyaan yang ga nge-block; provider error → tidur & bangun sendiri pas provider normal; agent bisa tidur sendiri kalau lagi nunggu; batas langkah/iterasi per hari bisa diatur (default bebas); HP mati = misi berhenti, nyala lagi tinggal tap Lanjut
  - **Batas langkah per pesan** bisa diatur (50 / 150 / 400 / tanpa batas, default 150); tombol stop selalu jalan, dan agent berhenti sendiri kalau muter-muter (aksi sama 4x berturut-turut atau error terus 5 langkah). Kalau berhenti, tinggal tap **Lanjut**
  - Agent bisa ganti model sendiri per chat (`model_switch`) dan bikin gambar pakai model gambar (`image_generate`)
  - **Agent eksternal**: ngobrol sama `agy` (Antigravity CLI) di Termux/proot lewat SSH; soul-nya tetap di sana
- **Profil agent**: beberapa persona, masing-masing soul/memori/skill/model/tools sendiri; profil user dipakai bareng
- **Agent preset bawaan**: 🎨 Web Designer, 🛡️ Cyber Security (audit & hardening server, secret bocor, keamanan web, triase insiden), 🚀 DevOps (rilis aman + rollback, backup & restore, Docker, Nginx + SSL), 🔍 Code Reviewer (review diff dengan bukti, tes, audit dependency)
- **Cara kerja agent baru**: tiap agent yang di-summon dapet blok "Cara kerja" — rencana dulu (todo), bukti sebelum bilang beres, telusuri bug sendiri, catat pelajaran tiap dikoreksi
- **Skill bawaan dikunci**: skill default & skill preset cuma bisa diubah user (agent read-only); tombol "Kembaliin default" per skill / semua
- **Push skill ke Hermes**: kirim skill lewat SSH ke `~/.hermes/skills/satsh/<nama>/` (status sinkron/beda/belum ada, tarik balik skill buatan Hermes); tool agent `skill_push`
- **Sensor data sensitif**: API key, password, token, private key & IP disamarin di langkah tool, status, dialog izin, dan laporan error (bisa dimatiin di Pengaturan)
- **Zip otak agent** (`satsh-agent.json` + `profiles/<id>/…`): format sama di HP & desktop, bisa pindah bolak-balik
- **Preset 🎨 Web Designer**: agent kedua buat bikin UI web pakai [antislop](https://github.com/miqdadbadjuber/anti-slop) (MIT, © Miqdad Badjuber) + AGENTS.md + DESIGN.md + gambar referensi; preview & screenshot hasilnya sendiri (`web_preview`)
- **Bikin agent dari gambar**: kirim screenshot thread/postingan/repo → agent nyusun profil baru (tool `agent_profile`)
- **Markas** (tab baru): workspace bareng buat lu & semua agent — satsh, 🎨 web-designer, Hermes, agy, Muse. Target + PIC + progress, log pencapaian, obrolan. Data di server lu sendiri (`~/.markas/markas.db`), diakses lewat SSH, ga buka port.
  - Tool agent `markas` (brief / target / log / say / inbox) dan `tanya_agent` (Hermes lewat `hermes -z` di server, agy lewat agent eksternal, Muse lewat kontrol HP di aplikasinya)
  - **Rapat**: satsh nanya PIC tiap target, nyatet hasilnya, kirim rangkuman ke lu; bisa dijadwal harian
  - Hermes dapet skill `markas` otomatis (`~/.hermes/skills/markas/SKILL.md`), jadi dari CLI / Telegram dia bisa lapor sendiri
- **Cek HP / diagnosa** (Pengaturan → Cek HP, tool `diagnosa_hp`): perkiraan kapasitas baterai asli vs desain, cycle, spek asli dari sistem, tanda root / bootloader unlock, tes layar/sentuh/multitouch/speaker/mic/getar/kamera/port cas → vonis layak / cek lagi / waspada. Log sistem & `dumpsys battery` setelah izin adb sekali (`adb shell pm grant id.adam.satsh android.permission.READ_LOGS` + `…DUMP`). Desktop: skill `cek-laptop-bekas`.
- **Log error** dengan stack trace + tombol kirim laporan
- Jawaban agent: tombol salin per blok kode & kutipan, plus "Salin semua"
- Mata & tangan: screenshot browser, lihat layar HP, kontrol app lain (Aksesibilitas), kamera, suara
- Tema gelap / terang, backup / restore, keep-alive di background

## Build APK

Butuh: Flutter 3.47+, Android SDK (compileSdk 37), Go 1.24+.

```bash
# 1. Build server Mode Server → app/android/app/src/main/jniLibs/*/libsatshd.so
./satshd/build.sh

# 2. Build APK
cd app
flutter pub get
flutter build apk --release --split-per-abi
# hasil: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> APK release ditandatangani pakai `android/key.properties` + `android/app/satsh-release.jks` (ga di-commit). Tanpa itu jatuh ke debug key.

## Test

```bash
cd app
# Bisa jalan di mana aja:
flutter test test/ui_golden_test.dart test/browser_test.dart test/providers_test.dart test/brain_test.dart

# Test integrasi butuh fixture lokal:
#  - OpenSSH di 127.0.0.1:2222, user `tester` / password `rahasia123`
#  - key ber-passphrase `pp123` di /tmp/claude-0/testkey (public key-nya di authorized_keys tester)
#  - HTTP server di 127.0.0.1:9876 (python3 -m http.server 9876)
#  - /tmp/satshd-x86 (dari satshd/build.sh)
#  - /usr/local/bin/agy + proot-distro palsu buat external_agent_test
flutter test -j 1
```

Golden screenshot ada di `app/test/goldens/`. Kalau sengaja ubah UI: `flutter test test/ui_golden_test.dart --update-goldens`.

## satsh desktop (Windows 7 / 10 / 11)

```bash
# Download wheel offline buat Python 3.8–3.14, 32 & 64-bit (sekali, dari komputer yang ada internet)
./desktop/tools/download_wheels.sh
```

Terus copy folder `desktop/` ke laptop, jalanin `install.bat`, lalu `satsh.bat`. Panduan lengkap ada di `desktop/PANDUAN.txt`.

## Struktur penting (app)

```
lib/
  main.dart, theme.dart, widgets.dart, store.dart, models.dart
  ssh_manager.dart     # koneksi, terminal, sftp, tunnel, jump host
  phone_server.dart    # Mode Server, pairing QR, relay VPS
  browser.dart         # browser riset agent
  keepalive.dart, keygen.dart, media_server.dart
  agent/               # agent loop, brain, providers, tools, external (agy)
  pages/               # semua layar
android/app/src/main/kotlin/…/MainActivity.kt   # channel nativeLibDir
```
