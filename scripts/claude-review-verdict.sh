#!/bin/bash
# Turn Claude's structured review result into a PR comment and, only on a clean
# PASS for the commit that was reviewed, the REVIEWED label. Fails closed.
#
# Env: REPO (owner/name), PR (number), EXPECTED_SHA (head commit the job started on),
#      STRUCTURED_OUTPUT (JSON from the action: {verdict, summary, findings[]}).
#      GH overrides the gh binary (tests).
# Exit 0 only when the label was applied.
set -euo pipefail

GH="${GH:-gh}"
: "${REPO:?}" "${PR:?}" "${EXPECTED_SHA:?}"
out="${STRUCTURED_OUTPUT:-}"

fail() {
  echo "::error::$1"
  exit 1
}

verdict=$(printf '%s' "$out" | jq -r '.verdict // empty' 2>/dev/null) || verdict=""
case "$verdict" in
  PASS | BLOCK) ;;
  *) fail "Claude review returned no parseable verdict (got '${verdict}'); not labelling" ;;
esac

summary=$(printf '%s' "$out" | jq -r '.summary // "(no summary)"')
findings=$(printf '%s' "$out" | jq -r '(.findings // [])[] | "- " + .')
body=$(printf '## Claude review\n\n%s\n\n%s\n\nReviewed commit: `%s`\n\nVERDICT: %s\n' \
  "$summary" "$findings" "$EXPECTED_SHA" "$verdict")

# A failed comment must not hide the verdict, but it is surfaced.
printf '%s' "$body" | "$GH" pr comment "$PR" -R "$REPO" --body-file - \
  || echo "::warning::could not post the review comment"

[ "$verdict" = "BLOCK" ] && fail "Claude review found blocking issues; REVIEWED not applied"

current=$("$GH" pr view "$PR" -R "$REPO" --json headRefOid --jq .headRefOid) \
  || fail "could not read the PR head SHA; not labelling"
if [ "$current" != "$EXPECTED_SHA" ]; then
  fail "PR head moved (${EXPECTED_SHA} -> ${current}) during review; not labelling"
fi

"$GH" pr edit "$PR" -R "$REPO" --add-label REVIEWED
echo "Applied REVIEWED to ${REPO}#${PR} at ${EXPECTED_SHA}"
