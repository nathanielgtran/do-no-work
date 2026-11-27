#!/bin/bash
# Runs repo-bootstrap --review and review-rollout against a fake gh that logs argv and stdin.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

TMP="$(mktemp -d)"
mkdir "$TMP/bin"
SHA_A=1111111111111111111111111111111111111111
SHA_B=2222222222222222222222222222222222222222
printf 'steps:\n  - uses: anthropics/claude-code-action@%s # v1\n' "$SHA_A" > "$TMP/cr.yml"
printf 'runs:\n  steps:\n    - uses: oven-sh/setup-bun@%s # v2\n' "$SHA_B" > "$TMP/action.yml"
cat > "$TMP/bin/gh" <<'FAKE'
#!/bin/bash
echo "$*" >> "$GH_LOG"
DEFAULT_LABELS='[{"name":"REVIEWED"}]'
DEFAULT_RUNNERS='{"runners":[]}'
if [[ "$*" == *"--input -"* ]]; then cat >> "$GH_BODY"; echo >> "$GH_BODY"; fi
case "$*" in
  "pr create"*) cat >> "$GH_PRBODY"; echo "https://github.com/o/r/pull/1" ;;
  "pr list"*) case "$*" in *review-harden*) echo "${FAKE_PR_HARDEN:-}" ;; *) echo "${FAKE_PR:-}" ;; esac ;;
  *"/actions/runners?"*) echo "${FAKE_RUNNERS:-$DEFAULT_RUNNERS}" ;;
  *"commits/"*) echo "${FAKE_SHA:-cccccccccccccccccccccccccccccccccccccccc}" ;;
  *"contents/.github/workflows/review.yml"*"--jq .sha"*) echo blob123 ;;
  *"contents/.github/workflows/review.yml?ref=NO-TICKET"*)
    if [ -f "$FAKE_BRANCH_CALLER" ]; then cat "$FAKE_BRANCH_CALLER"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
  "secret list"*) echo "${FAKE_SECRETS:-}" ;;
  "secret set"*) cat >> "$GH_STDIN" ;;
  "repo view"*) echo "${FAKE_VIS:-PRIVATE}" ;;
  *"-X "*) echo '{}' ;;
  *"actions/permissions/selected-actions") cat "$FAKE_SELECTED" ;;
  *"actions/permissions --jq"*) echo "${FAKE_MODE:-selected}" ;;
  *"/labels?"*) echo "${FAKE_LABELS-$DEFAULT_LABELS}" ;;
  *"contents/.github/workflows/claude-review.yml"*) cat "$FAKE_CR" ;;
  *"claude-code-action/contents/action.yml"*) cat "$FAKE_ACTION" ;;
  *"contents/examples/claude-review-caller.yml"*) cat "$FAKE_EXAMPLE" ;;
  *"contents/.github/workflows/review.yml"*)
    if [ -f "$FAKE_CALLER" ]; then cat "$FAKE_CALLER"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
  *"contents/.github/workflows") echo '[]' ;;
  *"--jq .default_branch"*) echo main ;;
  *"--jq .object.sha"*) echo abc123 ;;
  *) echo '{}' ;;
esac
FAKE
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_LOG="$TMP/log" GH_BODY="$TMP/body" GH_PRBODY="$TMP/prbody" GH_STDIN="$TMP/stdin"
export FAKE_CR="$TMP/cr.yml" FAKE_ACTION="$TMP/action.yml" FAKE_SELECTED="$TMP/sel.json"
export FAKE_CALLER="$TMP/caller.yml" FAKE_BRANCH_CALLER="$TMP/branch.yml" FAKE_EXAMPLE="$REPO/examples/claude-review-caller.yml"
BS="$REPO/bin/repo-bootstrap"
GOOD_CALLER=""
OLD_CALLER=$'permissions:\n  pull-requests: write\nuses: nathanielgtran/do-no-work/.github/workflows/claude-review.yml@main\n'
decode() { grep -o 'content=[^ ]*' "$GH_LOG" | head -1 | cut -d= -f2- | base64 -d > "$1"; }

reset() {
  : > "$GH_LOG"; : > "$GH_BODY"; : > "$GH_PRBODY"; : > "$GH_STDIN"
  unset FAKE_MODE FAKE_PR FAKE_PR_HARDEN FAKE_SECRETS FAKE_LABELS FAKE_RUNNERS FAKE_SHA FAKE_VIS \
    CLAUDE_CODE_OAUTH_TOKEN BOOTSTRAP_REVIEW_RUNS_ON BOOTSTRAP_REVIEW_REF || true
  if [ -f "$FAKE_BRANCH_CALLER" ]; then mv "$FAKE_BRANCH_CALLER" "$TMP/branch.gone.$RANDOM"; fi
  printf '{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":["astral-sh/setup-uv@*"]}' > "$FAKE_SELECTED"
  printf '%s' "$GOOD_CALLER" > "$FAKE_CALLER"
  export FAKE_SECRETS=CLAUDE_CODE_OAUTH_TOKEN
}

reset
mv "$FAKE_CALLER" "$TMP/caller.gone"
"$BS" o/r --review > "$TMP/out"
decode "$TMP/good.yml"
GOOD_CALLER=$(cat "$TMP/good.yml")

echo "-- allowlist merge"
reset
"$BS" o/r --review > "$TMP/out"
check "PUT selected-actions" "grep -q -- '-X PUT repos/o/r/actions/permissions/selected-actions' '$GH_LOG'"
check "keeps existing pattern" "jq -e '.patterns_allowed | index(\"astral-sh/setup-uv@*\")' '$GH_BODY' >/dev/null"
check "adds action pin" "jq -e '.patterns_allowed | index(\"anthropics/claude-code-action@$SHA_A\")' '$GH_BODY' >/dev/null"
check "adds setup-bun pin from action.yml" "jq -e '.patterns_allowed | index(\"oven-sh/setup-bun@$SHA_B\")' '$GH_BODY' >/dev/null"
check "reads action.yml at pinned sha" "grep -q 'action.yml?ref=$SHA_A' '$GH_LOG'"
check "summary line" "grep -q 'summary label=ok allowlist=updated caller=ok secret=ok' '$TMP/out'"
reset
printf '{"patterns_allowed":["anthropics/claude-code-action@%s","oven-sh/setup-bun@%s"]}' "$SHA_A" "$SHA_B" > "$FAKE_SELECTED"
"$BS" o/r --review > "$TMP/out"
check "no write when pins present" "! grep -q -- '-X PUT repos/o/r/actions' '$GH_LOG'"

echo "-- allowed_actions all"
reset
FAKE_MODE=all "$BS" o/r --review > "$TMP/out"
check "all skips allowlist" "grep -q 'allowlist=skip(all)' '$TMP/out' && ! grep -q 'selected-actions' '$GH_LOG'"

echo "-- caller missing"
reset
rm_caller() { mv "$FAKE_CALLER" "$TMP/caller.gone"; }
rm_caller
"$BS" o/r --review > "$TMP/out"
check "creates branch" "grep -q -- '-X POST repos/o/r/git/refs .*ref=refs/heads/NO-TICKET-claude-review.*sha=abc123' '$GH_LOG'"
check "PUTs caller" "grep -q -- '-X PUT repos/o/r/contents/.github/workflows/review.yml' '$GH_LOG'"
check "opens PR" "grep -q '^pr create -R o/r --base main --head NO-TICKET-claude-review' '$GH_LOG'"
check "PR body has template headings" "grep -q '^## What' '$GH_PRBODY' && grep -q '^## Risk + rollback' '$GH_PRBODY' && grep -q '^## Checklist' '$GH_PRBODY'"
content=$(grep -o 'content=[^ ]*' "$GH_LOG" | head -1 | cut -d= -f2-)
printf '%s' "$content" | base64 -d > "$TMP/rendered.yml"
check "private caller passes runs-on input" "grep -q \"runs-on: '\\\"ubuntu-latest\\\"'\" '$TMP/rendered.yml'"
check "caller keeps pull-requests: write" "grep -q 'pull-requests: write' '$TMP/rendered.yml'"
check "caller has no comments" "! grep -q '^ *#' '$TMP/rendered.yml'"
reset; rm_caller
BOOTSTRAP_REVIEW_RUNS_ON='["self-hosted","nuc"]' "$BS" o/r --review > "$TMP/out"
content=$(grep -o 'content=[^ ]*' "$GH_LOG" | head -1 | cut -d= -f2-)
printf '%s' "$content" | base64 -d > "$TMP/rendered.yml"
check "private runs-on override" "grep -q 'self-hosted' '$TMP/rendered.yml'"
reset; rm_caller
"$BS" o/r --review --public > "$TMP/out"
content=$(grep -o 'content=[^ ]*' "$GH_LOG" | head -1 | cut -d= -f2-)
printf '%s' "$content" | base64 -d > "$TMP/rendered.yml"
check "public caller has no with/runs-on" "! grep -q 'runs-on' '$TMP/rendered.yml'"
reset; rm_caller
check "public refuses self-hosted runs-on" "! BOOTSTRAP_REVIEW_RUNS_ON=self-hosted '$BS' o/r --review --public >/dev/null 2>&1"
check "public refusal makes no writes" "! grep -q -- '-X ' '$GH_LOG'"
reset; rm_caller
printf '%s' "$GOOD_CALLER" > "$FAKE_BRANCH_CALLER"
FAKE_PR=https://github.com/o/r/pull/9 "$BS" o/r --review > "$TMP/out"
check "open current PR is not duplicated" "! grep -q -- '-X .*contents/' '$GH_LOG' && grep -q 'caller=pr-open' '$TMP/out'"

echo "-- caller render"
reset; rm_caller
"$BS" o/r --review > "$TMP/out"
decode "$TMP/r.yml"
SHA=$(grep -oE '@[0-9a-f]{40}' "$TMP/r.yml" | head -1 | tr -d @)
check "fork guard on the job" "grep -q '^    if: github.event.pull_request.head.repo.full_name == github.repository\$' '$TMP/r.yml'"
check "top-level permissions empty" "grep -qx 'permissions: {}' '$TMP/r.yml'"
check "pinned to a 40-hex SHA with comment" "grep -qE 'claude-review.yml@[0-9a-f]{40} # do-no-work [0-9a-f]{7}\$' '$TMP/r.yml'"
check "tools-ref matches the pin" "[ -n '$SHA' ] && grep -q 'tools-ref: $SHA\$' '$TMP/r.yml'"
check "not pinned to main" "! grep -q '@main' '$TMP/r.yml'"
check "reads example at the SHA" "grep -q 'claude-review-caller.yml?ref=$SHA' '$GH_LOG'"
reset; rm_caller
BOOTSTRAP_REVIEW_REF=v9.9 "$BS" o/r --review > "$TMP/out"
check "ref override resolved via commits api" "grep -q 'repos/nathanielgtran/do-no-work/commits/v9.9' '$GH_LOG'"
reset; rm_caller
check "non-hex resolved ref rejected" "! FAKE_SHA=main '$BS' o/r --review >/dev/null 2>&1"
check "non-hex rejection makes no writes" "! grep -q -- '-X ' '$GH_LOG'"
reset; rm_caller
check "bad ref characters rejected" "! BOOTSTRAP_REVIEW_REF='x;y' '$BS' o/r --review >/dev/null 2>&1"

echo "-- runner auto-pick"
runs_on_for() { reset; rm_caller; "$@" "$BS" o/r --review > "$TMP/out"; decode "$TMP/r.yml"; }
runs_on_for env FAKE_RUNNERS='{"runners":[{"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"X64"},{"name":"nuc"},{"name":"nuc-kachink"}]}]}'
check "picks repo-specific nuc-kachink" "grep -qF \"runs-on: '[\\\"self-hosted\\\",\\\"nuc-kachink\\\"]'\" '$TMP/r.yml'"
runs_on_for env FAKE_RUNNERS='{"runners":[{"labels":[{"name":"self-hosted"},{"name":"nuc"}]}]}'
check "falls back to nuc" "grep -qF 'runs-on: '\"'\"'[\"self-hosted\",\"nuc\"]' '$TMP/r.yml'"
runs_on_for env FAKE_RUNNERS='{"runners":[{"labels":[{"name":"self-hosted"},{"name":"nuc"},{"name":"nuc-a"},{"name":"nuc-b"}]}]}'
check "two specific labels fall back to nuc" "grep -qF '\"nuc\"]' '$TMP/r.yml' && ! grep -q 'nuc-a' '$TMP/r.yml'"
runs_on_for env FAKE_RUNNERS='{"runners":[]}'
check "no runners: ubuntu-latest with note" "grep -q 'ubuntu-latest' '$TMP/r.yml' && grep -q '^note runner: no nuc' '$TMP/out'"
runs_on_for env FAKE_RUNNERS='{"runners":[{"labels":[{"name":"nuc-kachink"},{"name":"nuc"}]}]}' FAKE_VIS=PUBLIC
check "public repo detected: ubuntu-latest, no runs-on" "! grep -q 'runs-on' '$TMP/r.yml' && ! grep -q 'self-hosted' '$TMP/r.yml'"
runs_on_for env FAKE_RUNNERS='{"runners":[{"labels":[{"name":"nuc-kachink"},{"name":"nuc"}]}]}' BOOTSTRAP_REVIEW_RUNS_ON=ubuntu-latest
check "explicit override beats auto" "grep -q 'ubuntu-latest' '$TMP/r.yml' && ! grep -q 'nuc' '$TMP/r.yml'"
runs_on_for env FAKE_RUNNERS='{"runners":[{"labels":[{"name":"nuc-kachink"},{"name":"nuc"}]}]}' BOOTSTRAP_REVIEW_RUNS_ON=auto
check "explicit auto picks" "grep -q 'nuc-kachink' '$TMP/r.yml'"

echo "-- skip-changelog"
reset; rm_caller
FAKE_LABELS='[{"name":"REVIEWED"},{"name":"skip-changelog"}]' "$BS" o/r --review > "$TMP/out"
check "label applied when it exists" "grep -q '^pr edit -R o/r https://github.com/o/r/pull/1 --add-label skip-changelog\$' '$GH_LOG'"
reset; rm_caller
"$BS" o/r --review > "$TMP/out"
check "no label call when absent" "! grep -q '^pr edit' '$GH_LOG'"

echo "-- update mode"
reset
check "current default caller prints ok" "'$BS' o/r --review | grep -q 'caller=ok'"
check "current caller makes no caller writes" "! grep -q -- '-X .*\(contents\|git/refs\)' '$GH_LOG'"
reset
printf '%s' "$OLD_CALLER" > "$FAKE_CALLER"
FAKE_LABELS='[{"name":"REVIEWED"},{"name":"skip-changelog"}]' "$BS" o/r --review > "$TMP/out"
check "old default caller: harden branch" "grep -q -- '-X POST repos/o/r/git/refs .*ref=refs/heads/NO-TICKET-claude-review-harden' '$GH_LOG'"
check "writes review.yml with blob sha" "grep -q -- '-X PUT repos/o/r/contents/.github/workflows/review.yml .*branch=NO-TICKET-claude-review-harden.*sha=blob123' '$GH_LOG'"
check "harden PR title" "grep -qF -- '--head NO-TICKET-claude-review-harden --title [NO-TICKET] ci: harden Claude review caller (pin SHA, fork guard)' '$GH_LOG'"
check "harden PR body template + fixes" "grep -q '^## Proof' '$GH_PRBODY' && grep -q '^## Risk + rollback' '$GH_PRBODY' && grep -q 'Fork guard' '$GH_PRBODY' && grep -q 'SHA pin' '$GH_PRBODY'"
check "harden PR gets skip-changelog" "grep -q '^pr edit .*--add-label skip-changelog' '$GH_LOG'"
decode "$TMP/h.yml"
check "hardened file has guard and pin" "grep -q 'if: github.event.pull_request' '$TMP/h.yml' && grep -qE '@[0-9a-f]{40}' '$TMP/h.yml'"
check "only review.yml contents touched" "! grep -- '-X PUT .*contents/' '$GH_LOG' | grep -qv 'contents/.github/workflows/review.yml'"
check "summary says pr-opened" "grep -q 'caller=pr-opened' '$TMP/out'"
reset
printf '%s' "$OLD_CALLER" > "$FAKE_BRANCH_CALLER"
FAKE_PR=https://github.com/o/r/pull/9 FAKE_LABELS='[{"name":"skip-changelog"},{"name":"REVIEWED"}]' "$BS" o/r --review > "$TMP/out"
check "open caller PR: updates its branch" "grep -q -- '-X PUT repos/o/r/contents/.github/workflows/review.yml .*branch=NO-TICKET-claude-review .*sha=blob123' '$GH_LOG'"
check "open caller PR: no new branch or PR" "! grep -q -- '-X POST repos/o/r/git/refs' '$GH_LOG' && ! grep -q '^pr create' '$GH_LOG'"
check "open caller PR: comments" "grep -q '^pr comment https://github.com/o/r/pull/9 ' '$GH_LOG' && grep -q 'caller=pr-updated' '$TMP/out'"
reset
printf '%s' "$OLD_CALLER" > "$FAKE_BRANCH_CALLER"
FAKE_PR_HARDEN=https://github.com/o/r/pull/10 "$BS" o/r --review > "$TMP/out"
check "open harden PR is refreshed, not duplicated" "grep -q 'branch=NO-TICKET-claude-review-harden' '$GH_LOG' && ! grep -q '^pr create' '$GH_LOG' && ! grep -q -- 'git/refs' '$GH_LOG'"
reset
printf '%s' "$OLD_CALLER" > "$FAKE_CALLER"
FAKE_LABELS='[{"name":"REVIEWED"},{"name":"skip-changelog"}]' "$BS" o/r --review --dry-run > "$TMP/out"
check "update dry run: no mutating calls" "! grep -q -e '-X ' -e '^pr create' -e '^pr edit' -e '^pr comment' '$GH_LOG'"
check "update dry run: plans harden PR" "grep -q 'dry  gh pr create .*NO-TICKET-claude-review-harden' '$TMP/out' && grep -q 'dry  gh pr edit .*skip-changelog' '$TMP/out'"

echo "-- secret"
reset
FAKE_SECRETS="" CLAUDE_CODE_OAUTH_TOKEN="sk-secret-value" "$BS" o/r --review > "$TMP/out"
check "secret set called" "grep -q '^secret set CLAUDE_CODE_OAUTH_TOKEN -R o/r\$' '$GH_LOG'"
check "token arrives on stdin" "[ \"\$(cat '$GH_STDIN')\" = sk-secret-value ]"
check "token not in argv log" "! grep -q 'sk-secret-value' '$GH_LOG'"
check "token not in output" "! grep -q 'sk-secret-value' '$TMP/out'"
reset
FAKE_SECRETS="" "$BS" o/r --review > "$TMP/out"
check "fix line without env" "grep -q '^fix: gh secret set CLAUDE_CODE_OAUTH_TOKEN -R o/r' '$TMP/out' && grep -q 'claude setup-token' '$TMP/out'"
check "no secret set without env" "! grep -q '^secret set' '$GH_LOG'"

echo "-- dry run"
reset; rm_caller
FAKE_SECRETS="" FAKE_LABELS='[]' CLAUDE_CODE_OAUTH_TOKEN="sk-secret-value" "$BS" o/r --review --dry-run > "$TMP/out"
check "no mutating calls" "! grep -q -e '-X ' -e '^pr create' -e '^secret set' '$GH_LOG'"
check "prints planned writes" "grep -q 'dry  PUT' '$TMP/out' && grep -q 'dry  gh pr create' '$TMP/out' && grep -q 'dry  gh secret set' '$TMP/out' && grep -q 'dry  POST repos/o/r/labels' '$TMP/out'"

echo "-- review-rollout"
RO="$REPO/bin/review-rollout"
reset
mv "$FAKE_CALLER" "$TMP/caller.gone"
FAKE_VIS=PUBLIC "$RO" o/r o/r2 > "$TMP/out" 2> "$TMP/err" || true
check "table header" "grep -q 'repo.*label.*allowlist.*caller.*secret' '$TMP/out'"
check "row per repo" "grep -q '^o/r ' '$TMP/out' && grep -q '^o/r2 ' '$TMP/out'"
check "public repo gets --public path" "! grep -q 'with:' '$GH_BODY'"
reset
"$RO" notarepo o/r > "$TMP/out" 2> "$TMP/err" || true
check "continues after a bad repo" "grep -q '^notarepo .*FAILED' '$TMP/out' && grep -q '^o/r ' '$TMP/out'"

mv "$TMP" "$HOME/.trash/review_test.$$" 2>/dev/null || true
exit $fail
