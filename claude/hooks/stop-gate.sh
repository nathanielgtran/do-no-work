#!/bin/bash
# Stop hook: block the stop while the repo's fast check fails.
# Check, first match wins: $CLAUDE_STOP_GATE_CMD, .claude/stop-gate (one line), auto-detect.
# Repo-defined checks (.claude/stop-gate, auto-detect) run only when origin is owned by a
# GitHub user/org in CLAUDE_STOP_GATE_OWNERS (space-separated), so a cloned repo can't run code.
# Env: CLAUDE_STOP_GATE_TIMEOUT (seconds, default 120).
# Allows the stop when not in git, the tree is clean, the tree matches the last passing run, or the same failure repeats under stop_hook_active.
set -uo pipefail
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

MAX_LINES=40
LIMIT="${CLAUDE_STOP_GATE_TIMEOUT:-120}"

run_timed() {
  if command -v gtimeout >/dev/null; then gtimeout "$LIMIT" "$@"
  elif [ -n "$(type -P timeout)" ]; then command timeout "$LIMIT" "$@"
  else "$@"
  fi
}

detect_cmd() {
  local parts=()
  if [ -f go.mod ]; then
    parts+=("go vet ./... && go test ./...")
  elif [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    parts+=("npm test --silent")
  elif [ -f pytest.ini ] || grep -qs pytest pyproject.toml; then
    parts+=("python3 -m pytest -q -x")
  fi
  if [ -f openspec/config.yaml ] && command -v openspec >/dev/null; then
    parts+=("openspec validate --strict --all")
  fi
  local out="" p
  for p in "${parts[@]+"${parts[@]}"}"; do out="${out:+$out && }$p"; done
  printf '%s' "$out"
}

trusted_repo() {
  local url owner
  url=$(git remote get-url origin 2>/dev/null) || return 1
  for owner in ${CLAUDE_STOP_GATE_OWNERS:-}; do
    case "$url" in *github.com[:/]"$owner"/*) return 0 ;; esac
  done
  return 1
}

select_cmd() {
  if [ -n "${CLAUDE_STOP_GATE_CMD:-}" ]; then printf '%s' "$CLAUDE_STOP_GATE_CMD"; return; fi
  trusted_repo || return 0
  if [ -s .claude/stop-gate ]; then head -n 1 .claude/stop-gate; return; fi
  detect_cmd
}

tree_fingerprint() {
  {
    printf '%s\n' "$1"
    git rev-parse HEAD 2>/dev/null
    git diff HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
      printf '%s ' "$f"
      cksum < "$f" 2>/dev/null
    done
  } | cksum
}

block() {
  jq -n --arg r "$1" '{decision:"block",reason:$r}'
}

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "none"' | tr -c 'A-Za-z0-9_-' '_')

[ -n "$CWD" ] && { cd "$CWD" || exit 0; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0
[ -n "$(git status --porcelain)" ] || exit 0

CMD=$(select_cmd)
[ -n "$CMD" ] || exit 0

STATE="${TMPDIR:-/tmp}/claude-stop-gate-$SESSION"
GREEN="$STATE.green"
FINGERPRINT=$(tree_fingerprint "$CMD")
[ "$(cat "$GREEN" 2>/dev/null)" = "$FINGERPRINT" ] && exit 0

OUT=$(run_timed bash -c "$CMD" 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then
  [ -e "$STATE" ] && : > "$STATE"
  printf '%s' "$FINGERPRINT" > "$GREEN"
  exit 0
fi

SUM=$(printf '%s' "$OUT" | cksum)
if [ "$ACTIVE" = true ] && [ "$(cat "$STATE" 2>/dev/null)" = "$SUM" ]; then
  echo "{\"systemMessage\":\"stop-gate: same failure after a retry, allowing stop\"}"
  exit 0
fi
printf '%s' "$SUM" > "$STATE"

CLIPPED=$(printf '%s\n' "$OUT" | head -n "$MAX_LINES")
[ "$RC" -eq 124 ] && CLIPPED="timed out after ${LIMIT}s
$CLIPPED"
block "stop-gate: \`$CMD\` failed (exit $RC). Fix before finishing.
$CLIPPED"
