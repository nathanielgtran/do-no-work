#!/bin/bash
# Flip the autonomy dial from a plain chat phrase.
# STRICT: the trimmed, lowercased prompt must be EXACTLY the phrase (+ optional . or !),
# so "go fully autonomous" / "go less strict on X" never mis-fire.
set -uo pipefail
p=$(jq -r '.prompt // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[.!]+$//')
f="$HOME/.claude/autonomy-level"

case "$p" in
  "go less"|"go into less"|"go into less mode")  lvl=less
    msg="Autonomy -> LESS. git push + gh pr merge now HARD-BLOCKED by hook. Say 'go full' to restore." ;;
  "go full"|"go into full"|"go into full mode")  lvl=full
    msg="Autonomy -> FULL. Free push + gated self-merge (REVIEWED + green CI) restored." ;;
  *) exit 0 ;;
esac

if ! echo "$lvl" > "$f" 2>/dev/null; then
  printf '{"systemMessage":"autonomy-toggle: FAILED to write %s (state unchanged). Check ~/.claude/autonomy-level perms."}\n' "$f"
  exit 0
fi
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"autonomy-level = %s"}}\n' "$msg" "$(tr -d '[:space:]' < "$f")"
