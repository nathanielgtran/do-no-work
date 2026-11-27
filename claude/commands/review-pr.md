Review the current PR (or PR $ARGUMENTS if specified).

1. Get the PR details: `gh pr view $PR_NUMBER` (use current branch if no number given)
2. Get the full diff: `gh pr diff $PR_NUMBER`
3. Review the changes for:
   - **Bugs**: Logic errors, edge cases, null/nil checks
   - **Security**: Credentials, injection, OWASP top 10
   - **Tests**: Missing test coverage for new code
   - **Code quality**: Functions >50 lines, deep nesting, silent error swallowing
   - **CLAUDE.md compliance**: Check against the project's CLAUDE.md rules (commit style, code quality rules, testing requirements)
   - **Style**: Matches existing patterns in the codebase

Present the review as:

### PR Review: [title]
**Overall**: [LGTM / Minor Issues / Needs Changes]

| Severity | File | Line | Issue |
|----------|------|------|-------|
| ... | ... | ... | ... |

**Summary**: 2-3 sentences on the overall quality and any patterns noticed.

Keep it concise. Don't nitpick formatting or style unless it deviates from the existing codebase. Focus on things that could break in production.
