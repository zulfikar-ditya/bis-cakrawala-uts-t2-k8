# D7 — Batas lingkup capstone (ditandatangani di Sesi 8)

> Diisi tim **sebelum** menghadap dosen. Dosen hanya mencoret dan tanda tangan.
> Form ini yang jadi acuan rubrik di Sesi 15–16: yang kamu potong tidak dihitung sebagai kekurangan.

Tim: Kelompok 2 (K2)  Topik / slice: T3 Cuaca BMKG — Kota Makassar (`--topic t3 --slice k3`)  Tanggal: 2 Oktober 2026

## AKAN DIBANGUN (maksimal 1 fact table + 1 conformed dimension per RPS butir 8)

| # | Artefak | Ukuran selesai | Deadline |
|---|---|---|---|
| 1 | fact: `fact_prakiraan_cuaca` (grain: 1 desa × 1 slot prakiraan × 1 run analisis BMKG) | Dimuat dari snapshot k3 = 2874 baris; load dijalankan 2× tetap 2874 (upsert idempoten); 6 test di `tests/test_definitions.yml` jalan, hanya test run basi yang gagal sesuai harapan (18 baris) | Sesi 10 |
| 2 | conformed dim: `dim_lokasi` (desa → kecamatan → kabkot → provinsi, SCD Type 2) | 153 desa + 1 anggota Unknown; maks. 1 versi aktif per desa; 0 baris fact jatuh ke `lokasi_sk = -1` | Sesi 10 |
| 3 | metrik di kamus: 1 dari 3 — slot siaga (t ≥ 33 °C atau ws ≥ 20 km/jam) | 12 field terisi di `docs/kamus_metrik.md`; SQL di `sql/50_metrics/` cocok dengan rumus (160 slot · 67 desa · 11 kecamatan pada snapshot); 1 guard test | Sesi 12 |
| 4 | dashboard: 3 tile | Desa siaga (q01) · peringkat kecamatan (q02) · tren siaga harian (q03); tiap angka bisa ditelusuri ke kueri di `sql/40_analytics/` | Sesi 14 |

## TIDAK LAGI DIBANGUN (sebut namanya, jangan "kalau ada waktu")

| # | Yang dicabut | Alasan |
|---|---|---|
| 1 | Metrik & tile siaga hujan (curah hujan `tp`) | Makassar nol hujan di snapshot: `tp = 0` di 2844 dari 2874 baris, maksimum 0.2 mm, tidak ada kode cuaca hujan — metrik ini akan selalu nol. Sinyal siaga diambil dari angin dan suhu. |
| 2 | Metrik akurasi prakiraan (prakiraan vs kenyataan) | Butuh data observasi cuaca aktual BMKG yang tidak ada di `data/raw/`; dataset lain dilarang. Dicatat sebagai batas desain. |
| 3 | Metrik/tile jarak pandang (`vs`, `vs_text`) | Kolom kosong di 2874 dari 2874 baris. |
| 4 | Analisis per jam slot lintas desa | Jam slot tidak seragam antar desa (136 desa jam 0/3/6…, 16 desa jam 2/5/8…, 1 desa jam 1/4/7…); analisis dibatasi per tanggal. |
| 5 | Penarikan ulang otomatis API BMKG (scheduler/refresh) | Repo membekukan snapshot 2026-09-19; tarik ulang hanya manual saat persiapan, lalu commit ulang. |

## Tanda tangan

| Tim | Dosen |
|---|---|
|  |  |
| [tanda tangan] | [tanda tangan] |
