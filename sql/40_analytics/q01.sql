-- ============================================================
-- q01 — Desa mana di Kota Makassar yang masuk siaga, dan karena angin atau suhu?
-- Pola  : CTE · filter slice kode_kabkot = '73.71' (Kota Makassar)
-- Sumber: v_prakiraan_terbaru (run terbaru per desa × slot — jangan agregasi lintas run)
--
-- Siaga per slot = t_celsius >= 33 ATAU ws_kmh >= 20.
--   Makassar nol hujan di snapshot (tp = 0 di 2844 dari 2874 baris, maks 0.2 mm) → sinyal dari angin & suhu.
--   ws >= 20 km/jam ≈ persentil 99 (awal Beaufort 4); ambang 10.8 ditolak: itu batas m/s,
--   di km/jam membuat 153/153 desa siaga sehingga tidak membedakan apa pun.
--   Ambang hanya ditulis di CTE `ambang` — harus sama dengan docs/kamus_metrik.md.
--
-- Kolom keluaran: kecamatan | desa | slot_siaga | slot_angin | slot_suhu | slot_total | rasio_siaga
--
-- Jawaban yang diharapkan:
--   "67 dari 153 desa di 11 dari 15 kecamatan Kota Makassar punya minimal satu slot siaga (160 slot) —
--    48 desa karena angin, 19 desa karena suhu, tidak ada yang keduanya — dengan Paccerakkang dan Berua
--    (Biringkanaya) teratas, 5 dari 19 slot, semuanya karena suhu ≥ 33 °C."
-- ============================================================

WITH ambang AS (
    SELECT 33.0 AS t_min, 20.0 AS ws_min
),
slot AS (
    SELECT l.nama_kecamatan,
           l.nama_desa,
           f.ws_kmh    >= a.ws_min AS siaga_angin,
           f.t_celsius >= a.t_min  AS siaga_suhu
    FROM v_prakiraan_terbaru f
    JOIN dim_lokasi l ON l.lokasi_sk = f.lokasi_sk   -- lokasi_sk sudah versi SCD2 yang benar saat load
    CROSS JOIN ambang a
    WHERE l.kode_kabkot = '73.71'                    -- slice K2: Kota Makassar
)
SELECT nama_kecamatan                                        AS kecamatan,
       nama_desa                                             AS desa,
       count(*) FILTER (WHERE siaga_angin OR siaga_suhu)     AS slot_siaga,
       count(*) FILTER (WHERE siaga_angin)                   AS slot_angin,
       count(*) FILTER (WHERE siaga_suhu)                    AS slot_suhu,
       count(*)                                              AS slot_total,
       round(count(*) FILTER (WHERE siaga_angin OR siaga_suhu)::numeric / count(*), 2) AS rasio_siaga
FROM slot
GROUP BY nama_kecamatan, nama_desa
HAVING count(*) FILTER (WHERE siaga_angin OR siaga_suhu) > 0
ORDER BY slot_siaga DESC, rasio_siaga DESC, kecamatan, desa;
