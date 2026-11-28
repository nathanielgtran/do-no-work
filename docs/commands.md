# Slash commands

Slash commands install to `~/.claude/commands/`. They are prompts, not scripts, so edit the markdown to change them. Delete a file to remove its command. [Back to the catalogue](REFERENCE.md).

`/deploy`, `/hc` and `/rollback` expect `HOMESERVER=user@host`.

---

### `/log`

Syncs logs, plans and handoff notes at the end of a session, then pushes personal-kb.

| When it runs | You type `/log` after finishing work |
|---|---|
| **Disable** | Delete the file |
| **Source** | [`claude/commands/log.md`](../claude/commands/log.md) |

<details>
<summary>Details and examples</summary>

- Updates the daily log, notes, todo, `PLAN.md` current state, CHANGELOG, repo CLAUDE.md and memory.
- Writes a gitignored per-worktree `.claude/HANDOFF.md`: 25 lines, with the HEAD sha.
- Commits and pushes personal-kb. Assumes `~/Github/personal-kb`.
- `/log` after merging a PR adds the PR to today's daily-log and moves the todo to completed.
- The repo template says PRs add a `changelog.d/` fragment instead of editing `CHANGELOG.md`. Adjust step 6 if you use fragments.

</details>

### `/prune`

Shrinks the context loaded at startup.

| When it runs | You type `/prune` every few sessions |
|---|---|
| **Disable** | Delete the file |
| **Source** | [`claude/commands/prune.md`](../claude/commands/prune.md) |

<details>
<summary>Details and examples</summary>

- 3-day rolling daily-log: older entries are archived.
- Completed todos move to an archive.
- One-line notes per project.
- Done phases leave `PLAN.md`; stale references leave CLAUDE.md.
- It commits and pushes. Edit the rules in the file.

</details>

### `/test`

Detects the repo's stack and runs its tests.

| When it runs | `/test [package-or-path]` |
|---|---|
| **Disable** | Delete the file |
| **Source** | [`claude/commands/test.md`](../claude/commands/test.md) |

<details>
<summary>Details and examples</summary>

- Detects Go, Node, Python or Rust from the repo root.
- Also runs `go vet`, `golangci-lint` and `cargo clippy` where they apply, then summarises.
- `/test internal/store` runs `go test ./internal/store/...`.
- Edit the file for other stacks.

</details>

### `/review-pr`

Reviews a PR and prints a severity table. It does not apply a label.

| When it runs | `/review-pr [number]`; defaults to the current branch's PR |
|---|---|
| **Disable** | Delete the file |
| **Source** | [`claude/commands/review-pr.md`](../claude/commands/review-pr.md) |

<details>
<summary>Details and examples</summary>

- Reads `gh pr view` and `gh pr diff`.
- Reviews for bugs, security, tests, code quality and CLAUDE.md compliance.
- `/review-pr 42` returns `LGTM`, `Minor Issues` or `Needs Changes` with a table.
- Edit the rubric in the file.
- For a review that applies a label, use the [CI workflow](config.md#claude-review) or the [`reviewer` agent](skills.md#reviewer).

</details>

### `/deploy`

Tags a release, watches the release workflow and checks the service is healthy.

| When it runs | `/deploy [service] [version]`; version defaults to the next patch |
|---|---|
| **Disable** | Delete the file |
| **Source** | [`claude/commands/deploy.md`](../claude/commands/deploy.md) |

<details>
<summary>Details and examples</summary>

1. Confirms service and version.
2. Checks `main` is current and tests pass.
3. Tags and creates a GitHub release.
4. Watches the release workflow.
5. Checks the container and health endpoint over SSH.

- `/deploy myservice` tags the next patch version and watches `release.yml`.
- Needs `HOMESERVER=user@host`.
- The `gh release` step is a release. Run it only where releases are yours to cut.

</details>

### `/hc`

Health check of the home server over SSH.

| When it runs | `/hc` |
|---|---|
| **Disable** | Delete the file |
| **Source** | [`claude/commands/hc.md`](../claude/commands/hc.md) |

<details>
<summary>Details and examples</summary>

- Checks ping, uptime, disk, memory, docker containers and stats.
- Prints an HTTP status for each URL in `HC_URLS`.
- `HC_URLS="https://a.example https://b.example"` then `/hc` prints a status table and flags unhealthy items.
- Needs `HOMESERVER=user@host`; `HC_URLS` is optional.

</details>

### `/rollback`

Puts a service back on its previous image.

| When it runs | `/rollback <service>` |
|---|---|
| **Disable** | Delete the file |
| **Source** | [`claude/commands/rollback.md`](../claude/commands/rollback.md) |

<details>
<summary>Details and examples</summary>

- Stops the service on the server, retags its `:previous` image as `:latest`, brings it back up and curls a health URL.
- `/rollback myservice` expects `~/myservice/docker-compose.yml` on the host, with a `:previous` tag pushed by the release workflow.
- Needs `HOMESERVER`. `HEALTH_URL` overrides `http://localhost:8000/health`.

</details>
