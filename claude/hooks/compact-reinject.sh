#!/bin/bash
# SessionStart hook (matcher "compact"): re-inject critical rules after compaction.
# Plain stdout from SessionStart is added to Claude's context (hooks doc, SessionStart).
# Always exits 0; missing files are skipped silently.
DIGEST="${COMPACT_DIGEST:-$HOME/.claude/compact-digest.md}"
input=$(cat 2>/dev/null)
# cwd from hook JSON (no jq dependency), fallback $PWD
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -d "$cwd" ] || cwd="$PWD"
if [ -r "$DIGEST" ]; then
  cat "$DIGEST" 2>/dev/null
fi
if [ -r "$cwd/.claude/HANDOFF.md" ]; then
  printf '\nSESSION HANDOFF (%s/.claude/HANDOFF.md, first 30 lines; git log/status wins if they disagree):\n' "$cwd"
  head -n 30 "$cwd/.claude/HANDOFF.md" 2>/dev/null
fi
exit 0
