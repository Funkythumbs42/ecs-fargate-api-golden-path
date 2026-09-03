#!/usr/bin/env bash
# Create or attach a GitHub repo for a rendered app tree, then push the scaffold.
# Env: ROOT NAME DEST GIT_MODE (create|existing) GIT_REPO (owner/name or URL)
# Default git mode is create. this-repo is not a product path.
set -euo pipefail

ROOT="${ROOT:?}"
NAME="${NAME:?}"
DEST="${DEST:?}"
GIT_MODE="${GIT_MODE:-create}"
GIT_REPO="${GIT_REPO:-}"
LIST="$ROOT/.teamcity/services.list"

log() { echo "==> $*"; }

die() { echo "$*" >&2; exit 1; }

normalize_slug() {
  local r="$1"
  r="${r%%[[:space:]]*}"
  r="${r%.git}"
  r="${r%/}"
  r="${r#git@github.com:}"
  r="${r#https://github.com/}"
  r="${r#http://github.com/}"
  r="${r#ssh://git@github.com/}"
  if [[ ! "$r" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    die "repo must be owner/name or a github.com URL, got: $1"
  fi
  echo "$r"
}

https_url() {
  echo "https://github.com/${1}.git"
}

require_gh() {
  command -v gh >/dev/null || die "gh (GitHub CLI) is required for git.mode=${GIT_MODE}"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in; run gh auth login"
}

gh_login() {
  gh api user --jq .login
}

register_line() {
  local name="$1"
  local rest="${2:-}"
  mkdir -p "$(dirname "$LIST")"
  touch "$LIST"
  local tmp
  tmp="$(mktemp)"
  awk -v n="$name" '
    $0 ~ /^[[:space:]]*#/ { print; next }
    NF==0 { print; next }
    $1==n { next }
    { print }
  ' "$LIST" > "$tmp"
  if [[ -n "$rest" ]]; then
    echo "${name} ${rest}" >> "$tmp"
  else
    echo "${name}" >> "$tmp"
  fi
  mv "$tmp" "$LIST"
}

repo_is_effectively_empty() {
  local dir="$1"
  local files
  files="$(git -C "$dir" ls-files || true)"
  if [[ -z "$files" ]]; then
    return 0
  fi
  if echo "$files" | grep -Ev '^(README(\.md)?|LICENSE.*|\.gitignore)$' >/dev/null; then
    return 1
  fi
  return 0
}

push_app_tree() {
  local url="$1"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git clone "$url" "$tmp/repo"
  if ! repo_is_effectively_empty "$tmp/repo"; then
    die "existing repo is not empty; recorded the pointer but refusing to overwrite."
  fi
  shopt -s dotglob
  cp -a "$DEST"/. "$tmp/repo/"
  shopt -u dotglob
  # Drop leftover git metadata from a previous copy if any (DEST is not a git repo).
  rm -rf "$tmp/repo/.git/info" 2>/dev/null || true
  git -C "$tmp/repo" add -A
  if git -C "$tmp/repo" diff --cached --quiet; then
    log "nothing to push to $url"
    return 0
  fi
  git -C "$tmp/repo" \
    -c user.email="factory@example.invalid" \
    -c user.name="api-factory" \
    commit -m "factory: scaffold ${NAME}"
  git -C "$tmp/repo" push -u origin HEAD
  log "pushed scaffold to $url"
}

case "$GIT_MODE" in
  create|"")
    require_gh
    if [[ -z "$GIT_REPO" ]]; then
      GIT_REPO="$(gh_login)/${NAME}"
    fi
    slug="$(normalize_slug "$GIT_REPO")"
    url="$(https_url "$slug")"
    if gh repo view "$slug" >/dev/null 2>&1; then
      die "GitHub repo $slug already exists; use git.mode=existing to attach it"
    fi
    log "creating private GitHub repo $slug"
    if ! gh repo create "$slug" --private --description "API ${NAME} (golden-path app repo)" --confirm; then
      gh repo create "$slug" --private --description "API ${NAME} (golden-path app repo)"
    fi
    push_app_tree "$url"
    register_line "$NAME" "$url"
    echo "$url"
    ;;
  existing)
    require_gh
    [[ -n "$GIT_REPO" ]] || die "git.mode=existing requires git.repo (owner/name or GitHub URL)"
    slug="$(normalize_slug "$GIT_REPO")"
    url="$(https_url "$slug")"
    gh repo view "$slug" >/dev/null 2>&1 || die "GitHub repo $slug not found (or this account cannot see it)"
    log "attaching existing $slug"
    tmp="$(mktemp -d)"
    git clone "$url" "$tmp/repo"
    if repo_is_effectively_empty "$tmp/repo"; then
      rm -rf "$tmp"
      push_app_tree "$url"
    else
      rm -rf "$tmp"
      log "repo has commits; recording pointer only (will not overwrite)"
    fi
    register_line "$NAME" "$url"
    echo "$url"
    ;;
  this-repo)
    die "git.mode=this-repo is not the product path. App files live in a standalone GitHub repo (create|existing)."
    ;;
  *)
    die "git.mode must be create or existing (got: $GIT_MODE)"
    ;;
esac
