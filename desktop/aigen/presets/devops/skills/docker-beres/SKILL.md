---
name: docker-beres
description: Diagnosa & beresin masalah Docker di server — container mati/restart terus, port bentrok, disk penuh gara-gara image/log, cek resource. Pakai kalau user bilang app docker-nya down, error, atau disk penuh.
---
# Docker beres

1. Gambaran (satu ssh_exec):
   ```
   docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | head -30
   docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' | head -20
   docker system df; df -h / | tail -1
   ```
2. Container `Exited`/`Restarting`: `docker logs --tail 80 <ctr>` + `docker inspect -f '{{.State.ExitCode}} {{.State.OOMKilled}} {{.State.Error}}' <ctr>`.
   - OOMKilled true → kurang RAM: kasih limit/naikin RAM/tambah swap.
   - Exit 1 + error config → cek env/.env & volume mount.
   - Port already allocated → `ss -tlpn | grep <port>` cari yang make.
3. Disk penuh: lihat `docker system df -v`. Urutan bersih-bersih yang AMAN (tunjukin dulu perkiraan yang kebebas): `docker image prune` (dangling) → `docker builder prune` → log raksasa (`truncate -s 0 $(docker inspect -f '{{.LogPath}}' <ctr>)`) + saranin `log-opts max-size`. **`docker system prune -a` dan `volume prune` cuma kalau user izin eksplisit** (volume = data!).
4. Perbaikan → `docker compose up -d <svc>` → cek `docker ps` + log 20 baris + curl health.
5. Laporan: penyebab, perbaikan, bukti jalan, dan pencegahan (restart policy, limit memori, log rotation).
