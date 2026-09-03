# Source from inception.sh. Maps TeamCity select *labels* to create|existing and true|false.
normalize_git_mode() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    create|create\ a\ new*) printf '%s' create ;;
    existing|use\ an\ existing*) printf '%s' existing ;;
    this-repo) printf '%s' this-repo ;;
    *) printf '%s' "$1" ;;
  esac
}
normalize_alb() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    true|internal*) printf '%s' true ;;
    false|internet*) printf '%s' false ;;
    *) printf '%s' "$1" ;;
  esac
}
GIT_MODE="$(normalize_git_mode "$GIT_MODE")"
ALB_INTERNAL="$(normalize_alb "$ALB_INTERNAL")"
if [ -n "$GIT_REPO" ] && [ "$GIT_REPO" = "${GIT_REPO#*/}" ] && [ "$GIT_REPO" = "${GIT_REPO#*github.com}" ]; then
  echo "==> git.repo '$GIT_REPO' is not owner/name; defaulting to <you>/${NAME}"
  GIT_REPO=""
fi
