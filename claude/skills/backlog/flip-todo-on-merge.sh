#!/bin/bash
# flip-todo-on-merge.sh — flip matching open TODO.md checkbox to [x] when a PR merges.
# Usage:
#   ./flip-todo-on-merge.sh [PR_NUMBER] [--dry-run]
#   echo '{"tool":"Bash","tool_input":{"command":"gh pr merge 154 --merge"}}' | ./flip-todo-on-merge.sh [--dry-run]
# PostToolUse hook: reads stdin JSON; falls back to CLI arg; falls back to most recent merged PR.

set -euo pipefail

log() { echo "[flip-todo] $*" >&2; }
die() { echo "[flip-todo] ERROR: $*" >&2; exit 1; }

usage() {
  echo "Usage: $0 [PR_NUMBER] [--dry-run]" >&2
  exit 1
}

DRY_RUN=false
PR_NUMBER=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help|-h) usage ;;
    [0-9]*) PR_NUMBER="$arg" ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

if ! git rev-parse --show-toplevel &>/dev/null; then
  die "Not inside a git repository. Run from within a repo."
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
TODO_FILE="${REPO_ROOT}/TODO.md"

if [[ ! -f "$TODO_FILE" ]]; then
  log "No TODO.md found at ${TODO_FILE}. Nothing to flip."
  exit 0
fi

if [[ -z "$PR_NUMBER" ]] && [[ ! -t 0 ]]; then
  STDIN_JSON=""
  if IFS= read -r -t 2 STDIN_JSON 2>/dev/null || true; then
    if [[ -n "$STDIN_JSON" ]]; then
      EXTRACTED=$(echo "$STDIN_JSON" | grep -oP '(?<=gh pr merge )\d+' || true)
      if [[ -n "$EXTRACTED" ]]; then
        PR_NUMBER="$EXTRACTED"
        log "Detected PR #${PR_NUMBER} from hook stdin."
      fi
    fi
  fi
fi

if [[ -z "$PR_NUMBER" ]]; then
  log "No PR number provided or detected. Querying most recently merged PR..."
  PR_NUMBER=$(gh pr list --state merged --limit 1 --json number --jq '.[0].number' 2>/dev/null || true)
  if [[ -z "$PR_NUMBER" ]]; then
    die "Could not determine PR number. Pass it as an argument or run from a hook."
  fi
  log "Using most recently merged PR: #${PR_NUMBER}"
fi

log "Fetching PR #${PR_NUMBER} metadata..."

PR_JSON=$(gh pr view "$PR_NUMBER" --json title,headRefName,number 2>/dev/null) \
  || die "Failed to fetch PR #${PR_NUMBER}. Check the number and gh auth."

PR_TITLE=$(echo "$PR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['title'])" 2>/dev/null || true)
PR_BRANCH=$(echo "$PR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['headRefName'])" 2>/dev/null || true)

log "PR title : ${PR_TITLE}"
log "PR branch: ${PR_BRANCH}"

# Change-ID priority: [fix-129] in title, then fix-129-... branch prefix,
# then a bare fix-129 in the title as a last resort.
extract_bracket_ids() {
  echo "$1" | grep -oP '(?<=\[)[a-z]+-\d+(?=\])' || true
}

extract_branch_prefix_id() {
  echo "$1" | grep -oP '^[a-z]+-\d+(?=-|$)' || true
}

extract_bare_ids() {
  echo "$1" | grep -oP '\b[a-z]+-\d+\b' || true
}

ALL_IDS=""

add_id() {
  local id="$1"
  if [[ -n "$id" ]] && ! echo " ${ALL_IDS} " | grep -qw "$id"; then
    ALL_IDS="${ALL_IDS} ${id}"
  fi
}

for id in $(extract_bracket_ids "$PR_TITLE"); do add_id "$id"; done
for id in $(extract_branch_prefix_id "$PR_BRANCH"); do add_id "$id"; done

if [[ -z "${ALL_IDS// /}" ]]; then
  for id in $(extract_bare_ids "$PR_TITLE"); do add_id "$id"; done
fi

ALL_IDS="${ALL_IDS# }"

if [[ -z "$ALL_IDS" ]]; then
  log "No change-IDs found in PR #${PR_NUMBER} title or branch. Nothing to flip."
  exit 0
fi

log "Change-IDs found: ${ALL_IDS}"

FLIPPED=0
NOT_FOUND=()
ALREADY_DONE=()

flip_id() {
  local id="$1"

  local open_lines
  open_lines=$(grep -n "^- \[ \]" "$TODO_FILE" | grep -P "\b${id}\b" || true)

  if [[ -z "$open_lines" ]]; then
    local closed_line
    closed_line=$(grep -n "^- \[x\]" "$TODO_FILE" | grep -P "\b${id}\b" || true)
    if [[ -n "$closed_line" ]]; then
      log "ID '${id}': already marked [x] — skipping."
      ALREADY_DONE+=("$id")
    else
      log "ID '${id}': no matching open line in TODO.md — no change."
      NOT_FOUND+=("$id")
    fi
    return
  fi

  while IFS= read -r match; do
    local lineno linetext
    lineno=$(echo "$match" | cut -d: -f1)
    linetext=$(echo "$match" | cut -d: -f2-)

    if [[ "$DRY_RUN" == "true" ]]; then
      log "[DRY-RUN] Would flip line ${lineno}: ${linetext:0:80}"
      FLIPPED=$((FLIPPED + 1))
    else
      local tmp_file
      tmp_file="${TODO_FILE}.flip.tmp"
      awk \
        -v target="$lineno" \
        -v id="$id" \
        'NR == target && /^- \[ \]/ && index($0, id) {
           sub(/^- \[ \]/, "- [x]")
         }
         { print }' \
        "$TODO_FILE" > "$tmp_file"
      mv "$tmp_file" "$TODO_FILE"
      log "ID '${id}': flipped line ${lineno} to [x]."
      FLIPPED=$((FLIPPED + 1))
    fi
  done <<< "$open_lines"
}

for id in $ALL_IDS; do
  flip_id "$id"
done

echo ""
echo "[flip-todo] === Summary for PR #${PR_NUMBER} ==="
echo "[flip-todo] Change-IDs scanned : ${ALL_IDS}"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[flip-todo] Mode              : DRY-RUN (no changes written)"
else
  echo "[flip-todo] Mode              : LIVE"
fi
echo "[flip-todo] Lines flipped      : ${FLIPPED}"
if [[ ${#ALREADY_DONE[@]} -gt 0 ]]; then
  echo "[flip-todo] Already done       : ${ALREADY_DONE[*]}"
fi
if [[ ${#NOT_FOUND[@]} -gt 0 ]]; then
  echo "[flip-todo] Not found in TODO  : ${NOT_FOUND[*]}"
fi
echo "[flip-todo] TODO.md            : ${TODO_FILE}"
