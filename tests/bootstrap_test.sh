#!/bin/bash
# Runs bin/repo-bootstrap against a fake gh that logs argv and returns canned JSON.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

TMP="$(mktemp -d)"
mkdir "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/bin/bash
echo "$*" >> "$GH_LOG"
if [[ "$*" == *"--input -"* ]]; then cat >> "$GH_BODY"; echo >> "$GH_BODY"; fi
case "$*" in
  *"-X "*) echo '{}' ;;
  *"/rulesets") echo "${FAKE_RULESETS:-[]}" ;;
  *"/labels?"*) echo "${FAKE_LABELS:-[]}" ;;
  *"contents/.github/workflows/"*) cat "$FAKE_WORKFLOW" ;;
  *"contents/.github/workflows") echo '[{"name":"ci.yml"},{"name":"README.md"}]' ;;
  *) echo '{}' ;;
esac
FAKE
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_LOG="$TMP/log" GH_BODY="$TMP/body" FAKE_WORKFLOW="$TMP/wf.yml"
BS="$REPO/bin/repo-bootstrap"

reset() { : > "$GH_LOG"; : > "$GH_BODY"; unset FAKE_RULESETS BOOTSTRAP_CHECKS BOOTSTRAP_ACTIONS || true; }

echo "-- dry run"
reset
BOOTSTRAP_CHECKS=test "$BS" o/r --dry-run > "$TMP/out"
check "no mutating calls" "! grep -q -- '-X ' '$GH_LOG'"
check "prints planned calls" "grep -q 'dry  PATCH repos/o/r' '$TMP/out'"

echo "-- normal run"
reset
BOOTSTRAP_CHECKS="test,gitleaks" "$BS" o/r > "$TMP/out"
for ep in \
  "PUT repos/o/r/actions/permissions/workflow" \
  "PUT repos/o/r/actions/permissions/fork-pr-contributor-approval" \
  "PUT repos/o/r/actions/permissions " \
  "PUT repos/o/r/actions/permissions/selected-actions" \
  "PATCH repos/o/r " \
  "PUT repos/o/r/private-vulnerability-reporting" \
  "PUT repos/o/r/vulnerability-alerts" \
  "PUT repos/o/r/automated-security-fixes" \
  "POST repos/o/r/labels" \
  "POST repos/o/r/rulesets"; do
  check "calls $ep" "grep -q -- '-X $ep' '$GH_LOG'"
done
check "default action patterns" "grep -q 'patterns_allowed\[\]=astral-sh/setup-uv@\*' '$GH_LOG'"
check "ruleset has both checks" "jq -e '[.rules[] | select(.type==\"required_status_checks\") | .parameters.required_status_checks[].context] == [\"test\",\"gitleaks\"]' '$GH_BODY' >/dev/null"
check "no mutating call to other repos" "! grep -- '-X ' '$GH_LOG' | grep -qv 'repos/o/r'"

echo "-- no BOOTSTRAP_CHECKS"
reset
"$BS" o/r > "$TMP/out"
check "says checks skipped" "grep -q 'skip required_status_checks' '$TMP/out'"
check "ruleset omits status checks rule" "! jq -e '.rules[] | select(.type==\"required_status_checks\")' '$GH_BODY' >/dev/null"

echo "-- existing ruleset"
reset
FAKE_RULESETS='[{"id":42,"name":"other"},{"id":77,"name":"protect-main"}]' "$BS" o/r > "$TMP/out"
check "updates ruleset 77" "grep -q -- '-X PUT repos/o/r/rulesets/77' '$GH_LOG'"
check "does not create a duplicate" "! grep -q -- '-X POST repos/o/r/rulesets' '$GH_LOG'"
check "does not touch other ruleset" "! grep -q 'rulesets/42' '$GH_LOG'"

echo "-- existing label"
reset
FAKE_LABELS='[{"name":"REVIEWED"}]' "$BS" o/r > "$TMP/out"
check "label not recreated" "! grep -q -- '-X POST repos/o/r/labels' '$GH_LOG'"

echo "-- --public"
reset
printf 'jobs:\n  t:\n    runs-on: [self-hosted, nuc]\n' > "$FAKE_WORKFLOW"
"$BS" o/r --public > "$TMP/out" 2> "$TMP/err"
check "warns on self-hosted workflow" "grep -q 'WARNING: ci.yml' '$TMP/err'"
printf 'jobs:\n  t:\n    runs-on: ubuntu-latest\n' > "$FAKE_WORKFLOW"
"$BS" o/r --public > "$TMP/out" 2> "$TMP/err"
check "no warning on hosted runner" "[ ! -s '$TMP/err' ]"
reset
"$BS" o/r > "$TMP/out" 2> "$TMP/err"
check "no workflow fetch without --public" "! grep -q 'contents/.github' '$GH_LOG'"

echo "-- bad args"
check "rejects bad repo" "! '$BS' notarepo >/dev/null 2>&1"

mv "$TMP" "$HOME/.trash/bootstrap_test.$$" 2>/dev/null || true
exit $fail
