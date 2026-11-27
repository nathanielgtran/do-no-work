#!/bin/bash
# dnw-apply against a temp bare origin, a clone, a throwaway HOME and a fake curl. Never touches the real HOME.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
fail=0
base="" origin="" clone="" pusher="" home="" cap="" out="" rc=0
TOKEN="tok_SECRET_do_not_leak_123"
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
has() { grep -Eq -- "$1" <<<"$out"; }
gitq() { git -c user.name=T -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

make_fake_curl() {
  mkdir -p "$base/fakebin"
  cat > "$base/fakebin/curl" <<'EOF'
#!/bin/bash
cat > /dev/null
printf '%s\n' "$*" >> "$CAP/argv"
case "$*" in
  *users/@me/channels*) echo '{"id":"chan1"}' ;;
  *) for a in "$@"; do case "$a" in '{"content"'*) printf '%s\n' "$a" >> "$CAP/payload" ;; esac; done
     if [ -e "$CAP/fail" ]; then exit 22; fi
     echo '{"id":"msg1"}' ;;
esac
EOF
  chmod +x "$base/fakebin/curl"
}

copy_repo() {
  local f
  mkdir -p "$1"
  while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")"
    cp -p "$REPO/$f" "$1/$f"
  done < <(cd "$REPO" && git ls-files -co --exclude-standard)
}

setup() {
  base="$(mktemp -d)"
  origin="$base/origin.git"
  clone="$base/clone"
  pusher="$base/pusher"
  home="$base/home"
  cap="$base/cap"
  mkdir -p "$home/.config/claude-notify" "$cap"
  printf 'DISCORD_BOT_TOKEN=%s\nDISCORD_OWNER_ID=42\n' "$TOKEN" > "$home/.config/claude-notify/env"
  make_fake_curl
  git init -q --bare -b main "$origin"
  copy_repo "$pusher"
  git -C "$pusher" init -q -b main
  git -C "$pusher" add -A
  gitq -C "$pusher" commit -q -m base
  git -C "$pusher" remote add origin "$origin"
  git -C "$pusher" push -q origin main
  git clone -q "$origin" "$clone"
  [ "$HOME" = "$REAL_HOME" ] && [ "$home" != "$REAL_HOME" ]
}

run_apply() {
  rc=0
  out="$(env -u DOTFILES_OVERLAY -u XDG_STATE_HOME HOME="$home" CAP="$cap" CURL="$base/fakebin/curl" \
    CLAUDE_NOTIFY_ENV="$home/.config/claude-notify/env" GIT_NAME=T GIT_EMAIL=t@example.com \
    "$clone/bin/dnw-apply" --repo "$clone" "$@" </dev/null 2>&1)" || rc=$?
}

push_change() {  # push_change <file> <text>
  mkdir -p "$(dirname "$pusher/$1")"
  printf '%s\n' "$2" >> "$pusher/$1"
  case "$1" in bin/*) chmod +x "$pusher/$1" ;; esac
  git -C "$pusher" add -A
  gitq -C "$pusher" commit -q -m "change $1"
  git -C "$pusher" push -q origin main
}

state() { echo "$home/.local/state/do-no-work/$1"; }
installed() { [ -e "$home/.claude/hooks/autonomy-gate.sh" ]; }
head_of() { git -C "$1" rev-parse HEAD; }

case_refusals() {
  echo "-- refusals"
  setup
  echo dirt >> "$clone/README.md"
  run_apply
  check "dirty tree exits 2" "[ $rc -eq 2 ] && has 'not clean'"
  check "dirty tree installs nothing" "! installed && [ ! -e '$(state applied)' ]"
  git -C "$clone" checkout -q -- README.md
  mkdir -p "$clone/overlay" && echo x > "$clone/overlay/mine.txt"
  git -C "$clone" checkout -q -b topic
  run_apply
  check "other branch exits 2" "[ $rc -eq 2 ] && has \"not the default branch 'main'\""
  git -C "$clone" checkout -q main
  echo local > "$clone/local.txt"
  git -C "$clone" add local.txt
  gitq -C "$clone" commit -q -m local
  run_apply
  check "ahead of origin exits 2" "[ $rc -eq 2 ] && has 'not on origin/main'"
  push_change bin/x-tool 'echo hi'
  run_apply
  check "diverged exits 2" "[ $rc -eq 2 ] && ! installed"
  check "diverged keeps local HEAD" "[ \"\$(git -C '$clone' log -1 --format=%s)\" = local ]"
  run_apply --repo "$base/nope"
  check "not a repo exits 2" "[ $rc -eq 2 ]"
  mkdir "$base/plain"
  rc=0; out="$(HOME="$home" "$REPO/bin/dnw-apply" --repo "$base/plain" 2>&1 </dev/null)" || rc=$?
  check "plain dir exits 2" "[ $rc -eq 2 ] && has 'not a git repo'"
}

case_first_run_and_ff() {
  echo "-- fast-forward, first run, state"
  setup
  push_change bin/x-tool '# new'
  run_apply
  check "behind: exits 0 or 1 from doctor" "[ $rc -le 1 ]"
  check "fast-forwarded to origin" "[ \"\$(head_of '$clone')\" = \"\$(head_of '$pusher')\" ]"
  check "installed" "installed"
  check "applied state written" "[ \"\$(cat '$(state applied)')\" = \"\$(head_of '$clone')\" ]"
  check "first run: no audit log" "[ ! -e '$(state audit.log)' ]"
  check "first run: no DM" "[ ! -e '$cap/payload' ]"
  check "summary line" "has 'applied none\\.\\.[0-9a-f]+, [0-9]+ files changed, overlay seeded no, guard change no, doctor [0-9]+ fail / [0-9]+ warn'"
  check "doctor output printed" "has '^ok +installed'"
  push_change bin/x-tool '# more'
  run_apply
  check "bin-only change: no audit" "[ ! -e '$(state audit.log)' ]"
  check "bin-only change: no DM" "[ ! -e '$cap/payload' ]"
  check "summary shows 1 file" "has ', 1 files changed, overlay seeded no, guard change no'"
  check "link mode kept" "[ -L '$home/.claude/hooks/autonomy-gate.sh' ]"
}

case_guard() {
  echo "-- guard change alert"
  setup
  run_apply
  push_change claude/hooks/autonomy-gate.sh '# tweak'
  run_apply
  check "audit line written" "grep -Eq '^[0-9T:Z-]+ [0-9a-f]+\\.\\.[0-9a-f]+ claude/hooks/autonomy-gate.sh\$' '$(state audit.log)'"
  check "DM sent with message" "grep -q 'guard hooks changed: claude/hooks/autonomy-gate.sh' '$cap/payload'"
  check "DM names audit path" "grep -q 'Audit: $home/.local/state/do-no-work/audit.log' '$cap/payload'"
  check "token never in argv" "! grep -q '$TOKEN' '$cap/argv'"
  check "summary says guard yes" "has 'guard change yes'"
  push_change claude/settings.example.json ' '
  touch "$cap/fail"
  run_apply
  check "notify failure warns but finishes" "has 'warning: Discord notify failed' && [ \"\$(cat '$(state applied)')\" = \"\$(head_of '$clone')\" ]"
  check "audit has two lines" "[ \"\$(wc -l < '$(state audit.log)')\" -eq 2 ]"
}

case_overlay_and_copy() {
  echo "-- overlay seed once, copy mode"
  setup
  mkdir -p "$home/.dotfiles-backup/20200101000000/.claude/commands" "$home/.dotfiles-backup/20250101000000/.claude/commands"
  echo old > "$home/.dotfiles-backup/20200101000000/.claude/commands/log.md"
  echo newest > "$home/.dotfiles-backup/20250101000000/.claude/commands/log.md"
  run_apply
  check "seeded from newest backup" "[ \"\$(cat '$home/.config/do-no-work/overlay/claude/commands/log.md')\" = newest ]"
  check "summary says seeded" "has 'overlay seeded yes'"
  echo mine > "$home/.config/do-no-work/overlay/claude/commands/log.md"
  push_change bin/x-tool '# a'
  run_apply
  check "not seeded again" "has 'overlay seeded no' && [ \"\$(cat '$home/.config/do-no-work/overlay/claude/commands/log.md')\" = mine ]"
  setup
  HOME="$home" GIT_NAME=T GIT_EMAIL=t@example.com DOTFILES_SKIP_UPSTREAM=1 "$clone/install.sh" --no-deps --copy >/dev/null </dev/null
  push_change bin/x-tool '# a'
  run_apply
  check "copy mode kept" "[ -f '$home/.claude/hooks/autonomy-gate.sh' ] && [ ! -L '$home/.claude/hooks/autonomy-gate.sh' ]"
}

case_dry_run() {
  echo "-- dry run"
  setup
  mkdir -p "$home/.dotfiles-backup/20250101000000/.claude/commands"
  echo newest > "$home/.dotfiles-backup/20250101000000/.claude/commands/log.md"
  push_change bin/x-tool '# a'
  local before
  before="$(head_of "$clone")"
  run_apply --dry-run
  check "exit 0" "[ $rc -eq 0 ]"
  check "plan printed" "has 'dry run' && has 'would fast-forward: [0-9a-f]+\\.\\.[0-9a-f]+' && has 'would seed overlay: yes' && has 'would install: link mode' && has 'guard change: no'"
  check "no fast-forward" "[ \"\$(head_of '$clone')\" = '$before' ]"
  check "no applied file" "[ ! -e '$(state applied)' ] && [ ! -d '$home/.local/state/do-no-work' ]"
  check "nothing installed" "! installed && [ ! -d '$home/.config/do-no-work' ]"
  check "no DM" "[ ! -e '$cap/payload' ]"
}

case_notify_message() {
  echo "-- claude-notify --message"
  setup
  local n="$clone/claude/hooks/claude-notify.sh" r=0
  HOME="$home" CAP="$cap" CURL="$base/fakebin/curl" "$n" --message 'hello world' || r=$?
  check "sends and exits 0" "[ $r -eq 0 ] && grep -q 'hello world' '$cap/payload'"
  check "token not in argv" "! grep -q '$TOKEN' '$cap/argv'"
  r=0; HOME="$home" CAP="$cap" CURL="$base/fakebin/curl" "$n" --message 2>/dev/null || r=$?
  check "no text exits 2" "[ $r -eq 2 ]"
  r=0; HOME="$base/empty" CAP="$cap" CURL="$base/fakebin/curl" "$n" --message hi || r=$?
  check "no env file exits 1" "[ $r -eq 1 ]"
}

case_refusals
case_notify_message
case_first_run_and_ff
case_guard
case_overlay_and_copy
case_dry_run
exit $fail
