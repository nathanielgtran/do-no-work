#!/bin/bash
# Usage: scripts/changelog.sh next <feat|fix|docs|chore>
#        scripts/changelog.sh check
#        scripts/changelog.sh compile [--version vX.Y.Z]
# Changelog fragments: one changelog.d/<type-N>.md per PR, merged into CHANGELOG.md at release.
set -euo pipefail

TYPES="feat fix docs chore"
NAME_RE='^(feat|fix|docs|chore)-[0-9]+\.md$'

root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

fragments() {
  local f
  for f in changelog.d/*.md; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = README.md ] && continue
    echo "$f"
  done
}

used_ids() {
  { grep -oE '(feat|fix|docs|chore)-[0-9]+' CHANGELOG.md 2>/dev/null || true
    fragments | sed -E 's#.*/##; s#\.md$##'
  } | sort -u
}

cmd_next() {
  local type="${1:-}" max
  case " $TYPES " in *" $type "*) ;; *) echo "unknown type: $type" >&2; return 2 ;; esac
  max="$(used_ids | grep -E "^$type-[0-9]+$" | sed -E 's/.*-//' | sort -n | tail -1 || true)"
  echo "$type-$(( ${max:-0} + 1 ))"
}

fragment_problems() {
  local f="$1" base id lines
  base="$(basename "$f")"
  if ! [[ "$base" =~ $NAME_RE ]]; then echo "$f: bad filename"; return; fi
  id="${base%.md}"
  lines="$(grep -c . "$f" || true)"
  [ "$lines" -eq 1 ] && [ "$(wc -l < "$f")" -le 1 ] || echo "$f: must be exactly one non-empty line"
  if grep -qE "^- $id:" CHANGELOG.md 2>/dev/null; then echo "$f: $id already in CHANGELOG.md"; fi
  return 0
}

duplicate_problems() {
  fragments | sed -E 's#.*/##; s#\.md$##' | sort | uniq -d | sed 's/^/duplicate fragment ID: /'
}

cmd_check() {
  local f problems=""
  while IFS= read -r f; do
    problems+="$(fragment_problems "$f")"$'\n'
  done < <(fragments)
  problems+="$(duplicate_problems)"
  problems="$(printf '%s\n' "$problems" | grep . || true)"
  if [ -n "$problems" ]; then
    printf '%s\n' "$problems" >&2
    return 1
  fi
  echo "changelog fragments ok"
}

sorted_lines() {
  local f base id type n order
  while IFS= read -r f; do
    base="$(basename "$f" .md)"
    type="${base%-*}"
    n="${base##*-}"
    case "$type" in feat) order=1 ;; fix) order=2 ;; docs) order=3 ;; *) order=4 ;; esac
    printf '%s %s - %s: %s\n' "$order" "$n" "$base" "$(grep . "$f" | head -1)"
  done < <(fragments) | sort -k1,1n -k2,2n | sed -E 's/^[0-9]+ [0-9]+ - /- /'
  return 0
}

insert_after_line() {
  local lineno="$1" text="$2" out
  out="$(mktemp)"
  { head -n "$lineno" CHANGELOG.md; printf '%s\n' "$text"; tail -n +"$((lineno + 1))" CHANGELOG.md; } > "$out"
  mv "$out" CHANGELOG.md
}

ensure_unreleased() {
  grep -q '^## Unreleased' CHANGELOG.md 2>/dev/null && return 0
  [ -f CHANGELOG.md ] || printf '# Changelog\n' > CHANGELOG.md
  insert_after_line "$(grep -n -m1 '^# ' CHANGELOG.md | cut -d: -f1 || echo 0)" $'\n## Unreleased'
}

heading_line() {
  local version="${1:-}"
  if [ -n "$version" ]; then
    printf '## %s - %s\n' "$version" "$(date '+%-d %b %Y')"
  fi
}

remove_fragments() {
  local f trash="${TRASH_DIR:-$HOME/.trash}"
  while IFS= read -r f; do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git rm -q -f "$f"
    else
      mkdir -p "$trash"
      mv "$f" "$trash/$(basename "$f").$$"
    fi
  done < <(fragments)
}

cmd_compile() {
  local version="" lines target
  if [ "${1:-}" = "--version" ]; then version="${2:?--version needs a value}"; fi
  lines="$(sorted_lines)"
  if [ -z "$lines" ]; then echo "no fragments to compile"; return 0; fi
  cmd_check >/dev/null
  ensure_unreleased
  target="$(grep -n -m1 '^## Unreleased' CHANGELOG.md | cut -d: -f1)"
  if [ -n "$version" ]; then
    insert_after_line "$target" $'\n'"$(heading_line "$version")"
    target=$((target + 2))
  fi
  insert_after_line "$target" "$lines"
  remove_fragments
  echo "compiled $(printf '%s\n' "$lines" | wc -l | tr -d ' ') fragment(s) into CHANGELOG.md"
}

main() {
  cd "$(root)"
  case "${1:-}" in
    next) shift; cmd_next "$@" ;;
    check) cmd_check ;;
    compile) shift; cmd_compile "$@" ;;
    *) sed -n '2,4p' "$0" >&2; return 2 ;;
  esac
}

main "$@"
