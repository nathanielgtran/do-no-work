# do no work

A Claude Code setup where the agent does the work and you make the decisions, with guardrails that make it safe to let it run.

Built by Nathaniel Tran. See more of my work at **[ngtran.dev](https://ngtran.dev)**. <!-- public-safety: allow (author byline) -->

Hooks, slash commands, skills, a `CLAUDE.md` template, daily CLI scripts and shell/git config. One installer for macOS/Linux/WSL, one for Windows.

- [The workflow](#the-workflow)
- [Guardrails at a glance](#guardrails-at-a-glance)
- [autobuild: hands-off feature loop](#autobuild-hands-off-feature-loop)
- [Install](#install)
- [Docs](#docs)

## The workflow

Every change goes the same way: plan, isolate, prove, review, merge. Each step leaves evidence the next one checks. Hooks enforce the steps, so nobody has to remember them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/workflow-dark.svg">
  <img src="docs/diagrams/workflow.svg" alt="Workflow: session start, plan, worktree, build, push and PR, CI and Claude review, gate-self-merge, squash merge, release, log, with a fix loop on a blocked review">
</picture>

The rules live in [`claude/CLAUDE.md.example`](claude/CLAUDE.md.example):

| Rule | Means |
|---|---|
| No hacks | No workaround, retry or fallback that hides a bug. Fix the first place it goes wrong |
| Mistakes become rules | A correction that happens twice becomes a check (lint, test, hook) that fails on the real past instance |
| Comments default to none | Rename, extract or type the code instead |
| Proof, not claims | PR bodies carry pasted test output or screenshots, never "tested locally" |

PR format, changelog fragments and cross-repo tracking: [docs/operations.md](docs/operations.md).

## Guardrails at a glance

Every Bash call passes through the hooks before it runs. The strictest decision wins: deny, then ask, then allow.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/guardrails-dark.svg">
  <img src="docs/diagrams/guardrails.svg" alt="Guardrails: a Bash command passes autonomy-gate with push-guard, gate-self-merge and openspec-autonomy; data heredocs are skipped; deny rules always win; outcomes are deny, ask, allow or the normal prompt">
</picture>

| Always denied | Asks | Ignored |
|---|---|---|
| Push or merge to `main`/`master` | Writes to hook files | Heredoc bodies that are data |
| Git hook bypasses (`--no-verify`, `SKIP=`) | Merges without `REVIEWED` and green CI | Reading or mentioning guarded paths |
| Writes to the autonomy dial | Commands the parser can't read | |
| Any push or merge after "go less" | Missing `jq` or `python3` | |

- Denials hold through wrappers: `bash -c`, `eval`, `$(...)`, aliases, `git -C`.
- A prompt on a harmless command is a guard bug to fix, not to approve.
- Say **"go less"** to block all push and merge, **"go full"** to restore them.

> **Warning:** `openspec-autonomy` auto-approves allowlisted commands in any repo with `openspec/config.yaml`, and a cloned repo can contain that file. Only wire it if you keep the `permissions.deny` block from [`claude/settings.example.json`](claude/settings.example.json).

Every hook, with exact rules: [docs/hooks.md](docs/hooks.md).

## autobuild: hands-off feature loop

[`autobuild`](claude/skills/autobuild/SKILL.md) is for when you'd rather the agent decide what to build.

- It scouts the repo, picks up to three features and builds them in parallel worktrees.
- You review and merge one PR at a time.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/autobuild-dark.svg">
  <img src="docs/diagrams/autobuild.svg" alt="autobuild: preconditions, scout, pick up to three features, set up worktrees, build in parallel, outside reviewer, wait for CI review label, merge, verify live, log">
</picture>

## Install

1. Clone and run the installer:

   ```bash
   git clone https://github.com/nathanielgtran/do-no-work ~/Github/do-no-work  # public-safety: allow (public repo URL)
   cd ~/Github/do-no-work && ./install.sh
   ```

2. Merge `hooks`, `permissions` and `statusLine` from [`claude/settings.example.json`](claude/settings.example.json) into `~/.claude/settings.json`. The installer never touches it.
3. Run `dnw-doctor` to check the install.

Windows, flags, packages and the personal overlay: [docs/install.md](docs/install.md).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/install-dark.svg">
  <img src="docs/diagrams/install.svg" alt="Install map: install.ps1 and install.sh place home config, bin scripts, Claude config, upstream skills and dependencies; settings merge and the diagram-design plugin are manual">
</picture>

## Docs

| Page | What's in it |
|---|---|
| [Catalogue](docs/REFERENCE.md) | Every hook, command, skill, script and config file, one line each |
| [Hooks](docs/hooks.md) | Guard, gate and context hooks |
| [Commands](docs/commands.md) | `/log`, `/prune`, `/test`, `/review-pr`, `/deploy`, `/hc`, `/rollback` |
| [Skills and agents](docs/skills.md) | `autobuild`, `backlog`, `call`, `tighten`, `wanderlog`, `reviewer` |
| [Scripts](docs/scripts.md) | `bin/` CLI scripts, repo scripts and installers |
| [Config and CI](docs/config.md) | Settings example, templates, CI workflows |
| [Install](docs/install.md) | Install steps, what lands where, personal overlay |
| [Operations](docs/operations.md) | PR format, changelog, new repos, CI review, secrets, tests |
| [Workflow research](docs/workflow-research.md) | What was adopted and what to try next |

## License

MIT. See [LICENSE](LICENSE).
