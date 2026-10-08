---
name: audit-server
description: Audit keamanan server Linux via SSH (read-only) — SSH config, firewall, update, port terbuka, user sudo, login gagal, permission file sensitif. Pakai kalau user minta cek keamanan / hardening server.
---
# Audit keamanan server (read-only)

1. Pastiin host-nya (ssh_hosts). Satu server satu kali jalan.
2. Kumpulin data pakai SATU ssh_exec (hemat, ga ngubah apa-apa):
   ```
   echo "== os"; . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME"; uname -r
   echo "== sshd"; sudo -n sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries|x11forwarding|permitemptypasswords) ' || grep -Ei '^\s*(Port|PermitRootLogin|PasswordAuthentication|MaxAuthTries|X11Forwarding)' /etc/ssh/sshd_config
   echo "== firewall"; (sudo -n ufw status 2>/dev/null || sudo -n nft list ruleset 2>/dev/null | head -40 || sudo -n iptables -S 2>/dev/null | head -40) || echo "ga bisa baca (butuh sudo)"
   echo "== fail2ban"; (systemctl is-active fail2ban 2>/dev/null; sudo -n fail2ban-client status 2>/dev/null | head -5) || true
   echo "== ports"; ss -tulpn 2>/dev/null | grep -v '127.0.0.1\|::1' | head -30
   echo "== updates"; (apt list --upgradable 2>/dev/null | grep -c security) 2>/dev/null; systemctl is-enabled unattended-upgrades 2>/dev/null
   echo "== sudoers"; getent group sudo wheel 2>/dev/null
   echo "== users shell"; awk -F: '$7 ~ /(bash|sh|zsh)$/ {print $1}' /etc/passwd
   echo "== auth fail 24h"; (sudo -n journalctl -u ssh -u sshd --since -24h 2>/dev/null | grep -c 'Failed password') || (sudo -n grep -c 'Failed password' /var/log/auth.log 2>/dev/null)
   echo "== perms"; ls -l /etc/shadow ~/.ssh ~/.ssh/authorized_keys 2>/dev/null; find ~ -maxdepth 3 -name '.env*' -perm /044 2>/dev/null | head
   ```
3. Nilai dengan patokan ini:
   - 🔴 PermitRootLogin yes + PasswordAuthentication yes, port DB (3306/5432/6379/27017) kebuka ke publik, `.env` bisa dibaca semua user, firewall mati sama sekali.
   - 🟠 PasswordAuthentication yes (pakai key aja), ga ada fail2ban/rate limit, update security numpuk, user ber-shell yang ga dikenal.
   - 🟡 MaxAuthTries > 4, X11Forwarding yes, unattended-upgrades mati.
4. Laporan: tabel `Level | Temuan | Bukti (potongan output) | Cara beresin (perintah)`. Maks 10 baris, urut dari paling parah.
5. Tawarin perbaikan satu-satu. Sebelum ngubah sshd_config: backup (`sudo cp /etc/ssh/sshd_config{,.bak-$(date +%F)}`), cek `sudo sshd -t`, dan pastiin user punya sesi SSH kedua yang kebuka biar ga kekunci.
6. Simpan ringkasan audit (tanggal + 3 temuan teratas) ke memori.
