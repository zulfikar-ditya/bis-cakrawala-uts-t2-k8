# DESIGN LOAD — T3 Cuaca BMKG (Kota Makassar)

## 1. Diagram star schema

```mermaid
erDiagram
    dim_date       ||--o{ fact_prakiraan_cuaca : "tanggal_key (prakiraan)"
    dim_date       ||--o{ fact_prakiraan_cuaca : "tanggal_analisis_key (role-playing)"
    dim_lokasi     ||--o{ fact_prakiraan_cuaca : "lokasi_key"
    dim_cuaca      ||--o{ fact_prakiraan_cuaca : "cuaca_key"

    dim_date {
        int date_key PK "YYYYMMDD"
        date tanggal UK "natural key"
        smallint tahun
        smallint kuartal
        smallint bulan
        varchar nama_bulan
        smallint minggu_iso
        smallint hari_dalam_minggu
        varchar nama_hari
        boolean is_akhir_pekan
    }
    dim_lokasi {
        bigint lokasi_key PK "surrogate"
        varchar kode_desa NK "natural key (adm4)"
        varchar nama_desa
        varchar kode_kecamatan
        varchar nama_kecamatan
        varchar kode_kabkot
        varchar nama_kabkot
        varchar kode_provinsi
        varchar nama_provinsi
        timestamptz valid_from "SCD2"
        timestamptz valid_to "SCD2"
        boolean is_current "SCD2"
        char row_hash
    }
    dim_cuaca {
        smallint cuaca_key PK "surrogate"
        smallint kode_cuaca NK "SCD1"
        varchar deskripsi_id
        varchar deskripsi_en
    }
    fact_prakiraan_cuaca {
        bigint lokasi_key FK
        int tanggal_key FK "partisi"
        int tanggal_analisis_key FK
        smallint cuaca_key FK
        varchar kode_desa "NK upsert"
        timestamptz waktu_utc "NK upsert"
        timestamptz analisis_utc "NK upsert"
        timestamp waktu_lokal
        smallint jam_lokal
        numeric t_celsius "non-aditif"
        numeric hu_persen "non-aditif"
        numeric tp_mm "aditif waktu"
        numeric tcc_persen "non-aditif"
        numeric ws_kmh "non-aditif"
        smallint wd_deg "non-aditif"
        numeric vs_m "non-aditif"
        smallint jumlah_slot "aditif"
    }
```

Grain fact: **1 desa × 1 slot prakiraan 3-jaman × 1 run analisis BMKG**
(153 desa × ±19 slot = 2.874 baris pada snapshot 2026-09-19).

## 2. Alur

```
CSV snapshot (beku, commit di repo)
  provinsi / kabkot / kecamatan / desa / prakiraan_cuaca
        │  COPY (TRUNCATE + reload tiap batch)
        ▼
  stg_lokasi   stg_prakiraan          (schema stg, tanpa constraint, semua text → cast)
        │            │
        ▼            ▼
  dim_date     dim_cuaca    dim_lokasi        ← urutan: dim dulu
  (seed)       (SCD1)       (SCD2)
        └──────┬─────┴──────────┘
               ▼
      fact_prakiraan_cuaca  (lookup surrogate key → upsert)
```

Urutan eksekusi: `stg → dim_date → dim_cuaca → dim_lokasi → fact`. Satu transaksi per tabel; batch_id = timestamp snapshot (`20260919T152857Z`).

## 3. Strategi per tabel

| Tabel | Strategi | Natural key upsert | Partisi |
|---|---|---|---|
| `stg_lokasi`, `stg_prakiraan` | Truncate & reload (full refresh per batch) | – | – |
| `dim_date` | Seed statis, `INSERT … ON CONFLICT DO NOTHING` | `date_key` / `tanggal` | – |
| `dim_cuaca` | SCD1: upsert timpa | `kode_cuaca` | – |
| `dim_lokasi` | SCD2: tutup versi lama + sisip versi baru | `kode_desa` (+ `is_current`) | – |
| `fact_prakiraan_cuaca` | Upsert idempoten (`ON CONFLICT DO UPDATE`) | `kode_desa, waktu_utc, analisis_utc, tanggal_key` | RANGE bulanan `tanggal_key` |

### 3.1 dim_date
```sql
INSERT INTO dim_date ... FROM generate_series(...) ON CONFLICT (date_key) DO NOTHING;
```
**Menggandakan baris bila:** PK/UNIQUE dilepas lalu seed dijalankan ulang, atau rentang seed pakai `timestamp` sehingga satu hari terhitung dua kali (DST/zona waktu).

### 3.2 dim_cuaca (SCD1)
```sql
INSERT INTO dim_cuaca (kode_cuaca, deskripsi_id, deskripsi_en)
SELECT DISTINCT ON (kode_cuaca) kode_cuaca, weather_desc, weather_desc_en
FROM stg_prakiraan ORDER BY kode_cuaca, weather_desc
ON CONFLICT (kode_cuaca) DO UPDATE
   SET deskripsi_id = EXCLUDED.deskripsi_id,
       deskripsi_en = EXCLUDED.deskripsi_en,
       updated_at   = now();
```
**Menggandakan bila:** `UNIQUE(kode_cuaca)` tidak ada; atau natural key dipilih dari teks (`weather_desc`) sehingga kode 0 & 1 ("Cerah") tergabung/terbelah tidak konsisten; atau staging punya >1 deskripsi per kode dan `DISTINCT ON` dilewatkan (`ON CONFLICT` gagal di baris kembar dalam satu statement).

### 3.3 dim_lokasi (SCD2)
```sql
BEGIN;
-- (1) tutup versi aktif yang atributnya berubah
UPDATE dim_lokasi d
   SET valid_to = :batch_ts, is_current = false
  FROM stg_lokasi s
 WHERE d.kode_desa = s.kode_desa AND d.is_current AND d.row_hash <> s.row_hash;

-- (2) sisipkan versi baru (desa baru ATAU baru saja ditutup)
INSERT INTO dim_lokasi (kode_desa, nama_desa, kode_kecamatan, nama_kecamatan,
                        kode_kabkot, nama_kabkot, kode_provinsi, nama_provinsi,
                        valid_from, valid_to, is_current, row_hash)
SELECT s.kode_desa, s.nama_desa, s.kode_kecamatan, s.nama_kecamatan,
       s.kode_kabkot, s.nama_kabkot, s.kode_provinsi, s.nama_provinsi,
       CASE WHEN EXISTS (SELECT 1 FROM dim_lokasi x WHERE x.kode_desa = s.kode_desa)
            THEN :batch_ts ELSE TIMESTAMPTZ '1970-01-01' END,   -- load awal mencakup seluruh riwayat
       '9999-12-31', true, s.row_hash
  FROM stg_lokasi s
 WHERE NOT EXISTS (SELECT 1 FROM dim_lokasi d WHERE d.kode_desa = s.kode_desa AND d.is_current);
COMMIT;
```
**Menggandakan bila:** langkah (1) dan (2) tidak satu transaksi (gagal di tengah → 2 versi aktif; dicegah `uq_lokasi_current`); `row_hash` memuat kolom volatil (mis. timestamp) atau teks belum di-`trim` sehingga tiap batch dianggap "berubah"; `desa.csv` punya kode ganda; fact di-join ke `dim_lokasi` hanya dengan `kode_desa` tanpa rentang `valid_from/valid_to` (fan-out ×jumlah versi).

### 3.4 fact_prakiraan_cuaca
```sql
INSERT INTO fact_prakiraan_cuaca (lokasi_key, tanggal_key, tanggal_analisis_key, cuaca_key,
       kode_desa, waktu_utc, analisis_utc, waktu_lokal, jam_lokal, arah_angin, arah_angin_tujuan,
       t_celsius, hu_persen, tp_mm, tcc_persen, ws_kmh, wd_deg, vs_m, batch_id)
SELECT l.lokasi_key,
       to_char(s.waktu_lokal::date,'YYYYMMDD')::int,
       to_char(s.analisis_utc::date,'YYYYMMDD')::int,
       COALESCE(c.cuaca_key, 0),
       s.kode_desa, s.waktu_utc, s.analisis_utc, s.waktu_lokal,
       extract(hour FROM s.waktu_lokal), s.wd, s.wd_to,
       s.t, s.hu, s.tp, s.tcc, s.ws, s.wd_deg, s.vs, :batch_id
  FROM stg_prakiraan s
  JOIN dim_lokasi l ON l.kode_desa = s.kode_desa
                   AND s.waktu_utc >= l.valid_from AND s.waktu_utc < l.valid_to
  LEFT JOIN dim_cuaca c ON c.kode_cuaca = s.kode_cuaca
ON CONFLICT (kode_desa, waktu_utc, analisis_utc, tanggal_key) DO UPDATE
   SET lokasi_key = EXCLUDED.lokasi_key, cuaca_key = EXCLUDED.cuaca_key,
       t_celsius = EXCLUDED.t_celsius, hu_persen = EXCLUDED.hu_persen, tp_mm = EXCLUDED.tp_mm,
       tcc_persen = EXCLUDED.tcc_persen, ws_kmh = EXCLUDED.ws_kmh, wd_deg = EXCLUDED.wd_deg,
       vs_m = EXCLUDED.vs_m, batch_id = EXCLUDED.batch_id, loaded_at = now();
```
Kolom partisi: `tanggal_key` (tanggal lokal WITA). Partisi bulanan dibuat sebelum load; sisanya masuk `_default`.

**Menggandakan baris bila:**
1. **Run analisis berbeda.** Slot yang sama muncul lagi di tarikan berikutnya dengan `analisis_utc` baru → sah secara grain, tetapi `SUM(tp_mm)` / `COUNT` ganda. Pakai `v_prakiraan_terbaru` untuk agregasi (snapshot ini sudah punya 2 run: 12:00 dan 00:00).
2. **Natural key memakai `lokasi_key`.** Bila SCD2 menerbitkan versi baru antar-batch, key berubah → `ON CONFLICT` tidak cocok. Karena itu NK memakai `kode_desa`.
3. **`tanggal_key` berubah antar-batch** (mis. dihitung dari UTC di satu batch dan lokal di batch lain) → baris jatuh di partisi lain, konflik tidak terdeteksi.
4. **Zona waktu.** `analysis_date` tanpa zona di sumber; jika di-cast dengan zona berbeda antar-batch, NK berubah.
5. **Join SCD2 tanpa rentang validitas** (lihat 3.3) → fan-out.
6. **Load ulang batch lama tanpa `ON CONFLICT`** (plain `INSERT`) — PK menolak, tetapi bila PK dilepas terjadi duplikasi penuh.

## 4. Catatan kualitas data snapshot
- `vs` dan `vs_text` 100% kosong → `vs_m` NULL semua.
- `weather` 0 dan 1 sama-sama "Cerah"; `tp` hanya {0, 0.1, 0.2}.
- `local_datetime` = UTC+8 (WITA); `analysis_date` diasumsikan UTC.
- Repo membekukan snapshot: jangan tarik ulang saat lab; tarik ulang hanya saat persiapan lalu commit ulang.
