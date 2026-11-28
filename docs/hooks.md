# Hooks

Hooks are scripts Claude Code runs on events such as a Bash call or a stop. They install to `~/.claude/hooks/`. [Back to the catalogue](REFERENCE.md).

- All matching hooks for a call run. The strictest decision wins: deny, then ask, then allow.
- `permissions.deny` rules in settings beat every hook.
- To disable a hook, delete its entry from `~/.claude/settings.json`. The installer never edits that file.
- Editing hook files or settings from inside a Claude session is blocked on purpose. Use a `!` command or edit by hand.

| Hook | Runs on | Does |
|---|---|---|
| [`autonomy-gate`](#autonomy-gate) | PreToolUse: `Bash` | Guard the dial, the hooks, `main` and git hook bypasses (deny, ask) |
| [`gate-self-merge`](#gate-self-merge) | PreToolUse: `Bash`, `if: Bash(gh pr merge:*)` | Merge only with `REVIEWED` and green checks (allow, ask) |
| [`openspec-autonomy`](#openspec-autonomy) | PreToolUse: `Bash` | Skip prompts for reversible commands in OpenSpec repos (allow, else no opinion) |
| [`protect-lint-config`](#protect-lint-config) | PreToolUse: `Edit\|Write\|MultiEdit` | Ask before lint, format or type-check config changes (ask) |
| [`autonomy-toggle`](#autonomy-toggle) | UserPromptSubmit | Flip the dial on "go less" and "go full" |
| [`claude-notify`](#claude-notify) | PermissionRequest, Notification: `idle_prompt` for Notification | Discord DM when a session needs you |
| [`session-context`](#session-context) | SessionStart | Inject last daily-log entry, active todos, HANDOFF |
| [`compact-reinject`](#compact-reinject) | SessionStart: `compact` | Re-inject a rules digest and HANDOFF after compaction |
| [`go-check`](#go-check) | PostToolUse (async): `Write\|Edit\|MultiEdit` | gofmt, vet and lint on the edited package; wakes Claude on failure |
| [`stop-gate`](#stop-gate) | Stop | Refuse to stop while the repo's fast check fails (block) |
| [`post-pr-create`](#post-pr-create) | PostToolUse: `Bash`, `if: Bash(gh pr create:*)` | Tell the session how the new PR gets reviewed |
| [`flip-todo-on-merge`](#flip-todo-on-merge) | PostToolUse: `Bash` | Tick the matching TODO.md line after a merge |

---

### `autonomy-gate`

Checks every Bash command and blocks pushes to `main`, git hook bypasses and tampering with the guards.

| When it runs | PreToolUse on every Bash call, no `if` filter |
|---|---|
| **Disable** | Remove the `autonomy-gate.sh` entry under `PreToolUse` > `Bash` |
| **Source** | [`autonomy-gate.sh`](../claude/hooks/autonomy-gate.sh), [`push-guard.py`](../claude/hooks/push-guard.py) |

<details>
<summary>Details and examples</summary>

**What it blocks**

| Action | Result |
|---|---|
| Write to `~/.claude/autonomy-level` | deny |
| Write to `~/.claude/hooks/` or this repo's `claude/hooks/` | ask |
| Push or merge to `main`/`master`, including `git update-ref` | deny at every level |
| Git hook bypass: `--no-verify` and its abbreviations, `commit -n`, `core.hooksPath` by any spelling, `SKIP=`/`HUSKY=` before a git command | deny at every level |
| Any push or merge while the dial is `less` | deny |
| Missing `jq` or `python3` | ask |

**How it reads commands**

- `push-guard.py` is the shared parser. It sees through refspecs, `-C`, `-c`, `bash -c`, `eval`, `$(...)`, aliases, quote splitting, line continuations and `gh api`.
- No `if` filter, so `git -C`, `cd && git push` and `VAR=1 git push` are all seen.
- The push normaliser only runs when `push`, `merge`, `api`, `graphql` or `update-ref` appears.
- Heredoc bodies that are data (`cat > f <<EOF`, `python3 - <<EOF`) are removed before matching (`push-guard.py --strip`).
- A body on a line that names a shell (`bash <<EOF`, `cat <<EOF | sh`) is still checked.
- The tamper guard inspects write targets (redirects, cp/mv/tee/sed -i operands and similar). Reading or mentioning those paths passes.
- A literal `$HOME/...` target is denied because it cannot be resolved statically.
- If `jq` cannot parse the input, the level file is unreadable or `push-guard.py` fails, it asks instead of passing.

**Examples**

- `echo x > ~/.claude/autonomy-level`: denied.
- `echo x > ~/.claude/hooks/a.sh`: prompts. `cat ~/.claude/hooks/a.sh`: passes.
- Dial at `less`: `git push origin feat` is denied.
- `git push origin HEAD:main` and `git commit --no-verify`: denied at both levels.
- `git commit -m "mention --no-verify"`: passes.

**Configure**

- The level lives in `~/.claude/autonomy-level`: `full` or `less`. Missing means `full`.
- The tamper guard applies at both levels.
- Repos that push straight to main by design: one absolute path per line in `~/.claude/hooks/push-main-allow.txt`.

</details>

### `gate-self-merge`

Lets `gh pr merge` through only when the PR has `REVIEWED` and every check is green.

| When it runs | PreToolUse on Bash, filtered to `gh pr merge` by the settings `if` |
|---|---|
| **Disable** | Remove the entry. Merges go back to the normal prompt |
| **Source** | [`gate-self-merge.sh`](../claude/hooks/gate-self-merge.sh) |

<details>
<summary>Details and examples</summary>

- Reads the PR's labels and the latest run of each check.
- Allows only when `REVIEWED` is present, there is at least one check, and none failed or are pending. Everything else asks.
- The script also exits early for other commands. It ignores `gh pr merge` that only appears inside a data heredoc body.
- It does not check the merge method. Squash comes from the review prompt and repo settings.
- No env vars. Needs `gh` and `jq`.

| Command | Result |
|---|---|
| `gh pr merge 12 -R owner/repo --squash` with `REVIEWED` and green checks | allow |
| Red check, no label, or no checks at all | ask |
| A second `gh pr merge` in the same command | ask |
| `cd` or `git -C` in the command | ask |
| A shell variable instead of a literal PR number | ask |

</details>

### `openspec-autonomy`

Skips the prompt for reversible commands inside OpenSpec repos.

| When it runs | PreToolUse on every Bash call; acts only when the dial is `full` |
|---|---|
| **Disable** | Remove the entry |
| **Source** | [`openspec-autonomy.sh`](../claude/hooks/openspec-autonomy.sh) |

<details>
<summary>Details and examples</summary>

Acts only in a repo that contains `openspec/config.yaml`. It allows a command with no prompt when every segment starts with an allowlisted verb:

| Tool | Allowed |
|---|---|
| git | `add`, `commit`, `rebase`, `fetch`, `pull`, `switch`, `checkout`, `branch`, `worktree`, `status`, `log`, `diff`, `show`, `stash`, `push` |
| gh | `pr create`, `pr view`, `pr edit`, `pr checks`, `pr list`, `pr comment`, `pr diff` |
| other | `openspec`, `npm test`/`ci`/`run test\|lint\|build\|typecheck`, `pytest`, `uv run pytest\|ruff`, `go test`/`vet`/`build`, `make test\|lint` |

Falls through to the normal prompt (no opinion) on:

- a pipe, `$(`, backtick or redirect
- `rm`, `sudo`, `ssh`, `git reset --hard`, `git clean`
- push to main or force push
- `gh api`, `gh release`, `npm publish`
- anything that touches settings or hooks
- a `cd` or `git -C` into a non-OpenSpec directory (other than `/tmp`)

Example: `git add -A && git commit -m "x"` in an OpenSpec repo is allowed.

**Configure:** reads `~/.claude/autonomy-level`. Edit the `allow` and `hard` regexes in the script to change the lists.

**Warning:** a cloned repo can add `openspec/config.yaml`. Only wire this hook if you keep the `permissions.deny` block from the settings example.

</details>

### `protect-lint-config`

Asks before an edit touches lint, format or type-check config, because agents disable rules to pass.

| When it runs | PreToolUse on `Edit\|Write\|MultiEdit` |
|---|---|
| **Disable** | Remove the `Edit\|Write\|MultiEdit` entry |
| **Source** | [`protect-lint-config.sh`](../claude/hooks/protect-lint-config.sh) |

<details>
<summary>Details and examples</summary>

- Plain config files always ask: `.eslintrc.json`, `eslint.config.*`, `.golangci.*`, `ruff.toml`, `.prettierrc*`, `biome.json`, `.markdownlint*`, `.pre-commit-config.yaml`, any `*baseline*.json`.
- `pyproject.toml` asks only when the change touches `[tool.ruff|mypy|pyright`.
- `tsconfig*.json` asks only when the change mentions a strictness key.
- Adding `"noImplicitAny": false` to `tsconfig.json` asks with "lint/type config change: fix the code instead, or confirm".
- Editing `src/app.ts` does not ask.
- No env vars. Add file names to `is_plain_config` to extend it.

</details>

### `autonomy-toggle`

Flips the autonomy dial when your whole prompt is "go less" or "go full".

| When it runs | UserPromptSubmit |
|---|---|
| **Disable** | Remove the `UserPromptSubmit` entry. The file can still be edited by hand |
| **Source** | [`autonomy-toggle.sh`](../claude/hooks/autonomy-toggle.sh) |

<details>
<summary>Details and examples</summary>

- Writes `less` or `full` to `~/.claude/autonomy-level`.
- Also accepts "go into less mode" and "go into full mode". Case-insensitive; a trailing `.` or `!` is ignored.
- `go less` blocks push and merge until you type `go full`.
- "go less strict on X" does nothing.
- Install writes `full` if the state file is missing.

</details>

### `claude-notify`

Sends you a Discord DM when a session needs approval or has gone idle.

| When it runs | PermissionRequest, and Notification with matcher `idle_prompt` |
|---|---|
| **Disable** | Remove both entries |
| **Source** | [`claude-notify.sh`](../claude/hooks/claude-notify.sh) |

<details>
<summary>Details and examples</summary>

- Sends through a Discord bot: the tool and a redacted command, or an idle notice.
- Secret-like strings in the message are redacted.
- Prints nothing on stdout, so it never decides a permission.
- One DM per session per 120 s.
- Example: `[WSL] Approval needed - owner/repo (a1b2c3d4)` followed by `Bash: gh pr merge 12 ...`.
- `claude-notify.sh --message "<text>"` sends one DM synchronously. `dnw-apply` uses it. Exit 1 if it could not be sent.
- Needs `python3` and `curl`.

| Env | Meaning |
|---|---|
| `CLAUDE_NOTIFY_ENV` | Env file path, default `~/.config/claude-notify/env`. It must set `DISCORD_BOT_TOKEN` and `DISCORD_OWNER_ID`; without it the hook logs and does nothing |
| `CLAUDE_NOTIFY_STATE` | State and log dir |
| `CLAUDE_NOTIFY_DEDUPE_SECS` | Dedupe window |
| `CLAUDE_NOTIFY_SYNC` | Send in the foreground |

</details>

### `session-context`

Loads your last daily-log entry, active todos and the repo's handoff note at session start.

| When it runs | SessionStart, every start |
|---|---|
| **Disable** | Remove the entry |
| **Source** | [`session-context.sh`](../claude/hooks/session-context.sh) |

<details>
<summary>Details and examples</summary>

- From `~/Github/personal-kb/`: the most recent daily-log day, the "in progress" todo section and the "current work" notes.
- From the repo: `.claude/HANDOFF.md` and live git state. Marked STALE when the handoff commit differs from HEAD.
- Falls back to a "read the files" instruction if slicing finds nothing.
- Skips the KB part if the folder is missing. Only the HANDOFF part then applies.
- Lines are clipped at 180 characters.
- The KB path is hard-coded. Edit `KB` in the script.
- Effect: a new session opens with context in place, so Claude asks about meetings and goals instead of reading three files.

</details>

### `compact-reinject`

Puts the rules digest and handoff note back into context after compaction.

| When it runs | SessionStart with matcher `compact` |
|---|---|
| **Disable** | Remove the `compact` entry |
| **Source** | [`compact-reinject.sh`](../claude/hooks/compact-reinject.sh) |

<details>
<summary>Details and examples</summary>

- Prints `~/.claude/compact-digest.md` and the first 30 lines of the repo's `.claude/HANDOFF.md`.
- Always exits 0. Missing files are skipped.
- After `/compact`, the digest of hard rules reappears in context.
- `COMPACT_DIGEST` overrides the digest path. Write the digest yourself.

</details>

### `go-check`

Runs gofmt, `go vet` and golangci-lint on the edited Go package in the background.

| When it runs | PostToolUse on `Write\|Edit\|MultiEdit`, async; exits at once for non-Go files |
|---|---|
| **Disable** | Remove the entry |
| **Source** | [`go-check.sh`](../claude/hooks/go-check.sh) |

<details>
<summary>Details and examples</summary>

- Finds the file's `go.mod`, then runs `gofmt -l` on the file and `go vet` on its package.
- Runs `golangci-lint run --new-from-rev=HEAD` if installed. 90 s lint timeout, 40-line clipping.
- Does not run `go test`. `stop-gate` does.
- Wired `async` with `asyncRewake`. Success is silent. A failure prints the report to stderr and exits 2, which wakes Claude with it as a system reminder.
- Editing `internal/store/db.go` checks `./internal/store` only. A vet error arrives a moment later without blocking the edit.
- No env vars. Needs `go` and `gofmt` on PATH (`/usr/local/go/bin` and `~/go/bin` are appended).

</details>

### `stop-gate`

Refuses to let Claude stop while the repo's fast check fails.

| When it runs | Stop |
|---|---|
| **Disable** | Remove the `Stop` entry |
| **Source** | [`stop-gate.sh`](../claude/hooks/stop-gate.sh) |

<details>
<summary>Details and examples</summary>

If the working tree has changes, it runs the check and blocks the stop with the failure output (40 lines).

**Which check** (first match wins)

1. `$CLAUDE_STOP_GATE_CMD`
2. The first line of `.claude/stop-gate`
3. Auto-detect: `go vet ./... && go test ./...`, `npm test --silent` or `pytest -q -x`, plus `openspec validate --strict --all` when `openspec/config.yaml` exists

**Lets the stop through when**

- the same failure repeats under `stop_hook_active` (with a message)
- not in git, the tree is clean, or no check is found
- the working tree (HEAD, `git diff HEAD`, untracked files and their checksums) matches the last passing run in the session, so question-only turns skip the check

A failing run is never remembered.

Example: Claude edits a Go file and tries to finish with a failing test. The stop is blocked with the `go test` output.

| Env | Meaning |
|---|---|
| `CLAUDE_STOP_GATE_CMD` | Check command; runs in any repo |
| `CLAUDE_STOP_GATE_TIMEOUT` | Seconds, default 120 |
| `CLAUDE_STOP_GATE_OWNERS` | Space-separated GitHub users or orgs |

Repo-defined checks (`.claude/stop-gate`, auto-detect) run only when `origin` is owned by one of those owners, so a cloned repo cannot run code. Keep the check fast.

</details>

### `post-pr-create`

Tells the session how its new PR gets reviewed and merged.

| When it runs | PostToolUse on Bash, filtered by the settings `if` to `gh pr create` |
|---|---|
| **Disable** | Remove its PostToolUse entry |
| **Source** | [`post-pr-create.sh`](../claude/hooks/post-pr-create.sh) |

<details>
<summary>Details and examples</summary>

**Repo has a workflow mentioning `claude-review`:**

- CI reviews and applies `REVIEWED`.
- Wait with `gh pr checks <N> --watch --interval 20`.
- Merge with `gh pr merge <N> --squash --delete-branch` only when labelled and green.
- Never add `REVIEWED` itself. A review block is a red check to fix.

**Otherwise:** spawn one `reviewer` agent with the diff, report findings, and leave `REVIEWED` and the merge to you.

- Always exits 0.
- The PR number comes from the `/pull/<N>` URL in the command output when present.
- See the [Claude review workflow](config.md#claude-review).
- It replaces the old inline hook that told the session to label its own PR.

</details>

### `flip-todo-on-merge`

Ticks the matching `TODO.md` line after a PR merges.

| When it runs | PostToolUse on Bash (second entry in the example); ignores other commands |
|---|---|
| **Disable** | Remove the second PostToolUse Bash entry |
| **Source** | [`claude/skills/backlog/flip-todo-on-merge.sh`](../claude/skills/backlog/flip-todo-on-merge.sh) |

<details>
<summary>Details and examples</summary>

- After `gh pr merge <N>`, flips the matching open `- [ ]` line in the repo's `TODO.md` to `- [x]`.
- `gh pr merge 154` ticks the TODO line that mentions PR 154.
- Supports `--dry-run`.
- Wiring notes: [`claude/skills/backlog/hook-install.md`](../claude/skills/backlog/hook-install.md).

</details>
