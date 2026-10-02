-- ============================================================
-- m01 — Jumlah desa siaga per hari (Kota Makassar)        kamus: docs/kamus_metrik.md, Metrik 1, v1
-- Sumber: v_prakiraan_terbaru (run terbaru per desa × slot — jangan hitung lintas run)
--
-- Desa siaga pada suatu tanggal = desa yang punya ≥ 1 slot prakiraan (tanggal lokal WITA) dengan
-- t_celsius >= 33 ATAU ws_kmh >= 20. Ambang hanya ditulis di CTE `ambang` — sama dengan q01–q03.
-- Makassar nol hujan di snapshot (tp = 0 di 2844 dari 2874 baris) → sinyal dari angin & suhu, bukan tp_mm.
--
-- Nilai yang diharapkan (snapshot 2026-09-19 19:00 → 2026-09-22 06:00 WITA):
--   19 Sep = 0 · 20 Sep = 65 · 21 Sep = 66 (puncak) · 22 Sep = 0  — dari 153 desa.
--   Seluruh jendela (distinct desa, bukan jumlah harian): 67 desa.
-- ============================================================

WITH ambang AS (
    SELECT 33.0 AS t_min, 20.0 AS ws_min
)
SELECT d.full_date                                                            AS tanggal,
       count(DISTINCT l.kode_desa) FILTER (WHERE f.t_celsius >= a.t_min
                                              OR f.ws_kmh    >= a.ws_min)     AS desa_siaga,
       count(DISTINCT l.kode_desa)                                            AS desa_total
FROM v_prakiraan_terbaru f
JOIN dim_lokasi l ON l.lokasi_sk = f.lokasi_sk
JOIN dim_date   d ON d.date_sk   = f.tanggal_sk           -- peran: tanggal prakiraan (WITA)
CROSS JOIN ambang a
WHERE l.kode_kabkot = '73.71'                             -- filter default: Kota Makassar
GROUP BY d.full_date
ORDER BY d.full_date;
