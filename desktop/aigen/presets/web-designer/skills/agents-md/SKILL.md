---
name: agents-md
description: Bikin AGENTS.md (aturan & alur kerja buat AI agent di sebuah project web). Pakai pas mulai project baru atau user minta rules buat agent.
---
# AGENTS.md — aturan main buat agent

AGENTS.md = tempat aturan/rules, workflow, dan batasan buat AI agent yang ngerjain project ini (kamu sendiri, Codex, Claude Code, Cursor, dll). Isinya **diputusin user**; tanya yang belum jelas, jangan nebak.

## Yang perlu ada
- Tujuan project (1–2 kalimat) + stack (HTML/CSS/JS polos? React? Tailwind?).
- **File wajib dibaca dulu**: DESIGN.md, AGENTS.md, file lain yang penting.
- **Boleh diubah / jangan diubah**: folder/file yang dikunci.
- Alur kerja: rencana → tanya kalau ragu → bikin → preview → Delivery Gate → laporan.
- Batasan: nggak nambah library tanpa izin, nggak bikin aset tanpa izin, aksesibilitas minimal, target perangkat.
- Pointer antislop (biar agent lain ikut aturan yang sama).

## Template
```md
# AGENTS.md — <nama project>

## Tujuan
…  Stack: …

## Baca dulu sebelum ngubah apa pun
1. DESIGN.md (arahan tampilan — wajib diikutin)
2. …

## Aturan
- Boleh ubah: …        Jangan sentuh: …
- Jangan nambah library/framework tanpa izin.
- Tanya dulu sebelum bikin/pakai aset (gambar, ikon, font).
- Semua UI harus jalan di HP (≥360px) dan desktop.

## Alur kerja
1. Rencana singkat → minta oke
2. Kerjain → preview → cek di lebar HP & desktop
3. Delivery Gate antislop → laporan singkat

<!-- antislop:start -->
## antislop
Untuk kerjaan UI, copy, aksesibilitas, layout mobile, atau komentar kode: baca `antislop.md` (inti) lalu skill yang sesuai (antislop-ui, antislop-copywriting, antislop-human, antislop-layoutmobile, antislop-code). Ikutin "Two Usage Modes" dan jalanin Delivery Gate sebelum nyerahin hasil.
<!-- antislop:end -->
```
Kalau project udah punya AGENTS.md: jangan timpa isi lama, cukup tambah blok antislop di akhir (kalau belum ada).
