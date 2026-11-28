#!/bin/bash
# PostToolUse hook, wired with "if": "Bash(gh pr create:*)": tells the session how the new PR gets reviewed.
# Never tells the session to apply REVIEWED; CI claude-review does that.
set -uo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && { cd "$CWD" 2>/dev/null || true; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

PR=$(printf '%s' "$INPUT" | jq -r '(.tool_response // "") | tostring' 2>/dev/null | grep -oE '/pull/[0-9]+' | head -n 1 | tr -dc '0-9')
PR="${PR:-<N>}"

if grep -qsr 'claude-review' "$ROOT/.github/workflows"; then
  MSG="A PR was just created. CI claude-review will review it and apply REVIEWED. Wait with: gh pr checks $PR --watch --interval 20. Merge with one literal PR number, gh pr merge $PR --squash --delete-branch, only when REVIEWED is on and all checks are green. Never add REVIEWED yourself. A claude-review block is a red check: fix the findings and push."
else
  MSG="A PR was just created. This repo has no CI review. Spawn one reviewer agent with the PR diff and report its findings. Leave REVIEWED and the merge to the user."
fi

jq -n --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
