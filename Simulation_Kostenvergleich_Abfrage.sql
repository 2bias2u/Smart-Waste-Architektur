-- Grafana variables:
-- $abholzyklus
-- $pickup_day
-- $simulation
-- $capacity_pct        (optional; Standard 100)
-- $dyn_max_till_empty  (Pflicht für dynamische Abholung)
-- $cost_per_empty
-- $cost_per_volume
-- $overflow_cost

WITH cfg AS (
  SELECT
    CASE lower(NULLIF('$abholzyklus',''))
      WHEN 'täglich'     THEN 1
      WHEN 'wöchentlich' THEN 7
      WHEN '10-tägig'    THEN 10
      WHEN '14-tägig'    THEN 14
      WHEN '30-tägig'    THEN 30
      ELSE NULL
    END::int AS abholzyklus,
    CASE lower(NULLIF('$pickup_day',''))
      WHEN 'montag'     THEN 1
      WHEN 'dienstag'   THEN 2
      WHEN 'mittwoch'   THEN 3
      WHEN 'donnerstag' THEN 4
      WHEN 'freitag'    THEN 5
      WHEN 'samstag'    THEN 6
      WHEN 'sonntag'    THEN 7
      ELSE NULL
    END AS abholzyklus_tag,
    COALESCE(NULLIF('$capacity_pct','')::numeric, 100) AS capacity_pct,
    NULLIF('$dyn_max_till_empty','')::numeric          AS dyn_max_till_empty
),

sim AS (
  SELECT
    sensor_id,
    simulation_number,
    (ts AT TIME ZONE 'Europe/Berlin')::date AS day,
    new_fill_in,
    MIN((ts AT TIME ZONE 'Europe/Berlin')::date)
      OVER (PARTITION BY sensor_id, simulation_number) AS start_date
  FROM sensor_daily_delta
  WHERE simulation = TRUE
    AND simulation_number = $simulation
    AND (ts AT TIME ZONE 'Europe/Berlin')::date <= CURRENT_DATE
),

joined AS (
  SELECT
    s.*,
    c.abholzyklus,
    c.abholzyklus_tag,
    c.capacity_pct,
    c.dyn_max_till_empty,
    ((s.day - s.start_date))::int AS days_since_start,
    -- 1=Mon .. 7=Sun
    (((EXTRACT(dow FROM s.day)::int + 6) % 7) + 1) AS dow_user
  FROM sim s
  CROSS JOIN cfg c
),

-- ========= DYNAMISCHE LOGIK =========

overall_cum AS (
  SELECT
    j.sensor_id,
    j.simulation_number,
    j.day,
    j.new_fill_in,
    j.capacity_pct,
    j.dyn_max_till_empty,
    SUM(j.new_fill_in) OVER (
      PARTITION BY j.sensor_id, j.simulation_number
      ORDER BY j.day
      ROWS UNBOUNDED PRECEDING
    ) AS cum_total
  FROM joined j
),

dyn_logic AS (
  SELECT
    o.*,
    CASE
      WHEN o.dyn_max_till_empty IS NULL OR o.dyn_max_till_empty <= 0
        THEN NULL
      ELSE FLOOR(o.cum_total / o.dyn_max_till_empty)
    END AS dyn_grp_index,
    CASE
      WHEN o.dyn_max_till_empty IS NULL OR o.dyn_max_till_empty <= 0 THEN 0
      ELSE
        CASE
          WHEN FLOOR(o.cum_total / o.dyn_max_till_empty)
               >
               FLOOR(
                 COALESCE(
                   LAG(o.cum_total) OVER (
                     PARTITION BY o.sensor_id, o.simulation_number
                     ORDER BY o.day
                   ),
                   0
                 ) / o.dyn_max_till_empty
               )
          THEN 1 ELSE 0
        END
    END AS pickup_flag_dyn,
    CASE
      WHEN o.dyn_max_till_empty IS NULL OR o.dyn_max_till_empty <= 0 THEN NULL
      ELSE o.cum_total
           - (FLOOR(o.cum_total / o.dyn_max_till_empty) * o.dyn_max_till_empty)
    END AS cum_fill_since_last_dyn
  FROM overall_cum o
),

dyn_overflow AS (
  SELECT
    d.*,
    CASE
      WHEN d.cum_fill_since_last_dyn IS NOT NULL
       AND d.capacity_pct IS NOT NULL
       AND d.cum_fill_since_last_dyn > d.capacity_pct
      THEN 1 ELSE 0
    END AS overflow_day_flag_dyn,
    CASE
      WHEN d.cum_fill_since_last_dyn IS NOT NULL
       AND d.capacity_pct IS NOT NULL
       AND d.cum_fill_since_last_dyn > d.capacity_pct
       AND COALESCE(
             LAG(d.cum_fill_since_last_dyn) OVER (
               PARTITION BY d.sensor_id, d.simulation_number, d.dyn_grp_index
               ORDER BY d.day
             ),
             0
           ) <= d.capacity_pct
      THEN 1 ELSE 0
    END AS overflow_event_flag_dyn
  FROM dyn_logic d
),

dyn_deltas AS (
  SELECT
    d.*,
    GREATEST(
      d.dyn_grp_index
      - COALESCE(
          LAG(d.dyn_grp_index) OVER (
            PARTITION BY d.sensor_id, d.simulation_number
            ORDER BY d.day
          ),
          0
        ),
      0
    ) AS dyn_index_delta
  FROM dyn_overflow d
),

dyn_total AS (
  SELECT
    sensor_id,
    simulation_number,
    SUM(dyn_index_delta * dyn_max_till_empty) AS total_disposed_dyn
  FROM dyn_deltas
  GROUP BY sensor_id, simulation_number
),

dyn_summary AS (
  SELECT
    f.sensor_id,
    f.simulation_number,
    SUM(f.pickup_flag_dyn)         AS empties_dyn,
    MAX(f.dyn_grp_index)           AS dyn_cycles_completed,
    SUM(f.overflow_event_flag_dyn) AS overflow_events_dyn,
    SUM(f.overflow_day_flag_dyn)   AS overflow_days_dyn,
    MAX(c.cum_total)               AS cum_total
  FROM dyn_overflow f
  JOIN overall_cum c
    ON f.sensor_id = c.sensor_id
   AND f.simulation_number = c.simulation_number
  GROUP BY f.sensor_id, f.simulation_number
),

dyn_statistic AS (
  SELECT
    d.sensor_id,
    d.simulation_number,
    MAX(d.dyn_grp_index)::bigint AS dyn_grp_index,
    t.total_disposed_dyn         AS total_disposed,
    SUM(d.new_fill_in)           AS sum_new_fill_in
  FROM dyn_overflow d
  JOIN dyn_total t
    ON t.sensor_id = d.sensor_id
   AND t.simulation_number = d.simulation_number
  GROUP BY d.sensor_id, d.simulation_number, t.total_disposed_dyn
),

-- ========= STATISCHE LOGIK =========

st_first_emptied AS (
  SELECT
    sensor_id,
    simulation_number,
    MIN(days_since_start) FILTER (
      WHERE dow_user = abholzyklus_tag
    ) AS first_emptied
  FROM joined
  GROUP BY sensor_id, simulation_number
),

st_marked AS (
  SELECT
    j.*,
    fe.first_emptied,
    CASE
      WHEN fe.first_emptied IS NOT NULL
       AND j.days_since_start = fe.first_emptied
      THEN 1
      WHEN fe.first_emptied IS NOT NULL
       AND j.abholzyklus IS NOT NULL
       AND j.abholzyklus > 0
       AND j.days_since_start >= fe.first_emptied
       AND ( (j.days_since_start - fe.first_emptied) % j.abholzyklus ) = 0
      THEN 1
      ELSE 0
    END AS pickup_flag
  FROM joined j
  LEFT JOIN st_first_emptied fe
    USING (sensor_id, simulation_number)
),

st_grp_calc AS (
  SELECT
    *,
    SUM(pickup_flag) OVER (
      PARTITION BY sensor_id, simulation_number
      ORDER BY day
    ) AS grp
  FROM st_marked
),

st_grp_and_cum AS (
  SELECT
    sensor_id,
    simulation_number,
    day,
    new_fill_in,
    pickup_flag,
    grp,
    days_since_start,
    first_emptied,
    abholzyklus,
    abholzyklus_tag,
    capacity_pct,
    SUM(new_fill_in) OVER (
      PARTITION BY sensor_id, simulation_number, grp
      ORDER BY day
    ) AS cum_fill_since_last_pickup,
    -- statischer Overflow-Tag: Füllstand nach letzter Leerung > Kapazitätsgrenze
    CASE
      WHEN capacity_pct IS NOT NULL
       AND SUM(new_fill_in) OVER (
             PARTITION BY sensor_id, simulation_number, grp
             ORDER BY day
           ) > capacity_pct
      THEN 1 ELSE 0
    END AS overflow_day_flag_static
  FROM st_grp_calc
),

st_sumup AS (
  SELECT DISTINCT
    sensor_id,
    simulation_number,
    SUM(cum_fill_since_last_pickup) FILTER (
      WHERE ((days_since_start - first_emptied) % abholzyklus) = abholzyklus - 1
    ) OVER (PARTITION BY sensor_id, simulation_number) AS total_emptied_volumen_per_sensor,
    COUNT(*) FILTER (WHERE pickup_flag = 1)
      OVER (PARTITION BY sensor_id, simulation_number) AS number_of_emptied_per_sensor,
    SUM(new_fill_in) OVER (PARTITION BY sensor_id, simulation_number) AS sum_total_volumen_per_sensor,
    SUM(overflow_day_flag_static) OVER (PARTITION BY sensor_id, simulation_number) AS static_overflow_days
  FROM st_grp_and_cum
),

-- ========= KOMBINIERTE KOSTEN (wide) =========

combined AS (
  SELECT
    d.sensor_id,
    d.simulation_number,

    -- dynamische Kosten
    d.dyn_grp_index * $cost_per_empty    AS dyn_cost_for_empting,
    d.total_disposed * $cost_per_volume  AS dyn_cost_for_volume,
    s.overflow_days_dyn * $overflow_cost AS dyn_overflow_cost,

    -- statische Kosten
    su.number_of_emptied_per_sensor * $cost_per_empty      AS static_cost_for_empting,
    su.total_emptied_volumen_per_sensor * $cost_per_volume AS static_cost_for_volume,
    su.static_overflow_days * $overflow_cost               AS static_overflow_cost
  FROM dyn_statistic d
  LEFT JOIN dyn_summary s USING (sensor_id, simulation_number)
  LEFT JOIN st_sumup su USING (sensor_id, simulation_number)
)

-- ========= AUSGABE: je Sensor 2 gestapelte Balken (dyn/stat) =========

SELECT
  sensor_id || ' dyn' AS x_label,
  simulation_number,
  dyn_cost_for_empting  AS cost_empting,
  dyn_cost_for_volume   AS cost_volume,
  dyn_overflow_cost     AS cost_overflow
FROM combined

UNION ALL

SELECT
  sensor_id || ' stat' AS x_label,
  simulation_number,
  static_cost_for_empting  AS cost_empting,
  static_cost_for_volume   AS cost_volume,
  static_overflow_cost     AS cost_overflow
FROM combined

ORDER BY x_label;




