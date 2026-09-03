#!/usr/bin/env bash
# Code apply / rollback: current checkout Terraform + an explicit digest.
# Always a new task-definition revision. Never family:N of an old revision.
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

terraform -chdir="$S" apply -input=false -no-color tfplan-code

print_alb "$S"
