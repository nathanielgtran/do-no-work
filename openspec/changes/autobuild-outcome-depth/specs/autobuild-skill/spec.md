## ADDED Requirements

### Requirement: Outcome-ranked scouting
`claude/skills/autobuild/SKILL.md` SHALL direct the Scout to read the target repo's `PLAN.md` `## Outcome` and `## Signals`, pull the signal data first, and rank candidate features by how much they move the outcome. When a repo has no such block, the skill SHALL direct the agent to draft one, show the user and seed it before scouting further.

#### Scenario: Repo without an outcome block
- **WHEN** autobuild scouts a repo whose `PLAN.md` has no `## Outcome` section
- **THEN** the skill tells the agent to draft `## Outcome` and `## Signals`, show the user, and seed them before picking features

### Requirement: Independent review before merge
The skill SHALL direct the agent, before labelling or merging a builder's PR, to run `git status --short` in that worktree and discard stray uncommitted edits, and to spawn one independent `reviewer` agent per PR given the diff and the outcome it targets but not the builder's conclusion. Docs-only and baseline PRs MAY skip the judge.

#### Scenario: Feature PR reviewed
- **WHEN** a builder opens a feature PR
- **THEN** the skill tells the agent to spawn a `reviewer` agent with the diff and the target outcome before merging

### Requirement: REVIEWED comes from CI
The skill SHALL NOT direct the agent to apply the `REVIEWED` label, except in a repo with a standing self-label grant in the owner's `~/CLAUDE.md`. It SHALL direct the agent to merge with one literal PR number only after the `claude-review` check has applied `REVIEWED` and every check is green, and to treat a `claude-review` block as a red check.

#### Scenario: Merge step
- **WHEN** a PR's checks are green and `claude-review` has applied `REVIEWED`
- **THEN** the skill's merge instruction is `gh pr merge <N> -R <repo> --squash --delete-branch` with no `gh pr edit --add-label REVIEWED` step
