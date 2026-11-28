## Why
The guards matched text inside heredoc bodies. Agents write files and run Python through heredocs constantly, so docs that mention `gh pr merge`, a `'''` the shell tokenizer cannot parse, or a commit message that mentions a bypass flag made `autonomy-gate` and `gate-self-merge` prompt or deny on harmless commands. The owner wants the guards to stay but prompt only when a command can actually hit one.

## What Changes
- `push-guard.py --strip` prints the command with data heredoc bodies removed; bodies on a line that names a shell are kept.
- `autonomy-gate` runs its hook-bypass and push/merge checks on the stripped command, calls the normaliser only when push/merge keywords remain, and asks on a tokenize failure only when a bypass is mentioned.
- `gate-self-merge` matches the stripped command and builds its JSON with `jq`.
- Known limit, unchanged in kind: code the gate cannot see as shell is opaque, as `python3 script.py` already is. That covers an interpreter heredoc (`python3 - <<EOF`) and a file written by a heredoc and run later (`cat > f <<EOF ... EOF; sh f`). The auto-mode classifier still sees the full command.

## Impact
- Spec: `agent-guardrails` (new requirement).
- Code: `claude/hooks/push-guard.py`, `claude/hooks/autonomy-gate.sh`, `claude/hooks/gate-self-merge.sh`, `tests/hooks_test.sh`, `docs/REFERENCE.md`.
