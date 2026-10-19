# satsh — sat-set SSH

SSH client Android yang "gw banget": terminal, SFTP, tunnel, agent AI di dalam aplikasi, Mode Server (HP lain bisa SSH ke HP ini), plus versi desktop buat Windows 7 / 10 / 11.

Versi app: **2.7.2** · desktop **2.4.9**

## Baru di 2.7.2

- **Tempel perintah SSH** di form host: tombol "Tempel perintah SSH" (baca clipboard) atau paste langsung ke kolom Host. Ngerti `ssh -p 2222 user@host`, `ssh host -p 2222`, `-l user`, `-o Port=/User=`, `ssh://user@host:port`, `user@host:port`, `sshpass -p … ssh …` (password ikut keisi), dan `mosh --ssh="ssh -p 2222" user@host` (nyambung pakai SSH biasa; mosh belum didukung). Perintah setelah host masuk ke auto-run; `-i`, `-J`, `-L/-R/-D` dikasih catatan harus diset di mana
- Desktop 2.4.9: sama — form Host baru + kotak quick connect ngerti perintah `ssh`/`mosh` lengkap

## Baru di 2.7.1 (hardening)

- **Satpam data keluar (agent)**: kalau agent mau buka URL / ngetik teks yang kayaknya bawa rahasia (password tersimpan, private key, token, API key) atau data panjang mencurigakan, wajib minta izin dulu — walau udah "Izinin semua". Di misi/jadwal langsung diblokir. Nutup trik "baca ~/.ssh/id_rsa terus buka evil.com/?k=…" dari halaman web jahat. Desktop juga.
- **Preview HTML dari server di-sandbox** (CSP, origin opak): JavaScript di halaman ga bisa lagi baca file lain di server lewat media server lokal. Media server cuma nerima GET/HEAD dari `127.0.0.1` (anti DNS rebinding), token 128-bit
- **Backup "ikutin semua" dikunci password** (PBKDF2-SHA256 310k + XSalsa20-Poly1305). Backup lama tetep bisa di-restore. Restore ga pernah ngidupin "izinin aksi berisiko otomatis" dan cuma nulis slot rahasia punya satsh
- **Mode Server**: handshake/login wajib kelar dalam 30 dtk, maks 16 koneksi yang belum login (anti banjir koneksi dari Wi-Fi yang sama); QR pairing tanpa sidik jari server ditolak
- Backup otomatis Android (Google Drive & pindah HP) dimatiin — data host, known_hosts & chat agent ga ikut ke cloud; pakai backup satsh
- Laporan error selalu disensor walau "Sensor data sensitif" dimatiin
- Preview web agent pakai token acak; izin "Akses semua file" cuma ditanya sekali per buka app; file sementara buat Share dibersihin otomatis

## Baru di 2.7.0

- **Terminal ga nge-lag / force close lagi pas output panjang**: output server dikumpulin & ditulis per frame (maks 32 KB/frame), stream SSH di-pause kalau antrean > 1 MB
- **SSH 20x lebih kenceng**: cipher AES-CTR / ChaCha20 dipakai duluan; AES-GCM bawaan dartssh2 (pure Dart) cuma ~0,5 MB/s dan bikin UI macet berdetik-detik — ini biang force close di terminal, video & download
- **Video / audio di SFTP**: ga force close lagi buat file gede (tes 60 MB: macet maks <0,1 dtk, dulu 22 dtk); geser slider baru seek pas dilepas
- **Download SFTP beneran jalan**: di-stream langsung ke `Download/satsh` (ga ditampung di RAM), ada tombol Batal, bisa juga dari layar pemutar/preview. Belum kasih izin file → lewat menu Share
- SFTP: folder symlink (mis. `~/storage` di Termux) bisa dibuka; upload ga bilang "beres" kalau gagal
- **Markas dihapus** (tab, tool `markas` & `tanya_agent`, CLI di server, versi desktop). Jadwal "Rapat Markas" lama otomatis kehapus

## Isi repo

| Folder | Apa | Bahasa |
|---|---|---|
| `app/` | Aplikasi Android satsh | Flutter / Dart |
| `satshd/` | SSH server mini yang ditanam di APK buat **Mode Server** | Go |
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
- **Cek HP / diagnosa** (Pengaturan → Cek HP, tool `diagnosa_hp`): perkiraan kapasitas baterai asli vs desain, cycle, spek asli dari sistem, tanda root / bootloader unlock, tes layar/sentuh/multitouch/speaker/mic/getar/kamera/port cas → vonis layak / cek lagi / waspada. Log sistem & `dumpsys battery` setelah izin adb sekali (`adb shell pm grant id.adam.satsh android.permission.READ_LOGS` + `…DUMP`). Desktop: skill `cek-laptop-bekas`.
- **Log error** dengan stack trace + tombol kirim laporan
- Jawaban agent: tombol salin per blok kode & kutipan, plus "Salin semua"
- Mata & tangan: screenshot browser, lihat layar HP, kontrol app lain (Aksesibilitas), kamera, suara
- Tema gelap / terang, backup / restore, keep-alive di background

## Build APK

Butuh: Flutter 3.47+, Android SDK (compileSdk 37, NDK 28.2), Go 1.26+.

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
#  - /tmp/satshd-x86 (dari satshd/build.sh) — juga dipakai media_stress_test (video/download/terminal flood)
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
