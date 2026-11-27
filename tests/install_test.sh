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
  check "agent installed"       "[ -e '$home/.claude/agents/reviewer.md' ]"
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
  check "rerun makes no backups" "[ ! -d '$home/.dotfiles-backup' ]"
  if [ "$(uname)" = Darwin ]; then check "zshrc sources dotfiles" "grep -q dotfiles.sh '$home/.zshrc'"; fi
  local rc dupes=0
  for rc in "$home/.bashrc" "$home/.bash_profile" "$home/.zshrc"; do
    [ -f "$rc" ] || continue
    [ "$(grep -c dotfiles.sh "$rc")" -eq 1 ] || dupes=1
  done
  check "idempotent rc line" "[ $dupes -eq 0 ]"
}

run_noident() {
  local home out
  home="$(mktemp -d)"
  out="$(HOME="$home" DOTFILES_SKIP_UPSTREAM=1 "$REPO/install.sh" --no-deps </dev/null 2>&1)"
  echo "-- no identity, no TTY"
  check "rc wired without identity" "grep -qs 'dotfiles.sh' '$home/.bashrc' '$home/.bash_profile'"
  check "no gitconfig.local created" "[ ! -e '$home/.gitconfig.local' ]"
  check "identity hint printed" "grep -q 'no git identity' <<<'$out'"
  check "files still installed" "[ -e '$home/.claude/hooks/autonomy-gate.sh' ]"
}

run_mode ""
run_mode --copy
run_noident
exit $fail
