---
name: web-build
description: Alur bikin halaman web di satsh — tulis file, preview di browser agent, screenshot & benerin, lalu kirim/deploy. Pakai tiap kali bikin atau ngedit UI web.
---
# Bikin web: tulis → lihat → benerin

1. **Folder project**: di HP `Download/satsh-web/<nama-project>/` (phone_mkdir/phone_write); di laptop (satsh desktop) folder pilihan user (fs_write). Isi minimal: `index.html`, `DESIGN.md`, `AGENTS.md`. CSS/JS boleh inline biar 1 file, atau `style.css`/`main.js`.
   - Font/ikon dari CDN boleh (Google Fonts, dll).
2. **Tulis kode** sesuai DESIGN.md + aturan antislop (antislop-ui, antislop-layoutmobile, antislop-human). Semantic HTML, state hover/focus/active, kontras cukup.
3. **Preview** (di HP): `web_preview` path folder project → kebuka di browser agent. Di laptop: buka file-nya di browser user (open_path) dan minta user cek / screenshot.
4. **Lihat**: `browser_look marks=false` → nilai jujur pakai mata: hierarki, jarak, kontras, ada yang kepotong/tumpuk? Scroll (`browser_scroll`) + look lagi buat bagian bawah. Panel browser kira-kira selebar HP, jadi sekalian ngetes mobile.
5. **Benerin** → `web_preview` lagi → look lagi. Ulang sampai rapi (maks ~3 putaran, jangan muter-muter).
6. **Delivery Gate** antislop → laporan singkat ke user: apa yang dibikin, keputusan desain + alasannya, catatan gate, path file.
7. **Kirim/deploy (kalau diminta)**: phone_share_file buat ngirim, atau sftp_write ke folder web di VPS user (cek memori: path web root, domain) lalu browser_open URL-nya buat cek live.
