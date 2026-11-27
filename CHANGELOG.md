# Changelog

## Unreleased
- feat-8: reusable `claude-review.yml` workflow (Claude read-only review, applies REVIEWED only on PASS for the reviewed commit), `scripts/claude-review-verdict.sh` with tests, caller example, and self-review via `review.yml`
- feat-9: stop-gate Stop hook blocks the stop while the repo's fast check fails (env, .claude/stop-gate or auto-detect; timeout, 40-line clip, loop-safe)
- feat-10: protect-lint-config PreToolUse hook asks before edits to lint, format, type-check config and baselines
- feat-11: read-only reviewer subagent (claude/agents/reviewer.md), installed to ~/.claude/agents/
- feat-12: sandbox, autoMode.environment and .worktreeinclude examples; CLAUDE.md template gains fan-out and /clear lines
- feat-1: initial import of Claude Code hooks, commands, skills, CLI scripts and shell/git config, with install.sh (macOS/Linux/WSL) and install.ps1 (Windows)
- fix-1: review fixes: openspec-autonomy allowlist + deny rules in example, gate-self-merge one-PR/no-cd, global pinned skill installs, idempotent copy mode with backups in ~/.dotfiles-backup, zsh on macOS, claude() without ~/Github, go-check on macOS, non-interactive install
- feat-3: autobuild skill; README rewritten with workflow, guardrail, autobuild and install diagrams
- feat-2: CI on GitHub-hosted runners only (installer + skill tests, gitleaks)
- feat-4: repo-bootstrap applies fleet GitHub defaults (Actions lockdown, squash-only, secret scanning, REVIEWED label, protect-main ruleset) idempotently, with --public self-hosted runner warning and --dry-run
- feat-5: ci-wait blocks until a PR's checks finish, retries through the no-checks-yet window, exits 0 only if all passed
- fix-2: autonomy-gate tamper guard checks write targets (redirect target, mutating-command operands, sed -i files, cd into the dir), not any mention of the path
