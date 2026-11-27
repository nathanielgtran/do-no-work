#!/bin/bash
# Print "src<TAB>dst" for every file install.sh places. Shared by install.sh and bin/dnw-doctor.
# Usage: install-manifest.sh [REPO]   (dst paths are rooted at $HOME)
set -euo pipefail

REPO="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
c="$HOME/.claude"

emit() { printf '%s\t%s\n' "$1" "$2"; }

emit "$REPO/home/gitconfig" "$HOME/.gitconfig"
emit "$REPO/home/gitignore_global" "$HOME/.gitignore_global"
emit "$REPO/home/ohmyposh-theme.json" "$HOME/.config/ohmyposh/theme.json"
emit "$REPO/home/bashrc.d/dotfiles.sh" "$HOME/.config/dotfiles/dotfiles.sh"
for f in "$REPO"/bin/*; do emit "$f" "$HOME/.local/bin/$(basename "$f")"; done
for f in "$REPO"/claude/hooks/*.sh; do emit "$f" "$c/hooks/$(basename "$f")"; done
for f in "$REPO"/claude/commands/*.md; do emit "$f" "$c/commands/$(basename "$f")"; done
for f in "$REPO"/claude/agents/*.md; do emit "$f" "$c/agents/$(basename "$f")"; done
for d in "$REPO"/claude/skills/*/; do emit "${d%/}" "$c/skills/$(basename "$d")"; done
