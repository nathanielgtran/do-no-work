# Config and CI

Settings templates, CI workflows and other repo files. [Back to the catalogue](REFERENCE.md).

- [CI workflows](#ci-workflows)
- [Settings and templates](#settings-and-templates)
- [Other files](#other-files)

---

## CI workflows

### `ci`

Runs the tests, checks and installs on every PR.

| When it runs | Pull requests and pushes to `main` |
|---|---|
| **Disable** | Not optional |
| **Source** | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) |

<details>
<summary>Details and examples</summary>

- Shell syntax check.
- `tests/run-all.sh` on Ubuntu and macOS: every `tests/*_test.sh`, plus the wanderlog, backlog and tighten suites.
- Changelog fragment check and the public-safety check.
- A Windows install into a throwaway home, and gitleaks.
- Pinned action SHAs, read-only token.
- Add `tests/<x>_test.sh` and CI runs it with no workflow edit. `tests/ci_discovery_test.sh` fails if `ci.yml` lists individual tests.
- Secret `PUBLIC_SAFETY_DENY_LIST` is optional. Required checks come from `repo-bootstrap` (`BOOTSTRAP_CHECKS`).

</details>

### `claude-review`

Reusable workflow: Claude reviews the PR read-only, and `REVIEWED` is applied only on a PASS.

| When it runs | Called on `pull_request` opened, synchronize, reopened, ready_for_review |
|---|---|
| **Disable** | Delete the caller (`.github/workflows/review.yml`) in that repo |
| **Source** | [`.github/workflows/claude-review.yml`](../.github/workflows/claude-review.yml) |

<details>
<summary>Details and examples</summary>

1. Removes `REVIEWED` if present.
2. Skips forks and drafts (no secrets on forks).
3. Checks out the PR head, and a trusted copy of the verdict script from `tools-ref`.
4. Claude reviews the diff read-only: Read, Grep, Glob, `git diff`, `git log`. Max 20 turns.
5. Posts the findings as a comment.
6. Applies `REVIEWED` only on a `PASS` for that commit.

- The verdict is read from the action's `structured_output` by [`claude-review-verdict.sh`](scripts.md#claude-review-verdictsh), always loaded from `tools-ref` (a pinned SHA in callers), not the PR.
- A push after review removes the label and re-reviews.
- A `BLOCK`, a missing or unparseable verdict, or a head that moved mid-review fails the job with no label.

| Setting | Meaning |
|---|---|
| Secret `CLAUDE_CODE_OAUTH_TOKEN` | From `claude setup-token` |
| Input `runs-on` | JSON, default `"ubuntu-latest"`; keep it for public repos |
| Inputs `model`, `max-turns`, `tools-ref` | Model, turn cap, trusted ref for the verdict script |

If the repo restricts allowed actions, allow `anthropics/claude-code-action@*`. Enabling it in a repo: [operations.md](operations.md#claude-review).

</details>

### `review`

This repo's own caller of `claude-review`.

| When it runs | Same PR events |
|---|---|
| **Disable** | Delete the file to stop self-review |
| **Source** | [`.github/workflows/review.yml`](../.github/workflows/review.yml) |

<details>
<summary>Details and examples</summary>

- `uses: ./.github/workflows/claude-review.yml`, so no pin is needed. Job-level fork guard.
- Every PR here gets the review and label automatically.

</details>

### `claude-review-caller.yml` (example)

Template to copy into another repo as `.github/workflows/review.yml`.

| When it runs | Not run here; it is a template |
|---|---|
| **Disable** | Not installed |
| **Source** | [`examples/claude-review-caller.yml`](../examples/claude-review-caller.yml) |

<details>
<summary>Details and examples</summary>

- Calls this repo's reusable workflow pinned at `@<40-hex SHA>`, with `tools-ref` set to the same SHA.
- Placeholders `__SHA__`, `__SHORT__`, `__RUNS_ON__` are filled by `repo-bootstrap --review`.
- Job-level fork guard, `contents: read` and `pull-requests: write`.
- Setup: create a `REVIEWED` label, set the secret, run `repo-bootstrap owner/repo --review`.
- Private repos pass `runs-on` as their repo-specific runner, for example `'["self-hosted","nuc-myrepo"]'`. Public repos drop the line.

</details>

---

## Settings and templates

### `settings.example.json`

The wiring for every hook, plus permissions, statusline, sandbox and auto mode examples.

| When it runs | Not installed. Merge `hooks`, `permissions` and `statusLine` into `~/.claude/settings.json` by hand |
|---|---|
| **Disable** | Remove any hook entry to disable that hook |
| **Source** | [`claude/settings.example.json`](../claude/settings.example.json) |

<details>
<summary>Details and examples</summary>

| Section | Holds |
|---|---|
| `permissions.deny` | rm, sudo, push to main or master, force push, `--admin` merge, edits to settings and the dial |
| `permissions.ask` | Edits to hooks |
| `hooks` | All [hooks](hooks.md). `autonomy-gate` and `gate-self-merge` carry `onFailure: block`, so a crashed guard blocks the call. `go-check` is `async` + `asyncRewake` |
| `statusLine` | [`pstack-budget-statusline`](scripts.md#pstack-budget-statusline) |
| `sandbox` | OS sandbox with `denyRead` for `~/.password-store`, `~/.gnupg`, `~/.ssh`, and a strict network allowlist |
| `autoMode.environment` | Starts with `$defaults` plus your own lines (user settings only) |

- Replace the placeholder registry domain and `homeserver.local`.
- Keep the deny block if you wire `openspec-autonomy`.
- For large directories such as `node_modules`, set `worktree.symlinkDirectories` here rather than copying them with `.worktreeinclude`.

</details>

### `CLAUDE.md.example`

Global instructions template, copied to `~/CLAUDE.md` if you have none.

| When it runs | Loaded by Claude Code every session |
|---|---|
| **Disable** | Edit or delete `~/CLAUDE.md` |
| **Source** | [`claude/CLAUDE.md.example`](../claude/CLAUDE.md.example) |

<details>
<summary>Details and examples</summary>

- Covers hard rules, worktree rules, code and PR rules (no hacks, comments default to none, fleet PR template, changelog fragments), agent use, autonomy, workflows and UI/UX rules.
- Fill in `<NAME>` and `<ROLE>`.
- The rule "never push to main" is repeated as a deny rule, so it does not depend on the prompt.
- Edit freely. Shrink prose once a rule is enforced by a hook or check.

</details>

### `.worktreeinclude.example`

Copies small gitignored files such as `.env` into new worktrees.

| When it runs | On worktree creation |
|---|---|
| **Disable** | Don't copy it to `.worktreeinclude` |
| **Source** | [`.worktreeinclude.example`](../.worktreeinclude.example) |

<details>
<summary>Details and examples</summary>

- Copy to `.worktreeinclude` so `.env`, `.env.local` and `config/*.local.*` are copied into worktrees Claude Code creates.
- A new worktree then starts with a working `.env`.
- It copies, it does not link. For `node_modules` set `worktree.symlinkDirectories` in settings.

</details>

### `skills-upstream.txt`

Third-party skills installed from their own repos, plus a list of plugins to install yourself.

| When it runs | During `install.sh` and `install.ps1` |
|---|---|
| **Disable** | `DOTFILES_SKIP_UPSTREAM=1` skips all; comment a line out to drop one |
| **Source** | [`skills-upstream.txt`](../skills-upstream.txt) |

<details>
<summary>Details and examples</summary>

- One `owner/repo` per line, installed with `npx skills add -g`.
- A commented section lists plugins to install yourself, including diagram-design: `claude plugin marketplace add cathrynlavery/diagram-design`, then `claude plugin install diagram-design@diagram-design`.

</details>

---

## Other files

| File | What |
|---|---|
| [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) | gitleaks and the public-safety check |
| [`home/`](../home) | `gitconfig` (identity in `~/.gitconfig.local`), `gitignore_global`, oh-my-posh theme, `bashrc.d/dotfiles.sh` (brew, PATH, prompt, `pass`-backed secrets) |
| [`docs/diagrams/`](diagrams) | HTML sources and SVGs for the README diagrams; `.diagram-design` selects the style profile |
| [`docs/workflow-research.md`](workflow-research.md) | What was adopted and what to try next |
