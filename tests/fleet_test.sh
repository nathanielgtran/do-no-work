#!/bin/bash
# Runs bin/fleet against a fake gh serving canned pr list JSON per repo and canned run logs.
# shellcheck disable=SC2034 # vars are read inside check()'s eval strings
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

TMP="$(mktemp -d)"
mkdir "$TMP/bin" "$TMP/data" "$TMP/home"
cat > "$TMP/bin/gh" <<'FAKE'
#!/bin/bash
repo=""
prev=""
for a in "$@"; do
  [ "$prev" = "-R" ] && repo="$a"
  prev="$a"
done
key="${repo//\//_}"
case "$1 $2" in
  "pr list")
    n=$(( $(cat "$FAKE_DATA/$key.count" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$FAKE_DATA/$key.count"
    f="$FAKE_DATA/$key.$n.json"
    [ -f "$f" ] || f="$FAKE_DATA/$key.json"
    [ -f "$f" ] || { echo "gh: not found: $repo" >&2; exit 1; }
    cat "$f" ;;
  "run view")
    [ -f "$FAKE_DATA/runlog.txt" ] || { echo "gh: no logs" >&2; exit 1; }
    cat "$FAKE_DATA/runlog.txt" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DATA="$TMP/data" HOME="$TMP/home"
unset FLEET_FILE
FL="$REPO/bin/fleet"

ok='{"name":"test","status":"COMPLETED","conclusion":"SUCCESS"}'
skip='{"name":"lint","status":"COMPLETED","conclusion":"SKIPPED"}'
run='{"name":"test","status":"IN_PROGRESS","conclusion":""}'
bad='{"name":"lint","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/a/actions/runs/777/job/1"}'
rev='[{"name":"REVIEWED"}]'

pr() { # number title head labels merge checks
  printf '{"number":%s,"title":"%s","headRefName":"%s","labels":%s,"mergeStateStatus":"%s","author":{"login":"me"},"statusCheckRollup":[%s]}' "$1" "$2" "$3" "$4" "$5" "$6"
}
put() { echo "[$2]" > "$TMP/data/$1.json"; }
reset() { find "$TMP/data" -type f -delete; }
ready_of() { jq -r --argjson n "$2" '.[] | select(.number==$n) | .ready' <<<"$1"; }

echo "-- repo list precedence"
reset; put o_a "$(pr 1 one feat-x "$rev" CLEAN "$ok")"; put o_b "$(pr 2 two feat-y "$rev" CLEAN "$ok")"
put o_f "$(pr 3 three feat-z "$rev" CLEAN "$ok")"; put o_d "$(pr 4 four feat-w "$rev" CLEAN "$ok")"
printf '# comment\no/f  # trailing\n\n' > "$TMP/fleet.txt"
mkdir -p "$TMP/home/.config/do-no-work"; printf 'o/d\n' > "$TMP/home/.config/do-no-work/fleet.txt"
out=$(FLEET_FILE="$TMP/fleet.txt" "$FL" ready --repos o/a,o/b)
check "--repos wins over FLEET_FILE" "[ \"\$out\" = \"\$(printf 'o/a#1\no/b#2')\" ]"
out=$(FLEET_FILE="$TMP/fleet.txt" "$FL" ready)
check "FLEET_FILE wins over default path" "[ \"\$out\" = 'o/f#3' ]"
out=$("$FL" ready)
check "default path used" "[ \"\$out\" = 'o/d#4' ]"
mv "$TMP/home/.config/do-no-work/fleet.txt" "$TMP/home/fleet.moved"
rc=0; "$FL" ready > "$TMP/out" 2> "$TMP/err" || rc=$?
check "no list: exit 2 with hint" "[ $rc -eq 2 ] && grep -q 'examples/fleet.txt' '$TMP/err'"
rc=0; "$FL" ready --repos notarepo > "$TMP/out" 2> "$TMP/err" || rc=$?
check "bad repo name rejected" "[ $rc -eq 2 ]"

echo "-- ready computation"
reset
put o_a "$(pr 1 ok f "$rev" CLEAN "$ok,$skip"),$(pr 2 pending f "$rev" CLEAN "$ok,$run"),$(pr 3 failing f "$rev" CLEAN "$ok,$bad"),$(pr 4 unreviewed f '[]' CLEAN "$ok"),$(pr 5 dirty f "$rev" DIRTY "$ok")"
rows=$("$FL" prs --repos o/a --json)
check "skipped counts as pass: ready" "[ \"\$(ready_of \"\$rows\" 1)\" = true ]"
check "pending: not ready" "[ \"\$(ready_of \"\$rows\" 2)\" = false ]"
check "failure: not ready" "[ \"\$(ready_of \"\$rows\" 3)\" = false ]"
check "missing REVIEWED: not ready" "[ \"\$(ready_of \"\$rows\" 4)\" = false ]"
check "DIRTY: not ready" "[ \"\$(ready_of \"\$rows\" 5)\" = false ]"
check "check counts" "jq -e '.[0].pass==2 and .[2].fail==1 and .[1].pending==1' <<<\"\$rows\" >/dev/null"
table=$("$FL" prs --repos o/a)
check "table has header and rows" "grep -q '^REPO' <<<\"\$table\" && grep -q 'o/a *1 *ok' <<<\"\$table\""
put o_a "$(pr 9 'a title that is much longer than fifty characters in total length' f "$rev" CLEAN "$ok")"
table=$("$FL" prs --repos o/a)
check "title truncated to 50" "grep -q 'a title that is much longer than fifty characte\\.\\.\\.' <<<\"\$table\""

echo "-- ready output"
put o_a "$(pr 1 ok f "$rev" CLEAN "$ok"),$(pr 2 pending f "$rev" CLEAN "$run")"
put o_b "$(pr 7 other f "$rev" CLEAN "$ok")"
out=$("$FL" ready --repos o/a,o/b)
check "ready lists owner/repo#N only" "[ \"\$out\" = \"\$(printf 'o/a#1\no/b#7')\" ]"

echo "-- head glob"
put o_a "$(pr 1 a NO-TICKET-one "$rev" CLEAN "$ok"),$(pr 2 b feature-two "$rev" CLEAN "$ok"),$(pr 3 c NO-TICKET-three "$rev" CLEAN "$ok")"
out=$("$FL" ready --repos o/a --head 'NO-TICKET-*')
check "--head filters by glob" "[ \"\$out\" = \"\$(printf 'o/a#1\no/a#3')\" ]"

echo "-- watch"
printf 'job\tstep\t2026-01-01T00:00:00Z ##[error]Process completed with exit code 1.\n' > "$TMP/data/runlog.txt"
put o_a "$(pr 1 ok f "$rev" CLEAN "$ok")"
rc=0; "$FL" watch --repos o/a --interval 0 > "$TMP/out" || rc=$?
check "all ready: exit 0" "[ $rc -eq 0 ]"
put o_a "$(pr 1 ok f "$rev" CLEAN "$ok"),$(pr 3 failing f "$rev" CLEAN "$bad")"
rc=0; "$FL" watch --repos o/a --interval 0 > "$TMP/out" || rc=$?
check "failure: exit 1" "[ $rc -eq 1 ]"
check "prints extracted error line" "grep -qx 'o/a#3 lint: Process completed with exit code 1.' '$TMP/out'"
mv "$TMP/data/runlog.txt" "$TMP/data/runlog.moved"
rc=0; "$FL" watch --repos o/a --interval 0 > "$TMP/out" || rc=$?
check "missing logs reported" "grep -qx 'o/a#3 lint: logs unavailable' '$TMP/out'"
put o_a "$(pr 1 ok f "$rev" CLEAN "$run")"
rc=0; "$FL" watch --repos o/a --interval 0 --timeout 1 > "$TMP/out" 2> "$TMP/err" || rc=$?
check "timeout: exit 2" "[ $rc -eq 2 ] && grep -q 'timed out' '$TMP/err'"
reset
put o_a "$(pr 1 ok f "$rev" CLEAN "$run")"
echo "[$(pr 1 ok f "$rev" CLEAN "$ok")]" > "$TMP/data/o_a.2.json"
rc=0; "$FL" watch --repos o/a --interval 0 --timeout 30 > "$TMP/out" || rc=$?
check "polls until pending clears, exit 0" "[ $rc -eq 0 ] && [ \"\$(cat '$TMP/data/o_a.count')\" -ge 2 ]"
rm -f "$TMP/data/o_a.count"
rc=0; "$FL" watch --repos o/a --interval 0 --json > "$TMP/out" || rc=$?
check "watch --json parses" "jq -e 'length==1 and .[0].ready' '$TMP/out' >/dev/null"

echo "-- errors"
rc=0; "$FL" prs --repos o/missing > "$TMP/out" 2> "$TMP/err" || rc=$?
check "gh failure surfaces, exit 1" "[ $rc -eq 1 ] && grep -q 'o/missing' '$TMP/err'"
rc=0; "$FL" bogus > "$TMP/out" 2> "$TMP/err" || rc=$?
check "unknown subcommand exit 2" "[ $rc -eq 2 ]"

mv "$TMP" "$HOME/.trash/fleet_test.$$" 2>/dev/null || true
exit $fail
