#!/bin/bash
# Print "src<TAB>dst<TAB>origin" for every file install.sh places. Shared by install.sh and bin/dnw-doctor.
# origin is "repo" or "overlay". A file under the overlay root ($DOTFILES_OVERLAY, default
# ~/.config/do-no-work/overlay) replaces the repo file at the same relative path; overlay-only
# files under known dirs are added. A skill dir touched by the overlay is listed per file.
# Usage: install-manifest.sh [REPO]   (dst paths are rooted at $HOME)
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overlay-lib.sh
. "$SELF_DIR/overlay-lib.sh"
REPO="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OV="${DOTFILES_OVERLAY:-$HOME/.config/do-no-work/overlay}"
c="$HOME/.claude"

emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

flat() { case "$1" in */*) return 1 ;; *) return 0 ;; esac; }

dst_for() {
  local rel="$1" rest
  case "$rel" in
    home/gitconfig) echo "$HOME/.gitconfig" ;;
    home/gitignore_global) echo "$HOME/.gitignore_global" ;;
    home/ohmyposh-theme.json) echo "$HOME/.config/ohmyposh/theme.json" ;;
    home/bashrc.d/*) rest="${rel#home/bashrc.d/}"; flat "$rest" && echo "$HOME/.config/dotfiles/$rest" ;;
    bin/*) rest="${rel#bin/}"; flat "$rest" && echo "$HOME/.local/bin/$rest" ;;
    claude/hooks/*.sh | claude/hooks/*.py | claude/commands/*.md | claude/agents/*.md)
      rest="${rel#claude/*/}"; flat "$rest" && echo "$c/${rel#claude/}" ;;
    *) return 1 ;;
  esac
}

# An overlay file on a non-overlayable path is never applied; warn and fall back to the repo file.
ignore_overlay() {
  [ -f "$OV/$1" ] || return 1
  overlayable "$1" && return 1
  echo "install-manifest: ignoring overlay/$1 (not overlayable); using the repo file" >&2
  return 0
}

emit_rel() {
  local rel="$1" dst
  dst="$(dst_for "$rel")" || return 0
  if ignore_overlay "$rel"; then
    [ -f "$REPO/$rel" ] && emit "$REPO/$rel" "$dst" repo
    return 0
  fi
  if [ -f "$OV/$rel" ]; then emit "$OV/$rel" "$dst" overlay; else emit "$REPO/$rel" "$dst" repo; fi
}

files_in() {
  [ -d "$1" ] || return 0
  (cd "$1" && find . -type f -not -path '*/__pycache__/*' | sed 's|^\./||' | LC_ALL=C sort)
}

emit_skill() {
  local name="$1" rel ov_files
  ov_files="$(files_in "$OV/claude/skills/$name" | while IFS= read -r rel; do
    ignore_overlay "claude/skills/$name/$rel" || printf '%s\n' "$rel"
  done)"
  if [ -z "$ov_files" ]; then emit "$REPO/claude/skills/$name" "$c/skills/$name" repo; return 0; fi
  { files_in "$REPO/claude/skills/$name"; printf '%s\n' "$ov_files"; } | LC_ALL=C sort -u | while IFS= read -r rel; do
    if [ -f "$OV/claude/skills/$name/$rel" ]; then
      emit "$OV/claude/skills/$name/$rel" "$c/skills/$name/$rel" overlay
    else
      emit "$REPO/claude/skills/$name/$rel" "$c/skills/$name/$rel" repo
    fi
  done
}

skill_names() {
  local d
  for d in "$REPO"/claude/skills/*/ "$OV"/claude/skills/*/; do
    [ -d "$d" ] && basename "$d"
  done | LC_ALL=C sort -u
}

main() {
  local rel name
  for rel in home/gitconfig home/gitignore_global home/ohmyposh-theme.json home/bashrc.d/dotfiles.sh; do emit_rel "$rel"; done
  for rel in $(cd "$REPO" && ls -d bin/* claude/hooks/*.sh claude/hooks/*.py claude/commands/*.md claude/agents/*.md 2>/dev/null); do emit_rel "$rel"; done
  if [ -d "$OV" ]; then
    while IFS= read -r rel; do
      [ -e "$REPO/$rel" ] || emit_rel "$rel"
    done < <(files_in "$OV")
  fi
  for name in $(skill_names); do emit_skill "$name"; done
}

main
