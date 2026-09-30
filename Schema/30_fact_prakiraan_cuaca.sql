-- =====================================================================
-- fact_prakiraan_cuaca
-- GRAIN : 1 desa x 1 slot prakiraan 3-jaman (utc_datetime) x 1 run analisis BMKG.
-- Tipe  : periodic snapshot (prakiraan; BMKG tidak menyediakan arsip historis).
-- Partisi: RANGE bulanan pada tanggal_key (tanggal lokal WITA, YYYYMMDD).
--
-- LABEL ADITIVITAS
--   t_celsius        NON-ADITIF  -> agregasi AVG / MIN / MAX
--   hu_persen        NON-ADITIF  -> AVG / MIN / MAX
--   tp_mm            ADITIF terhadap waktu (total curah hujan per periode);
--                    SEMI-ADITIF lintas lokasi (jangan SUM lintas desa, pakai AVG)
--   tcc_persen       NON-ADITIF  -> AVG
--   ws_kmh           NON-ADITIF  -> AVG / MAX
--   wd_deg           NON-ADITIF  (sudut/sirkular) -> jangan di-AVG biasa
--   vs_m             NON-ADITIF  -> AVG / MIN (100% NULL di snapshot ini)
--   jumlah_slot      ADITIF      -> SUM (=1 per baris, untuk COUNT tanpa NULL)
-- =====================================================================
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca (
    -- ---- foreign key ke dimensi (surrogate key) ----
    lokasi_key           bigint   NOT NULL REFERENCES dim_lokasi (lokasi_key),
    tanggal_key          integer  NOT NULL REFERENCES dim_date (date_key),  -- tanggal lokal slot
    tanggal_analisis_key integer  NOT NULL REFERENCES dim_date (date_key),  -- role-playing
    cuaca_key            smallint NOT NULL REFERENCES dim_cuaca (cuaca_key),

    -- ---- degenerate / natural key (untuk upsert idempoten) ----
    kode_desa            varchar(16)  NOT NULL,
    waktu_utc            timestamptz  NOT NULL,   -- utc_datetime
    analisis_utc         timestamptz  NOT NULL,   -- analysis_date (asumsi UTC)
    waktu_lokal          timestamp    NOT NULL,   -- local_datetime (WITA, UTC+8)
    jam_lokal            smallint     NOT NULL CHECK (jam_lokal BETWEEN 0 AND 23),
    arah_angin           varchar(3),              -- wd (N, NE, ...), from -> wd_to
    arah_angin_tujuan    varchar(3),              -- wd_to

    -- ---- measures ----
    t_celsius            numeric(4,1),            -- NON-ADITIF
    hu_persen            numeric(5,2),            -- NON-ADITIF
    tp_mm                numeric(6,2),            -- ADITIF (waktu) / SEMI-ADITIF (lokasi)
    tcc_persen           numeric(5,2),            -- NON-ADITIF
    ws_kmh               numeric(6,2),            -- NON-ADITIF
    wd_deg               smallint,                -- NON-ADITIF (sirkular)
    vs_m                 numeric(8,1),            -- NON-ADITIF
    jumlah_slot          smallint NOT NULL DEFAULT 1,  -- ADITIF

    -- ---- audit ----
    batch_id             varchar(32)  NOT NULL,
    loaded_at            timestamptz  NOT NULL DEFAULT now(),

    -- natural key upsert; wajib memuat kolom partisi (tanggal_key)
    CONSTRAINT pk_fact_prakiraan
        PRIMARY KEY (kode_desa, waktu_utc, analisis_utc, tanggal_key)
) PARTITION BY RANGE (tanggal_key);

-- Partisi bulanan (tambahkan bulan baru saat persiapan tarik snapshot).
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_09 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20260901) TO (20261001);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_10 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20261001) TO (20261101);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_11 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20261101) TO (20261201);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_12 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20261201) TO (20270101);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_default PARTITION OF fact_prakiraan_cuaca DEFAULT;

CREATE INDEX IF NOT EXISTS ix_fact_lokasi ON fact_prakiraan_cuaca (lokasi_key, tanggal_key);
CREATE INDEX IF NOT EXISTS ix_fact_cuaca  ON fact_prakiraan_cuaca (cuaca_key);

COMMENT ON TABLE  fact_prakiraan_cuaca IS 'Grain: desa x slot 3-jam x run analisis BMKG. Partisi bulanan by tanggal_key.';
COMMENT ON COLUMN fact_prakiraan_cuaca.t_celsius  IS 'NON-ADITIF: AVG/MIN/MAX';
COMMENT ON COLUMN fact_prakiraan_cuaca.hu_persen  IS 'NON-ADITIF: AVG/MIN/MAX';
COMMENT ON COLUMN fact_prakiraan_cuaca.tp_mm      IS 'ADITIF terhadap waktu; SEMI-ADITIF lintas lokasi';
COMMENT ON COLUMN fact_prakiraan_cuaca.tcc_persen IS 'NON-ADITIF: AVG';
COMMENT ON COLUMN fact_prakiraan_cuaca.ws_kmh     IS 'NON-ADITIF: AVG/MAX';
COMMENT ON COLUMN fact_prakiraan_cuaca.wd_deg     IS 'NON-ADITIF (sirkular)';
COMMENT ON COLUMN fact_prakiraan_cuaca.vs_m       IS 'NON-ADITIF: AVG/MIN';
COMMENT ON COLUMN fact_prakiraan_cuaca.jumlah_slot IS 'ADITIF: SUM';

-- View "run terbaru": satu baris per desa x slot, aman untuk agregasi.
CREATE OR REPLACE VIEW v_prakiraan_terbaru AS
SELECT DISTINCT ON (kode_desa, waktu_utc) *
FROM fact_prakiraan_cuaca
ORDER BY kode_desa, waktu_utc, analisis_utc DESC;
