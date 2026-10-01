-- ============================================================
-- q02 — Kecamatan mana yang paling luas terdampak siaga?
-- Pola  : CTE + window function RANK() · filter slice kode_kabkot = '73.71'
-- Sumber: v_prakiraan_terbaru (run terbaru per desa × slot)
--
-- Siaga per slot = t_celsius >= 33 ATAU ws_kmh >= 20 (sama dengan q01 & kamus metrik).
-- Peringkat = porsi desa yang punya ≥1 slot siaga; seri dipecah dengan jumlah slot siaga.
-- ws_maks & t_maks memakai MAX — keduanya NON-ADDITIVE, tidak boleh di-SUM.
--
-- Kolom keluaran: peringkat | kecamatan | desa_total | desa_siaga | rasio_desa | slot_siaga | ws_maks | t_maks
--
-- Jawaban yang diharapkan:
--   "Bontoala, Ujung Tanah, Wajo, dan Kepulauan Sangkarrang menempati peringkat 1–4 dengan seluruh desanya
--    siaga (rasio 1.00), sedangkan Mariso, Rappocini, Mamajang, dan Tamalate tidak punya satu pun desa siaga
--    (peringkat 12 bersama)."
-- ============================================================

WITH ambang AS (
    SELECT 33.0 AS t_min, 20.0 AS ws_min
),
desa AS (
    SELECT l.nama_kecamatan,
           l.kode_desa,
           count(*) FILTER (WHERE f.t_celsius >= a.t_min OR f.ws_kmh >= a.ws_min) AS slot_siaga,
           max(f.ws_kmh)    AS ws_maks,
           max(f.t_celsius) AS t_maks
    FROM v_prakiraan_terbaru f
    JOIN dim_lokasi l ON l.lokasi_sk = f.lokasi_sk
    CROSS JOIN ambang a
    WHERE l.kode_kabkot = '73.71'                    -- slice K2: Kota Makassar
    GROUP BY l.nama_kecamatan, l.kode_desa
),
kecamatan AS (
    SELECT nama_kecamatan,
           count(*)                                AS desa_total,
           count(*) FILTER (WHERE slot_siaga > 0)  AS desa_siaga,
           sum(slot_siaga)                         AS slot_siaga,   -- jumlah slot (count) — ADDITIVE
           max(ws_maks)                            AS ws_maks,
           max(t_maks)                             AS t_maks
    FROM desa
    GROUP BY nama_kecamatan
)
SELECT rank() OVER (ORDER BY desa_siaga::numeric / desa_total DESC, slot_siaga DESC) AS peringkat,
       nama_kecamatan                                        AS kecamatan,
       desa_total,
       desa_siaga,
       round(desa_siaga::numeric / desa_total, 2)            AS rasio_desa,
       slot_siaga,
       ws_maks,
       t_maks
FROM kecamatan
ORDER BY peringkat, kecamatan;
