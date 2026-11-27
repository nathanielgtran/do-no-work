#!/bin/bash
# Install dotfiles + Claude Code setup on macOS, Linux or WSL.
# Usage: ./install.sh [--copy] [--no-deps]
#   --copy     copy files instead of symlinking (default: symlink)
#   --no-deps  skip package installs
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=link
DEPS=1
for a in "$@"; do
  case "$a" in
    --copy) MODE=copy ;;
    --no-deps) DEPS=0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

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

place_manifest() {
  local src dst
  while IFS=$'\t' read -r src dst; do place "$src" "$dst"; done < <("$REPO/scripts/install-manifest.sh" "$REPO")
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

if [ "$DEPS" = 1 ]; then install_deps; install_cli_tools; fi
chmod +x "$REPO"/bin/* "$REPO"/claude/hooks/*.sh
place_manifest
install_identity
install_rc
install_claude
install_upstream_skills
log "done. Open a new shell."
