## Why
`push-guard.py`, the shared push/merge normaliser, was written for `autonomy-gate` but never committed, so nothing calls it. At the `full` dial the only push-to-main barrier is prefix deny rules, which miss `git push origin HEAD:main`, `git -C x push origin main` and `git -c a=b push origin main`. Separately, nothing stops `git commit --no-verify`, `-n`, `core.hooksPath` or `SKIP=`/`HUSKY=`, so one flag skips the gitleaks and commit-msg hooks.

## What Changes
- Ship `claude/hooks/push-guard.py` and have `autonomy-gate` call it on every Bash command: deny push or merge to `main`/`master` at every dial level (repos listed in `~/.claude/hooks/push-main-allow.txt` excepted), and deny any push or merge in `less` mode. A guard failure answers `ask`.
- `autonomy-gate` denies git hook bypasses at every dial level, matching tokens so a quoted commit message that mentions a flag is not a match.
- Hook edits move from deny to ask: the tamper guard answers `ask` for writes under the hooks directories (the dial stays `deny`), and the example settings move the hook `Edit`/`Write` rules from `permissions.deny` to `permissions.ask`, so Claude can change a hook when the owner approves the prompt. Merged hooks still only go live through PR, review and `dnw-apply`.
- `autonomy-gate` builds its JSON with `jq` so reasons with quotes stay valid.
- The installer's managed set gains `claude/hooks/*.py`.

## Impact
- Specs: `agent-guardrails` (push/merge requirement rewritten, new hook-bypass requirement), `installer` (managed set).
- Code: `claude/settings.example.json`, `claude/hooks/autonomy-gate.sh`, `claude/hooks/push-guard.py`, `scripts/install-manifest.sh`, `install.sh`, `tests/hooks_test.sh`, `docs/REFERENCE.md`.
- `autonomy-gate` now runs `python3` on every Bash call (about 30 ms).
