# hook-install.md — flip-todo-on-merge PostToolUse wiring

## How the hook works

`flip-todo-on-merge.sh` reads stdin JSON when invoked as a Claude Code PostToolUse hook.
The hook fires AFTER every Bash tool call. The script checks the JSON for `gh pr merge <N>`
and exits cleanly (no-op) when the command is anything else. This means wiring it as a
broad Bash PostToolUse hook is safe — it self-guards.

---

## settings.json snippet

Add the following inside the `"hooks"` object. If `"hooks"` does not yet exist, create it.
This must go in `~/.claude/settings.json` (global) or `.claude/settings.json` (per-project).

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/skills/backlog/flip-todo-on-merge.sh"
          }
        ]
      }
    ]
  }
}
```

The `matcher: "Bash"` fires this after every Bash tool call. The script reads the stdin
JSON and extracts the PR number only when the command string matches `gh pr merge <N>`;
all other Bash calls fall through silently (exit 0, no output).

### Command-substring guard (built-in)

The script's stdin reader does:
```bash
EXTRACTED=$(echo "$STDIN_JSON" | grep -oP '(?<=gh pr merge )\d+' || true)
```
If no `gh pr merge <N>` is found, `EXTRACTED` is empty → script logs "No PR number provided
or detected" → queries `gh pr list --state merged --limit 1` as last resort. To avoid that
fallback when the Bash call was unrelated, the script will still query the most recent merged
PR — which is idempotent and safe (already-flipped lines are skipped). If you want it to
be a strict no-op for non-merge calls, wrap it:

```json
{
  "command": "bash -c 'echo \"$STDIN_JSON\" | grep -q \"gh pr merge\" && $HOME/.claude/skills/backlog/flip-todo-on-merge.sh || true'"
}
```

---

## Manual test (standalone)

From inside any fleet repo with a `TODO.md`:

```bash
# Dry-run with explicit PR number (safe, read-only)
cd ~/Github/myapp
$HOME/.claude/skills/backlog/flip-todo-on-merge.sh 93 --dry-run

# Dry-run simulating hook stdin (PostToolUse JSON)
echo '{"tool":"Bash","tool_input":{"command":"gh pr merge 154 --merge --squash"}}' \
  | $HOME/.claude/skills/backlog/flip-todo-on-merge.sh --dry-run

# Live flip (actually edits TODO.md, no commit)
$HOME/.claude/skills/backlog/flip-todo-on-merge.sh 154
```

---

## Caveats

1. **Working tree only** — the script edits `TODO.md` in place but does NOT run
   `git commit` or `git push`. The change sits as an uncommitted working-tree edit.
   Your next `git commit` (or the `log` skill / EOD hook) carries it. This is
   intentional: it keeps the hook fast and avoids double-commits during a merge session.

2. **No partial-ID matches** — `fix-12` will NOT flip a line mentioning `fix-129`.
   Word-boundary detection uses `\b` in grep and `index()` on the exact ID string in awk.

3. **Idempotent** — if the line is already `[x]` the script says so and does nothing.

4. **No TODO.md = silent skip** — the script exits 0 with a log message if the repo
   has no `TODO.md` at its root. Safe to wire fleet-wide.

5. **PR number detection order**:
   - CLI arg (`./flip-todo-on-merge.sh 154`)
   - stdin JSON `gh pr merge <N>` substring
   - `gh pr list --state merged --limit 1` (most recent merged)
