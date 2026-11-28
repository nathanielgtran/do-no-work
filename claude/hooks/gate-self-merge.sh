#!/bin/bash
# Auto-ALLOW `gh pr merge` only if the PR has the REVIEWED label AND no failing CI.
set -uo pipefail
input=$(cat)
if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"gate-self-merge: jq or python3 missing, prompting."}}'
  exit 0
fi
decision() { jq -nc --arg d "$1" --arg r "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'; exit 0; }
cmd=$(printf '%s' "$input" | python3 "$(dirname "$0")/push-guard.py" --strip) || decision ask "gate-self-merge: push-guard --strip failed"
case "$cmd" in *"gh pr merge"*) ;; *) exit 0 ;; esac
[ "$(printf '%s' "$cmd" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge' | wc -l)" -eq 1 ] || decision ask "one gh pr merge per command"
printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(cd|pushd)[[:space:]]|git[[:space:]]+-C' && decision ask "no cd/-C with gh pr merge: pass -R owner/repo instead"
num=$(printf '%s' "$cmd" | grep -oE 'merge[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1)
# First -R/--repo only: chained commands (`gh pr checks N -R x && gh pr merge N -R x`)
# repeat the flag, and a multi-line repo makes every gh call below fail.
repo=$(printf '%s' "$cmd" | grep -oE '(-R|--repo)[[:space:]=]+[^[:space:];&|]+' | head -1 | sed -E 's/^(-R|--repo)[[:space:]=]+//')
if [ -z "$num" ]; then
  # `gh pr merge <branch|url>`: first non-flag arg after `merge`, resolved to a number
  ref=$(printf '%s' "$cmd" | grep -oE 'pr[[:space:]]+merge([[:space:]]+[^[:space:];&|]+)*' | tr -s ' \t' '\n' | tail -n +3 | grep -vE '^-' | head -1)
  [ -n "$ref" ] && num=$(gh pr view "$ref" ${repo:+-R "$repo"} --json number -q .number 2>/dev/null)
fi
[ -n "$num" ] || decision ask "no PR number parsed: run one gh pr merge per command with a literal PR number and -R repo (no loops or shell variables) so REVIEWED + CI can be checked"
data=$(gh pr view "$num" ${repo:+-R "$repo"} --json labels,statusCheckRollup 2>/dev/null)
[ -n "$data" ] || decision ask "gh pr view failed for #$num"
rev=$(printf '%s' "$data" | jq -r '[.labels[].name] | index("REVIEWED") // empty')
# Only the LATEST run per check name counts: superseded runs cancelled by workflow
# concurrency (re-label, re-push) must not force a prompt once the newest run is green.
# Pending (queued/in-progress/PENDING) is not green; jq failure or zero checks prompts (fail closed).
checks=$(printf '%s' "$data" | jq -c '[.statusCheckRollup[]? | {n:(.name // .context), t:(.startedAt // .createdAt // ""), c:((.conclusion // .state // "") | ascii_upcase), s:((.status // "COMPLETED") | ascii_upcase)}] | group_by(.n) | map(max_by(.t))') || decision ask "could not parse checks for #$num"
total=$(printf '%s' "$checks" | jq 'length')
fail=$(printf '%s' "$checks" | jq '[.[] | select(.c=="FAILURE" or .c=="CANCELLED" or .c=="TIMED_OUT" or .c=="STARTUP_FAILURE" or .c=="ERROR" or .c=="ACTION_REQUIRED")] | length')
pend=$(printf '%s' "$checks" | jq '[.[] | select(.s!="COMPLETED" or .c=="" or .c=="PENDING" or .c=="EXPECTED")] | length')
[ -n "$rev" ] || decision ask "PR #$num lacks REVIEWED label"
[ "${total:-0}" -gt 0 ] || decision ask "PR #$num has no CI checks"
[ "${fail:-1}" = "0" ] || decision ask "PR #$num has ${fail:-?} failing check(s)"
[ "${pend:-1}" = "0" ] || decision ask "PR #$num has ${pend:-?} pending check(s); wait for CI"
decision allow "PR #$num REVIEWED + CI green"
