# do no work

A Claude Code setup built so the agent does the work and you make the decisions. It ships with guardrails that make it safe to let the agent run.

Built by Nathaniel Tran. See more of my work at **[ngtran.dev](https://ngtran.dev)**. <!-- public-safety: allow (author byline) -->

It includes hooks, slash commands, skills, a `CLAUDE.md` template, the CLI scripts I use daily, and shell/git config. There is one installer for macOS/Linux/WSL and one for Windows.

**[Full catalogue of hooks, commands, skills and scripts](docs/REFERENCE.md)**. Each entry says what it does, when it runs, how to disable it, and links its source. Research notes behind the setup: [docs/workflow-research.md](docs/workflow-research.md).

- [The workflow](#the-workflow)
- [Guardrails](#guardrails)
- [autobuild: hands-off feature loop](#autobuild-hands-off-feature-loop)
- [Install](#install)
- [What's in it](#whats-in-it)

## The workflow

Every change goes the same way: plan, isolate, prove, review, merge. Each step leaves evidence the next one checks. Hooks enforce the steps; nobody has to remember them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/workflow-dark.svg">
  <img src="docs/diagrams/workflow.svg" alt="Workflow: session start, plan, worktree, build, push and PR, CI and Claude review, gate-self-merge, squash merge, release, log, with a fix loop on a blocked review">
</picture>

The rules behind it live in [`claude/CLAUDE.md.example`](claude/CLAUDE.md.example). The short version:

- **No hacks.** No workaround, retry or fallback that hides a bug. Fix the first place it goes wrong.
- **Mistakes become rules.** When a correction happens a second time, encode a check (lint, test, hook) that fails on the real past instance. Prose is the last resort.
- **Comments default to none.** Rename, extract or type the code instead of explaining it.
- **Proof, not claims.** PR bodies carry pasted test output or screenshots, never "tested locally".

### PR format

PR bodies follow the fleet template, [`PULL_REQUEST_TEMPLATE.md`](https://github.com/nathanielgtran/.github/blob/main/PULL_REQUEST_TEMPLATE.md): `## What`, `## Why`, `## Proof`, `## Risk + rollback`, `## Checklist`. Proof is pasted test or run output, never "tested locally". The [`CLAUDE.md` template](claude/CLAUDE.md.example) enforces it for the agent, and the `pr-template` check in the fleet repos enforces it in CI.

### Changelog

PRs never edit `CHANGELOG.md`, so parallel PRs can't conflict there. Each PR adds one fragment, `changelog.d/<type-N>.md` (one line, no ID). `scripts/changelog.sh next <type>` prints the next free ID, `check` validates fragments (CI runs it), and `compile [--version vX.Y.Z]` folds them into `CHANGELOG.md` at release.

## Guardrails

Every Bash call the agent makes passes through the hooks before it runs. The strictest decision wins: deny, then ask, then allow.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/guardrails-dark.svg">
  <img src="docs/diagrams/guardrails.svg" alt="Guardrails: a Bash command passes autonomy-gate, gate-self-merge and openspec-autonomy; deny rules always win; outcomes are deny, ask, allow or the normal prompt">
</picture>

The tamper guard inspects write targets (redirects, cp/mv/tee/sed -i operands and similar), so reading or merely mentioning those paths passes; a literal `$HOME/.claude/...` target is still denied.

Say **"go less"** in a prompt to block all push and merge, and **"go full"** to restore them. `autonomy-toggle` flips the dial and `autonomy-gate` enforces it.

> **Warning:** `openspec-autonomy` auto-approves allowlisted commands in any repo containing `openspec/config.yaml`, and a repo you clone can contain that file. Only wire it if you keep the `permissions.deny` block from [`claude/settings.example.json`](claude/settings.example.json). Leave it out if you run Claude in repos you don't trust.

Two more hooks sit outside that Bash flow:

- **stop-gate** (Stop): when files changed, runs the repo's fast check (`$CLAUDE_STOP_GATE_CMD`, then `.claude/stop-gate`, then go/npm/pytest/openspec auto-detect) and blocks the stop with the failure output. It lets the stop through when the same failure repeats under `stop_hook_active`. Repo-defined checks only run in repos owned by someone in `CLAUDE_STOP_GATE_OWNERS` (space-separated GitHub users/orgs), so a cloned repo can't use it to run code.
- **protect-lint-config** (PreToolUse on Edit/Write/MultiEdit): asks before changes to lint, format and type-check config and baseline files, because agents disable rules to pass. Fix the code, or confirm.

Sandbox, `autoMode.environment` and worktree examples are in [`claude/settings.example.json`](claude/settings.example.json) and [`.worktreeinclude.example`](.worktreeinclude.example). Copy the latter to `.worktreeinclude` to have gitignored files like `.env` copied into new worktrees; for large directories such as `node_modules` set `worktree.symlinkDirectories` in settings instead.

## autobuild: hands-off feature loop

Use [`claude/skills/autobuild`](claude/skills/autobuild/SKILL.md) when you'd rather the agent decide what to build. It scouts the repo, picks up to three features, and builds them in parallel worktrees. You review and merge one PR at a time.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/autobuild-dark.svg">
  <img src="docs/diagrams/autobuild.svg" alt="autobuild: preconditions, scout, pick up to three features, set up worktrees, build in parallel, review, wait for CI, label and merge, verify live, log">
</picture>

## Install

macOS / Linux / WSL:

```bash
git clone https://github.com/nathanielgtran/do-no-work ~/Github/do-no-work  # public-safety: allow (public repo URL)
cd ~/Github/do-no-work && ./install.sh     # symlinks; --copy to copy, --no-deps to skip packages
```

Run `dnw-doctor` after pulling to see drift and missing settings.

Windows (PowerShell):

```powershell
git clone https://github.com/nathanielgtran/do-no-work $HOME\Github\do-no-work  # public-safety: allow (public repo URL)
cd $HOME\Github\do-no-work; powershell -ExecutionPolicy Bypass -File .\install.ps1
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/install-dark.svg">
  <img src="docs/diagrams/install.svg" alt="Install map: install.ps1 and install.sh place home config, bin scripts, Claude config, upstream skills and dependencies; settings merge and the diagram-design plugin are manual">
</picture>

- **Windows** runs `install.sh --copy` through Git Bash. Claude Code on Windows runs hooks through Git Bash as well, so the bash hooks work unchanged.
- **macOS** gets the shell config in both `~/.zshrc` and `~/.bash_profile`.
- **Reruns** leave identical files alone. Anything that differs is moved to `~/.dotfiles-backup/<timestamp>/` before it is replaced.
- **Settings** are never touched: merge `hooks`, `permissions` and `statusLine` from [`claude/settings.example.json`](claude/settings.example.json) into `~/.claude/settings.json` yourself.
- **Non-interactive installs** need `GIT_NAME` and `GIT_EMAIL` set.

### New repo

Apply the fleet defaults (Actions lockdown, squash-only merges, secret scanning, `REVIEWED` label, `protect-main` ruleset) to an existing GitHub repo. It is idempotent; `--dry-run` prints the calls without making them.

```bash
BOOTSTRAP_CHECKS="test (ubuntu-latest),gitleaks" repo-bootstrap owner/repo --public
```

`--public` also warns if a workflow uses a self-hosted runner. Without `BOOTSTRAP_CHECKS` the required-checks rule is skipped. `BOOTSTRAP_ACTIONS` overrides the allowed third-party actions.

### Roll out the review

`repo-bootstrap owner/repo --review` sets up only the CI Claude review: the `REVIEWED` label, the Actions allowlist entries for the pinned `claude-code-action` and its nested `setup-bun` (merged into the existing list; skipped when all actions are allowed), a caller workflow opened as a PR if `.github/workflows/review.yml` is missing, and the `CLAUDE_CODE_OAUTH_TOKEN` secret. `review-rollout` runs it over several repos and prints a summary table.

```bash
CLAUDE_CODE_OAUTH_TOKEN=... review-rollout owner/repo1 owner/repo2
```

The token is read from the environment and piped to `gh secret set` on stdin; without it you get a `fix:` line with the command (a long-lived token comes from `claude setup-token`). Private repos run the caller on `BOOTSTRAP_REVIEW_RUNS_ON` (default `ubuntu-latest`); public repos never get a self-hosted runner.

## What's in it

| Path | What |
|---|---|
| `claude/hooks/` | `autonomy-gate` + `autonomy-toggle` (push/merge kill switch), `gate-self-merge` (merge only with REVIEWED + green CI), `openspec-autonomy`, `go-check` (go test/vet/lint on the edited package), `stop-gate` (done gate on Stop), `protect-lint-config` (ask before lint/type config edits), `session-context` (loads daily log/todo at start), `compact-reinject`, `claude-notify` (Discord DM on permission prompts and idle) |
| `claude/agents/` | `reviewer` (read-only review subagent: bugs, security, missing tests, ends with `VERDICT: PASS` or `BLOCK`) |
| `claude/commands/` | `/log`, `/prune`, `/test`, `/review-pr`, `/deploy`, `/hc`, `/rollback` (the last three expect `$HOMESERVER=user@host`) |
| `claude/skills/` | `autobuild` (hands-off feature loop), `tighten` (post-PR simplify + fix), `backlog` (cross-repo TODO + issue rollup), `call` (call recording to notes), `wanderlog` (Wanderlog trip API) |
| `claude/CLAUDE.md.example` | Global instructions template, copied to `~/CLAUDE.md` if you have none |
| `bin/` | `pstack-budget-statusline` (5h/7d plan usage in the statusline, picks a model budget tier), `safe-worktree-remove` (refuses dirty, unmerged or in-use worktrees), `repo-bootstrap` (fleet GitHub defaults: Actions lockdown, squash-only, protect-main ruleset), `review-rollout` (enable the CI Claude review on repos: allowlist, caller PR, label, secret), `ci-wait` (block until a PR's checks finish, exit 1 on any failure), `dnw-doctor` (read-only drift check of the live install: missing or stale files, unwired settings.json hooks, git identity, shell rc, tools), `transcribe` + `callrec` (local call recording + transcription), `pasteimg`, `chrome-devtools-mcp-gated`, `engraph-*` (engraph knowledge-graph MCP helpers) |
| `home/` | `gitconfig` (identity in `~/.gitconfig.local`), `gitignore_global`, oh-my-posh theme, `bashrc.d/dotfiles.sh` (brew, PATH, prompt, `pass`-backed secrets) |
| `skills-upstream.txt` | Third-party skills installed from their own repos, not copied here, plus a commented list of recommended plugins |

Also installed unless you pass `--no-deps`:
- npm: `chrome-devtools-mcp`, `@fission-ai/openspec`, `@charmland/crush`
- uv: `mcp-proxy`, `aider-chat`

Recommended plugin, not automated: [diagram-design](https://github.com/cathrynlavery/diagram-design) (MIT) drew the diagrams above. The sources are in `docs/diagrams/` and the project profile is `.diagram-design`.

```bash
claude plugin marketplace add cathrynlavery/diagram-design
claude plugin install diagram-design@diagram-design
```

Not automated:
- `bombadil` (UI property testing)
- `herdr` (installs its own hook)
- the Parakeet model that `transcribe` expects at `~/parakeet`

## Claude review

`.github/workflows/claude-review.yml` is a reusable workflow. On each PR it removes `REVIEWED`, has Claude review the diff read-only (Read/Grep/Glob, `git diff`/`git log`), posts the findings as a comment, and adds `REVIEWED` only on a PASS for the same head commit. A BLOCK, a missing or unparseable verdict, or a head that moved mid-review fails the job with no label. Fork PRs and drafts are skipped (no secrets on forks). The label is read from the action's `structured_output`, via `scripts/claude-review-verdict.sh`, which is always loaded from `main` rather than the PR.

Enable in a repo: create a `REVIEWED` label, run `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R owner/repo` with a token from `claude setup-token`, and copy `examples/claude-review-caller.yml` to `.github/workflows/review.yml`. Public repos keep `ubuntu-latest`. If the repo restricts allowed actions, allow `anthropics/claude-code-action@*`.

## Secrets

None are stored here. Scripts read tokens from environment variables or `pass` (e.g. `pass dev/magic-mcp-key`). A gitleaks pre-commit hook and GitHub push protection both block accidental commits.

### Keeping it public-safe

`scripts/public-safety-check.sh` fails if a tracked file contains personal data. It matches case-insensitively against three sources:

1. Builtin generic patterns: private IP ranges, private keys, absolute home directories.
2. Values derived from the machine at run time and never committed: `$USER`, `git config user.email` and `user.name`.
3. A private list, one regex per line with `#` comments, at `~/.config/do-no-work/public-safety-deny` (override with `PUBLIC_SAFETY_DENY`). See `scripts/public-safety-deny.example` for the format.

In CI the private list comes from the optional `PUBLIC_SAFETY_DENY_LIST` repo secret (empty on fork PRs). Set it with:

```bash
gh secret set PUBLIC_SAFETY_DENY_LIST -R nathanielgtran/do-no-work < ~/.config/do-no-work/public-safety-deny  # public-safety: allow (public repo name)
```

Output names the file, line and source but never prints a private pattern. A line containing `public-safety: allow` is skipped; give a reason next to it.

## Test

```bash
./tests/run-all.sh                  # every tests/*_test.sh plus the skill suites, summary table at the end
./tests/run-all.sh --only 'hooks*'  # one test by glob
./tests/run-all.sh --list           # what would run
```

New tests: name them tests/<x>_test.sh; CI picks them up, don't edit ci.yml.

CI runs these on GitHub-hosted Ubuntu and macOS, plus the skill test suites and gitleaks.
`scripts/public-safety-check.sh` also runs in CI and as a pre-commit hook.
A `windows` job runs `install.ps1 -NoDeps` on `windows-latest` into a throwaway home and checks the hook and bin script landed.

## License

MIT. See [LICENSE](LICENSE).
