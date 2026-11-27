#!/usr/bin/env python3
"""Generate personal-kb/backlog.md — a read-only rollup of every active repo's
open TODO.md items plus open GitHub issues, in one queryable dashboard.

Source of truth is NOT this output. It is:
  - each real repo's TODO.md  (open `- [ ]` lines only; `[x]` done is ignored)
  - personal-kb/todo.md       (cross-repo / personal items -> "Cross-repo" block)
  - open GitHub issues per repo (best-effort via `gh`)

Worktrees are skipped (a worktree's `.git` is a file, a real repo's is a dir),
so we never double-count the same TODO.md carried on a feature branch.

Output format: priority-triage view with 3 urgency buckets across all repos,
sorted by repo label within each bucket. Mobile-readable on GitHub web.

Usage:
  python3 generate.py            # full scan incl. gh issues + reconcile
  python3 generate.py --no-gh    # skip gh issue calls (fast / offline)
"""
import os
import re
import sys
import json
import subprocess
from datetime import datetime

GITHUB = os.path.expanduser("~/Github")
OUT = os.path.join(GITHUB, "personal-kb", "backlog.md")
OPEN_RE = re.compile(r"^\s*-\s*\[ \]\s?(.*)")
WITH_GH = "--no-gh" not in sys.argv

# Comma-separated repo names to leave out of the rollup.
SKIP = set(filter(None, os.environ.get("BACKLOG_SKIP", "").split(",")))

# Change-ID: lowercase prefix of >= 2 letters, hyphen, digits (fix-129, feat-142).
# A date like 2026-08-01 never matches because it starts with a digit.
_CHANGEID_RE = re.compile(r"\b([a-z]{2,}-\d+)\b")
_GHREF_RE = re.compile(r"#(\d+)")

_BLOCKER_RE = re.compile(
    r"(?i)\b(p0|blocker|blocked|leaked?|rotate|red|broken|down|exfil|security|"
    r"cve|vuln|urgent|critical|fail[- ]?closed|breaks?|secret|credential)\b|🔴|⚠"
)
_DEMOTE_RE = re.compile(
    r"(?i)\b(optional|someday|later|defer|deferred|eventually|"
    r"nice[- ]to[- ]have|consider|hygiene|housekeeping|cleanup|clean up|tidy|"
    r"not send[- ]?blocking|non[- ]blocking)\b"
    r"|not[ -](a[ -])?(send[ -])?block(er|ing)"
)
_WEEK_RE = re.compile(
    r"(?i)\b(merge|deploy|ship|verify|confirm|release|sign[- ]?off|send|wire|"
    r"install|flip|register|set up|setup|enable|apply)\b|#\d+"
)


def classify_priority(text: str) -> str:
    """Classify a TODO/issue line into one of three urgency buckets.

    Precedence: explicit de-prioritisers win FIRST — if the author tagged an
    item optional/deferred/hygiene/"not a blocker", honour that even when
    security keywords (rotate/secret/leaked/...) also appear in the same line.
    Then real blockers, then actionable ("this week"), else someday.

    Returns one of: "blocker", "week", "someday".
    """
    if _DEMOTE_RE.search(text):
        return "someday"
    if _BLOCKER_RE.search(text):
        return "blocker"
    if _WEEK_RE.search(text):
        return "week"
    return "someday"


def is_real_repo(path):
    # worktrees have `.git` as a FILE pointing at the primary; real repos as a DIR
    return os.path.isdir(os.path.join(path, ".git"))


def open_todos(todo_path):
    if not os.path.isfile(todo_path):
        return []
    items = []
    with open(todo_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = OPEN_RE.match(line)
            if m and m.group(1).strip():
                items.append(m.group(1).strip())
    return items


def open_issues(repo_path):
    if not WITH_GH:
        return []
    try:
        r = subprocess.run(
            ["gh", "issue", "list", "--state", "open", "--limit", "60",
             "--json", "number,title"],
            cwd=repo_path, capture_output=True, text=True, timeout=25,
        )
        if r.returncode != 0:
            return []
        return [(i["number"], i["title"]) for i in json.loads(r.stdout or "[]")]
    except Exception:
        return []


def extract_ids(line: str) -> list[str]:
    """Return candidate identifiers from a TODO line.

    Extracts:
      - GitHub issue/PR refs:  #123  -> "123"  (stored as "#123")
      - Fleet change-IDs:      fix-129, ci-124, sec-48, feat-142 -> "fix-129" etc.

    A date like 2026-08-01 does NOT match because the prefix starts with a digit.
    Returns a list of strings in the form "#NNN" or "type-N".
    """
    ids: list[str] = []
    for m in _GHREF_RE.finditer(line):
        ids.append(f"#{m.group(1)}")
    for m in _CHANGEID_RE.finditer(line):
        ids.append(m.group(1))
    return ids


def build_merged_index(repo_path: str) -> dict[str, tuple[int, str]]:
    """Run ONE gh call per repo; return {id_str -> (pr_number, merged_date)}.

    Scans each merged PR's title and branch name for #NNN and type-N refs.
    Returns empty dict on any failure (logged to stderr).
    """
    try:
        r = subprocess.run(
            ["gh", "pr", "list", "--state", "merged", "--limit", "100",
             "--json", "number,title,headRefName,mergedAt"],
            cwd=repo_path, capture_output=True, text=True, timeout=30,
        )
        if r.returncode != 0:
            print(
                f"[reconcile] gh pr list failed in {repo_path}: {r.stderr.strip()}",
                file=sys.stderr,
            )
            return {}
        prs = json.loads(r.stdout or "[]")
    except subprocess.TimeoutExpired:
        print(f"[reconcile] gh pr list timed out in {repo_path}", file=sys.stderr)
        return {}
    except Exception as exc:
        print(f"[reconcile] gh pr list error in {repo_path}: {exc}", file=sys.stderr)
        return {}

    index: dict[str, tuple[int, str]] = {}
    for pr in prs:
        pr_num: int = pr["number"]
        merged_date = (pr.get("mergedAt") or "")[:10]  # YYYY-MM-DD
        haystack = f"#{pr_num} {pr.get('title', '')} {pr.get('headRefName', '')}"
        for id_str in extract_ids(haystack):
            if id_str not in index:
                index[id_str] = (pr_num, merged_date)
    return index


def annotate_line(line: str, merged_index: dict[str, tuple[int, str]]) -> str:
    """If any id in line hits the merged index, return line + warning marker.

    Returns the original line unchanged if no match found.
    """
    for id_str in extract_ids(line):
        if id_str in merged_index:
            pr_num, merged_date = merged_index[id_str]
            return f"{line}  [likely-done: PR #{pr_num} merged {merged_date}]"
    return line


def main():
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    names = sorted(
        d for d in os.listdir(GITHUB)
        if is_real_repo(os.path.join(GITHUB, d)) and d not in SKIP
    )

    all_items: list[tuple[str, str]] = []
    repo_counts: dict[str, tuple[int, int]] = {}  # repo -> (todos, issues)
    total_todos = total_issues = total_flagged = 0

    for name in names:
        repo = os.path.join(GITHUB, name)
        # personal-kb keeps its list in lowercase todo.md and is cross-repo, not repo-scoped
        if name == "personal-kb":
            continue

        todos = open_todos(os.path.join(repo, "TODO.md"))
        issues = open_issues(repo)
        if not todos and not issues:
            continue

        total_todos += len(todos)
        total_issues += len(issues)
        repo_counts[name] = (len(todos), len(issues))

        merged_index: dict[str, tuple[int, str]] = {}
        if WITH_GH and todos:
            merged_index = build_merged_index(repo)

        repo_flagged = 0
        for t in todos:
            annotated = annotate_line(t, merged_index)
            if annotated != t:
                repo_flagged += 1
            all_items.append((name, annotated))

        total_flagged += repo_flagged

        for num, title in issues:
            all_items.append((name, f"#{num} {title}  _(gh issue)_"))

    cross = open_todos(os.path.join(GITHUB, "personal-kb", "todo.md"))
    if cross:
        total_todos += len(cross)
        for t in cross:
            all_items.append(("cross-repo", t))

    buckets: dict[str, list[tuple[str, str]]] = {
        "blocker": [],
        "week": [],
        "someday": [],
    }
    for repo_label, text in all_items:
        priority = classify_priority(text)
        buckets[priority].append((repo_label, text))

    # Stable sort keeps each repo's original item order.
    for key in buckets:
        buckets[key].sort(key=lambda x: x[0])

    n_blockers = len(buckets["blocker"])
    n_week = len(buckets["week"])
    n_someday = len(buckets["someday"])
    n_repos = len(repo_counts)

    header = (
        "# Backlog\n\n"
        f"_Generated {stamp}. **Do not hand-edit.** Source = each repo's TODO.md open items "
        "+ open GitHub issues; cross-repo/personal items in todo.md. "
        "Regenerate via the `backlog` skill "
        "(`python3 ~/.claude/skills/backlog/generate.py`)._\n\n"
        f"**{total_todos} open todos + {total_issues} open issues** across {n_repos} repos."
        + (" _Cross-repo items included._" if cross else "")
        + (f" _{total_flagged} items flagged as likely-done (merged PR found)._" if total_flagged else "")
        + "\n"
    )

    def bucket_lines(label: str, items: list[tuple[str, str]]) -> str:
        lines = [f"\n## {label}  ({len(items)})\n"]
        for repo_label, text in items:
            lines.append(f"- [ ] {text}  · _{repo_label}_")
        return "\n".join(lines)

    body = (
        bucket_lines("\U0001f525 Blockers — do now", buckets["blocker"])
        + "\n\n"
        + bucket_lines("\U0001f4c5 This week", buckets["week"])
        + "\n\n"
        + bucket_lines("\U0001f5c4 Someday", buckets["someday"])
    )

    detail_lines = ["\n<details><summary>By repo (counts)</summary>\n"]
    for repo_label in sorted(repo_counts):
        t, i = repo_counts[repo_label]
        detail_lines.append(f"- {repo_label} — {t} todo / {i} issue")
    if cross:
        detail_lines.append(f"- cross-repo — {len(cross)} todo / 0 issue")
    detail_lines.append("\n</details>")

    text = header + body + "\n" + "\n".join(detail_lines) + "\n"

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(text)

    print(f"Wrote {OUT}")
    print(
        f"  {total_todos} todos, {total_issues} issues, {n_repos} repos"
        + (" + cross-repo" if cross else "")
        + (f", {total_flagged} likely-done flags" if total_flagged else "")
        + f"  [{n_blockers} blockers / {n_week} week / {n_someday} someday]"
    )


if __name__ == "__main__":
    main()
