## Why
Autobuild picks features from the TODO list and lets builders grade their own work. Picks drift away from what the repo exists to move, and a loop gated only on its own Proof can merge weak work. The skill also still tells the agent to apply `REVIEWED` itself, which the `claude-review` CI check now owns.

## What Changes
- Scout reads `PLAN.md` `## Outcome` and `## Signals`, ranks candidates by outcome impact, and challenges one belief against raw signal data before picking.
- Each pick is raised against four questions (expert practice, rawest material, professional instruments, an outside check) with an unreasonable target; builders use the named instrument.
- Review checks each worktree for stray uncommitted agent edits and spawns an independent `reviewer` judge per PR.
- `REVIEWED` comes only from the `claude-review` check; the skill merges after it lands and checks are green.

## Impact
- New spec: `autobuild-skill`.
- Files: `claude/skills/autobuild/SKILL.md`, `changelog.d/docs-5.md`.
