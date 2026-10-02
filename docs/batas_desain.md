# Batas desain (UTS deliverable 6)

> K2 · T3 Cuaca BMKG · Kota Makassar (slice `k3`). Satu pertanyaan yang **tidak bisa** dijawab star schema
> kami, alasannya, dan apa yang dibutuhkan untuk menjawabnya.

## Pertanyaan yang tidak terjawab

**"Seberapa akurat prakiraan siaga BMKG untuk Kota Makassar — apakah desa yang diprakirakan siaga
(t ≥ 33 °C atau ws ≥ 20 km/jam) benar-benar mengalami suhu/angin setinggi itu?"**

Contoh konkret: q01 menyebut 67 desa siaga (160 slot) dan q03 menyebut puncak Senin 21 Sep (66 desa).
Kami tidak bisa mengatakan berapa dari 160 slot itu yang **terjadi**, berapa yang alarm palsu, dan berapa
kejadian nyata yang terlewat.

## Kenapa tidak terjawab

- `fact_prakiraan_cuaca` hanya berisi **prakiraan**. `t_celsius` dan `ws_kmh` adalah nilai yang
  diramalkan, bukan yang terukur. Di `data/raw/t3_publik/k3/` tidak ada satu pun kolom pengamatan.
- Snapshot dibekukan (2026-09-19 19:00 → 2026-09-22 06:00 WITA) dan BMKG tidak menyediakan arsip
  prakiraan historis lewat API ini, jadi kami juga tidak bisa membangun riwayat untuk dibandingkan.
- Menambah dataset lain dilarang di UTS (hanya `data/raw/`).
- Jadi pertanyaan akurasi bukan soal kueri yang lebih pintar. Datanya memang tidak ada. Itu sebabnya
  metrik akurasi masuk TIDAK LAGI DIBANGUN di `docs/D7_scope_cut.md`.

## Yang dibutuhkan untuk menjawabnya

| # | Kebutuhan | Detail |
|---|---|---|
| 1 | **Data observasi aktual BMKG** | Suhu dan kecepatan angin terukur dari stasiun/AWS BMKG di Makassar dan sekitarnya, minimal per jam, untuk periode yang sama dengan jendela prakiraan |
| 2 | **Pemetaan stasiun → desa** | Tabel jembatan stasiun → `kode_desa` (stasiun terdekat atau per kecamatan). Stasiun jauh lebih sedikit dari 153 desa, jadi akurasi hanya sahih di tingkat kecamatan/kota, bukan per desa |
| 3 | **Fact baru `fact_observasi_cuaca`** | Grain: 1 stasiun × 1 jam pengamatan. Measure `t_obs_celsius`, `ws_obs_kmh` (non-additive). Memakai **conformed dimension** `dim_lokasi` dan `dim_date` yang sudah ada |
| 4 | **Satuan dan zona waktu yang sama** | Angin dalam km/jam (bukan m/s, kesalahan yang sama dengan ambang 10.8). Waktu dalam UTC lalu dipetakan ke `tanggal_sk` WITA, supaya slot 3-jam prakiraan bisa dicocokkan dengan jam pengamatan |
| 5 | **Riwayat beberapa run** | Beberapa snapshot dari waktu ke waktu, supaya akurasi bisa diukur per lead time (prakiraan 12 jam sebelumnya vs 48 jam sebelumnya) |

## Yang sudah disiapkan desain kami

- **Grain menyimpan run analisis** (desa × slot × run, PK memuat `analisis_utc`). Begitu ada beberapa
  run, perbandingan per lead time tinggal di-join, tanpa mengubah fact. Grain alternatif yang ditolak,
  `(adm4, utc_datetime)` dengan run terbaru menimpa, akan membuang histori ini.
- **`dim_lokasi` dan `dim_date` conformed**, jadi fact observasi bisa langsung dipasang di samping
  fact prakiraan (drill-across per kecamatan × tanggal).
- **Ambang siaga terkunci di kamus** (`docs/kamus_metrik.md`, v1: 33 °C / 20 km/jam). Akurasi bisa
  dihitung dengan ambang yang sama di kedua sisi: slot siaga prakiraan vs slot siaga observasi →
  hit, alarm palsu, dan kejadian terlewat.
