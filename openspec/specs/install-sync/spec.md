# install-sync Specification

## Purpose
After install, `bin/dnw-doctor` reports drift between the checkout and the live install without changing anything, and `bin/dnw-apply` brings a machine up to merged `main` safely enough to run unattended, alerting the owner when guard hooks or deny rules changed.

## Requirements

### Requirement: Doctor report
`dnw-doctor` SHALL print one finding per line as a status (`ok`, `warn` or `fail`), an area, and a detail, with an indented `fix:` line under any finding that has a remedy. The areas SHALL be `installed`, `overlay`, `settings`, `identity`, `shell` and `tools`. It SHALL be read-only and SHALL exit 1 when any finding is `fail`, otherwise 0 (warnings do not fail). `--json` SHALL emit one array of objects with `status`, `area`, `detail` and `fix` instead of text, with the same exit code.

#### Scenario: Clean install
- **WHEN** the repo was installed into the home directory and the user's settings contain every hook and deny rule from `claude/settings.example.json`
- **THEN** the output has `ok` lines for `installed`, `settings`, `identity` and `shell`, none of those areas has a `warn` or `fail` line, and the exit code is 0

#### Scenario: Missing installed file
- **WHEN** `~/.claude/hooks/stop-gate.sh` has been removed
- **THEN** a `fail installed missing ~/.claude/hooks/stop-gate.sh` finding with an `install.sh --no-deps` fix is printed and the exit code is 1

#### Scenario: Link points elsewhere or copy is stale
- **WHEN** an installed symlink targets a path other than the repo (or overlay) file, or an installed copy differs from its source
- **THEN** a `warn installed` finding names the file and the exit code stays 0
- **AND** for a stale copy the fix is `install.sh --no-deps --copy`

#### Scenario: JSON output
- **WHEN** the user runs `dnw-doctor --json` and the git identity is not set
- **THEN** stdout is a JSON array that includes an object with `status` `fail`, `area` `identity` and a non-empty `fix`, and the exit code is 1

#### Scenario: Bad invocation
- **WHEN** `dnw-doctor` is given an unknown flag, or a `--repo` directory with no `scripts/install-manifest.sh`
- **THEN** it prints an error and exits 2

### Requirement: Settings and environment checks
`dnw-doctor` SHALL compare the user's `~/.claude/settings.json` with `claude/settings.example.json` and warn for each hook command missing under its event and each `permissions.deny` entry missing, treating the home directory path and `~` as equal, and SHALL warn when `statusLine` is not set. It SHALL warn when the settings file is absent and `fail` when it is not valid JSON. It SHALL NOT modify the settings file. It SHALL `fail` when no global git `user.email` is set, `warn` when the shell rc files do not source `dotfiles.sh`, and `warn` for each of `gh`, `jq`, `git`, `node`, `uv`, `gitleaks` and `shellcheck` that is not on `PATH`.

#### Scenario: Gaps in the user's settings
- **WHEN** the user's settings lack the `Stop` hook, the `Bash(sudo:*)` deny rule and `statusLine`
- **THEN** three `warn settings` findings name them, each with a fix naming the settings key to add
- **AND** the settings file is byte-identical afterwards and the exit code is 0

#### Scenario: Absolute home path in a hook command
- **WHEN** the user's settings spell a hook command with the absolute home path where the example uses `~`
- **THEN** that hook is not reported missing

#### Scenario: Invalid settings JSON
- **WHEN** the settings file is not valid JSON
- **THEN** a `fail settings` finding is printed and the exit code is 1

### Requirement: Overlay checks
When an overlay directory exists, `dnw-doctor` SHALL report the number and names of overlay files in use, warn for each overlay file that shadows a repo file whose blob SHA differs from the one recorded in `.provenance` (showing the short SHAs, a `diff` fix and the advice to remove the file if it is not personal), warn once for overlay files that shadow a repo file but have no provenance row (fix: `install.sh --record-overlay`), warn for an overlay file on a non-overlayable path, and warn for an overlay file that is not under a known install location.

#### Scenario: Repo file changed since seeding
- **WHEN** an overlay file shadows `claude/commands/hc.md` and the repo's copy has changed since its provenance row was written
- **THEN** a `warn overlay` finding says it shadows a repo file that changed since it was seeded, with `repo <old7>..<new7>`

#### Scenario: Unrecorded overlay files
- **WHEN** overlay files shadow repo files and the overlay has no `.provenance` rows for them
- **THEN** one warning lists them and suggests `install.sh --record-overlay`

#### Scenario: Ignored overlay hook
- **WHEN** the overlay holds `claude/hooks/autonomy-gate.sh`
- **THEN** a `warn overlay ignored: claude/hooks/autonomy-gate.sh (not overlayable)` finding is printed

### Requirement: Apply preconditions
`dnw-apply [--repo DIR] [--dry-run]` SHALL apply only merged `main`. It SHALL exit 2 with an explanatory message, before installing anything, when: the directory is not a git work tree; the work tree has uncommitted changes (an untracked `overlay/` directory excepted); `git fetch origin` fails; the default branch of `origin` cannot be determined; the checkout is not on that default branch; the local default branch has commits that are not on `origin/<default>` (ahead or diverged); or the branch cannot be fast-forwarded. An unknown option SHALL also exit 2. With no `--repo` it SHALL use the checkout the script itself resolves to through symlinks.

#### Scenario: Dirty tree
- **WHEN** a tracked file in the checkout is modified
- **THEN** it exits 2 with `working tree not clean`, installs nothing and writes no applied-state file

#### Scenario: Not on the default branch
- **WHEN** the checkout is on a topic branch
- **THEN** it exits 2 with `not the default branch 'main'`

#### Scenario: Local commits on main
- **WHEN** the local `main` has a commit that is not on `origin/main`, whether or not `origin/main` has moved
- **THEN** it exits 2 with a message that it will not merge or rebase, and local `main` is unchanged

### Requirement: Apply procedure and state
When the preconditions hold, `dnw-apply` SHALL fast-forward to `origin/<default>` with `--ff-only`; if no overlay directory exists and a `~/.dotfiles-backup/*` directory exists, seed the overlay once from the newest one; run `install.sh --no-deps` (adding `--copy` when the installed `autonomy-gate.sh` is a regular file rather than a link, and skipping upstream skills unless `DOTFILES_SKIP_UPSTREAM` says otherwise); run `dnw-doctor`; record the applied commit in `<state>/applied` (state being `${XDG_STATE_HOME:-~/.local/state}/do-no-work`); print the doctor output and a summary line `applied <old>..<new>, N files changed, overlay seeded yes|no, guard change yes|no, doctor F fail / W warn`; and exit with the doctor's exit code (0 or 1). `<old>` SHALL read `none` when no applied commit is recorded.

#### Scenario: First run
- **WHEN** `origin/main` is ahead of a clean local `main` and no applied commit is recorded
- **THEN** local `main` is fast-forwarded to `origin/main`, the files are installed, `<state>/applied` holds the new commit, the summary starts `applied none..`, and the exit code is 0 or 1 from the doctor

#### Scenario: Link or copy mode kept
- **WHEN** the existing install is in link mode (or in copy mode)
- **THEN** the apply reinstalls in the same mode

#### Scenario: Overlay seeded once
- **WHEN** no overlay directory exists and two backup directories exist
- **THEN** the overlay is seeded from the newest backup and the summary says `overlay seeded yes`
- **AND** a later run, with the overlay present, says `overlay seeded no` and leaves an edited overlay file alone

### Requirement: Guard change alert
`dnw-apply` SHALL treat `claude/hooks/autonomy-gate.sh`, `autonomy-toggle.sh`, `gate-self-merge.sh`, `openspec-autonomy.sh` and `claude/settings.example.json` as guard files. When any of them differs between the previously applied commit and the new one, it SHALL append `<UTC timestamp> <old7>..<new7> <files>` to `<state>/audit.log` and send the owner a message through `~/.claude/hooks/claude-notify.sh --message` that names the commits, the changed guard files and the audit path. It SHALL NOT alert on the first run, when no applied commit is recorded or the recorded one is unknown to the checkout. A missing notifier or a failed send SHALL print a warning, not stop the apply.

#### Scenario: Guard hook changed
- **WHEN** a merged change touches `claude/hooks/autonomy-gate.sh` after a recorded apply
- **THEN** `audit.log` gains one line naming that file, the owner message is sent, and the summary says `guard change yes`

#### Scenario: Non-guard change
- **WHEN** a merged change touches only `bin/`
- **THEN** no audit line is written and no message is sent

#### Scenario: Notification fails
- **WHEN** a guard file changed and the send fails
- **THEN** a `Discord notify failed` warning is printed, `audit.log` still has the line, and the applied commit is recorded

### Requirement: Dry run
`dnw-apply --dry-run` SHALL run the same preconditions (including the fetch), print `dry run: nothing written` and the plan (whether it would fast-forward, seed the overlay, install in link or copy mode and how many files changed, and whether a guard file changed), and exit 0 without fast-forwarding, installing, seeding, writing state or sending a message.

#### Scenario: Dry run with pending changes
- **WHEN** `origin/main` is ahead and a backup directory exists but no overlay
- **THEN** the plan lists `would fast-forward: <old>..<new>`, `would seed overlay: yes`, `would install: link mode` and `guard change: no`
- **AND** local `main`, the home directory and the state directory are unchanged

### Requirement: Owner message
`claude-notify.sh --message <text>` SHALL send `<text>` as one direct message to the owner through the Discord bot configured in the env file (`~/.config/claude-notify/env` unless `CLAUDE_NOTIFY_ENV` says otherwise) and exit 0 only when the send succeeded. It SHALL exit 2 when no text is given and 1 when the env file is missing or the send fails. The bot token SHALL be passed to `curl` through its config on stdin, never on the command line.

#### Scenario: Successful send
- **WHEN** the env file holds a bot token and owner ID and the Discord endpoints answer
- **THEN** the text is posted as the message content and the exit code is 0
- **AND** the token appears in no `curl` argument

#### Scenario: No text
- **WHEN** `--message` is given an empty or no argument
- **THEN** it prints `--message needs text` and exits 2

#### Scenario: No env file
- **WHEN** the env file does not exist
- **THEN** it exits 1 without sending
