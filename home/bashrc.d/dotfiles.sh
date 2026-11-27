#!/bin/bash
# Sourced from ~/.bashrc (Linux/WSL) or ~/.bash_profile + ~/.zshrc (macOS) by install.sh.

# Homebrew (macOS arm64/intel, Linuxbrew)
for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do  # public-safety: allow (Homebrew prefix)
  [ -x "$b" ] && { eval "$("$b" shellenv)"; break; }
done
[ -d /usr/local/go/bin ] && export PATH="$PATH:/usr/local/go/bin"
export PATH="$HOME/.local/bin:$PATH"
export GPG_TTY=$(tty)

# Prompt
if command -v oh-my-posh >/dev/null; then
  eval "$(oh-my-posh init "$([ -n "${ZSH_VERSION:-}" ] && echo zsh || echo bash)" --config "$HOME/.config/ohmyposh/theme.json")"
fi

# Optional: deploy/ssh target used by the /deploy, /hc, /rollback commands
# export HOMESERVER="user@homeserver.local"

# GitHub owners whose repos stop-gate trusts to define their own checks
# export CLAUDE_STOP_GATE_OWNERS="<your-github-user> <your-org>"

# Launch Claude Code from ~/Github unless already inside a git repo
claude() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -d "$HOME/Github" ]; then
    cd "$HOME/Github" || true
  fi
  command claude "$@"
}

# workmux: block local merges, go through a PR
workmux() {
  if [ "${1:-}" = "merge" ]; then
    echo "workmux merge is blocked: push the branch, gh pr create, merge via PR. Then 'workmux remove'." >&2
    return 1
  fi
  command workmux "$@"
}

# MCP secrets from `pass`, only when the GPG agent is already unlocked so a
# cold shell never blocks on pinentry. Edit the entry names to match yours.
if command -v pass >/dev/null && gpg-connect-agent 'keyinfo --list' /bye 2>/dev/null | grep -qE ' 1 P'; then
  export SUPABASE_ACCESS_TOKEN=$(pass dev/supabase-mcp-token 2>/dev/null)
  export MAGIC_API_KEY=$(pass dev/magic-mcp-key 2>/dev/null)
fi

# Private additions (from the overlay: home/bashrc.d/local.sh)
[ -f "$HOME/.config/dotfiles/local.sh" ] && . "$HOME/.config/dotfiles/local.sh"
