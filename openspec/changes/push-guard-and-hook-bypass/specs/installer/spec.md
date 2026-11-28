## MODIFIED Requirements

### Requirement: Placement mode
`install.sh` SHALL place every managed file as a symlink into the checkout by default and as a copy when `--copy` is given. The managed set is: `home/gitconfig`, `home/gitignore_global`, `home/ohmyposh-theme.json` and `home/bashrc.d/dotfiles.sh` under the home directory; each `bin/*` file in `~/.local/bin`; each `claude/hooks/*.sh` and `claude/hooks/*.py` in `~/.claude/hooks`; each `claude/commands/*.md` in `~/.claude/commands`; each `claude/agents/*.md` in `~/.claude/agents`; and each `claude/skills/<name>/` directory in `~/.claude/skills/<name>`. Before placing, it SHALL make `bin/*`, `claude/hooks/*.sh` and `claude/hooks/*.py` executable in the checkout.

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
