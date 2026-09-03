#!/usr/bin/env bash
# Shared helpers for TeamCity infra/code scripts. Source this file.
# This copy lives in the APP repo; pipelines check out this repo, not the factory.
set -euo pipefail

: "${AWS_DEFAULT_REGION:=eu-west-1}"
export AWS_DEFAULT_REGION

service_root() {
  echo "envs/${DEPLOY_ENV}"
}

normalize_digest() {
  local d="$1"
  d="${d#sha256:}"
  echo "sha256:${d}"
}

require_digest() {
  local d="${IMAGE_DIGEST:-}"
  if [[ -z "$d" && -f image_digest.txt ]]; then
    d="$(tr -d '[:space:]' < image_digest.txt)"
  fi
  if [[ -z "$d" ]]; then
    echo "IMAGE_DIGEST is required (artifact, env, or rollback parameter)" >&2
    exit 1
  fi
  normalize_digest "$d"
}

# Digest currently recorded in service state. Empty if the stack was never applied.
# `terraform output` can print a colored "No outputs found" warning on stdout
# (not stderr) on a first apply; only accept a real sha256 digest.
state_digest() {
  local root="$1"
  local d
  d="$(terraform -chdir="$root" output -raw -no-color image_digest 2>/dev/null || true)"
  d="${d#"${d%%[![:space:]]*}"}"
  d="${d%"${d##*[![:space:]]}"}"
  d="${d#sha256:}"
  if [[ "$d" =~ ^[0-9a-f]{64}$ ]]; then
    echo "sha256:${d}"
  fi
}

print_alb() {
  local root="$1"
  local dns
  dns="$(terraform -chdir="$root" output -raw -no-color alb_dns_name 2>/dev/null || true)"
  dns="${dns#"${dns%%[![:space:]]*}"}"
  dns="${dns%"${dns##*[![:space:]]}"}"
  if [[ -n "$dns" && "$dns" != *"No outputs"* ]]; then
    echo "ALB: http://${dns}  (curl http://${dns}/health — no Host header)"
  fi
}

tf_init() {
  local root="$1"
  terraform -chdir="$root" init -input=false -no-color -backend-config=backend.hcl.example
}
