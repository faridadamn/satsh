---
name: nginx-ssl
description: Pasang domain/subdomain ke app di VPS lewat Nginx reverse proxy + HTTPS gratis (certbot), atau benerin config Nginx yang error. Pakai kalau user mau online-in app ke domain atau SSL-nya expired/error.
---
# Nginx + SSL

1. Pre-check: DNS domain udah nunjuk ke IP server (`dig +short <domain>` vs `curl -s ifconfig.me`), app jalan di port lokal (`curl -sI http://127.0.0.1:<port>`), port 80/443 kebuka di firewall.
2. Config `/etc/nginx/sites-available/<domain>` (tunjukin isinya dulu, tulis setelah oke):
   ```
   server {
     listen 80; server_name <domain>;
     client_max_body_size 50m;
     location / {
       proxy_pass http://127.0.0.1:<port>;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "upgrade";
     }
   }
   ```
3. Aktifin: `sudo ln -s ../sites-available/<domain> /etc/nginx/sites-enabled/` → **`sudo nginx -t` wajib lolos** → `sudo systemctl reload nginx`.
4. HTTPS: `sudo certbot --nginx -d <domain> --redirect -m <email> --agree-tos -n` → cek `sudo certbot renew --dry-run`.
5. Verifikasi: `curl -sI https://<domain>` (200/301 + header HSTS kalau ditambah), sisa umur sertifikat.
6. Simpan ke memori: domain → port → folder project.
