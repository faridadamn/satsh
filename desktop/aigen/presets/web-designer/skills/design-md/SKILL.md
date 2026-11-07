---
name: design-md
description: Bikin atau rapihin DESIGN.md (arahan visual project) dari jawaban user atau gambar referensi. Pakai sebelum bikin UI kalau project belum punya DESIGN.md.
---
# DESIGN.md — arahan tampilan

DESIGN.md = "selera" project dalam bentuk tertulis, biar output konsisten dan nggak balik ke selera default AI. User = penulis, kamu = juru tulis/perapih. **Jangan ngarang isi** (antislop: never invent example content for DESIGN.md).

## Sumber arahan (pilih yang ada)
1. **Gambar referensi** (paling enak): user kirim screenshot Pinterest/Dribbble/web/app yang dia suka.
   - Lihat tiap gambar. Catat yang KELIHATAN: palet (perkiraan hex), kontras terang/gelap, jenis font (serif/sans/mono, tebal/tipis, kapital?), ukuran relatif judul vs badan, radius sudut, kepadatan (lega/padat), gaya ilustrasi/foto, ritme grid, tombol (bentuk, isi/outline), motion yang tersirat.
   - Bedain "yang sama di semua referensi" (= arah) vs "cuma di satu gambar" (= opsional).
   - Tunjukin ringkasan ke user, minta koreksi, baru tulis.
2. **Tanya jawab singkat** (maks 6 pertanyaan sekali kirim): produk & audiens; 3 kata kepribadian; warna wajib/terlarang; font (punya brand?); mood referensi; yang DIBENCI.
3. **Generator** (lihat skill `web-resources`): designmd.co, context.dev, design.dev — hasilnya tetap ditinjau user.

## Template
```md
# DESIGN.md — <nama project>

## Identitas
- Produk: …            - Audiens: …
- Kepribadian (3 kata): … · … · …

## Warna
- Latar: #…   Permukaan: #…   Teks: #…   Teks redup: #…
- Aksen utama: #… (dipakai buat: CTA, link aktif)   Aksen kedua (opsional): #…
- Larangan warna: … (mis. gradien ungu-biru, neon)

## Tipografi
- Judul: <font>, berat …, huruf …   Badan: <font>, …   Mono (opsional): …
- Skala: H1 …px / H2 …px / badan …px / kecil …px, line-height …

## Bentuk & ukuran
- Radius: kecil …px (input), sedang …px (kartu), tombol …px
- Tombol: tinggi …px, padding …, isi vs outline: …
- Spasi dasar: …px (kelipatan)

## Komponen & pola
- Navbar: …   Kartu: …   Ikon: <set>, ukuran …
- Motion: … (durasi, easing, kapan)

## DILARANG
- (mis. badge "New"/"AI", emoji di heading, glassmorphism di semua elemen, hero gradien orb, teks "Unlock/Elevate/Seamless")

## Referensi
- <gambar/link> — yang diambil: …
```
Simpan di root project (sebelah index.html). Kalau project di server, tulis lewat sftp_write.
