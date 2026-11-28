# do-no-work

A public Claude Code setup plus dotfiles: guard hooks, commands, skills, CLI scripts and shell/git config, installed by `install.sh` (macOS, Linux, WSL) or `install.ps1` (Windows).

- Tests: `./tests/run-all.sh` (`--list`, `--only <glob>`); one suite is `bash tests/<name>_test.sh`. A new `tests/*_test.sh` is discovered without a CI change. Each suite builds a throwaway `HOME` or repo and fakes `gh` and `curl`; never point a test at the real home.
- Public repo: no personal data in any tracked file. `./scripts/public-safety-check.sh` runs in pre-commit and CI; mark an intentional match with `public-safety: allow` and a reason.
- Changelog: never edit `CHANGELOG.md` in a PR. Add `changelog.d/<type-N>.md` with one line and no ID; `./scripts/changelog.sh next <feat|fix|docs|chore>` gives the ID.
- Docs and installers track the code: a PR that adds, removes or renames a hook, command, skill, CLI script or config file updates `docs/REFERENCE.md` (the catalogue) in the same PR — and `README.md` when the workflow, guardrails, install steps or "What's in it" change — and installs the file from BOTH `install.sh` and `install.ps1` (the `installer` spec's managed set is the source of truth; keep the two installers at parity). Changing one installer but not the other, or adding a piece with no catalogue entry, is an incomplete PR, not a follow-up.
- Shell must run on bash 3.2 and BSD tools (macOS CI); `tests/portability_test.sh` lists the known breakers.
- The guard hooks (`autonomy-gate`, `autonomy-toggle`, `gate-self-merge`, `openspec-autonomy`) and the deny rules in `claude/settings.example.json` are a contract: `dnw-apply` alerts the owner when they change. Add the failing test case first.

## OpenSpec

- `openspec/specs/<capability>/spec.md` is the source of truth for what the code does today (6 capabilities: `installer`, `install-sync`, `agent-guardrails`, `changelog-fragments`, `public-safety`, `pr-tooling`). Read the relevant spec before changing behaviour; if code and spec disagree, treat it as a bug in one of them and say which.
- Non-trivial changes start as `openspec/changes/<id>/` (proposal.md, delta specs, tasks.md, design.md when warranted) before code. Run `openspec validate <id> --strict` before writing code.
- Never hand-edit `openspec/specs/` outside a change. Archive a change only via the repo's release flow or when told.
- Run `openspec validate --all --strict` before opening a PR that touches `openspec/`.
- Project context and per-artifact rules live in `openspec/config.yaml`.
- Not yet specified: `claude/skills/`, `claude/commands/`, `claude/agents/`, `bin/` scripts other than `dnw-apply`, `dnw-doctor`, `ci-wait`, `fleet`, `safe-worktree-remove` and `repo-bootstrap`, and the hooks `session-context.sh`, `compact-reinject.sh` and `claude-notify.sh` (beyond `--message`). Add a spec in the change that first alters one of them.
