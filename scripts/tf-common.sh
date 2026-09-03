#!/usr/bin/env bash
# Shared helpers for factory platform scripts. Source this file.
set -euo pipefail

: "${AWS_DEFAULT_REGION:=eu-west-1}"
export AWS_DEFAULT_REGION

platform_root() {
  echo "platform/envs/${DEPLOY_ENV}"
}

tf_init() {
  local root="$1"
  terraform -chdir="$root" init -input=false -no-color -backend-config=backend.hcl.example
}
