#!/bin/bash
# SessionStart context loader: injects a slice of personal-kb (last daily-log
# entry, active todos, current-work notes) instead of having Claude read all three
# files in full. Claude reads the full files on demand.

KB="$HOME/Github/personal-kb"

# Lines are clipped so one long bullet can't blow out the startup context.
CLIP=180

emit() { jq -nc --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'; }

# Per-worktree HANDOFF.md (written by /log, gitignored). Live git state is
# injected alongside it so a stale handoff is visible, not trusted.
input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
handoff=""
if root=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) && [ -f "$root/.claude/HANDOFF.md" ]; then
  head_sha=$(git -C "$root" rev-parse --short=7 HEAD)
  h_sha=$(sed -n 's/^commit: *//p' "$root/.claude/HANDOFF.md" | head -1 | cut -c1-7)
  stale=""
  [ "$h_sha" != "$head_sha" ] && stale=" (STALE: written at $h_sha, HEAD $head_sha — trust git)"
  handoff="

=== HANDOFF $root$stale ===
$(head -25 "$root/.claude/HANDOFF.md" | cut -c1-160)
=== git ===
$(git -C "$root" status -sb | head -8)
$(git -C "$root" log --oneline -5)"
fi

if [ ! -d "$KB" ]; then
  emit "Session started. personal-kb is not cloned on this machine. Skip KB steps. Ask about meetings and ask for 2-3 goals for the day.$handoff"
  exit 0
fi

# Most recent day-section of the daily log (template "## YYYY-MM-DD" is skipped
# because the regex requires digits). Newest-first, so this is the last workday.
log=$(awk '
  /^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ { count++ }
  count > 1 { exit }
  count >= 1 { print }
' "$KB/daily-log.md" | cut -c1-"$CLIP" | head -40)

# Active todo only: from "## in progress" up to (not including) "## to do".
todo=$(awk '
  /^## in progress/ { grab=1 }
  /^## to do/       { grab=0 }
  grab { print }
' "$KB/todo.md" | cut -c1-"$CLIP" | head -40)

# Notes: "## current work" section only.
notes=$(awk '
  /^## current work/ { grab=1; next }
  /^## /             { grab=0 }
  grab { print }
' "$KB/notes.md" 2>/dev/null | cut -c1-"$CLIP" | head -30)

# Fall back to a read-everything instruction if slicing produced nothing
# (e.g. headings were renamed) so a format change never silently drops context.
if [ -z "$log" ] || [ -z "$todo" ]; then
  emit "Session started. Run the morning startup routine from CLAUDE.md: read daily-log.md, todo.md, and notes.md from personal-kb, present a brief summary of last workday and active tasks, ask about meetings, and ask for 2-3 goals for the day.$handoff"
  exit 0
fi

emit "Session started — morning routine. The last workday's log, active todo, and current-work notes are pre-loaded below (long lines clipped); do NOT re-read those files in full (read on demand only if the user asks for older history, the full backlog, or a clipped line). Summarize last workday + active tasks, ask about meetings, ask for 2-3 goals (note them under '### goals' in today's daily-log section).

=== daily-log (last workday) ===
$log

=== todo (in progress + high priority) ===
$todo

=== notes (current work) ===
$notes

Full files: $KB/daily-log.md, $KB/todo.md, $KB/notes.md$handoff"
