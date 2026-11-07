---
name: audit-dependency
description: Cek dependency yang punya celah keamanan atau udah usang (npm audit, pip-audit, govulncheck) dan kasih urutan update yang aman. Pakai kalau user minta cek dependency, sebelum rilis, atau ada notifikasi vulnerability.
---
# Audit dependency

1. Deteksi package manager dari lockfile.
2. Jalanin (read-only):
   - npm: `npm audit --omit=dev --json | head -c 20000` dan `npm outdated`
   - pnpm: `pnpm audit --prod` · yarn: `yarn npm audit` / `yarn audit`
   - Python: `pip-audit -r requirements.txt` (kalau belum ada: tawarin `pipx run pip-audit`)
   - Go: `govulncheck ./...`
3. Saring yang penting: cuma dependency yang beneran kepake di runtime (bukan dev), severity high/critical, dan yang punya versi perbaikan.
4. Laporan tabel `Paket | Versi sekarang → aman | Severity | Dipakai di mana | Breaking?` (cek changelog major version).
5. Usulan update urut dari paling aman (patch) ke paling berisiko (major). Jangan jalanin `npm audit fix --force` — itu bisa naikin major version diem-diem. Abis update: jalanin `cek-test`.
