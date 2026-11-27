#!/bin/bash
# Fails if tracked files contain personal data that must not enter this public repo.
# Usage: scripts/public-safety-check.sh [file...]   (no args: every tracked file)
# Sources: builtin generic patterns; values derived from this machine ($USER, git
# user.email/user.name); a private list (one ERE per line, # comments) at
# ${PUBLIC_SAFETY_DENY:-$HOME/.config/do-no-work/public-safety-deny), or in CI the
# PUBLIC_SAFETY_DENY_LIST env var. Private patterns are never printed.
# A line containing "public-safety: allow" is skipped.
set -euo pipefail

SELF="scripts/public-safety-check.sh"
MARKER="public-safety: allow"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

builtin_patterns() {
  cat <<'PAT'
(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}
(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}
(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}
-----BEGIN .*PRIVATE KEY
/home/[a-z][a-z0-9_-]+/
/Users/[A-Za-z][A-Za-z0-9_-]+/
C:\\Users\\[^\\$%]+\\
/mnt/c/Users/[^/$]+/
PAT
}

escape_literal() { printf '%s\n' "$1" | sed 's/[][\.*^$+?(){}|/-]/\\&/g'; }

derived_patterns() {
  local user email name
  user="${USER:-}"
  if [ -z "${GITHUB_ACTIONS:-}" ] && [ "${#user}" -ge 3 ] && [ "$user" != root ]; then
    escape_literal "$user"
  fi
  email="$(git config user.email 2>/dev/null || true)"
  name="$(git config user.name 2>/dev/null || true)"
  if [ -n "$email" ] && [ "$email" != "$(noreply_email)" ]; then escape_literal "$email"; fi
  if [ "${#name}" -ge 3 ] && [ "$name" != "$(origin_owner)" ]; then escape_literal "$name"; fi
}

origin_owner() {
  git remote get-url origin 2>/dev/null | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p'
}

noreply_email() {
  local owner; owner="$(origin_owner)"
  git config user.email 2>/dev/null | grep -E "^[0-9]+\+${owner:-x}@users\.noreply\.github\.com$" || true
}

private_patterns() {
  local file="${PUBLIC_SAFETY_DENY:-$HOME/.config/do-no-work/public-safety-deny}"
  if [ -n "${PUBLIC_SAFETY_DENY_LIST:-}" ]; then
    printf '%s\n' "$PUBLIC_SAFETY_DENY_LIST" | clean_list
  elif [ -f "$file" ]; then
    clean_list <"$file"
  else
    echo "public-safety: no private list at $file (builtin + derived only)" >&2
  fi
}

clean_list() { grep -vE '^[[:space:]]*(#|$)' || true; }

scan() {
  local source="$1" patterns="$2" out
  shift 2
  [ -s "$patterns" ] || return 0
  out="$(grep -HnEIi -f "$patterns" -- "$@" 2>/dev/null || true)"
  [ -n "$out" ] || return 0
  printf '%s\n' "$out" | grep -vF "$MARKER" | report "$source" || true
}

report() {
  local source="$1" hit=1 file rest line
  while IFS= read -r row; do
    file="${row%%:*}"; rest="${row#*:}"; line="${rest%%:*}"
    hit=0
    if [ "$source" = builtin ]; then
      echo "$file:$line: [builtin] ${rest#*:}"
    else
      echo "$file:$line: [$source] matched private pattern"
    fi
  done
  return $hit
}

collect_files() {
  local f
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else git ls-files; fi |
    while IFS= read -r f; do
      if [ "$f" != "$SELF" ] && [ "$f" != LICENSE ] && [ -f "$f" ]; then printf '%s\n' "$f"; fi
    done
}

main() {
  local files=() f found=0 src
  while IFS= read -r f; do files+=("$f"); done < <(collect_files "$@")
  [ "${#files[@]}" -gt 0 ] || exit 0
  builtin_patterns >"$tmp/builtin"
  derived_patterns >"$tmp/derived"
  private_patterns >"$tmp/private"
  for src in builtin derived private; do
    scan "$src" "$tmp/$src" "${files[@]}" >"$tmp/out"
    if [ -s "$tmp/out" ]; then cat "$tmp/out"; found=1; fi
  done
  if [ "$found" -ne 0 ]; then echo "public-safety: FAILED" >&2; exit 1; fi
  echo "public-safety: ok (${#files[@]} files)"
}

main "$@"
