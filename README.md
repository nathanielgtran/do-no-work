# do no work

My Claude Code setup (hooks, slash commands, skills, CLAUDE.md template), the CLI scripts I use daily, and shell/git config. One installer for macOS/Linux/WSL, one for Windows.

## Install

macOS / Linux / WSL:

```bash
git clone https://github.com/<you>/do-no-work ~/Github/do-no-work
cd ~/Github/do-no-work && ./install.sh          # symlinks; --copy to copy, --no-deps to skip packages
```

Windows (PowerShell):

```powershell
git clone https://github.com/<you>/do-no-work $HOME\Github\do-no-work
cd $HOME\Github\do-no-work; powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Windows installs packages with winget, then runs `install.sh --copy` through Git Bash. Claude Code on Windows runs hooks through Git Bash, so the bash hooks work unchanged.

Existing files are moved to `<file>.pre-dotfiles.<timestamp>` before being replaced. Nothing touches `~/.claude/settings.json`: merge the `hooks` block from `claude/settings.example.json` into it yourself.

## What's in it

| Path | What |
|---|---|
| `claude/hooks/` | `autonomy-gate` / `autonomy-toggle` ("go less" / "go full" kill switch for push + merge), `gate-self-merge` (merge only with a REVIEWED label + green CI), `openspec-autonomy`, `go-check` (per-package go test/vet/lint after edits), `session-context` (loads daily log/todo at session start), `compact-reinject`, `claude-notify` (Discord DM on permission prompts) |
| `claude/commands/` | `/log`, `/prune`, `/test`, `/review-pr`, `/deploy`, `/hc`, `/rollback`. The deploy/healthcheck ones expect `$HOMESERVER` (`user@host`) |
| `claude/skills/` | `tighten` (post-PR simplify + fix), `backlog` (cross-repo TODO + issue rollup), `call` (transcribe a call recording into notes), `wanderlog` (Wanderlog trip API) |
| `claude/CLAUDE.md.example` | My global instructions as a template. Copied to `~/CLAUDE.md` if you don't have one |
| `bin/` | `pstack-budget-statusline` (statusline showing 5h/7d plan usage; picks a model budget tier), `safe-worktree-remove` (refuses dirty/unmerged/in-use worktrees), `transcribe` + `callrec` (local call recording + transcription), `pasteimg`, `chrome-devtools-mcp-gated`, `engraph-*` (helpers for the engraph knowledge-graph MCP) |
| `home/` | `gitconfig` (identity goes in `~/.gitconfig.local`), `gitignore_global`, oh-my-posh theme, `bashrc.d/dotfiles.sh` (brew, PATH, prompt, `pass`-backed secrets) |
| `skills-upstream.txt` | Third-party skills installed from their own repos via `npx skills add`, not copied here |

## Also installed

`--no-deps` skips these. npm globals: `chrome-devtools-mcp`, `@fission-ai/openspec`, `@charmland/crush`. uv tools: `mcp-proxy`, `aider-chat`. Not automated: `bombadil` (UI property testing, binary in `~/.local/bin`), `herdr` (installs its own Claude hook), and `transcribe` expects a local Parakeet install at `~/parakeet`.

## Secrets

None are stored here. Scripts read tokens from environment variables or `pass` (e.g. `pass dev/magic-mcp-key`); rename entries in `home/bashrc.d/dotfiles.sh` to match yours. A gitleaks pre-commit hook runs on every commit.

## Test

```bash
./tests/install_test.sh   # installs into a throwaway HOME in link and copy mode
```
