#!/bin/bash
# sync-check.sh - report whether the rubrics' pinned upstream sources have moved.
#
# Usage: sync-check.sh [rubric file ...]   (default: every rubric*.md in the skill dir)
# Each rubric pins its sources on lines of the form:
#   <!-- upstream: <owner/repo> <path> commit=<sha> blob=<sha> -->
# This script asks GitHub for the latest commit touching that path and the current
# blob sha, and prints OK or DRIFT per source. It never rewrites anything; when a
# source drifted, read the upstream diff and update rubric.md and the pin by hand.
#
# Exit 0 = all pinned, 1 = at least one drift, 2 = usage or API error.
set -uo pipefail

if [ $# -gt 0 ]; then RUBRICS=("$@"); else RUBRICS=("$(dirname "$0")"/../rubric*.md); fi
for r in "${RUBRICS[@]}"; do [ -r "$r" ] || { echo "sync-check: cannot read $r" >&2; exit 2; }; done

check_one() { # <repo> <path> <pinned commit> <pinned blob>
  local repo=$1 path=$2 commit=$3 blob=$4 latest_commit latest_blob
  latest_commit=$(gh api "repos/$repo/commits?path=$path&per_page=1" --jq '.[0].sha' 2>&1) \
    || { echo "ERROR $repo/$path: $latest_commit"; return 2; }
  latest_blob=$(gh api "repos/$repo/contents/$path" --jq .sha 2>&1) \
    || { echo "ERROR $repo/$path: $latest_blob"; return 2; }
  if [ "$latest_blob" = "$blob" ]; then
    echo "OK    $repo/$path (blob unchanged; latest commit ${latest_commit:0:7})"
    return 0
  fi
  echo "DRIFT $repo/$path: pinned ${commit:0:7}/${blob:0:7}, upstream ${latest_commit:0:7}/${latest_blob:0:7}"
  echo "      view: https://github.com/$repo/compare/${commit:0:12}...${latest_commit:0:12}"
  return 1
}

rc=0
while read -r repo path commit blob; do
  check_one "$repo" "$path" "${commit#commit=}" "${blob#blob=}"
  r=$?; [ "$r" -gt "$rc" ] && rc=$r
done < <(sed -nE 's/^<!-- upstream: ([^ ]+) ([^ ]+) (commit=[0-9a-f]+) (blob=[0-9a-f]+) -->$/\1 \2 \3 \4/p' "${RUBRICS[@]}")

[ "$rc" -eq 0 ] && echo "All rubric sources are pinned to current upstream."
exit "$rc"
