# Scripts

CLI scripts in `bin/` install to `~/.local/bin/`. Most are bash; `engraph-mcp-proxy` is Python. Repo scripts in `scripts/` and the installers run from the checkout. [Back to the catalogue](REFERENCE.md).

- [CLI scripts (bin/)](#cli-scripts-bin)
- [engraph helpers](#engraph--helpers)
- [Repo scripts (scripts/)](#repo-scripts-scripts)

---

## CLI scripts (bin/)

### `pstack-budget-statusline`

Shows model and plan usage in the statusline, and picks a model budget tier for new sessions.

| When it runs | Every statusline refresh (`statusLine` in settings) |
|---|---|
| **Disable** | Remove the `statusLine` entry |
| **Source** | [`bin/pstack-budget-statusline`](../bin/pstack-budget-statusline) |

<details>
<summary>Details and examples</summary>

- Prints model, 5-hour and 7-day plan usage: `Opus | 5h 42% | 7d 31% | pstack large`.
- Rewrites `~/.claude/rules/pstack-models.md` from the higher of the two: under 50% large, under 80% medium, else small.
- With no rate-limit data it prints `usage n/a` and leaves the rule alone.
- `PSTACK_RULE` overrides the rule path. Hand edits to that rule are overwritten.

</details>

### `safe-worktree-remove`

Removes a worktree only when nothing uses it. Never passes `--force`.

| When it runs | You or an agent run it after a PR merges |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/safe-worktree-remove`](../bin/safe-worktree-remove) |

<details>
<summary>Details and examples</summary>

Refuses:

- the main checkout, or a locked worktree
- dirty or untracked changes
- commits that are not pushed, not on the default branch and not in a merged PR
- any process whose cwd is inside it

`safe-worktree-remove ../repo-task --branch` removes the worktree and deletes its branch. Needs `/proc` or `lsof` for the in-use check.

</details>

### `repo-bootstrap`

Applies the fleet GitHub defaults to an existing repo, or sets up only the CI Claude review.

| When it runs | Once per repo, by hand |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/repo-bootstrap`](../bin/repo-bootstrap) |

<details>
<summary>Details and examples</summary>

**Default mode** (through `gh api`, idempotent):

- read-only Actions token, selected actions only, fork-PR approval
- squash-only merges with branch auto-delete
- secret scanning and push protection, private vulnerability reporting, Dependabot alerts
- the `REVIEWED` label and a `protect-main` ruleset

Example: `BOOTSTRAP_CHECKS="test (ubuntu-latest),gitleaks" repo-bootstrap owner/repo --public`.

| Flag or env | Meaning |
|---|---|
| `--dry-run` | Print the writes, make none |
| `--public` | Warn on self-hosted runners; in review mode, refuse them |
| `BOOTSTRAP_ACTIONS` | Allowed actions, default `astral-sh/setup-uv@*,gitleaks/gitleaks-action@*` |
| `BOOTSTRAP_CHECKS` | Required checks; without it the required-checks rule is skipped |

**Review mode** (`repo-bootstrap owner/repo --review`):

- Ensures the `REVIEWED` label exists.
- Merges the pinned `claude-code-action` and its nested `setup-bun` into a `selected` actions allowlist without dropping existing patterns.
- Opens a PR adding `.github/workflows/review.yml` if missing.
- Sets `CLAUDE_CODE_OAUTH_TOKEN` from the env via stdin, never echoed.
- Pins the caller to the full SHA of `BOOTSTRAP_REVIEW_SRC` HEAD (or `BOOTSTRAP_REVIEW_REF`; only a 40-hex result is accepted), with `tools-ref` set to the same SHA and a job-level fork guard.
- Private repos: `BOOTSTRAP_REVIEW_RUNS_ON` (label or JSON) wins. Unset or `auto` queries the repo's runners and picks the single `nuc-*` label, else `nuc`, else `ubuntu-latest` with a printed note.
- Public repos (or `--public`, or detected via `gh repo view`) always get `ubuntu-latest`.
- A `skip-changelog` label, if the repo has one, is applied to the caller PR.

**Update mode:** if the caller already exists on the default branch, or a `NO-TICKET-claude-review` PR is open, the new caller is rendered and compared.

- A difference opens `NO-TICKET-claude-review-harden` with a `[NO-TICKET] ci: harden Claude review caller (pin SHA, fork guard)` PR, or updates the open caller PR's branch and comments.
- Identical prints `ok`. Only `review.yml` is touched.

Tests: `tests/bootstrap_test.sh`, `tests/review_test.sh`. Walkthrough: [operations.md](operations.md#new-repo).

</details>

### `review-rollout`

Turns on the CI Claude review across many repos and prints a summary table.

| When it runs | By hand, when enabling the review on more repos |
|---|---|
| **Disable** | Per repo, delete its `.github/workflows/review.yml` |
| **Source** | [`bin/review-rollout`](../bin/review-rollout) |

<details>
<summary>Details and examples</summary>

- Runs `repo-bootstrap <repo> --review` on each repo, adding `--public` for public ones.
- Continues past failures, then prints a repo / label / allowlist / caller / secret table.
- `CLAUDE_CODE_OAUTH_TOKEN=... review-rollout owner/a owner/b`.
- Same env as `repo-bootstrap --review`.
- Re-running over repos with an existing caller opens or refreshes hardening PRs.

</details>

### `dnw-doctor`

Read-only check of the live install against the repo. Every problem comes with a `fix:` line.

| When it runs | By hand after pulling |
|---|---|
| **Disable** | Don't call it. It never edits settings |
| **Source** | [`bin/dnw-doctor`](../bin/dnw-doctor), mapping shared with `install.sh` via [`scripts/install-manifest.sh`](../scripts/install-manifest.sh) |

<details>
<summary>Details and examples</summary>

Checks:

- missing or stale installed files
- hooks from `settings.example.json` not wired into `~/.claude/settings.json`
- missing `statusLine` or deny rules
- git identity, the shell rc source line, tools on PATH
- the overlay: ignored non-overlayable files, shadowed repo files that changed since seeding, missing provenance (see [Personal overlay](install.md#personal-overlay))

Output: `ok installed 43 files match the repo and overlay`, or `warn settings hook missing under PreToolUse: ...` with its fix.

| Flag | Meaning |
|---|---|
| `--json` | Machine output |
| `--repo DIR` | Check another checkout |

Exit 1 on any `fail`.

</details>

### `dnw-apply`

Installs merged main onto this machine, and alerts you when a guard hook changed.

| When it runs | Claude runs it after do-no-work merges to main; you can too |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/dnw-apply`](../bin/dnw-apply) |

<details>
<summary>Details and examples</summary>

1. Refuses (exit 2) unless the checkout is clean, on the default branch, and fast-forwards to `origin/<default>`. So only code that passed CI and review is installed.
2. Seeds the overlay once from the newest `~/.dotfiles-backup/*`, only if no overlay exists.
3. Runs `install.sh --no-deps`, with `--copy` if `~/.claude/hooks/autonomy-gate.sh` is a regular file.
4. Runs `dnw-doctor`.
5. Records HEAD in `${XDG_STATE_HOME:-~/.local/state}/do-no-work/applied`.

Output: `applied 1a2b3c4..5d6e7f8, 3 files changed, overlay seeded no, guard change no, doctor 0 fail / 1 warn`.

**Guard alert.** If `autonomy-gate.sh`, `autonomy-toggle.sh`, `gate-self-merge.sh`, `openspec-autonomy.sh`, `push-guard.py` or `settings.example.json` changed since the last applied commit:

- it appends `<ISO time> <old>..<new> <files>` to `audit.log` in the same state dir
- it DMs you `do-no-work applied <old>..<new>: guard hooks changed: <files>. Audit: <path>` through `claude-notify.sh --message`
- a failed DM only warns
- the first run on a machine has no recorded commit, so it never alerts

Exit is doctor's code: 0 ok, 1 fails.

| Flag or env | Meaning |
|---|---|
| `--repo DIR` | Checkout to apply; default is the one the script resolves to |
| `--dry-run` | Checks and plan only; fetches but does not fast-forward or write |
| `DOTFILES_SKIP_UPSTREAM` | Defaults to 1 here |

Needs the `claude-notify` env file for DMs. Test: `tests/apply_test.sh`.

</details>

### `ci-wait`

Blocks until a PR's checks finish, and exits 1 on any failure.

| When it runs | You or an agent run it after a push |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/ci-wait`](../bin/ci-wait) |

<details>
<summary>Details and examples</summary>

- Polls and prints each result: `ci-wait 42 -R owner/repo` prints `test (ubuntu-latest): success` and so on.
- Exit 0 only if all passed (success, skipped, neutral). Exit 1 on failure, timeout or no checks. Exit 2 on bad usage.

| Env | Default |
|---|---|
| `CI_WAIT_TIMEOUT` | 1200 s |
| `CI_WAIT_INTERVAL` | 15 s |
| `CI_WAIT_EMPTY_GRACE` | 60 s of waiting for checks to appear |

Test: `tests/ci_wait_test.sh`.

</details>

### `fleet`

Lists open PRs across many repos with checks, `REVIEWED` and merge state.

| When it runs | You or an agent run it after a fan-out |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/fleet`](../bin/fleet) |

<details>
<summary>Details and examples</summary>

| Subcommand | Does |
|---|---|
| `prs` | Table of open PRs: checks pass/fail/pending, REVIEWED, merge state, ready? |
| `watch` | Polls until no check is pending, then prints the table and the first `##[error]` line of each failing check. Exit 0 all ready, 1 not all ready, 2 timeout |
| `ready` | Prints only ready PRs as `owner/repo#N` |

- There is no merge subcommand. Merge one PR per `gh` call, so the merge gate checks each.
- Typical use: `fleet watch --head 'NO-TICKET-*'`, then `fleet ready`.
- Filters: `--author`, `--label`, `--head <glob>`. `--json` on `prs` and `watch`.
- Repo list: `--repos owner/a,owner/b`, else `FLEET_FILE` (default `~/.config/do-no-work/fleet.txt`, one `owner/repo` per line, `#` comments). Format in [`examples/fleet.txt`](../examples/fleet.txt).
- `--timeout` (1500 s), `--interval` (30 s).
- Test: `tests/fleet_test.sh`.

</details>

### `callrec`

Starts and stops an OBS recording from WSL, then transcribes it.

| When it runs | `callrec start`, `callrec stop [--no-transcribe]`, `callrec status` |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/callrec`](../bin/callrec), [`lib/obsws.ps1`](../lib/obsws.ps1) |

<details>
<summary>Details and examples</summary>

- Records mic and desktop audio over obs-websocket, then runs `transcribe` on the file.
- `callrec start` before a call, `callrec stop` after. The transcript lands next to the recording.
- Windows and WSL only. Needs OBS with the websocket server on port 4455. Uses `lib/obsws.ps1`.
- Password from `OBS_WS_PASSWORD`, OBS's own config, or `pass`.
- Other env: `CALLREC_OBS_DIR`, `CALLREC_REC_DIR`, `CALLREC_OBS_WS_CONFIG`, `CALLREC_SETTLE_SECS`.

</details>

### `transcribe`

Wraps the local Parakeet CPU transcriber.

| When it runs | By hand, or from the `call` skill |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/transcribe`](../bin/transcribe) |

<details>
<summary>Details and examples</summary>

- Runs `uv run --project ~/parakeet python ~/parakeet/transcribe.py "$@"`.
- `transcribe --last` or `transcribe recording.mkv`.
- The Parakeet install at `~/parakeet` is not automated and not in this repo.

</details>

### `pasteimg`

Saves the Windows clipboard image to a file and prints its WSL path, so Claude Code can read it.

| When it runs | After a Win+Shift+S snip |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/pasteimg`](../bin/pasteimg) |

<details>
<summary>Details and examples</summary>

- `pasteimg` prints `.../Pictures/Screenshots/clip.png`. Mention that path in the prompt.
- `PASTEIMG_OUT` sets the output file. `WIN_HOME` overrides the Windows home.
- WSL only.

</details>

### `chrome-devtools-mcp-gated`

Starts the real Chrome DevTools MCP only in your UI repos, and a no-tool stub elsewhere, to save memory.

| When it runs | As the MCP server command in your MCP config |
|---|---|
| **Disable** | Point your MCP config at `chrome-devtools-mcp` directly, or remove it |
| **Source** | [`bin/chrome-devtools-mcp-gated`](../bin/chrome-devtools-mcp-gated) |

<details>
<summary>Details and examples</summary>

- Runs `chrome-devtools-mcp` headless and isolated when the working directory matches your UI repo glob.
- In `~/Github/site-ui` it starts Chrome. In any other repo it answers `initialize` and `tools/list` with nothing.
- `CHROME_MCP_REPO_GLOB`: a `case` pattern, default `$HOME/Github/*-ui*`.
- `CHROME_BIN`: Chrome binary.

</details>

---

## `engraph-*` helpers

Helpers for the engraph knowledge-graph MCP server, over a vault of hardlinked markdown (`memory` and `personal-kb`). Skip them if you do not run engraph.

### `engraph-enqueue`

Queues vault files for reindexing and returns at once.

| When it runs | After you edit a memory or personal-kb note |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/engraph-enqueue`](../bin/engraph-enqueue) |

<details>
<summary>Details and examples</summary>

- `engraph-enqueue ~/Github/personal-kb/notes.md` prints `queued: personal-kb/notes.md`.
- Accepts only `.md` files under memory, personal-kb or the vault.
- `ENGRAPH_QUEUE_DIR` sets the queue dir.

</details>

### `engraph-reindex-drain`

Drains the reindex queue into the engraph server.

| When it runs | From a systemd path unit when the queue changes |
|---|---|
| **Disable** | Disable the path unit |
| **Source** | [`bin/engraph-reindex-drain`](../bin/engraph-reindex-drain) |

<details>
<summary>Details and examples</summary>

- Dedupes, syncs the vault to the index host, and calls MCP `reindex_file` once per file.
- Retries three times, then writes `reindex.failed`. Read that file for leftovers.

| Env | Default or meaning |
|---|---|
| `ENGRAPH_MCP_URL` | Server URL |
| `ENGRAPH_CALL_TIMEOUT` | 900 |
| `ENGRAPH_MAX_BYTES` | 30000 |
| `ENGRAPH_SYNC_CMD` | Copies the vault to a remote index host |

</details>

### `engraph-relink`

Rebuilds the combined vault as hardlinks of the source markdown.

| When it runs | After files are added or deleted; also called by the refresh scripts |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/engraph-relink`](../bin/engraph-relink) |

<details>
<summary>Details and examples</summary>

- Hardlinks `*.md` from the memory and personal-kb sources, skipping archives and `output/`.
- Prints `relinked N markdown files into ~/engraph-vault`.
- Source roots are set in the script.

</details>

### `engraph-refresh`

Relinks and fully rebuilds the engraph index.

| When it runs | By hand, with no Claude session using the engraph MCP |
|---|---|
| **Disable** | Don't call it |
| **Source** | [`bin/engraph-refresh`](../bin/engraph-refresh) |

<details>
<summary>Details and examples</summary>

- Runs relink, then `engraph index --rebuild` and `engraph status`.
- Refuses while `engraph serve` holds the database lock.
- Use it after renames or deletes. For one changed note use `engraph-enqueue` instead.

</details>

### `engraph-nightly-index`

Nightly reindex with a server restart and a count check.

| When it runs | From a nightly systemd timer |
|---|---|
| **Disable** | Disable the timer |
| **Source** | [`bin/engraph-nightly-index`](../bin/engraph-nightly-index) |

<details>
<summary>Details and examples</summary>

- Stops `engraph-mcp`, relinks, runs `engraph index`, restarts the server.
- Warns when the indexed count differs from the file count by more than one.
- Logs `indexed=312 fs=312 diff=0 secs=41` to the journal.
- Needs systemd user units named `engraph-mcp`.

</details>

### `engraph-mcp-watchdog`

Health check that restarts `engraph-mcp` when it stops answering.

| When it runs | From a systemd timer |
|---|---|
| **Disable** | Disable the timer |
| **Source** | [`bin/engraph-mcp-watchdog`](../bin/engraph-mcp-watchdog) |

<details>
<summary>Details and examples</summary>

- Checks the process tree, then a real MCP `initialize` and `tools/list` on `127.0.0.1:8765`.
- Restarts the service on failure. Does nothing if the service was stopped on purpose.
- Journal line: `UNHEALTHY: initialize failed -- restarting engraph-mcp`.
- The port is fixed in the script.

</details>

### `engraph-mcp-proxy`

Runs `mcp-proxy` behind a Host and Origin allowlist.

| When it runs | As the service command, using mcp-proxy's own Python |
|---|---|
| **Disable** | Run `mcp-proxy` directly |
| **Source** | [`bin/engraph-mcp-proxy`](../bin/engraph-mcp-proxy) |

<details>
<summary>Details and examples</summary>

- Allows localhost:8765 only, to block DNS rebinding and cross-origin browser requests. Others get 403.
- A request with `Host: evil.example` gets `403 forbidden host or origin`.
- Edit `HOSTS` and `ORIGINS` in the script.

</details>

---

## Repo scripts (scripts/)

### `claude-review-verdict.sh`

Turns the review's verdict into a PR comment, and the `REVIEWED` label only on a PASS.

| When it runs | Last step of the [`claude-review` workflow](config.md#claude-review); loaded from `main`, never from the PR |
|---|---|
| **Disable** | Part of the workflow; disable the workflow |
| **Source** | [`scripts/claude-review-verdict.sh`](../scripts/claude-review-verdict.sh) |

<details>
<summary>Details and examples</summary>

- Reads the review action's structured output.
- Labels only on `PASS` for the commit that was reviewed.
- Fails closed on a missing or unparseable verdict, a `BLOCK`, or a head commit that moved.
- `PASS` at the expected sha adds the label. `BLOCK` posts the comment and exits 1.
- Env: `REPO`, `PR`, `EXPECTED_SHA`, `STRUCTURED_OUTPUT`. `GH` overrides the gh binary for tests.
- Test: `tests/claude_review_verdict_test.sh`.

</details>

### `public-safety-check.sh`

Fails if a tracked file contains personal data.

| When it runs | Pre-commit hook and CI |
|---|---|
| **Disable** | Mark one line with `public-safety: allow` and a reason |
| **Source** | [`scripts/public-safety-check.sh`](../scripts/public-safety-check.sh) |

<details>
<summary>Details and examples</summary>

- Prints `public-safety: ok (N files)` or `file:line: [builtin] ...`.
- Output names file, line and source but never prints a private pattern.
- Sources, private list setup and the CI secret: see [Keeping it public-safe](operations.md#keeping-it-public-safe).
- Test: `tests/public_safety_test.sh`.

</details>

### `changelog.sh` and `changelog.d/`

Changelog fragments, so parallel PRs never conflict on `CHANGELOG.md`.

| When it runs | `check` in CI; `next` when you start a PR; `compile` at release |
|---|---|
| **Disable** | Not optional; CI runs `check` |
| **Source** | [`scripts/changelog.sh`](../scripts/changelog.sh), [`changelog.d/README.md`](../changelog.d/README.md) |

<details>
<summary>Details and examples</summary>

Each PR adds `changelog.d/<type-N>.md` holding one line, with no ID. Types: `feat`, `fix`, `docs`, `chore`.

| Subcommand | Does |
|---|---|
| `next <type>` | Prints the next free ID: `scripts/changelog.sh next docs` prints `docs-3` |
| `check` | Validates names, one-line content, duplicates, and IDs already in the changelog |
| `compile [--version vX.Y.Z]` | Folds fragments into `CHANGELOG.md` and removes them; `--version v1.0.0` adds a `## v1.0.0 - <date>` block |

- `TRASH_DIR` sets where uncommitted fragments go after compile.
- Test: `tests/changelog_test.sh`.

</details>

### `install.sh`

Installer for macOS, Linux and WSL.

| When it runs | By hand, once and after pulls |
|---|---|
| **Disable** | Don't run it |
| **Source** | [`install.sh`](../install.sh) |

<details>
<summary>Details and examples</summary>

- Places `home/` config, `bin/` scripts and `claude/` hooks, commands, agents and skills. Symlinks by default.
- Creates `~/.claude/autonomy-level` as `full` if missing.
- Copies `CLAUDE.md.example` to `~/CLAUDE.md` if you have none.
- Installs packages, then upstream skills.
- Never edits `settings.json`.
- Anything that differs is moved to `~/.dotfiles-backup/<timestamp>/` first. Reruns leave identical files alone.
- Example: `./install.sh --copy --no-deps`.

| Flag or env | Meaning |
|---|---|
| `--copy` | Copy instead of symlink |
| `--no-deps` | Skip packages |
| `--seed-overlay`, `--seed-overlay-from DIR`, `--record-overlay` | See [Personal overlay](install.md#personal-overlay) |
| `GIT_NAME`, `GIT_EMAIL` | Needed for non-interactive installs |
| `DOTFILES_SKIP_UPSTREAM=1` | Skip upstream skill installs |

Test: `tests/install_test.sh`. Walkthrough: [install.md](install.md).

</details>

### `install.ps1`

Windows installer.

| When it runs | By hand from PowerShell |
|---|---|
| **Disable** | Don't run it |
| **Source** | [`install.ps1`](../install.ps1) |

<details>
<summary>Details and examples</summary>

- Installs packages with winget, unless `-NoDeps`.
- Finds Git Bash and runs `install.sh --copy --no-deps` through it. Files are copied, not symlinked.
- Adds oh-my-posh to the PowerShell profile.
- Example: `powershell -ExecutionPolicy Bypass -File .\install.ps1`.
- The `windows` CI job runs it into a throwaway home.

</details>
