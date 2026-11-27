#!/bin/bash
# Exercises scripts/public-safety-check.sh with synthetic values only.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO/scripts/public-safety-check.sh"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

work="$(mktemp -d)"
home="$(mktemp -d)"
deny="$work/deny"
printf '# synthetic\nacme-secret-client\n' >"$deny"
REAL_USER="${USER:-}"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null USER=nobody-synthetic

new_repo() {
  local d
  d="$(mktemp -d "$work/r.XXXX")"
  git -C "$d" init -q
  git -C "$d" config user.email "jane.doe@example.org"
  git -C "$d" config user.name "Jane Doe"
  printf 'ok\n' >"$d/clean.txt"
  echo "$d"
}

run_in() {
  local d="$1"
  shift
  git -C "$d" add -A
  (cd "$d" && env HOME="$home" "$@" "$CHECK" 2>&1) || true
}

d="$(new_repo)"
printf 'a\nhost 192.168.1.5\n' >"$d/lan.txt"  # public-safety: allow
out="$(run_in "$d" PUBLIC_SAFETY_DENY="$deny")"
check "builtin LAN IP reported with line" "grep -q 'lan.txt:2:.*builtin' <<<\"\$out\""
check "builtin hit echoes the line"       "grep -q '192\\.168\\.1\\.5' <<<\"\$out\""

d="$(new_repo)"
printf 'x\nwork for Acme-Secret-Client today\n' >"$d/note.txt"
out="$(run_in "$d" PUBLIC_SAFETY_DENY="$deny")"
check "private hit reported with line"   "grep -q 'note.txt:2:.*private' <<<\"\$out\""
check "private pattern not echoed"       "! grep -qi 'acme-secret-client' <<<\"\$out\""
out="$(run_in "$d" PUBLIC_SAFETY_DENY=/nonexistent PUBLIC_SAFETY_DENY_LIST=$'# c\nacme-secret-client')"
check "CI env list used, not echoed"     "grep -q 'note.txt:2:.*private' <<<\"\$out\" && ! grep -qi 'acme-secret' <<<\"\$out\""

d="$(new_repo)"
printf 'mail jane.doe@example.org\n' >"$d/mail.txt"
out="$(run_in "$d" PUBLIC_SAFETY_DENY="$deny")"
check "derived git email hit"            "grep -q 'mail.txt:1:.*derived' <<<\"\$out\" && ! grep -q 'jane.doe' <<<\"\$out\""

d="$(new_repo)"
printf 'host 10.0.0.7 public-safety: allow\n' >"$d/ok.txt"
out="$(run_in "$d" PUBLIC_SAFETY_DENY="$deny")"
check "allow marker skips the line"      "grep -q 'ok (' <<<\"\$out\""

d="$(new_repo)"
printf 'x 10.1.2.3\n' >"$d/ip.txt"  # public-safety: allow
out="$(run_in "$d" PUBLIC_SAFETY_DENY="$work/missing")"
check "missing private list: note"       "grep -q 'no private list' <<<\"\$out\""
check "missing private list: still runs" "grep -q 'ip.txt:1:.*builtin' <<<\"\$out\""

d="$(new_repo)"
printf 'path /home/someuser/x\n' >"$d/p.txt"  # public-safety: allow
out="$(run_in "$d" PUBLIC_SAFETY_DENY="$deny")"
check "home path flagged"                "grep -q 'p.txt:1:.*builtin' <<<\"\$out\""

empty="$(mktemp -d)"
out="$(cd "$REPO" && env HOME="$empty" USER="$REAL_USER" "$CHECK" 2>&1)" && rc=0 || rc=$?
check "real repo passes (builtin + derived)" "[ $rc -eq 0 ]"
[ "$rc" -eq 0 ] || echo "$out"
exit $fail
