#!/usr/bin/env bash
# Render templates/service-api into a destination directory (the future app repo).
# Does NOT copy into factory services/. Factory example-api is the template source only.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:-${NAME:-}}"
DEST="${2:-}"
if [[ -z "$NAME" || -z "$DEST" ]]; then
  echo "usage: $0 <service-name> <dest-dir>   (lowercase, DNS-safe, e.g. orders-api)" >&2
  exit 1
fi
if [[ ! "$NAME" =~ ^[a-z][a-z0-9-]{1,30}[a-z0-9]$ ]]; then
  echo "service name must be 3-32 chars, start with a letter, lowercase alphanumeric plus hyphens" >&2
  exit 1
fi
SRC="$ROOT/templates/service-api"
if [[ ! -d "$SRC" ]]; then
  echo "template missing: $SRC" >&2
  exit 1
fi
if [[ -e "$DEST" && -n "$(ls -A "$DEST" 2>/dev/null || true)" ]]; then
  echo "destination is not empty: $DEST" >&2
  exit 1
fi

mkdir -p "$DEST"
# Copy including dotfiles (.teamcity, .gitignore, .dockerignore) but not . / ..
shopt -s dotglob
cp -a "$SRC"/. "$DEST"/
shopt -u dotglob
# Never copy terraform local state from a developer laptop into a new app.
find "$DEST" -type d -name .terraform -prune -exec rm -rf {} +
find "$DEST" -type f \( -name '*.tfstate' -o -name '*.tfstate.*' -o -name '.terraform.lock.hcl' \) -delete

find "$DEST" -type f -print0 | xargs -0 sed -i "s/example-api/${NAME}/g"

echo "scaffolded $DEST from templates/service-api for $NAME"

# TeamCity versioned settings delete the project if Kotlin has no uuid.
if [[ -f "$DEST/.teamcity/settings.kts" ]] && ! grep -q 'uuid =' "$DEST/.teamcity/settings.kts"; then
  UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  sed -i "s/^project {/project {\n    uuid = \"$UUID\"/" "$DEST/.teamcity/settings.kts"
  echo "pinned TeamCity project uuid $UUID"
fi
