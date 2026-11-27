#!/bin/bash
set -uo pipefail
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

FILE=$(jq -r '.tool_input.file_path')

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

if ! TEST_OUT=$(timeout 90 go test "$PKG" 2>&1); then
  PROBLEMS+="TEST FAILURES ($PKG):\n$(printf '%s\n' "$TEST_OUT" | clip)\n\n"
fi

if ! VET_OUT=$(go vet "$PKG" 2>&1); then
  PROBLEMS+="VET ISSUES ($PKG):\n$(printf '%s\n' "$VET_OUT" | clip)\n\n"
fi

if command -v golangci-lint >/dev/null 2>&1; then
  if ! LINT_OUT=$(timeout 90 golangci-lint run --new-from-rev=HEAD "$PKG" 2>&1); then
    PROBLEMS+="LINT ISSUES ($PKG):\n$(printf '%s\n' "$LINT_OUT" | clip)\n\n"
  fi
fi

if [ -z "$PROBLEMS" ]; then
  echo "{\"systemMessage\":\"go test + vet + lint passed ($PKG)\"}"
else
  ESCAPED=$(echo -e "$PROBLEMS" | jq -Rs .)
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$ESCAPED}}"
fi
