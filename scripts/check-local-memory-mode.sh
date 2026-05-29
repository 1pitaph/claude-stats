#!/usr/bin/env bash
set -u

MEMORYD_BASE_URL="${MEMORYD_BASE_URL:-http://127.0.0.1:8765}"
LOCAL_AI_BASE_URL="${LOCAL_AI_BASE_URL:-http://127.0.0.1:18765}"
LOCAL_AI_TOKEN="${LOCAL_AI_TOKEN:-}"

failures=0

check_get() {
  local name="$1"
  local url="$2"
  shift 2
  if curl -fsS "$@" "$url" >/dev/null; then
    printf 'ok   %s\n' "$name"
  else
    printf 'fail %s (%s)\n' "$name" "$url" >&2
    failures=$((failures + 1))
  fi
}

check_get "memoryd health" "$MEMORYD_BASE_URL/health"
check_get "memoryd projects" "$MEMORYD_BASE_URL/v1/projects"
check_get "local AI health" "$LOCAL_AI_BASE_URL/health"

if [ -n "$LOCAL_AI_TOKEN" ]; then
  check_get "local AI models" "$LOCAL_AI_BASE_URL/v1/models" -H "Authorization: Bearer $LOCAL_AI_TOKEN"
else
  printf 'skip local AI models (set LOCAL_AI_TOKEN to check authenticated endpoints)\n'
fi

if [ "$failures" -eq 0 ]; then
  printf 'local memory mode readiness checks passed\n'
else
  printf 'local memory mode readiness checks failed: %s\n' "$failures" >&2
fi

exit "$failures"
