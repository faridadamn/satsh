---
name: cek-bocor-secret
description: Cari API key, password, token, private key yang bocor di folder project / repo git (termasuk riwayat commit) dan file .env yang salah permission. Pakai sebelum push/deploy atau kalau curiga ada key bocor.
---
# Cek kebocoran secret

1. Tentuin lokasi: folder project di server (ssh_exec) atau di HP/laptop.
2. Scan isi file sekarang (abaikan node_modules, .git, vendor, dist):
   ```
   cd <dir> && grep -rInP --exclude-dir={node_modules,.git,vendor,dist,build} '(sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.|(password|secret|api_?key|token)\s*[:=]\s*["\x27][^"\x27]{6,})' . | cut -c1-160 | head -50
   ```
3. Cek .env & git:
   - `git ls-files | grep -Ei '(^|/)\.env($|\.)|id_rsa|\.pem$|\.p12$'` → file rahasia yang ke-commit = 🔴.
   - `git check-ignore -q .env && echo aman || echo ".env BELUM di .gitignore"`.
   - Riwayat: `git log -p --all -S 'sk-' --oneline | head -20` (ganti kata kunci sesuai jenis key yang ketemu).
4. Laporan: `Level | Jenis | Lokasi (file:baris / commit)` — **nilai secret JANGAN ditulis**, cukup 4 karakter awal + ••••.
5. Kalau ada yang bocor ke repo/publik: urutan beresinnya → (1) **rotate/cabut key-nya dulu** di dashboard penyedia (yang lama anggap udah ketahuan), (2) pindahin ke .env + .gitignore, (3) baru bersihin riwayat (git filter-repo) kalau repo publik. Langkah 3 ngubah riwayat → wajib izin user.
