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
   `REPOS.md`, the repo's `TODO.md`, `PLAN.md` `## Current State` + `## Outcome` + `## Signals`,
   `.claude/HANDOFF.md`.

## 1. Scout (you, not agents; keep it short)

```bash
git fetch -q && git log --oneline origin/main -10
gh pr list -R <owner/repo>; gh issue list -R <owner/repo>
ls openspec/changes; sed -n '1,80p' TODO.md
```

**Start from the outcome, not the task list (altitude).** Read `PLAN.md` `## Outcome` (the one
result the repo exists to move) and `## Signals` (the live data that measures it: an MCP tool,
logs, analytics, a read-only db copy). Pull the signal data first. Rank every candidate below by
how much it moves the outcome, not by TODO order. If a repo has no `## Outcome`/`## Signals` block,
draft one from `REPOS.md` + memory `project_*`, show the user, and seed it before scouting further.

**Challenge one belief against the raw data (depth).** Name one assumption the repo is built on and
try to reproduce it from the `## Signals` raw data before picking. If it fails to reproduce, that
gap is the feature. Example: reproduce spending-app's "borrowing capacity" from raw transactions
the way a broker would; the difference from what the app shows is the fix.

Sources of good features, after the outcome ranking, in priority order:
- **Something you just did by hand for the user this session.** A manual step that happened
  twice is the strongest signal.
- Data the code already parses but no output uses yet (grep the model fields against the
  formatters).
- TODO.md items marked as gaps (not "verify live" chores).
- The user's actual goal (memory `project_*`). Ask what would change a decision for them.

**Raise the bar before locking picks (depth).** For each pick, answer Felix Rieseberg's four
questions and fold the answers into the agent spec: (1) what a field-leading pro would do here that
you are not asking for; (2) the rawest material they would start from, not what's already digested;
(3) the specific methods and tools they use (insist on real instruments, not markdown tables where a
database or statistical model is the professional choice); (4) what, other than you or the model,
would prove the result right — name a tool or check the builder can run. State the target as an
unreasonable version (200ms, not "faster") and treat it as solvable.

**Research, every round.** While you scout, run one background research agent (web search, then
fetch primary sources) on how others solve the candidate problems: official docs, tools with
traction, practitioner write-ups, and what backfired. Give it the repo's stack and the 4-6
candidate problems; ask for ranked approaches with links and dates, flagging unverified claims.
Fold the findings into the picks: prefer a proven approach over a homegrown one, drop a
candidate if a maintained tool already does it, and put the sources in each agent spec and the
PR's `## Why`.

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
     Use the professional instrument the Scout spec named (a real database/model/tool where that is what an expert reaches for, not a markdown-table stand-in), and hit the unreasonable target it set rather than an easy one.
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
   Before reviewing, run `git status --short` in the worktree: agents leave uncommitted edits
   (twice so far: TODO items ticked that were still open). Inspect and discard them; never let
   a later `commit -a` sweep them in.

   **Outside judge (don't let the builder grade itself).** The builder wrote its own Proof, so
   before you label, spawn one independent `reviewer` agent per PR. Give it the diff and the
   feature's acceptance (the `## Outcome` it was meant to move), never the builder's own
   conclusion. Act on real bugs it finds; a disagreement you can't resolve from the diff goes in
   the report, not a quiet merge. Skip the judge only for a docs-only or baseline PR.
2. CI: to track every PR across repos at once, run `fleet watch --head '<branch-glob>'` and take merge candidates from `fleet ready` (needs a repo list: `--repos` or `fleet.txt`). Per PR, wait about 25 s after a push before `gh pr checks <N> -R <repo> --watch --interval 15`.
   Checks show "no checks reported" right after a push. Red means fix, never merge.
3. The `claude-review` CI check applies `REVIEWED` when it passes; never add the label yourself
   (a repo with a standing self-label grant in `~/CLAUDE.md` is the only exception). Once the
   label is on and every check is green, merge with one literal PR number:
   `gh pr merge <N> -R <repo> --squash --delete-branch`. A `claude-review` BLOCK is a red check:
   fix and push.
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
