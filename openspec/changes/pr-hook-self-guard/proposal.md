## Why
`post-pr-create` relies on the settings `if: Bash(gh pr create:*)` filter. In practice Claude Code runs the hook for Bash calls that never created a PR (for loops, `ssh '...'`, heredocs), so sessions get "A PR was just created ... spawn a reviewer" after unrelated commands and either ignore it or spawn needless reviewers.

## What Changes
- `post-pr-create` checks the call itself: it prints context only when `tool_input.command` contains a `gh pr create` invocation and the tool response contains a `/pull/<N>` URL. Otherwise it exits 0 with no output.
- The `if` filter in the settings example stays as the first, cheap filter.

## Impact
- Specs: `agent-guardrails` (post-PR-create self-guard added).
- Code: `claude/hooks/post-pr-create.sh`, `tests/hooks_test.sh`, `changelog.d` fragment, `docs/hooks.md`.
