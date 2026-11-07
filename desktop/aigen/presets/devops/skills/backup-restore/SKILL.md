---
name: backup-restore
description: Bikin backup DB (Postgres/MySQL/SQLite) dan folder penting di VPS, rotasi file lama, jadwalin, dan UJI restore. Pakai kalau user minta backup, nanya backupnya aman ga, atau mau restore.
---
# Backup & restore

1. Inventaris (cek memori dulu): DB apa (docker atau native), folder upload/data, ukuran (`du -sh`), sisa disk.
2. Lokasi backup: `~/backups/<app>/` (permission 700). Nama file: `<app>-<db|files>-$(date +%F-%H%M).<ext>`.
3. Perintah backup:
   - Postgres: `pg_dump -Fc -d <db> > file.dump` (docker: `docker exec <ctr> pg_dump -U <user> -Fc <db> > file.dump`).
   - MySQL: `mysqldump --single-transaction --routines <db> | gzip > file.sql.gz` (password lewat ~/.my.cnf, JANGAN di command line).
   - SQLite: `sqlite3 <file> ".backup 'out.db'"`.
   - Folder: `tar czf files.tgz -C <parent> <folder>`.
4. Verifikasi file: ukuran > 0, `gzip -t` / `pg_restore -l file.dump | head` sukses.
5. Rotasi: simpan 7 harian + 4 mingguan; hapus yang lebih lama pakai `find ~/backups/<app> -mtime +30 -name '*.gz' -delete` (tunjukin dulu daftar yang bakal kehapus).
6. Jadwal: tawarin crontab (mis. `15 2 * * *`) — pasang setelah user oke. Saranin salinan off-server (rclone ke Google Drive/S3) karena backup di server yang sama ikut ilang kalau servernya ilang.
7. **Uji restore** minimal sekali: restore ke DB/folder sementara (`createdb <db>_restoretest` → `pg_restore -d ...`), cek jumlah baris tabel utama, lalu hapus DB tes. Backup yang belum pernah dites = belum ada backup.
