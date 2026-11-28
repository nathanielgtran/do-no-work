#!/bin/bash
set -uo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
printf '%s' "$CMD" | grep -qE '(^|[;&|(`[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0

OUT=$(printf '%s' "$INPUT" | jq -r '.tool_response | if type == "object" then (.stdout // "") else tostring end' 2>/dev/null)
PR=$(printf '%s\n' "$OUT" | grep -E '^https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+$' | tail -n 1 | sed 's#.*/pull/##')
[ -n "$PR" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && { cd "$CWD" 2>/dev/null || true; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if grep -qsr 'claude-review' "$ROOT/.github/workflows"; then
  MSG="A PR was just created. CI claude-review will review it and apply REVIEWED. Wait with: gh pr checks $PR --watch --interval 20. Merge with one literal PR number, gh pr merge $PR --squash --delete-branch, only when REVIEWED is on and all checks are green. Never add REVIEWED yourself. A claude-review block is a red check: fix the findings and push."
else
  MSG="A PR was just created. This repo has no CI review. Spawn one reviewer agent with the PR diff and report its findings. Leave REVIEWED and the merge to the user."
fi

jq -n --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
