#!/bin/bash
# Autonomy dial enforcement + tamper guard. Runs on EVERY Bash call (no `if` filter),
# so bypass forms (git -C, cd && push, VAR=1 git push, command git push) are all seen.
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null); jq_rc=$?

emit() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"; exit 0; }
deny() { emit deny "$1"; }
ask()  { emit ask  "$1"; }

# Fail-CLOSED: if the command can't be parsed, prompt rather than pass through.
[ "$jq_rc" -eq 0 ] || ask "autonomy-gate: could not parse command (jq failed) — prompting."

# Tamper guard (ALL levels): block WRITES to the dial/hooks from Bash (redirect, editor,
# mutating coreutil). Reads/greps/cats of these paths pass through untouched.
tgt='\.claude/(autonomy-level|hooks/)'
if printf '%s' "$cmd" | grep -Eq ">>?[^&;|]*$tgt" \
   || printf '%s' "$cmd" | grep -Eq "[[:space:]](tee|cp|mv|rm|ln|chmod|chown|truncate|install|dd)[[:space:]][^&;|]*$tgt" \
   || printf '%s' "$cmd" | grep -Eq "sed[[:space:]]+-i[^&;|]*$tgt" \
   || printf '%s' "$cmd" | grep -Eq "\b(vi|vim|nano|emacs|ex|ed)\b[^&;|]*$tgt"; then
  deny "autonomy-gate: refusing to WRITE the autonomy dial or its hooks from Bash. Use a ! command or lift the guard manually."
fi

# Read level. File absent -> default full (documented). Unreadable -> fail-closed (ask).
f="$HOME/.claude/autonomy-level"
if [ -e "$f" ]; then
  level=$(tr -d '[:space:]' < "$f" 2>/dev/null) || ask "autonomy-gate: state file unreadable — prompting."
else
  level=full
fi
[ "$level" = "less" ] || exit 0

# less mode: deny push + merge.
# git [ -C dir | -opts ]* push   (covers plain, -C, env-prefixed, cd && git push)
if printf '%s' "$cmd" | grep -Eq '\bgit\b([[:space:]]+-[^[:space:]]+|[[:space:]]+-C[[:space:]]+[^[:space:]]+)*[[:space:]]+push\b'; then
  deny "autonomy=less: PUSH blocked. The user pushes manually in less mode. Say 'go full' to restore."
fi
# gh ... pr ... merge   AND   gh ... api ... merge (REST merge bypass)
if printf '%s' "$cmd" | grep -Eq '\bgh\b[^&;|]*\bpr\b[^&;|]*\bmerge\b|\bgh\b[^&;|]*\bapi\b[^&;|]*merge'; then
  deny "autonomy=less: MERGE blocked (incl. gh api). Route this PR to a human. Say 'go full' to restore."
fi
exit 0
