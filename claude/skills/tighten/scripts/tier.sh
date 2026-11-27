#!/bin/bash
# tier.sh - deterministic tighten tier from a diff.
#
# Usage:
#   tier.sh <base-ref> <head-ref>     numstat from `git diff --numstat base...head` in cwd
#   tier.sh --numstat <file>          numstat from a file (tests / fixtures)
#
# Prints one JSON object: tier, loc, files, pkgs, risk, reasons.
# Tier 0 = skip, 1 = lean checklist, 2 = + structure rubric, 3 = + cross-file tracing.
# Thresholds can be overridden with TIGHTEN_T0_LOC, TIGHTEN_T1_LOC, TIGHTEN_T1_FILES,
# TIGHTEN_T2_LOC, TIGHTEN_T3_PKGS.
set -uo pipefail

T0_LOC="${TIGHTEN_T0_LOC:-10}"
T1_LOC="${TIGHTEN_T1_LOC:-150}"
T1_FILES="${TIGHTEN_T1_FILES:-3}"
T2_LOC="${TIGHTEN_T2_LOC:-600}"
T3_PKGS="${TIGHTEN_T3_PKGS:-3}"

# Files that never count as code to tighten.
NOISE='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|uv\.lock|poetry\.lock|Cargo\.lock)$|\.snap$|\.min\.(js|css)$|(^|/)(vendor|node_modules|dist|build|\.next|coverage)/|\.pb\.go$|\.gen\.(ts|go)$|\.(png|jpe?g|gif|svg|webp|ico|woff2?|ttf|pdf|lock)$|\.md$|(^|/)LICENSE$'
# Config files: counted separately so a config-only PR is tier 0.
CONFIG='\.(ya?ml|json|toml|ini|cfg|env|properties)$|(^|/)\.env(\..*)?$|(^|/)Dockerfile(\..*)?$|(^|/)Makefile$'
# Paths whose change makes the PR tier 3 regardless of size.
RISK='(^|/)[^/]*(auth|session|token|secret|crypt|payment|billing|migration|schema|middleware|rls|policy|webhook)[^/]*(/|$)|\.sql$|(^|/)Dockerfile|docker-compose|\.github/workflows/|(^|/)\.env(\..*)?$'

usage() { echo "usage: tier.sh <base> <head> | tier.sh --numstat <file>" >&2; exit 2; }

read_numstat() {
  if [ "${1:-}" = "--numstat" ]; then
    [ -r "${2:-}" ] || { echo "tier.sh: cannot read numstat file '${2:-}'" >&2; exit 2; }
    cat "$2"
    return
  fi
  [ $# -eq 2 ] || usage
  git diff --numstat "$1...$2" || { echo "tier.sh: git diff failed" >&2; exit 2; }
}

# One awk pass: classify each path, sum code LOC, collect packages and risk paths.
# Regexes come in through ENVIRON (awk -v would escape-process the backslashes).
classify() {
  NOISE="$NOISE" CONFIG="$CONFIG" RISK="$RISK" awk '
    BEGIN { noise = ENVIRON["NOISE"]; config = ENVIRON["CONFIG"]; risk = ENVIRON["RISK"] }
    function pkg(p,  n, parts) {
      n = split(p, parts, "/")
      if (n == 1) return "."
      if (n >= 3 && parts[1] ~ /^(src|internal|cmd|pkg|app|lib)$/) return parts[1] "/" parts[2]
      return parts[1]
    }
    {
      path = $3
      if (path ~ noise) { noise_n++; next }
      if (path ~ risk) risks[path] = 1
      if (path ~ config) { config_n++; next }
      if ($1 == "-" || $2 == "-") { binary_n++; next }
      loc += $1 + $2
      files++
      pkgs[pkg(path)] = 1
    }
    END {
      np = 0; for (k in pkgs) np++
      printf "%d %d %d %d %d\n", loc, files, np, noise_n + binary_n, config_n
      for (k in risks) print "RISK " k
    }'
}

decide() {
  local loc=$1 files=$2 pkgs=$3 nrisk=$4
  if [ "$loc" -lt "$T0_LOC" ]; then echo "0 code LOC $loc < $T0_LOC"; return; fi
  if [ "$nrisk" -gt 0 ]; then echo "3 risk path touched"; return; fi
  if [ "$pkgs" -ge "$T3_PKGS" ]; then echo "3 $pkgs packages >= $T3_PKGS"; return; fi
  if [ "$loc" -gt "$T2_LOC" ]; then echo "3 code LOC $loc > $T2_LOC"; return; fi
  if [ "$loc" -le "$T1_LOC" ] && [ "$files" -le "$T1_FILES" ] && [ "$pkgs" -le 1 ]; then
    echo "1 code LOC $loc <= $T1_LOC, $files files, one package"; return
  fi
  echo "2 code LOC $loc <= $T2_LOC, $files files, $pkgs packages"
}

main() {
  local out summary loc files pkgs skipped config risks verdict tier reason
  out=$(read_numstat "$@" | classify) || exit 2
  summary=$(printf '%s\n' "$out" | head -1)
  read -r loc files pkgs skipped config <<<"$summary"
  risks=$(printf '%s\n' "$out" | awk '/^RISK /{print $2}')
  verdict=$(decide "$loc" "$files" "$pkgs" "$(printf '%s' "$risks" | grep -c .)")
  tier=${verdict%% *}
  reason=${verdict#* }
  jq -cn --argjson tier "$tier" --argjson loc "$loc" --argjson files "$files" \
    --argjson pkgs "$pkgs" --argjson skipped "$skipped" --argjson config "$config" \
    --arg reason "$reason" --arg risks "$risks" \
    '{tier:$tier, loc:$loc, files:$files, pkgs:$pkgs, skipped_noise:$skipped,
      config_files:$config, risk:($risks|split("\n")|map(select(.!=""))), reasons:[$reason]}'
}

main "$@"
