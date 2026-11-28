## ADDED Requirements

### Requirement: Post PR create guidance
`post-pr-create` (PostToolUse on Bash, wired with `if: Bash(gh pr create:*)`) SHALL read the hook JSON, find the git top level of `cwd`, and print `additionalContext` built with `jq`; it SHALL always exit 0. When a file under that repo's `.github/workflows` mentions `claude-review`, the context SHALL say that CI `claude-review` reviews the PR and applies `REVIEWED`, to wait with `gh pr checks <N> --watch --interval 20`, to merge with one literal PR number via `gh pr merge <N> --squash --delete-branch` only when `REVIEWED` is on and every check is green, never to add `REVIEWED` itself, and that a `claude-review` block is a red check to fix and push. Otherwise the context SHALL say the repo has no CI review, to spawn one `reviewer` agent with the diff and report its findings, and that `REVIEWED` and the merge are left to the user. The context SHALL use the PR number when the tool response contains a `/pull/<N>` URL, else `<N>`. In neither case SHALL it tell the session to apply `REVIEWED`.

#### Scenario: Repo with CI review
- **WHEN** the repo has a workflow file that mentions `claude-review`
- **THEN** the context mentions `claude-review`, `gh pr checks`, `--watch --interval 20` and `gh pr merge`, and the only mention of adding `REVIEWED` is a prohibition

#### Scenario: Repo without CI review
- **WHEN** the repo has no workflow that mentions `claude-review`, or no workflows
- **THEN** the context tells the session to spawn one `reviewer` agent and leave `REVIEWED` and the merge to the user, and does not mention `gh pr merge`

## MODIFIED Requirements

### Requirement: Stop gate
`stop-gate` (Stop) SHALL allow the stop silently when the working directory is not in a git repo, when the work tree is clean, or when no check command is selected. Otherwise it SHALL run the selected command through `bash -c` with a timeout of `CLAUDE_STOP_GATE_TIMEOUT` seconds (default 120) when a `timeout` or `gtimeout` binary exists and block the stop with `{"decision":"block","reason":...}` when it fails, the reason naming the command and exit code and carrying at most the first 40 lines of output (and `timed out after <N>s` first on exit 124). The command SHALL be chosen in order: `CLAUDE_STOP_GATE_CMD`; the first line of `.claude/stop-gate`; auto-detect, which takes the first of `go.mod` (`go vet ./... && go test ./...`), a `package.json` with a `test` script (`npm test --silent`), and `pytest.ini` or pytest in `pyproject.toml` (`python3 -m pytest -q -x`) that applies, followed by `openspec validate --strict --all` when `openspec/config.yaml` exists and the `openspec` CLI is installed. The last two sources are repo-defined and SHALL run only when `origin` is a GitHub URL owned by a user or organisation listed in `CLAUDE_STOP_GATE_OWNERS`. When the stop hook is already active and the failure output is identical to the previous failure in the same session, it SHALL allow the stop with a `systemMessage` saying so; a different failure SHALL block again. After a passing run it SHALL store, per session, a fingerprint of the selected command, the HEAD commit, the `git diff HEAD` output and the names and content checksums of untracked, non-ignored files; when a later stop in the same session computes the same fingerprint it SHALL allow the stop without running the check. A failing or timed-out run SHALL NOT be stored as passing.

#### Scenario: Gate outcomes
- **WHEN** the tree is dirty and `CLAUDE_STOP_GATE_CMD` is `true`, or the tree is clean and it is `false`, or the directory is not a git repo
- **THEN** the stop is allowed with no output

#### Scenario: Failing check
- **WHEN** the tree is dirty and `CLAUDE_STOP_GATE_CMD` is `echo boom; false`
- **THEN** the hook blocks, and the reason contains `boom`

#### Scenario: Same failure twice
- **WHEN** the hook is invoked again with `stop_hook_active` true and the same failure output
- **THEN** it allows the stop; a different failure output blocks again

#### Scenario: Untrusted repo
- **WHEN** `.claude/stop-gate` exists but `origin` is not owned by anyone in `CLAUDE_STOP_GATE_OWNERS`
- **THEN** the file's command is not run

#### Scenario: Timeout and clipping
- **WHEN** the check outlives `CLAUDE_STOP_GATE_TIMEOUT`, or prints more than 40 lines before failing
- **THEN** the reason says `timed out after <N>s`, or holds only the first 40 lines of output

#### Scenario: Unchanged tree after a pass
- **WHEN** the check passes, and the hook runs again with the working tree unchanged
- **THEN** the second run allows the stop and the check command is not run again

#### Scenario: Changed tree reruns
- **WHEN** the check passed, and then a tracked file is edited or an untracked file is added or edited
- **THEN** the next stop runs the check again

#### Scenario: Failure not remembered
- **WHEN** the check fails and the hook runs again with the tree unchanged and `stop_hook_active` false
- **THEN** the check runs again and the stop is blocked again

### Requirement: Go check after edits
`go-check` (PostToolUse on Write, Edit and MultiEdit, wired `async` and `asyncRewake`) SHALL do nothing when `.tool_input.file_path` is absent or not a `.go` file, or no `go.mod` exists in its directory or any parent. Otherwise, in the directory holding `go.mod`, it SHALL run `gofmt -l` on the edited file, `go vet` on its package, and `golangci-lint run --new-from-rev=HEAD` on the package when `golangci-lint` is installed, the linter limited to 90 seconds. It SHALL NOT run `go test`; `stop-gate` runs tests. On success it SHALL print nothing and exit 0. On any failure it SHALL print to stderr a report that names each failing tool and package, with each tool's output clipped to 40 lines, and exit 2, which `asyncRewake` turns into a wake-up for Claude with the report as a system reminder.

#### Scenario: Passing package
- **WHEN** a `.go` file in a module whose vet and lint pass and whose file is gofmt-clean is edited
- **THEN** the hook prints nothing, exits 0, and has not run `go test`

#### Scenario: Failing vet
- **WHEN** `go vet` fails on the package
- **THEN** stderr begins `VET ISSUES (./pkg):` followed by the vet output and the exit code is 2

#### Scenario: Unformatted file
- **WHEN** `gofmt -l` lists the edited file
- **THEN** stderr names `FORMAT` and the file, and the exit code is 2

#### Scenario: Not Go
- **WHEN** the edited file is `README.md`, a `.go` file outside any module, or the input has no `file_path`
- **THEN** the hook prints nothing and exits 0

### Requirement: Settings example wiring
`claude/settings.example.json` SHALL wire `autonomy-gate`, `gate-self-merge` and `openspec-autonomy` under `PreToolUse` for `Bash`, with `onFailure` set to `block` on `autonomy-gate` and `gate-self-merge`; `protect-lint-config` under `PreToolUse` for `Edit|Write|MultiEdit`; `autonomy-toggle` under `UserPromptSubmit`; `post-pr-create` under `PostToolUse` for `Bash` with `if` `Bash(gh pr create:*)`; `go-check` under `PostToolUse` for `Write|Edit|MultiEdit` with `async` and `asyncRewake` true; and `stop-gate` under `Stop`. It SHALL carry no inline `gh pr create` hook. It SHALL carry `permissions.deny` entries for `rm`, `sudo`, `git push origin main`, `git push origin master`, `git push --force`, `gh pr merge --admin`, `Edit` of `~/.claude/settings.json` and `~/.claude/settings.local.json`, and `Edit` and `Write` of `~/.claude/autonomy-level`, `~/.claude/hooks/**` and `~/Github/do-no-work/claude/hooks/**`. `dnw-doctor` compares a user's settings against this file by hook command and deny entry.

#### Scenario: Doctor against its own example
- **WHEN** a user's settings are a copy of `claude/settings.example.json`
- **THEN** `dnw-doctor` reports no missing hook or deny rule

#### Scenario: Hook options
- **WHEN** the example is read
- **THEN** the `go-check` entry has `async` and `asyncRewake` true, the `post-pr-create` entry has the `gh pr create` `if`, and the `autonomy-gate` and `gate-self-merge` entries have `onFailure` `block`
