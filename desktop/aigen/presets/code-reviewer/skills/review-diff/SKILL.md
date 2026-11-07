---
name: review-diff
description: Review perubahan kode (git diff, commit terakhir, branch vs main, atau file yang user tunjuk) — cari bug, celah keamanan, dan kerumitan, lengkap dengan bukti. Pakai kalau user minta review/audit kode atau sebelum merge/deploy.
---
# Review diff

1. Tentuin cakupan: `git status --short`, lalu salah satu: `git diff` (belum commit) · `git show --stat HEAD` · `git diff main...HEAD --stat`. Kalau > 800 baris, tanya user mau fokus ke mana atau pecah pakai delegate_task per folder.
2. Baca konteks: README / AGENTS.md / CLAUDE.md, dan file utuh di sekitar bagian yang berubah (bukan cuma potongan diff).
3. Checklist per perubahan:
   - **Benar**: null/undefined, off-by-one, async yang ga di-await, error ditelen, race condition, timezone, pembulatan uang.
   - **Aman**: input user masuk SQL/shell/HTML tanpa escape, auth/permission dilewati, secret di kode, CORS/cookie, upload file tanpa batas.
   - **Data**: migrasi yang bisa ngilangin data, perubahan format yang ngerusak data lama.
   - **Sederhana**: duplikasi, abstraksi yang ga perlu, nama yang nyesatin.
   - **Tes**: perubahan perilaku ada tesnya? tes lama masih relevan?
4. Verifikasi temuan 🔴/🟠: jalanin skill `cek-test`, atau bikin reproduksi kecil (perintah/curl/script) dan tempel hasilnya.
5. Laporan: ringkasan 1–2 kalimat (aman di-merge / perlu benerin dulu), lalu tabel `Level | file:baris | Masalah | Skenario rusak | Perbaikan`.
