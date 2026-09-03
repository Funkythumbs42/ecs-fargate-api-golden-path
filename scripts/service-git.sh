#!/usr/bin/env bash
# Attach or create a GitHub repo for a factory service.
# Env: ROOT NAME GIT_MODE (this-repo|create|existing) GIT_REPO (owner/name or URL)
set -euo pipefail

ROOT="${ROOT:?}"
NAME="${NAME:?}"
GIT_MODE="${GIT_MODE:-this-repo}"
GIT_REPO="${GIT_REPO:-}"
LIST="$ROOT/.teamcity/services.list"
SERVICE_DIR="$ROOT/services/$NAME"

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
  touch "$LIST"
  local tmp
  tmp="$(mktemp)"
  # drop any existing line for this service (comment lines stay)
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
  # GitHub's default README/LICENSE/gitignore still counts as empty for our purposes
  if echo "$files" | grep -Ev '^(README(\.md)?|LICENSE.*|\.gitignore)$' >/dev/null; then
    return 1
  fi
  return 0
}

push_service_tree() {
  local url="$1"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git clone "$url" "$tmp/repo"
  if ! repo_is_effectively_empty "$tmp/repo"; then
    die "existing repo is not empty; recorded the pointer but refusing to overwrite. Clone it yourself and keep the factory services/${NAME} copy as CI source."
  fi
  # Service tree at repo root (app + Dockerfile + envs). Factory still holds CI + platform.
  shopt -s dotglob
  cp -a "$SERVICE_DIR"/* "$tmp/repo/"
  shopt -u dotglob
  cat > "$tmp/repo/FACTORY.md" << MD
This repo is the git home for **${NAME}**.

TeamCity pipelines and shared platform Terraform live in the factory:
https://github.com/Funkythumbs42/ecs-fargate-api-golden-path
MD
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
  this-repo|"")
    register_line "$NAME"
    log "git: service stays in this factory repo"
    ;;
  create)
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
    gh repo create "$slug" --private --description "API ${NAME} (golden-path service)" --confirm
    push_service_tree "$url"
    register_line "$NAME" "$url"
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
      push_service_tree "$url"
    else
      rm -rf "$tmp"
      log "repo has commits; recording pointer only (will not overwrite)"
    fi
    register_line "$NAME" "$url"
    ;;
  *)
    die "git.mode must be this-repo, create, or existing (got: $GIT_MODE)"
    ;;
esac
