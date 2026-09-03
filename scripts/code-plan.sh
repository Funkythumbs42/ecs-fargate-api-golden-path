#!/usr/bin/env bash
# Code plan: service root only, required IMAGE_DIGEST, fail if the plan
# touches anything other than task definition / ECS service.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tf-common.sh
source "$ROOT/scripts/tf-common.sh"

: "${SERVICE_NAME:?}"
: "${DEPLOY_ENV:?}"

aws sts get-caller-identity >/dev/null

S="$(service_root)"
DIGEST="$(require_digest)"
tf_init "$S"

terraform -chdir="$S" plan -input=false -no-color \
  -var="image_digest=${DIGEST}" \
  -out=tfplan-code

terraform -chdir="$S" show -json tfplan-code \
  | python3 "$ROOT/scripts/assert-code-plan.py"
