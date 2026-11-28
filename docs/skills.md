# Skills and agents

Skills install to `~/.claude/skills/<name>/`. Delete a skill folder to remove it. Upstream skills listed in `skills-upstream.txt` install separately; see [`skills-upstream.txt`](config.md#skills-upstreamtxt) for those and the plugin list. [Back to the catalogue](REFERENCE.md).

---

## Skills

### `autobuild`

Hands-off feature loop for an OpenSpec repo: it scouts, builds up to three features and merges them one at a time.

| When it runs | Say "autobuild", "keep building features" or "scout and build" |
|---|---|
| **Disable** | Delete the skill folder |
| **Source** | [`claude/skills/autobuild/SKILL.md`](../claude/skills/autobuild/SKILL.md) |

<details>
<summary>Details and examples</summary>

1. Scout the repo.
2. Pick up to three features.
3. Cut worktrees from `origin/main` with pre-assigned IDs.
4. Build in parallel agents.
5. Review each PR itself, then wait for CI.
6. Label, then merge, in separate calls. Rebase the next PR.
7. Verify live, then log.

- In an OpenSpec repo, "autobuild, go" picks three features, opens three PRs and merges them one at a time.
- Stops without `openspec/config.yaml`.
- Builds only up to open PRs when the dial is `less`.
- Stops at once if you reject a tool call.
- Reads `REPOS.md`, `TODO.md`, `PLAN.md`. The model comes from `~/.claude/rules/pstack-models.md`.
- See the [diagram](../README.md#autobuild-hands-off-feature-loop).

</details>

### `backlog`

Rebuilds `personal-kb/backlog.md`, one read-only list of open TODOs and issues across repos.

| When it runs | "what's open", "backlog", or `python3 ~/.claude/skills/backlog/generate.py` |
|---|---|
| **Disable** | Delete the skill folder |
| **Source** | [`SKILL.md`](../claude/skills/backlog/SKILL.md), [`generate.py`](../claude/skills/backlog/generate.py) |

<details>
<summary>Details and examples</summary>

- Collects every real repo's open `- [ ]` TODO lines plus open GitHub issues, grouped by urgency. Worktrees are skipped.
- `python3 ~/.claude/skills/backlog/generate.py --no-gh` rebuilds offline; `--no-gh` skips issue calls.
- Never hand-edit the output. Edit the repo's `TODO.md`.
- Tests: `test_generate.py`. CI runs it with `uvx pytest`.
- The merge hook that ticks TODOs is in [`hook-install.md`](../claude/skills/backlog/hook-install.md). See [`flip-todo-on-merge`](hooks.md#flip-todo-on-merge).

</details>

### `call`

Transcribes the newest call recording on your machine and summarises it.

| When it runs | "transcribe the last call", `/call`, or a path to a recording |
|---|---|
| **Disable** | Delete the skill folder |
| **Source** | [`claude/skills/call/SKILL.md`](../claude/skills/call/SKILL.md) |

<details>
<summary>Details and examples</summary>

- Runs `transcribe --last` (Parakeet on CPU) and reads the `[mm:ss]` transcript.
- Summarises key points, action items and open questions, with timestamps, then offers to file it.
- Audio never leaves the machine.
- Needs the Parakeet install `transcribe` expects (not automated) and `callrec` or OBS recordings.
- Edit the filing path (personal-kb) in the skill.

</details>

### `tighten`

Cleanup that fixes what it reviews, for a PR or a single file.

| When it runs | `/tighten [PR# \| path] [--again] [--dry] [--tier N]`; model invocation is disabled |
|---|---|
| **Disable** | Delete the skill folder |
| **Source** | [`claude/skills/tighten/SKILL.md`](../claude/skills/tighten/SKILL.md) |

<details>
<summary>Details and examples</summary>

**PR mode**

1. Checks the PR out into a detached worktree.
2. Sizes the diff into a tier.
3. Runs one reviewer against `rubric.md`.
4. Applies bounded fixes: net-negative lines or correctness.
5. Verifies with lint and tests, then pushes.
6. Strips `REVIEWED`, adds a `tightened` label and posts one comment.

**File mode** tightens one prose or code file without losing facts.

- `/tighten 42 --dry` reports what it would change without editing.
- Refuses merged PRs, forks and unpushed commits.
- Wiring into the PR hook is manual: see [`HOOK-INSTALL.md`](../claude/skills/tighten/HOOK-INSTALL.md).
- Tests under `claude/skills/tighten/tests/` run in CI on Linux.

</details>

### `wanderlog`

CLI (`wl.py`) for Wanderlog's internal JSON API.

| When it runs | "my Wanderlog", or `python3 ~/.claude/skills/wanderlog/wl.py <cmd>` |
|---|---|
| **Disable** | Delete the skill folder |
| **Source** | [`claude/skills/wanderlog/SKILL.md`](../claude/skills/wanderlog/SKILL.md) |

<details>
<summary>Details and examples</summary>

- Lists trips, exports a trip to markdown, archives all trips, creates trips, adds places and notes, or makes a raw call.
- Commands: `trips`, `export`, `places`, `archive`, `trip-create`, `place-add`, `note-add`, `refresh`, `raw`.
- Typical use: `wl.py trips`, then `wl.py export <key>`.
- Auth is a `connect.sid` cookie cached at `~/.config/wanderlog/session`, refreshed with credentials from `pass personal/wanderlog`.
- `archive` writes under `~/Github/personal-kb/travel/wanderlog` by default; `--out` overrides.
- Tests: `test_wl.py`.

</details>

---

## Agents

### `reviewer`

Read-only review subagent that ends with `VERDICT: PASS` or `VERDICT: BLOCK`.

| When it runs | The parent delegates to it after a change, passing the diff or paths |
|---|---|
| **Disable** | Delete `~/.claude/agents/reviewer.md` |
| **Source** | [`claude/agents/reviewer.md`](../claude/agents/reviewer.md) |

<details>
<summary>Details and examples</summary>

- Tools: Read, Grep, Glob. Model: sonnet. It cannot run commands or edit.
- Loads the repo CLAUDE.md and any matching `openspec/changes/<id>/`.
- Reports real bugs, security issues, missing tests and clear rule violations, each with `file:line` and a failing scenario.
- "Use the reviewer agent on `git diff origin/main`" returns findings and a verdict line.
- Edit `tools` or `model` in the front matter.

</details>
