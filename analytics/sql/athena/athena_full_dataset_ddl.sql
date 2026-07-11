-- Global Power Plant Analytics: Athena DDL Bundle
--
-- 1) Replace <BUCKET_NAME> with your deployed bucket, for example:
--    gppa-dev-lake-mubin-20260710212811
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
-- DASHBOARD VIEWS
-- ============================================================================
CREATE OR REPLACE VIEW gppa_dev_analytics.vw_power_generation_dashboard AS
SELECT
  country,
  primary_fuel,
  SUM(total_generation_gwh) AS total_generation_gwh,
  SUM(CASE WHEN primary_fuel IN ('Hydro','Solar','Wind','Biomass','Geothermal') THEN total_generation_gwh ELSE 0 END) AS renewable_generation_gwh
FROM gppa_dev_analytics.fact_power_generation
GROUP BY 1,2;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_plant_operations_dashboard AS
SELECT
  p.plant_id,
  p.plant_name,
  p.country,
  p.primary_fuel,
  p.capacity_mw AS plant_capacity_mw,
  p.commissioning_year,
  c.total_capacity_mw AS country_fuel_capacity_mw
FROM gppa_dev_analytics.dim_plant p
JOIN gppa_dev_analytics.fact_plant_capacity c
  ON p.country = c.country
 AND p.primary_fuel = c.primary_fuel;

CREATE OR REPLACE VIEW gppa_dev_analytics.vw_data_quality_monitoring AS
SELECT
  run_timestamp,
  dataset,
  input_rows,
  valid_rows,
  malformed_rows,
  null_issues,
  range_issues
FROM gppa_dev_analytics.audit_silver_quality_report;

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
