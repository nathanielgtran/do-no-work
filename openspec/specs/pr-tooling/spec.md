# pr-tooling Specification

## Purpose
The scripts and workflows an agent uses to take a PR from open to merged without a human watching: wait for CI, track PRs across repos, clean up worktrees safely, review a PR in CI and apply the `REVIEWED` label only for a clean verdict on the reviewed commit, apply the fleet's GitHub defaults to a repo, and run the repo's own test suite.

## Requirements

### Requirement: Waiting for CI
`ci-wait <pr-number> [-R owner/repo]` SHALL poll the PR's checks with `gh pr view --json statusCheckRollup`, print one line `<name>: <result>` per check (`pending` while unfinished), and exit 0 only when at least one check exists, all have finished, and each concluded `success`, `skipped` or `neutral`. It SHALL exit 1 when a finished check has any other conclusion, when no check has appeared after `CI_WAIT_EMPTY_GRACE` seconds (default 60; it prints `no checks reported after <N>s` to stderr), and when checks are still pending after `CI_WAIT_TIMEOUT` seconds (default 1200; it prints the current results and `timed out after <N>s`). It SHALL poll every `CI_WAIT_INTERVAL` seconds (default 15). A missing or non-numeric PR number, an unknown flag, a missing `gh` or `jq`, or a failed fetch SHALL exit 2.

#### Scenario: All green
- **WHEN** every check is `COMPLETED` with conclusion `SUCCESS`
- **THEN** each check is printed as `<name>: success` and the exit code is 0

#### Scenario: One failure
- **WHEN** one check concluded `FAILURE`
- **THEN** it is printed as `<name>: failure` and the exit code is 1

#### Scenario: Checks not registered yet
- **WHEN** the first polls return no checks and a later poll returns one successful check within the grace period
- **THEN** the exit code is 0

#### Scenario: Never any checks
- **WHEN** no check appears for the whole grace period
- **THEN** the exit code is 1

#### Scenario: Still running at the timeout
- **WHEN** a check is still in progress when `CI_WAIT_TIMEOUT` expires
- **THEN** the exit code is 1

### Requirement: Fleet PR tracking
`fleet <prs|watch|ready>` SHALL list open PRs (up to 100 per repo, from `gh pr list`) for the repos given by `--repos owner/a,owner/b`, else by the file named by `FLEET_FILE`, else by `~/.config/do-no-work/fleet.txt` (one `owner/repo` per line, `#` comments allowed). It SHALL narrow the list with `--author`, `--label` and `--head <branch-glob>`. A PR SHALL be ready when no check failed or is pending (`success`, `skipped` and `neutral` count as passing), it has the `REVIEWED` label, and its merge state is `CLEAN`. `prs` SHALL print a table of repo, number, title (cut to 50 characters), check counts, `REVIEWED`, merge state and ready, or JSON with `--json`. `ready` SHALL print only ready PRs as `owner/repo#N`. `watch` SHALL poll every `--interval` seconds (default 30) until no matching PR has a pending check, print the table and one `owner/repo#N <check>: <first error line>` line per failed check, and exit 0 when all are ready, 1 when not, and 2 on reaching `--timeout` seconds (default 1500). A missing repo list, a malformed repo name, an unknown subcommand or flag, or a non-numeric `--timeout` or `--interval` SHALL exit 2, and a failed `gh pr list` SHALL exit 1 naming the repo.

#### Scenario: Ready computation
- **WHEN** one PR has all checks passing, `REVIEWED` and a `CLEAN` merge state, and others are pending, failing, unlabelled or `DIRTY`
- **THEN** `fleet prs --json` marks only the first as ready, and `fleet ready` prints only its `owner/repo#N`

#### Scenario: Repo list precedence
- **WHEN** `--repos`, `FLEET_FILE` and the default file all exist
- **THEN** `--repos` wins, then `FLEET_FILE`, then the default path

#### Scenario: Branch filter
- **WHEN** the user passes `--head 'NO-TICKET-*'`
- **THEN** only PRs whose head branch matches the glob are listed

#### Scenario: Watching a failure
- **WHEN** `fleet watch` finds a failed check whose run log has an `##[error]` line
- **THEN** it prints `owner/repo#N <check>: <that line>` and exits 1
- **AND** when the log cannot be fetched it prints `logs unavailable` in its place

#### Scenario: Watch timeout
- **WHEN** a check is still pending when `--timeout` expires
- **THEN** it prints `timed out` to stderr and exits 2

### Requirement: Safe worktree removal
`safe-worktree-remove <worktree-path> [--branch]` SHALL remove a linked git worktree with `git worktree remove` (never `--force`) only when none of these hold: the path is the main checkout, is not a worktree, or is a subdirectory of one rather than its root; the worktree is locked; it has uncommitted or untracked changes; its HEAD has commits that are covered by none of: its upstream, `origin`'s default branch, the main checkout's HEAD, or a merged GitHub PR for its branch; or any running process has the worktree as its working directory. Each refusal SHALL print `safe-worktree-remove: <reason>` to stderr and exit 1. With `--branch` it SHALL also delete the worktree's local branch after the removal. A missing path or missing argument SHALL exit 1 with a usage or `no such directory` message.

#### Scenario: Clean worktree with nothing new
- **WHEN** a worktree has no changes and no commits beyond the main checkout's HEAD
- **THEN** it is removed, `removed worktree <path>` is printed and the exit code is 0

#### Scenario: Refusals
- **WHEN** the target is the main checkout, a dirty worktree, a locked worktree, a worktree with an unpushed commit and no merged PR, or a worktree that is another process's working directory
- **THEN** it exits 1 with `refusing: ...` naming the reason (`the main checkout`, `uncommitted or untracked changes`, `locked`, `commits that are not pushed`, `in use by process(es)`) and the worktree is untouched

#### Scenario: Subdirectory
- **WHEN** the path is a subdirectory of a worktree
- **THEN** it exits 1 with `pass the worktree root, not a subdirectory`

#### Scenario: Delete the branch too
- **WHEN** a removable worktree is given with `--branch`
- **THEN** the worktree and its local branch are both gone

### Requirement: Review verdict handling
`scripts/claude-review-verdict.sh` SHALL turn a structured review result (`{verdict, summary, findings[]}` in `STRUCTURED_OUTPUT`) into a PR comment and, only for the verdict `PASS` on the commit that was reviewed, the `REVIEWED` label. It SHALL fail closed: a missing, unparseable or lowercase verdict, a verdict other than `PASS` or `BLOCK`, a `BLOCK`, a PR head that no longer equals `EXPECTED_SHA`, and a head SHA that cannot be read SHALL each exit 1 without labelling. The comment (summary, one bullet per finding, the reviewed commit and `VERDICT: <verdict>`) SHALL be posted for both `PASS` and `BLOCK`; failing to post it SHALL warn but not change the verdict. It SHALL exit 0 only when the label was applied.

#### Scenario: Clean pass
- **WHEN** the verdict is `PASS` and the PR head equals `EXPECTED_SHA`
- **THEN** a comment is posted, `REVIEWED` is added and the exit code is 0

#### Scenario: Block
- **WHEN** the verdict is `BLOCK`
- **THEN** the comment is still posted, no label is added and the exit code is 1

#### Scenario: Head moved during review
- **WHEN** the verdict is `PASS` but the PR head differs from `EXPECTED_SHA`
- **THEN** no label is added and the exit code is 1

#### Scenario: Unusable output
- **WHEN** the structured output is empty, not JSON, lacks `verdict`, or has `pass` in lowercase
- **THEN** no label is added and the exit code is 1

### Requirement: Reusable review workflow
`.github/workflows/claude-review.yml` SHALL be a `workflow_call` workflow with `contents: read` and `pull-requests: write` only, at most one run per PR number (a newer run cancels the older). It SHALL skip PRs from forks (leaving the label to a human) without touching the label. For other PRs it SHALL remove `REVIEWED` when present on every run, then skip drafts. For the rest it SHALL check out the PR head, check out `scripts/claude-review-verdict.sh` from the `tools-ref` of the tools repository (default `main`, never the PR's own copy), run Claude with read-only tools (`Read`, `Grep`, `Glob`, `git diff`, `git log`) and a JSON schema requiring `verdict`, `summary` and `findings`, and pass the result to the verdict script. `.github/workflows/review.yml` SHALL call it for this repo's own PRs from the same repository only.

#### Scenario: New push invalidates review
- **WHEN** a PR with the `REVIEWED` label gets a new commit
- **THEN** the workflow removes the label before the review starts

#### Scenario: Fork or draft PR
- **WHEN** the PR comes from a fork, or is a draft
- **THEN** no Claude review runs (and for a draft the label has already been removed)

#### Scenario: Verdict script source
- **WHEN** a PR modifies `scripts/claude-review-verdict.sh`
- **THEN** the workflow still runs the copy from the trusted `tools-ref`

### Requirement: Repo bootstrap
`repo-bootstrap <owner/repo> [--public] [--dry-run]` SHALL apply the fleet's GitHub defaults to that one repo through `gh api`, printing one `ok` or `dry` line per setting: Actions with a read-only default token, no PR approval by Actions, approval required for all external contributors, and only GitHub-owned plus allow-listed actions (`BOOTSTRAP_ACTIONS`); squash-only merges with automatic branch deletion and no wiki or projects; secret scanning with push protection; private vulnerability reporting, Dependabot alerts and security updates; the `REVIEWED` label, created only when absent; and a `protect-main` ruleset on the default branch (no deletion, no non-fast-forward, PR required with stale reviews dismissed on push), created or, when one named `protect-main` exists, updated in place. The required-status-checks rule SHALL be included only when `BOOTSTRAP_CHECKS` (comma-separated) is set; otherwise it prints `skip required_status_checks: BOOTSTRAP_CHECKS not set`. With `--dry-run` it SHALL make no mutating call. With `--public` it SHALL warn on stderr for each workflow that uses a self-hosted runner. A repo name that is not `owner/repo` SHALL exit 1.

#### Scenario: Dry run
- **WHEN** the user runs `repo-bootstrap o/r --dry-run`
- **THEN** planned calls print as `dry  <METHOD> <endpoint> (<setting>)` and no mutating `gh api` call is made

#### Scenario: Existing ruleset
- **WHEN** a ruleset named `protect-main` already exists
- **THEN** it is updated by ID, no second ruleset is created and other rulesets are not touched

#### Scenario: Public repo with a self-hosted workflow
- **WHEN** `--public` is given and a workflow file has `runs-on: [self-hosted, ...]`
- **THEN** `WARNING: <file> uses a self-hosted runner` is printed to stderr

#### Scenario: Bad repo name
- **WHEN** the argument is `notarepo`
- **THEN** it exits 1 without calling the API

### Requirement: Review caller rollout
`repo-bootstrap <owner/repo> --review` SHALL set up the CI review for one repo and print a final `summary label=<..> allowlist=<..> caller=<..> secret=<..>` line. It SHALL create the `REVIEWED` label when absent; add the pinned `anthropics/claude-code-action` and `oven-sh/setup-bun` action patterns (the latter read from the action's `action.yml` at the pinned SHA) to the repo's selected-actions allowlist without removing existing patterns, writing nothing when both are already present and skipping the allowlist when the repo allows all actions; render `.github/workflows/review.yml` from `examples/claude-review-caller.yml` with the reusable workflow and `tools-ref` pinned to the same 40-hex commit SHA of the workflow repository (never `main`) and open a PR for it on a `NO-TICKET-claude-review` branch, never duplicating an open caller PR (an out-of-date one is updated in place); and set the `CLAUDE_CODE_OAUTH_TOKEN` secret from the environment (token passed on stdin) when absent, else print the `gh secret set` command to run. A public repo SHALL get a caller without a `runs-on` input and SHALL refuse a self-hosted `BOOTSTRAP_REVIEW_RUNS_ON` before making any write. The rendered caller SHALL have empty top-level permissions and a job-level condition that skips fork PRs.

#### Scenario: Allowlist merge
- **WHEN** the repo's allowlist holds only `astral-sh/setup-uv@*`
- **THEN** a PUT sends that pattern plus the two action pins, and a rerun with the pins present sends no PUT

#### Scenario: Caller missing
- **WHEN** the repo has no `.github/workflows/review.yml`
- **THEN** the branch is created, the rendered caller is committed to it, and a PR is opened whose body has the `What`, `Why`, `Proof`, `Risk + rollback` and `Checklist` headings

#### Scenario: Public repo with self-hosted runs-on
- **WHEN** `--review --public` runs with `BOOTSTRAP_REVIEW_RUNS_ON=self-hosted`
- **THEN** it exits non-zero and no mutating API call has been made

### Requirement: Test discovery and CI
`tests/run-all.sh` SHALL run every `tests/*_test.sh` plus the skill suites it lists, each with a timeout of `TEST_TIMEOUT` seconds (default 300), print a result table, and exit non-zero when any suite fails. A suite whose required tool is missing, or that is Linux-only on another OS, SHALL be reported as skipped. `--list` SHALL print the suite names, `--only <glob>` SHALL run only suites whose name matches, and an unknown option SHALL exit 2. `.github/workflows/ci.yml` SHALL run on pull requests and pushes to `main` using GitHub-hosted runners only: the shell-syntax check, `tests/run-all.sh`, the public-safety check and the changelog check on `ubuntu-latest` and `macos-latest`; `install.ps1 -NoDeps` into a throwaway home on `windows-latest`; and gitleaks. It SHALL NOT name individual test files, so a new `tests/*_test.sh` runs without a workflow change.

#### Scenario: New test is picked up
- **WHEN** a file `tests/new_test.sh` is added
- **THEN** `tests/run-all.sh --list` includes `new_test.sh` and `ci.yml` needs no change

#### Scenario: Filtered run
- **WHEN** the user runs `tests/run-all.sh --only 'ci_discovery*'`
- **THEN** only that suite runs and the table lists it

#### Scenario: Unknown option
- **WHEN** the user runs `tests/run-all.sh --bogus`
- **THEN** it prints `unknown option: --bogus` and exits 2
