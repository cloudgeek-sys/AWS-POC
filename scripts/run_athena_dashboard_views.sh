#!/usr/bin/env bash
set -euo pipefail

WORKGROUP="${ATHENA_WORKGROUP:-gppa-main-wg}"
DATABASE="${ATHENA_DATABASE:-gppa_main_analytics}"
OUTPUT_LOCATION="${ATHENA_OUTPUT_LOCATION:-s3://gppa-main-lake-platform-20260710212811/athena/results/}"
REGION="${AWS_REGION:-us-east-1}"

SQL_FILES=(
  "analytics/sql/gold_views/power_generation_dashboard.sql"
  "analytics/sql/gold_views/plant_operations_dashboard.sql"
  "analytics/sql/gold_views/sustainability_dashboard.sql"
  "analytics/sql/gold_views/geographic_dashboard.sql"
  "analytics/sql/monitoring/data_quality_monitoring.sql"
)

GOLD_TABLE_NAMES=(
  "dim_plant"
  "dim_country"
  "dim_fuel_type"
  "dim_time"
  "fact_plant_capacity"
  "fact_power_generation"
  "fact_capacity_geo"
)

extract_bucket_from_s3_uri() {
  local s3_uri="$1"
  local no_scheme
  no_scheme="${s3_uri#s3://}"
  echo "${no_scheme%%/*}"
}

run_query() {
  local query="$1"
  local context_db="${2:-$DATABASE}"
  local qid state reason

  if [[ -n "$context_db" ]]; then
    qid="$(aws athena start-query-execution \
      --region "$REGION" \
      --work-group "$WORKGROUP" \
      --query-execution-context "Database=$context_db" \
      --result-configuration "OutputLocation=$OUTPUT_LOCATION" \
      --query-string "$query" \
      --query 'QueryExecutionId' \
      --output text)"
  else
    qid="$(aws athena start-query-execution \
      --region "$REGION" \
      --work-group "$WORKGROUP" \
      --result-configuration "OutputLocation=$OUTPUT_LOCATION" \
      --query-string "$query" \
      --query 'QueryExecutionId' \
      --output text)"
  fi

  echo "  QueryExecutionId: $qid"

  while true; do
    state="$(aws athena get-query-execution \
      --region "$REGION" \
      --query-execution-id "$qid" \
      --query 'QueryExecution.Status.State' \
      --output text)"

    case "$state" in
      SUCCEEDED)
        echo "  Status: SUCCEEDED"
        break
        ;;
      FAILED|CANCELLED)
        reason="$(aws athena get-query-execution \
          --region "$REGION" \
          --query-execution-id "$qid" \
          --query 'QueryExecution.Status.StateChangeReason' \
          --output text)"
        echo "  Status: $state"
        echo "  Reason: $reason"
        return 1
        ;;
      *)
        sleep 2
        ;;
    esac
  done
}

run_sql_file_statements() {
  local sql_file="$1"

  if [[ ! -f "$sql_file" ]]; then
    echo "Missing SQL file: $sql_file" >&2
    exit 1
  fi

  echo "Processing file: $sql_file"

  awk 'BEGIN{RS=";"} {
    gsub(/[\r\n]+/, " ", $0);
    gsub(/[[:space:]]+/, " ", $0);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
    if (length($0) > 0) print $0 ";"
  }' "$sql_file" |
    while IFS= read -r stmt; do
      echo "- Executing statement"
      run_query "$stmt"
    done
}

bootstrap_athena_objects() {
  local data_lake_bucket="$1"
  local audit_metrics_src="s3://${data_lake_bucket}/audit/metrics.csv"
  local audit_quality_src="s3://${data_lake_bucket}/audit/silver_quality_report.csv"
  local audit_freshness_src="s3://${data_lake_bucket}/audit/freshness_report.csv"
  local audit_metrics_dst="s3://${data_lake_bucket}/audit_tables/metrics/data.csv"
  local audit_quality_dst="s3://${data_lake_bucket}/audit_tables/silver_quality_report/data.csv"
  local audit_freshness_dst="s3://${data_lake_bucket}/audit_tables/freshness_report/data.csv"

  echo "Bootstrapping analytics database and external tables"

  for table_name in "${GOLD_TABLE_NAMES[@]}"; do
    local source_uri="s3://${data_lake_bucket}/gold/${table_name}.parquet"
    local target_uri="s3://${data_lake_bucket}/gold_tables/${table_name}/data.parquet"

    if aws s3 ls "$source_uri" >/dev/null 2>&1; then
      echo "- Ensuring table prefix for ${table_name}"
      aws s3 cp "$source_uri" "$target_uri" >/dev/null
    else
      echo "- Skipping ${table_name}; source not found at ${source_uri}"
    fi
  done

  if aws s3 ls "$audit_quality_src" >/dev/null 2>&1; then
    echo "- Ensuring isolated audit table prefix for silver_quality_report"
    aws s3 cp "$audit_quality_src" "$audit_quality_dst" >/dev/null
  else
    echo "- Skipping audit_silver_quality_report; source not found at ${audit_quality_src}"
  fi

  if aws s3 ls "$audit_metrics_src" >/dev/null 2>&1; then
    echo "- Ensuring isolated audit table prefix for metrics"
    aws s3 cp "$audit_metrics_src" "$audit_metrics_dst" >/dev/null
  else
    echo "- Skipping audit_metrics; source not found at ${audit_metrics_src}"
  fi

  if aws s3 ls "$audit_freshness_src" >/dev/null 2>&1; then
    echo "- Ensuring isolated audit table prefix for freshness_report"
    aws s3 cp "$audit_freshness_src" "$audit_freshness_dst" >/dev/null
  else
    echo "- Skipping audit_freshness_report; source not found at ${audit_freshness_src}"
  fi

  run_query "CREATE DATABASE IF NOT EXISTS ${DATABASE}" ""

  run_query "DROP TABLE IF EXISTS ${DATABASE}.silver_stg_power_plants"
  run_query "CREATE EXTERNAL TABLE ${DATABASE}.silver_stg_power_plants (plant_id string, plant_name string, country string, capacity_mw double, primary_fuel string, commissioning_year double, latitude double, longitude double, owner string, estimated_generation_gwh double, continent string, sub_region string, last_updated_at string, ingested_at string, source_name string, event_year bigint, event_month bigint) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/silver/' TBLPROPERTIES ('classification'='parquet')"

  run_query "DROP TABLE IF EXISTS ${DATABASE}.dim_plant"
  run_query "CREATE EXTERNAL TABLE ${DATABASE}.dim_plant (plant_id string, plant_name string, country string, capacity_mw double, primary_fuel string, commissioning_year double, latitude double, longitude double, owner_masked string) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/gold_tables/dim_plant/' TBLPROPERTIES ('classification'='parquet')"

  run_query "CREATE EXTERNAL TABLE IF NOT EXISTS ${DATABASE}.dim_country (country string, country_id bigint) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/gold_tables/dim_country/' TBLPROPERTIES ('classification'='parquet')"

  run_query "CREATE EXTERNAL TABLE IF NOT EXISTS ${DATABASE}.dim_fuel_type (primary_fuel string, fuel_type_id bigint, is_renewable boolean) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/gold_tables/dim_fuel_type/' TBLPROPERTIES ('classification'='parquet')"

  run_query "CREATE EXTERNAL TABLE IF NOT EXISTS ${DATABASE}.dim_time (year bigint, month bigint, day bigint, date string) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/gold_tables/dim_time/' TBLPROPERTIES ('classification'='parquet')"

  run_query "CREATE EXTERNAL TABLE IF NOT EXISTS ${DATABASE}.fact_plant_capacity (country string, primary_fuel string, total_capacity_mw double, renewable_capacity_mw double) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/gold_tables/fact_plant_capacity/' TBLPROPERTIES ('classification'='parquet')"

  run_query "DROP TABLE IF EXISTS ${DATABASE}.fact_power_generation"
  run_query "CREATE EXTERNAL TABLE ${DATABASE}.fact_power_generation (country string, primary_fuel string, year bigint, total_generation_gwh double) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/gold_tables/fact_power_generation/' TBLPROPERTIES ('classification'='parquet')"

  run_query "CREATE EXTERNAL TABLE IF NOT EXISTS ${DATABASE}.fact_capacity_geo (continent string, sub_region string, total_capacity_mw double) STORED AS PARQUET LOCATION 's3://${data_lake_bucket}/gold_tables/fact_capacity_geo/' TBLPROPERTIES ('classification'='parquet')"

  run_query "DROP TABLE IF EXISTS ${DATABASE}.audit_silver_quality_report"
  run_query "CREATE EXTERNAL TABLE ${DATABASE}.audit_silver_quality_report (run_timestamp string, dataset string, input_rows string, valid_rows string, malformed_rows string, duplicate_rows_detected string, unique_plant_id_ok string, duplicate_plant_id_count string, mandatory_fields_ok string, mandatory_null_validation_ok string, null_plant_name string, null_country string, null_primary_fuel string, null_capacity_mw string, positive_capacity_ok string, invalid_capacity_rows string, valid_commissioning_year_ok string, invalid_commissioning_year_rows string, schema_drift_detected string, schema_new_columns string, schema_removed_columns string, null_issues string, range_issues string) ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde' WITH SERDEPROPERTIES ('separatorChar'=',','quoteChar'='\"') STORED AS TEXTFILE LOCATION 's3://${data_lake_bucket}/audit_tables/silver_quality_report/' TBLPROPERTIES ('skip.header.line.count'='1')"

  run_query "DROP TABLE IF EXISTS ${DATABASE}.audit_freshness_report"
  run_query "CREATE EXTERNAL TABLE ${DATABASE}.audit_freshness_report (run_timestamp string, source_name string, ingest_status string, last_ingested_at string, event_time_watermark string, update_sla_hours string, hours_since_last_update string, missing_updates string, ingestion_delay_sla_hours string, ingestion_delay_hours string, ingestion_delay_breached string) ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde' WITH SERDEPROPERTIES ('separatorChar'=',','quoteChar'='\"') STORED AS TEXTFILE LOCATION 's3://${data_lake_bucket}/audit_tables/freshness_report/' TBLPROPERTIES ('skip.header.line.count'='1')"

  run_query "CREATE EXTERNAL TABLE IF NOT EXISTS ${DATABASE}.audit_metrics (metric_timestamp string, metric_name string, metric_value double) ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde' WITH SERDEPROPERTIES ('separatorChar'=',','quoteChar'='\"') STORED AS TEXTFILE LOCATION 's3://${data_lake_bucket}/audit_tables/metrics/' TBLPROPERTIES ('skip.header.line.count'='0')"
}

echo "Running Athena dashboard view SQL"
echo "  Region: $REGION"
echo "  Workgroup: $WORKGROUP"
echo "  Database: $DATABASE"
echo "  Output: $OUTPUT_LOCATION"

DATA_LAKE_BUCKET="$(extract_bucket_from_s3_uri "$OUTPUT_LOCATION")"
if [[ -z "$DATA_LAKE_BUCKET" ]]; then
  echo "Unable to determine data lake bucket from output location: $OUTPUT_LOCATION" >&2
  exit 1
fi

echo "  Data lake bucket: $DATA_LAKE_BUCKET"

bootstrap_athena_objects "$DATA_LAKE_BUCKET"

for sql_file in "${SQL_FILES[@]}"; do
  run_sql_file_statements "$sql_file"
done

echo "All dashboard SQL views applied successfully."