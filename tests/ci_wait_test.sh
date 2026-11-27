#!/bin/bash
# Runs bin/ci-wait against a fake gh that serves canned statusCheckRollup JSON in sequence.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

TMP="$(mktemp -d)"
mkdir "$TMP/bin" "$TMP/seq"
cat > "$TMP/bin/gh" <<'FAKE'
#!/bin/bash
n=$(( $(cat "$FAKE_SEQ/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_SEQ/count"
f="$FAKE_SEQ/$n.json"
[ -f "$f" ] || f=$(ls "$FAKE_SEQ"/*.json | sort -V | tail -1)
cat "$f"
FAKE
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_SEQ="$TMP/seq" CI_WAIT_INTERVAL=0 CI_WAIT_EMPTY_GRACE=1

seq_reset() { find "$TMP/seq" -type f -delete; }
put() { echo "$2" > "$TMP/seq/$1.json"; }
ok='{"name":"test","status":"COMPLETED","conclusion":"SUCCESS"}'
ok2='{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}'
bad='{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}'
run='{"name":"test","status":"IN_PROGRESS","conclusion":""}'
wrap() { echo "{\"statusCheckRollup\":[$1]}"; }
CW="$REPO/bin/ci-wait"

echo "-- all success"
seq_reset; put 1 "$(wrap "$ok,$ok2")"
rc=0; "$CW" 5 > "$TMP/out" || rc=$?
check "exit 0" "[ $rc -eq 0 ]"
check "prints each check" "grep -q '^test: success' '$TMP/out' && grep -q '^lint: success' '$TMP/out'"

echo "-- one failure"
seq_reset; put 1 "$(wrap "$ok,$bad")"
rc=0; "$CW" 5 > "$TMP/out" || rc=$?
check "exit 1" "[ $rc -eq 1 ]"
check "prints failure" "grep -q '^lint: failure' '$TMP/out'"

echo "-- empty then success"
seq_reset; put 1 "$(wrap "")"; put 2 "$(wrap "")"; put 3 "$(wrap "$ok")"
rc=0; CI_WAIT_EMPTY_GRACE=30 "$CW" 5 -R o/r > "$TMP/out" || rc=$?
check "exit 0" "[ $rc -eq 0 ]"

echo "-- running then success"
seq_reset; put 1 "$(wrap "$run")"; put 2 "$(wrap "$ok")"
rc=0; "$CW" 5 > "$TMP/out" || rc=$?
check "waits for completion, exit 0" "[ $rc -eq 0 ]"

echo "-- never any checks"
seq_reset; put 1 "$(wrap "")"
rc=0; "$CW" 5 > "$TMP/out" 2>/dev/null || rc=$?
check "exit 1 after grace" "[ $rc -eq 1 ]"

echo "-- timeout"
seq_reset; put 1 "$(wrap "$run")"
rc=0; CI_WAIT_TIMEOUT=0 "$CW" 5 > "$TMP/out" 2>/dev/null || rc=$?
check "exit 1 on timeout" "[ $rc -eq 1 ]"

mv "$TMP" "$HOME/.trash/ci_wait_test.$$" 2>/dev/null || true
exit $fail
