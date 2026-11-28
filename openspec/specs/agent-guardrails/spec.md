# agent-guardrails Specification

## Purpose
The hooks in `claude/hooks/` and the wiring and deny rules in `claude/settings.example.json` bound what an unattended Claude Code agent may do: a push-and-merge dial the owner flips from chat, a guard that stops the agent rewriting that dial or the hooks, a merge gate that needs a review label and green CI, reversible-command auto-approval in OpenSpec repos, and checks that run when files change or the agent stops. Each hook reads Claude Code hook JSON on stdin; a permission hook prints a `permissionDecision` of `deny`, `ask` or `allow`, or prints nothing to leave the decision to the next hook and the normal prompt.

## Requirements

### Requirement: Autonomy dial state
The dial SHALL be the single word `full` or `less` in `~/.claude/autonomy-level`. An absent file SHALL mean `full`. `autonomy-gate` SHALL answer `ask` when the file exists but cannot be read.

#### Scenario: Absent file
- **WHEN** `~/.claude/autonomy-level` does not exist and the agent runs `git push origin feature`
- **THEN** `autonomy-gate` makes no decision

### Requirement: Dial toggle from chat
`autonomy-toggle` (UserPromptSubmit) SHALL, after trimming whitespace, lowercasing and removing trailing `.` and `!`, treat the prompt `go less`, `go into less` or `go into less mode` as a request for `less`, and `go full`, `go into full` or `go into full mode` as a request for `full`. It SHALL write the level to `~/.claude/autonomy-level` and print a `systemMessage` and `additionalContext` naming the new level. Any other prompt SHALL produce no output and no change. If the write fails it SHALL print a `systemMessage` that the write failed and the state is unchanged.

#### Scenario: Exact phrases
- **WHEN** the prompt is `Go Full!` or `  go into less mode. `
- **THEN** the level file holds `full` or `less` respectively and a confirmation is printed

#### Scenario: Near misses
- **WHEN** the prompt is `go fully autonomous`, `go less strict on X` or `go less please`
- **THEN** nothing is printed and the level file is unchanged

#### Scenario: Unwritable state
- **WHEN** the level file cannot be written
- **THEN** the hook prints `FAILED to write` in a `systemMessage` and exits 0

### Requirement: Push and merge block in less mode
When the dial is `less`, `autonomy-gate` SHALL answer `deny` to any Bash command that runs `git push` (including with `-C <dir>`, other leading options, an environment prefix, `command`, or after `cd ... &&`), `gh ... pr ... merge`, or `gh ... api ... merge`. It SHALL make no decision on other commands. When the dial is `full` it SHALL make no decision on them.

#### Scenario: Push forms blocked
- **WHEN** the dial is `less` and the command is `git push origin x`, `git -C /x push`, `cd /x && git push`, `VAR=1 git push` or `command git push`
- **THEN** each is denied with a reason that says push is blocked and to say `go full`

#### Scenario: Merge forms blocked
- **WHEN** the dial is `less` and the command is `gh pr merge 5 -R o/r` or `gh api repos/o/r/pulls/5/merge -X PUT`
- **THEN** each is denied

#### Scenario: Other commands and full mode
- **WHEN** the dial is `less` and the command is `git status`, `git pull`, `gh pr view 5` or `gh pr create`; or the dial is `full` and the command is `git push origin x`
- **THEN** no decision is made

### Requirement: Tamper guard
At every dial level, `autonomy-gate` SHALL answer `deny` to a Bash command that writes to the autonomy-level file, to anything under `~/.claude/hooks/`, or to anything under a `do-no-work/claude/hooks` directory (the conventional checkout location). A write is a redirection target (`>`, `>>`, `&>`, `2>>`), an operand of `tee`, `cp`, `mv`, `rm`, `ln`, `install`, `chmod`, `chown`, `touch`, `truncate`, `shred` or an editor, an `of=` operand of `dd`, a file of `sed -i`, a command string passed to `bash -c`, `sh -c` or `eval`, a script string passed to an interpreter (`python`, `node`, `ruby`, `perl` and similar) with `-c` or `-e`, or a relative target after a `cd` into one of those directories. A literal `$HOME/.claude/...` target SHALL be denied because `$HOME` cannot be resolved statically. Reading, listing, diffing or copying out of those paths SHALL NOT be denied. A command that cannot be parsed SHALL be answered with `ask`.

#### Scenario: Writes denied
- **WHEN** the command is `echo less > ~/.claude/autonomy-level`, `cp x ~/.claude/hooks/autonomy-gate.sh`, `sed -i 's/a/b/' ~/.claude/hooks/autonomy-gate.sh`, `echo less | tee ~/.claude/autonomy-level`, `cd ~/.claude/hooks; sed -i s/a/b/ autonomy-gate.sh` or `bash -c 'echo less > ~/.claude/autonomy-level'`
- **THEN** each is denied with a reason that refuses to write the dial or its hooks from Bash

#### Scenario: Reads allowed
- **WHEN** the command is `cat ~/.claude/autonomy-level`, `grep -n x ~/.claude/hooks/*.sh`, `cp ~/.claude/hooks/autonomy-gate.sh /tmp/copy.sh` or `bash ~/.claude/hooks/autonomy-gate.sh < input.json`
- **THEN** no decision is made

#### Scenario: Unparseable input
- **WHEN** the hook's stdin is not valid JSON
- **THEN** it answers `ask` with a reason that the command could not be parsed

### Requirement: Merge gate
`gate-self-merge` SHALL act only on commands containing `gh pr merge`. It SHALL answer `allow` only when the command holds exactly one `gh pr merge`, has no `cd`, `pushd` or `git -C`, resolves to one PR (a literal number, or a branch or URL it can resolve with `gh pr view`), the PR carries the `REVIEWED` label, and the latest run of each check name has finished without failure (`FAILURE`, `CANCELLED`, `TIMED_OUT`, `STARTUP_FAILURE`, `ERROR`, `ACTION_REQUIRED`) and without pending. In every other case it SHALL answer `ask` with the reason, including when the PR has no checks at all or `gh` or `jq` fails.

#### Scenario: Reviewed and green
- **WHEN** the command is `gh pr merge 5 -R o/r --squash` and PR 5 has the `REVIEWED` label and one successful check
- **THEN** the answer is `allow` with the reason `PR #5 REVIEWED + CI green`

#### Scenario: Not reviewed, red, pending or no checks
- **WHEN** PR 5 lacks the label, or has a failing check, or has a pending check, or has no checks
- **THEN** the answer is `ask` with the matching reason (`lacks REVIEWED label`, `failing check(s)`, `pending check(s); wait for CI`, `no CI checks`)

#### Scenario: Superseded cancelled run
- **WHEN** a check name has an earlier `CANCELLED` run and a later `SUCCESS` run
- **THEN** only the later run counts and the gate can allow

#### Scenario: Chained or directory-changing merge
- **WHEN** the command is `gh pr merge 5 && gh pr merge 6`, or `cd ../other && gh pr merge 5 -R a/b`
- **THEN** the answer is `ask` and `gh` is not called

#### Scenario: Not a merge
- **WHEN** the command is `gh pr view 5`
- **THEN** the hook makes no decision

### Requirement: Auto-approval in OpenSpec repos
`openspec-autonomy` SHALL answer `allow` to a Bash command only when all of these hold: the dial is `full`; the command's working directory (the directory of a leading `cd`, else the session `cwd`) is inside a git work tree whose top level has `openspec/config.yaml`; every directory the command moves into with `cd` or `git -C` is such a repo or under `/tmp`; the command matches none of the hard stops; it contains no pipe, backtick, `$(`, `<` or `>`; and every segment (split on `&&` and `;`) begins with an allowed verb. The allowed verbs are `cd`, `git` (`add`, `commit`, `rebase`, `fetch`, `pull`, `switch`, `checkout`, `branch`, `worktree`, `status`, `log`, `diff`, `show`, `stash`, `push`), `gh pr` (`create`, `view`, `edit`, `checks`, `list`, `comment`, `diff`), `openspec`, `npm` (`test`, `ci`, `run test|lint|build|typecheck`), `pytest`, `uv run pytest|ruff`, `go test|vet|build` and `make test|lint`. The hard stops are `rm`, `sudo`, `dd`, `mkfs`, `shred`, `ssh`, `scp`, `rsync`, a push naming `main` or `master`, a force push, `git reset --hard`, `git clean`, `gh` with `--admin`, `gh release`, `gh workflow run`, `gh api`, `gh repo delete|edit|rename`, `gh secret`, `npm publish`, `wrangler` deploy/publish/delete, `docker push|rm|system`, `curl ... | sh`, `make release`, any mention of Claude settings files, the autonomy-level file or the hooks directory, `pass`, and mail-sending commands. Everything else it SHALL leave undecided, so deny rules and other hooks still apply and the most restrictive decision wins.

#### Scenario: Reversible ceremony
- **WHEN** the session is in an OpenSpec repo with the dial at `full` and the command is `git add -A && git commit -m x`, `git push -u origin feat-x`, `gh pr create --title x`, `openspec validate --all --strict`, `uv run pytest -q` or `git worktree add ../x -b y`
- **THEN** the answer is `allow` with the reason `openspec-autonomy: OpenSpec repo, reversible command`

#### Scenario: Hard stops fall through
- **WHEN** the command is `git push origin main`, `git push --force origin x`, `git push origin HEAD:refs/heads/main`, `rm -f x`, `git reset --hard`, `gh api repos/o/r`, `gh release create v1` or `curl -s https://x/p.py | python3`
- **THEN** no decision is made

#### Scenario: Outside the allowlist
- **WHEN** the command is `gh pr merge 5`, `git status | head`, `echo hi > f` or `ls`
- **THEN** no decision is made

#### Scenario: Not an OpenSpec repo, or dial at less
- **WHEN** the session is in a git repo without `openspec/config.yaml`, or the dial is `less`
- **THEN** no decision is made for any command

#### Scenario: Leading cd chooses the repo
- **WHEN** the session is in a plain repo and the command is `cd <openspec repo> && git status`
- **THEN** the answer is `allow`
- **AND** the same command run from an OpenSpec repo with a plain repo as the `cd` target gets no decision

### Requirement: Lint and type-config protection
`protect-lint-config` (PreToolUse on Edit, Write and MultiEdit) SHALL answer `ask` with the reason `lint/type config change: fix the code instead, or confirm` when the edited file is a linter, formatter or pre-commit config (`.eslintrc*`, `eslint.config.*`, `.golangci.*`, `ruff.toml`, `.ruff.toml`, `.prettierrc*`, `biome.json`, `.markdownlint*`, `.pre-commit-config.yaml`) or a baseline file (`aiq-lint-baseline.json`, `*baseline*.json`); a `pyproject.toml` whose edit text names `[tool.ruff`, `[tool.mypy` or `[tool.pyright`; or a `tsconfig*.json` whose edit text names `strict`, `noImplicit`, `noUnchecked`, `exactOptional`, `useUnknown` or `noFallthrough`. Any other edit SHALL get no decision.

#### Scenario: Config files
- **WHEN** the edit targets `eslint.config.js`, `.pre-commit-config.yaml` or `some-baseline.json`
- **THEN** the answer is `ask`

#### Scenario: Section-sensitive files
- **WHEN** an edit to `pyproject.toml` changes `[tool.ruff]`, or a `Write` to it contains `[tool.mypy]`, or an edit to `tsconfig.json` changes `"strict"`
- **THEN** the answer is `ask`
- **AND** an edit to `pyproject.toml` that changes only `[project]`, or to `tsconfig.json` that changes only `"target"`, gets no decision

### Requirement: Stop gate
`stop-gate` (Stop) SHALL allow the stop silently when the working directory is not in a git repo, when the work tree is clean, or when no check command is selected. Otherwise it SHALL run the selected command through `bash -c` with a timeout of `CLAUDE_STOP_GATE_TIMEOUT` seconds (default 120) when a `timeout` or `gtimeout` binary exists and block the stop with `{"decision":"block","reason":...}` when it fails, the reason naming the command and exit code and carrying at most the first 40 lines of output (and `timed out after <N>s` first on exit 124). The command SHALL be chosen in order: `CLAUDE_STOP_GATE_CMD`; the first line of `.claude/stop-gate`; auto-detect, which takes the first of `go.mod` (`go vet ./... && go test ./...`), a `package.json` with a `test` script (`npm test --silent`), and `pytest.ini` or pytest in `pyproject.toml` (`python3 -m pytest -q -x`) that applies, followed by `openspec validate --strict --all` when `openspec/config.yaml` exists and the `openspec` CLI is installed. The last two sources are repo-defined and SHALL run only when `origin` is a GitHub URL owned by a user or organisation listed in `CLAUDE_STOP_GATE_OWNERS`. When the stop hook is already active and the failure output is identical to the previous failure in the same session, it SHALL allow the stop with a `systemMessage` saying so; a different failure SHALL block again.

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

### Requirement: Go check after edits
`go-check` (PostToolUse on Write and Edit) SHALL do nothing when the edited file is not a `.go` file or no `go.mod` exists in its directory or any parent. Otherwise, in the directory holding `go.mod`, it SHALL run `go test` and `go vet` on the edited file's package, and `golangci-lint run --new-from-rev=HEAD` on it when `golangci-lint` is installed, each with output clipped to 40 lines and the tests and linter limited to 90 seconds. It SHALL report failures as `additionalContext` that names the failing tool and package, and a pass as the `systemMessage` `go test + vet + lint passed (<package>)`.

#### Scenario: Passing package
- **WHEN** a `.go` file in a module whose tests and vet pass is edited
- **THEN** the hook prints a `systemMessage` ending `passed (./pkg)`

#### Scenario: Failing test
- **WHEN** the package's test fails
- **THEN** the hook prints `additionalContext` beginning `TEST FAILURES (./pkg):` followed by the test output

#### Scenario: Not Go
- **WHEN** the edited file is `README.md`, or a `.go` file outside any module
- **THEN** the hook prints nothing and exits 0

### Requirement: Settings example wiring
`claude/settings.example.json` SHALL wire `autonomy-gate`, `gate-self-merge` and `openspec-autonomy` under `PreToolUse` for `Bash`, `protect-lint-config` under `PreToolUse` for `Edit|Write|MultiEdit`, `autonomy-toggle` under `UserPromptSubmit`, `go-check` under `PostToolUse` for `Write|Edit`, and `stop-gate` under `Stop`. It SHALL carry `permissions.deny` entries for `rm`, `sudo`, `git push origin main`, `git push origin master`, `git push --force`, `gh pr merge --admin`, `Edit` of `~/.claude/settings.json` and `~/.claude/settings.local.json`, and `Edit` and `Write` of `~/.claude/autonomy-level`, `~/.claude/hooks/**` and `~/Github/do-no-work/claude/hooks/**`. `dnw-doctor` compares a user's settings against this file.

#### Scenario: Doctor against its own example
- **WHEN** a user's settings are a copy of `claude/settings.example.json`
- **THEN** `dnw-doctor` reports no missing hook or deny rule
