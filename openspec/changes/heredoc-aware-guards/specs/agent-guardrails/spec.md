## ADDED Requirements

### Requirement: Heredoc data bodies are not commands
Before matching, `autonomy-gate` and `gate-self-merge` SHALL remove the body of every heredoc whose line does not name a shell (`bash`, `sh`, `zsh`, `dash`, `ksh`, `ssh`, `eval`, `source` or `.`) anywhere in it, using `push-guard.py --strip`. A heredoc body on a line that names a shell SHALL be kept and checked as commands. Commands after a heredoc's terminator SHALL still be checked. `autonomy-gate` SHALL call the push and merge normaliser only when the stripped command contains `push`, `merge`, `api`, `graphql` or `update-ref`, and SHALL answer `ask` for a command it cannot tokenize only when that command mentions a git hook bypass.

#### Scenario: Data heredocs pass
- **WHEN** the command writes a file with `cat > f <<'EOF'` whose body mentions `git commit --no-verify`, `SKIP=gitleaks` or `git push origin main`, or runs `python3 - <<'PY'` with an unbalanced `'''` in the body, or `cd /x && cat > d.md <<EOF` whose body mentions `gh pr merge 5`
- **THEN** neither gate makes a decision

#### Scenario: Shell-fed heredocs and trailing commands still checked
- **WHEN** the command is `bash <<EOF` or `cat <<EOF | sh` with `git push origin main` in the body, or a data heredoc followed by `git push origin main` or `git commit --no-verify -m x` after the terminator
- **THEN** `autonomy-gate` answers `deny`
