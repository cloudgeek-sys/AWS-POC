#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
NAME_PREFIX="${1:-gppa-main}"

required_datasets=(
  "${NAME_PREFIX}-power_generation_country_capacity-dataset"
  "${NAME_PREFIX}-power_generation_fuel_distribution-dataset"
  "${NAME_PREFIX}-power_generation_renewable_trends-dataset"
  "${NAME_PREFIX}-plant_largest_plants-dataset"
  "${NAME_PREFIX}-plant_aging_plants-dataset"
  "${NAME_PREFIX}-plant_utilization-dataset"
  "${NAME_PREFIX}-sustainability_heatmap-dataset"
  "${NAME_PREFIX}-sustainability_clean_energy_growth-dataset"
  "${NAME_PREFIX}-sustainability_coal_dependency-dataset"
  "${NAME_PREFIX}-sustainability_country_distribution-dataset"
  "${NAME_PREFIX}-sustainability_regional_density-dataset"
  "${NAME_PREFIX}-geographic_generation_density-dataset"
  "${NAME_PREFIX}-geographic_country_infrastructure_density-dataset"
  "${NAME_PREFIX}-monitoring_pipeline_freshness-dataset"
  "${NAME_PREFIX}-monitoring_failed_jobs-dataset"
  "${NAME_PREFIX}-monitoring_data_quality-dataset"
  "${NAME_PREFIX}-monitoring_latency-dataset"
)

required_dashboard_labels=(
  "power generation"
  "plant operations"
  "sustainability"
  "geographic"
  "monitoring"
)

echo "Checking QuickSight assets in account ${ACCOUNT_ID}, region ${AWS_REGION}, prefix ${NAME_PREFIX}"

dataset_output="$(mktemp)"
dashboard_output="$(mktemp)"

if ! aws quicksight list-data-sets \
  --aws-account-id "${ACCOUNT_ID}" \
  --region "${AWS_REGION}" \
  --query 'DataSetSummaries[].Name' \
  --output text >"${dataset_output}" 2>&1; then
  echo "QuickSight validation blocked: unable to list datasets."
  cat "${dataset_output}"
  rm -f "${dataset_output}" "${dashboard_output}"
  exit 3
fi

if ! aws quicksight list-dashboards \
  --aws-account-id "${ACCOUNT_ID}" \
  --region "${AWS_REGION}" \
  --query 'DashboardSummaryList[].Name' \
  --output text >"${dashboard_output}" 2>&1; then
  echo "QuickSight validation blocked: unable to list dashboards."
  cat "${dashboard_output}"
  rm -f "${dataset_output}" "${dashboard_output}"
  exit 3
fi

mapfile -t existing_datasets < <(cat "${dataset_output}" | tr '\t' '\n' | sed '/^$/d')
mapfile -t existing_dashboards < <(cat "${dashboard_output}" | tr '\t' '\n' | sed '/^$/d')
rm -f "${dataset_output}" "${dashboard_output}"

missing=0

echo "\nRequired datasets:"
for ds in "${required_datasets[@]}"; do
  if printf '%s\n' "${existing_datasets[@]}" | grep -Fxq "$ds"; then
    echo "  OK  $ds"
  else
    echo "  MISSING  $ds"
    missing=1
  fi
done

echo "\nRequired dashboard coverage labels:"
for label in "${required_dashboard_labels[@]}"; do
  if printf '%s\n' "${existing_dashboards[@]}" | grep -Eiq "$label"; then
    echo "  OK  $label"
  else
    echo "  MISSING  $label"
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo "\nQuickSight validation failed: missing required assets."
  exit 2
fi

echo "\nQuickSight validation passed: all required assets are present."
