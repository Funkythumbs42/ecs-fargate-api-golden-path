#!/usr/bin/env bash
# Infra apply: platform then service, preserving the running image digest.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tf-common.sh
source "$ROOT/scripts/tf-common.sh"

: "${SERVICE_NAME:?}"
: "${DEPLOY_ENV:?}"

aws sts get-caller-identity >/dev/null

P="$(platform_root)"
S="$(service_root)"

tf_init "$P"
terraform -chdir="$P" apply -input=false -no-color -auto-approve

tf_init "$S"
CURRENT="$(state_digest "$S")"
if [[ -z "$CURRENT" ]]; then
  CURRENT="$(require_digest)"
  echo "first infra apply for $S; bootstrapping image $CURRENT"
else
  CURRENT="$(normalize_digest "$CURRENT")"
  echo "preserving running digest $CURRENT"
fi

terraform -chdir="$S" apply -input=false -no-color -auto-approve \
  -var="image_digest=${CURRENT}"
