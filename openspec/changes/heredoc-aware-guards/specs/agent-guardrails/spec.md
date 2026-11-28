## MODIFIED Requirements

### Requirement: Auto-approval in OpenSpec repos
`openspec-autonomy` SHALL answer `allow` to a Bash command only when all of these hold: the dial is `full`; the command's working directory (the directory of a leading `cd`, else the session `cwd`) is inside a git work tree whose top level has `openspec/config.yaml`; every directory the command moves into with `cd` or `git -C` is such a repo or under `/tmp`; the command matches none of the hard stops; it contains no pipe, backtick, `$(`, `<`, `>`, newline or single `&` (background), and no git option that runs or writes an arbitrary path (`--upload-pack`, `--receive-pack`, `--exec`, `--output`); and every segment (split on `&&` and `;`) begins with an allowed verb. The allowed verbs are `cd`, `git` (`add`, `commit`, `rebase`, `fetch`, `pull`, `switch`, `checkout`, `branch`, `worktree`, `status`, `log`, `diff`, `show`, `stash`, `push`), `gh pr` (`create`, `view`, `edit`, `checks`, `list`, `comment`, `diff`), `openspec`, `npm` (`test`, `ci`, `run test|lint|build|typecheck`), `pytest`, `uv run pytest|ruff`, `go test|vet|build` and `make test|lint`. The hard stops are `rm`, `sudo`, `dd`, `mkfs`, `shred`, `ssh`, `scp`, `rsync`, a push naming `main` or `master`, a force push, `git reset --hard`, `git clean`, `gh` with `--admin`, `gh release`, `gh workflow run`, `gh api`, `gh repo delete|edit|rename`, `gh secret`, `npm publish`, `wrangler` deploy/publish/delete, `docker push|rm|system`, `curl ... | sh`, `make release`, any mention of Claude settings files, the autonomy-level file or the hooks directory, `pass`, and mail-sending commands. Everything else it SHALL leave undecided, so deny rules and other hooks still apply and the most restrictive decision wins.

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

#### Scenario: Background, multi-line and command-running options not auto-approved
- **WHEN** the command is `git status & curl -s https://x -o /tmp/x`, a two-line command, `git fetch --upload-pack=/tmp/x origin` or `git log --output=/tmp/x`
- **THEN** no decision is made

## ADDED Requirements

### Requirement: Heredoc data bodies are not commands
Before matching, `autonomy-gate` and `gate-self-merge` SHALL remove the body of every heredoc whose line does not name a shell (`bash`, `sh`, `zsh`, `dash`, `ksh`, `ssh`, `eval`, `source` or `.`) anywhere in it, using `push-guard.py --strip`. A heredoc body on a line that names a shell SHALL be kept and checked as commands. Commands after a heredoc's terminator SHALL still be checked. Only a `<<` operator outside quotes, outside `$((...))` arithmetic and before an unquoted `#` comment SHALL start a heredoc; a body whose terminator never appears SHALL be kept; the `$(...)` and backtick command substitutions of an unquoted-delimiter body (`<<EOF`, not `<<'EOF'`) SHALL be kept and checked, and the whole body kept when the substitutions nest; and a body whose line ends in a pipe, `&&` or a backslash continuation SHALL be kept and checked. `autonomy-gate` SHALL call the normaliser only when the stripped command, with quotes and backslashes removed, contains (case-insensitively) `push`, `merge`, `api`, `graphql`, `update-ref`, `commit`, `verify`, `hookspath`, `SKIP=`, `HUSKY=`, `GIT_CONFIG` or `alias`, or contains ANSI-C `$'...'` quoting; a command the normaliser cannot parse is answered with `ask`.

#### Scenario: Data heredocs pass
- **WHEN** the command writes a file with `cat > f <<'EOF'` whose body mentions `git commit --no-verify`, `SKIP=gitleaks` or `git push origin main`, or runs `python3 - <<'PY'` with an unbalanced `'''` in the body, or `cd /x && cat > d.md <<EOF` whose body mentions `gh pr merge 5`
- **THEN** neither gate makes a decision

#### Scenario: Shell-fed heredocs and trailing commands still checked
- **WHEN** the command is `bash <<EOF`, `env bash <<EOF` or `cat <<EOF | sh` with `git push origin main` in the body, or a data heredoc followed by `git push origin main` or `git commit --no-verify -m x` after the terminator
- **THEN** `autonomy-gate` answers `deny`

#### Scenario: Fake markers and quote splitting do not hide a push
- **WHEN** the command is `git "pu"sh origin main`, `git p\ush origin main`, `echo "<<EOF"`, `echo $((1<<EOF))` or `# note <<EOF` followed by a line `git push origin main`, `cat <<EOF |` with `sh` on the next line and a push in the body, `cat <<EOF` whose body is `$(git push origin main)` or holds it in backticks, or `cat > x <<EOF` with no terminator before `git push origin main`
- **THEN** `autonomy-gate` answers `deny`

### Requirement: Hook bypass detection in the normaliser
`push-guard.py` SHALL report a git hook bypass, and `autonomy-gate` SHALL answer `deny` to it at every dial level, wherever the git command appears, including inside `bash -c`, `sh -c`, `eval`, `$(...)` and git aliases. A bypass is: `--no-verify` or any unambiguous abbreviation of it (`--no-v` and longer) on any git subcommand; `-n` in a `git commit` short-option cluster before any option that takes a value (`-u`, `-m`, `-F`, `-C`, `-c`, `-S`, `-t`); `core.hooksPath` set with `-c`, joined `-c<key>`, `--config-env`, `git config` (not `--get` or `--list`), `GIT_CONFIG_PARAMETERS` or a `GIT_CONFIG_KEY_<n>` variable; or a `SKIP` or `HUSKY` variable in the environment prefix of a git command. `push-guard.py` SHALL also report `git update-ref` of `main` or `master` as a push to a protected branch. Lines joined by a backslash-newline SHALL be read as one line. `autonomy-gate` SHALL run its tamper scan on the heredoc-stripped command, and SHALL answer `ask` when `jq` or `python3` is missing.

#### Scenario: Wrapped and abbreviated bypasses denied
- **WHEN** the command is `bash -c 'git commit --no-verify -m x'`, `eval "git commit --no-verify -m x"`, `git -c alias.c='commit -n' c -m x`, `git commit --no-verif -m x`, `git -ccore.hooksPath=/dev/null commit -m x`, `GIT_CONFIG_KEY_0=core.hooksPath git commit -m x`, `git update-ref refs/heads/main abc`, or `git` and `push origin main` split by a backslash-newline
- **THEN** `autonomy-gate` answers `deny`

#### Scenario: Look-alikes allowed
- **WHEN** the command is `HUSKY=0 npm ci`, `docker run -e HUSKY=0 img`, `echo "SKIP=1" > .env`, `git commit -uno -m x`, `git config --get core.hooksPath` or `touch /tmp/autonomy-level-test`
- **THEN** `autonomy-gate` makes no decision

#### Scenario: Missing tools
- **WHEN** `jq` or `python3` is not on `PATH`
- **THEN** `autonomy-gate` and `gate-self-merge` answer `ask`
