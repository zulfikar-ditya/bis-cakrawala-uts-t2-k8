-- ============================================================
-- q03 — Hari apa siaga memuncak di Kota Makassar, dan bagaimana perubahannya dari hari ke hari?
-- Pola  : CTE + window function LAG() · join role-playing dim_date (tanggal_sk = tanggal lokal WITA)
--         · filter slice kode_kabkot = '73.71'
-- Sumber: v_prakiraan_terbaru (run terbaru per desa × slot)
--
-- Per tanggal, bukan per jam: jam slot tidak seragam antar desa (136 desa di jam 0/3/6/…,
-- 16 desa di jam 2/5/8/…, 1 desa di jam 1/4/7/…), jadi agregasi per jam akan memecah desa.
-- Jendela snapshot 2026-09-19 19:00 → 2026-09-22 06:00 WITA: tanggal 19 dan 22 terpotong
-- (lihat kolom slot_total), hanya 20 dan 21 yang penuh (153 desa × 8 slot = 1224).
--
-- Kolom keluaran: tanggal | nama_hari | desa_total | slot_total | desa_siaga | slot_siaga
--                 | slot_angin | slot_suhu | ws_maks | t_maks | perubahan_desa_siaga
--
-- Jawaban yang diharapkan:
--   "Siaga hanya muncul pada Minggu 20 Sep (65 desa, 76 slot) dan Senin 21 Sep (66 desa, 84 slot; puncak),
--    sedangkan 19 dan 22 Sep — hari yang terpotong jendela prakiraan — nol desa siaga, sehingga
--    perubahan hari terakhir −66 desa."
-- ============================================================

WITH ambang AS (
    SELECT 33.0 AS t_min, 20.0 AS ws_min
),
harian AS (
    SELECT d.full_date                                                    AS tanggal,
           d.nama_hari,
           count(DISTINCT l.kode_desa)                                    AS desa_total,
           count(*)                                                       AS slot_total,
           count(DISTINCT l.kode_desa) FILTER (WHERE f.t_celsius >= a.t_min OR f.ws_kmh >= a.ws_min) AS desa_siaga,
           count(*) FILTER (WHERE f.t_celsius >= a.t_min OR f.ws_kmh >= a.ws_min)                    AS slot_siaga,
           count(*) FILTER (WHERE f.ws_kmh    >= a.ws_min)                AS slot_angin,
           count(*) FILTER (WHERE f.t_celsius >= a.t_min)                 AS slot_suhu,
           max(f.ws_kmh)                                                  AS ws_maks,
           max(f.t_celsius)                                               AS t_maks
    FROM v_prakiraan_terbaru f
    JOIN dim_lokasi l ON l.lokasi_sk = f.lokasi_sk
    JOIN dim_date   d ON d.date_sk   = f.tanggal_sk          -- peran: tanggal prakiraan
    CROSS JOIN ambang a
    WHERE l.kode_kabkot = '73.71'                            -- slice K2: Kota Makassar
    GROUP BY d.full_date, d.nama_hari
)
SELECT tanggal,
       nama_hari,
       desa_total,
       slot_total,
       desa_siaga,
       slot_siaga,
       slot_angin,
       slot_suhu,
       ws_maks,
       t_maks,
       desa_siaga - lag(desa_siaga) OVER (ORDER BY tanggal) AS perubahan_desa_siaga
FROM harian
ORDER BY tanggal;
