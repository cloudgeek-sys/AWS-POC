#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Assume one of the project persona IAM roles and emit shell exports.

Usage:
  eval "$(scripts/assume_persona_role.sh <persona>)"

Personas:
  data-engineer | de
  analyst       | an
  dashboard-user| dashboard | du

Options:
  --prefix <name>       Role name prefix (default: gppa-main)
  --account-id <id>     AWS account ID (default: from caller identity)
  --duration <seconds>  Session duration in seconds (default: 3600)
  --help                Show this help

Examples:
  eval "$(scripts/assume_persona_role.sh data-engineer)"
  eval "$(scripts/assume_persona_role.sh analyst --duration 7200)"
  eval "$(scripts/assume_persona_role.sh dashboard-user --prefix gppa-main)"
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PERSONA=""
PREFIX="gppa-main"
ACCOUNT_ID=""
DURATION="3600"

while [[ $# -gt 0 ]]; do
  case "$1" in
    data-engineer|de|analyst|an|dashboard-user|dashboard|du)
      if [[ -n "$PERSONA" ]]; then
        echo "Persona already provided: $PERSONA" >&2
        exit 1
      fi
      PERSONA="$1"
      shift
      ;;
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --account-id)
      ACCOUNT_ID="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
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

if [[ -z "$PERSONA" ]]; then
  echo "Persona is required." >&2
  usage
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required." >&2
  exit 1
fi

if [[ -z "$ACCOUNT_ID" ]]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
fi

case "$PERSONA" in
  data-engineer|de)
    ROLE_BASENAME="data-engineer-role"
    ROLE_LABEL="data-engineer"
    ;;
  analyst|an)
    ROLE_BASENAME="analyst-role"
    ROLE_LABEL="analyst"
    ;;
  dashboard-user|dashboard|du)
    ROLE_BASENAME="dashboard-user-role"
    ROLE_LABEL="dashboard-user"
    ;;
  *)
    echo "Unsupported persona: $PERSONA" >&2
    exit 1
    ;;
esac

ROLE_NAME="${PREFIX}-${ROLE_BASENAME}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
SESSION_NAME="${PREFIX}-${ROLE_LABEL}-$(date +%s)"

read -r ACCESS_KEY SECRET_KEY SESSION_TOKEN EXPIRATION <<< "$(
  aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "$SESSION_NAME" \
    --duration-seconds "$DURATION" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]' \
    --output text
)"

# Emit shell exports so caller can eval this script output in current shell.
echo "export AWS_ACCESS_KEY_ID='${ACCESS_KEY}'"
echo "export AWS_SECRET_ACCESS_KEY='${SECRET_KEY}'"
echo "export AWS_SESSION_TOKEN='${SESSION_TOKEN}'"
echo "export AWS_ROLE_ARN='${ROLE_ARN}'"
echo "export AWS_ROLE_SESSION_NAME='${SESSION_NAME}'"
echo "export AWS_PERSONA='${ROLE_LABEL}'"
echo "echo 'Assumed role ${ROLE_NAME} until ${EXPIRATION}' >&2"
