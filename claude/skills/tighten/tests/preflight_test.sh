#!/bin/bash
# Plain-bash tests for scripts/preflight.sh.
# Uses a real local git remote (bare repo + clone) and a fake `gh` on PATH that answers
# from environment variables. Run: bash tests/preflight_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PREFLIGHT="$HERE/../scripts/preflight.sh"
TMP=$(mktemp -d)
trap 'mv "$TMP" "${TMPDIR:-/tmp}/tighten-preflight-test-$$" 2>/dev/null' EXIT
pass=0 fail=0

# --- fake gh --------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/bash
# Fake gh: `gh pr view [N] --json ...` and `gh repo view --json ...`, driven by GH_* vars.
args="$*"
case "$args" in
  "pr view --json number --jq .number") echo "${GH_PR:-7}" ;;
  "repo view --json defaultBranchRef --jq .defaultBranchRef.name") echo "${GH_DEFAULT:-main}" ;;
  pr\ view\ *--json*)
    jq -cn --argjson n "${GH_PR:-7}" --arg state "${GH_STATE:-OPEN}" --arg base "${GH_BASE:-main}" \
      --argjson cross "${GH_CROSS:-false}" --argjson labels "${GH_LABELS:-[]}" \
      --argjson comments "${GH_COMMENTS:-[]}" --arg head "${GH_HEAD:-feat}" \
      '{number:$n, url:"https://example.test/pr/\($n)", title:"Add thing", state:$state,
        isDraft:false, headRefName:$head, baseRefName:$base, isCrossRepository:$cross,
        labels:($labels|map({name:.})), mergedAt:null, comments:($comments|map({body:.})),
        author:{login:"user"}}' ;;
  *) echo "fake gh: unhandled: $args" >&2; exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# --- real git fixture -----------------------------------------------------------
git init -q --bare "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/work/demo_app" 2>/dev/null
REPO="$TMP/work/demo_app"
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
printf '{"name":"x"}\n' > "$REPO/package.json"; : > "$REPO/tsconfig.json"
printf '# Changelog\n\n- **feat-530** thing\n- **test-531** other\n' > "$REPO/CHANGELOG.md"
git -C "$REPO" add -A; git -C "$REPO" commit -qm "init"
git -C "$REPO" branch -M main; git -C "$REPO" push -q -u origin main
git -C "$REPO" checkout -qb feat
echo "x" > "$REPO/a.ts"; git -C "$REPO" add -A; git -C "$REPO" commit -qm "[DEMO-1] feat: add a"
git -C "$REPO" push -q -u origin feat
git -C "$REPO" checkout -q main

printf '| Repo | Lang | Deploy | Test | Lint | Port |\n|---|---|---|---|---|---|\n| demo_app | TypeScript, Next.js 16 | Docker | `npm run test` | `npm run lint` | 3000 |\n' > "$TMP/REPOS.md"
export TIGHTEN_REPOS_MD="$TMP/REPOS.md"
export TIGHTEN_WORKTREE_PARENT="$TMP/wt"
mkdir -p "$TMP/wt"

run() { (cd "$REPO" && bash "$PREFLIGHT" "$@"); }
cleanup_wt() { git -C "$REPO" worktree remove --force "$TMP/wt/demo_app-tighten-7" 2>/dev/null; git -C "$REPO" worktree prune; }

check() { # <name> <json> <jq expr> <want>
  local got; got=$(printf '%s' "$2" | jq -r "$3")
  if [ "$got" = "$4" ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: want '$4' got '$got'"; echo "     $2"; fi
}

out=$(GH_STATE=MERGED run 7);        check "merged PR refuses" "$out" .status refuse
check "merged reason mentions follow-up" "$out" '.reason | contains("follow-up")' true
out=$(GH_STATE=CLOSED run 7);        check "closed PR refuses" "$out" .status refuse
out=$(GH_CROSS=true run 7);          check "fork PR refuses" "$out" .status refuse
out=$(GH_BASE=develop run 7);        check "non-default base refuses" "$out" .status refuse
out=$(GH_LABELS='["tightened"]' run 7); check "tightened label skips" "$out" .status skip
out=$(GH_COMMENTS='["<!-- tighten:pass tier=1 -->\nstuff"]' run 7); check "comment marker skips" "$out" .status skip
out=$(run --followup 7);             check "--followup refuses" "$out" .status refuse
out=$(run --bogus 7);                check "unknown flag refuses" "$out" .status refuse

# unpushed commit on the branch in the primary checkout -> refuse
git -C "$REPO" checkout -q feat; echo y > "$REPO/b.ts"; git -C "$REPO" add -A; git -C "$REPO" commit -qm "wip"
out=$(run 7);                        check "unpushed commits refuse" "$out" .status refuse
check "unpushed reason names the path" "$out" '.reason | contains("unpushed")' true
git -C "$REPO" push -q origin feat; git -C "$REPO" checkout -q main

# happy path
out=$(run 7)
check "happy path goes" "$out" .status go
check "branch" "$out" .branch feat
check "base" "$out" .base main
check "worktree path" "$out" .worktree "$TMP/wt/demo_app-tighten-7"
check "worktree exists and is detached" "$(jq -cn --arg d "$(git -C "$TMP/wt/demo_app-tighten-7" symbolic-ref -q HEAD 2>/dev/null || echo detached)" '{d:$d}')" .d detached
check "worktree HEAD matches origin/feat" "$(jq -cn --arg a "$(git -C "$TMP/wt/demo_app-tighten-7" rev-parse HEAD)" --arg b "$(git -C "$REPO" rev-parse origin/feat)" '{same:($a==$b)}')" .same true
check "test cmd from REPOS.md" "$out" .test "npm run test"
check "lint cmd from REPOS.md" "$out" .lint "npm run lint"
check "typecheck detected from tsconfig" "$out" .typecheck "npx tsc --noEmit"
check "lang from REPOS.md" "$out" .lang "TypeScript, Next.js 16"
check "ticket prefix detected" "$out" .prefix "[DEMO-1]"
check "changelog style bold" "$out" .changelog.style bold
check "changelog next id" "$out" .changelog.next 532
check "other_checkout is empty when branch not checked out" "$out" .other_checkout ""
check "flags default" "$out" '.flags | "\(.again) \(.dry) \(.tier)"' "false false "

# stale worktree dir from a previous run -> refuse
out=$(run 7);                        check "existing worktree dir refuses" "$out" .status refuse
cleanup_wt

# flags and --again bypass
out=$(GH_LABELS='["tightened"]' run 7 --again --dry --tier 2)
check "--again bypasses label guard" "$out" .status go
check "--dry recorded" "$out" .flags.dry true
check "--tier recorded" "$out" .flags.tier 2
cleanup_wt

# PR number resolved from gh when omitted
out=$(run);                          check "PR number from gh pr view" "$out" .pr 7
cleanup_wt

# repo not in REPOS.md falls back to detection
export TIGHTEN_REPOS_MD="$TMP/none.md"
out=$(run 7);                        check "fallback test cmd" "$out" .test "npm test"
check "fallback lint cmd" "$out" .lint "npm run lint"
cleanup_wt

# branch checked out elsewhere but fully pushed -> go, other_checkout reported
git -C "$REPO" worktree add -q "$TMP/wt/elsewhere" feat
out=$(run 7);                        check "pushed branch elsewhere goes" "$out" .status go
check "other_checkout reported" "$out" .other_checkout "$TMP/wt/elsewhere"
cleanup_wt
git -C "$REPO" worktree remove --force "$TMP/wt/elsewhere"

# --- file mode --------------------------------------------------------------------
export TIGHTEN_REPOS_MD="$TMP/REPOS.md"
NOTE="$REPO/notes/study.md"; mkdir -p "$REPO/notes"
printf -- '---\ntags: [x]\n---\n# Note\n\nSee [[other]]. Built 9 Oct 2026.\n' > "$NOTE"
git -C "$REPO" add -A; git -C "$REPO" commit -qm "add note"

out=$(run "$NOTE");                  check "file: clean tracked goes" "$out" .status go
check "file: mode" "$out" .mode file
check "file: kind prose" "$out" .kind prose
check "file: tracked" "$out" .tracked true
check "file: not dirty" "$out" .dirty false
check "file: in place" "$out" .in_place true
check "file: out_path is the file" "$out" .out_path "$NOTE"
check "file: lines counted" "$out" .lines 6
check "file: repo_root" "$out" .repo_root "$REPO"
out=$(run "$NOTE" --dry);            check "file: --dry recorded" "$out" .flags.dry true
out=$(cd "$REPO/notes" && bash "$PREFLIGHT" study.md); check "file: relative path resolves" "$out" .path "$NOTE"

echo "edit" >> "$NOTE"
out=$(run "$NOTE");                  check "file: dirty tracked goes" "$out" .status go
check "file: dirty flagged" "$out" .dirty true
check "file: dirty writes beside" "$out" .out_path "$REPO/notes/study.tightened.md"
check "file: dirty not in place" "$out" .in_place false
git -C "$REPO" checkout -q -- "$NOTE"

printf '# Draft\n' > "$REPO/notes/draft.md"
out=$(run "$REPO/notes/draft.md");  check "file: untracked goes beside" "$out" .out_path "$REPO/notes/draft.tightened.md"
check "file: untracked flagged" "$out" .tracked false

mkdir -p "$TMP/norepo"; printf 'plain text\nmore\n' > "$TMP/norepo/readme"
out=$(run "$TMP/norepo/readme");    check "file: non-repo goes" "$out" .status go
check "file: non-repo no root" "$out" .repo_root ""
check "file: no-extension prose" "$out" .kind prose
check "file: no-extension out name" "$out" .out_path "$TMP/norepo/readme.tightened"

printf '#!/bin/bash\necho hi\n' > "$TMP/norepo/tool"
out=$(run "$TMP/norepo/tool");      check "file: shebang means code" "$out" .kind code

printf 'package main\nfunc main() {}\n' > "$REPO/main.go"; : > "$REPO/go.mod"
git -C "$REPO" add -A; git -C "$REPO" commit -qm "go"
out=$(run "$REPO/main.go");         check "file: code kind" "$out" .kind code
check "file: code typecheck from repo" "$out" .typecheck "go vet ./..."
check "file: code lint from REPOS.md row" "$out" .lint "npm run lint"

head -c 64 /dev/urandom > "$TMP/norepo/blob.md"; printf '\0\0binary' >> "$TMP/norepo/blob.md"
out=$(run "$TMP/norepo/blob.md");   check "file: binary refuses" "$out" .status refuse
check "file: binary reason" "$out" '.reason | contains("binary")' true

seq 1 2001 > "$TMP/norepo/big.txt"
out=$(run "$TMP/norepo/big.txt");   check "file: too large refuses" "$out" .status refuse
check "file: too large reason" "$out" '.reason | contains("2001 lines")' true
out=$(TIGHTEN_MAX_FILE_LINES=3000 run "$TMP/norepo/big.txt"); check "file: limit override" "$out" .status go

: > "$TMP/norepo/empty.md"
out=$(run "$TMP/norepo/empty.md");  check "file: empty refuses" "$out" .status refuse
printf 'x' > "$TMP/norepo/thing.xyz"
out=$(run "$TMP/norepo/thing.xyz"); check "file: unknown extension refuses" "$out" .status refuse
out=$(run "$TMP/norepo");           check "file: directory refuses" "$out" .status refuse

chmod -w "$TMP/norepo"
out=$(TIGHTEN_SCRATCHPAD="$TMP/scratch" run "$TMP/norepo/readme")
check "file: unwritable dir falls back to scratchpad" "$out" .out_path "$TMP/scratch/readme.tightened"
check "file: unwritable flagged" "$out" .writable false
chmod u+w "$TMP/norepo"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
