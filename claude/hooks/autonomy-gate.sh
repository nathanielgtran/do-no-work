#!/bin/bash
# Autonomy dial enforcement + tamper guard. Runs on EVERY Bash call (no `if` filter),
# so bypass forms (git -C, cd && push, VAR=1 git push, command git push) are all seen.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null); jq_rc=$?

emit() { jq -nc --arg d "$1" --arg r "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'; exit 0; }
deny() { emit deny "$1"; }
ask()  { emit ask  "$1"; }

# Fail-CLOSED: if the command can't be parsed, prompt rather than pass through.
[ "$jq_rc" -eq 0 ] || ask "autonomy-gate: could not parse command (jq failed) — prompting."

# Tamper guard (ALL levels): deny Bash that WRITES the dial or hooks. Checks write TARGETS
# (redirect target, mutating-command operands, sed -i files, a cd into the dir), not mere
# mentions. A literal $HOME/.claude/... target is denied: $HOME cannot be resolved statically.
TGT_RE='\.claude/(autonomy-level|hooks)|do-no-work/claude/hooks(/|$)|(^|/)autonomy-level'
SEP=$'\001S'; RDR=$'\001R'; CWDMODE=none; CI=0

flush() { [ "$have" = 1 ] && TOK[${#TOK[@]}]=$cur; cur=""; have=0; }
add() { flush; TOK[${#TOK[@]}]=$1; }

tok_quoted() {
  if [ "$c" = "$qs" ]; then qs=""
  elif [ "$qs" = '"' ] && [ "$c" = '\' ]; then i=$((i+1)); cur="$cur${s:$i:1}"
  else cur="$cur$c"; fi
}

tok_gt() {
  case $cur in *[!0-9]*) ;; *) cur=""; have=0;; esac
  flush
  case ${s:$((i+1)):1} in '>'|'|') i=$((i+1));; esac
  if [ "${s:$((i+1)):1}" = '&' ]; then
    i=$((i+1))
    case ${s:$((i+1)):1} in [0-9-]) return;; esac
  fi
  add "$RDR"
}

tok_plain() {
  case $c in
    '\') i=$((i+1)); cur="$cur${s:$i:1}"; have=1;;
    "'"|'"') qs=$c; have=1;;
    ' '|$'\t') flush;;
    $'\n'|';'|'|') add "$SEP";;
    '&') if [ "${s:$((i+1)):1}" = '>' ]; then
           i=$((i+1)); [ "${s:$((i+1)):1}" = '>' ] && i=$((i+1)); add "$RDR"
         else add "$SEP"; fi;;
    '>') tok_gt;;
    '<') flush;;
    *) cur="$cur$c"; have=1;;
  esac
}

tokenize() {
  local i=0 n=${#1} c cur="" have=0 qs="" s=$1
  TOK=()
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    if [ -n "$qs" ]; then tok_quoted; else tok_plain; fi
    i=$((i+1))
  done
  flush
  [ -z "$qs" ]
}

is_target() {
  local t=$1
  [[ $t =~ $TGT_RE ]] && return 0
  case $CWDMODE in
    hooks) case $t in /*|\~*|\$*|-*) return 1;; esac; return 0;;
    claude) case $t in hooks|hooks/*) return 0;; esac;;
  esac
  return 1
}

set_cwd() {
  case $1 in
    *.claude/hooks|*.claude/hooks/|*do-no-work/claude/hooks|*do-no-work/claude/hooks/) CWDMODE=hooks;;
    *.claude|*.claude/) CWDMODE=claude;;
    hooks|hooks/) [ "$CWDMODE" = claude ] && CWDMODE=hooks || CWDMODE=none;;
    ..) [ "$CWDMODE" = hooks ] && CWDMODE=claude || CWDMODE=none;;
    *) CWDMODE=none;;
  esac
}

check_ops() {
  local j t last="" tdir=0
  for ((j=CI+1; j<${#WORDS[@]}; j++)); do
    t=${WORDS[$j]}
    if [ "$tdir" = 1 ]; then tdir=0; is_target "$t" && return 0; continue; fi
    case $t in
      -t) tdir=1;;
      --target-directory=*) is_target "${t#*=}" && return 0;;
      -*) ;;
      *) [ "$1" = all ] && is_target "$t" && return 0; last=$t;;
    esac
  done
  [ "$1" = last ] && [ -n "$last" ] && is_target "$last"
}

check_sed() {
  local j t inplace=0 script=0 hit=1
  for ((j=CI+1; j<${#WORDS[@]}; j++)); do
    t=${WORDS[$j]}
    case $t in
      -e|-f|--expression|--file) script=1; j=$((j+1));;
      --in-place*|-i*|-[a-zA-Z]*i*) inplace=1;;
      -*) ;;
      *) if [ "$script" = 0 ]; then script=1; elif is_target "$t"; then hit=0; fi;;
    esac
  done
  [ "$inplace" = 1 ] && return $hit
  return 1
}

check_dd() {
  local j t
  for ((j=CI+1; j<${#WORDS[@]}; j++)); do
    t=${WORDS[$j]}
    case $t in of=*) is_target "${t#of=}" && return 0;; esac
  done
  return 1
}

check_interp() {
  local j t flag=0 hit=1
  for ((j=CI+1; j<${#WORDS[@]}; j++)); do
    t=${WORDS[$j]}
    case $t in -[cerE]*|-[a-zA-Z]*[cerE]*) flag=1;; esac
    [[ $t =~ $TGT_RE ]] && hit=0
  done
  [ "$flag" = 1 ] && return $hit
  return 1
}

check_shell() {
  local j t code="" take=0
  for ((j=CI+1; j<${#WORDS[@]}; j++)); do
    t=${WORDS[$j]}
    if [ "${WORDS[$CI]##*/}" = eval ]; then code="$code $t"; continue; fi
    if [ "$take" = 1 ]; then code=$t; break; fi
    case $t in -c*|-[a-zA-Z]*c*) take=1;; esac
  done
  [ -n "$code" ] && ( tamper_scan "$code" )
}

skip_prefix() {
  case $1 in
    [A-Za-z_]*=*|sudo|command|builtin|exec|nohup|time|env|nice|then|do|else|if|while|'!'|'{'|'(') return 0;;
  esac
  return 1
}

check_words() {
  local wn=${#WORDS[@]} cmd
  CI=0
  while [ "$CI" -lt "$wn" ] && skip_prefix "${WORDS[$CI]}"; do CI=$((CI+1)); done
  [ "$CI" -lt "$wn" ] || return 1
  cmd=${WORDS[$CI]##*/}; cmd=${cmd#\$\(}; cmd=${cmd#\(}; cmd=${cmd#\{}
  case $cmd in
    cd|pushd) set_cwd "${WORDS[$((CI+1))]:-}"; return 1;;
    tee|rm|touch|chmod|chown|chgrp|truncate|shred|rmdir|unlink|mv|vi|vim|nano|emacs|ex|ed) check_ops all;;
    cp|install|ln|rsync) check_ops last;;
    sed|gsed) check_sed;;
    dd) check_dd;;
    python*|node*|ruby|perl|php|lua|osascript) check_interp;;
    bash|sh|zsh|dash|eval) check_shell;;
    *) return 1;;
  esac
}

check_segment() {
  local j=$1 t
  WORDS=()
  while [ "$j" -lt "$2" ]; do
    t=${TOK[$j]}
    if [ "$t" = "$RDR" ]; then
      j=$((j+1))
      [ "$j" -lt "$2" ] && is_target "${TOK[$j]}" && return 0
    else WORDS[${#WORDS[@]}]=$t; fi
    j=$((j+1))
  done
  check_words
}

legacy_tamper() {
  local t='\.claude/(autonomy-level|hooks/)'
  printf '%s' "$1" | grep -Eq ">>?[^&;|]*$t" \
    || printf '%s' "$1" | grep -Eq "[[:space:]](tee|cp|mv|rm|ln|chmod|chown|truncate|install|dd)[[:space:]][^&;|]*$t" \
    || printf '%s' "$1" | grep -Eq "sed[[:space:]]+-i[^&;|]*$t" \
    || printf '%s' "$1" | grep -Eq "\b(vi|vim|nano|emacs|ex|ed)\b[^&;|]*$t"
}

tamper_scan() {
  local j=0 start=0 n
  tokenize "$1" || { legacy_tamper "$1"; return; }
  n=${#TOK[@]}; CWDMODE=none
  while [ "$j" -le "$n" ]; do
    if [ "$j" -eq "$n" ] || [ "${TOK[$j]}" = "$SEP" ]; then
      [ "$j" -gt "$start" ] && check_segment "$start" "$j" && return 0
      start=$((j+1))
    fi
    j=$((j+1))
  done
  return 1
}

if tamper_scan "$cmd"; then
  case $cmd in
    *autonomy-level*|*'$HOME'*|*'${HOME}'*) deny "autonomy-gate: refusing to WRITE the autonomy dial from Bash. The user flips it with 'go less' / 'go full'." ;;
    *) ask "autonomy-gate: this writes a guard hook. Approve only if you asked for this hook change." ;;
  esac
fi

# Read level. File absent -> default full (documented). Unreadable -> fail-closed (ask).
f="$HOME/.claude/autonomy-level"
if [ -e "$f" ]; then
  level=$(tr -d '[:space:]' < "$f" 2>/dev/null) || ask "autonomy-gate: state file unreadable — prompting."
else
  level=full
fi

# Git hook bypass (ALL levels): gitleaks, commit-msg and pre-push hooks must run.
# Token-based so a quoted commit message that mentions --no-verify is not a match.
hook_bypass() {
  local t git=0 sub="" skip=0
  tokenize "$1" || return 2
  for t in "${TOK[@]}"; do
    if [ "$t" = "$SEP" ]; then git=0; sub=""; skip=0; continue; fi
    if [ "$skip" = 1 ]; then
      skip=0
      case $t in core.hooksPath=*|core.hookspath=*) return 0;; esac
      continue
    fi
    if [ "$git" = 0 ]; then
      case $t in SKIP=*|HUSKY=*) return 0;; esac
      [ "${t##*/}" = git ] && git=1
      continue
    fi
    if [ -z "$sub" ]; then
      case $t in -C|-c|--git-dir|--work-tree) skip=1;; -*) ;; *) sub=$t;; esac
      continue
    fi
    case "$sub:$t" in
      *:--no-verify|commit:-n*|commit:-[!-]*n*|config:core.hooksPath|config:core.hookspath) return 0;;
    esac
  done
  return 1
}
GUARD="$(dirname "$0")/push-guard.py"
scmd=$(printf '%s' "$input" | python3 "$GUARD" --strip) || ask "autonomy-gate: push-guard --strip failed — prompting."
hook_bypass "$scmd"; hb=$?
[ "$hb" = 0 ] && deny "autonomy-gate: git hook bypass blocked (--no-verify, commit -n, core.hooksPath, SKIP=, HUSKY=). Fix what the hook flags instead."
if [ "$hb" = 2 ] && printf '%s' "$scmd" | grep -Eq 'no-verify|hooksPath|hookspath|SKIP=|HUSKY=|commit.*[[:space:]]-[a-z]*n'; then
  ask "autonomy-gate: could not tokenize a command that mentions a git hook bypass — prompting."
fi

# Push/merge to main (ALL levels) and any push/merge (less) via the shared normaliser.
printf '%s' "$scmd" | grep -Eq 'push|merge|api|graphql|update-ref' || exit 0
gflag=(); [ "$level" = "less" ] && gflag=(--less)
verdict=$(printf '%s' "$input" | python3 "$GUARD" ${gflag[@]+"${gflag[@]}"}) \
  || ask "autonomy-gate: push-guard failed to run — prompting."
kind=${verdict%%$'\t'*}; why=${verdict#*$'\t'}
case $kind in
  OK) exit 0 ;;
  MAIN) deny "autonomy-gate: $why. Never push or merge to main/master; open a PR." ;;
  PUSH) deny "autonomy=less: PUSH blocked ($why). The user pushes manually in less mode. Say 'go full' to restore." ;;
  MERGE) deny "autonomy=less: MERGE blocked ($why). Route this PR to a human. Say 'go full' to restore." ;;
  *) ask "autonomy-gate: $why" ;;
esac
