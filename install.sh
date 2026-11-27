#!/bin/bash
# Install dotfiles + Claude Code setup on macOS, Linux or WSL.
# Usage: ./install.sh [--copy] [--no-deps] [--seed-overlay | --seed-overlay-from DIR]
#   --copy                     copy files instead of symlinking (default: symlink)
#   --no-deps                  skip package installs
#   --seed-overlay             copy installed files that differ from the repo into the overlay, then exit
#   --seed-overlay-from DIR    same, reading from a backup dir such as ~/.dotfiles-backup/<timestamp>
#   --record-overlay           write .provenance rows for existing overlay files against the repo HEAD, copy nothing, then exit
# Seeding never copies hooks, tests, settings/CLAUDE.md templates, install.sh, scripts/ or .github/ (see scripts/overlay-lib.sh).
# Overlay root: $DOTFILES_OVERLAY, default ~/.config/do-no-work/overlay (mirrors repo paths; wins over the repo).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overlay-lib.sh
. "$REPO/scripts/overlay-lib.sh"
MODE="link"
DEPS=1
SEED=""
RECORD=0
SEEDED_LIST=()
while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE=copy ;;
    --no-deps) DEPS=0 ;;
    --seed-overlay) SEED="$HOME" ;;
    --record-overlay) RECORD=1 ;;
    --seed-overlay-from)
      [ $# -ge 2 ] || { echo "--seed-overlay-from needs a directory" >&2; exit 2; }
      [ -d "$2" ] || { echo "not a directory: $2" >&2; exit 2; }
      SEED="$(cd "$2" && pwd)"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
OVERLAY="${DOTFILES_OVERLAY:-$HOME/.config/do-no-work/overlay}"
export DOTFILES_OVERLAY="$OVERLAY"

log() { printf '==> %s\n' "$*"; }

BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"

# Back up a differing target outside the install dirs, then link or copy src -> dst.
place() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] && [ "$MODE" = link ]; then return; fi
  if [ ! -L "$dst" ] && [ -e "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1 && [ "$MODE" = copy ]; then return; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mkdir -p "$BACKUP$(dirname "${dst#"$HOME"}")"
    mv "$dst" "$BACKUP${dst#"$HOME"}"
    log "backed up $dst -> $BACKUP"
  fi
  if [ "$MODE" = link ]; then
    ln -sfn "$src" "$dst"
  else
    cp -R "$src" "$dst"
  fi
}

install_deps() {
  local pkgs=(git gh jq node uv gitleaks pre-commit oh-my-posh)
  if [ "$(uname)" = Darwin ]; then
    command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    brew install "${pkgs[@]}" pass ffmpeg
    return
  fi
  if command -v brew >/dev/null; then
    brew install "${pkgs[@]}" pass ffmpeg
    return
  fi
  log "no Homebrew found; install these with your package manager: ${pkgs[*]} pass ffmpeg"
}

install_cli_tools() {
  if command -v npm >/dev/null; then
    npm install -g chrome-devtools-mcp @fission-ai/openspec @charmland/crush || log "npm globals failed (continuing)"
  fi
  if command -v uv >/dev/null; then
    for t in mcp-proxy aider-chat; do uv tool install "$t" || log "uv tool $t failed (continuing)"; done
  fi
}

# A skill dir linked whole must not stay a symlink when its files are placed one by one.
detach_linked_parent() {
  local skills="$HOME/.claude/skills" rest name d
  case "$1" in "$skills"/*/*) ;; *) return 0 ;; esac
  rest="${1#"$skills"/}"
  name="${rest%%/*}"
  d="$skills/$name"
  [ -L "$d" ] || return 0
  mkdir -p "$BACKUP/.claude/skills"
  mv "$d" "$BACKUP/.claude/skills/$name"
  log "backed up $d -> $BACKUP"
}

place_manifest() {
  local src dst origin n=0
  while IFS=$'\t' read -r src dst origin; do
    detach_linked_parent "$dst"
    place "$src" "$dst"
    [ "$origin" = overlay ] && n=$((n + 1))
  done < <("$REPO/scripts/install-manifest.sh" "$REPO")
  [ "$n" -eq 0 ] || log "$n files from overlay $OVERLAY"
  return 0
}

seed_one() {
  local src="$1" inst="$2" rel="${1#"$REPO"/}"
  [ -f "$inst" ] || return 0
  cmp -s "$src" "$inst" && return 0
  if ! overlayable "$rel"; then echo "skip (not overlayable): $rel"; return 0; fi
  if [ -e "$OVERLAY/$rel" ]; then log "kept existing overlay/$rel"; return 0; fi
  mkdir -p "$(dirname "$OVERLAY/$rel")"
  cp "$inst" "$OVERLAY/$rel"
  prov_record "$OVERLAY" "$REPO" "$rel"
  SEEDED_LIST+=("$rel")
}

seed_overlay() {
  local root="$1" src dst origin f
  while IFS=$'\t' read -r src dst origin; do
    if [ -d "$src" ]; then
      while IFS= read -r f; do seed_one "$src/$f" "$root${dst#"$HOME"}/$f"; done \
        < <(cd "$src" && find . -type f -not -path '*/__pycache__/*' | sed 's|^\./||')
    else
      seed_one "$src" "$root${dst#"$HOME"}"
    fi
  done < <(DOTFILES_OVERLAY=/nonexistent/dnw-no-overlay "$REPO/scripts/install-manifest.sh" "$REPO")
}

seed_report() {
  local rel
  [ "${#SEEDED_LIST[@]}" -gt 0 ] || return 0
  for rel in "${SEEDED_LIST[@]}"; do printf 'seeded: %s\n' "$rel"; done
  echo "Review: these now override the repo; delete any that aren't personal from $OVERLAY"
}

record_overlay() {
  local rel
  [ -d "$OVERLAY" ] || { log "no overlay at $OVERLAY"; return 0; }
  while IFS= read -r rel; do
    [ "$rel" = .provenance ] && continue
    overlayable "$rel" || continue
    [ -n "$(prov_lookup "$OVERLAY" "$rel")" ] && continue
    prov_record "$OVERLAY" "$REPO" "$rel"
    [ -n "$(prov_lookup "$OVERLAY" "$rel")" ] && echo "recorded: $rel"
  done < <(cd "$OVERLAY" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
  return 0
}

install_claude() {
  local c="$HOME/.claude"
  [ -f "$c/autonomy-level" ] || echo full > "$c/autonomy-level"
  if [ ! -f "$HOME/CLAUDE.md" ]; then
    cp "$REPO/claude/CLAUDE.md.example" "$HOME/CLAUDE.md"
    log "wrote ~/CLAUDE.md from template; fill in <NAME>/<ROLE>"
  fi
  log "hooks need wiring: merge claude/settings.example.json into ~/.claude/settings.json (not done automatically); run bin/dnw-doctor to check"
}

install_identity() {
  [ -f "$HOME/.gitconfig.local" ] && return 0
  local n="${GIT_NAME:-}" e="${GIT_EMAIL:-}"
  if [ -z "$n" ] && [ -t 0 ]; then read -rp "git user.name: " n; read -rp "git user.email: " e; fi
  if [ -z "$n" ]; then read -r n || true; read -r e || true; fi
  if [ -z "$n" ]; then
    log "no git identity: set GIT_NAME/GIT_EMAIL or create ~/.gitconfig.local yourself"
    return 0
  fi
  printf '[user]\n\tname = %s\n\temail = %s\n' "$n" "$e" > "$HOME/.gitconfig.local"
}

install_rc() {
  local rcs=("$HOME/.bashrc")
  [ "$(uname)" = Darwin ] && rcs=("$HOME/.bash_profile" "$HOME/.zshrc")
  local line='[ -f "$HOME/.config/dotfiles/dotfiles.sh" ] && . "$HOME/.config/dotfiles/dotfiles.sh"'
  local rc
  for rc in "${rcs[@]}"; do
    grep -qF "$line" "$rc" 2>/dev/null || printf '\n%s\n' "$line" >> "$rc"
  done
}

install_upstream_skills() {
  [ "${DOTFILES_SKIP_UPSTREAM:-0}" = 1 ] && { log "skipping upstream skills"; return; }
  command -v npx >/dev/null || { log "npx missing; skipping upstream skills"; return; }
  grep -vE '^\s*(#|$)' "$REPO/skills-upstream.txt" | while read -r repo; do
    log "skill: $repo"
    npx -y skills@1.9.0 add "$repo" -g -a claude-code -y </dev/null || log "failed: $repo (continuing)"
  done
}

if [ "$RECORD" = 1 ]; then record_overlay; exit 0; fi
if [ -n "$SEED" ]; then seed_overlay "$SEED"; seed_report; exit 0; fi
if [ "$DEPS" = 1 ]; then install_deps; install_cli_tools; fi
chmod +x "$REPO"/bin/* "$REPO"/claude/hooks/*.sh
place_manifest
install_identity
install_rc
install_claude
install_upstream_skills
log "done. Open a new shell."
