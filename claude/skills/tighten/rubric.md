# tighten rubric

Condensed from two MIT-licensed sources. Wording is paraphrased; the checklist order and
intent are theirs. Run `scripts/sync-check.sh` to see whether either has moved upstream.

<!-- upstream: DietrichGebert/ponytail skills/ponytail-review/SKILL.md commit=2a1fe842d078cf66ec7f3e6096a8ca4279c2cad7 blob=a50e3ac6ded6fccc9edae34ce37877bbce11e3fa -->
<!-- upstream: cursor/plugins thermos/skills/thermo-nuclear-code-quality-review/SKILL.md commit=5102244dabd626b101cff40accbe7f7d1eeefa15 blob=ac76a2bc88bb2d895e83ab1788aa584a82346cfc -->

Sources: ponytail-review (Dietrich Gebert, MIT) for section A and the finding discipline;
thermo-nuclear-code-quality-review (Cursor, MIT) for section B. Pinned 9 Oct 2026.

## Scope by tier

- Tier 1: section A on the diff hunks only.
- Tier 2: sections A and B on the diff hunks.
- Tier 3: sections A and B, plus trace callers of any changed signature or exported symbol
  (Read the specific file range; do not read whole files) and flag public API impact.

Only report on lines the PR adds or changes. Pre-existing problems in untouched code are
out of scope. A `shortcut: <limit>, <when to upgrade>` comment marks a deliberate
decision, not a finding, unless you found a bug or security problem in that block.

## Finding discipline (applies to every finding)

- Every finding needs a concrete case: this input or situation leads to this wrong or
  wasteful result. No case, no finding.
- Re-read the lines before reporting. Confirm the caller exists, the value can really be
  empty, the code really is unused (grep the worktree for the symbol, including tests,
  fixtures and string references).
- Propose the smallest fix that works. Prefer a fix that deletes code. Never add a layer,
  framework, option or config the problem does not need.
- No style taste, no "consider", no vague worries, no renames for their own sake.
- At most 5 findings. Fewer high-conviction findings beat a long list of nits.

## A. Lean and correct (ponytail-review)

Order of importance: correct, safe, holds under load, tested, fast, lean.

1. bug: wrong result, crash, missed edge case (empty, zero, last item, rounding, time
   zone), a caller broken by a changed signature or return value, a fix applied in one
   caller while the shared function stays broken.
2. security: injection, weak randomness, secrets in code, missing checks on user input.
3. error-handling: errors swallowed, writes in the wrong order, no transaction, data loss.
4. scale: fine for one user, wrong for many: check-then-write race, repeated work per
   process, lists that only grow, a query per item, O(n^2) on real input sizes.
5. test: new non-trivial logic (a branch, a loop, a parser, money, security, a data write,
   a bug fix) with no test that fails when it breaks. Ask for one good test, not coverage.
6. speed: a real slowdown on a hot path. Micro-wins are nice-to-have at most.
7. delete: dead code, unused options or params, speculative features, "for later" code.
8. reuse: the repo already has this helper, component or pattern. Name the path.
9. stdlib: the standard library or platform already does it; a new dependency for a few
   lines of code.
10. yagni: abstraction with one implementation, wrapper that only passes calls through,
    config nobody sets, type conversion nobody needs.
11. merge: near-copies that must change together.
12. split: one function doing several unrelated jobs. Split by job, never by line count,
    and never into helpers whose only purpose is making a function shorter.
13. nesting: three or more nesting levels or a long if/else chain where early returns
    make the flow flat.

## B. Structure (thermo-nuclear-code-quality-review)

Be ambitious in what you notice, conservative in what you ask tighten to apply. Anything
that reshapes a module goes out as `kind: structure` so a human decides.

1. Is there a reframing that makes whole branches, helpers, modes or layers disappear
   while behaviour stays the same? Prefer deleting complexity over rearranging it.
2. Does the PR push a file from under 1,000 lines to over 1,000 lines? Treat as a smell
   unless there is a clear structural reason and the file stays organised.
3. Spaghetti growth: new ad-hoc conditionals, scattered special cases, one-off booleans or
   nullable modes bolted into unrelated flows. That is a design problem, not a nit.
4. Thin abstractions, identity wrappers, pass-through helpers, "magic" generic handling
   that hides a simple data shape. Flag indirection that buys no clarity.
5. Type and boundary cleanliness: unnecessary optionality, `any`/`unknown`, casts, silent
   fallbacks that paper over an unclear invariant. Ask for the explicit boundary.
6. Logic in the wrong layer: feature logic leaking into shared paths, implementation
   details leaking through an API, a bespoke helper where a canonical one exists.
7. Orchestration: independent work serialised for no reason; related updates that can
   leave state half-applied when an atomic shape is obvious.
8. Copy-pasted logic across the diff instead of one extracted helper.

Priority inside B: structural regression, missed dramatic simplification, branching
growth, boundary and type problems, file size, modularity, legibility.

## Project rules the fix must respect

Functions at most 50 lines, cyclomatic complexity at most 10, no 3+ nesting levels, never
swallow errors, early returns over nested if/else. Go: `go vet` + `golangci-lint` clean.
Python: `ruff` clean. TypeScript: strict, no `any`. A fix that would break one of these
is not a fix.

## Output contract

Return only JSON lines, one finding per line, nothing else:

```
{"id":1,"kind":"delete","file":"src/lib/photos.ts","lines":"41-58","title":"retry option is never passed by any caller","fix":"Remove the retry param and the loop; keep the single fetch.","loc_delta":-14,"confidence":"high","case":"grep shows one caller, it never sets retry","public_api":false}
```

Fields: `id` (1..5), `kind` (one of: bug, security, error-handling, scale, test, speed,
delete, reuse, stdlib, yagni, merge, split, nesting, structure), `file`, `lines`
(`start-end` in the new file), `title` (one sentence), `fix` (at most 3 short sentences),
`loc_delta` (estimated net lines, negative = smaller), `confidence` (high or medium),
`case` (the concrete case, one sentence), `public_api` (true when a signature or export
used outside the diff would change). If there is nothing to report, return the single
line `{"findings":0}`.
