#!/usr/bin/env bash
# From-nothing factory. Called by TeamCity "new-api" (or make inception).
# Creates the service files, registers it in the factory DSL list, builds
# the first image, and commits so TeamCity can load the new pipelines.
# Terraform apply / ECR push run only when AWS creds are real; the
# placeholder account in this example will not be applied.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NAME="${1:-${NEW_NAME:-}}"
PORT="${2:-${NEW_PORT:-8080}}"
PRESET="${3:-${NEW_PRESET:-small}}"
HOST="${4:-${NEW_HOST:-}}"

if [[ -z "$NAME" ]]; then
  echo "usage: $0 <service-name> [port] [small|medium|large] [host-header]" >&2
  exit 1
fi
if [[ ! "$PRESET" =~ ^(small|medium|large)$ ]]; then
  echo "preset must be small|medium|large" >&2
  exit 1
fi
if [[ -z "$HOST" ]]; then
  HOST="${NAME}.dev.example.invalid"
fi

echo "==> scaffold $NAME"
"$ROOT/scripts/new-service.sh" "$NAME"

echo "==> tfvars port=$PORT preset=$PRESET host=$HOST"
for env in dev staging prod; do
  f="$ROOT/services/$NAME/envs/$env/terraform.tfvars"
  sed -i "s/^container_port.*/container_port         = ${PORT}/" "$f"
  sed -i "s/^cpu_mem_preset.*/cpu_mem_preset         = \"${PRESET}\"/" "$f"
done
# Host header is per-env; keep env in the hostname.
sed -i "s/^host_header.*/host_header            = \"${NAME}.dev.example.invalid\"/" \
  "$ROOT/services/$NAME/envs/dev/terraform.tfvars"
sed -i "s/^host_header.*/host_header            = \"${NAME}.staging.example.invalid\"/" \
  "$ROOT/services/$NAME/envs/staging/terraform.tfvars"
sed -i "s/^host_header.*/host_header            = \"${NAME}.example.invalid\"/" \
  "$ROOT/services/$NAME/envs/prod/terraform.tfvars"
if [[ -n "${4:-}" ]]; then
  sed -i "s/^host_header.*/host_header            = \"${HOST}\"/" \
    "$ROOT/services/$NAME/envs/dev/terraform.tfvars"
fi

LIST="$ROOT/.teamcity/services.list"
touch "$LIST"
if ! grep -qx "$NAME" "$LIST"; then
  echo "$NAME" >> "$LIST"
  echo "==> registered $NAME in .teamcity/services.list"
fi

echo "==> docker build ${NAME}:inception"
docker build \
  --build-arg VERSION="inception" \
  --build-arg SERVICE_NAME="$NAME" \
  -t "${NAME}:inception" \
  "$ROOT/services/$NAME"

DIGEST_FILE="$ROOT/services/$NAME/.inception-image-digest"
if docker image inspect "${NAME}:inception" --format '{{.Id}}' > /tmp/img-id 2>/dev/null; then
  echo "local image ${NAME}:inception id=$(cat /tmp/img-id)"
fi

if command -v git >/dev/null && [[ -d "$ROOT/.git" || "${INCEPTION_GIT:-}" == "1" ]]; then
  if [[ ! -d "$ROOT/.git" ]]; then
    git init -b main
    git add -A
    git -c user.email="factory@example.invalid" -c user.name="api-factory" \
      commit -m "factory: initial" || true
  fi
  git add "services/$NAME" .teamcity/services.list platform/envs/*/terraform.tfvars
  if ! git diff --cached --quiet; then
    git -c user.email="factory@example.invalid" -c user.name="api-factory" \
      commit -m "factory: add ${NAME}"
    echo "==> committed so TeamCity versioned settings can load pipelines for $NAME"
  fi
fi

if aws sts get-caller-identity >/dev/null 2>&1; then
  ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
  if [[ "$ACCOUNT" == "123456789012" ]]; then
    echo "==> AWS is the placeholder account; skip apply"
  else
    echo "==> AWS account $ACCOUNT: first create (platform ECR + service)"
    export SERVICE_NAME="$NAME"
    export DEPLOY_ENV="${DEPLOY_ENV:-dev}"
    # Real accounts must already have backend.hcl and IDs patched.
    bash "$ROOT/scripts/infra-apply.sh"
  fi
else
  echo "==> no AWS creds; files + image + pipelines are in place"
  echo "    with real account IDs, this same job runs infra-apply after ECR exists"
fi

echo "inception ok: service=$NAME image=${NAME}:inception"
echo "after TeamCity reloads versioned settings, ship/promote/rollback exist under $NAME"
echo "first AWS deploy: Run '$NAME / create (dev)' or re-run this job with creds"
