#!/usr/bin/env bash
# Register a TeamCity project whose versioned-settings VCS root is the APP repo.
# Env: NAME APP_GIT_URL
#      TEAMCITY_URL  (e.g. http://localhost:8111 or %teamcity.serverUrl%)
#      TEAMCITY_TOKEN  or TEAMCITY_USER + TEAMCITY_PASSWORD
#      TEAMCITY_PARENT (default _Root)
#      TEAMCITY_GITHUB_TOKEN (optional; falls back to gh auth token, never printed)
#
# If REST cannot enable Kotlin versioned settings, we still created the
# project + VCS root. One-time UI: Project Settings → Versioned Settings →
# Synchronization enabled, format Kotlin, VCS root = this GitHub root,
# settings path .teamcity, import from VCS.
set -euo pipefail

NAME="${NAME:?}"
APP_GIT_URL="${APP_GIT_URL:?}"
TEAMCITY_URL="${TEAMCITY_URL:-}"
TEAMCITY_PARENT="${TEAMCITY_PARENT:-_Root}"
TEAMCITY_TOKEN="${TEAMCITY_TOKEN:-}"
TEAMCITY_USER="${TEAMCITY_USER:-}"
TEAMCITY_PASSWORD="${TEAMCITY_PASSWORD:-}"

# Ephemeral build credentials cannot create projects (REST 403).
if [[ "${TEAMCITY_USER:-}" == TeamCityBuildId=* ]]; then
  TEAMCITY_USER=""
  TEAMCITY_PASSWORD=""
fi
if [[ -z "${TEAMCITY_TOKEN:-}" && -n "${TEAMCITY_TOKEN_FILE:-}" && -f "$TEAMCITY_TOKEN_FILE" ]]; then
  TEAMCITY_TOKEN="$(cat "$TEAMCITY_TOKEN_FILE")"
fi
if [[ -z "${TEAMCITY_TOKEN:-}" && -f /run/secrets/tc.token ]]; then
  TEAMCITY_TOKEN="$(cat /run/secrets/tc.token)"
fi
cleaned="$(printf "%s\n" "$APP_GIT_URL" | grep -Eo "https://github.com/[^[:space:]]+" | tail -n1 || true)"
if [[ -n "$cleaned" ]]; then
  APP_GIT_URL="$cleaned"
fi

log() { echo "==> $*"; }

ui_fallback() {
  cat <<TXT
TeamCity UI (one-time) if versioned settings did not import:
  1. Administration → project ${NAME} (or create it)
  2. VCS Roots → Git → Fetch URL ${APP_GIT_URL} → Default branch refs/heads/main
     (private repo: attach a GitHub token / connection; do not paste tokens into git)
  3. Versioned Settings → Synchronization: enabled
     Format: Kotlin
     VCS root: the GitHub root above
     Settings path: .teamcity
     Import settings from VCS
The Kotlin in the app repo is already the source of truth; this click only points TeamCity at it.
TXT
}

if [[ -z "$TEAMCITY_URL" ]]; then
  log "TEAMCITY_URL unset; skip REST registration"
  ui_fallback
  exit 0
fi

TEAMCITY_URL="${TEAMCITY_URL%/}"

AUTH_ARGS=()
if [[ -n "$TEAMCITY_TOKEN" ]]; then
  AUTH_ARGS=(-u ":${TEAMCITY_TOKEN}")
elif [[ -n "$TEAMCITY_USER" && -n "$TEAMCITY_PASSWORD" ]]; then
  AUTH_ARGS=(-u "${TEAMCITY_USER}:${TEAMCITY_PASSWORD}")
else
  log "no TEAMCITY_TOKEN or TEAMCITY_USER/PASSWORD; skip REST registration"
  ui_fallback
  exit 0
fi

GH_FOR_TC="${TEAMCITY_GITHUB_TOKEN:-}"
if [[ -z "$GH_FOR_TC" ]] && command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  GH_FOR_TC="$(gh auth token 2>/dev/null || true)"
fi

safe_id() { echo "$1" | tr '-' '_'; }
PROJECT_ID="App_$(safe_id "$NAME")"
VCS_ID="${PROJECT_ID}_GitHub"

tc() {
  local method="$1" path="$2"
  shift 2
  curl -sS -f -X "$method" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Origin: ${TEAMCITY_URL}" \
    "${AUTH_ARGS[@]}" \
    "${TEAMCITY_URL}${path}" \
    "$@"
}

log "TeamCity project $PROJECT_ID (auth and tokens not logged)"

if tc GET "/app/rest/projects/id:${PROJECT_ID}" >/dev/null 2>&1; then
  log "project $PROJECT_ID already exists"
else
  proj_body="$(PROJECT_ID="$PROJECT_ID" NAME="$NAME" TEAMCITY_PARENT="$TEAMCITY_PARENT" python3 - << 'PY'
import json, os
print(json.dumps({
  "parentProject": {"locator": "id:" + os.environ["TEAMCITY_PARENT"]},
  "name": os.environ["NAME"],
  "id": os.environ["PROJECT_ID"],
  "copyAllAssociatedSettings": True,
}))
PY
)"
  tc POST "/app/rest/projects" -d "$proj_body" >/dev/null
  log "created project $PROJECT_ID"
fi

vcs_body="$(APP_GIT_URL="$APP_GIT_URL" GH_FOR_TC="${GH_FOR_TC:-}" VCS_ID="$VCS_ID" NAME="$NAME" PROJECT_ID="$PROJECT_ID" python3 - << 'PY'
import json, os
props = [
  {"name": "url", "value": os.environ["APP_GIT_URL"]},
  {"name": "branch", "value": "refs/heads/main"},
  {"name": "branchSpec", "value": "+:refs/heads/*"},
]
tok = os.environ.get("GH_FOR_TC") or ""
if tok:
    props.extend([
        {"name": "authMethod", "value": "PASSWORD"},
        {"name": "username", "value": "x-access-token"},
        {"name": "secure:password", "value": tok},
    ])
else:
    props.append({"name": "authMethod", "value": "ANONYMOUS"})
print(json.dumps({
  "id": os.environ["VCS_ID"],
  "name": os.environ["NAME"] + " GitHub",
  "vcsName": "jetbrains.git",
  "project": {"id": os.environ["PROJECT_ID"]},
  "properties": {"property": props},
}))
PY
)"

if tc GET "/app/rest/vcs-roots/id:${VCS_ID}" >/dev/null 2>&1; then
  log "VCS root $VCS_ID already exists"
else
  if ! tc POST "/app/rest/vcs-roots" -d "$vcs_body" >/dev/null; then
    log "WARN: failed to create VCS root via REST"
    ui_fallback
    exit 0
  fi
  log "created VCS root $VCS_ID"
fi

vs_body="$(VCS_ID="$VCS_ID" python3 - << 'PY'
import json, os
print(json.dumps({
  "format": "kotlin",
  "synchronizationMode": "enabled",
  "allowUIEditing": True,
  "storeSecureValuesOutsideVcs": True,
  "portableDsl": True,
  "showSettingsChanges": True,
  "vcsRootId": os.environ["VCS_ID"],
  "settingsPath": ".teamcity",
  "buildSettingsMode": "alwaysUseCurrent",
  "importDecision": "importFromVCS",
}))
PY
)"

set +e
tc PUT "/app/rest/projects/id:${PROJECT_ID}/versionedSettings/config" -d "$vs_body" >/dev/null 2>/dev/null
rc=$?
if [[ $rc -ne 0 ]]; then
  tc POST "/app/rest/projects/id:${PROJECT_ID}/versionedSettings/config" -d "$vs_body" >/dev/null 2>/dev/null
  rc=$?
fi
set -e
if [[ $rc -ne 0 ]]; then
  log "WARN: REST did not enable versioned settings cleanly"
  ui_fallback
  exit 0
fi
log "enabled Kotlin versioned settings on $PROJECT_ID"

set +e
tc POST "/app/rest/projects/id:${PROJECT_ID}/versionedSettings/loadSettings" >/dev/null 2>/dev/null
set -e
log "asked TeamCity to load settings from the app repo"
log "after reload, run ${NAME} / create (dev) for the first AWS deploy"
