-- =====================================================================
-- fact_prakiraan_cuaca
-- GRAIN : 1 desa x 1 slot prakiraan 3-jaman (utc_datetime) x 1 run analisis BMKG.
-- Tipe  : periodic snapshot (prakiraan; BMKG tidak menyediakan arsip historis).
-- Partisi: RANGE bulanan pada tanggal_sk (tanggal lokal WITA, YYYYMMDD).
--
-- LABEL ADITIVITAS
--   t_celsius        NON-ADDITIVE  -> agregasi AVG / MIN / MAX
--   hu_persen        NON-ADDITIVE  -> AVG / MIN / MAX
--   tp_mm            ADDITIVE terhadap waktu (total curah hujan per periode);
--                    SEMI-ADDITIVE lintas lokasi (jangan SUM lintas desa, pakai AVG)
--   tcc_persen       NON-ADDITIVE  -> AVG
--   ws_kmh           NON-ADDITIVE  -> AVG / MAX
--   wd_deg           NON-ADDITIVE  (sudut/sirkular) -> jangan di-AVG biasa
--   vs_m             NON-ADDITIVE  -> AVG / MIN (100% NULL di snapshot ini)
--   jumlah_slot      ADDITIVE      -> SUM (=1 per baris, untuk COUNT tanpa NULL)
-- =====================================================================
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca (
    -- ---- foreign key ke dimensi (surrogate key) ----
    lokasi_sk           bigint   NOT NULL REFERENCES dim_lokasi (lokasi_sk),
    -- dim_date dibangun CTAS oleh sql/10_dim_date.sql (tanpa PK) -> FK logis, dijaga test orphan
    tanggal_sk          integer  NOT NULL,  -- -> dim_date.date_sk, tanggal lokal slot (WITA)
    tanggal_analisis_sk integer  NOT NULL,  -- -> dim_date.date_sk, role-playing (tanggal run)
    cuaca_sk            smallint NOT NULL REFERENCES dim_cuaca (cuaca_sk),

    -- ---- degenerate / natural key (untuk upsert idempoten) ----
    kode_desa            varchar(16)  NOT NULL,
    waktu_utc            timestamptz  NOT NULL,   -- utc_datetime
    analisis_utc         timestamptz  NOT NULL,   -- analysis_date (asumsi UTC)
    waktu_lokal          timestamp    NOT NULL,   -- local_datetime (WITA, UTC+8)
    jam_lokal            smallint     NOT NULL CHECK (jam_lokal BETWEEN 0 AND 23),
    arah_angin           varchar(3),              -- wd (N, NE, ...), from -> wd_to
    arah_angin_tujuan    varchar(3),              -- wd_to

    -- ---- measures ----
    t_celsius            numeric(4,1),            -- NON-ADDITIVE
    hu_persen            numeric(5,2),            -- NON-ADDITIVE
    tp_mm                numeric(6,2),            -- ADDITIVE (waktu) / SEMI-ADDITIVE (lokasi)
    tcc_persen           numeric(5,2),            -- NON-ADDITIVE
    ws_kmh               numeric(6,2),            -- NON-ADDITIVE
    wd_deg               smallint,                -- NON-ADDITIVE (sirkular)
    vs_m                 numeric(8,1),            -- NON-ADDITIVE
    jumlah_slot          smallint NOT NULL DEFAULT 1,  -- ADDITIVE

    -- ---- audit ----
    batch_id             varchar(32)  NOT NULL,
    loaded_at            timestamptz  NOT NULL DEFAULT now(),

    -- natural key upsert; wajib memuat kolom partisi (tanggal_sk)
    CONSTRAINT pk_fact_prakiraan
        PRIMARY KEY (kode_desa, waktu_utc, analisis_utc, tanggal_sk)
) PARTITION BY RANGE (tanggal_sk);

-- Partisi bulanan (tambahkan bulan baru saat persiapan tarik snapshot).
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_09 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20260901) TO (20261001);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_10 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20261001) TO (20261101);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_11 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20261101) TO (20261201);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_2026_12 PARTITION OF fact_prakiraan_cuaca FOR VALUES FROM (20261201) TO (20270101);
CREATE TABLE IF NOT EXISTS fact_prakiraan_cuaca_default PARTITION OF fact_prakiraan_cuaca DEFAULT;

CREATE INDEX IF NOT EXISTS ix_fact_lokasi ON fact_prakiraan_cuaca (lokasi_sk, tanggal_sk);
CREATE INDEX IF NOT EXISTS ix_fact_cuaca  ON fact_prakiraan_cuaca (cuaca_sk);

COMMENT ON TABLE  fact_prakiraan_cuaca IS 'Grain: desa x slot 3-jam x run analisis BMKG. Partisi bulanan by tanggal_sk.';
COMMENT ON COLUMN fact_prakiraan_cuaca.t_celsius  IS 'NON-ADDITIVE: AVG/MIN/MAX';
COMMENT ON COLUMN fact_prakiraan_cuaca.hu_persen  IS 'NON-ADDITIVE: AVG/MIN/MAX';
COMMENT ON COLUMN fact_prakiraan_cuaca.tp_mm      IS 'ADDITIVE terhadap waktu; SEMI-ADDITIVE lintas lokasi';
COMMENT ON COLUMN fact_prakiraan_cuaca.tcc_persen IS 'NON-ADDITIVE: AVG';
COMMENT ON COLUMN fact_prakiraan_cuaca.ws_kmh     IS 'NON-ADDITIVE: AVG/MAX';
COMMENT ON COLUMN fact_prakiraan_cuaca.wd_deg     IS 'NON-ADDITIVE (sirkular)';
COMMENT ON COLUMN fact_prakiraan_cuaca.vs_m       IS 'NON-ADDITIVE: AVG/MIN';
COMMENT ON COLUMN fact_prakiraan_cuaca.jumlah_slot IS 'ADDITIVE: SUM';

-- View "run terbaru": satu baris per desa x slot, aman untuk agregasi.
CREATE OR REPLACE VIEW v_prakiraan_terbaru AS
SELECT DISTINCT ON (kode_desa, waktu_utc) *
FROM fact_prakiraan_cuaca
ORDER BY kode_desa, waktu_utc, analisis_utc DESC;
