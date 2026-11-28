#!/bin/bash
# PostToolUse hook, wired async + asyncRewake: silent on success; on failure prints a report to
# stderr and exits 2 so Claude Code wakes the session with it. Tests stay with stop-gate.
set -uo pipefail
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"

FILE=$(jq -r '.tool_input.file_path // empty')

[[ "$FILE" == *.go ]] || exit 0

DIR=$(dirname "$FILE")
while [ "$DIR" != "/" ] && [ ! -f "$DIR/go.mod" ]; do
  DIR=$(dirname "$DIR")
done
[ -f "$DIR/go.mod" ] || exit 0

cd "$DIR" || exit 0

REL="$(cd "$(dirname "$FILE")" && pwd -P)"
REL="${REL#"$(pwd -P)"}"
PKG=".${REL:-/}"
MAX_LINES=40
PROBLEMS=""

clip() { head -n "$MAX_LINES"; }
timeout() {
  if command -v gtimeout >/dev/null; then gtimeout "$@"
  elif [ -n "$(type -P timeout)" ]; then command timeout "$@"
  else shift; "$@"
  fi
}

FMT_OUT=$(gofmt -l "$FILE" 2>&1)
if [ -n "$FMT_OUT" ]; then
  PROBLEMS+="FORMAT ISSUES ($PKG), run gofmt -w:\n$(printf '%s\n' "$FMT_OUT" | clip)\n\n"
fi

if ! VET_OUT=$(go vet "$PKG" 2>&1); then
  PROBLEMS+="VET ISSUES ($PKG):\n$(printf '%s\n' "$VET_OUT" | clip)\n\n"
fi

if command -v golangci-lint >/dev/null 2>&1; then
  if ! LINT_OUT=$(timeout 90 golangci-lint run --new-from-rev=HEAD "$PKG" 2>&1); then
    PROBLEMS+="LINT ISSUES ($PKG):\n$(printf '%s\n' "$LINT_OUT" | clip)\n\n"
  fi
fi

[ -z "$PROBLEMS" ] && exit 0
printf '%b' "$PROBLEMS" >&2
exit 2
