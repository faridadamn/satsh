---
name: insiden-login
description: Triase kalau curiga server dibobol / ada login aneh — siapa yang login, dari mana, proses & cron mencurigakan, authorized_keys baru — lalu langkah karantina. Pakai kalau user bilang "server gw kayaknya dibobol", ada login asing, atau CPU tiba-tiba penuh.
---
# Triase insiden login

**Tenang dulu, kumpulin bukti, jangan langsung hapus apa pun** (bukti bisa ilang).

1. Siapa & dari mana (read-only):
   ```
   who; echo "== last"; last -n 20 -a | head -25; echo "== gagal"; sudo -n lastb -n 10 2>/dev/null | head
   echo "== accepted 7d"; sudo -n journalctl -u ssh -u sshd --since -7d 2>/dev/null | grep -E 'Accepted' | tail -20
   echo "== keys"; for u in $(awk -F: '$7 ~ /sh$/ {print $6}' /etc/passwd); do ls -la --time-style=+%F $u/.ssh/authorized_keys 2>/dev/null; done
   echo "== proses top"; ps -eo pid,user,%cpu,%mem,lstart,cmd --sort=-%cpu | head -12
   echo "== cron"; sudo -n ls -la /etc/cron.* /var/spool/cron/crontabs 2>/dev/null | head -40; crontab -l 2>/dev/null
   echo "== koneksi keluar"; ss -tpn state established 2>/dev/null | head -20
   echo "== file baru /tmp"; find /tmp /var/tmp /dev/shm -type f -mtime -3 2>/dev/null | head -20
   ```
2. Tanda bahaya: login sukses dari IP/negara yang user ga kenal, key di authorized_keys yang ga user kenali, proses nama aneh dengan CPU tinggi (miner), cron yang download script (`curl|sh`), binary di /tmp atau /dev/shm.
3. Laporan kronologi singkat (jam → kejadian → bukti). Tandain mana yang PASTI vs DUGAAN.
4. Usulan karantina (eksekusi satu-satu setelah user "oke"):
   - Snapshot/backup dulu kalau provider VPS punya fitur snapshot.
   - Cabut key asing dari authorized_keys (simpan salinannya dulu), ganti password user, matiin PasswordAuthentication.
   - Blok IP penyerang di firewall, kill proses jahat, hapus cron jahat (simpan salinan buat bukti).
   - Rotate semua secret yang ada di server itu (DB, API key di .env).
5. Kalau udah parah (root kebobol): saranin bangun ulang server dari nol + restore data dari backup bersih — jangan percaya server lama.
