#!/usr/bin/env bash
set -euo pipefail

TF_ENV_DIR="${TF_ENV_DIR:-infra/terraform/environments/main}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
NAME_PREFIX="gppa-main"
REPORT_FILE="${SMOKE_REPORT_FILE:-}"
LAST_ERROR_MESSAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report-file)
      REPORT_FILE="$2"
      shift 2
      ;;
    --env-dir)
      TF_ENV_DIR="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: scripts/post_deploy_smoke_check.sh [name_prefix] [--report-file <path>] [--env-dir <terraform_env_dir>]

Examples:
  scripts/post_deploy_smoke_check.sh gppa-main
  scripts/post_deploy_smoke_check.sh gppa-main --report-file smoke-check-report-main.json
EOF
      exit 0
      ;;
    *)
      NAME_PREFIX="$1"
      shift
      ;;
  esac
done

WORKGROUP="$(terraform -chdir="$TF_ENV_DIR" output -raw athena_workgroup)"
BUCKET="$(terraform -chdir="$TF_ENV_DIR" output -raw data_lake_bucket)"
SFN_ARN="$(terraform -chdir="$TF_ENV_DIR" output -raw step_function_arn)"

DB="${ATHENA_DATABASE:-gppa_main_analytics}"
RESULTS="s3://${BUCKET}/athena/results/"

sfn_status="unknown"
code_count="0"
dataset_check="pending"
dashboard_check="pending"
power_generation_rows=""
plant_operations_rows=""
sustainability_rows=""
monitoring_rows=""
geographic_rows=""

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_report() {
  local overall_status="$1"
  local error_message="${2:-}"

  if [[ -z "$REPORT_FILE" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$REPORT_FILE")"

  cat > "$REPORT_FILE" <<EOF
{
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment_dir": "$(json_escape "$TF_ENV_DIR")",
  "name_prefix": "$(json_escape "$NAME_PREFIX")",
  "region": "$(json_escape "$AWS_REGION")",
  "account_id": "$(json_escape "$AWS_ACCOUNT_ID")",
  "bucket": "$(json_escape "$BUCKET")",
  "athena_database": "$(json_escape "$DB")",
  "athena_workgroup": "$(json_escape "$WORKGROUP")",
  "overall_status": "$(json_escape "$overall_status")",
  "error_message": "$(json_escape "$error_message")",
  "checks": {
    "step_functions_status": "$(json_escape "$sfn_status")",
    "glue_code_object_count": $code_count,
    "dataset_check": "$(json_escape "$dataset_check")",
    "dashboard_check": "$(json_escape "$dashboard_check")",
    "athena": {
      "power_generation_rows": "$(json_escape "$power_generation_rows")",
      "plant_operations_rows": "$(json_escape "$plant_operations_rows")",
      "sustainability_rows": "$(json_escape "$sustainability_rows")",
      "geographic_rows": "$(json_escape "$geographic_rows")",
      "monitoring_rows": "$(json_escape "$monitoring_rows")"
    }
  }
}
EOF

  echo "Smoke-check report written to ${REPORT_FILE}"
}

on_error() {
  local exit_code="$1"
  write_report "failed" "${LAST_ERROR_MESSAGE:-command failed with exit code ${exit_code}}"
  exit "$exit_code"
}

trap 'on_error $?' ERR

echo "Running post-deploy smoke checks"
echo "  Environment dir: $TF_ENV_DIR"
echo "  Region: $AWS_REGION"
echo "  Account: $AWS_ACCOUNT_ID"
echo "  Prefix: $NAME_PREFIX"

echo "[1/4] Step Functions state machine status"
sfn_status="$(aws stepfunctions describe-state-machine --state-machine-arn "$SFN_ARN" --query 'status' --output text)"
aws stepfunctions describe-state-machine \
  --state-machine-arn "$SFN_ARN" \
  --query '{name:name,status:status}' \
  --output json
if [[ "$sfn_status" != "ACTIVE" ]]; then
  LAST_ERROR_MESSAGE="state machine status is ${sfn_status}, expected ACTIVE"
  exit 1
fi

echo "[2/4] Glue code uploaded to S3"
code_count="$(aws s3 ls "s3://${BUCKET}/code/pipelines/" --recursive | wc -l | tr -d ' ')"
if [[ "$code_count" -eq 0 ]]; then
  LAST_ERROR_MESSAGE="no pipeline code found under s3://${BUCKET}/code/pipelines/"
  echo "ERROR: no pipeline code found under s3://${BUCKET}/code/pipelines/" >&2
  exit 1
fi
echo "  OK: ${code_count} objects under code/pipelines"

echo "[3/4] QuickSight required datasets and dashboards"

mapfile -t qs_datasets < <(
  aws quicksight list-data-sets \
    --aws-account-id "$AWS_ACCOUNT_ID" \
    --region "$AWS_REGION" \
    --query 'DataSetSummaries[].Name' \
    --output text | tr '\t' '\n' | sed '/^$/d'
)

mapfile -t qs_dashboards < <(
  aws quicksight list-dashboards \
    --aws-account-id "$AWS_ACCOUNT_ID" \
    --region "$AWS_REGION" \
    --query 'DashboardSummaryList[].Name' \
    --output text | tr '\t' '\n' | sed '/^$/d'
)

required_datasets=(
  "${NAME_PREFIX}-power_generation_country_capacity-dataset"
  "${NAME_PREFIX}-power_generation_fuel_distribution-dataset"
  "${NAME_PREFIX}-power_generation_renewable_trends-dataset"
  "${NAME_PREFIX}-power_generation_global_fuel_dominance-dataset"
  "${NAME_PREFIX}-power_generation_annual_generation_trends-dataset"
  "${NAME_PREFIX}-power_generation_kpi_summary-dataset"
  "${NAME_PREFIX}-plant_largest_plants-dataset"
  "${NAME_PREFIX}-plant_aging_plants-dataset"
  "${NAME_PREFIX}-plant_utilization-dataset"
  "${NAME_PREFIX}-plant_underutilized_plants-dataset"
  "${NAME_PREFIX}-plant_aging_by_region-dataset"
  "${NAME_PREFIX}-sustainability_heatmap-dataset"
  "${NAME_PREFIX}-sustainability_clean_energy_growth-dataset"
  "${NAME_PREFIX}-sustainability_coal_dependency-dataset"
  "${NAME_PREFIX}-sustainability_country_distribution-dataset"
  "${NAME_PREFIX}-sustainability_regional_density-dataset"
  "${NAME_PREFIX}-geographic_heatmap_points-dataset"
  "${NAME_PREFIX}-geographic_generation_density-dataset"
  "${NAME_PREFIX}-geographic_country_infrastructure_density-dataset"
  "${NAME_PREFIX}-monitoring_pipeline_freshness-dataset"
  "${NAME_PREFIX}-monitoring_failed_jobs-dataset"
  "${NAME_PREFIX}-monitoring_data_quality-dataset"
  "${NAME_PREFIX}-monitoring_dq_failure_breakdown-dataset"
  "${NAME_PREFIX}-monitoring_dq_failure_breakdown_latest-dataset"
  "${NAME_PREFIX}-monitoring_latency-dataset"
  "${NAME_PREFIX}-monitoring_duplicate_plants-dataset"
  "${NAME_PREFIX}-monitoring_missing_or_inconsistent_generation-dataset"
)

for ds in "${required_datasets[@]}"; do
  if ! printf '%s\n' "${qs_datasets[@]}" | grep -Fxq "$ds"; then
    dataset_check="failed"
    LAST_ERROR_MESSAGE="missing required dataset: ${ds}"
    echo "ERROR: missing required dataset: $ds" >&2
    exit 1
  fi
done
dataset_check="passed"

coverage_labels=("power generation" "plant operations" "sustainability" "geographic" "monitoring")
for label in "${coverage_labels[@]}"; do
  if ! printf '%s\n' "${qs_dashboards[@]}" | grep -Eiq "$label"; then
    dashboard_check="failed"
    LAST_ERROR_MESSAGE="missing dashboard coverage for ${label}"
    echo "ERROR: missing dashboard coverage for '${label}'." >&2
    echo "Found dashboards:" >&2
    printf '  - %s\n' "${qs_dashboards[@]}" >&2
    exit 1
  fi
done
dashboard_check="passed"

echo "  OK: required datasets present"
echo "  OK: dashboard coverage present (power generation, plant operations, sustainability, geographic, monitoring)"

run_athena_check() {
  local query="$1"
  local label="$2"
  local out_var="$3"

  local qid
  qid="$(aws athena start-query-execution \
    --region "$AWS_REGION" \
    --work-group "$WORKGROUP" \
    --query-execution-context "Database=$DB" \
    --result-configuration "OutputLocation=$RESULTS" \
    --query-string "$query" \
    --query 'QueryExecutionId' \
    --output text)"

  while true; do
    local state
    state="$(aws athena get-query-execution \
      --region "$AWS_REGION" \
      --query-execution-id "$qid" \
      --query 'QueryExecution.Status.State' \
      --output text)"

    case "$state" in
      SUCCEEDED)
        local value
        value="$(aws athena get-query-results \
          --region "$AWS_REGION" \
          --query-execution-id "$qid" \
          --query 'ResultSet.Rows[1].Data[0].VarCharValue' \
          --output text)"
        printf -v "$out_var" '%s' "$value"
        echo "  OK: ${label} -> ${value}"
        return 0
        ;;
      FAILED|CANCELLED)
        local reason
        reason="$(aws athena get-query-execution \
          --region "$AWS_REGION" \
          --query-execution-id "$qid" \
          --query 'QueryExecution.Status.StateChangeReason' \
          --output text)"
        LAST_ERROR_MESSAGE="${label} check failed: ${reason}"
        echo "ERROR: ${label} check failed: ${reason}" >&2
        return 1
        ;;
      *)
        sleep 2
        ;;
    esac
  done
}

echo "[4/4] Athena dashboard-view smoke checks"
run_athena_check "SELECT count(*) FROM vw_power_generation_country_capacity" "Power Generation view" power_generation_rows
run_athena_check "SELECT count(*) FROM vw_power_generation_fuel_distribution" "Power Generation fuel distribution view" power_generation_rows
run_athena_check "SELECT count(*) FROM vw_power_generation_renewable_trend" "Power Generation renewable trend view" power_generation_rows
run_athena_check "SELECT count(*) FROM vw_power_generation_global_fuel_dominance" "Power Generation global fuel dominance view" power_generation_rows
run_athena_check "SELECT count(*) FROM vw_power_generation_annual_generation_trends" "Power Generation annual generation trend view" power_generation_rows
run_athena_check "SELECT count(*) FROM vw_power_generation_kpi_summary" "Power Generation KPI summary view" power_generation_rows
run_athena_check "SELECT count(*) FROM vw_plant_operations_largest_plants" "Plant Operations view" plant_operations_rows
run_athena_check "SELECT count(*) FROM vw_plant_operations_aging_infrastructure" "Plant Operations aging view" plant_operations_rows
run_athena_check "SELECT count(*) FROM vw_plant_operations_capacity_utilization" "Plant Operations utilization view" plant_operations_rows
run_athena_check "SELECT count(*) FROM vw_plant_operations_underutilized_plants" "Plant Operations underutilized plants view" plant_operations_rows
run_athena_check "SELECT count(*) FROM vw_plant_operations_aging_by_region" "Plant Operations aging by region view" plant_operations_rows
run_athena_check "SELECT count(*) FROM vw_sustainability_regional_density" "Sustainability view" sustainability_rows
run_athena_check "SELECT count(*) FROM vw_sustainability_clean_energy_growth" "Sustainability renewable adoption view" sustainability_rows
run_athena_check "SELECT count(*) FROM vw_sustainability_coal_dependency" "Sustainability coal dependency view" sustainability_rows
run_athena_check "SELECT count(*) FROM vw_sustainability_heatmap" "Geographic heatmap view" geographic_rows
run_athena_check "SELECT count(*) FROM vw_geographic_heatmap_points" "Geographic heatmap points view" geographic_rows
run_athena_check "SELECT count(*) FROM vw_geographic_country_infrastructure_density" "Geographic country distribution view" geographic_rows
run_athena_check "SELECT count(*) FROM vw_geographic_generation_density" "Geographic regional density view" geographic_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_latency" "Monitoring view" monitoring_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_pipeline_freshness" "Monitoring freshness view" monitoring_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_failed_jobs" "Monitoring failed ingestion jobs view" monitoring_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_data_quality" "Monitoring data quality alerts view" monitoring_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_dq_failure_breakdown" "Monitoring DQ failure breakdown view" monitoring_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_dq_failure_breakdown_latest" "Monitoring DQ failure latest snapshot view" monitoring_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_duplicate_plants" "Monitoring duplicate plant entries view" monitoring_rows
run_athena_check "SELECT count(*) FROM vw_monitoring_missing_or_inconsistent_generation" "Monitoring missing or inconsistent generation view" monitoring_rows

echo "Post-deploy smoke checks passed."
write_report "passed" ""
