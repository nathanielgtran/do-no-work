# installer Specification

## Purpose
`install.sh` (macOS, Linux, WSL) and `install.ps1` (Windows) put the repo's shell and git config, CLI scripts, Claude Code hooks, commands, agents and skills into the user's home, and let a personal overlay replace or add files without touching the repo. They never edit Claude settings.

## Requirements

### Requirement: Placement mode
`install.sh` SHALL place every managed file as a symlink into the checkout by default and as a copy when `--copy` is given. The managed set is: `home/gitconfig`, `home/gitignore_global`, `home/ohmyposh-theme.json` and `home/bashrc.d/dotfiles.sh` under the home directory; each `bin/*` file in `~/.local/bin`; each `claude/hooks/*.sh` in `~/.claude/hooks`; each `claude/commands/*.md` in `~/.claude/commands`; each `claude/agents/*.md` in `~/.claude/agents`; and each `claude/skills/<name>/` directory in `~/.claude/skills/<name>`. Before placing, it SHALL make `bin/*` and `claude/hooks/*.sh` executable in the checkout.

#### Scenario: Link mode
- **WHEN** the user runs `install.sh --no-deps` into an empty home
- **THEN** `~/.gitconfig` is a symlink to the checkout's `home/gitconfig`
- **AND** `~/.claude/skills/<name>` is a symlink to the whole skill directory
- **AND** `~/.local/bin/safe-worktree-remove` is executable

#### Scenario: Copy mode
- **WHEN** the user runs `install.sh --no-deps --copy`
- **THEN** every managed file is a regular file, not a symlink

#### Scenario: Unknown flag
- **WHEN** the user passes a flag `install.sh` does not define
- **THEN** it prints `unknown flag: <flag>` to stderr and exits 2 without installing anything

### Requirement: Backup and idempotence
When a destination exists and is not already what the install would produce, `install.sh` SHALL move it to `~/.dotfiles-backup/<timestamp>/` under its path relative to the home directory before replacing it, and log the move. A rerun in which every destination already matches SHALL create no backup.

#### Scenario: Differing file is backed up
- **WHEN** `~/.claude/commands/log.md` exists with content that differs from the repo file and the user runs `install.sh --no-deps`
- **THEN** the old file is moved to `~/.dotfiles-backup/<timestamp>/.claude/commands/log.md`
- **AND** a `backed up` line names both paths

#### Scenario: Rerun in either mode
- **WHEN** the user runs `install.sh --no-deps` twice with the same mode
- **THEN** the second run creates no `~/.dotfiles-backup` directory

#### Scenario: Linked skill directory becomes per-file
- **WHEN** a skill directory was linked whole and an overlay file for that skill now exists
- **THEN** the old directory link is moved to the backup, and the skill directory is recreated as a real directory with one placed file per skill file

### Requirement: Personal overlay
`install.sh` SHALL read an overlay rooted at `$DOTFILES_OVERLAY` (default `~/.config/do-no-work/overlay`) that mirrors repo paths. An overlay file SHALL replace the repo file at the same relative path. An overlay-only file (one with no repo counterpart) under `bin/`, `claude/commands/`, `claude/agents/`, `claude/skills/` or `home/bashrc.d/` SHALL be installed as well. The overlay SHALL NOT modify the checkout.

#### Scenario: Overlay replaces and adds
- **WHEN** the overlay holds `claude/commands/hc.md` (a repo file) and `claude/commands/mine.md` (not in the repo)
- **THEN** `~/.claude/commands/hc.md` and `~/.claude/commands/mine.md` hold the overlay content
- **AND** `git status` in the checkout shows no change

#### Scenario: Skill file overlaid, siblings kept
- **WHEN** the overlay holds only `claude/skills/call/SKILL.md`
- **THEN** `~/.claude/skills/call/SKILL.md` is the overlay file and every other file of that skill comes from the repo
- **AND** other skills stay linked whole

#### Scenario: Overlay bashrc.d file
- **WHEN** the overlay holds `home/bashrc.d/local.sh`
- **THEN** it is installed as `~/.config/dotfiles/local.sh`

### Requirement: Paths an overlay cannot replace
An overlay file at `claude/hooks/*`, `claude/settings.example.json`, `claude/CLAUDE.md.example`, `install.sh`, `scripts/*`, `.github/*`, or any test path (`tests/*`, `*/tests/*`, `*_test.*`, `test_*.py`) SHALL be ignored at install time. `scripts/install-manifest.sh` SHALL print `install-manifest: ignoring overlay/<path> (not overlayable); using the repo file` to stderr and use the repo file, or nothing if the repo has none. The deny list SHALL live in one place, `scripts/overlay-lib.sh`.

#### Scenario: Hand-placed overlay hook
- **WHEN** the overlay holds `claude/hooks/autonomy-gate.sh`
- **THEN** the installed `~/.claude/hooks/autonomy-gate.sh` links to the repo's hook
- **AND** the warning above is printed

#### Scenario: Overlay-only hook
- **WHEN** the overlay holds `claude/hooks/new-hook.sh` and the repo has no such file
- **THEN** it is not installed

### Requirement: Seeding the overlay
`install.sh --seed-overlay` (reading the home directory) and `install.sh --seed-overlay-from DIR` (reading a backup directory such as `~/.dotfiles-backup/<timestamp>`) SHALL copy into the overlay each installed file that differs from the repo file it maps to, and then exit without installing anything. It SHALL skip a file identical to the repo, a file with no repo counterpart, and a non-overlayable path (printing `skip (not overlayable): <path>`). It SHALL NOT overwrite a file already in the overlay (logging `kept existing overlay/<path>`). It SHALL record a provenance row for each copied file, print `seeded: <path>` for each, and end with a reminder to delete any seeded file that is not personal.

#### Scenario: Seed from a backup
- **WHEN** a backup holds a changed `commands/hc.md`, an unchanged `commands/log.md`, a changed `hooks/autonomy-gate.sh` and an unmapped `commands/not-in-repo.md`
- **THEN** only `claude/commands/hc.md` is copied into the overlay
- **AND** `skip (not overlayable): claude/hooks/autonomy-gate.sh` and `seeded: claude/commands/hc.md` are printed
- **AND** no file is installed into the home directory

#### Scenario: Existing overlay file wins
- **WHEN** the overlay already holds `claude/commands/hc.md` and the backup holds a different one
- **THEN** the overlay file is unchanged

#### Scenario: Missing seed directory
- **WHEN** `--seed-overlay-from` has no argument, or names a directory that does not exist
- **THEN** it prints an error and exits 2

### Requirement: Overlay provenance
Each seeded file SHALL get one row `<path><TAB><repo blob SHA><TAB><YYYY-MM-DD>` in `<overlay>/.provenance`, never a second row for the same path. `install.sh --record-overlay` SHALL add a row, printing `recorded: <path>`, for each overlay file that shadows a repo file and has none, SHALL skip overlay-only and non-overlayable files, and SHALL exit without copying or installing anything. A plain install SHALL NOT write provenance rows.

#### Scenario: Record backfills rows
- **WHEN** the overlay holds `claude/commands/hc.md` (shadowing), `claude/commands/brand-new.md` (overlay-only) and `claude/hooks/go-check.sh` and the user runs `install.sh --record-overlay`
- **THEN** `.provenance` gains a row for `claude/commands/hc.md` only, holding the repo file's current blob SHA

#### Scenario: Plain install records nothing
- **WHEN** the user runs `install.sh --no-deps` with a pre-existing overlay that has no `.provenance`
- **THEN** no `.provenance` file is created

### Requirement: First-install side files
`install.sh` SHALL create `~/.claude/autonomy-level` containing `full` only if that file is absent, SHALL copy `claude/CLAUDE.md.example` to `~/CLAUDE.md` only if that file is absent, and SHALL NOT create or modify `~/.claude/settings.json` or `~/.claude/settings.local.json`. It SHALL print a reminder to merge `claude/settings.example.json` into the user's settings by hand and to run `dnw-doctor`.

#### Scenario: Existing files preserved
- **WHEN** `~/CLAUDE.md`, `~/.claude/settings.json` and `~/.claude/autonomy-level` (containing `less`) exist and the user runs `install.sh --no-deps`
- **THEN** all three are byte-for-byte unchanged
- **AND** the hook-wiring reminder is printed

#### Scenario: Fresh home
- **WHEN** the home directory has none of those files
- **THEN** `~/.claude/autonomy-level` contains `full` and `~/CLAUDE.md` is the template

### Requirement: Git identity
`install.sh` SHALL write `~/.gitconfig.local` (the file `home/gitconfig` includes) from `GIT_NAME` and `GIT_EMAIL`, else from a prompt or two lines on stdin, and SHALL leave an existing `~/.gitconfig.local` untouched. When no name is available it SHALL print `no git identity` guidance, create no file, and continue.

#### Scenario: Identity from environment
- **WHEN** `GIT_NAME` and `GIT_EMAIL` are set and `~/.gitconfig.local` is absent
- **THEN** it is created with that name and email in a `[user]` section

#### Scenario: No identity, no terminal
- **WHEN** neither variable is set and stdin is not a terminal and carries no lines
- **THEN** no `~/.gitconfig.local` is created, the hint is printed, and the rest of the install still runs

#### Scenario: Existing identity file
- **WHEN** `~/.gitconfig.local` exists
- **THEN** it is not modified

### Requirement: Shell rc wiring
`install.sh` SHALL append, once, a line that sources `~/.config/dotfiles/dotfiles.sh` to `~/.bashrc` on Linux and WSL, and to both `~/.bash_profile` and `~/.zshrc` on macOS.

#### Scenario: Repeated install
- **WHEN** the user runs `install.sh --no-deps` twice
- **THEN** each rc file contains the sourcing line exactly once

### Requirement: Dependencies and upstream skills
Unless `--no-deps` is given, `install.sh` SHALL install the package set through Homebrew when it is available (installing Homebrew first on macOS) and print the package list otherwise, then install the npm and uv command-line tools it names, logging and continuing when one fails. After placing files it SHALL install each skill repo listed in `skills-upstream.txt` with a pinned `skills` CLI version, logging and continuing on failure, unless `DOTFILES_SKIP_UPSTREAM=1` is set or `npx` is missing.

#### Scenario: Skip dependencies and upstream skills
- **WHEN** the user runs `install.sh --no-deps` with `DOTFILES_SKIP_UPSTREAM=1`
- **THEN** no package manager or `npx` is invoked and the files are still placed

### Requirement: Windows installer
`install.ps1` SHALL locate Git Bash in the Program Files, Program Files (x86) or per-user `Programs\Git` locations and throw when none exists, SHALL pass the repo path to Git Bash through environment variables converted with `cygpath` (throwing on a non-zero exit or empty result), SHALL run `install.sh --copy --no-deps` there and throw when it fails, and SHALL add an `oh-my-posh` init line to the PowerShell profile once. Unless `-NoDeps` is given it SHALL install packages with `winget` first and throw when `winget` is missing; a package that fails to install SHALL produce a warning, not a stop.

#### Scenario: Install into a throwaway home on Windows
- **WHEN** CI runs `install.ps1 -NoDeps` with `HOME` pointing at an empty directory
- **THEN** `~/.claude/hooks/autonomy-gate.sh` and `~/.local/bin/safe-worktree-remove` exist as regular files, not links

#### Scenario: Git Bash missing
- **WHEN** none of the three Git Bash locations holds `bash.exe`
- **THEN** the script throws `Git Bash not found` and installs nothing
