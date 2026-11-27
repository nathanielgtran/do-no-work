# Workflow research

What we took from the Claude Code docs and engineering write-ups, what is already in this repo, and what is worth trying next. Numbers from third-party or secondary sources are marked unverified.

## Adopted in this repo

- **Stop hook as a done gate.** A Stop hook that runs the repo's fast check and blocks the stop on failure keeps "done" honest. Adopted as [`stop-gate`](../claude/hooks/stop-gate.sh), with a timeout, a 40-line clip, loop safety and a trusted-owner rule so a cloned repo cannot run code. Source: <https://code.claude.com/docs/en/best-practices>
- **Read-only reviewer subagent.** A reviewer with Read, Grep and Glob only, ending in `VERDICT: PASS` or `BLOCK`. Adopted as [`claude/agents/reviewer.md`](../claude/agents/reviewer.md).
- **CI review that applies `REVIEWED`.** The review runs in CI, comments, and labels only on a PASS for the exact head commit; [`gate-self-merge`](../claude/hooks/gate-self-merge.sh) then checks the label and green checks. Adopted as [`claude-review.yml`](../.github/workflows/claude-review.yml).
- **Lint-config protection.** Agents disable rules to make checks pass. Adopted as [`protect-lint-config`](../claude/hooks/protect-lint-config.sh), which asks before config and baseline edits.
- **Worktree includes.** `.worktreeinclude` copies small gitignored files into new worktrees; `worktree.symlinkDirectories` links big directories such as `node_modules`. Adopted as [`.worktreeinclude.example`](../.worktreeinclude.example) and a settings note. Related: `/batch` for fleet-wide mechanical changes fits the same worktree-per-task model.

## Worth trying next

- **`/goal <condition>` for headless and nightly loops.** Give the loop a turn cap and require proof in the output, so it ends on evidence and not on a claim. Source: <https://code.claude.com/docs/en/goal>
- **OS sandbox plus auto mode instead of hook allowlists.** Anthropic reports 84% fewer permission prompts, and that about 93% of prompts were approved anyway. Those figures come from the engineering post and are unverified here. The settings example already ships a sandbox block; the next step is to retire parts of `openspec-autonomy`'s allowlist. Source: <https://anthropic.com/engineering/how-we-contain-claude>
- **`/auto-mode-setup` and `autoMode.environment`.** Describe your trusted repos, hosts and registries once, in user settings only, to stop cross-repo prompts. The example file has a starter block. Source: <https://code.claude.com/docs/en/auto-mode-config.md>
- **`/batch` for fleet-wide changes.** Use it for mechanical edits across many repos, one worktree each, and keep the human review queue short.
- **`--bare -p` for reproducible headless runs.** It skips hooks and CLAUDE.md, so none of the guardrails here apply. Enforce merge rules with branch protection and required checks instead; `repo-bootstrap` already sets the `protect-main` ruleset.

## Backfires to avoid

- **Heavy Stop hooks.** A slow or flaky gate makes sessions hang or loop. Keep the check fast, set a timeout, and let a repeated identical failure through.
- **Agents editing lint configs.** Covered by `protect-lint-config`.
- **Fan-out wider than you can review.** Review is the bottleneck, not generation. Three parallel PRs reviewed one at a time is the ceiling in `autobuild`. Source (secondary, unverified): <https://infoq.com/news/2026/03/agoda-ai-code-bottleneck>
- **Fixed proxy allowlists.** Domain lists rot and block legitimate work. Prefer the sandbox's filesystem limits and a short, reviewed network list, and treat the list as config you maintain.
