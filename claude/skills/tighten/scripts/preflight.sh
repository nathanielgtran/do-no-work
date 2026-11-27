#!/bin/bash
# preflight.sh - PR state checks, re-entry guard, detached worktree, repo commands.
#
# Usage: preflight.sh [PR#] [--again] [--dry] [--tier N]      PR mode
#        preflight.sh <path> [--dry]                             file mode (path must exist)
#
# Always exits 0 and prints ONE JSON object. `status` is one of:
#   go      - proceed; `mode` is "pr" or "file" and the other fields follow from it
#   skip    - nothing to do (already tightened, etc.); `reason` says why
#   refuse  - cannot run safely (merged, fork, unpushed commits, binary, ...); `reason` says why
# Exit 0 always because SKILL.md runs this as !` ` preprocessing, where a non-zero
# exit would abort the invocation before the model can label or report.
#
# Env: TIGHTEN_REPOS_MD (default ~/Github/REPOS.md), TIGHTEN_WORKTREE_PARENT
# (default: parent dir of the repo root).
set -uo pipefail

REPOS_MD="${TIGHTEN_REPOS_MD:-$HOME/Github/REPOS.md}"
MAX_FILE_LINES="${TIGHTEN_MAX_FILE_LINES:-2000}"
PROSE_EXT='md|markdown|txt|rst|adoc|asciidoc|org'
CODE_EXT='go|py|ts|tsx|js|jsx|mjs|cjs|sh|bash|zsh|rs|java|kt|rb|php|c|h|cpp|hpp|cs|swift|sql|yaml|yml|toml|json|css|scss|html|vue|svelte|lua|tf|hcl'
AGAIN=0 DRY=0 FORCE_TIER="" PR="" FILE=""

emit() { # emit <status> <reason> [extra jq object]
  jq -cn --arg status "$1" --arg reason "$2" --argjson extra "${3:-{\}}" \
    '{status:$status, reason:$reason} + $extra'
  exit 0
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --again) AGAIN=1 ;;
      --dry) DRY=1 ;;
      --tier) shift; FORCE_TIER="${1:-}" ;;
      --followup) emit refuse "--followup is not in v1; open a follow-up PR by hand" ;;
      -*) emit refuse "unknown flag $1" ;;
      *) if [ -e "$1" ]; then FILE="$1"; else PR="$1"; fi ;;
    esac
    shift
  done
}

# --- PR facts -----------------------------------------------------------------

fetch_pr() { # sets PR_JSON, DEFAULT_BRANCH, ME
  local err
  if [ -z "$PR" ]; then
    PR=$(gh pr view --json number --jq .number 2>&1) || emit refuse "no PR number given and gh pr view failed: $PR"
  fi
  PR_JSON=$(gh pr view "$PR" --json number,url,title,state,isDraft,headRefName,baseRefName,isCrossRepository,labels,mergedAt,comments,author 2>&1) \
    || emit refuse "gh pr view $PR failed: $PR_JSON"
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>&1) \
    || emit refuse "gh repo view failed: $DEFAULT_BRANCH"
  err=$(printf '%s' "$PR_JSON" | jq -e . >/dev/null 2>&1) || emit refuse "gh returned non-JSON: $PR_JSON"
}

pr_field() { printf '%s' "$PR_JSON" | jq -r "$1"; }

check_state() {
  local state base cross
  state=$(pr_field .state); base=$(pr_field .baseRefName); cross=$(pr_field .isCrossRepository)
  case "$state" in
    MERGED) emit refuse "PR #$PR is merged; tighten cannot push to it. If the cleanup is still wanted, branch from $DEFAULT_BRANCH and open a follow-up PR by hand." ;;
    CLOSED) emit refuse "PR #$PR is closed" ;;
    OPEN) ;;
    *) emit refuse "PR #$PR has unexpected state '$state'" ;;
  esac
  [ "$cross" = "false" ] || emit refuse "PR #$PR comes from a fork; cannot push to its branch"
  [ "$base" = "$DEFAULT_BRANCH" ] || emit refuse "PR #$PR targets '$base', not the default branch '$DEFAULT_BRANCH' (stacked PRs are out of scope)"
}

check_guard() {
  local labelled marked
  [ "$AGAIN" -eq 1 ] && return
  labelled=$(pr_field '[.labels[].name] | index("tightened") != null')
  marked=$(pr_field '[.comments[].body] | any(contains("<!-- tighten:pass"))')
  [ "$labelled" = "true" ] && emit skip "PR #$PR already has the tightened label (use --again to rerun)"
  [ "$marked" = "true" ] && emit skip "PR #$PR already has a tighten comment (use --again to rerun)"
}

# --- git / worktree -----------------------------------------------------------

locate_repo() { # sets ROOT, REPO, PARENT, BRANCH, WT
  ROOT=$(git rev-parse --show-toplevel 2>&1) || emit refuse "not inside a git repository: $ROOT"
  REPO=$(basename "$ROOT")
  PARENT="${TIGHTEN_WORKTREE_PARENT:-$(dirname "$ROOT")}"
  BRANCH=$(pr_field .headRefName)
  WT="$PARENT/$REPO-tighten-$PR"
}

check_other_checkouts() {
  local line path="" cur_path="" ahead
  [ -e "$WT" ] && emit refuse "$WT already exists (stale run?). Inspect it, then: git -C '$ROOT' worktree remove '$WT'"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur_path=${line#worktree } ;;
      "branch refs/heads/$BRANCH") path=$cur_path ;;
    esac
  done < <(git -C "$ROOT" worktree list --porcelain)
  OTHER_CHECKOUT="$path"
  [ -n "$path" ] || return
  ahead=$(git -C "$path" rev-list --count "origin/$BRANCH..$BRANCH" 2>&1) \
    || emit refuse "could not compare $path with origin/$BRANCH: $ahead"
  [ "$ahead" = "0" ] || emit refuse "$path has $ahead unpushed commit(s) on $BRANCH; push first so tighten builds on the same history"
}

make_worktree() {
  local out
  out=$(git -C "$ROOT" fetch origin "$BRANCH" "$DEFAULT_BRANCH" 2>&1) || emit refuse "git fetch failed: $out"
  out=$(git -C "$ROOT" worktree add --detach "$WT" "origin/$BRANCH" 2>&1) || emit refuse "git worktree add failed: $out"
}

# --- repo conventions -----------------------------------------------------------

strip_cmd() { # table cell -> command or empty
  local c
  c=$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^`//' -e 's/`$//')
  case "$c" in "(none)"|"") echo "" ;; *) echo "$c" ;; esac
}

repo_commands() { # sets LANG_, LINT, TEST, TYPECHECK from REPOS.md, else detection
  local row
  LANG_="" LINT="" TEST="" TYPECHECK=""
  if [ -r "$REPOS_MD" ]; then
    row=$(awk -F'|' -v r="$REPO" '$2 ~ "^[[:space:]]*"r"[[:space:]]*$" {print; exit}' "$REPOS_MD")
    if [ -n "$row" ]; then
      LANG_=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')
      TEST=$(strip_cmd "$(printf '%s' "$row" | awk -F'|' '{print $5}')")
      LINT=$(strip_cmd "$(printf '%s' "$row" | awk -F'|' '{print $6}')")
    fi
  fi
  if [ -f "$WT/go.mod" ]; then
    [ -n "$TEST" ] || TEST="go test ./..."; [ -n "$LINT" ] || LINT="golangci-lint run ./..."
    TYPECHECK="go vet ./..."; [ -n "$LANG_" ] || LANG_="Go"
  elif [ -f "$WT/pyproject.toml" ]; then
    [ -n "$TEST" ] || TEST="uv run pytest"; [ -n "$LINT" ] || LINT="uv run ruff check ."
    [ -n "$LANG_" ] || LANG_="Python"
  elif [ -f "$WT/package.json" ]; then
    [ -n "$TEST" ] || TEST="npm test"; [ -n "$LINT" ] || LINT="npm run lint"
    [ -f "$WT/tsconfig.json" ] && TYPECHECK="npx tsc --noEmit"
    [ -n "$LANG_" ] || LANG_="TypeScript"
  fi
}

commit_prefix() { # sets PREFIX from recent subjects on the branch
  local subjects
  subjects=$(git -C "$WT" log -8 --format=%s 2>/dev/null)
  PREFIX=$(printf '%s\n' "$subjects" | grep -oE '^\[[A-Z]+-[0-9]+\]' | head -1)
  [ -n "$PREFIX" ] || PREFIX=$(printf '%s\n' "$subjects" | grep -oE '^\[NO-TICKET\]' | head -1)
}

changelog_scheme() { # sets CL_STYLE, CL_NEXT
  local f="$WT/CHANGELOG.md" max
  CL_STYLE="none" CL_NEXT=0
  [ -r "$f" ] || { CL_STYLE="missing"; return; }
  max=$(grep -oE '\*\*[a-z]+-[0-9]+\*\*' "$f" | grep -oE '[0-9]+' | sort -n | tail -1)
  if [ -n "$max" ]; then CL_STYLE="bold"; CL_NEXT=$((max + 1)); return; fi
  max=$(grep -oE '\([a-z]+-[0-9]+\)' "$f" | grep -oE '[0-9]+' | sort -n | tail -1)
  if [ -n "$max" ]; then CL_STYLE="paren"; CL_NEXT=$((max + 1)); fi
}

# --- file mode --------------------------------------------------------------------

file_kind() { # <path> -> prose | code | unknown
  local name ext
  name=$(basename "$1"); ext="${name##*.}"
  if [ "$ext" = "$name" ]; then # no extension: shebang means code, else prose
    head -c 2 "$1" | grep -q '^#!' && echo code || echo prose
    return
  fi
  ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$ext" | grep -qxE "$PROSE_EXT"; then echo prose
  elif printf '%s' "$ext" | grep -qxE "$CODE_EXT"; then echo code
  else echo unknown; fi
}

file_checks() { # sets ABS, KIND, LINES; refuses on dir, unreadable, binary, empty, too large
  [ -f "$FILE" ] || emit refuse "$FILE is not a regular file"
  [ -r "$FILE" ] || emit refuse "$FILE is not readable"
  ABS=$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")
  LC_ALL=C grep -qI '' "$ABS" || emit refuse "$ABS looks binary; tighten only handles text"
  LINES=$(wc -l < "$ABS")
  [ "$LINES" -gt 0 ] || emit refuse "$ABS is empty"
  [ "$LINES" -le "$MAX_FILE_LINES" ] || emit refuse "$ABS has $LINES lines; limit is $MAX_FILE_LINES. Split it or tighten a section."
  KIND=$(file_kind "$ABS")
  [ "$KIND" != "unknown" ] && return
  emit refuse "$ABS has an unsupported extension; prose: $PROSE_EXT; code: $CODE_EXT"
}

file_git_state() { # sets ROOT, REPO, TRACKED, DIRTY
  local dir
  dir=$(dirname "$ABS")
  ROOT=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || { ROOT="" REPO="" TRACKED=false DIRTY=false; return; }
  REPO=$(basename "$ROOT")
  if git -C "$dir" ls-files --error-unmatch -- "$ABS" >/dev/null 2>&1; then TRACKED=true; else TRACKED=false; fi
  if [ -n "$(git -C "$dir" status --porcelain -- "$ABS")" ]; then DIRTY=true; else DIRTY=false; fi
}

file_out_path() { # sets OUT, WRITABLE
  local dir name ext stem
  dir=$(dirname "$ABS"); name=$(basename "$ABS")
  if [ "$TRACKED" = true ] && [ "$DIRTY" = false ] && [ -w "$ABS" ]; then WRITABLE=true; OUT="$ABS"; return; fi
  ext="${name##*.}"; stem="${name%.*}"
  [ "$ext" = "$name" ] && { ext=""; stem="$name"; }
  name="$stem.tightened${ext:+.$ext}"
  if [ -w "$dir" ]; then WRITABLE=true; OUT="$dir/$name"
  else WRITABLE=false; OUT="${TIGHTEN_SCRATCHPAD:-${TMPDIR:-/tmp}/tighten}/$name"; fi
}

file_main() {
  file_checks
  file_git_state
  LINT="" TYPECHECK="" TEST="" LANG_=""
  [ "$KIND" = code ] && [ -n "$ROOT" ] && WT="$ROOT" && repo_commands
  file_out_path
  emit go "ok" "$(jq -cn --arg path "$ABS" --arg kind "$KIND" --argjson tracked "$TRACKED" \
    --argjson dirty "$DIRTY" --argjson lines "$LINES" --argjson writable "$WRITABLE" --arg out "$OUT" \
    --arg root "$ROOT" --arg lint "$LINT" --arg typecheck "$TYPECHECK" --argjson dry "$DRY" \
    '{mode:"file", path:$path, kind:$kind, tracked:$tracked, dirty:$dirty, lines:$lines,
      writable:$writable, out_path:$out, in_place:($out==$path), repo_root:$root,
      lint:$lint, typecheck:$typecheck, flags:{dry:($dry==1)}}')"
}

# --- main -----------------------------------------------------------------------

main() {
  parse_args "$@"
  [ -n "$FILE" ] && file_main
  fetch_pr
  check_state
  check_guard
  locate_repo
  check_other_checkouts
  make_worktree
  repo_commands
  commit_prefix
  changelog_scheme
  emit go "ok" "$(jq -cn \
    --argjson pr "$PR" --arg url "$(pr_field .url)" --arg title "$(pr_field .title)" \
    --arg branch "$BRANCH" --arg base "$DEFAULT_BRANCH" --arg repo "$REPO" --arg root "$ROOT" \
    --arg wt "$WT" --arg other "$OTHER_CHECKOUT" --argjson draft "$(pr_field .isDraft)" \
    --arg lang "$LANG_" --arg lint "$LINT" --arg typecheck "$TYPECHECK" --arg test "$TEST" \
    --arg prefix "$PREFIX" --arg cl_style "$CL_STYLE" --argjson cl_next "$CL_NEXT" \
    --argjson again "$AGAIN" --argjson dry "$DRY" --arg tier "$FORCE_TIER" \
    '{mode:"pr", pr:$pr, url:$url, title:$title, branch:$branch, base:$base, repo:$repo, repo_root:$root,
      worktree:$wt, other_checkout:$other, draft:$draft, lang:$lang,
      lint:$lint, typecheck:$typecheck, test:$test, prefix:$prefix,
      changelog:{style:$cl_style, next:$cl_next},
      flags:{again:($again==1), dry:($dry==1), tier:$tier}}')"
}

main "$@"
