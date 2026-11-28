#!/bin/bash
# Feeds JSON to stop-gate and protect-lint-config in temp repos and checks decisions.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$REPO/claude/hooks"
fail=0
tmp="$(mktemp -d)"
export TMPDIR="$tmp"
unset CLAUDE_STOP_GATE_CMD

git init -q "$tmp/clean"
git -C "$tmp/clean" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git init -q "$tmp/dirty"
git -C "$tmp/dirty" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
echo x > "$tmp/dirty/f.txt"
mkdir "$tmp/plain"

pass() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

gate() {
  jq -n --arg d "$1" --argjson a "$2" '{cwd:$d,session_id:"s1",stop_hook_active:$a}' |
    bash "$HOOKS/stop-gate.sh" 2>/dev/null
}

check_gate() {
  local name="$1" want="$2" dir="$3" active="$4" cmd="$5" got
  got="$(CLAUDE_STOP_GATE_CMD="$cmd" gate "$dir" "$active" | jq -r '.decision // empty')"
  got="${got:-allow}"
  if [ "$got" = "$want" ]; then pass "$name"; else bad "$name -> $got (want $want)"; fi
}

check_gate "non-git dir allows"            allow "$tmp/plain" false "false"
check_gate "clean tree allows"             allow "$tmp/clean" false "false"
check_gate "dirty + passing cmd allows"    allow "$tmp/dirty" false "true"
check_gate "dirty + failing cmd blocks"    block "$tmp/dirty" false "echo boom; false"
reason="$(CLAUDE_STOP_GATE_CMD='echo boom; false' gate "$tmp/dirty" false | jq -r '.reason')"
case "$reason" in *boom*) pass "block reason carries output" ;; *) bad "block reason: $reason" ;; esac
check_gate "same failure under stop_hook_active allows" allow "$tmp/dirty" true "echo boom; false"
check_gate "different failure under stop_hook_active blocks" block "$tmp/dirty" true "echo other; false"

mkdir -p "$tmp/dirty/.claude"
echo "echo filecmd; false" > "$tmp/dirty/.claude/stop-gate"
got="$(gate "$tmp/dirty" false | jq -r '.decision // empty')"
[ -z "$got" ] && pass "untrusted repo: .claude/stop-gate not run" || bad "untrusted repo ran repo command: $got"
git -C "$tmp/dirty" remote add origin https://github.com/someone-else/repo.git
got="$(CLAUDE_STOP_GATE_OWNERS="me" gate "$tmp/dirty" false | jq -r '.decision // empty')"
[ -z "$got" ] && pass "other owner: .claude/stop-gate not run" || bad "other owner ran repo command: $got"
git -C "$tmp/dirty" remote set-url origin git@github.com:me/repo.git
got="$(CLAUDE_STOP_GATE_OWNERS="org me" gate "$tmp/dirty" false | jq -r '.reason // empty')"
case "$got" in *filecmd*) pass "trusted owner: .claude/stop-gate used" ;; *) bad ".claude/stop-gate file: $got" ;; esac

lint() {
  jq -n --arg f "$1" --arg o "${2:-}" --arg n "${3:-}" '{tool_input:{file_path:$f,old_string:$o,new_string:$n}}' |
    bash "$HOOKS/protect-lint-config.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

check_lint() {
  local got
  got="$(lint "$2" "${3:-}" "${4:-}")"
  got="${got:-none}"
  if [ "$got" = "$1" ]; then pass "lint $2 -> $1"; else bad "lint $2 -> $got (want $1)"; fi
}

check_lint ask  /r/eslint.config.js
check_lint ask  /r/.eslintrc.json
check_lint ask  /r/.pre-commit-config.yaml
check_lint ask  /r/aiq-lint-baseline.json
check_lint ask  /r/some-baseline.json
check_lint none /r/src/app.ts
check_lint ask  /r/pyproject.toml '[tool.ruff]
select = ["E"]' '[tool.ruff]
select = []'
check_lint none /r/pyproject.toml '[project]
name = "a"' '[project]
name = "b"'
check_lint ask  /r/tsconfig.json '"strict": true' '"strict": false'
check_lint none /r/tsconfig.json '"target": "es2020"' '"target": "es2022"'

rc=$(jq -n '{tool_input:{file_path:"/r/pyproject.toml",content:"[tool.mypy]\nstrict=false\n"}}' | bash "$HOOKS/protect-lint-config.sh" | jq -r '.hookSpecificOutput.permissionDecision')
if [ "$rc" = ask ]; then pass "pyproject Write content with [tool.mypy] -> ask"; else bad "pyproject Write content -> $rc"; fi
echo "-- stop-gate fingerprint"
git init -q "$tmp/fp"
git -C "$tmp/fp" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
echo a > "$tmp/fp/f.txt"
runs="$tmp/runs"
fpgate() {
  jq -n --arg d "$tmp/fp" '{cwd:$d,session_id:"fp1",stop_hook_active:false}' |
    CLAUDE_STOP_GATE_CMD="echo r >> '$runs'; $1" bash "$HOOKS/stop-gate.sh" 2>/dev/null
}
count() { if [ -f "$runs" ]; then wc -l < "$runs" | tr -d ' '; else echo 0; fi; }
want_count() { local c; c="$(count)"; if [ "$c" = "$2" ]; then pass "$1"; else bad "$1: ran $c times, want $2"; fi; }
fpgate true >/dev/null; fpgate true >/dev/null
want_count "same tree twice runs the check once" 1
echo b >> "$tmp/fp/f.txt"; fpgate true >/dev/null
want_count "changed untracked file reruns" 2
echo new > "$tmp/fp/g.txt"; fpgate true >/dev/null
want_count "added untracked file reruns" 3
git -C "$tmp/fp" add -A; git -C "$tmp/fp" -c user.name=t -c user.email=t@t commit -q -m c
echo c >> "$tmp/fp/f.txt"; fpgate true >/dev/null
want_count "changed tracked file reruns" 4
fpgate true >/dev/null
want_count "unchanged tracked diff does not rerun" 4
echo d >> "$tmp/fp/f.txt"
r1="$(fpgate false | jq -r '.decision // empty')"; r2="$(fpgate false | jq -r '.decision // empty')"
want_count "failing run is not stored as green" 6
if [ "$r1" = block ] && [ "$r2" = block ]; then pass "failure blocks both times"; else bad "failure decisions: $r1 $r2"; fi
exit $fail
