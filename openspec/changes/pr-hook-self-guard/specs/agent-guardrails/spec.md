## ADDED Requirements

### Requirement: Post-PR-create self-guard
`post-pr-create` SHALL print no output and exit 0 unless `tool_input.command` contains a `gh pr create` invocation (at the start of the command or after a shell separator or whitespace) and the tool response's stdout has a line that is exactly a GitHub pull request URL (`https://github.com/<owner>/<repo>/pull/<N>`), which is what `gh pr create` prints on success. It SHALL NOT depend on the settings `if` filter to stay silent for other Bash calls.

#### Scenario: Unrelated Bash call
- **WHEN** the command is `for h in a b; do curl -s https://$h; done` or `ssh host 'docker ps'`
- **THEN** the hook prints nothing and exits 0

#### Scenario: PR URL without a create
- **WHEN** the command is `gh pr view 42` and the response contains `https://github.com/o/r/pull/42`
- **THEN** the hook prints nothing

#### Scenario: Create text inside a heredoc
- **WHEN** the command writes a file through a heredoc whose body mentions `gh pr create` and the output is `Change 'x' is valid`
- **THEN** the hook prints nothing

#### Scenario: Failed create
- **WHEN** the command is `gh pr create --fill` and stdout has no pull request URL line
- **THEN** the hook prints nothing

#### Scenario: Create inside a compound command
- **WHEN** the command is `git push -u origin x && gh pr create --fill` and stdout ends with the line `https://github.com/o/r/pull/7`
- **THEN** the hook prints the review context for PR 7
