#!/usr/bin/env bash
# Offline-ish checks: docker build + terraform fmt/validate.
# No ECR push, no terraform apply, no AWS API calls (validate may download
# the hashicorp/aws provider). Used by `make local-checks` and the TeamCity
# "local-checks" build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${REPO_HOST_PATH:-$ROOT}"
TF_VERSION="${TF_VERSION:-1.9.8}"
IMAGE="${IMAGE:-example-api}"
TAG="${TAG:-local}"

if [[ ! -f "$ROOT/services/example-api/Dockerfile" ]]; then
  echo "cannot find services/example-api/Dockerfile under $ROOT" >&2
  exit 1
fi

tf() {
  if command -v terraform >/dev/null 2>&1; then
    terraform "$@"
  else
    # Sibling container on the host daemon; ROOT must be a host path.
    docker run --rm -v "$ROOT:$ROOT" -w "$ROOT" "hashicorp/terraform:${TF_VERSION}" "$@"
  fi
}

echo "==> docker build ${IMAGE}:${TAG}"
docker build   --build-arg VERSION="$TAG"   --build-arg SERVICE_NAME="$IMAGE"   -t "${IMAGE}:${TAG}"   "$ROOT/services/example-api"

echo "==> terraform fmt -recursive -check"
tf -chdir="$ROOT" fmt -recursive -check

TF_DIRS=(
  modules/ecs-api
  modules/platform
  platform/envs/dev
  platform/envs/staging
  platform/envs/prod
  services/example-api/envs/dev
  services/example-api/envs/staging
  services/example-api/envs/prod
)

for d in "${TF_DIRS[@]}"; do
  echo "==> validate $d"
  tf -chdir="$ROOT/$d" init -backend=false -input=false -no-color
  tf -chdir="$ROOT/$d" validate -no-color
done

echo "local-checks: ok"
