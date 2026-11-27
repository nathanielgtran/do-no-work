#!/bin/bash
# Installs into a throwaway HOME, then checks dnw-doctor's report before and after drift.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$REPO/bin/dnw-doctor"
fail=0
home=""
out=""
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

doctor() { HOME="$home" "$DOC" "$@" </dev/null; }
has() { grep -Eq -- "$1" <<<"$out"; }
snap() { out="$(doctor "$@" || true)"; }
install_home() {
  home="$(mktemp -d)"
  HOME="$home" GIT_NAME=T GIT_EMAIL=t@example.com DOTFILES_SKIP_UPSTREAM=1 "$REPO/install.sh" --no-deps "$@" >/dev/null </dev/null
}
write_settings() { jq "$1" "$REPO/claude/settings.example.json" > "$home/.claude/settings.json"; }

echo "-- clean link install"
install_home
write_settings .
snap
check "installed ok" 'has "^ok +installed"'
check "no installed drift" '! has "^(warn|fail) +installed"'
check "identity ok" 'has "^ok +identity"'
check "shell ok" 'has "^ok +shell"'
check "settings ok" 'has "^ok +settings"'
check "exit 0" 'doctor >/dev/null'

echo "-- missing hook target"
mkdir -p "$home/trash"
mv "$home/.claude/hooks/stop-gate.sh" "$home/trash/"
snap
check "fail line" 'has "^fail +installed +missing ~/.claude/hooks/stop-gate.sh"'
check "fix line" 'has "fix: cd .*install.sh --no-deps"'
check "exit 1" '! doctor >/dev/null'
ln -s "$REPO/claude/hooks/stop-gate.sh" "$home/.claude/hooks/stop-gate.sh"

echo "-- symlink pointing elsewhere"
ln -sfn /nonexistent "$home/.claude/hooks/gate-self-merge.sh"
snap
check "warn line" 'has "^warn +installed +~/.claude/hooks/gate-self-merge.sh links to /nonexistent"'
check "warn exits 0" 'doctor >/dev/null'
ln -sfn "$REPO/claude/hooks/gate-self-merge.sh" "$home/.claude/hooks/gate-self-merge.sh"

echo "-- settings gaps"
write_settings 'del(.hooks.Stop) | del(.statusLine) | .permissions.deny |= map(select(. != "Bash(sudo:*)"))'
# shellcheck disable=SC2034 # read by the eval in check
before="$(cksum < "$home/.claude/settings.json")"
snap
check "missing Stop hook" 'has "^warn +settings +hook missing under Stop: bash ~/.claude/hooks/stop-gate.sh"'
check "fix names event" 'has "fix: add to ~/.claude/settings.json under hooks.Stop: bash ~/.claude/hooks/stop-gate.sh"'
check "missing deny" 'has "permissions.deny missing: Bash\(sudo:\*\)"'
check "missing statusLine" 'has "^warn +settings +statusLine"'
check "warns only, exit 0" 'doctor >/dev/null'
check "settings untouched" '[ "$before" = "$(cksum < "$home/.claude/settings.json")" ]'
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash %s/.claude/hooks/stop-gate.sh"}]}]}}' "$home" > "$home/.claude/settings.json"
snap
check "absolute home path normalised" '! has "hook missing under Stop"'
check "other hooks still flagged" 'has "hook missing under PreToolUse"'

echo "-- identity and rc"
mv "$home/.gitconfig.local" "$home/trash/"
snap
check "identity fail" 'has "^fail +identity"'
check "identity fix" 'has "fix: git config -f ~/.gitconfig.local user.name .* git config -f ~/.gitconfig.local user.email"'
check "identity exit 1" '! doctor >/dev/null'
: > "$home/.bashrc"
: > "$home/.zshrc"
: > "$home/.bash_profile"
snap
check "rc warn" 'has "^warn +shell"'

echo "-- json"
snap --json
check "json is a non-empty array" 'jq -e "type == \"array\" and length > 0" <<<"$out" >/dev/null'
check "json identity fail with fix" 'jq -e "any(.[]; .status == \"fail\" and .area == \"identity\" and (.fix | length > 0))" <<<"$out" >/dev/null'
check "json exit 1" '! doctor --json >/dev/null'

echo "-- stale copy"
install_home --copy
echo '# local edit' >> "$home/.claude/hooks/autonomy-gate.sh"
snap
check "stale copy warns" 'has "^warn +installed +~/.claude/hooks/autonomy-gate.sh differs"'
check "fix suggests --copy" 'has "install.sh --no-deps --copy"'
check "only the edited file" '[ "$(grep -Ec "^(warn|fail) +installed" <<<"$out")" -eq 1 ]'
exit $fail
