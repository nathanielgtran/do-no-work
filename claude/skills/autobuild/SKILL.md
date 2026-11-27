---
name: autobuild
description: >
  Hands-off feature loop for an OpenSpec repo: scout the repo and its real usage for
  gaps, pick up to 3 features, write and validate an OpenSpec change per feature, build
  them in parallel worktree agents, review each PR, merge on green CI, verify live, log.
  Use when the user says "autobuild", "keep building features", "scout and build",
  "figure out what to build, hands off", or "any other features we can get in" with a
  go-ahead.
---

# autobuild

The user hands the repo over: you choose what to build, build it, merge it, and report
milestones. Every hard rule in `~/CLAUDE.md` still applies. Hands-off changes who decides
*what* to build. It does not loosen the merge condition.

## Preconditions (check before anything)

1. `openspec/config.yaml` exists. If it is missing, stop. Standing autonomy only covers OpenSpec repos.
   Outside one, propose the features and ask.
2. Autonomy is not "go less". If push or merge is blocked, build up to open PRs and stop there.
3. You know where the repo runs live, if anywhere: a run worktree, a deploy target or a CLI skill. Read
   `REPOS.md`, the repo's `TODO.md`, `PLAN.md` `## Current State`, `.claude/HANDOFF.md`.

## 1. Scout (you, not agents; keep it short)

```bash
git fetch -q && git log --oneline origin/main -10
gh pr list -R <owner/repo>; gh issue list -R <owner/repo>
ls openspec/changes; sed -n '1,80p' TODO.md
```

Sources of good features, in priority order:
- **Something you just did by hand for the user this session.** A manual step that happened
  twice is the strongest signal.
- Data the code already parses but no output uses yet (grep the model fields against the
  formatters).
- TODO.md items marked as gaps (not "verify live" chores).
- The user's actual goal (memory `project_*`). Ask what would change a decision for them.

Pick **at most 3** features, independent enough to build in parallel. For each one, write one line
on what it does, one on why it matters to the user, and the files it touches. Prefer features that
touch different modules. Two features in the same formatter mean rebase pain, not a blocker.
Tell the user the picks in about four lines, then go. Don't wait for approval unless they asked
to approve.

## 2. Set up (you)

- Cut worktrees yourself from `origin/main`. `isolation: "worktree"` branches from the primary
  checkout's HEAD, which is often stale:
  ```bash
  git worktree add -q ../<repo>-<slug> -b NO-TICKET-<slug> origin/main
  ```
  Use the repo's ticket prefix if it has one. `NO-TICKET` is for personal repos.
- **Assign CHANGELOG IDs up front** (`scripts/changelog.sh next feat` when the repo has
  `changelog.d/`, else the next free `feat-N`, `fix-N` from
  `grep -oE "(feat|fix|chore|docs)-[0-9]+" CHANGELOG.md | sort -t- -k2 -n | tail`), and an
  OpenSpec change id per feature. Agents that pick IDs on their own collide.

## 3. Build (parallel agents)

Run one background `general-purpose` agent per feature, all in a single message. Use the model
from `~/.claude/rules/pstack-models.md` (`feature` role, currently sonnet). Each prompt must be
self-contained and include:

- The absolute worktree path and branch. Tell it to verify `pwd` and touch no other checkout.
- The feature spec: behaviour, output format examples, config keys, and edge cases (unknown
  data is shown as unknown, never invented). Name the files to read first for style, plus one
  existing `openspec/changes/<id>/` as the format reference.
- The repo rules, verbatim:
  1. OpenSpec change first; `openspec validate <id> --strict` clean before code; tick tasks;
     re-validate before the PR.
  2. TDD with behaviour tests; functions of 50 lines or fewer, complexity 10 or less, no swallowed errors, default no comments.
  3. Lint, format check and the full test suite green (the repo's commands from REPOS.md).
  4. CHANGELOG line (or `changelog.d/<id>.md` fragment) with the assigned ID, TODO follow-ups, README for new commands or config.
  5. Commit `[NO-TICKET] feat: ...` with no co-author or footer. Push, and open the PR with the fleet template
     sections `## What` `## Why` `## Proof` (pasted output) `## Risk + rollback`
     `## Checklist`.
  6. Never rm, push main, merge or label. Don't hit live or external services. A read-only run
     against a *copy* of real state is fine and makes the best Proof.
- What to report: PR number, test count, example output, what's left open.

While they run, don't touch their files. Report the launch in a few lines.

## 4. Review and merge (you, one PR at a time)

The post-create review hook skips PRs opened by sub-agents, so you are the reviewer.

For each PR, in merge order (smallest blast radius first):
1. Read the diff: `git diff origin/main --stat`, then the core module. Check for:
   - spec scope creep
   - hidden fallbacks
   - invented data
   - swallowed errors
   - output that looks wrong. Example: a snippet cut mid-word in the agent's own example is a real bug, so fix it.

   Fix small issues yourself in that worktree, then commit and push.
2. CI: wait about 25 s after a push before `gh pr checks <N> -R <repo> --watch --interval 15`.
   Checks show "no checks reported" right after a push. Red means fix, never merge.
3. Label and merge in **separate calls**, one literal PR number each:
   `gh pr edit <N> -R <repo> --add-label REVIEWED`, then
   `gh pr merge <N> -R <repo> --squash --delete-branch`.
4. Rebase the next PR onto the new main:
   - Resolve CHANGELOG, README and TODO conflicts by keeping both sides.
   - Resolve code conflicts by combining both features, never by dropping one.
   - Re-run the full suite, force-push with `--force-with-lease`, and wait for CI again.

If the user interrupts or rejects a tool call, stop the loop. Report state as PRs, CI and
what's next, then wait.

## 5. Verify live and close out

- Update the run checkout (`git checkout --detach origin/main` in the run worktree) and run
  each feature once against real data, read-only where possible. Respect the repo skill's
  volume and notification rules. Compare the output with
  what you expected. Anything surprising goes in the report, not a quiet follow-up.
- Remove the feature worktrees with `safe-worktree-remove`. Only do this after their agents have finished.
- Append a dated note to the repo's memory file and to personal-kb `daily-log.md`. Run
  `engraph-enqueue` on both.

## Report (to the user, at the end)

Keep it short and scannable:
- A table of features with their PRs, tests and merged state.
- Real output from the live check.
- Caveats: estimates, untuned rules, unverified live paths.
- One next step.

Offer the next scouting round in one line. Don't start it unasked.
