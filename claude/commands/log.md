Update all documentation, logs, plans, and tracking files. Usage: /log

Run this after completing work to ensure everything is synced.

## Steps

Run all steps using parallel sub-agents where possible to minimize time.

### 1. Gather context

Read the current conversation to understand what was done this session. Identify:
- Which repos were touched
- What PRs were created/merged
- What features/fixes were shipped
- What was deployed
- Any issues found or decisions made

### 2. Update daily-log.md

File: `~/Github/personal-kb/daily-log.md`

- If today's entry doesn't exist, create it with the date heading `## YYYY-MM-DD`
- Add/update `### goals` if goals were set
- Add work items under `### work`, grouped by project (`#### repo-name`)
- Each item: `- [repo-name] brief description of what was done`
- Include PR numbers, version numbers, ticket IDs where applicable
- Don't duplicate items already in today's entry

### 3. Update notes.md

File: `~/Github/personal-kb/notes.md`

- Update `## current work` section with current state of each active project (version, what's live, what's pending)
- Update `## active prs` — add new PRs, remove merged ones
- If meeting notes were processed, ensure they're under `## meeting notes`

### 4. Update todo.md

File: `~/Github/personal-kb/todo.md`

- Move completed items from `## to do` / `## in progress` to `## completed` with checkmark
- Add any new tasks discovered during work
- Format: `- [x] Brief description (version, PR #N)`

### 5. Update PLAN.md in each touched repo

For each touched repo that has a `PLAN.md`:
- `## Current State` = repo-level, main's view (3 lines: phase, next, blocked). No "PR open" lines — branch state goes in HANDOFF.
- Remove completed items from `## What's pending`; add new ones.

### 5b. Write HANDOFF.md per touched worktree

Skip if the repo is personal-kb. Overwrite `<worktree>/.claude/HANDOFF.md` (gitignored globally, <=25 lines). Only what git can't tell: in-flight, dead ends, unverified, exact next step. No secrets, no token-bearing URLs. `commit:` = current HEAD short sha (7 chars) — the SessionStart hook flags STALE on mismatch.

```
# HANDOFF <branch> <YYYY-MM-DD HH:MM>
commit: <sha7>
change: openspec/changes/<id>/ | none
pr: #N open|merged | none

## in-flight
- <half-done thing + file>

## dead ends
- <approach> — <why it failed>

## unverified
- <claim not yet checked>

## next
1. <exact first command or edit>
```

### 6. Update CHANGELOG.md in each touched repo

For each repo that has a `CHANGELOG.md`:
- Verify the latest entry matches what was actually shipped
- Ensure the incrementing ID is correct (check highest existing ID)

### 7. Update CLAUDE.md in each touched repo

For each repo that has a `CLAUDE.md`:
- Update `Current highest ID` if CHANGELOG entries were added
- Update `## Pending work` section if items were completed or added
- Update any stale references (container counts, version numbers, etc.)

### 8. Update memory if needed

If any non-obvious project context, user preferences, or reference info was learned during the session, save it to memory at your Claude Code project memory directory (`~/.claude/projects/<project>/memory/`).

### 9. Commit and push personal-kb

```bash
cd ~/Github/personal-kb
git add -A
git commit -m "updated logs for YYYY-MM-DD"
git push
```

### 10. Report

Present a brief summary of what was updated:
- Files modified
- Items added/moved
- Any stale info that was cleaned up
