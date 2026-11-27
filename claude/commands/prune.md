Prune documentation across all active repos and personal-kb to reduce context token overhead. Usage: /prune

Run this periodically (every few sessions) or when startup context is getting heavy.

## What gets pruned

### personal-kb
- `daily-log.md` — rolling 3-day window. Archive entries older than 3 days to `daily-log-archive.md` (prepend, newest first). Keep file under 200 lines.
- `todo.md` — remove all `[x]` completed items from `## to do` and `## high priority`. Append them to `todo-archive.md` under a `## archived YYYY-MM-DD` heading. Keep only `[ ]` items in the active file.
- `notes.md` — trim `## current work` to one line per project: `- project: vX.Y live. Pending: item1, item2`. Drop implementation detail, keep version + key pending items.

### Each active repo with a PLAN.md
- Strip the task checklist body from all **completed phases** — replace with a single `(done — brief summary)` line.
- Keep the full task list only for the **current phase** and **next phase**.
- Keep `## Current State`, `## Future / Nice to Have`, and any phase that is not yet started.

### Each active repo with a CHANGELOG.md
- Verify `## Unreleased` only contains items not yet in a tagged release. If a release has been cut, move those entries into the versioned block.
- No other changes to CHANGELOG.

### Each active repo with a CLAUDE.md
- Remove references to deleted files (check they still exist with Glob before keeping).
- Remove stale "known gotchas" entries that describe bugs already fixed.
- Update version numbers and secret names if stale (cross-check with sites/*.yml and deploy workflows).

## Steps

### 1. Gather context
Identify which repos have been touched recently from the daily-log and notes. Only prune repos that are active — don't touch repos with no recent activity.

### 2. personal-kb pruning
Read daily-log.md, find the cutoff line (entry for date = today - 3 days), archive everything older. Rewrite todo.md keeping only `[ ]` items. Trim notes.md current-work lines.

### 3. PLAN.md pruning (each active repo in parallel)
For each done phase: replace the full checklist with `## Phase N: Title (done — one-sentence summary)`. Keep current + next phases intact.

### 4. CHANGELOG.md check (each active repo in parallel)
Verify Unreleased section is accurate. Flag anything misplaced but don't restructure if unclear.

### 5. CLAUDE.md cleanup (each active repo in parallel)
Quick pass: dead file references, stale gotchas, outdated secrets/versions. Make targeted edits only — don't restructure.

### 6. Commit all changes
- personal-kb: `git add -A && git commit -m "prune: YYYY-MM-DD rolling window + todo + notes" && git push`
- Each repo: `git add PLAN.md CHANGELOG.md CLAUDE.md && git commit -m "chore: prune docs for context efficiency" && git push`

### 7. Report
Show line counts before/after for the major files and list what was changed.
