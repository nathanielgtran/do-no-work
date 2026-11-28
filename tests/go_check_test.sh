#!/bin/bash
# Runs go-check against stub go, gofmt and golangci-lint binaries and checks silence, stderr and exit codes.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/claude/hooks/go-check.sh"
fail=0
tmp="$(mktemp -d)"
export HOME="$tmp/home"
mkdir -p "$HOME" "$tmp/bin" "$tmp/mod/pkg" "$tmp/plain"
echo 'module x' > "$tmp/mod/go.mod"
echo 'package pkg' > "$tmp/mod/pkg/a.go"
echo 'hi' > "$tmp/mod/README.md"
echo 'package p' > "$tmp/plain/b.go"
log="$tmp/calls"

cat > "$tmp/bin/go" <<STUB
#!/bin/bash
echo "go \$*" >> "$log"
if [ "\$1" = vet ] && [ -e "$tmp/fail-vet" ]; then echo "vet: boom"; exit 1; fi
exit 0
STUB
cat > "$tmp/bin/gofmt" <<STUB
#!/bin/bash
echo "gofmt \$*" >> "$log"
if [ -e "$tmp/fail-fmt" ]; then echo "\$2"; fi
exit 0
STUB
cat > "$tmp/bin/golangci-lint" <<STUB
#!/bin/bash
echo "golangci-lint \$*" >> "$log"
if [ -e "$tmp/fail-lint" ]; then seq 1 100; exit 1; fi
exit 0
STUB
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"

run() {
  : > "$log"
  OUT="" ERR="" RC=0
  jq -n --arg f "$1" '{tool_input:{file_path:$f}}' | bash "$HOOK" >"$tmp/out" 2>"$tmp/err" || RC=$?
  OUT="$(cat "$tmp/out")"; ERR="$(cat "$tmp/err")"
}
check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1 (rc=$RC out='$OUT' err='$ERR')"; fail=1; fi
}

run "$tmp/mod/pkg/a.go"
check "pass: silent exit 0" '[ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]'
check "pass: never runs go test" '! grep -q "^go test" "$log"'
check "pass: runs vet, gofmt and lint" 'grep -q "^go vet ./pkg" "$log" && grep -q "^gofmt -l" "$log" && grep -q "^golangci-lint run --new-from-rev=HEAD ./pkg" "$log"'

touch "$tmp/fail-vet"; run "$tmp/mod/pkg/a.go"; rm "$tmp/fail-vet"
check "vet failure: exit 2" '[ "$RC" = 2 ]'
check "vet failure: stderr report" 'case "$ERR" in "VET ISSUES (./pkg):"*vet:\ boom*) true ;; *) false ;; esac'
check "vet failure: stdout empty" '[ -z "$OUT" ]'

touch "$tmp/fail-fmt"; run "$tmp/mod/pkg/a.go"; rm "$tmp/fail-fmt"
check "gofmt failure: exit 2 naming FORMAT" '[ "$RC" = 2 ] && case "$ERR" in *FORMAT*a.go*) true ;; *) false ;; esac'

touch "$tmp/fail-lint"; run "$tmp/mod/pkg/a.go"; rm "$tmp/fail-lint"
check "lint failure: exit 2 naming LINT" '[ "$RC" = 2 ] && case "$ERR" in *"LINT ISSUES (./pkg):"*) true ;; *) false ;; esac'
check "lint failure: clipped to 40 lines" '[ "$(printf "%s\n" "$ERR" | grep -cE "^[0-9]+$")" = 40 ]'

run "$tmp/mod/README.md"
check "non-go file: silent exit 0, nothing run" '[ "$RC" = 0 ] && [ -z "$OUT$ERR" ] && [ ! -s "$log" ]'
run "$tmp/plain/b.go"
check "go file outside a module: silent exit 0" '[ "$RC" = 0 ] && [ -z "$OUT$ERR" ] && [ ! -s "$log" ]'
RC=0; echo '{"tool_input":{}}' | bash "$HOOK" >"$tmp/out" 2>"$tmp/err" || RC=$?
check "no file_path: silent exit 0" '[ "$RC" = 0 ] && [ ! -s "$tmp/out" ] && [ ! -s "$tmp/err" ]'
exit $fail
