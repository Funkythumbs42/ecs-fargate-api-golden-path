#!/usr/bin/env bash
# Offline-ish checks: docker build of the app template + terraform fmt/validate
# of factory modules and platform roots. Template env roots use a git module
# source; we rewrite that to the local modules/ecs-api for validate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${REPO_HOST_PATH:-$ROOT}"
TF_VERSION="${TF_VERSION:-1.9.8}"
IMAGE="${IMAGE:-example-api}"
TAG="${TAG:-local}"

if [[ ! -f "$ROOT/templates/service-api/Dockerfile" ]]; then
  echo "cannot find templates/service-api/Dockerfile under $ROOT" >&2
  exit 1
fi

tf() {
  if command -v terraform >/dev/null 2>&1; then
    terraform "$@"
  else
    docker run --rm -v "$ROOT:$ROOT" -w "$ROOT" "hashicorp/terraform:${TF_VERSION}" "$@"
  fi
}

echo "==> docker build ${IMAGE}:${TAG} (templates/service-api)"
docker build \
  --build-arg VERSION="$TAG" \
  --build-arg SERVICE_NAME="$IMAGE" \
  -t "${IMAGE}:${TAG}" \
  "$ROOT/templates/service-api"

echo "==> terraform fmt -recursive -check"
tf -chdir="$ROOT" fmt -recursive -check

TF_DIRS=(
  modules/ecs-api
  modules/platform
  platform/envs/dev
  platform/envs/staging
  platform/envs/prod
)

for d in "${TF_DIRS[@]}"; do
  echo "==> validate $d"
  tf -chdir="$ROOT/$d" init -backend=false -input=false -no-color
  tf -chdir="$ROOT/$d" validate -no-color
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -a "$ROOT/templates/service-api/envs" "$TMP/envs"
find "$TMP/envs" -name main.tf -print0 | xargs -0 sed -i \
  "s#source = \"git::https://github.com/Funkythumbs42/ecs-fargate-api-golden-path.git//modules/ecs-api?ref=main\"#source = \"${ROOT}/modules/ecs-api\"#"

for env in dev staging prod; do
  echo "==> validate template envs/$env (local module source)"
  tf -chdir="$TMP/envs/$env" init -backend=false -input=false -no-color
  tf -chdir="$TMP/envs/$env" validate -no-color
done

echo "local-checks: ok"
