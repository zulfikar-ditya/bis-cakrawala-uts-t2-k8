-- =====================================================================
-- dim_date : dimensi tanggal (grain = 1 hari). SCD Type 0 (statis).
-- Tabel fisik dibangun oleh sql/10_dim_date.sql (diberikan dosen, conformed) —
-- TIDAK didefinisikan ulang di sini supaya hanya ada satu dim_date di warehouse.
--   date_sk     : surrogate key cerdas YYYYMMDD (integer), mis. 20260920
--   full_date   : natural key
--   rentang     : 2024-01-01 .. 2027-12-31 (mencakup snapshot 2026-09-19 .. 2026-09-22)
--   anggota -1  : 'TIDAK DIKETAHUI' untuk baris tanpa tanggal
--
-- Role-playing: fact_prakiraan_cuaca menunjuk dim_date dua kali —
--   tanggal_sk           -> tanggal lokal slot prakiraan (WITA, dari local_datetime)
--   tanggal_analisis_sk  -> tanggal run analisis BMKG (dari analysis_date)
-- Dua view di bawah memberi nama kolom yang jelas per peran, tanpa menyalin data.
-- =====================================================================

CREATE OR REPLACE VIEW dim_tanggal_prakiraan AS
SELECT date_sk     AS tanggal_sk,
       full_date   AS tanggal_prakiraan,
       tahun, triwulan, bulan, nama_bulan, pekan_iso, hari, hari_ke, nama_hari, akhir_pekan
FROM dim_date;

CREATE OR REPLACE VIEW dim_tanggal_analisis AS
SELECT date_sk     AS tanggal_analisis_sk,
       full_date   AS tanggal_analisis,
       tahun, triwulan, bulan, nama_bulan, pekan_iso, hari, hari_ke, nama_hari, akhir_pekan
FROM dim_date;
