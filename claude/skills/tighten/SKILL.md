---
name: tighten
description: >
  Cleanup pass that fixes what it reviews. PR mode: checks the PR branch out into a
  detached worktree, sizes the diff, runs one reviewer with a lean-code rubric, applies
  bounded net-negative or correctness fixes, verifies with lint and tests, pushes to the
  PR branch, strips REVIEWED, labels tightened, posts one PR comment. File mode: tightens
  one prose or code file in place (or beside it) without losing a single fact. Single
  pass, never asks questions. Use for /tighten, "tighten this PR", "tighten this note",
  or from the gh pr create hook before the review step.
argument-hint: "[PR# | path] [--again] [--dry] [--tier N]"
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/*), Bash(git *), Bash(gh *), Read, Edit, Write, Agent
---

# tighten

Make the thing smaller and safer without changing what it does or says. One pass. Never
ask a question: every choice below is a rule, and anything a human would have decided goes
in the report. An argument that is an existing path selects file mode; a number or nothing
selects PR mode.

## 1. Preflight (already ran)

```json
!`bash ${CLAUDE_SKILL_DIR}/scripts/preflight.sh $ARGUMENTS || true`
```

- `status: refuse` -> report `reason`, stop.
- `status: skip` -> report `reason`, stop (the PR already carries the tightened marker).
- `status: go`, `mode: pr` -> sections 2 to 6. `mode: file` -> section 7.

## 2. Tier and diff (PR mode)

```
bash ${CLAUDE_SKILL_DIR}/scripts/tier.sh origin/<base> HEAD      (run with cwd = worktree)
git -C <worktree> diff -U25 origin/<base>...HEAD > <scratchpad>/tighten-<pr>.diff
```

`flags.tier` overrides the computed tier. Tier 0: go to step 6 with an empty ledger and
reason "trivial diff". Do not paste the diff into this conversation.

## 3. Review (one subagent)

Spawn one `Agent`, `subagent_type: general-purpose`, `model: haiku` for tier 1 and
`model: sonnet` for tier 2 and 3. Prompt, filled in:

> Read-only code review. Read `${CLAUDE_SKILL_DIR}/rubric.md` first and apply the tier
> <N> scope. The diff is at `<scratchpad>/tighten-<pr>.diff` (unified, 25 lines of
> context); the checked-out branch is at `<worktree>` if you must Read a specific file
> range or grep for a symbol. PR title: "<title>". Do not edit anything, do not spawn
> agents, stay under 12 tool calls. Return only the JSON lines the rubric's output
> contract describes, at most 5, or `{"findings":0}`.

Output that does not parse as JSON lines counts as no findings; say so in the report.

## 4. Triage (rules, no judgement calls)

APPLY a finding only when all of these hold: `confidence` high with a concrete `case`;
`file` in the diff (or its test file; tests may be created); `public_api` false;
`loc_delta <= 0` or `kind` in bug, security, error-handling, test; fix within 2 files and
roughly 40 changed lines, no new dependency, no new non-test file.

Everything else is DEFER with a one-word reason (`structure`, `public-api`, `adds-lines`,
`outside-diff`, `confidence`, `too-big`). `kind: structure` is always DEFER. When two
findings overlap and one deletes while the other extracts, keep the delete. Order APPLY:
bug, security, error-handling, test, then the rest. `flags.dry` -> skip step 5.

## 5. Fix (one subagent, sonnet)

Spawn one `Agent`, `model: sonnet`, with the worktree path, the APPLY list and the gate
commands. Its instructions:

> Work only under `<worktree>` with absolute paths. For each item in order: make the
> change; run `<lint>` and `<typecheck>` (skip either that is empty) limited to the
> changed files where the tool allows; on success `git -C <worktree> commit` all changes
> with subject `<prefix> <type>: <title>` where type is `fix` for bug/security/
> error-handling, `test` for test, else `refactor`, body = the finding's case and fix,
> trailer `Tighten-Finding: <id>`; no co-author, no footer, no emoji. On failure
> `git -C <worktree> checkout -- . && git -C <worktree> clean -fd`, mark the item
> REVERTED with the first 15 lines of output, continue. After the loop run `<test>` once,
> scoped to the touched packages when the runner supports it; if it fails,
> `git -C <worktree> reset --hard HEAD~1` newest-first until green, marking each dropped
> commit REVERTED; if the base commit itself is red, mark everything REVERTED and say the
> PR was red before tighten. For an applied `bug` or `security` fix add one CHANGELOG line
> under the PR's section in the repo's style (`changelog.style` bold: `- **fix-<next>**`,
> paren: `(fix-<next>)`, none: plain) in the same commit. Never push. Return a JSON
> ledger: `[{"id":1,"status":"applied|reverted","sha":"...","note":"..."}]`.

## 6. Finish (direct commands, so the autonomy gate can see the push)

1. Structure DEFER items with `confidence: high`: append `- [ ] tighten #<pr>: <title> (<file>)`
   to the worktree's `TODO.md` open items and commit `<prefix> chore: record deferred tighten findings`.
2. If any commit exists: `git -C <worktree> push origin HEAD:refs/heads/<branch>` (never
   `--force`). If denied (autonomy `less`) or rejected, keep the worktree and report
   "commits are local at <worktree>; push with: git -C <worktree> push origin HEAD:refs/heads/<branch>".
3. `gh label create tightened --color 5319e7 --description "tighten pass done" --force`,
   `gh pr edit <pr> --add-label tightened`; after a successful push also
   `gh pr edit <pr> --remove-label REVIEWED` (ignore "label not found").
4. `gh pr comment <pr> --body-file <scratchpad>/tighten-<pr>.md` with:

```
<!-- tighten:pass tier=<N> -->
## tighten (tier <N>)
Applied: <n> commit(s), <net> lines
1. <title> (<file>) <sha>
Reverted: <title>: <first line of failure>   (or "none")
Deferred: [<reason>] <title> (<file>)          (or "none")
Gate: <lint>; <typecheck>; <test>
```

5. When every subagent has returned: `git -C <repo_root> worktree remove <worktree>` (skip
   when commits are unpushed) and `git -C <repo_root> worktree prune`.
6. Report: tier, reviewer model, applied/reverted/deferred counts, push status, and when
   `other_checkout` is set: "branch moved; run `git pull` in <other_checkout>".

## 7. File mode

No PR, worktree, push, label, comment or commit. Preflight gives `path`, `kind` (prose or
code), `lines`, `tracked`, `dirty`, `in_place`, `out_path`, `lint`, `typecheck`.

1. Review: one `Agent`, `model: haiku` when `lines <= 300`, else `sonnet`. Prompt:

> Read-only review of one file. Read `${CLAUDE_SKILL_DIR}/<rubric-prose.md if kind is
> prose, else rubric.md (tier 2 scope)>` first, then Read `<path>` in full (in chunks by
> heading if it is long). Do not edit, do not spawn agents, stay under 10 tool calls.
> Return only the JSON lines the rubric's output contract describes, at most <8 for
> prose, 5 for code>, or `{"findings":0}`.

2. Triage: APPLY when `confidence` is high and `kind` is not `structure` or
   `factual-risk`. Those two are always report-only. For code, the PR-mode APPLY rules
   apply too (no public API change, bounded size).
3. Apply (skip when `flags.dry`): make each APPLY edit yourself with `Edit` on `out_path`.
   When `in_place` is false, first copy the file: `cp <path> <out_path>` (create the
   directory if needed) and edit the copy; the original is never touched. Prose hard
   rules from the rubric are binding: every fact, number, command, code block, link,
   wikilink, name, date and the frontmatter survive verbatim. For `kind: code`, run `<lint>`
   and `<typecheck>` on the file afterwards; if either fails, undo your edits
   (`git restore <path>` when in place, otherwise rewrite the copy from the original) and
   report the failure.
4. Report: findings table (id, kind, lines, title, applied or deferred), then the diff.
   In place: `git -C <repo_root> diff --stat -- <path>` and `git -C <repo_root> diff -- <path>`,
   and the line "undo with: git -C <repo_root> restore <path>". Copy: `diff -u <path> <out_path>`
   and the line "original untouched; tightened copy at <out_path>". Dry: findings only.
   List every `factual-risk` finding under "Check these facts" with both lines quoted.

## Rules

- Single pass. No re-review, no retry of a reverted item. `--again` is the user's call.
- Never `--force`, never push to main/master, never `gh pr create`, never ask a question.
- Never stash, reset or edit a checkout you did not create (PR mode); never write
  anywhere but `out_path` (file mode).
- Push, label and comment commands run directly in this session, not inside a script.
