#!/usr/bin/env bash
# Scaffold a new HTTP API from services/example-api.
# Then in TeamCity: point settings.kts serviceName at it and Run "create (dev)".
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:-${NAME:-}}"
if [[ -z "$NAME" ]]; then
  echo "usage: $0 <service-name>   (lowercase, DNS-safe, e.g. orders-api)" >&2
  exit 1
fi
if [[ ! "$NAME" =~ ^[a-z][a-z0-9-]{1,30}[a-z0-9]$ ]]; then
  echo "service name must be 3-32 chars, start with a letter, lowercase alphanumeric plus hyphens" >&2
  exit 1
fi
SRC="$ROOT/services/example-api"
DST="$ROOT/services/$NAME"
if [[ -e "$DST" ]]; then
  echo "already exists: $DST" >&2
  exit 1
fi

cp -a "$SRC" "$DST"
find "$DST" -type f -print0 | xargs -0 sed -i "s/example-api/${NAME}/g"

add_ecr() {
  local f="$1"
  grep -q "\"$NAME\"" "$f" && return 0
  # Insert ", \"name\"" before the closing ] of ecr_repositories = [...]
  sed -i "s/ecr_repositories[[:space:]]*=[[:space:]]*\\[\\(.*\\)\\]/ecr_repositories     = [\\1, \"$NAME\"]/" "$f"
}

for env in dev staging prod; do
  add_ecr "$ROOT/platform/envs/$env/terraform.tfvars"
done

echo "scaffolded $DST"
echo "next:"
echo "  1. set serviceName = \"$NAME\" in .teamcity/settings.kts (or a copied TeamCity project)"
echo "  2. commit"
echo "  3. Run the one-click build: create (dev)"
