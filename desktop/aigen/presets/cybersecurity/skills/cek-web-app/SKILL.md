---
name: cek-web-app
description: Cek keamanan dasar web app/domain milik user dari luar — HTTPS & masa berlaku sertifikat, security header, file sensitif yang kebuka (.env, .git), CORS, info server yang bocor. Pakai kalau user minta cek keamanan website/API-nya.
---
# Cek keamanan web app (dari luar, pasif)

Cuma buat domain milik user. Semua request GET/HEAD biasa, ga ada serangan.

1. Header & redirect: `curl -sSIL --max-time 15 https://<domain>` (lewat ssh_exec di server user, atau http_get).
   - Wajib ada: `Strict-Transport-Security`, `Content-Security-Policy` (atau minimal `X-Frame-Options`), `X-Content-Type-Options: nosniff`, `Referrer-Policy`.
   - `http://` harus redirect ke `https://`.
   - Header `Server`/`X-Powered-By` yang nyebut versi → 🔵 bocor info.
2. TLS: `echo | openssl s_client -servername <domain> -connect <domain>:443 2>/dev/null | openssl x509 -noout -dates -issuer` → sisa < 14 hari = 🟠.
3. File sensitif yang ga boleh kebuka (cek status code aja, jangan simpan isinya):
   `for p in .env .git/HEAD .git/config backup.zip db.sql wp-config.php.bak .DS_Store phpinfo.php; do printf "%s " $p; curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 https://<domain>/$p; done`
   → 200 di `.env`/`.git`/`.sql` = 🔴.
4. CORS API: `curl -sI -H "Origin: https://contoh-jahat.test" https://<domain>/api/...` → `Access-Control-Allow-Origin: *` bareng `Allow-Credentials: true` = 🔴; `*` di API yang butuh login = 🟠.
5. Laporan tabel `Level | Temuan | Bukti | Cara beresin` + contoh konfigurasi nginx/vercel/cloudflare yang pas buat stack user (cek memori).
