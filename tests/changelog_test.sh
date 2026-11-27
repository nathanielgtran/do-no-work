#!/bin/bash
# Exercises scripts/changelog.sh in a throwaway git repo.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CL="$REPO/scripts/changelog.sh"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

TMP="$(mktemp -d)"
export TRASH_DIR="$TMP/trash"
W="$TMP/w"
mkdir "$W" && cd "$W"
git init -q . && git config user.email t@example.invalid && git config user.name t
mkdir changelog.d
echo readme > changelog.d/README.md
printf '# Changelog\n\n## Unreleased\n- feat-2: old two\n- fix-7: old fix\n' > CHANGELOG.md
git add -A && git commit -qm init

echo "-- next"
echo "frag" > changelog.d/feat-5.md
echo "frag" > changelog.d/docs-1.md
check "next feat skips changelog and fragments" '[ "$("$CL" next feat)" = feat-6 ]'
check "next fix skips changelog" '[ "$("$CL" next fix)" = fix-8 ]'
check "next docs skips fragment" '[ "$("$CL" next docs)" = docs-2 ]'
check "next chore starts at 1" '[ "$("$CL" next chore)" = chore-1 ]'
check "next rejects bad type" '! "$CL" next bogus 2>/dev/null'

echo "-- check"
check "check passes on good fragments" '"$CL" check >/dev/null'
echo "x" > changelog.d/oops.md
check "check flags bad name" '! out=$("$CL" check 2>&1) && echo "$out" | grep -q oops.md'
rm_frag() { mv "$1" "$TMP/"; }
rm_frag changelog.d/oops.md
printf 'one\ntwo\n' > changelog.d/fix-9.md
check "check flags two-line fragment" '! out=$("$CL" check 2>&1) && echo "$out" | grep -q fix-9.md'
: > changelog.d/fix-9.md
check "check flags empty fragment" '! "$CL" check >/dev/null 2>&1'
echo "dup" > changelog.d/fix-9.md
echo "dup" > changelog.d/feat-2.md
check "check flags ID already in CHANGELOG" '! out=$("$CL" check 2>&1) && echo "$out" | grep -q feat-2'
rm_frag changelog.d/feat-2.md

echo "-- compile"
echo "nine" > changelog.d/fix-9.md
echo "ten" > changelog.d/feat-10.md
echo "chore one" > changelog.d/chore-1.md
git add -A
"$CL" compile >/dev/null
check "fragments removed" '[ "$(ls changelog.d)" = README.md ]'
body="$(sed -n '/## Unreleased/,$p' CHANGELOG.md | head -8 | tail -7)"
expected="- feat-5: frag
- feat-10: ten
- fix-9: nine
- docs-1: frag
- chore-1: chore one
- feat-2: old two
- fix-7: old fix"
export body expected
check "sorted under Unreleased" '[ "$body" = "$expected" ]'
before="$(cat CHANGELOG.md)"
out="$("$CL" compile)"
export before out
check "second compile no-op" '[ "$(cat CHANGELOG.md)" = "$before" ] && echo "$out" | grep -qi "no fragments"'

echo "-- compile --version"
echo "new thing" > changelog.d/feat-20.md
"$CL" compile --version v1.2.3 >/dev/null
check "dated heading created" 'grep -qE "^## v1\.2\.3 - [0-9]{1,2} [A-Z][a-z]{2} [0-9]{4}$" CHANGELOG.md'
check "fragment under version heading" '[ "$(grep -A1 "^## v1.2.3" CHANGELOG.md | tail -1)" = "- feat-20: new thing" ]'
check "Unreleased kept above" '[ "$(grep -n "^## Unreleased" CHANGELOG.md | cut -d: -f1)" -lt "$(grep -n "^## v1.2.3" CHANGELOG.md | cut -d: -f1)" ]'

exit "$fail"
