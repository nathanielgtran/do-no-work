# Operations

Running the workflow day to day: PRs, changelog, new repos, the CI review, secrets and tests. [Back to the README](../README.md).

- [PR format](#pr-format)
- [Changelog](#changelog)
- [Tracking PRs across repos](#tracking-prs-across-repos)
- [New repo](#new-repo)
- [Roll out the review](#roll-out-the-review)
- [Claude review](#claude-review)
- [Secrets](#secrets)
- [Keeping it public-safe](#keeping-it-public-safe)
- [Test](#test)

---

## PR format

PR bodies follow the fleet template, [`PULL_REQUEST_TEMPLATE.md`](https://github.com/nathanielgtran/.github/blob/main/PULL_REQUEST_TEMPLATE.md):

`## What` · `## Why` · `## Proof` · `## Risk + rollback` · `## Checklist`

- Proof is pasted test or run output, never "tested locally".
- The [`CLAUDE.md` template](../claude/CLAUDE.md.example) enforces it for the agent.
- The `pr-template` check in the fleet repos enforces it in CI.

## Changelog

PRs never edit `CHANGELOG.md`, so parallel PRs can't conflict there.

| Step | Command |
|---|---|
| Get the next free ID | `scripts/changelog.sh next <type>` |
| Add the fragment | `changelog.d/<type-N>.md`, one line, no ID |
| Validate (CI runs it) | `scripts/changelog.sh check` |
| Fold in at release | `scripts/changelog.sh compile [--version vX.Y.Z]` |

Details: [`changelog.sh`](scripts.md#changelogsh-and-changelogd).

## Tracking PRs across repos

After a fan-out:

1. `fleet watch --head 'NO-TICKET-*'` waits for checks.
2. `fleet ready` lists the PRs that can merge.
3. Merge each line with one `gh pr merge` per PR, so the merge gate checks each.

Repo list format: [`examples/fleet.txt`](../examples/fleet.txt). Details: [`fleet`](scripts.md#fleet).

## New repo

`repo-bootstrap` applies the fleet defaults to an existing GitHub repo:

- Actions lockdown
- squash-only merges
- secret scanning
- the `REVIEWED` label
- a `protect-main` ruleset

```bash
BOOTSTRAP_CHECKS="test (ubuntu-latest),gitleaks" repo-bootstrap owner/repo --public
```

- Idempotent. `--dry-run` prints the calls without making them.
- `--public` also warns if a workflow uses a self-hosted runner.
- Without `BOOTSTRAP_CHECKS` the required-checks rule is skipped.
- `BOOTSTRAP_ACTIONS` overrides the allowed third-party actions.

Full flag list: [`repo-bootstrap`](scripts.md#repo-bootstrap).

## Roll out the review

`repo-bootstrap owner/repo --review` sets up only the CI Claude review. `review-rollout` runs it over several repos and prints a summary table.

```bash
CLAUDE_CODE_OAUTH_TOKEN=... review-rollout owner/repo1 owner/repo2
```

**What it sets up**

- the `REVIEWED` label
- Actions allowlist entries for the pinned `claude-code-action` and its nested `setup-bun`, merged into the existing list (skipped when all actions are allowed)
- a caller workflow, opened as a PR if `.github/workflows/review.yml` is missing, or updated by PR when it differs from the current template
- the `CLAUDE_CODE_OAUTH_TOKEN` secret

**Token.** Read from the environment and piped to `gh secret set` on stdin. Without it you get a `fix:` line with the command. A long-lived token comes from `claude setup-token`.

**Pinning and runners**

| Item | Rule |
|---|---|
| Caller pin | Full commit SHA of this repo: the current HEAD of its default branch, or `BOOTSTRAP_REVIEW_REF` |
| `tools-ref` | Same SHA |
| Fork guard | `if: github.event.pull_request.head.repo.full_name == github.repository`, so fork PRs never reach a self-hosted runner |
| Private repos | `BOOTSTRAP_REVIEW_RUNS_ON`; unset or `auto` picks the repo's single `nuc-*` runner label, else `nuc`, else `ubuntu-latest` with a note |
| Public repos | Always `ubuntu-latest` |
| `skip-changelog` label | Applied to the caller PR when the repo has one |

**Re-run to update.** If the caller already exists on the default branch, or a `NO-TICKET-claude-review` PR is open, the new caller is rendered and compared.

- A difference opens `NO-TICKET-claude-review-harden` with a `[NO-TICKET] ci: harden Claude review caller (pin SHA, fork guard)` PR, or updates the open caller PR's branch and comments on it.
- Identical prints `ok`.
- Bump a pin by re-running after merging a change here.

## Claude review

`.github/workflows/claude-review.yml` is a reusable workflow. On each PR:

1. It removes `REVIEWED`.
2. Claude reviews the diff read-only (Read/Grep/Glob, `git diff`/`git log`).
3. It posts the findings as a comment.
4. It adds `REVIEWED` only on a PASS for the same head commit.

- A BLOCK, a missing or unparseable verdict, or a head that moved mid-review fails the job with no label.
- Fork PRs and drafts are skipped (no secrets on forks).
- The label is read from the action's `structured_output` via `scripts/claude-review-verdict.sh`, always loaded from `tools-ref` (a pinned SHA in callers), not the PR.

**Enable it in a repo** (easiest: `repo-bootstrap owner/repo --review`, which fills in the SHA pin):

1. Create a `REVIEWED` label.
2. Run `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R owner/repo` with a token from `claude setup-token`.
3. Render `examples/claude-review-caller.yml` into `.github/workflows/review.yml`.

Public repos keep `ubuntu-latest`. If the repo restricts allowed actions, allow `anthropics/claude-code-action@*`. Workflow inputs: [`claude-review`](config.md#claude-review).

## Secrets

- None are stored here.
- Scripts read tokens from environment variables or `pass` (for example `pass dev/magic-mcp-key`).
- A gitleaks pre-commit hook and GitHub push protection both block accidental commits.

## Keeping it public-safe

`scripts/public-safety-check.sh` fails if a tracked file contains personal data. It matches case-insensitively against three sources:

| Source | What |
|---|---|
| Builtin | Generic patterns: private IP ranges, private keys, absolute home directories |
| Machine | Derived at run time, never committed: `$USER`, `git config user.email` and `user.name` |
| Private list | One regex per line, `#` comments, at `~/.config/do-no-work/public-safety-deny` (override with `PUBLIC_SAFETY_DENY`). Format: [`scripts/public-safety-deny.example`](../scripts/public-safety-deny.example) |

In CI the private list comes from the optional `PUBLIC_SAFETY_DENY_LIST` repo secret (empty on fork PRs). Set it with:

```bash
gh secret set PUBLIC_SAFETY_DENY_LIST -R nathanielgtran/do-no-work < ~/.config/do-no-work/public-safety-deny  # public-safety: allow (public repo name)
```

- Output names the file, line and source, but never prints a private pattern.
- A line containing `public-safety: allow` is skipped. Give a reason next to it.

## Test

```bash
./tests/run-all.sh                  # every tests/*_test.sh plus the skill suites, summary table at the end
./tests/run-all.sh --only 'hooks*'  # one test by glob
./tests/run-all.sh --list           # what would run
```

- Name new tests `tests/<x>_test.sh`. CI picks them up; don't edit `ci.yml`.
- `tests/docs_links_test.sh` fails on any broken relative link or `#anchor` in `README.md` and `docs/*.md`.

**What CI runs**

- the tests on GitHub-hosted Ubuntu and macOS, plus the skill test suites and gitleaks
- `scripts/public-safety-check.sh`, also a pre-commit hook
- a `windows` job: `install.ps1 -NoDeps` on `windows-latest` into a throwaway home, checking the hook and bin script landed

Details: [`ci`](config.md#ci).
