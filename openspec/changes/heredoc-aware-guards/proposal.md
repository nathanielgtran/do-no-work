## Why
The guards matched text inside heredoc bodies. Agents write files and run Python through heredocs constantly, so docs that mention `gh pr merge`, a `'''` the shell tokenizer cannot parse, or a commit message that mentions a bypass flag made `autonomy-gate` and `gate-self-merge` prompt or deny on harmless commands. The owner wants the guards to stay but prompt only when a command can actually hit one.

## What Changes
- `push-guard.py --strip` prints the command with data heredoc bodies removed; bodies on a line that names a shell are kept.
- `autonomy-gate` runs its hook-bypass and push/merge checks on the stripped command, calls the normaliser only when push/merge keywords remain, and asks on a tokenize failure only when a bypass is mentioned.
- `gate-self-merge` matches the stripped command and builds its JSON with `jq`.
- Known limit, unchanged in kind: an interpreter heredoc (`python3 - <<EOF`) is opaque, like `python3 script.py` already is; the auto-mode classifier still sees it.

## Impact
- Spec: `agent-guardrails` (new requirement).
- Code: `claude/hooks/push-guard.py`, `claude/hooks/autonomy-gate.sh`, `claude/hooks/gate-self-merge.sh`, `tests/hooks_test.sh`, `docs/REFERENCE.md`.
