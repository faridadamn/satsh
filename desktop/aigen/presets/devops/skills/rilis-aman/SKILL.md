---
name: rilis-aman
description: Rilis/deploy app ke VPS dengan aman — pre-check, catat versi lama, deploy, health check, rollback kalau gagal. Pakai tiap kali user minta deploy/update app di server (lebih ketat dari deploy-git).
---
# Rilis aman

1. **Pre-check** (satu ssh_exec): disk (`df -h /`), RAM, status service (pm2/systemd/docker), `git status --short` + `git log -1 --oneline` di folder project. Disk > 90% atau ada perubahan lokal belum commit → STOP, lapor.
2. **Catat titik balik**: `PREV=$(git rev-parse HEAD)` → sebut ke user & simpan di laporan. Docker: catat image tag yang lagi jalan (`docker compose images`).
3. **Deploy** sesuai stack (cek memori dulu):
   - Node: `git pull --ff-only && npm ci && npm run build --if-present` lalu restart (pm2 reload <app> / systemctl restart <svc>).
   - Docker: `git pull --ff-only && docker compose build && docker compose up -d`.
   - Static: build lalu sync ke web root.
4. **Health check** (tunggu 5–10 detik): status service, `journalctl -u <svc> -n 30` / `pm2 logs --lines 30 --nostream` / `docker compose logs --tail 30`, dan `curl -fsS -o /dev/null -w "%{http_code}" http://127.0.0.1:<port>/<health>`. Harus 2xx/3xx dan ga ada error baru di log.
5. **Gagal → rollback** (setelah kabarin user): `git checkout $PREV` + build + restart (atau balik ke image lama), lalu health check lagi.
6. Laporan: versi lama → versi baru, bukti health check (kode HTTP + 3 baris log), dan perintah rollback kalau nanti butuh.
