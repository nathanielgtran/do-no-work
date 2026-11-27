#!/bin/bash
# Tests for scripts/claude-review-verdict.sh. Run: bash tests/claude_review_verdict_test.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/claude-review-verdict.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# Stub gh: logs every call, answers `pr view` with $STUB_HEAD (or fails if unset).
cat > "$work/gh" <<'STUB'
#!/bin/bash
cat >/dev/null 2>&1 || true
echo "$*" >> "$LOG"
if [ "$1 $2" = "pr view" ]; then
  [ -n "${STUB_HEAD:-}" ] || exit 1
  echo "$STUB_HEAD"
fi
STUB
chmod +x "$work/gh"

# run <name> <want-exit> <want-label:yes|no> <structured-output> [head-sha]
run() {
  local name="$1" want="$2" want_label="$3" out="$4" head="${5-abc123}"
  local got=0 label=no
  export LOG="$work/log"
  : > "$LOG"
  GH="$work/gh" REPO=o/r PR=7 EXPECTED_SHA=abc123 STUB_HEAD="$head" \
    STRUCTURED_OUTPUT="$out" bash "$SCRIPT" >/dev/null 2>&1 || got=$?
  grep -q -- '--add-label REVIEWED' "$LOG" && label=yes
  if [ "$got" -eq "$want" ] && [ "$label" = "$want_label" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name (want exit $want label $want_label, got exit $got label $label)"
    failures=$((failures + 1))
  fi
}

PASS='{"verdict":"PASS","summary":"Looks fine.","findings":[]}'
BLOCK='{"verdict":"BLOCK","summary":"Bug.","findings":["a.sh:3 unquoted var"]}'

run "PASS labels" 0 yes "$PASS"
run "BLOCK does not label, exits 1" 1 no "$BLOCK"
run "missing verdict fails" 1 no '{"summary":"x"}'
run "empty output fails" 1 no ''
run "invalid JSON fails" 1 no 'not json'
run "lowercase pass is not accepted" 1 no '{"verdict":"pass","summary":"x"}'
run "head SHA changed does not label" 1 no "$PASS" def456
run "unreadable head SHA does not label" 1 no "$PASS" ""

run "BLOCK still posts the comment" 1 no "$BLOCK"
grep -q 'pr comment' "$LOG" && echo "ok   - comment posted on BLOCK" || {
  echo "FAIL - comment posted on BLOCK"
  failures=$((failures + 1))
}

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
