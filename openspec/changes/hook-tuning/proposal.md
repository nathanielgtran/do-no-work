## Why
The inline `gh pr create` hook in the settings example tells the session to review its own PR and apply `REVIEWED`. The `claude-review` workflow now reviews and applies the label, and the session must never apply it. `go-check` runs `go test` for up to 90 s synchronously on every `.go` edit, duplicating `stop-gate`. `stop-gate` reruns the full check on every turn end while the tree is dirty, including turns that changed nothing.

## What Changes
- Add `claude/hooks/post-pr-create.sh` (PostToolUse, `if: Bash(gh pr create:*)`) replacing the inline hook: it tells the session to wait for the CI review when the repo has a `claude-review` workflow, otherwise to spawn one `reviewer` agent and leave the label and merge to the owner. It never tells the session to apply `REVIEWED`.
- `go-check` stops running `go test` (stop-gate keeps tests), adds a `gofmt -l` check, and is wired `async` + `asyncRewake`: silent on success, a clipped report on stderr with exit 2 on failure.
- `stop-gate` stores a fingerprint of the working tree after a passing run and skips the check when the next stop sees the same fingerprint. A failing run is never stored.
- Settings example: wire `post-pr-create`, run `go-check` on `Write|Edit|MultiEdit` as `async`/`asyncRewake`, add `onFailure: block` to the `autonomy-gate` and `gate-self-merge` entries so a crashed guard blocks instead of letting the call through.

## Impact
- Specs: `agent-guardrails` (stop gate, go check, settings wiring modified; post-PR-create added).
- Code: `claude/hooks/post-pr-create.sh`, `go-check.sh`, `stop-gate.sh`, `claude/settings.example.json`, `tests/hooks_test.sh`, `tests/research_hooks_test.sh`, new `tests/go_check_test.sh`, `docs/REFERENCE.md`.
- Users re-merge the `hooks` block of the settings example by hand; `dnw-doctor` flags the new `post-pr-create` command. It compares commands only, not `if`, `async` or `onFailure`.
