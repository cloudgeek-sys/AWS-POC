#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
NAME_PREFIX="${1:-gppa-main}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for dataset refresh automation." >&2
  exit 1
fi

echo "Refreshing QuickSight datasets in account ${ACCOUNT_ID}, region ${AWS_REGION}, prefix ${NAME_PREFIX}"

mapfile -t DATASET_IDS < <(
  aws quicksight list-data-sets \
    --aws-account-id "${ACCOUNT_ID}" \
    --region "${AWS_REGION}" \
    --query "DataSetSummaries[?starts_with(Name, '${NAME_PREFIX}-')].DataSetId" \
    --output text | tr '\t' '\n' | sed '/^$/d'
)

if [[ "${#DATASET_IDS[@]}" -eq 0 ]]; then
  echo "No datasets found for prefix ${NAME_PREFIX}; nothing to refresh."
  exit 0
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

for dataset_id in "${DATASET_IDS[@]}"; do
  echo "- Processing dataset ${dataset_id}"

  describe_json="${tmp_dir}/${dataset_id}.json"
  aws quicksight describe-data-set \
    --aws-account-id "${ACCOUNT_ID}" \
    --data-set-id "${dataset_id}" \
    --region "${AWS_REGION}" >"${describe_json}"

  name="$(jq -r '.DataSet.Name' "${describe_json}")"
  import_mode="$(jq -r '.DataSet.ImportMode' "${describe_json}")"

  if [[ "${import_mode}" == "SPICE" ]]; then
    ingestion_id="postdeploy-$(date +%s)-${dataset_id}"
    echo "  Triggering SPICE ingestion ${ingestion_id}"
    aws quicksight create-ingestion \
      --aws-account-id "${ACCOUNT_ID}" \
      --data-set-id "${dataset_id}" \
      --ingestion-id "${ingestion_id}" \
      --region "${AWS_REGION}" >/dev/null
    continue
  fi

  physical_table_map_file="${tmp_dir}/${dataset_id}-physical.json"
  logical_table_map_file="${tmp_dir}/${dataset_id}-logical.json"

  jq '.DataSet.PhysicalTableMap' "${describe_json}" >"${physical_table_map_file}"
  jq '.DataSet.LogicalTableMap // {}' "${describe_json}" >"${logical_table_map_file}"

  if [[ "$(jq -r 'length' "${logical_table_map_file}")" -gt 0 ]]; then
    aws quicksight update-data-set \
      --aws-account-id "${ACCOUNT_ID}" \
      --data-set-id "${dataset_id}" \
      --name "${name}" \
      --import-mode "${import_mode}" \
      --physical-table-map "file://${physical_table_map_file}" \
      --logical-table-map "file://${logical_table_map_file}" \
      --region "${AWS_REGION}" >/dev/null
  else
    aws quicksight update-data-set \
      --aws-account-id "${ACCOUNT_ID}" \
      --data-set-id "${dataset_id}" \
      --name "${name}" \
      --import-mode "${import_mode}" \
      --physical-table-map "file://${physical_table_map_file}" \
      --region "${AWS_REGION}" >/dev/null
  fi

  echo "  Refreshed DIRECT_QUERY dataset metadata"
done

echo "QuickSight dataset refresh completed."
