#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/upload_glue_code.sh --bucket <s3-bucket> [--prefix code/pipelines] [--repo-root .]
  scripts/upload_glue_code.sh --env-dir <terraform-env-dir> [--prefix code/pipelines] [--repo-root .]

Examples:
  scripts/upload_glue_code.sh --bucket my-gppa-lake-bucket
  scripts/upload_glue_code.sh --env-dir infra/terraform/environments/main
EOF
}

BUCKET=""
PREFIX="code/pipelines"
REPO_ROOT="."
ENV_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET="$2"
      shift 2
      ;;
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    --env-dir)
      ENV_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$BUCKET" && -z "$ENV_DIR" ]]; then
  echo "Either --bucket or --env-dir is required." >&2
  usage
  exit 1
fi

if [[ -z "$BUCKET" ]]; then
  if ! command -v terraform >/dev/null 2>&1; then
    echo "terraform is required when using --env-dir." >&2
    exit 1
  fi
  BUCKET="$(terraform -chdir="$ENV_DIR" output -raw data_lake_bucket)"
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required." >&2
  exit 1
fi

TARGET_URI="s3://${BUCKET}/${PREFIX}"
SOURCE_DIR="${REPO_ROOT}/pipelines"
SAMPLES_DIR="${REPO_ROOT}/samples"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Pipelines directory not found: $SOURCE_DIR" >&2
  exit 1
fi

echo "Uploading Glue pipeline code from ${SOURCE_DIR} to ${TARGET_URI}"
aws s3 sync "$SOURCE_DIR" "$TARGET_URI" \
  --exclude "*/__pycache__/*" \
  --exclude "tests/*" \
  --exclude "*.pyc"

if [[ -d "$SAMPLES_DIR" ]]; then
  echo "Uploading sample source data from ${SAMPLES_DIR} to s3://${BUCKET}/samples"
  aws s3 sync "$SAMPLES_DIR" "s3://${BUCKET}/samples" \
    --exclude "*/__pycache__/*" \
    --exclude "*.pyc"
fi

if command -v zip >/dev/null 2>&1; then
  BUNDLE_PATH="/tmp/pipelines_bundle.zip"
  rm -f "$BUNDLE_PATH"
  (
    cd "$REPO_ROOT"
    zip -rq "$BUNDLE_PATH" pipelines \
      -x "*/__pycache__/*" \
      -x "pipelines/tests/*" \
      -x "*.pyc"
  )
  echo "Uploading Python dependency bundle to s3://${BUCKET}/code/pipelines_bundle.zip"
  aws s3 cp "$BUNDLE_PATH" "s3://${BUCKET}/code/pipelines_bundle.zip"
else
  echo "zip command not found; skipping pipelines_bundle.zip upload" >&2
fi

echo "Upload complete."
