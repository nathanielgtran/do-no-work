#!/bin/bash
# Overlay safety: seeding never copies hooks/tests, the manifest ignores non-overlayable overlay files,
# provenance is recorded, and dnw-doctor warns when a shadowed repo file changes.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
out=""
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
has() { grep -Eq -- "$1" <<<"$out"; }
content_is() { [ "$(cat "$1")" = "$2" ]; }
seed_cmd() { out="$(HOME="$home" DOTFILES_OVERLAY="$ovs" "$REPO/install.sh" "$@" 2>&1 </dev/null)"; }

home="$(mktemp -d)"
ovs="$(mktemp -d)/ov"
bk="$(mktemp -d)"

echo "-- seed from backup skips non-overlayable files"
mkdir -p "$bk/.claude/hooks" "$bk/.claude/commands" "$bk/.claude/skills/call" "$bk/.claude/skills/tighten/tests"
echo 'old gate' > "$bk/.claude/hooks/autonomy-gate.sh"
echo 'old test' > "$bk/.claude/skills/tighten/tests/tier_test.sh"
echo 'personal hc' > "$bk/.claude/commands/hc.md"
echo 'personal call' > "$bk/.claude/skills/call/SKILL.md"
seed_cmd --seed-overlay-from "$bk"
check "personal command seeded" "content_is '$ovs/claude/commands/hc.md' 'personal hc'"
check "personal skill file seeded" "content_is '$ovs/claude/skills/call/SKILL.md' 'personal call'"
check "hook not seeded" "[ ! -e '$ovs/claude/hooks/autonomy-gate.sh' ]"
check "skill test not seeded" "[ ! -e '$ovs/claude/skills/tighten/tests/tier_test.sh' ]"
check "only two files plus provenance" "[ \"\$(find '$ovs' -type f | wc -l)\" -eq 3 ]"
check "hook skip printed" "has 'skip \\(not overlayable\\): claude/hooks/autonomy-gate.sh'"
check "test skip printed" "has 'skip \\(not overlayable\\): claude/skills/tighten/tests/tier_test.sh'"
check "seeded list printed" "has '^seeded: claude/commands/hc.md\$' && has '^seeded: claude/skills/call/SKILL.md\$'"
check "review hint printed" "has 'Review: these now override the repo; delete any that aren.t personal from $ovs'"
check "provenance rows written" "[ \"\$(wc -l < '$ovs/.provenance')\" -eq 2 ]"
want="$(git hash-object "$REPO/claude/commands/hc.md")"
check "provenance holds repo blob sha" "grep -qP '^claude/commands/hc.md\\t$want\\t[0-9]{4}-[0-9]{2}-[0-9]{2}\$' '$ovs/.provenance'"

echo "-- seed from HOME uses the same deny list"
mkdir -p "$home/.claude/hooks"
echo 'old' > "$home/.claude/hooks/go-check.sh"
ovh="$(mktemp -d)/ov"
out="$(HOME="$home" DOTFILES_OVERLAY="$ovh" "$REPO/install.sh" --seed-overlay 2>&1 </dev/null)"
check "home seed skips hook" "has 'skip \\(not overlayable\\): claude/hooks/go-check.sh' && [ ! -e '$ovh/claude/hooks/go-check.sh' ]"

echo "-- manifest ignores a hand-placed overlay hook"
home2="$(mktemp -d)"
ovm="$(mktemp -d)"
mkdir -p "$ovm/claude/hooks" "$ovm/claude/skills/tighten/tests"
echo 'evil' > "$ovm/claude/hooks/autonomy-gate.sh"
echo 'evil' > "$ovm/claude/skills/tighten/tests/tier_test.sh"
echo 'extra' > "$ovm/claude/hooks/new-hook.sh"
errf="$(mktemp)"
out="$(HOME="$home2" DOTFILES_OVERLAY="$ovm" "$REPO/scripts/install-manifest.sh" "$REPO" 2>"$errf")"
check "manifest uses repo hook" "has '^$REPO/claude/hooks/autonomy-gate.sh.$home2/.claude/hooks/autonomy-gate.sh.repo\$'"
check "no overlay-origin hook rows" "! has 'claude/hooks/.*overlay\$'"
check "overlay-only hook not emitted" "! has 'new-hook.sh'"
check "manifest warns on stderr" "grep -q 'ignoring overlay/claude/hooks/autonomy-gate.sh (not overlayable)' '$errf'"
check "skill test ignored too" "! has 'overlay\$' && grep -q 'tier_test.sh' '$errf'"
HOME="$home2" DOTFILES_OVERLAY="$ovm" GIT_NAME=T GIT_EMAIL=t@example.com DOTFILES_SKIP_UPSTREAM=1 \
  "$REPO/install.sh" --no-deps >/dev/null 2>&1 </dev/null
check "installed hook links to repo" "[ \"\$(readlink '$home2/.claude/hooks/autonomy-gate.sh')\" = '$REPO/claude/hooks/autonomy-gate.sh' ]"
out="$(HOME="$home2" DOTFILES_OVERLAY="$ovm" "$REPO/bin/dnw-doctor" </dev/null || true)"
check "doctor reports ignored overlay hook" "has '^warn +overlay +ignored: claude/hooks/autonomy-gate.sh \\(not overlayable\\)'"

echo "-- doctor provenance staleness (temp repo copy)"
cp_repo="$(mktemp -d)/repo"
mkdir -p "$cp_repo"
(cd "$REPO" && tar --exclude=.git -cf - .) | (cd "$cp_repo" && tar -xf -)
home3="$(mktemp -d)"
ovp="$(mktemp -d)/ov"
mkdir -p "$ovp/claude/commands"
echo 'personal hc' > "$ovp/claude/commands/hc.md"
echo 'personal log' > "$ovp/claude/commands/log.md"
HOME="$home3" DOTFILES_OVERLAY="$ovp" "$cp_repo/install.sh" --record-overlay >/dev/null 2>&1 </dev/null
HOME="$home3" DOTFILES_OVERLAY="$ovp" GIT_NAME=T GIT_EMAIL=t@example.com DOTFILES_SKIP_UPSTREAM=1 \
  "$cp_repo/install.sh" --no-deps >/dev/null 2>&1 </dev/null
doc() { out="$(HOME="$home3" DOTFILES_OVERLAY="$ovp" "$cp_repo/bin/dnw-doctor" --repo "$cp_repo" </dev/null || true)"; }
doc
check "unchanged repo: no staleness warning" "! has 'shadows a repo file'"
old7="$(git hash-object "$cp_repo/claude/commands/hc.md" | cut -c1-7)"
echo '# upstream change' >> "$cp_repo/claude/commands/hc.md"
new7="$(git hash-object "$cp_repo/claude/commands/hc.md" | cut -c1-7)"
doc
check "changed file warned with shas" "has 'warn +overlay +claude/commands/hc.md shadows a repo file that changed since it was seeded \\(repo $old7\\.\\.$new7\\)'"
check "fix lines present" "has 'diff .*claude/commands/hc.md.*claude/commands/hc.md' && has 'remove it from the overlay if it isn.t personal'"
check "unchanged file not warned" "! has 'claude/commands/log.md shadows'"

echo "-- --record-overlay"
home4="$(mktemp -d)"
ovr="$(mktemp -d)/ov"
mkdir -p "$ovr/claude/commands" "$ovr/claude/hooks"
echo 'p' > "$ovr/claude/commands/hc.md"
echo 'p' > "$ovr/claude/commands/brand-new.md"
echo 'x' > "$ovr/claude/hooks/go-check.sh"
out="$(HOME="$home4" DOTFILES_OVERLAY="$ovr" "$REPO/bin/dnw-doctor" </dev/null || true)"
check "doctor warns once, suggests --record-overlay" "has 'warn +overlay .*no provenance' && has 'install.sh --record-overlay'"
out="$(HOME="$home4" DOTFILES_OVERLAY="$ovr" "$REPO/install.sh" --record-overlay 2>&1 </dev/null)"
check "records the shadowing file" "grep -q '^claude/commands/hc.md	' '$ovr/.provenance'"
check "skips overlay-only and non-overlayable" "! grep -q 'brand-new\\|go-check' '$ovr/.provenance'"
check "copies nothing and installs nothing" "[ ! -e '$home4/.claude' ] && [ \"\$(find '$ovr' -type f | wc -l)\" -eq 4 ]"
out="$(HOME="$home4" DOTFILES_OVERLAY="$ovr" "$REPO/bin/dnw-doctor" </dev/null || true)"
check "doctor no longer warns about missing rows" "! has 'no provenance'"
exit $fail
