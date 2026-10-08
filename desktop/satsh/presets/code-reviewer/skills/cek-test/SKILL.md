---
name: cek-test
description: Deteksi cara tes sebuah project (npm/pnpm, pytest, go, flutter, cargo), jalanin, dan rangkum hasil + penyebab yang gagal. Pakai sebelum/ sesudah perubahan kode, atau kalau user nanya "tesnya lolos ga".
---
# Cek tes

1. Deteksi dari file (cek memori dulu, mungkin udah dicatat):
   - `package.json` → script `test` (pakai pnpm/yarn kalau ada lockfile-nya). Tambah `CI=1` biar ga mode watch.
   - `pytest.ini`/`pyproject.toml`/`tests/` → `python -m pytest -q -x --maxfail=5`.
   - `go.mod` → `go test ./...` · `pubspec.yaml` → `flutter test` · `Cargo.toml` → `cargo test`.
2. Jalanin dengan batas waktu (ssh_exec timeout cukup, mis. 300 detik). Kalau ada linter/typecheck ringan (`npm run lint`, `tsc --noEmit`) jalanin juga.
3. Rangkum: total lolos/gagal/skip + durasi. Tiap yang gagal: nama tes, pesan error inti (3–5 baris), dan dugaan penyebab setelah lihat kodenya.
4. Bedain: gagal karena kode vs gagal karena lingkungan (DB ga jalan, env kosong, butuh internet). Yang lingkungan jangan dihitung bug.
5. Catat ke memori: perintah tes yang bener buat project ini.
