#!/bin/bash
# Shared overlay rules, sourced by install.sh, scripts/install-manifest.sh and bin/dnw-doctor.
# overlayable REL        exit 1 for repo paths an overlay file must never replace (the single deny list)
# prov_sha REPO REL      blob SHA of the repo file, empty if it has none
# prov_lookup OV REL     SHA recorded in OV/.provenance for REL, empty if no row
# prov_record OV REPO REL  append "REL<TAB>SHA<TAB>DATE" if REL has no row and the repo has the file

overlayable() {
  case "$1" in
    claude/hooks/* | claude/settings.example.json | claude/CLAUDE.md.example | install.sh | scripts/* | .github/*) return 1 ;;
    tests/* | */tests/* | *_test.* | test_*.py | */test_*.py) return 1 ;;
  esac
  return 0
}

prov_sha() {
  [ -f "$1/$2" ] || return 0
  git hash-object "$1/$2"
}

prov_lookup() {
  [ -f "$1/.provenance" ] || return 0
  awk -F'\t' -v r="$2" '$1 == r { print $2; exit }' "$1/.provenance"
}

prov_record() {
  local ov="$1" repo="$2" rel="$3" sha
  [ -z "$(prov_lookup "$ov" "$rel")" ] || return 0
  sha="$(prov_sha "$repo" "$rel")"
  [ -n "$sha" ] || return 0
  mkdir -p "$ov"
  printf '%s\t%s\t%s\n' "$rel" "$sha" "$(date +%Y-%m-%d)" >> "$ov/.provenance"
}
