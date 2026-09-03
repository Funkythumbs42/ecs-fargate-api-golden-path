#!/usr/bin/env bash
# From-nothing factory. Called by TeamCity "new-api" (or make inception).
# Renders the app template into a temp dir, creates/attaches a GitHub repo,
# registers a TeamCity project whose VCS root is THAT repo, and records a
# pointer + ECR name in this factory. Does not copy the app into services/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NAME="${1:-${NEW_NAME:-}}"
PORT="${2:-${NEW_PORT:-8080}}"
PRESET="${3:-${NEW_PRESET:-small}}"
HOST="${4:-${NEW_HOST:-}}"
GIT_MODE="${5:-${GIT_MODE:-create}}"
GIT_REPO="${6:-${GIT_REPO:-}}"
ALB_INTERNAL="${7:-${ALB_INTERNAL:-false}}"

# shellcheck source=inception-normalize.sh
source "$ROOT/scripts/inception-normalize.sh"

if [[ -z "$NAME" ]]; then
  echo "usage: $0 <service-name> [port] [small|medium|large] [host-hint] [create|existing] [owner/name-or-url] [false|true]" >&2
  exit 1
fi
if [[ ! "$PRESET" =~ ^(small|medium|large)$ ]]; then
  echo "preset must be small|medium|large" >&2
  exit 1
fi
if [[ ! "$ALB_INTERNAL" =~ ^(true|false)$ ]]; then
  echo "alb_internal must be true or false (true = internal ALB, false = internet-facing)" >&2
  exit 1
fi
if [[ "$GIT_MODE" == "this-repo" ]]; then
  echo "git.mode=this-repo is not the product path. Use create (default) or existing." >&2
  exit 1
fi

DEST="$(mktemp -d "/tmp/factory-${NAME}.XXXXXX")"
cleanup() { rm -rf "$DEST"; }
trap cleanup EXIT

echo "==> scaffold $NAME into temp dir (template: templates/service-api)"
"$ROOT/scripts/new-service.sh" "$NAME" "$DEST"

echo "==> tfvars port=$PORT preset=$PRESET alb_internal=$ALB_INTERNAL"
for env in dev staging prod; do
  f="$DEST/envs/$env/terraform.tfvars"
  sed -i "s/^container_port.*/container_port         = ${PORT}/" "$f"
  sed -i "s/^cpu_mem_preset.*/cpu_mem_preset         = \"${PRESET}\"/" "$f"
  sed -i "s/^alb_internal.*/alb_internal           = ${ALB_INTERNAL}/" "$f"
done

if [[ -n "$HOST" ]]; then
  echo "Suggested DNS / CNAME for the dedicated ALB: $HOST" >> "$DEST/README.md"
  echo "==> host hint recorded in app README (ALB is dedicated; no Host-header rule)"
fi

add_ecr() {
  local f="$1"
  grep -q "\"$NAME\"" "$f" && return 0
  sed -i "s/ecr_repositories[[:space:]]*=[[:space:]]*\\[\\(.*\\)\\]/ecr_repositories     = [\\1, \"$NAME\"]/" "$f"
}
for env in dev staging prod; do
  add_ecr "$ROOT/platform/envs/$env/terraform.tfvars"
done

echo "==> docker build ${NAME}:inception (verify Dockerfile)"
if command -v docker >/dev/null; then
  docker build \
    --build-arg VERSION="inception" \
    --build-arg SERVICE_NAME="$NAME" \
    -t "${NAME}:inception" \
    "$DEST"
else
  echo "docker not on PATH; skip local image build"
fi

export ROOT NAME DEST GIT_MODE GIT_REPO
APP_GIT_URL="$(bash "$ROOT/scripts/service-git.sh" | tail -n1)"
export APP_GIT_URL
echo "==> app repo: $APP_GIT_URL"

echo "==> register TeamCity project for the app repo"
# Inside a TeamCity build these %...% params are expanded by the Kotlin step.
# Locally: export TEAMCITY_URL / TEAMCITY_TOKEN (never commit them).
export NAME APP_GIT_URL
bash "$ROOT/scripts/register-teamcity.sh"

if command -v git >/dev/null && [[ -d "$ROOT/.git" || "${INCEPTION_GIT:-}" == "1" ]]; then
  if [[ ! -d "$ROOT/.git" ]]; then
    git init -b main
    git add -A
    git -c user.email="factory@example.invalid" -c user.name="api-factory" \
      commit -m "factory: initial" || true
  fi
  git add .teamcity/services.list platform/envs/*/terraform.tfvars
  if ! git diff --cached --quiet; then
    git -c user.email="factory@example.invalid" -c user.name="api-factory" \
      commit -m "factory: register ${NAME} (ECR + app pointer)"
    echo "==> committed factory pointer + ECR name for $NAME"
  fi
fi

echo
echo "inception ok: service=$NAME image=${NAME}:inception repo=${APP_GIT_URL}"
echo "App files were NOT copied into factory services/."
echo "First AWS deploy: after TeamCity loads the app .teamcity, Run '${NAME} / create (dev)'."
echo "That build checks out the APP repo, pushes a digest, and applies envs/dev (dedicated ALB)."
echo "If ECR does not exist yet, Run factory 'platform apply (dev)' once so the new repository is created."
if [[ "$ALB_INTERNAL" == "true" ]]; then
  echo "ALB: internal (private subnets). Curl from inside the VPC."
else
  echo "ALB: internet-facing (public subnets). create/ship prints alb_dns_name; no Host header."
fi
