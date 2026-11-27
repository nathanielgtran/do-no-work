---
name: backlog
description: Regenerate the fleet backlog rollup — a single read-only dashboard of every active repo's open TODO.md items plus open GitHub issues, written to personal-kb/backlog.md and indexed by engraph. Use when the user asks "what's open", "what's on my plate", "backlog", "where are we across repos", "refresh the backlog", or after finishing/discovering work so the rollup stays current. Also run before a cross-repo planning or standup session.
---

# backlog

One queryable view of everything open across the fleet, without hand-syncing a second list.

## Model (why it works)

- **Source of truth stays with the code.** Each repo's `TODO.md` holds its own open work as `- [ ]` lines; `[x]` done lines are ignored by the generator, so repo files can keep their history without cluttering the rollup.
- **Cross-repo / personal** items live in `personal-kb/todo.md`.
- **`personal-kb/backlog.md` is generated, never hand-edited.** It is a read-model. Editing it is pointless — the next run overwrites it. Fix the underlying repo `TODO.md` instead.
- engraph indexes `personal-kb/` so the rollup is semantically queryable (`mcp__engraph__search "open in myapp"`).

## Run

```bash
python3 ~/.claude/skills/backlog/generate.py         # full: repos + gh issues
python3 ~/.claude/skills/backlog/generate.py --no-gh  # fast: skip gh (offline)
```

The output is a hardlink into `~/engraph-vault/personal-kb/backlog.md`. To refresh the index run
`engraph-enqueue personal-kb/backlog.md` (instant, drained in the background). Do NOT
call `mcp__engraph__reindex_file` directly — it blocks 30s+ and times out.
If the vault copy ever desyncs (different inode), re-create the hardlink:

```bash
ln -f ~/Github/personal-kb/backlog.md ~/engraph-vault/personal-kb/backlog.md
```

## Rules

- Worktrees (`myapp-*`, `otherapp-*`, …) are skipped automatically — a worktree's `.git` is a file, a real repo's is a directory. Never scan them; they carry a stale copy of the same `TODO.md`.
- To ADD a task: append a `- [ ]` line to the relevant repo's `TODO.md` (or `personal-kb/todo.md` for cross-repo). Then regenerate.
- To CLOSE a task: flip `- [ ]` → `- [x]` in the repo `TODO.md` (keep the line as history) or open a real PR that removes it. Then regenerate.
- Do NOT put repo-scoped code tasks in `personal-kb/todo.md` — that reintroduces the drift this replaced.
- Keep IDs aligned with each repo's CHANGELOG `type-N` convention so todo ↔ changelog ↔ PR stay greppable.
