#!/bin/bash
# Fails on shell patterns that broke on macOS (BSD tools, bash 3.2) in CI on 27 Nov 2026.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
fail=0

scan() {
  local name="$1" pattern="$2" hits
  hits=$(git ls-files bin scripts tests install.sh claude/hooks |
    grep -v '^tests/portability_test.sh$' |
    xargs grep -nE -- "$pattern" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL $name"
    printf '%s\n' "$hits" | sed 's/^/     /'
    fail=1
  else
    echo "ok   $name"
  fi
}

scan "no grep -P (BSD grep lacks it)" 'grep +-[a-zA-Z]*P'
scan "no string compare on wc -l (BSD wc pads)" '"\$\(wc -l[^)]*\)" *!?= '
scan "no escaped quotes inside \${var:-default} (bash 3.2 keeps the backslashes)" '\$\{[A-Za-z_]+:-[^}]*\\"'
exit $fail
