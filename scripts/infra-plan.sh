#!/usr/bin/env bash
# Infra plan: platform first, then service. Image comes from STATE (or
# IMAGE_DIGEST only on first create). Never from a freshly built image
# unless this is the first apply of the service.
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
terraform -chdir="$P" plan -input=false -no-color -out=tfplan-platform

tf_init "$S"
CURRENT="$(state_digest "$S")"
if [[ -z "$CURRENT" ]]; then
  CURRENT="$(require_digest)"
  echo "first infra apply for $S; bootstrapping image $CURRENT"
else
  CURRENT="$(normalize_digest "$CURRENT")"
  echo "preserving running digest $CURRENT"
fi

terraform -chdir="$S" plan -input=false -no-color \
  -var="image_digest=${CURRENT}" \
  -out=tfplan-service
