#!/bin/bash
# Runs install.sh into a throwaway HOME and checks the result.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

run_mode() {
  local mode="$1" home
  home="$(mktemp -d)"
  printf 'Test User\ntest@example.com\n' |
    HOME="$home" DOTFILES_SKIP_UPSTREAM=1 "$REPO/install.sh" --no-deps $mode >/dev/null
  echo "-- mode: ${mode:-link}"
  check "hook installed"        "[ -e '$home/.claude/hooks/autonomy-gate.sh' ]"
  check "command installed"     "[ -e '$home/.claude/commands/log.md' ]"
  check "skill installed"       "[ -e '$home/.claude/skills/tighten/SKILL.md' ]"
  check "bin script installed"  "[ -x '$home/.local/bin/safe-worktree-remove' ]"
  check "CLAUDE.md from template" "grep -q '<NAME>' '$home/CLAUDE.md'"
  check "gitconfig.local written" "grep -q 'test@example.com' '$home/.gitconfig.local'"
  check "rc sources dotfiles"   "grep -qs 'dotfiles.sh' '$home/.bashrc' '$home/.bash_profile'"
  if [ "$mode" = --copy ]; then
    check "copy mode: no symlinks" "[ ! -L '$home/.gitconfig' ]"
  else
    check "link mode: symlinked"   "[ -L '$home/.gitconfig' ]"
  fi
  # Second run must be idempotent: rc line not duplicated
  HOME="$home" DOTFILES_SKIP_UPSTREAM=1 "$REPO/install.sh" --no-deps $mode >/dev/null </dev/null
  check "idempotent rc line" "[ \$(cat '$home/.bashrc' '$home/.bash_profile' 2>/dev/null | grep -c dotfiles.sh) -eq 1 ]"
}

run_mode ""
run_mode --copy
exit $fail
