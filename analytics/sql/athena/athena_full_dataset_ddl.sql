-- Global Power Plant Analytics: Athena DDL Bundle
--
-- 1) Replace <BUCKET_NAME> with your deployed bucket, for example:
--    gppa-main-lake-platform-20260710212811
--
-- 2) Gold files are currently written as individual parquet files in a single folder.
--    For clean table-per-prefix querying, run this one-time copy in shell first:
--
--    aws s3 cp s3://<BUCKET_NAME>/gold/dim_plant.parquet s3://<BUCKET_NAME>/gold_tables/dim_plant/data.parquet
--    aws s3 cp s3://<BUCKET_NAME>/gold/dim_country.parquet s3://<BUCKET_NAME>/gold_tables/dim_country/data.parquet
--    aws s3 cp s3://<BUCKET_NAME>/gold/dim_fuel_type.parquet s3://<BUCKET_NAME>/gold_tables/dim_fuel_type/data.parquet
--    aws s3 cp s3://<BUCKET_NAME>/gold/dim_time.parquet s3://<BUCKET_NAME>/gold_tables/dim_time/data.parquet
--    aws s3 cp s3://<BUCKET_NAME>/gold/fact_plant_capacity.parquet s3://<BUCKET_NAME>/gold_tables/fact_plant_capacity/data.parquet
--    aws s3 cp s3://<BUCKET_NAME>/gold/fact_power_generation.parquet s3://<BUCKET_NAME>/gold_tables/fact_power_generation/data.parquet
--
-- 3) Run this file in Athena Query Editor using workgroup gppa-dev-wg.

CREATE DATABASE IF NOT EXISTS gppa_dev_analytics;

-- ============================================================================
-- SILVER
-- ============================================================================
CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.silver_stg_power_plants (
  plant_id string,
  plant_name string,
  country string,
  capacity_mw double,
  primary_fuel string,
  commissioning_year bigint,
  latitude double,
  longitude double,
  owner string,
  estimated_generation_gwh double,
  last_updated_at string,
  ingested_at string,
  source_name string,
  event_year bigint,
  event_month bigint
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/silver/'
TBLPROPERTIES ('classification'='parquet');

-- ============================================================================
-- QUARANTINE
-- ============================================================================
CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.quarantine_stg_power_plants_malformed (
  plant_id string,
  plant_name string,
  country string,
  capacity_mw double,
  primary_fuel string,
  commissioning_year bigint,
  latitude double,
  longitude double,
  owner string,
  estimated_generation_gwh double,
  last_updated_at string,
  ingested_at string,
  source_name string
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/quarantine/'
TBLPROPERTIES ('classification'='parquet');

-- ============================================================================
-- GOLD (table-per-prefix under gold_tables)
-- ============================================================================
CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.dim_plant (
  plant_id string,
  plant_name string,
  country string,
  capacity_mw double,
  primary_fuel string,
  commissioning_year bigint,
  latitude double,
  longitude double,
  owner_masked string
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/gold_tables/dim_plant/'
TBLPROPERTIES ('classification'='parquet');

CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.dim_country (
  country string,
  country_id bigint
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/gold_tables/dim_country/'
TBLPROPERTIES ('classification'='parquet');

CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.dim_fuel_type (
  primary_fuel string,
  fuel_type_id bigint,
  is_renewable boolean
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/gold_tables/dim_fuel_type/'
TBLPROPERTIES ('classification'='parquet');

CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.dim_time (
  year bigint,
  month bigint,
  day bigint,
  date string
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/gold_tables/dim_time/'
TBLPROPERTIES ('classification'='parquet');

CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.fact_plant_capacity (
  country string,
  primary_fuel string,
  total_capacity_mw double,
  renewable_capacity_mw double
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/gold_tables/fact_plant_capacity/'
TBLPROPERTIES ('classification'='parquet');

CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.fact_power_generation (
  country string,
  primary_fuel string,
  year bigint,
  total_generation_gwh double
)
STORED AS PARQUET
LOCATION 's3://<BUCKET_NAME>/gold_tables/fact_power_generation/'
TBLPROPERTIES ('classification'='parquet');

-- ============================================================================
-- AUDIT (CSV)
-- ============================================================================
CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.audit_bronze_run_report (
  source_name string,
  status string,
  rows bigint
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar' = '"',
  'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://<BUCKET_NAME>/audit/'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.audit_silver_quality_report (
  run_timestamp string,
  dataset string,
  input_rows bigint,
  valid_rows bigint,
  malformed_rows bigint,
  null_issues string,
  range_issues string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar' = '"',
  'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://<BUCKET_NAME>/audit/'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE EXTERNAL TABLE IF NOT EXISTS gppa_dev_analytics.audit_metrics (
  metric_timestamp string,
  metric_name string,
  metric_value double
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar' = '"',
  'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://<BUCKET_NAME>/audit/'
TBLPROPERTIES ('skip.header.line.count'='0');

-- ============================================================================
-- DASHBOARD VIEWS: POWER GENERATION
-- ============================================================================
CREATE OR REPLACE VIEW gppa_dev_analytics.vw_power_generation_country_capacity AS
SELECT
  country,
  SUM(total_capacity_mw) AS total_capacity_mw,
  SUM(renewable_capacity_mw) AS renewable_capacity_mw,
  SUM(total_capacity_mw) - SUM(renewable_capacity_mw) AS non_renewable_capacity_mw
FROM gppa_dev_analytics.fact_plant_capacity
GROUP BY 1;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_power_generation_fuel_distribution AS
SELECT
  country,
  primary_fuel,
  SUM(total_generation_gwh) AS total_generation_gwh
FROM gppa_dev_analytics.fact_power_generation
GROUP BY 1,2;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_power_generation_renewable_trend AS
SELECT
  g.year,
  g.country,
  SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS renewable_generation_gwh,
  SUM(CASE WHEN NOT f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS non_renewable_generation_gwh,
  CASE
    WHEN SUM(g.total_generation_gwh) = 0 THEN 0
    ELSE SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) / SUM(g.total_generation_gwh)
  END AS renewable_generation_ratio
FROM gppa_dev_analytics.fact_power_generation g
LEFT JOIN gppa_dev_analytics.dim_fuel_type f
  ON g.primary_fuel = f.primary_fuel
GROUP BY 1,2;

-- ============================================================================
-- DASHBOARD VIEWS: PLANT OPERATIONS
-- ============================================================================
CREATE OR REPLACE VIEW gppa_dev_analytics.vw_plant_operations_largest_plants AS
SELECT
  plant_id,
  plant_name,
  country,
  primary_fuel,
  capacity_mw,
  commissioning_year,
  latitude,
  longitude
FROM gppa_dev_analytics.dim_plant;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_plant_operations_aging_infrastructure AS
SELECT
  country,
  primary_fuel,
  COUNT(*) AS plant_count,
  AVG(commissioning_year) AS avg_commissioning_year,
  SUM(CASE WHEN commissioning_year < year(current_date) - 30 THEN 1 ELSE 0 END) AS aging_30_plus_count,
  SUM(CASE WHEN commissioning_year < year(current_date) - 40 THEN 1 ELSE 0 END) AS aging_40_plus_count
FROM gppa_dev_analytics.dim_plant
GROUP BY 1,2;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_plant_operations_capacity_utilization AS
WITH generation_by_country_fuel AS (
  SELECT
    country,
    primary_fuel,
    year,
    SUM(total_generation_gwh) AS total_generation_gwh
  FROM gppa_dev_analytics.fact_power_generation
  GROUP BY 1,2,3
),
capacity_by_country_fuel AS (
  SELECT
    country,
    primary_fuel,
    SUM(total_capacity_mw) AS total_capacity_mw
  FROM gppa_dev_analytics.fact_plant_capacity
  GROUP BY 1,2
)
SELECT
  g.year,
  g.country,
  g.primary_fuel,
  c.total_capacity_mw,
  g.total_generation_gwh,
  (c.total_capacity_mw * 8.76) AS theoretical_max_generation_gwh,
  CASE
    WHEN c.total_capacity_mw <= 0 THEN 0
    ELSE g.total_generation_gwh / (c.total_capacity_mw * 8.76)
  END AS utilization_ratio
FROM generation_by_country_fuel g
JOIN capacity_by_country_fuel c
  ON g.country = c.country
 AND g.primary_fuel = c.primary_fuel;

-- ============================================================================
-- DASHBOARD VIEWS: SUSTAINABILITY
-- ============================================================================
CREATE OR REPLACE VIEW gppa_dev_analytics.vw_sustainability_coal_dependency AS
SELECT
  country,
  SUM(CASE WHEN lower(primary_fuel) = 'coal' THEN total_generation_gwh ELSE 0 END) AS coal_generation_gwh,
  SUM(total_generation_gwh) AS total_generation_gwh,
  CASE
    WHEN SUM(total_generation_gwh) = 0 THEN 0
    ELSE SUM(CASE WHEN lower(primary_fuel) = 'coal' THEN total_generation_gwh ELSE 0 END) / SUM(total_generation_gwh)
  END AS coal_dependency_ratio
FROM gppa_dev_analytics.fact_power_generation
GROUP BY 1;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_sustainability_renewable_adoption_trend AS
SELECT
  g.year,
  g.country,
  SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS renewable_generation_gwh,
  SUM(g.total_generation_gwh) AS total_generation_gwh,
  CASE
    WHEN SUM(g.total_generation_gwh) = 0 THEN 0
    ELSE SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) / SUM(g.total_generation_gwh)
  END AS renewable_adoption_ratio
FROM gppa_dev_analytics.fact_power_generation g
LEFT JOIN gppa_dev_analytics.dim_fuel_type f
  ON g.primary_fuel = f.primary_fuel
GROUP BY 1,2;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_sustainability_clean_energy_growth AS
WITH renewable_by_year AS (
  SELECT
    g.year,
    g.country,
    SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS renewable_generation_gwh
  FROM gppa_dev_analytics.fact_power_generation g
  LEFT JOIN gppa_dev_analytics.dim_fuel_type f
    ON g.primary_fuel = f.primary_fuel
  GROUP BY 1,2
)
SELECT
  year,
  country,
  renewable_generation_gwh,
  renewable_generation_gwh
    - LAG(renewable_generation_gwh) OVER (PARTITION BY country ORDER BY year) AS renewable_generation_growth_gwh
FROM renewable_by_year;

-- ============================================================================
-- DASHBOARD VIEWS: GEOGRAPHIC
-- ============================================================================
CREATE OR REPLACE VIEW gppa_dev_analytics.vw_geographic_plant_distribution AS
SELECT
  country,
  COUNT(*) AS plant_count,
  SUM(capacity_mw) AS total_capacity_mw,
  AVG(capacity_mw) AS avg_capacity_mw
FROM gppa_dev_analytics.dim_plant
GROUP BY 1;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_geographic_generation_density AS
SELECT
  p.country,
  COUNT(DISTINCT p.plant_id) AS plant_count,
  SUM(p.capacity_mw) AS total_capacity_mw,
  SUM(g.total_generation_gwh) AS total_generation_gwh,
  CASE
    WHEN COUNT(DISTINCT p.plant_id) = 0 THEN 0
    ELSE SUM(g.total_generation_gwh) / COUNT(DISTINCT p.plant_id)
  END AS generation_per_plant_gwh
FROM gppa_dev_analytics.dim_plant p
LEFT JOIN gppa_dev_analytics.fact_power_generation g
  ON p.country = g.country
 AND p.primary_fuel = g.primary_fuel
GROUP BY 1;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_geographic_heatmap_points AS
SELECT
  plant_id,
  plant_name,
  country,
  latitude,
  longitude,
  capacity_mw,
  primary_fuel
FROM gppa_dev_analytics.dim_plant
WHERE latitude IS NOT NULL
  AND longitude IS NOT NULL;

-- ============================================================================
-- DASHBOARD VIEWS: OPERATIONAL MONITORING
-- ============================================================================
CREATE OR REPLACE VIEW gppa_dev_analytics.vw_monitoring_data_quality AS
SELECT
  run_timestamp,
  dataset,
  input_rows,
  valid_rows,
  malformed_rows,
  null_issues,
  range_issues,
  CASE WHEN input_rows = 0 THEN 0 ELSE CAST(valid_rows AS double) / CAST(input_rows AS double) END AS valid_ratio
FROM gppa_dev_analytics.audit_silver_quality_report;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_monitoring_freshness AS
SELECT
  source_name,
  max(ingested_at) AS latest_ingested_at,
  date_diff('hour', max(from_iso8601_timestamp(ingested_at)), current_timestamp) AS lag_hours
FROM gppa_dev_analytics.silver_stg_power_plants
GROUP BY 1;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_monitoring_pipeline_metrics AS
SELECT
  metric_timestamp,
  metric_name,
  metric_value
FROM gppa_dev_analytics.audit_metrics;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_monitoring_processing_latency AS
WITH bronze_ts AS (
  SELECT max(from_iso8601_timestamp(metric_timestamp)) AS ts
  FROM gppa_dev_analytics.audit_metrics
  WHERE metric_name = 'bronze_rows_ingested'
),
silver_ts AS (
  SELECT max(from_iso8601_timestamp(metric_timestamp)) AS ts
  FROM gppa_dev_analytics.audit_metrics
  WHERE metric_name = 'silver_valid_rows'
),
gold_ts AS (
  SELECT max(from_iso8601_timestamp(metric_timestamp)) AS ts
  FROM gppa_dev_analytics.audit_metrics
  WHERE metric_name = 'gold_rows_fact_capacity'
),
viz_ts AS (
  SELECT max(from_iso8601_timestamp(metric_timestamp)) AS ts
  FROM gppa_dev_analytics.audit_metrics
  WHERE metric_name = 'visualizations_generated'
)
SELECT
  bronze_ts.ts AS bronze_completed_at,
  silver_ts.ts AS silver_completed_at,
  gold_ts.ts AS gold_completed_at,
  viz_ts.ts AS visualizations_completed_at,
  date_diff('minute', bronze_ts.ts, silver_ts.ts) AS bronze_to_silver_minutes,
  date_diff('minute', silver_ts.ts, gold_ts.ts) AS silver_to_gold_minutes,
  date_diff('minute', gold_ts.ts, viz_ts.ts) AS gold_to_viz_minutes
FROM bronze_ts, silver_ts, gold_ts, viz_ts;

-- ============================================================================
-- SANITY CHECKS
-- ============================================================================
-- SELECT count(*) AS silver_rows FROM gppa_dev_analytics.silver_stg_power_plants;
-- SELECT count(*) AS malformed_rows FROM gppa_dev_analytics.quarantine_stg_power_plants_malformed;
-- SELECT count(*) AS fact_capacity_rows FROM gppa_dev_analytics.fact_plant_capacity;
-- SELECT country, SUM(total_capacity_mw) AS total_capacity_mw
-- FROM gppa_dev_analytics.fact_plant_capacity
-- GROUP BY 1
-- ORDER BY 2 DESC
-- LIMIT 10;
