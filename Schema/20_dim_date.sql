-- =====================================================================
-- dim_date : dimensi tanggal (grain = 1 hari). SCD Type 0 (statis).
-- Role-playing: dipakai 2x oleh fact (tanggal_key & tanggal_analisis_key).
-- Surrogate key cerdas: YYYYMMDD (int) -- konvensi baku untuk dim_date.
-- =====================================================================
CREATE TABLE IF NOT EXISTS dim_date (
    date_key          integer     PRIMARY KEY,          -- surrogate key, mis. 20260919
    tanggal           date        NOT NULL UNIQUE,      -- natural key
    tahun             smallint    NOT NULL,
    kuartal           smallint    NOT NULL CHECK (kuartal BETWEEN 1 AND 4),
    bulan             smallint    NOT NULL CHECK (bulan BETWEEN 1 AND 12),
    nama_bulan        varchar(12) NOT NULL,
    minggu_iso        smallint    NOT NULL,
    hari_dalam_minggu smallint    NOT NULL CHECK (hari_dalam_minggu BETWEEN 1 AND 7), -- 1=Senin
    nama_hari         varchar(8)  NOT NULL,
    is_akhir_pekan    boolean     NOT NULL
);

-- Seed idempotent (aman dijalankan ulang; perluas rentang tiap tahun).
INSERT INTO dim_date
SELECT to_char(d, 'YYYYMMDD')::int,
       d::date,
       extract(year    FROM d)::smallint,
       extract(quarter FROM d)::smallint,
       extract(month   FROM d)::smallint,
       (ARRAY['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus',
              'September','Oktober','November','Desember'])[extract(month FROM d)::int],
       extract(week FROM d)::smallint,
       extract(isodow FROM d)::smallint,
       (ARRAY['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'])[extract(isodow FROM d)::int],
       extract(isodow FROM d) >= 6
FROM generate_series('2026-01-01'::date, '2027-12-31'::date, interval '1 day') AS d
ON CONFLICT (date_key) DO NOTHING;

COMMENT ON TABLE dim_date IS 'Dimensi tanggal (SCD0). Role-playing: tanggal prakiraan (lokal WITA) & tanggal analisis.';
