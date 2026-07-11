CREATE OR REPLACE VIEW vw_monitoring_data_quality AS
SELECT
  CAST(try(from_iso8601_timestamp(run_timestamp)) AS timestamp) AS run_timestamp,
  CAST(dataset AS varchar) AS dataset,
  CAST(input_rows AS integer) AS input_rows,
  CAST(valid_rows AS integer) AS valid_rows,
  CAST(malformed_rows AS integer) AS malformed_rows,
  CAST(null_issues AS integer) AS null_issues,
  CAST(range_issues AS integer) AS range_issues,
  CAST(CASE WHEN input_rows = 0 THEN 0 ELSE CAST(valid_rows AS double) / CAST(input_rows AS double) END AS double) AS valid_ratio
FROM audit_silver_quality_report;

CREATE OR REPLACE VIEW vw_monitoring_freshness AS
SELECT
  CAST(source_name AS varchar) AS source_name,
  CAST(max(from_iso8601_timestamp(ingested_at)) AS timestamp) AS latest_ingested_at,
  CAST(date_diff('hour', max(from_iso8601_timestamp(ingested_at)), current_timestamp) AS integer) AS lag_hours
FROM silver_stg_power_plants
GROUP BY 1;

CREATE OR REPLACE VIEW vw_monitoring_pipeline_freshness AS
SELECT
  source_name,
  latest_ingested_at,
  lag_hours
FROM vw_monitoring_freshness;

CREATE OR REPLACE VIEW vw_monitoring_failed_jobs AS
SELECT
  CAST(date_trunc('day', from_iso8601_timestamp(metric_timestamp)) AS timestamp) AS metric_date,
  CAST(metric_name AS varchar) AS metric_name,
  CAST(SUM(metric_value) AS double) AS failure_count
FROM audit_metrics
WHERE lower(metric_name) LIKE '%fail%'
   OR lower(metric_name) LIKE '%error%'
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_monitoring_pipeline_metrics AS
SELECT
  CAST(try(from_iso8601_timestamp(metric_timestamp)) AS timestamp) AS metric_timestamp,
  CAST(metric_name AS varchar) AS metric_name,
  CAST(metric_value AS double) AS metric_value
FROM audit_metrics;

CREATE OR REPLACE VIEW vw_monitoring_processing_latency AS
WITH bronze_runs AS (
  SELECT
    bronze_ts,
    lead(bronze_ts) OVER (ORDER BY bronze_ts) AS next_bronze_ts
  FROM (
    SELECT DISTINCT CAST(from_iso8601_timestamp(metric_timestamp) AS timestamp) AS bronze_ts
    FROM audit_metrics
    WHERE metric_name = 'bronze_rows_ingested'
  ) b
),
bronze_silver AS (
  SELECT
    b.bronze_ts,
    b.next_bronze_ts,
    (
      SELECT min(CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp))
      FROM audit_metrics m
      WHERE m.metric_name = 'silver_valid_rows'
        AND CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp) >= b.bronze_ts
        AND (b.next_bronze_ts IS NULL OR CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp) < b.next_bronze_ts)
    ) AS silver_ts
  FROM bronze_runs b
),
bronze_silver_gold AS (
  SELECT
    bs.bronze_ts,
    bs.next_bronze_ts,
    bs.silver_ts,
    (
      SELECT min(CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp))
      FROM audit_metrics m
      WHERE m.metric_name = 'gold_rows_fact_capacity'
        AND bs.silver_ts IS NOT NULL
        AND CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp) >= bs.silver_ts
        AND (bs.next_bronze_ts IS NULL OR CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp) < bs.next_bronze_ts)
    ) AS gold_ts
  FROM bronze_silver bs
),
pipeline_runs AS (
  SELECT
    bsg.bronze_ts,
    bsg.silver_ts,
    bsg.gold_ts,
    (
      SELECT min(CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp))
      FROM audit_metrics m
      WHERE m.metric_name = 'visualizations_generated'
        AND bsg.gold_ts IS NOT NULL
        AND CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp) >= bsg.gold_ts
        AND (bsg.next_bronze_ts IS NULL OR CAST(from_iso8601_timestamp(m.metric_timestamp) AS timestamp) < bsg.next_bronze_ts)
    ) AS viz_ts
  FROM bronze_silver_gold bsg
),
latest_complete_run AS (
  SELECT
    bronze_ts,
    silver_ts,
    gold_ts,
    viz_ts
  FROM pipeline_runs
  WHERE silver_ts IS NOT NULL
    AND gold_ts IS NOT NULL
    AND viz_ts IS NOT NULL
  ORDER BY bronze_ts DESC
  LIMIT 1
)
SELECT
  bronze_ts AS bronze_completed_at,
  silver_ts AS silver_completed_at,
  gold_ts AS gold_completed_at,
  viz_ts AS visualizations_completed_at,
  CAST(greatest(0, CEIL(CAST(date_diff('second', bronze_ts, silver_ts) AS double) / 60.0)) AS integer) AS bronze_to_silver_minutes,
  CAST(greatest(0, CEIL(CAST(date_diff('second', silver_ts, gold_ts) AS double) / 60.0)) AS integer) AS silver_to_gold_minutes,
  CAST(greatest(0, CEIL(CAST(date_diff('second', gold_ts, viz_ts) AS double) / 60.0)) AS integer) AS gold_to_viz_minutes
FROM latest_complete_run;

CREATE OR REPLACE VIEW vw_monitoring_latency AS
SELECT
  bronze_completed_at,
  silver_completed_at,
  gold_completed_at,
  visualizations_completed_at,
  bronze_to_silver_minutes,
  silver_to_gold_minutes,
  gold_to_viz_minutes
FROM vw_monitoring_processing_latency;
