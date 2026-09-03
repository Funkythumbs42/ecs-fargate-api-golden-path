#!/usr/bin/env bash
# Factory: plan shared platform for DEPLOY_ENV.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tf-common.sh
source "$ROOT/scripts/tf-common.sh"

: "${DEPLOY_ENV:?}"

aws sts get-caller-identity >/dev/null

P="$(platform_root)"
tf_init "$P"
terraform -chdir="$P" plan -input=false -no-color -out=tfplan-platform
