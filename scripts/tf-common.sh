#!/usr/bin/env bash
# Shared helpers for TeamCity infra/code scripts. Source this file.
set -euo pipefail

: "${AWS_DEFAULT_REGION:=eu-west-1}"
export AWS_DEFAULT_REGION

service_root() {
  echo "services/${SERVICE_NAME}/envs/${DEPLOY_ENV}"
}

platform_root() {
  echo "platform/envs/${DEPLOY_ENV}"
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
state_digest() {
  local root="$1"
  terraform -chdir="$root" output -raw image_digest 2>/dev/null || true
}

tf_init() {
  local root="$1"
  terraform -chdir="$root" init -input=false -no-color -backend-config=backend.hcl.example
}
