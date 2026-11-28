## Why
The guards matched text inside heredoc bodies. Agents write files and run Python through heredocs constantly, so docs that mention `gh pr merge`, a `'''` the shell tokenizer cannot parse, or a commit message that mentions a bypass flag made `autonomy-gate` and `gate-self-merge` prompt or deny on harmless commands. The owner wants the guards to stay but prompt only when a command can actually hit one.

## What Changes
- `push-guard.py --strip` prints the command with data heredoc bodies removed; bodies on a line that names a shell are kept.
- `autonomy-gate` runs all its checks on the stripped command and calls the normaliser only when push, merge or hook-bypass keywords remain (quotes removed first, so `git "pu"sh` still counts).
- `gate-self-merge` matches the stripped command and builds its JSON with `jq`.
- Hook-bypass detection moves from a bash token scan into `push-guard.py`, which already recurses through `bash -c`, `eval`, `$(...)` and aliases. It adds `--no-verify` abbreviations, joined `-c`, `--config-env`, `GIT_CONFIG_*`, and limits `SKIP=`/`HUSKY=` to a git command's env prefix. `git update-ref` of main is a protected push. Backslash-newlines are joined.
- The tamper scan runs on the stripped command (a 99 KB doc heredoc took 69 s and timed out the hook; now 0.13 s). Missing `jq` or `python3` answers `ask` instead of failing open.
- `openspec-autonomy` no longer auto-approves a backgrounded `&`, multi-line commands, or git options that run or write a path.
- Found by an adversarial review of about 350 cases and three claude-review rounds.
- Known limit, unchanged in kind: code the gate cannot see as shell is opaque, as `python3 script.py` already is. That covers a dial write from inside an interpreter heredoc, an interpreter heredoc (`python3 - <<EOF`) and a file written by a heredoc and run later (`cat > f <<EOF ... EOF; sh f`). The auto-mode classifier still sees the full command.

## Impact
- Specs: `agent-guardrails` (two new requirements, OpenSpec auto-approval modified), `install-sync` (`push-guard.py` is a guard file).
- Code: `claude/hooks/push-guard.py`, `claude/hooks/autonomy-gate.sh`, `claude/hooks/gate-self-merge.sh`, `claude/hooks/openspec-autonomy.sh`, `bin/dnw-apply`, `tests/hooks_test.sh`, `docs/REFERENCE.md`.
