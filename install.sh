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

install_claude() {
  local c="$HOME/.claude"
  mkdir -p "$c/hooks" "$c/commands" "$c/skills" "$c/agents"
  for f in "$REPO"/claude/hooks/*.sh; do place "$f" "$c/hooks/$(basename "$f")"; done
  for f in "$REPO"/claude/commands/*.md; do place "$f" "$c/commands/$(basename "$f")"; done
  for f in "$REPO"/claude/agents/*.md; do place "$f" "$c/agents/$(basename "$f")"; done
  for d in "$REPO"/claude/skills/*/; do place "${d%/}" "$c/skills/$(basename "$d")"; done
  [ -f "$c/autonomy-level" ] || echo full > "$c/autonomy-level"
  if [ ! -f "$HOME/CLAUDE.md" ]; then
    cp "$REPO/claude/CLAUDE.md.example" "$HOME/CLAUDE.md"
    log "wrote ~/CLAUDE.md from template; fill in <NAME>/<ROLE>"
  fi
  log "hooks need wiring: merge claude/settings.example.json into ~/.claude/settings.json (not done automatically)"
}

install_bin() {
  for f in "$REPO"/bin/*; do place "$f" "$HOME/.local/bin/$(basename "$f")"; done
  chmod +x "$REPO"/bin/* "$REPO"/claude/hooks/*.sh
}

install_home() {
  place "$REPO/home/gitconfig" "$HOME/.gitconfig"
  place "$REPO/home/gitignore_global" "$HOME/.gitignore_global"
  place "$REPO/home/ohmyposh-theme.json" "$HOME/.config/ohmyposh/theme.json"
  place "$REPO/home/bashrc.d/dotfiles.sh" "$HOME/.config/dotfiles/dotfiles.sh"
  if [ ! -f "$HOME/.gitconfig.local" ]; then
    local n="${GIT_NAME:-}" e="${GIT_EMAIL:-}"
    if [ -z "$n" ] && [ -t 0 ]; then read -rp "git user.name: " n; read -rp "git user.email: " e; fi
    if [ -z "$n" ]; then read -r n || true; read -r e || true; fi
    [ -n "$n" ] || { log "set GIT_NAME/GIT_EMAIL or create ~/.gitconfig.local yourself"; return 0; }
    printf '[user]\n\tname = %s\n\temail = %s\n' "$n" "$e" > "$HOME/.gitconfig.local"
  fi
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
install_home
install_bin
install_claude
install_upstream_skills
log "done. Open a new shell."
