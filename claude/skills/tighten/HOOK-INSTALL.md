# Wiring /tighten into the PR auto-review hook

Nothing here is applied automatically. `~/.claude/settings.json` and `~/.claude/hooks/*`
are guarded, so you edit them by hand.

## What exists today

`~/.claude/settings.json` has a `PostToolUse` hook on `Bash` that greps the command for
`gh pr create` and returns `additionalContext` telling the current session to spawn a
sonnet reviewer, fix, label `REVIEWED`, watch CI and squash-merge. It runs in the same
session, not headless, and only fires when `gh pr create` goes through Claude's Bash tool.

## The change

Prepend one step to that `additionalContext` string so tighten runs before the reviewer
and the review sees the final diff. Only the string changes; matcher, shape and the
second hook entry stay as they are.

Current text starts with:

```
A PR was just created. Automatically spawn a sub-agent to review the PR changes ...
```

Replace the opening with:

```
A PR was just created. STEP 1: invoke the tighten skill on it now (Skill tool, skill
"tighten", args "<pr-number>") and wait for it to finish; it is single-pass, never asks
questions, and guards itself with the tightened label, so never run it twice. If it
reports pushed commits the branch has moved: fetch before reviewing. STEP 2: only after
tighten has returned, spawn a sub-agent to review the PR changes ...
```

and keep the rest of the existing text unchanged (sonnet reviewer, REVIEWED label, CI
watch, squash merge).

The `gh pr create` hook entry, with the new string in place, for copy and paste. The
JSON is one line in settings.json; it is wrapped here for reading:

```json
{
  "type": "command",
  "command": "jq -r '.tool_input.command' | { read -r cmd; echo \"$cmd\" | grep -q 'gh pr create' && echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"A PR was just created. STEP 1: invoke the tighten skill on it now (Skill tool, skill tighten, args <pr-number>) and wait for it to finish; it is single-pass, never asks questions, and guards itself with the tightened label, so never run it twice. If it reports pushed commits the branch has moved: fetch before reviewing. STEP 2: only after tighten has returned, spawn a sub-agent to review the PR changes. The review sub-agent MUST use model sonnet (Agent tool with model: sonnet). Run git diff against the base branch. Review for: bugs, security issues, missing tests, code quality problems, and CLAUDE.md rule compliance. Present a concise review summary to the user. If the review passes (no must-fix issues), apply the REVIEWED label: gh pr edit --add-label REVIEWED. If issues are found, fix them, push fix commits, then re-review and apply the label only once all issues are resolved. After applying the label, do NOT merge immediately. First wait for CI to pass: run gh pr checks <pr-number> --watch --fail-fast and only once the ci check is green, merge with gh pr merge --squash --delete-branch. If CI fails, fix the issues, push, and re-check; never merge a red PR.\"}}' || true; }",
  "statusMessage": "Checking for PR creation..."
}
```

## Why this ordering is safe enough

- Tighten's own writes are `git push`, `gh pr edit` and `gh pr comment`. None of them
  match `gh pr create`, so the hook never re-fires on tighten's work.
- Tighten removes `REVIEWED` whenever it pushes, so a review label can never predate a
  tighten commit.
- The `tightened` label and the `<!-- tighten:pass -->` comment marker make a second
  invocation a no-op.
- `gh pr create` is not blocked: the hook returns at once and the work happens in the
  model's next turns, exactly as the review does today.

## Known gap (not fixed here)

`~/.claude/hooks/gate-self-merge.sh` allows `gh pr merge` when the `REVIEWED` label is
present and CI is green. It does not check that the label is newer than the head
commit, so any push after labelling (by tighten or by anyone) merges with a stale label.
Tighten narrows this by stripping `REVIEWED` on push. Closing it for every push would
mean comparing the `labeled` timeline event with the head commit date in that script.
Left as a separate decision.

## Check it works without touching a real PR

```
bash ~/.claude/skills/tighten/tests/tier_test.sh
bash ~/.claude/skills/tighten/tests/preflight_test.sh
bash ~/.claude/skills/tighten/scripts/sync-check.sh
```
