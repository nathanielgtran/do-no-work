#!/bin/bash
# OpenSpec standing autonomy (see CLAUDE.md), enforced as a hook.
# Inside a repo with openspec/config.yaml, auto-ALLOW Bash so reversible ceremony
# (commit, rebase, force-with-lease, worktree/branch cleanup, PR plumbing) doesn't prompt.
# Falls through (no decision) on anything in the hard-stop list or outside an OpenSpec repo.
# Deny rules in settings.json and other hooks (autonomy-gate deny, gate-self-merge ask)
# still win: the most restrictive decision across hooks applies.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] && [ -n "$cwd" ] || exit 0

# Autonomy dial: only in full mode.
f="$HOME/.claude/autonomy-level"
level=full; [ -e "$f" ] && level=$(tr -d '[:space:]' < "$f" 2>/dev/null)
[ "$level" = "full" ] || exit 0

is_openspec() {
  local top
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  # linked worktrees share the main repo's openspec/ via the checkout itself
  [ -f "$top/openspec/config.yaml" ]
}

# A command that opens with `cd <dir>` runs there, not in the session cwd.
lead=$(printf '%s' "$cmd" | sed -nE '1s/^[[:space:]]*cd[[:space:]]+([^[:space:];&|]+).*/\1/p')
lead="${lead/#\~/$HOME}"
if [ -n "$lead" ]; then
  case "$lead" in /*) ;; *) lead="$cwd/$lead" ;; esac
  is_openspec "$lead" || exit 0
else
  is_openspec "$cwd" || exit 0
fi

# Every directory the command moves into (cd X, git -C X) must also be an OpenSpec repo
# or a scratch/temp dir.
while read -r d; do
  [ -z "$d" ] && continue
  d="${d/#\~/$HOME}"; d="${d%\"}"; d="${d#\"}"; d="${d%\'}"; d="${d#\'}"
  case "$d" in /*) ;; *) d="$cwd/$d" ;; esac
  case "$d" in /tmp/*) continue ;; esac
  is_openspec "$d" || exit 0
done < <(printf '%s' "$cmd" | grep -oE '(\bcd|\bgit[[:space:]]+-C)[[:space:]]+[^[:space:];&|)]+' | awk '{print $NF}')

# Hard stops: never auto-allow these. Fall through to normal permission handling.
hard='(^|[;&|(`[:space:]])(rm|sudo|dd|mkfs|shred|ssh|scp|rsync)([[:space:]]|$)'
hard+='|git[^;&|]*push[^;&|]*[[:space:]:/](main|master)([[:space:]]|$)'
hard+='|git[^;&|]*push[^;&|]*[[:space:]](-f|--force)([[:space:]]|$)'
hard+='|git[^;&|]*reset[[:space:]]+--hard|git[[:space:]]+clean'
hard+='|gh[^;&|]*--admin|gh[[:space:]]+release|gh[[:space:]]+workflow[[:space:]]+run|gh[[:space:]]+api'
hard+='|gh[[:space:]]+repo[[:space:]]+(delete|edit|rename)|gh[[:space:]]+secret'
hard+='|npm[[:space:]]+publish|wrangler[^;&|]*(deploy|publish|delete)|docker[[:space:]]+(push|rm|system)'
hard+='|curl[^;&|]*\|[[:space:]]*(ba)?sh|make[[:space:]]+release'
hard+='|\.claude/(settings|autonomy-level|hooks/)|settings(\.local)?\.json'
hard+='|\bpass[[:space:]]|send_message|sendmail|\bmail[[:space:]]'
if printf '%s' "$cmd" | grep -Eq "$hard"; then
  exit 0
fi

# Allowlist: no pipes, substitution or redirects, and every segment starts with a known verb.
case "$cmd" in *'|'*|*'`'*|*'$('*|*'>'*|*'<'*) exit 0 ;; esac
allow='^(cd [^[:space:]]+|git (add|commit|rebase|fetch|pull|switch|checkout|branch|worktree|status|log|diff|show|stash|push)|gh pr (create|view|edit|checks|list|comment|diff)|openspec|npm (test|ci|run (test|lint|build|typecheck))|pytest|uv run (pytest|ruff)|go (test|vet|build)|make (test|lint))([[:space:]]|$)'
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [ -z "$seg" ] && continue
  printf '%s' "$seg" | grep -Eq "$allow" || exit 0
done < <(printf '%s\n' "$cmd" | sed -E 's/(&&|;)/\n/g')

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"openspec-autonomy: OpenSpec repo, reversible command"}}\n'
exit 0
