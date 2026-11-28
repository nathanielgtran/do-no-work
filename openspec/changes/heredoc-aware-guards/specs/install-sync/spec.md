## MODIFIED Requirements

### Requirement: Guard change alert
`dnw-apply` SHALL treat `claude/hooks/autonomy-gate.sh`, `autonomy-toggle.sh`, `gate-self-merge.sh`, `openspec-autonomy.sh`, `push-guard.py` and `claude/settings.example.json` as guard files. When any of them differs between the previously applied commit and the new one, it SHALL append `<UTC timestamp> <old7>..<new7> <files>` to `<state>/audit.log` and send the owner a message through `~/.claude/hooks/claude-notify.sh --message` that names the commits, the changed guard files and the audit path. It SHALL NOT alert on the first run, when no applied commit is recorded or the recorded one is unknown to the checkout. A missing notifier or a failed send SHALL print a warning, not stop the apply.

#### Scenario: Guard hook changed
- **WHEN** a merged change touches `claude/hooks/autonomy-gate.sh` after a recorded apply
- **THEN** `audit.log` gains one line naming that file, the owner message is sent, and the summary says `guard change yes`

#### Scenario: Non-guard change
- **WHEN** a merged change touches only `bin/`
- **THEN** no audit line is written and no message is sent

#### Scenario: Notification fails
- **WHEN** a guard file changed and the send fails
- **THEN** a `Discord notify failed` warning is printed, `audit.log` still has the line, and the applied commit is recorded
