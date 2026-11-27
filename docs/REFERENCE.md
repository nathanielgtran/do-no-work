# Reference

Everything in this repo, one card per item. Behaviour is taken from the code, not from the README. Paths are relative to the repo root; installed paths assume `install.sh` (hooks, commands, agents and skills go to `~/.claude/`, `bin/` goes to `~/.local/bin/`).

Each card has the same fields: what it does, when it runs, an example, how to configure or disable it, and the source.

| Section | What is in it |
|---|---|
| [Hooks](#hooks) | 10 hook scripts, 1 inline hook in the settings example, 1 hook script in a skill |
| [Slash commands](#slash-commands) | `/log`, `/prune`, `/test`, `/review-pr`, `/deploy`, `/hc`, `/rollback` |
| [Skills](#skills) | `autobuild`, `backlog`, `call`, `tighten`, `wanderlog` |
| [Agents](#agents) | `reviewer` |
| [CLI scripts (bin/)](#cli-scripts-bin) | 15 scripts installed to `~/.local/bin` |
| [Repo scripts (scripts/)](#repo-scripts-scripts) | review verdict, public-safety check, changelog, installers |
| [CI workflows](#ci-workflows) | `ci`, `claude-review`, `review`, caller example |
| [Settings example](#settings-example) | `claude/settings.example.json`, `CLAUDE.md.example`, other templates |

How hooks combine: all matching hooks for a call run, and the strictest decision wins (deny, then ask, then allow). `permissions.deny` rules in settings beat every hook.

To disable any hook, delete its entry from `~/.claude/settings.json` (the installer never edits that file). Editing hook files or settings from inside a Claude session is blocked on purpose; use a `!` command or edit by hand.

---

## Hooks

| Hook | Event | Matcher | Decision | Purpose |
|---|---|---|---|---|
| [`autonomy-gate`](#autonomy-gate) | PreToolUse | `Bash` | deny, ask | Block writes to the hooks and the autonomy dial; block push and merge when the dial is `less` |
| [`gate-self-merge`](#gate-self-merge) | PreToolUse | `Bash`, `if: Bash(gh pr merge:*)` | allow, ask | Allow a merge only when the PR has `REVIEWED` and all checks are green |
| [`openspec-autonomy`](#openspec-autonomy) | PreToolUse | `Bash` | allow (else no opinion) | Skip prompts for reversible commands in OpenSpec repos |
| [`protect-lint-config`](#protect-lint-config) | PreToolUse | `Edit\|Write\|MultiEdit` | ask | Ask before lint, format or type-check config changes |
| [`autonomy-toggle`](#autonomy-toggle) | UserPromptSubmit | none | none | Flip the dial on the exact prompts "go less" and "go full" |
| [`claude-notify`](#claude-notify) | PermissionRequest, Notification | `idle_prompt` for Notification | none | Discord DM when a session needs you |
| [`session-context`](#session-context) | SessionStart | none | none | Inject last daily-log entry, active todos, HANDOFF |
| [`compact-reinject`](#compact-reinject) | SessionStart | `compact` | none | Re-inject a rules digest and HANDOFF after compaction |
| [`go-check`](#go-check) | PostToolUse | `Write\|Edit` | none (feedback) | Run go test, vet and lint on the edited package |
| [`stop-gate`](#stop-gate) | Stop | none | block | Refuse to stop while the repo's fast check fails |
| [`gh pr create` review prompt](#gh-pr-create-review-prompt-inline) | PostToolUse | `Bash` | none (instruction) | Tell the session to review a new PR |
| [`flip-todo-on-merge.sh`](#flip-todo-on-merge) | PostToolUse | `Bash` | none | Tick the matching TODO.md line after a merge |

### `autonomy-gate`
**What:** Parses every Bash command, denies writes to `~/.claude/autonomy-level`, `~/.claude/hooks/` and this repo's `claude/hooks/`, and in `less` mode denies `git push` and `gh pr merge` (including `gh api ... merge`).  **When it runs:** PreToolUse on every Bash call, no `if` filter, so `git -C`, `cd && git push` and `VAR=1 git push` are all seen.
**Example:** `echo x > ~/.claude/hooks/a.sh` is denied; `cat ~/.claude/hooks/a.sh` passes. With the dial at `less`, `git push origin feat` is denied. If `jq` cannot parse the input or the level file is unreadable, it asks instead of passing.
**Configure / disable:** Level lives in `~/.claude/autonomy-level` (`full` or `less`; missing means `full`). The tamper guard applies at both levels. Remove the `autonomy-gate.sh` entry under `PreToolUse` > `Bash` to disable. A literal `$HOME/...` target is denied because it cannot be resolved statically.
**Source:** [`claude/hooks/autonomy-gate.sh`](../claude/hooks/autonomy-gate.sh)

### `gate-self-merge`
**What:** For `gh pr merge`, reads the PR's labels and the latest run of each check, and allows only when `REVIEWED` is present, there is at least one check, and none failed or are pending. Everything else asks.  **When it runs:** PreToolUse on Bash, filtered to `gh pr merge` by the settings `if`; the script also exits early for other commands.
**Example:** `gh pr merge 12 -R owner/repo --squash` with `REVIEWED` and green checks: allow. With a red check, no label, a second `gh pr merge` in the same command, `cd` or `git -C`, a shell variable instead of a literal PR number, or no checks at all: ask. It does not check merge method; squash comes from the review prompt and repo settings.
**Configure / disable:** No env vars. Needs `gh` and `jq`. Remove the entry to disable, which returns merges to the normal prompt.
**Source:** [`claude/hooks/gate-self-merge.sh`](../claude/hooks/gate-self-merge.sh)

### `openspec-autonomy`
**What:** Inside a repo that contains `openspec/config.yaml`, allows a Bash command with no prompt when every segment starts with an allowlisted verb (`git add/commit/rebase/fetch/pull/switch/checkout/branch/worktree/status/log/diff/show/stash/push`, `gh pr create/view/edit/checks/list/comment/diff`, `openspec`, `npm test/ci/run test|lint|build|typecheck`, `pytest`, `uv run pytest|ruff`, `go test/vet/build`, `make test|lint`).  **When it runs:** PreToolUse on every Bash call; it only acts when the dial is `full`.
**Example:** `git add -A && git commit -m "x"` in an OpenSpec repo: allow. Anything with a pipe, `$(`, backtick, redirect, `rm`, `sudo`, `ssh`, `git reset --hard`, `git clean`, push to main or force push, `gh api`, `gh release`, `npm publish`, or a touch of settings or hooks: no opinion, so the normal prompt applies. A `cd` or `git -C` into a non-OpenSpec directory (other than `/tmp`) also falls through.
**Configure / disable:** Reads `~/.claude/autonomy-level`. Edit the `allow` and `hard` regexes in the script to change the lists. A cloned repo can add `openspec/config.yaml`, so only wire this hook if you keep the `permissions.deny` block from the settings example.
**Source:** [`claude/hooks/openspec-autonomy.sh`](../claude/hooks/openspec-autonomy.sh)

### `protect-lint-config`
**What:** Asks before an Edit, Write or MultiEdit touches lint, format or type-check config. Plain config files always ask; `pyproject.toml` asks only when the change touches `[tool.ruff|mypy|pyright`; `tsconfig*.json` asks only when the change mentions a strictness key.  **When it runs:** PreToolUse on `Edit|Write|MultiEdit`.
**Example:** Adding `"noImplicitAny": false` to `tsconfig.json` asks with "lint/type config change: fix the code instead, or confirm". Editing `.eslintrc.json`, `eslint.config.*`, `.golangci.*`, `ruff.toml`, `.prettierrc*`, `biome.json`, `.markdownlint*`, `.pre-commit-config.yaml` or any `*baseline*.json` asks. Editing `src/app.ts` does not.
**Configure / disable:** No env vars. Add file names to `is_plain_config` to extend it. Remove the `Edit|Write|MultiEdit` entry to disable.
**Source:** [`claude/hooks/protect-lint-config.sh`](../claude/hooks/protect-lint-config.sh)

### `autonomy-toggle`
**What:** Writes `less` or `full` to `~/.claude/autonomy-level` when the whole prompt is exactly "go less" or "go full" (also "go into less/full mode"; case-insensitive, trailing `.` or `!` ignored).  **When it runs:** UserPromptSubmit.
**Example:** Typing `go less` blocks push and merge until you type `go full`. "go less strict on X" does nothing.
**Configure / disable:** State file is `~/.claude/autonomy-level`. Install writes `full` if the file is missing. Remove the `UserPromptSubmit` entry to lose the phrases; the file can still be edited by hand.
**Source:** [`claude/hooks/autonomy-toggle.sh`](../claude/hooks/autonomy-toggle.sh)

### `claude-notify`
**What:** Sends a Discord DM through a bot when Claude Code needs approval (tool and a redacted command) or has gone idle. Secrets-like strings in the message are redacted. It prints nothing on stdout, so it never decides a permission.  **When it runs:** PermissionRequest, and Notification with matcher `idle_prompt`. One DM per session per 120 s.
**Example:** `[WSL] Approval needed - owner/repo (a1b2c3d4)` followed by `Bash: gh pr merge 12 ...`.
**Configure / disable:** Env file `~/.config/claude-notify/env` (override with `CLAUDE_NOTIFY_ENV`) must set `DISCORD_BOT_TOKEN` and `DISCORD_OWNER_ID`; without it the hook logs and does nothing. Also `CLAUDE_NOTIFY_STATE` (state and log dir), `CLAUDE_NOTIFY_DEDUPE_SECS`, `CLAUDE_NOTIFY_SYNC` (send in the foreground). Needs `python3` and `curl`. Remove both entries to disable.
**Source:** [`claude/hooks/claude-notify.sh`](../claude/hooks/claude-notify.sh)

### `session-context`
**What:** Injects the most recent daily-log day, the "in progress" todo section and the "current work" notes from `~/Github/personal-kb/`, plus the repo's `.claude/HANDOFF.md` and live git state (marked STALE when the handoff commit differs from HEAD). Falls back to a "read the files" instruction if slicing finds nothing, and skips the KB part if the folder is missing.  **When it runs:** SessionStart, every start.
**Example:** A new session opens with last workday's log and active todos already in context, so Claude asks about meetings and goals instead of reading three files.
**Configure / disable:** The KB path is hard-coded to `~/Github/personal-kb`; edit `KB` in the script. Lines are clipped at 180 characters. Without that folder only the HANDOFF part applies. Remove the entry to disable.
**Source:** [`claude/hooks/session-context.sh`](../claude/hooks/session-context.sh)

### `compact-reinject`
**What:** Prints `~/.claude/compact-digest.md` and the first 30 lines of the repo's `.claude/HANDOFF.md` so they survive compaction. Always exits 0; missing files are skipped.  **When it runs:** SessionStart with matcher `compact`.
**Example:** After `/compact`, the digest of hard rules reappears in context.
**Configure / disable:** `COMPACT_DIGEST` overrides the digest path. Write the digest yourself. Remove the `compact` entry to disable.
**Source:** [`claude/hooks/compact-reinject.sh`](../claude/hooks/compact-reinject.sh)

### `go-check`
**What:** After a `.go` file is written or edited, finds its `go.mod`, then runs `go test`, `go vet` and (if installed) `golangci-lint run --new-from-rev=HEAD` on that package, with 90 s timeouts and 40-line clipping. Sends failures back as context, or a short pass message.  **When it runs:** PostToolUse on `Write|Edit`; exits at once for other files.
**Example:** Editing `internal/store/db.go` runs the checks for `./internal/store` only.
**Configure / disable:** No env vars. Needs `go` on PATH (`/usr/local/go/bin` and `~/go/bin` are added). Remove the entry to disable.
**Source:** [`claude/hooks/go-check.sh`](../claude/hooks/go-check.sh)

### `stop-gate`
**What:** On Stop, if the working tree has changes, runs the repo's fast check and blocks the stop with the failure output (40 lines). The check is `$CLAUDE_STOP_GATE_CMD`, else the first line of `.claude/stop-gate`, else auto-detect (`go vet ./... && go test ./...`, `npm test --silent`, or `pytest -q -x`, plus `openspec validate --strict --all` when `openspec/config.yaml` exists). It lets the stop through when the same failure repeats under `stop_hook_active`, when not in git, when the tree is clean, or when no check is found.  **When it runs:** Stop.
**Example:** Claude edits a Go file and tries to finish with a failing test; the stop is blocked with the `go test` output. A second identical failure after a retry is allowed through with a message.
**Configure / disable:** `CLAUDE_STOP_GATE_CMD` (runs in any repo), `CLAUDE_STOP_GATE_TIMEOUT` (seconds, default 120), `CLAUDE_STOP_GATE_OWNERS` (space-separated GitHub users or orgs). Repo-defined checks (`.claude/stop-gate`, auto-detect) run only when `origin` is owned by one of those owners, so a cloned repo cannot run code. Remove the `Stop` entry to disable. Keep the check fast.
**Source:** [`claude/hooks/stop-gate.sh`](../claude/hooks/stop-gate.sh)

### `gh pr create` review prompt (inline)
**What:** An inline command in the settings example. When a Bash command contains `gh pr create`, it returns context telling the session to spawn a sonnet reviewer, fix findings, apply `REVIEWED`, wait for CI with `gh pr checks --watch --fail-fast`, then squash-merge. It never merges red.  **When it runs:** PostToolUse on Bash.
**Example:** After `gh pr create`, the session reviews its own PR and, with `gh pr merge` gated by `gate-self-merge`, merges only when green and labelled. It does not fire for PRs opened by sub-agents.
**Configure / disable:** Edit the instruction string in `claude/settings.example.json` before merging it into your settings. Remove the first PostToolUse Bash entry to disable. With the [Claude review workflow](#claude-review) enabled, CI applies the label too.
**Source:** [`claude/settings.example.json`](../claude/settings.example.json)

### `flip-todo-on-merge`
**What:** After `gh pr merge <N>`, flips the matching open `- [ ]` line in the repo's `TODO.md` to `- [x]`. Supports `--dry-run`.  **When it runs:** PostToolUse on Bash (second entry in the example); it ignores other commands.
**Example:** `gh pr merge 154` ticks the TODO line that mentions PR 154.
**Configure / disable:** Wiring notes in `claude/skills/backlog/hook-install.md`. Remove the second PostToolUse Bash entry to disable.
**Source:** [`claude/skills/backlog/flip-todo-on-merge.sh`](../claude/skills/backlog/flip-todo-on-merge.sh)

---

## Slash commands

Installed to `~/.claude/commands/`. They are prompts, not scripts, so edit the markdown to change them.

### `/log`
**What:** End-of-session sync: daily log, notes, todo, `PLAN.md` current state, a gitignored per-worktree `.claude/HANDOFF.md` (25 lines, with the HEAD sha), CHANGELOG, repo CLAUDE.md and memory, then commits and pushes personal-kb.  **When it runs:** You type `/log` after finishing work.
**Example:** `/log` after merging a PR adds the PR to today's daily-log and moves the todo to completed.
**Configure / disable:** Assumes `~/Github/personal-kb`. Delete the file to remove it. The repo template says PRs add a `changelog.d/` fragment instead of editing `CHANGELOG.md`; adjust step 6 if you use fragments.
**Source:** [`claude/commands/log.md`](../claude/commands/log.md)

### `/prune`
**What:** Shrinks startup context: 3-day rolling daily-log, completed todos to an archive, one-line notes per project, done phases in `PLAN.md`, stale references in CLAUDE.md.  **When it runs:** You type `/prune` every few sessions.
**Example:** `/prune` archives daily-log entries older than 3 days.
**Configure / disable:** Edit the rules in the file. It commits and pushes.
**Source:** [`claude/commands/prune.md`](../claude/commands/prune.md)

### `/test`
**What:** Detects Go, Node, Python or Rust from the repo root and runs its tests (plus `go vet`, `golangci-lint`, `cargo clippy`), then summarises.  **When it runs:** `/test [package-or-path]`.
**Example:** `/test internal/store` runs `go test ./internal/store/...`.
**Configure / disable:** Edit the file for other stacks.
**Source:** [`claude/commands/test.md`](../claude/commands/test.md)

### `/review-pr`
**What:** Reads `gh pr view` and `gh pr diff`, reviews for bugs, security, tests, code quality and CLAUDE.md compliance, and prints a severity table.  **When it runs:** `/review-pr [number]`; defaults to the current branch's PR.
**Example:** `/review-pr 42` returns `LGTM`, `Minor Issues` or `Needs Changes` with a table. It does not apply a label.
**Configure / disable:** Edit the rubric in the file. For label-applying review use the [CI workflow](#claude-review) or the [`reviewer` agent](#reviewer).
**Source:** [`claude/commands/review-pr.md`](../claude/commands/review-pr.md)

### `/deploy`
**What:** Confirms service and version, checks `main` is current and tests pass, tags and creates a GitHub release, watches the release workflow, then checks the container and health endpoint over SSH.  **When it runs:** `/deploy [service] [version]`; version defaults to the next patch.
**Example:** `/deploy myservice` tags the next patch version and watches `release.yml`.
**Configure / disable:** Needs `HOMESERVER=user@host`. The `gh release` step is a release, so run it only where releases are yours to cut.
**Source:** [`claude/commands/deploy.md`](../claude/commands/deploy.md)

### `/hc`
**What:** Health check of the home server over SSH: ping, uptime, disk, memory, docker containers and stats, and an HTTP status for each URL in `HC_URLS`.  **When it runs:** `/hc`.
**Example:** `HC_URLS="https://a.example https://b.example"` then `/hc` prints a status table and flags unhealthy items.
**Configure / disable:** Needs `HOMESERVER=user@host` and optionally `HC_URLS`.
**Source:** [`claude/commands/hc.md`](../claude/commands/hc.md)

### `/rollback`
**What:** Stops the service on the server, retags its `:previous` image as `:latest`, brings it back up and curls a health URL.  **When it runs:** `/rollback <service>`.
**Example:** `/rollback myservice` expects `~/myservice/docker-compose.yml` on the host with a `:previous` tag pushed by the release workflow.
**Configure / disable:** Needs `HOMESERVER`; `HEALTH_URL` overrides `http://localhost:8000/health`.
**Source:** [`claude/commands/rollback.md`](../claude/commands/rollback.md)

---

## Skills

Installed to `~/.claude/skills/<name>/`. Upstream skills listed in `skills-upstream.txt` install separately; see [Settings example](#settings-example) for the plugin list.

### `autobuild`
**What:** Hands-off feature loop for an OpenSpec repo: scout, pick up to three features, cut worktrees from `origin/main` with pre-assigned IDs, build in parallel agents, review each PR yourself, wait for CI, label then merge in separate calls, rebase the next PR, verify live, log.  **When it runs:** Say "autobuild", "keep building features" or "scout and build".
**Example:** In an OpenSpec repo, "autobuild, go" picks three features, opens three PRs and merges them one at a time. It stops without `openspec/config.yaml`, builds only to open PRs when the dial is `less`, and stops at once if you reject a tool call.
**Configure / disable:** Reads `REPOS.md`, `TODO.md`, `PLAN.md`. Model comes from `~/.claude/rules/pstack-models.md`. Delete the skill folder to remove it. See the [diagram](../README.md#autobuild-hands-off-feature-loop).
**Source:** [`claude/skills/autobuild/SKILL.md`](../claude/skills/autobuild/SKILL.md)

### `backlog`
**What:** Regenerates `personal-kb/backlog.md`, a read-only rollup of every real repo's open `- [ ]` TODO lines plus open GitHub issues, grouped by urgency. Worktrees are skipped.  **When it runs:** "what's open", "backlog", or `python3 ~/.claude/skills/backlog/generate.py`.
**Example:** `python3 ~/.claude/skills/backlog/generate.py --no-gh` rebuilds offline. Never hand-edit the output; edit the repo's `TODO.md`.
**Configure / disable:** `--no-gh` skips issue calls. Tests: `test_generate.py` (CI runs it with `uvx pytest`). The merge hook that ticks TODOs is in [`hook-install.md`](../claude/skills/backlog/hook-install.md).
**Source:** [`claude/skills/backlog/SKILL.md`](../claude/skills/backlog/SKILL.md), [`generate.py`](../claude/skills/backlog/generate.py)

### `call`
**What:** Transcribes the newest call recording locally (Parakeet on CPU) with `transcribe --last`, reads the `[mm:ss]` transcript and summarises key points, action items and open questions, then offers to file it.  **When it runs:** "transcribe the last call", `/call`, or a path to a recording.
**Example:** `/call` finds the latest recording, transcribes it, and prints a summary with timestamps. Audio never leaves the machine.
**Configure / disable:** Needs the Parakeet install `transcribe` expects (not automated) and `callrec` or OBS recordings. Edit the filing path (personal-kb) in the skill.
**Source:** [`claude/skills/call/SKILL.md`](../claude/skills/call/SKILL.md)

### `tighten`
**What:** Cleanup that fixes what it reviews. PR mode checks the PR out into a detached worktree, sizes the diff into a tier, runs one reviewer against `rubric.md`, applies bounded fixes (net-negative lines or correctness), verifies with lint and tests, pushes, strips `REVIEWED`, adds a `tightened` label and posts one comment. File mode tightens one prose or code file without losing facts.  **When it runs:** `/tighten [PR# | path] [--again] [--dry] [--tier N]`; model invocation is disabled.
**Example:** `/tighten 42 --dry` reports what it would change without editing. It refuses merged PRs, forks and unpushed commits.
**Configure / disable:** `--dry`, `--tier`. Wiring into the PR hook is manual: see [`HOOK-INSTALL.md`](../claude/skills/tighten/HOOK-INSTALL.md). Tests under `claude/skills/tighten/tests/` run in CI on Linux.
**Source:** [`claude/skills/tighten/SKILL.md`](../claude/skills/tighten/SKILL.md)

### `wanderlog`
**What:** CLI wrapper (`wl.py`) around Wanderlog's internal JSON API: list trips, export a trip to markdown, archive all trips, create trips, add places and notes, or make a raw call.  **When it runs:** "my Wanderlog", or `python3 ~/.claude/skills/wanderlog/wl.py <cmd>`.
**Example:** `wl.py trips`, then `wl.py export <key>`. Commands: `trips`, `export`, `places`, `archive`, `trip-create`, `place-add`, `note-add`, `refresh`, `raw`.
**Configure / disable:** Auth is a `connect.sid` cookie cached at `~/.config/wanderlog/session`, refreshed with credentials from `pass personal/wanderlog`. `archive` writes under `~/Github/personal-kb/travel/wanderlog` by default (`--out` overrides). Tests: `test_wl.py`.
**Source:** [`claude/skills/wanderlog/SKILL.md`](../claude/skills/wanderlog/SKILL.md)

---

## Agents

### `reviewer`
**What:** Read-only review subagent (tools: Read, Grep, Glob; model sonnet). Loads the repo CLAUDE.md and any matching `openspec/changes/<id>/`, reports real bugs, security issues, missing tests and clear rule violations with `file:line` and a failing scenario, and ends with `VERDICT: PASS` or `VERDICT: BLOCK`.  **When it runs:** The parent delegates to it after a change, passing the diff or paths.
**Example:** "Use the reviewer agent on `git diff origin/main`" returns findings and a verdict line.
**Configure / disable:** Edit `tools` or `model` in the front matter. It cannot run commands or edit. Delete `~/.claude/agents/reviewer.md` to remove it.
**Source:** [`claude/agents/reviewer.md`](../claude/agents/reviewer.md)

---

## CLI scripts (bin/)

Installed to `~/.local/bin/`. Most are bash; `engraph-mcp-proxy` is Python.

### `pstack-budget-statusline`
**What:** Statusline command that prints model, 5-hour and 7-day plan usage, and rewrites `~/.claude/rules/pstack-models.md` so new sessions pick a budget tier from the higher of the two: under 50% large, under 80% medium, else small.  **When it runs:** Every statusline refresh (`statusLine` in settings).
**Example:** `Opus | 5h 42% | 7d 31% | pstack large`. With no rate-limit data it prints `usage n/a` and leaves the rule alone.
**Configure / disable:** `PSTACK_RULE` overrides the rule path. Hand edits to that rule are overwritten. Remove the `statusLine` entry to disable.
**Source:** [`bin/pstack-budget-statusline`](../bin/pstack-budget-statusline)

### `safe-worktree-remove`
**What:** Removes a worktree only when nothing uses it. Refuses the main checkout, locked worktrees, dirty or untracked changes, commits not pushed, not on the default branch and not in a merged PR, and any process whose cwd is inside it. Never passes `--force`.  **When it runs:** You or an agent run it after a PR merges.
**Example:** `safe-worktree-remove ../repo-task --branch` removes the worktree and deletes its branch.
**Configure / disable:** Needs `/proc` or `lsof` for the in-use check.
**Source:** [`bin/safe-worktree-remove`](../bin/safe-worktree-remove)

### `repo-bootstrap`
**What:** Applies fleet defaults to an existing GitHub repo through `gh api`: read-only Actions token, selected actions only, fork-PR approval, squash-only merges with branch auto-delete, secret scanning and push protection, private vulnerability reporting, Dependabot alerts, the `REVIEWED` label, and a `protect-main` ruleset. Idempotent.  **When it runs:** Once per repo, by hand.
**Example:** `BOOTSTRAP_CHECKS="test (ubuntu-latest),gitleaks" repo-bootstrap owner/repo --public`.
**Configure / disable:** `--dry-run` prints the writes. `--public` warns on self-hosted runners. `BOOTSTRAP_ACTIONS` sets allowed actions (default `astral-sh/setup-uv@*,gitleaks/gitleaks-action@*`); without `BOOTSTRAP_CHECKS` the required-checks rule is skipped. Test: `tests/bootstrap_test.sh`.
**Review mode:** `repo-bootstrap owner/repo --review` sets up only the CI Claude review. It ensures the `REVIEWED` label exists, merges the pinned `claude-code-action` and its nested `setup-bun` into a `selected` actions allowlist without dropping existing patterns, opens a PR adding `.github/workflows/review.yml` if missing, and sets `CLAUDE_CODE_OAUTH_TOKEN` from the env via stdin (never echoed). The caller is pinned to the full SHA of `BOOTSTRAP_REVIEW_SRC` HEAD (or `BOOTSTRAP_REVIEW_REF`; only a 40-hex result is accepted) with `tools-ref` set to the same SHA and a job-level fork guard. Private repos: `BOOTSTRAP_REVIEW_RUNS_ON` (label or JSON) wins; unset or `auto` queries the repo's runners and picks the single `nuc-*` label, else `nuc`, else `ubuntu-latest` with a printed note. Public repos (or `--public`, or detected via `gh repo view`) always get `ubuntu-latest`; `--public` refuses self-hosted. A `skip-changelog` label, if the repo has one, is applied to the caller PR. **Update mode:** if the caller already exists on the default branch or a `NO-TICKET-claude-review` PR is open, the new caller is rendered and compared; a difference opens `NO-TICKET-claude-review-harden` and a `[NO-TICKET] ci: harden Claude review caller (pin SHA, fork guard)` PR (or updates the open caller PR's branch and comments), identical prints `ok`. Only `review.yml` is touched. Test: `tests/review_test.sh`.
**Source:** [`bin/repo-bootstrap`](../bin/repo-bootstrap)

### `review-rollout`
**What:** Runs `repo-bootstrap <repo> --review` across many repos, adding `--public` for public ones, continuing past failures, then prints a repo / label / allowlist / caller / secret table.  **When it runs:** By hand when enabling the review on more repos.
**Example:** `CLAUDE_CODE_OAUTH_TOKEN=... review-rollout owner/a owner/b`.
**Configure / disable:** Same env as `repo-bootstrap --review`; re-running it over repos with an existing caller opens or refreshes hardening PRs. To disable the review on a repo, delete its `.github/workflows/review.yml`.
**Source:** [`bin/review-rollout`](../bin/review-rollout)

### `dnw-doctor`
**What:** Read-only drift check of the live install against the repo: missing or stale installed files, hooks from `settings.example.json` not wired into `~/.claude/settings.json`, missing `statusLine` / deny rules, git identity, shell rc source line, and tools on PATH. Each problem prints a `fix:` line with the exact command.  **When it runs:** By hand after pulling.
**Example:** `dnw-doctor` prints `ok installed 43 files match the repo` or `warn settings hook missing under PreToolUse: ...` with its fix. `--json` for machines. Exit 1 on any `fail`.
**Configure / disable:** `--repo DIR` to check another checkout. It never edits settings.
**Source:** [`bin/dnw-doctor`](../bin/dnw-doctor), mapping shared with `install.sh` via [`scripts/install-manifest.sh`](../scripts/install-manifest.sh)

### `ci-wait`
**What:** Polls a PR's checks until all finish; prints each result; exits 0 only if all passed (success, skipped, neutral).  **When it runs:** You or an agent run it after a push.
**Example:** `ci-wait 42 -R owner/repo` prints `test (ubuntu-latest): success` and so on. Exit 1 on failure, timeout or no checks; exit 2 on bad usage.
**Configure / disable:** `CI_WAIT_TIMEOUT` (1200 s), `CI_WAIT_INTERVAL` (15 s), `CI_WAIT_EMPTY_GRACE` (60 s of waiting for checks to appear). Test: `tests/ci_wait_test.sh`.
**Source:** [`bin/ci-wait`](../bin/ci-wait)

### `callrec`
**What:** Starts and stops an OBS recording from WSL over obs-websocket (mic and desktop audio), then runs `transcribe` on the file.  **When it runs:** `callrec start`, `callrec stop [--no-transcribe]`, `callrec status`.
**Example:** `callrec start` before a call, `callrec stop` after; the transcript lands next to the recording.
**Configure / disable:** Windows and WSL only. Needs OBS with the websocket server on port 4455. Password from `OBS_WS_PASSWORD`, OBS's own config, or `pass`. Other env: `CALLREC_OBS_DIR`, `CALLREC_REC_DIR`, `CALLREC_OBS_WS_CONFIG`, `CALLREC_SETTLE_SECS`. Uses `lib/obsws.ps1`.
**Source:** [`bin/callrec`](../bin/callrec), [`lib/obsws.ps1`](../lib/obsws.ps1)

### `transcribe`
**What:** Wraps the local Parakeet CPU transcriber: `uv run --project ~/parakeet python ~/parakeet/transcribe.py "$@"`.  **When it runs:** By hand, or from the `call` skill.
**Example:** `transcribe --last` or `transcribe recording.mkv`.
**Configure / disable:** The Parakeet install at `~/parakeet` is not automated and not in this repo.
**Source:** [`bin/transcribe`](../bin/transcribe)

### `pasteimg`
**What:** Saves the Windows clipboard image to a file and prints its WSL path so Claude Code can read it.  **When it runs:** After a Win+Shift+S snip.
**Example:** `pasteimg` prints `.../Pictures/Screenshots/clip.png`; mention that path in the prompt.
**Configure / disable:** `PASTEIMG_OUT` sets the output file; `WIN_HOME` overrides the Windows home. WSL only.
**Source:** [`bin/pasteimg`](../bin/pasteimg)

### `chrome-devtools-mcp-gated`
**What:** MCP launcher that runs the real `chrome-devtools-mcp` (headless, isolated) only when the working directory matches your UI repo glob, otherwise a stub MCP server with no tools, to save memory.  **When it runs:** As the MCP server command in your MCP config.
**Example:** In `~/Github/site-ui` it starts Chrome; in any other repo it answers `initialize` and `tools/list` with nothing.
**Configure / disable:** `CHROME_MCP_REPO_GLOB` (a `case` pattern; default `$HOME/Github/*-ui*`), `CHROME_BIN`.
**Source:** [`bin/chrome-devtools-mcp-gated`](../bin/chrome-devtools-mcp-gated)

### `engraph-*` helpers
Helpers for the engraph knowledge-graph MCP server over a vault of hardlinked markdown (`memory` and `personal-kb`). Skip them if you do not run engraph.

### `engraph-enqueue`
**What:** Queues vault files for reindexing and returns at once.  **When it runs:** After you edit a memory or personal-kb note.
**Example:** `engraph-enqueue ~/Github/personal-kb/notes.md` prints `queued: personal-kb/notes.md`.
**Configure / disable:** `ENGRAPH_QUEUE_DIR`. Accepts only `.md` files under memory, personal-kb or the vault.
**Source:** [`bin/engraph-enqueue`](../bin/engraph-enqueue)

### `engraph-reindex-drain`
**What:** Drains the queue: dedupes, syncs the vault to the index host, calls MCP `reindex_file` once per file, retries three times, then writes `reindex.failed`.  **When it runs:** From a systemd path unit when the queue changes.
**Example:** Runs unattended; read `reindex.failed` for leftovers.
**Configure / disable:** `ENGRAPH_MCP_URL`, `ENGRAPH_CALL_TIMEOUT` (900), `ENGRAPH_MAX_BYTES` (30000), `ENGRAPH_SYNC_CMD` (copy the vault to a remote index host).
**Source:** [`bin/engraph-reindex-drain`](../bin/engraph-reindex-drain)

### `engraph-relink`
**What:** Rebuilds the combined vault as hardlinks of `*.md` from the memory and personal-kb sources, skipping archives and `output/`.  **When it runs:** After files are added or deleted; also called by the refresh scripts.
**Example:** `engraph-relink` prints `relinked N markdown files into ~/engraph-vault`.
**Configure / disable:** Source roots are set in the script.
**Source:** [`bin/engraph-relink`](../bin/engraph-relink)

### `engraph-refresh`
**What:** Relinks, then runs `engraph index --rebuild` and `engraph status`. Refuses while `engraph serve` holds the database lock.  **When it runs:** By hand, with no Claude session using the engraph MCP.
**Example:** `engraph-refresh` after renames or deletes.
**Configure / disable:** For one changed note use `engraph-enqueue` instead.
**Source:** [`bin/engraph-refresh`](../bin/engraph-refresh)

### `engraph-nightly-index`
**What:** Stops `engraph-mcp`, relinks, runs `engraph index`, restarts the server, and warns when the indexed count differs from the file count by more than one.  **When it runs:** From a nightly systemd timer.
**Example:** Logs `indexed=312 fs=312 diff=0 secs=41` to the journal.
**Configure / disable:** Needs systemd user units named `engraph-mcp`.
**Source:** [`bin/engraph-nightly-index`](../bin/engraph-nightly-index)

### `engraph-mcp-watchdog`
**What:** Health check for `engraph-mcp`: process tree, then a real MCP `initialize` and `tools/list` on `127.0.0.1:8765`; restarts the service on failure. Does nothing if the service was stopped on purpose.  **When it runs:** From a systemd timer.
**Example:** Journal line `UNHEALTHY: initialize failed -- restarting engraph-mcp`.
**Configure / disable:** Port is fixed in the script.
**Source:** [`bin/engraph-mcp-watchdog`](../bin/engraph-mcp-watchdog)

### `engraph-mcp-proxy`
**What:** Runs `mcp-proxy` with a Host and Origin allowlist (localhost:8765 only) to block DNS rebinding and cross-origin browser requests; others get 403.  **When it runs:** As the service command, using mcp-proxy's own Python.
**Example:** A request with `Host: evil.example` gets `403 forbidden host or origin`.
**Configure / disable:** Edit `HOSTS` and `ORIGINS` in the script.
**Source:** [`bin/engraph-mcp-proxy`](../bin/engraph-mcp-proxy)

---

## Repo scripts (scripts/)

### `claude-review-verdict.sh`
**What:** Turns the review action's structured output into a PR comment and, only on `PASS` for the commit that was reviewed, the `REVIEWED` label. Fails closed on a missing or unparseable verdict, a `BLOCK`, or a head commit that moved.  **When it runs:** Last step of the [`claude-review` workflow](#claude-review), loaded from `main`, never from the PR.
**Example:** `PASS` at the expected sha adds the label; `BLOCK` posts the comment and exits 1.
**Configure / disable:** Env `REPO`, `PR`, `EXPECTED_SHA`, `STRUCTURED_OUTPUT`; `GH` overrides the gh binary for tests. Test: `tests/claude_review_verdict_test.sh`.
**Source:** [`scripts/claude-review-verdict.sh`](../scripts/claude-review-verdict.sh)

### `public-safety-check.sh`
**What:** Fails if a tracked file contains personal data: builtin patterns (private IPs, private keys, absolute home directories), values derived from the machine (`$USER`, git `user.email` and `user.name`), and a private regex list. Output names file, line and source but never prints a private pattern. A line containing `public-safety: allow` is skipped, so give a reason beside it.  **When it runs:** Pre-commit hook and CI.
**Example:** `./scripts/public-safety-check.sh` prints `public-safety: ok (N files)` or `file:line: [builtin] ...`.
**Configure / disable:** Private list at `~/.config/do-no-work/public-safety-deny` (override `PUBLIC_SAFETY_DENY`); in CI it comes from the `PUBLIC_SAFETY_DENY_LIST` secret. Format in [`public-safety-deny.example`](../scripts/public-safety-deny.example). Test: `tests/public_safety_test.sh`.
**Source:** [`scripts/public-safety-check.sh`](../scripts/public-safety-check.sh)

### `changelog.sh` and `changelog.d/`
**What:** Changelog fragments so parallel PRs never conflict on `CHANGELOG.md`. Each PR adds `changelog.d/<type-N>.md` holding one line (no ID). `next <type>` prints the next free ID, `check` validates names, one-line content, duplicates and IDs already in the changelog, `compile` folds fragments into `CHANGELOG.md` and removes them.  **When it runs:** `check` in CI; `next` when you start a PR; `compile` at release.
**Example:** `scripts/changelog.sh next docs` prints `docs-3`; `scripts/changelog.sh compile --version v1.0.0` adds a `## v1.0.0 - <date>` block.
**Configure / disable:** Types are `feat`, `fix`, `docs`, `chore`. `TRASH_DIR` sets where uncommitted fragments go after compile. Test: `tests/changelog_test.sh`.
**Source:** [`scripts/changelog.sh`](../scripts/changelog.sh), [`changelog.d/README.md`](../changelog.d/README.md)

### `install.sh`
**What:** Installs on macOS, Linux and WSL. Places `home/` config, `bin/` scripts and `claude/` hooks, commands, agents and skills (symlinks by default), creates `~/.claude/autonomy-level` as `full` if missing, copies `CLAUDE.md.example` to `~/CLAUDE.md` if you have none, installs packages, then upstream skills. It never edits `settings.json`. Anything that differs is moved to `~/.dotfiles-backup/<timestamp>/` first, and reruns leave identical files alone.  **When it runs:** By hand, once and after pulls.
**Example:** `./install.sh --copy --no-deps`.
**Configure / disable:** `--copy`, `--no-deps`. Env: `GIT_NAME` and `GIT_EMAIL` for non-interactive installs, `DOTFILES_SKIP_UPSTREAM=1`. Test: `tests/install_test.sh`.
**Source:** [`install.sh`](../install.sh)

### `install.ps1`
**What:** Windows entry point. Installs packages with winget (unless `-NoDeps`), finds Git Bash, runs `install.sh --copy --no-deps` through it, and adds oh-my-posh to the PowerShell profile.  **When it runs:** By hand from PowerShell.
**Example:** `powershell -ExecutionPolicy Bypass -File .\install.ps1`.
**Configure / disable:** `-NoDeps`. Files are copied, not symlinked. The `windows` CI job runs it into a throwaway home.
**Source:** [`install.ps1`](../install.ps1)

---

## CI workflows

### `ci`
**What:** Shell syntax check, then `tests/run-all.sh` on Ubuntu and macOS (discovers every `tests/*_test.sh`, plus the wanderlog, backlog and tighten suites), changelog fragment check, the public-safety check, a Windows install into a throwaway home, and gitleaks. Pinned action SHAs, read-only token.  **When it runs:** Pull requests and pushes to `main`.
**Example:** Add `tests/<x>_test.sh` and CI runs it with no workflow edit; `tests/ci_discovery_test.sh` fails if `ci.yml` lists individual tests.
**Configure / disable:** Secret `PUBLIC_SAFETY_DENY_LIST` is optional. Required checks come from `repo-bootstrap` (`BOOTSTRAP_CHECKS`).
**Source:** [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

### `claude-review`
**What:** Reusable workflow. Removes `REVIEWED` if present, skips forks and drafts, checks out the PR head and a trusted copy of the verdict script from `tools-ref`, has Claude review the diff read-only (Read, Grep, Glob, `git diff`, `git log`; max 20 turns), and applies `REVIEWED` only on a `PASS` for that commit.  **When it runs:** Called on `pull_request` opened, synchronize, reopened, ready_for_review.
**Example:** A push after review removes the label and re-reviews. A `BLOCK`, missing verdict or moved head fails the job with no label.
**Configure / disable:** Secret `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`). Inputs: `runs-on` (JSON, default `"ubuntu-latest"`; keep it for public repos), `model`, `max-turns`, `tools-ref`. Allow `anthropics/claude-code-action@*` if actions are restricted.
**Source:** [`.github/workflows/claude-review.yml`](../.github/workflows/claude-review.yml)

### `review`
**What:** This repo's own caller of `claude-review` (`uses: ./.github/workflows/claude-review.yml`, no pin needed; job-level fork guard).  **When it runs:** Same PR events.
**Example:** Every PR here gets the review and label automatically.
**Configure / disable:** Delete the file to stop self-review.
**Source:** [`.github/workflows/review.yml`](../.github/workflows/review.yml)

### `claude-review-caller.yml` (example)
**What:** The file to copy into another repo as `.github/workflows/review.yml`. Calls this repo's reusable workflow pinned at `@<40-hex SHA>` (placeholders `__SHA__`, `__SHORT__`, `__RUNS_ON__`, filled by `repo-bootstrap --review`) with `tools-ref` set to the same SHA, a job-level fork guard, `contents: read` and `pull-requests: write`.  **When it runs:** Not run here; it is a template.
**Example:** Create a `REVIEWED` label, set the secret, run `repo-bootstrap owner/repo --review`.
**Configure / disable:** Private repos pass `runs-on` as their repo-specific runner, e.g. `'["self-hosted","nuc-myrepo"]'`; public repos drop the line.
**Source:** [`examples/claude-review-caller.yml`](../examples/claude-review-caller.yml)

---

## Settings example

### `settings.example.json`
**What:** The wiring for everything above. Sections: `permissions.deny` (rm, sudo, push to main or master, force push, `--admin` merge, edits to settings, the dial and hooks), `hooks` (all hooks above), `statusLine`, `sandbox`, `autoMode.environment`.  **When it runs:** Not installed. Merge `hooks`, `permissions` and `statusLine` into `~/.claude/settings.json` by hand.
**Example:** The sandbox block turns on the OS sandbox with `denyRead` for `~/.password-store`, `~/.gnupg`, `~/.ssh` and a strict network allowlist; `autoMode.environment` starts with `$defaults` plus your own lines (user settings only).
**Configure / disable:** Replace the placeholder registry domain and `homeserver.local`. Keep the deny block if you wire `openspec-autonomy`. Remove any hook entry to disable that hook.
**Source:** [`claude/settings.example.json`](../claude/settings.example.json)

### `CLAUDE.md.example`
**What:** Global instructions template: hard rules, worktree rules, code and PR rules (no hacks, comments default to none, fleet PR template, changelog fragments), agent use, autonomy, workflows, UI/UX rules. Copied to `~/CLAUDE.md` if none exists; fill `<NAME>` and `<ROLE>`.  **When it runs:** Loaded by Claude Code every session.
**Example:** The rule "never push to main" is repeated as a deny rule so it does not depend on the prompt.
**Configure / disable:** Edit freely; shrink prose once a rule is enforced by a hook or check.
**Source:** [`claude/CLAUDE.md.example`](../claude/CLAUDE.md.example)

### `.worktreeinclude.example`
**What:** Copy to `.worktreeinclude` so gitignored small files (`.env`, `.env.local`, `config/*.local.*`) are copied into worktrees Claude Code creates.  **When it runs:** On worktree creation.
**Example:** A new worktree starts with a working `.env`.
**Configure / disable:** It copies, it does not link. For `node_modules` set `worktree.symlinkDirectories` in settings.
**Source:** [`.worktreeinclude.example`](../.worktreeinclude.example)

### `skills-upstream.txt`
**What:** Third-party skills, one `owner/repo` per line, installed by the installers with `npx skills add -g`. A commented section lists plugins to install yourself, including diagram-design.  **When it runs:** During `install.sh` and `install.ps1`.
**Example:** `claude plugin marketplace add cathrynlavery/diagram-design` then `claude plugin install diagram-design@diagram-design`.
**Configure / disable:** `DOTFILES_SKIP_UPSTREAM=1` skips the skill installs. Comment a line out to drop one.
**Source:** [`skills-upstream.txt`](../skills-upstream.txt)

### Other files
- [`.pre-commit-config.yaml`](../.pre-commit-config.yaml): gitleaks and the public-safety check.
- [`home/`](../home): `gitconfig` (identity in `~/.gitconfig.local`), `gitignore_global`, oh-my-posh theme, `bashrc.d/dotfiles.sh`.
- [`docs/diagrams/`](diagrams): HTML sources and SVGs for the README diagrams; `.diagram-design` selects the style profile.
- [`docs/workflow-research.md`](workflow-research.md): what was adopted and what to try next.
