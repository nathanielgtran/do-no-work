## MODIFIED Requirements

### Requirement: Push and merge block in less mode
`autonomy-gate` SHALL pass every Bash command to `push-guard.py` (in the same directory) and act on its verdict. At every dial level it SHALL answer `deny` to a push or merge whose target is `main` or `master`, including via a refspec (`HEAD:main`, `x:refs/heads/main`), `-C <dir>`, `-c k=v`, an environment prefix, `command`, `bash -c`, or after `cd ... &&`, unless the repository's top level is listed in `push-main-allow.txt` next to `push-guard.py`. When the dial is `less` it SHALL also answer `deny` to any `git push`, `gh ... pr ... merge` or `gh ... api ... merge`. When `push-guard.py` cannot decide or fails to run, `autonomy-gate` SHALL answer `ask`. It SHALL make no decision on other commands.

#### Scenario: Push forms blocked
- **WHEN** the dial is `less` and the command is `git push origin x`, `git -C /x push`, `cd /x && git push`, `VAR=1 git push`, `command git push` or `git -c a=b push origin x`
- **THEN** each is denied with a reason that says push is blocked and to say `go full`

#### Scenario: Merge forms blocked
- **WHEN** the dial is `less` and the command is `gh pr merge 5 -R o/r` or `gh api repos/o/r/pulls/5/merge -X PUT`
- **THEN** each is denied

#### Scenario: Push to main blocked at full
- **WHEN** the dial is `full` and the command is `git push origin HEAD:main`, `git -C /x push -u origin main`, `git -c a=b push origin main` or `cd /x && git push origin master`
- **THEN** each is denied

#### Scenario: Other commands and full mode
- **WHEN** the dial is `less` and the command is `git status`, `git pull`, `gh pr view 5`, `gh pr create` or `git push-all`; or the dial is `full` and the command is `git push origin x` or `gh pr merge 5 --squash`
- **THEN** no decision is made

### Requirement: Tamper guard
At every dial level, `autonomy-gate` SHALL answer `deny` to a Bash command that writes to the autonomy-level file, and `ask` to one that writes to anything under `~/.claude/hooks/` or under a `do-no-work/claude/hooks` directory (the conventional checkout location), so a hook change needs the owner's approval at a prompt. A write is a redirection target (`>`, `>>`, `&>`, `2>>`), an operand of `tee`, `cp`, `mv`, `rm`, `ln`, `install`, `chmod`, `chown`, `touch`, `truncate`, `shred` or an editor, an `of=` operand of `dd`, a file of `sed -i`, a command string passed to `bash -c`, `sh -c` or `eval`, a script string passed to an interpreter (`python`, `node`, `ruby`, `perl` and similar) with `-c` or `-e`, or a relative target after a `cd` into one of those directories. A literal `$HOME/.claude/...` target SHALL be denied because `$HOME` cannot be resolved statically. A command that writes a hook and also mentions the autonomy-level file SHALL be denied. Reading, listing, diffing or copying out of those paths SHALL NOT be denied. A command that cannot be parsed SHALL be answered with `ask`.

#### Scenario: Dial writes denied
- **WHEN** the command is `echo less > ~/.claude/autonomy-level`, `echo less | tee ~/.claude/autonomy-level` or `bash -c 'echo less > ~/.claude/autonomy-level'`
- **THEN** each is denied with a reason that refuses to write the dial from Bash

#### Scenario: Hook writes ask
- **WHEN** the command is `cp x ~/.claude/hooks/autonomy-gate.sh`, `sed -i 's/a/b/' ~/.claude/hooks/autonomy-gate.sh`, `cd ~/.claude/hooks; sed -i s/a/b/ autonomy-gate.sh` or `echo x > ~/Github/do-no-work/claude/hooks/gate-self-merge.sh`
- **THEN** each is answered with `ask` and a reason that it writes a guard hook

#### Scenario: Reads allowed
- **WHEN** the command is `cat ~/.claude/autonomy-level`, `grep -n x ~/.claude/hooks/*.sh`, `cp ~/.claude/hooks/autonomy-gate.sh /tmp/copy.sh` or `bash ~/.claude/hooks/autonomy-gate.sh < input.json`
- **THEN** no decision is made

#### Scenario: Unparseable input
- **WHEN** the hook's stdin is not valid JSON
- **THEN** it answers `ask` with a reason that the command could not be parsed

### Requirement: Settings example wiring
`claude/settings.example.json` SHALL wire `autonomy-gate`, `gate-self-merge` and `openspec-autonomy` under `PreToolUse` for `Bash`, `protect-lint-config` under `PreToolUse` for `Edit|Write|MultiEdit`, `autonomy-toggle` under `UserPromptSubmit`, `go-check` under `PostToolUse` for `Write|Edit`, and `stop-gate` under `Stop`. It SHALL carry `permissions.deny` entries for `rm`, `sudo`, `git push origin main`, `git push origin master`, `git push --force`, `gh pr merge --admin`, `Edit` of `~/.claude/settings.json` and `~/.claude/settings.local.json`, and `Edit` and `Write` of `~/.claude/autonomy-level`, and `permissions.ask` entries for `Edit` and `Write` of `~/.claude/hooks/**` and `~/Github/do-no-work/claude/hooks/**`. `dnw-doctor` compares a user's settings against this file.

#### Scenario: Doctor against its own example
- **WHEN** a user's settings are a copy of `claude/settings.example.json`
- **THEN** `dnw-doctor` reports no missing hook or deny rule

## ADDED Requirements

### Requirement: Git hook bypass block
At every dial level, `autonomy-gate` SHALL answer `deny` to a Bash command that skips git hooks: `--no-verify` on any git subcommand, `-n` (alone or in a short-flag cluster) on `git commit`, `core.hooksPath` set with `git -c` or `git config`, or a `SKIP=` or `HUSKY=` environment prefix. It SHALL match whole shell tokens, so a quoted argument that only mentions one of these is not a match. A command that cannot be tokenized SHALL be answered with `ask`.

#### Scenario: Bypass forms blocked
- **WHEN** the command is `git commit --no-verify -m x`, `git commit -nm x`, `git -C /x commit -n -m x`, `git push --no-verify origin x`, `SKIP=gitleaks git commit -m x`, `HUSKY=0 git commit -m x`, `git -c core.hooksPath=/dev/null commit -m x` or `git config core.hooksPath /tmp/none`
- **THEN** each is denied

#### Scenario: Mentions and unrelated short flags allowed
- **WHEN** the command is `git commit -m "block --no-verify and -n bypasses"`, `git push -n origin x` or `git commit -am x`
- **THEN** no decision is made
