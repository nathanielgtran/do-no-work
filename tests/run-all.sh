#!/bin/bash
# Usage: tests/run-all.sh [--list] [--only <glob>]
# Runs every tests/*_test.sh plus the skill suites listed in EXTRA. TEST_TIMEOUT seconds each (default 300).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"

# name|required tool|linux only (0/1)|directory|command
EXTRA=(
  "wanderlog|python3|0|claude/skills/wanderlog|python3 -m unittest -q test_wl"
  "backlog|uvx|0|claude/skills/backlog|uvx pytest -q test_generate.py -p no:cacheprovider"
  "tighten-preflight|bash|1|.|bash claude/skills/tighten/tests/preflight_test.sh"
  "tighten-tier|bash|1|.|bash claude/skills/tighten/tests/tier_test.sh"
)

ONLY="*"
LIST=0
NAMES=()
RESULTS=()
FAILED=0

timeout_cmd() {
  if command -v gtimeout >/dev/null 2>&1; then echo gtimeout
  elif command -v timeout >/dev/null 2>&1; then echo timeout
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --list) LIST=1 ;;
      --only)
        [ $# -ge 2 ] || { echo "--only needs a glob" >&2; exit 2; }
        ONLY="$2"
        shift
        ;;
      *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
  done
}

list_names() {
  local f e
  for f in tests/*_test.sh; do
    basename "$f"
  done | LC_ALL=C sort
  for e in "${EXTRA[@]}"; do
    echo "${e%%|*}"
  done
}

record() {
  NAMES+=("$1")
  RESULTS+=("$2|$3")
  if [ "$2" = FAIL ]; then FAILED=1; fi
  return 0
}

run_one() {
  local name="$1" dir="$2"
  shift 2
  local tmo start secs rc=0
  tmo="$(timeout_cmd)"
  echo "== $name"
  start=$(date +%s)
  if [ -n "$tmo" ]; then
    (cd "$dir" && "$tmo" "$TEST_TIMEOUT" "$@" </dev/null) || rc=$?
  else
    (cd "$dir" && "$@" </dev/null) || rc=$?
  fi
  secs=$(($(date +%s) - start))
  if [ "$secs" -lt 0 ]; then secs=0; fi
  if [ "$rc" -eq 0 ]; then
    record "$name" pass "$secs"
    return 0
  fi
  if [ "$rc" -eq 124 ]; then echo "timeout after ${TEST_TIMEOUT}s"; fi
  record "$name" FAIL "$secs"
}

run_extra() {
  local name tool linux dir cmd words
  IFS='|' read -r name tool linux dir cmd <<<"$1"
  # shellcheck disable=SC2254
  case "$name" in $ONLY) ;; *) return 0 ;; esac
  if [ "$linux" = 1 ] && [ "$(uname -s)" != Linux ]; then
    echo "== $name"
    echo "skip (non-Linux)"
    record "$name" skip 0
    return 0
  fi
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "== $name"
    echo "skip (tool missing: $tool)"
    record "$name" skip 0
    return 0
  fi
  read -r -a words <<<"$cmd"
  run_one "$name" "$REPO/$dir" "${words[@]}"
}

summary() {
  local i r
  echo
  printf '%-34s %-6s %s\n' name result seconds
  for i in "${!NAMES[@]}"; do
    r="${RESULTS[$i]}"
    printf '%-34s %-6s %s\n' "${NAMES[$i]}" "${r%%|*}" "${r##*|}"
  done
}

main() {
  parse_args "$@"
  if [ "$LIST" = 1 ]; then
    list_names
    return 0
  fi
  local f name e
  for f in tests/*_test.sh; do
    name="$(basename "$f")"
    # shellcheck disable=SC2254
    case "$name" in $ONLY) ;; *) continue ;; esac
    run_one "$name" "$REPO" bash "$f"
  done
  for e in "${EXTRA[@]}"; do
    run_extra "$e"
  done
  summary
  return "$FAILED"
}

main "$@"
