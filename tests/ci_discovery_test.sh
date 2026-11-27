#!/bin/bash
# Guards CI test discovery: no per-test steps in ci.yml, run-all --list covers every test.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

if grep -nE 'tests/[A-Za-z0-9_.-]+_test\.sh' "$REPO/.github/workflows/ci.yml"; then
  echo "FAIL: ci.yml references individual tests; use tests/run-all.sh" >&2
  fail=1
fi

listed="$("$REPO/tests/run-all.sh" --list)"
for f in "$REPO"/tests/*_test.sh; do
  n="$(basename "$f")"
  if ! grep -qx "$n" <<<"$listed"; then
    echo "FAIL: run-all --list is missing $n" >&2
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then echo "ok ci discovery"; fi
exit "$fail"
