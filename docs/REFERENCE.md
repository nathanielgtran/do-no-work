# Catalogue

Everything in this repo, one line each. Click a name for its card: what it does, when it runs, how to disable it, and its source.

- Behaviour is taken from the code, not from the README.
- Paths are relative to the repo root.
- Installed paths assume `install.sh`: hooks, commands, agents and skills go to `~/.claude/`; `bin/` goes to `~/.local/bin/`.

| Page | Covers |
|---|---|
| [hooks.md](hooks.md) | 11 hook scripts, plus 1 in a skill |
| [commands.md](commands.md) | 7 slash commands |
| [skills.md](skills.md) | 5 skills and the `reviewer` agent |
| [scripts.md](scripts.md) | 15 `bin/` scripts, repo scripts, installers |
| [config.md](config.md) | CI workflows, settings example, templates |
| [install.md](install.md) | Install steps and the personal overlay |
| [operations.md](operations.md) | PR format, changelog, review rollout, secrets, tests |

## Hooks

| Hook | Purpose |
|---|---|
| [`autonomy-gate`](hooks.md#autonomy-gate) | Deny push/merge to `main`, git hook bypasses and dial writes; ask before hook writes |
| [`gate-self-merge`](hooks.md#gate-self-merge) | Allow a merge only with `REVIEWED` and green checks |
| [`openspec-autonomy`](hooks.md#openspec-autonomy) | Skip prompts for reversible commands in OpenSpec repos |
| [`protect-lint-config`](hooks.md#protect-lint-config) | Ask before lint, format or type-check config changes |
| [`autonomy-toggle`](hooks.md#autonomy-toggle) | Flip the dial on "go less" and "go full" |
| [`claude-notify`](hooks.md#claude-notify) | Discord DM when a session needs you |
| [`session-context`](hooks.md#session-context) | Inject last daily-log entry, active todos, HANDOFF |
| [`compact-reinject`](hooks.md#compact-reinject) | Re-inject rules digest and HANDOFF after compaction |
| [`go-check`](hooks.md#go-check) | gofmt, vet and lint on the edited Go package |
| [`stop-gate`](hooks.md#stop-gate) | Refuse to stop while the fast check fails |
| [`post-pr-create`](hooks.md#post-pr-create) | Tell the session how the new PR gets reviewed |
| [`flip-todo-on-merge`](hooks.md#flip-todo-on-merge) | Tick the matching TODO.md line after a merge |

## Slash commands

| Command | Purpose |
|---|---|
| [`/log`](commands.md#log) | End-of-session sync of logs, plans and handoff |
| [`/prune`](commands.md#prune) | Shrink startup context |
| [`/test`](commands.md#test) | Detect the stack and run its tests |
| [`/review-pr`](commands.md#review-pr) | Review a PR, print a severity table |
| [`/deploy`](commands.md#deploy) | Tag a release, watch it, health-check |
| [`/hc`](commands.md#hc) | Home server health check over SSH |
| [`/rollback`](commands.md#rollback) | Put a service back on its `:previous` image |

## Skills and agents

| Name | Purpose |
|---|---|
| [`autobuild`](skills.md#autobuild) | Hands-off feature loop for OpenSpec repos |
| [`backlog`](skills.md#backlog) | Cross-repo TODO and issue rollup |
| [`call`](skills.md#call) | Call recording to local transcript and notes |
| [`tighten`](skills.md#tighten) | Post-PR or single-file cleanup that fixes what it reviews |
| [`wanderlog`](skills.md#wanderlog) | Wanderlog trip API CLI |
| [`reviewer`](skills.md#reviewer) | Read-only review subagent, ends with a verdict |

## CLI scripts (bin/)

| Script | Purpose |
|---|---|
| [`pstack-budget-statusline`](scripts.md#pstack-budget-statusline) | Plan usage in the statusline; picks a model budget tier |
| [`safe-worktree-remove`](scripts.md#safe-worktree-remove) | Remove a worktree only when nothing uses it |
| [`repo-bootstrap`](scripts.md#repo-bootstrap) | Fleet GitHub defaults, or the CI review only |
| [`review-rollout`](scripts.md#review-rollout) | Enable the CI review on many repos |
| [`dnw-doctor`](scripts.md#dnw-doctor) | Read-only drift check of the live install |
| [`dnw-apply`](scripts.md#dnw-apply) | Install merged main; alert on guard changes |
| [`ci-wait`](scripts.md#ci-wait) | Block until a PR's checks finish |
| [`fleet`](scripts.md#fleet) | Open PRs across many repos |
| [`callrec`](scripts.md#callrec) | OBS call recording from WSL |
| [`transcribe`](scripts.md#transcribe) | Local Parakeet transcription |
| [`pasteimg`](scripts.md#pasteimg) | Windows clipboard image to a WSL path |
| [`chrome-devtools-mcp-gated`](scripts.md#chrome-devtools-mcp-gated) | Chrome MCP only in UI repos |
| [`engraph-*` helpers](scripts.md#engraph--helpers) | enqueue, reindex-drain, relink, refresh, nightly-index, mcp-watchdog, mcp-proxy |

## Repo scripts (scripts/)

| Script | Purpose |
|---|---|
| [`claude-review-verdict.sh`](scripts.md#claude-review-verdictsh) | Review verdict to comment and label |
| [`public-safety-check.sh`](scripts.md#public-safety-checksh) | Fail on personal data in tracked files |
| [`changelog.sh`](scripts.md#changelogsh-and-changelogd) | Changelog fragments |
| [`install.sh`](scripts.md#installsh) | macOS, Linux, WSL installer |
| [`install.ps1`](scripts.md#installps1) | Windows installer |
| [Personal overlay](install.md#personal-overlay) | Private versions of repo files |

## CI workflows

| Workflow | Purpose |
|---|---|
| [`ci`](config.md#ci) | Tests, checks and installs on every PR |
| [`claude-review`](config.md#claude-review) | Reusable Claude review that applies `REVIEWED` |
| [`review`](config.md#review) | This repo's caller of `claude-review` |
| [`claude-review-caller.yml`](config.md#claude-review-calleryml-example) | Caller template for other repos |

## Settings and templates

| File | Purpose |
|---|---|
| [`settings.example.json`](config.md#settingsexamplejson) | Hook wiring, permissions, statusline, sandbox |
| [`CLAUDE.md.example`](config.md#claudemdexample) | Global instructions template |
| [`.worktreeinclude.example`](config.md#worktreeincludeexample) | Copy gitignored files into new worktrees |
| [`skills-upstream.txt`](config.md#skills-upstreamtxt) | Third-party skills and plugin list |
| [Other files](config.md#other-files) | pre-commit, `home/`, diagrams, research notes |
