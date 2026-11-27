#!/bin/bash
# Personal overlay: install, seed and doctor against a throwaway HOME and overlay dir.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
home=""
ov=""
out=""
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
same() { cmp -s "$1" "$2"; }
content_is() { [ "$(cat "$1")" = "$2" ]; }
doctor() { out="$(HOME="$home" DOTFILES_OVERLAY="$ov" "$REPO/bin/dnw-doctor" </dev/null || true)"; }
has() { grep -Eq -- "$1" <<<"$out"; }

setup() {
  home="$(mktemp -d)"
  ov="$(mktemp -d)"
  mkdir -p "$ov/claude/commands" "$ov/claude/skills/call" "$ov/bin" "$ov/home/bashrc.d"
  echo 'personal hc' > "$ov/claude/commands/hc.md"
  echo 'personal only' > "$ov/claude/commands/mine.md"
  echo 'personal call' > "$ov/claude/skills/call/SKILL.md"
  printf '#!/bin/bash\necho hi\n' > "$ov/bin/mytool"
  echo 'export X=1' > "$ov/home/bashrc.d/local.sh"
}

install() {
  HOME="$home" DOTFILES_OVERLAY="$ov" GIT_NAME=T GIT_EMAIL=t@example.com DOTFILES_SKIP_UPSTREAM=1 \
    "$REPO/install.sh" --no-deps "$@" >/dev/null </dev/null
}

sibling_present() {
  local f
  for f in "$REPO"/claude/skills/call/*; do
    [ "$(basename "$f")" = SKILL.md ] && continue
    [ -e "$home/.claude/skills/call/$(basename "$f")" ] || return 1
  done
  return 0
}

run_mode() {
  local mode="$1"
  echo "-- mode: ${mode:-link}"
  setup
  install $mode
  check "overlay command replaces repo" "same '$ov/claude/commands/hc.md' '$home/.claude/commands/hc.md'"
  check "overlay-only command installed" "same '$ov/claude/commands/mine.md' '$home/.claude/commands/mine.md'"
  check "overlay-only bin installed" "same '$ov/bin/mytool' '$home/.local/bin/mytool'"
  check "overlay bashrc.d installed" "same '$ov/home/bashrc.d/local.sh' '$home/.config/dotfiles/local.sh'"
  check "skill has overlay SKILL.md" "same '$ov/claude/skills/call/SKILL.md' '$home/.claude/skills/call/SKILL.md'"
  check "skill keeps repo siblings" "sibling_present"
  check "skill dir is a real dir" "[ -d '$home/.claude/skills/call' ] && [ ! -L '$home/.claude/skills/call' ]"
  check "other skill still whole-dir" "[ -e '$home/.claude/skills/tighten/SKILL.md' ]"
  check "repo skill and commands untouched" "[ -z \"\$(git -C '$REPO' status --porcelain -- claude/skills claude/commands)\" ]"
  if [ "$mode" = --copy ]; then
    check "copy mode: overlay file is a copy" "[ ! -L '$home/.claude/commands/hc.md' ]"
  else
    check "link mode: linked to overlay" "[ \"\$(readlink '$home/.claude/commands/hc.md')\" = '$ov/claude/commands/hc.md' ]"
  fi
  install $mode
  check "rerun makes no backups" "[ ! -d '$home/.dotfiles-backup' ]"
}

run_manifest() {
  echo "-- manifest"
  setup
  out="$(HOME="$home" DOTFILES_OVERLAY="$ov" "$REPO/scripts/install-manifest.sh" "$REPO")"
  check "overlay row marked overlay" "has '^$ov/claude/commands/hc.md.$home/.claude/commands/hc.md.overlay\$'"
  check "repo row marked repo" "has '/claude/commands/log.md.*repo\$'"
  check "three columns everywhere" "[ \"\$(awk -F'\t' 'NF != 3' <<<\"\$out\" | wc -l)\" -eq 0 ]"
  out="$(HOME="$home" DOTFILES_OVERLAY="$home/none" "$REPO/scripts/install-manifest.sh" "$REPO")"
  check "no overlay: all repo" "! has 'overlay\$'"
}

run_whole_to_split() {
  local empty
  echo "-- whole-dir link becomes per-file"
  setup
  empty="$(mktemp -d)"
  HOME="$home" DOTFILES_OVERLAY="$empty" GIT_NAME=T GIT_EMAIL=t@example.com DOTFILES_SKIP_UPSTREAM=1 \
    "$REPO/install.sh" --no-deps >/dev/null </dev/null
  check "starts as dir link" "[ -L '$home/.claude/skills/call' ]"
  install
  check "now a real dir" "[ -d '$home/.claude/skills/call' ] && [ ! -L '$home/.claude/skills/call' ]"
  check "old link backed up" "[ -n \"\$(ls '$home'/.dotfiles-backup/*/.claude/skills 2>/dev/null)\" ]"
  check "repo SKILL.md not overwritten" "! grep -q 'personal call' '$REPO/claude/skills/call/SKILL.md'"
}

run_seed_from_backup() {
  local bk ovs
  echo "-- seed from backup"
  setup
  bk="$(mktemp -d)"
  ovs="$(mktemp -d)"
  mkdir -p "$bk/.claude/commands" "$bk/.claude/skills/call" "$ovs/claude/commands"
  echo 'owner hc' > "$bk/.claude/commands/hc.md"
  cp "$REPO/claude/commands/log.md" "$bk/.claude/commands/log.md"
  echo 'owner call' > "$bk/.claude/skills/call/SKILL.md"
  echo 'unmapped' > "$bk/.claude/commands/not-in-repo.md"
  echo 'keep me' > "$ovs/claude/commands/hc.md"
  HOME="$home" DOTFILES_OVERLAY="$ovs" "$REPO/install.sh" --seed-overlay-from "$bk" >/dev/null </dev/null
  check "never overwrites existing overlay" "content_is '$ovs/claude/commands/hc.md' 'keep me'"
  check "copies differing skill file" "content_is '$ovs/claude/skills/call/SKILL.md' 'owner call'"
  check "skips identical file" "[ ! -e '$ovs/claude/commands/log.md' ]"
  check "skips files with no repo path" "[ ! -e '$ovs/claude/commands/not-in-repo.md' ]"
  check "seeding installs nothing" "[ ! -e '$home/.claude' ]"
  check "repo untouched" "[ -z \"\$(git -C '$REPO' status --porcelain -- claude)\" ]"
}

run_seed_from_home() {
  local ovs
  echo "-- seed from HOME"
  setup
  ovs="$(mktemp -d)"
  ov="$(mktemp -d)"
  install --copy
  echo 'my log' > "$home/.claude/commands/log.md"
  HOME="$home" DOTFILES_OVERLAY="$ovs" "$REPO/install.sh" --seed-overlay >/dev/null </dev/null
  check "seeds a locally changed file" "content_is '$ovs/claude/commands/log.md' 'my log'"
  check "seeds only that file" "[ \"\$(find '$ovs' -type f | wc -l)\" -eq 1 ]"
}

run_doctor() {
  echo "-- doctor"
  setup
  install
  echo 'stray' > "$ov/README-private.txt"
  doctor
  check "overlay count and list" "has '^ok +overlay +5 files \\(.*claude/commands/hc.md'"
  check "no stale warning" "! has '^(warn|fail) +installed'"
  check "unknown overlay file warned" "has '^warn +overlay +overlay/README-private.txt'"
  install --copy
  doctor
  check "copy mode: no stale warning" "! has '^(warn|fail) +installed'"
  echo 'drift' >> "$home/.claude/commands/hc.md"
  doctor
  check "drifted copy compared to overlay" "has 'commands/hc.md differs from the overlay'"
}

run_mode ""
run_mode --copy
run_manifest
run_whole_to_split
run_seed_from_backup
run_seed_from_home
run_doctor
exit $fail
