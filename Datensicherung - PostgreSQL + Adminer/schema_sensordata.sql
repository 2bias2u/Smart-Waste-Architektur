-- =====================================================================
-- Schema: sensordata (public)  –  rekonstruiert aus Adminer-Struktur
-- Hinweis: Spalten ohne "NULL" in Adminer sind NOT NULL.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ---------------------------------------------------------------------
-- routes
-- ---------------------------------------------------------------------
CREATE TABLE routes (
    "time"        timestamptz DEFAULT now(),
    route_id      serial      NOT NULL,   -- erzeugt routes_route_id_seq
    route_coords  jsonb,
    distance      real,
    duration      real,
    affected_bins jsonb,
    CONSTRAINT routes_pkey PRIMARY KEY (route_id)
);

-- ---------------------------------------------------------------------
-- sensor_avg_fill_rate
-- ---------------------------------------------------------------------
CREATE TABLE sensor_avg_fill_rate (
    sensor_id               text             NOT NULL,
    avg_fill_rate_per_hour  double precision,
    last_fill_level         double precision,
    estimated_hours_to_full double precision,
    empty_count             integer          DEFAULT 0,
    created_at              timestamptz      NOT NULL DEFAULT now(),
    estimated_full_time     timestamp,
    changed_at              timestamptz,
    CONSTRAINT sensor_avg_fill_rate_pkey PRIMARY KEY (sensor_id)
);

-- ---------------------------------------------------------------------
-- sensor_cost
-- ---------------------------------------------------------------------
CREATE TABLE sensor_cost (
    type                         text          NOT NULL,
    abholzyklus_in_tagen         integer,
    entsorgungskosten            numeric(10,2) NOT NULL,
    berechnungsart               text          NOT NULL,
    interne_kosten               numeric(10,2) NOT NULL,
    overflow_kosten              numeric(10,2) NOT NULL,
    max_dauer_till_overflow_cost smallint      NOT NULL,
    abholzyklus_tag              smallint      NOT NULL,
    abholzyklus_woche            smallint      NOT NULL,
    overflow_level               integer,
    CONSTRAINT sensor_cost_pkey PRIMARY KEY (type)
);

COMMENT ON COLUMN sensor_cost.type                         IS 'Art des Mülls';
COMMENT ON COLUMN sensor_cost.entsorgungskosten            IS 'direkte Entsorgungskosten';
COMMENT ON COLUMN sensor_cost.interne_kosten               IS 'Mitarbeiter, Fahrzeug, Infrastruktur';
COMMENT ON COLUMN sensor_cost.overflow_kosten              IS 'Mehrkosten, wenn Tonnen überfüllt sind';
COMMENT ON COLUMN sensor_cost.max_dauer_till_overflow_cost IS 'Maximale Dauer ab wann die Kosten für Überfüllung anfallen';
COMMENT ON COLUMN sensor_cost.abholzyklus_tag              IS '1- Montag, bis 7-sonntag';
COMMENT ON COLUMN sensor_cost.abholzyklus_woche            IS '1-4 Woche des Monats - nur erste Abholung, wenn mehrmals im Monat, dann nach Intervall';
COMMENT ON COLUMN sensor_cost.overflow_level               IS 'ab wie viel % gilt überfüllt für overflow';

-- ---------------------------------------------------------------------
-- sensor_cost_history
-- ---------------------------------------------------------------------
CREATE TABLE sensor_cost_history (
    sensor_id     text        NOT NULL,
    "timestamp"   timestamptz NOT NULL DEFAULT now(),
    fill_level    real,
    dyn_cost      real,
    static_cost   real,
    overflow_cost real,
    total_cost    real,
    route_cost    real,
    risky_days    integer,
    should_pickup boolean,
    scenario      text        DEFAULT 'dynamisch',
    CONSTRAINT sensor_cost_history_pkey PRIMARY KEY (sensor_id, "timestamp")
);

CREATE INDEX sensor_cost_history_timestamp_idx
    ON sensor_cost_history ("timestamp" DESC);
CREATE INDEX sensor_cost_history_sensor_id_timestamp_idx
    ON sensor_cost_history (sensor_id, "timestamp" DESC);

-- ---------------------------------------------------------------------
-- sensor_daily_delta
-- ---------------------------------------------------------------------
CREATE TABLE sensor_daily_delta (
    id                bigserial   NOT NULL,   -- erzeugt sensor_daily_delta_id_seq
    sensor_id         text        NOT NULL,
    ts                timestamptz NOT NULL,
    new_fill_in       numeric     NOT NULL,
    simulation        boolean     NOT NULL DEFAULT true,
    simulation_number integer     NOT NULL,
    CONSTRAINT sensor_daily_delta_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------
-- sensor_data  (Stammdaten der Sensoren, inkl. Felder aus sensor_data_uni)
-- ---------------------------------------------------------------------
CREATE TABLE sensor_data (
    sensor_id            text             NOT NULL,
    lon                  double precision NOT NULL,
    lat                  double precision NOT NULL,
    location             text             NOT NULL,
    topic                text             NOT NULL,
    type                 text             NOT NULL,
    volumen_in_l         double precision NOT NULL,
    gebaude              text,
    etage                integer,
    standortbeschreibung text,
    raumnummer           integer,
    cost_per_p           double precision,
    CONSTRAINT sensor_data_pkey PRIMARY KEY (sensor_id)
);

-- ---------------------------------------------------------------------
-- sensor_fill_level  (TimescaleDB-Hypertable)
-- ---------------------------------------------------------------------
CREATE TABLE sensor_fill_level (
    sensor_id   text             NOT NULL,
    created_at  timestamptz      NOT NULL DEFAULT now(),
    fill_level  double precision NOT NULL,
    distance    double precision,
    topic       text,
    new_fill_in double precision,
    CONSTRAINT sensor_fill_level_pkey PRIMARY KEY (sensor_id, created_at)
);

-- legt automatisch Index (created_at DESC) + Trigger ts_insert_blocker an
SELECT create_hypertable('sensor_fill_level', 'created_at', if_not_exists => TRUE);

-- ---------------------------------------------------------------------
-- sensor_last_empty  (TimescaleDB-Hypertable)
-- ---------------------------------------------------------------------
CREATE TABLE sensor_last_empty (
    sensor_id         text             NOT NULL,
    created_at        timestamp        NOT NULL DEFAULT now(),  -- ohne Zeitzone (wie im Original)
    fill_before_empty double precision,
    CONSTRAINT sensor_last_empty_pkey PRIMARY KEY (sensor_id, created_at)
);

SELECT create_hypertable('sensor_last_empty', 'created_at', if_not_exists => TRUE);
