#!/bin/bash
# Fails on any relative link, image path or #anchor in README.md and docs/*.md that does not resolve.
# Anchors follow GitHub's heading slug rules.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELFTEST="$(mktemp -d)"
trap 'rm -rf "$SELFTEST"' EXIT

check_links() {
  python3 - "$@" <<'PY'
import os, re, sys

root = sys.argv[1]
files = sys.argv[2:]

FENCE = re.compile(r'^\s*(```|~~~)')
LINK = re.compile(r'!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
HTML = re.compile(r'\b(?:src|srcset|href)="([^"]+)"')
CODE = re.compile(r'`+[^`]*`+')


def slug(text):
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = text.replace('`', '').strip().lower()
    text = re.sub(r'[^\w\- ]', '', text)
    return text.replace(' ', '-')


def lines_outside_fences(path):
    fenced = False
    with open(path, encoding='utf-8') as fh:
        for n, line in enumerate(fh, 1):
            if FENCE.match(line):
                fenced = not fenced
                continue
            if not fenced:
                yield n, line


anchor_cache = {}


def anchors(path):
    if path not in anchor_cache:
        seen = {}
        found = set()
        for _, line in lines_outside_fences(path):
            m = re.match(r'^#{1,6}\s+(.*?)\s*#*\s*$', line)
            if not m:
                continue
            base = slug(m.group(1))
            count = seen.get(base, 0)
            seen[base] = count + 1
            found.add(base if count == 0 else '%s-%d' % (base, count))
        anchor_cache[path] = found
    return anchor_cache[path]


bad = 0
for f in files:
    for n, line in lines_outside_fences(f):
        stripped = CODE.sub('', line)
        targets = [m.group(1) for m in LINK.finditer(stripped)]
        targets += [m.group(1) for m in HTML.finditer(line)]
        for t in targets:
            if re.match(r'^[a-z][a-z0-9+.-]*:', t, re.I):
                continue
            path, _, frag = t.partition('#')
            target = os.path.normpath(os.path.join(os.path.dirname(f), path)) if path else f
            rel = os.path.relpath(f, root)
            if not os.path.exists(target):
                print('FAIL %s:%d: missing target %s' % (rel, n, t))
                bad += 1
                continue
            if frag and target.endswith('.md') and frag not in anchors(target):
                print('FAIL %s:%d: missing anchor %s' % (rel, n, t))
                bad += 1
sys.exit(1 if bad else 0)
PY
}

fail=0

mkdir -p "$SELFTEST/docs"
printf '# Top\n\n### `engraph-*` helpers\n\n## Dup\n\n## Dup\n' > "$SELFTEST/docs/a.md"
printf '[ok](docs/a.md#engraph--helpers) [ok](docs/a.md#dup-1) `[skip](nope.md)`\n\n```\n[skip](nope.md)\n```\n' > "$SELFTEST/good.md"
printf '[bad](docs/a.md#nope)\n' > "$SELFTEST/bad-anchor.md"
printf '<img src="docs/missing.svg">\n' > "$SELFTEST/bad-file.md"

if check_links "$SELFTEST" "$SELFTEST/good.md" >/dev/null; then echo "ok   self-test: good links pass"; else echo "FAIL self-test: good links rejected"; fail=1; fi
if check_links "$SELFTEST" "$SELFTEST/bad-anchor.md" >/dev/null; then echo "FAIL self-test: bad anchor passed"; fail=1; else echo "ok   self-test: bad anchor caught"; fi
if check_links "$SELFTEST" "$SELFTEST/bad-file.md" >/dev/null; then echo "FAIL self-test: missing file passed"; fail=1; else echo "ok   self-test: missing file caught"; fi

if check_links "$REPO" "$REPO/README.md" "$REPO"/docs/*.md; then
  echo "ok   README.md and docs/*.md links resolve"
else
  fail=1
fi
exit "$fail"
