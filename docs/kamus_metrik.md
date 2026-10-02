# D6 — Kamus metrik (12 field)

> K2 · T3 Cuaca BMKG · Kota Makassar (slice `k3`). UTS item 5 = satu metrik lengkap.
> SQL yang bisa dijalankan: `sql/50_metrics/m01_desa_siaga_harian.sql` — rumus di bawah harus identik dengannya.

## Metrik 1 — Jumlah desa siaga per hari

| # | Field | Isi |
|---|---|---|
| 1 | Nama metrik | `desa_siaga_harian` — Jumlah desa siaga angin/suhu per hari |
| 2 | Definisi (satu kalimat, tanpa jargon) | Banyaknya desa/kelurahan di Kota Makassar yang pada tanggal itu diprakirakan BMKG mengalami setidaknya satu periode 3-jam dengan suhu 33 °C atau lebih, atau angin 20 km/jam atau lebih. |
| 3 | Rumus (SQL-nya, bukan bahasa manusia) | `SELECT d.full_date, count(DISTINCT l.kode_desa) FILTER (WHERE f.t_celsius >= 33 OR f.ws_kmh >= 20) FROM v_prakiraan_terbaru f JOIN dim_lokasi l ON l.lokasi_sk = f.lokasi_sk JOIN dim_date d ON d.date_sk = f.tanggal_sk WHERE l.kode_kabkot = '73.71' GROUP BY d.full_date` (lengkap: `sql/50_metrics/m01_desa_siaga_harian.sql`) |
| 4 | Grain | 1 nilai per tanggal lokal (WITA) per wilayah yang dipotong; dihitung dari fact berbutir desa × slot 3-jam × run analisis, lewat run terbaru saja |
| 5 | Tabel sumber | `v_prakiraan_terbaru` (di atas `fact_prakiraan_cuaca`), `dim_lokasi` (SCD2, `lokasi_sk` versi saat load), `dim_date` (peran tanggal prakiraan, `tanggal_sk`) |
| 6 | Owner (jabatan bernama) | Kepala Bidang Kedaruratan dan Logistik, BPBD Kota Makassar (penentu ambang); data steward: pemilik bagian Kualitas & Metrik Kelompok 2 |
| 7 | Time basis | Per hari kalender lokal WITA (UTC+8), dari `local_datetime` → `tanggal_sk`; bukan tanggal UTC dan bukan tanggal run analisis |
| 8 | Satuan | Desa (bilangan bulat, 0–153); ambang dalam °C dan km/jam |
| 9 | Dimensi yang boleh dipotong | Tanggal prakiraan (hari, nama hari), lokasi (kecamatan, kab/kota, provinsi), penyebab (angin vs suhu). Jangan dipotong per jam: jam slot tidak seragam antar desa (136 desa di jam 0/3/6…, 16 di 2/5/8…, 1 di 1/4/7…) |
| 10 | Filter default | `kode_kabkot = '73.71'` (Kota Makassar), run terbaru per desa × slot (`v_prakiraan_terbaru`) |
| 11 | Arti nilai kosong | 0 = ada prakiraan untuk tanggal itu tetapi tidak ada desa siaga (19 dan 22 Sep). Tanggal tanpa baris prakiraan sama sekali tidak muncul — itu "tidak ada data", bukan 0 |
| 12 | Versi | v1, berlaku 1 Okt 2026 — ambang t ≥ 33 °C atau ws ≥ 20 km/jam. Mengubah ambang = v2, bukan edit diam-diam |

**Nilai di snapshot ini** (2026-09-19 19:00 → 2026-09-22 06:00 WITA, 153 desa):
19 Sep = 0 · 20 Sep = 65 · 21 Sep = **66** (puncak) · 22 Sep = 0. Satu jendela penuh (distinct desa) = 67 desa
di 11 dari 15 kecamatan, 160 slot — 48 desa karena angin (98 slot), 19 desa karena suhu (62 slot), tidak ada yang keduanya.
Angka harian **tidak boleh dijumlah** jadi angka jendela (65 + 66 ≠ 67): satu desa bisa siaga di dua hari — metrik ini non-additive lintas waktu.

**Kenapa angin & suhu, bukan hujan:** Makassar nol hujan di snapshot — `tp = 0` di 2844 dari 2874 baris (maks 0.2 mm),
kode cuaca hanya 0/1/2/3 (tidak ada kode hujan). Ambang ws ≥ 20 km/jam ≈ persentil 99 (98 slot). Ambang 10.8 ditolak:
itu batas m/s; di km/jam ia membuat 153/153 desa siaga sehingga metrik tidak membedakan apa pun.

### Cara metrik ini di-gaming
Membuang run lama dengan dalih "pakai run terbaru saja": filter `WHERE analisis_utc = (SELECT max(analisis_utc) ...)`
secara global, bukan per desa × slot. Di snapshot ini 1 desa hanya punya run 2026-09-19T00 (18 baris), jadi desa itu
hilang dari pembilang **dan** penyebut — dasbor menampilkan "semua desa memakai prakiraan terbaru" dan, kalau desa itu
sedang siaga, angka desa siaga turun tanpa cuacanya membaik. (Gaming kedua — menaikkan ambang ws ke 25 agar siaga
"turun" — dikunci oleh field 12: ambang adalah bagian definisi v1, perubahannya wajib jadi v2.)

### Guard test-nya
`desa_run_terbaru_basi` di `tests/test_definitions.yml` (warning, `expected: fail`, `perkiraan_baris: 18`):
menghitung baris milik desa yang run terbarunya lebih tua dari run terbaru snapshot. Selama run lama tetap disimpan,
hasilnya 18. Kalau seseorang membuang run lama, hasilnya tiba-tiba **0** pada snapshot yang sama → test menjadi
"TIDAK sesuai harapan" dan ketahuan. Pasangannya: `desa_total` di `m01` harus tetap 153 per hari penuh — kurang dari itu
berarti ada desa yang terbuang.
