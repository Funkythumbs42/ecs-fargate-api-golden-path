#!/usr/bin/env bash
# Factory: apply shared platform (VPC, NAT, cluster, ECR) for DEPLOY_ENV.
# Does not apply any app. Apps own their ALB in their repo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tf-common.sh
source "$ROOT/scripts/tf-common.sh"

: "${DEPLOY_ENV:?}"

aws sts get-caller-identity >/dev/null

P="$(platform_root)"
tf_init "$P"
terraform -chdir="$P" apply -input=false -no-color -auto-approve
