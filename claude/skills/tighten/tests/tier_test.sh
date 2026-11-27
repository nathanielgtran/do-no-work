#!/bin/bash
# Plain-bash tests for scripts/tier.sh. Run: bash tests/tier_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TIER="$HERE/../scripts/tier.sh"
TMP=$(mktemp -d)
trap 'mv "$TMP" "${TMPDIR:-/tmp}/tighten-tier-test-$$" 2>/dev/null' EXIT
pass=0 fail=0

expect() { # <name> <expected tier> <numstat lines via stdin>
  local name=$1 want=$2 got json
  cat > "$TMP/numstat"
  json=$(bash "$TIER" --numstat "$TMP/numstat") || { echo "FAIL $name: tier.sh exited non-zero"; fail=$((fail+1)); return; }
  got=$(printf '%s' "$json" | jq -r .tier)
  if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "ok   $name -> tier $got"
  else fail=$((fail+1)); echo "FAIL $name: want $want got $got  ($json)"; fi
}

expect "tiny diff is tier 0" 0 <<'EOF'
3	2	src/lib/x.ts
EOF

expect "docs and lockfile only is tier 0" 0 <<'EOF'
120	4	README.md
900	900	package-lock.json
40	0	docs/guide.md
EOF

expect "config only is tier 0" 0 <<'EOF'
30	5	config/app.yaml
12	0	tsconfig.json
EOF

expect "small single package is tier 1" 1 <<'EOF'
60	20	src/lib/photos.ts
10	4	src/lib/photos.test.ts
EOF

expect "exactly at T1 limits is tier 1" 1 <<'EOF'
100	50	src/lib/a.ts
0	0	src/lib/b.ts
0	0	src/lib/c.ts
EOF

expect "four files pushes to tier 2" 2 <<'EOF'
30	10	src/lib/a.ts
20	10	src/lib/b.ts
10	5	src/lib/c.ts
5	5	src/lib/d.ts
EOF

expect "two packages pushes to tier 2" 2 <<'EOF'
40	10	cmd/server/main.go
30	10	internal/api/handler.go
EOF

expect "medium diff is tier 2" 2 <<'EOF'
300	150	internal/api/handler.go
50	20	internal/api/handler_test.go
EOF

expect "over 600 LOC is tier 3" 3 <<'EOF'
500	200	internal/api/handler.go
EOF

expect "three packages is tier 3" 3 <<'EOF'
40	10	cmd/server/main.go
30	10	internal/api/handler.go
20	5	internal/store/db.go
EOF

expect "migration path is tier 3 even when small" 3 <<'EOF'
15	0	migrations/000025_add_index.up.sql
EOF

expect "workflow change is risk" 3 <<'EOF'
20	5	.github/workflows/ci.yml
15	3	src/lib/a.ts
EOF

expect "auth dir is risk" 3 <<'EOF'
25	5	src/auth/session.ts
EOF

expect "binary files do not count" 0 <<'EOF'
-	-	public/logo.png
5	1	src/lib/a.ts
EOF

TIGHTEN_T0_LOC=2 expect "env override lowers T0" 1 <<'EOF'
3	2	src/lib/x.ts
EOF

echo "risk list check:"
printf '25\t5\tsrc/auth/session.ts\n10\t2\tsrc/lib/a.ts\n' > "$TMP/numstat"
risk=$(bash "$TIER" --numstat "$TMP/numstat" | jq -r '.risk[0]')
if [ "$risk" = "src/auth/session.ts" ]; then pass=$((pass+1)); echo "ok   risk path reported"
else fail=$((fail+1)); echo "FAIL risk path reported: got '$risk'"; fi

echo "missing file check:"
if bash "$TIER" --numstat "$TMP/does-not-exist" >/dev/null 2>&1; then
  fail=$((fail+1)); echo "FAIL missing numstat file should exit non-zero"
else pass=$((pass+1)); echo "ok   missing numstat file exits non-zero"; fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
