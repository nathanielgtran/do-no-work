"""Tests for pure reconcile functions in generate.py.

No real gh/network calls. Run with:
  python3 -m pytest test_generate.py -v
  python3 test_generate.py       (self-running fallback)
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from generate import extract_ids, annotate_line


class TestExtractIds:
    def test_github_ref(self):
        ids = extract_ids("Fix thing closes #123")
        assert "#123" in ids

    def test_fleet_changeid(self):
        ids = extract_ids("Ship fix-129 to prod")
        assert "fix-129" in ids

    def test_multiple_ids_one_line(self):
        ids = extract_ids("Resolves #45 and ci-124, also sec-48")
        assert "#45" in ids
        assert "ci-124" in ids
        assert "sec-48" in ids

    def test_date_not_matched(self):
        # dates like 2026-08-01 start with digits — must NOT match as change-id
        ids = extract_ids("Added 2026-08-01 to schedule")
        # numeric-prefix tokens must not appear as change-ids
        change_ids = [i for i in ids if not i.startswith("#")]
        for ci in change_ids:
            assert not ci[0].isdigit(), f"Date fragment matched as change-id: {ci}"

    def test_no_ids(self):
        ids = extract_ids("Just a plain prose line with no refs")
        assert ids == []

    def test_feat_changeid(self):
        ids = extract_ids("[feat-142] add quiz redesign")
        assert "feat-142" in ids

    def test_short_prefix_excluded(self):
        # single-char prefix like "a-1" should NOT match (prefix must be >= 2 chars)
        ids = extract_ids("something a-1 in prose")
        change_ids = [i for i in ids if not i.startswith("#")]
        assert "a-1" not in change_ids

    def test_infra_changeid(self):
        ids = extract_ids("infra-16: upgrade runner")
        assert "infra-16" in ids

    def test_test_changeid(self):
        ids = extract_ids("test-13 coverage for auth")
        assert "test-13" in ids


class TestAnnotateLine:
    def _index(self):
        return {
            "#123": (123, "2026-07-15"),
            "fix-129": (130, "2026-07-20"),
        }

    def test_matched_gh_ref(self):
        result = annotate_line("Deploy thing closes #123", self._index())
        assert "likely-done" in result
        assert "PR #123" in result
        assert "2026-07-15" in result

    def test_matched_changeid(self):
        result = annotate_line("Ship fix-129 to prod", self._index())
        assert "likely-done" in result
        assert "PR #130" in result

    def test_unmatched_returns_original(self):
        line = "Add dark mode support"
        result = annotate_line(line, self._index())
        assert result == line

    def test_empty_index_returns_original(self):
        line = "Fix #999 something"
        result = annotate_line(line, {})
        assert result == line

    def test_first_match_wins(self):
        # line has two ids; both in index — first encountered gets annotated
        index = {
            "#45": (45, "2026-06-01"),
            "ci-124": (200, "2026-06-10"),
        }
        result = annotate_line("Resolves #45 and ci-124", index)
        assert "likely-done" in result
        # ensure only one annotation appended
        assert result.count("likely-done") == 1

    def test_no_ids_in_line(self):
        line = "Plain prose, no refs"
        result = annotate_line(line, self._index())
        assert result == line


def _run_all():
    suites = [TestExtractIds, TestAnnotateLine]
    passed = failed = 0
    for suite_cls in suites:
        suite = suite_cls()
        for name in [m for m in dir(suite) if m.startswith("test_")]:
            try:
                getattr(suite, name)()
                print(f"  PASS  {suite_cls.__name__}.{name}")
                passed += 1
            except Exception as exc:
                print(f"  FAIL  {suite_cls.__name__}.{name}: {exc}")
                failed += 1
    print(f"\n{passed} passed, {failed} failed")
    return failed


if __name__ == "__main__":
    sys.exit(_run_all())
