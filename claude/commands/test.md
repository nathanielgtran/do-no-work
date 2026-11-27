Run tests for the current project. Usage: /test [package-or-path]

Auto-detects the project type from the repo root and runs the appropriate test suite.

## Steps

1. **Detect project type** by checking for:
   - `go.mod` -> Go project
   - `package.json` -> Node/TypeScript project
   - `Cargo.toml` -> Rust project
   - `requirements.txt` or `pyproject.toml` -> Python project

2. **Run tests based on type:**

   **Go:**
   - `go test ./...` (or `go test ./$ARGUMENTS/...` if a package path is given)
   - Then `go vet ./...`
   - Then `golangci-lint run ./...` (if available)
   - Report: pass/fail count, any failures with file:line references

   **Node/TypeScript:**
   - Check for test script in package.json
   - `npm test` or `npx jest` or `npx vitest`
   - Report results

   **Python:**
   - `python -m pytest` (or `pytest $ARGUMENTS`)
   - Report results with coverage if `.coveragerc` or pytest-cov is configured

   **Rust:**
   - `cargo test` (or `cargo test $ARGUMENTS`)
   - Then `cargo clippy`
   - Report results

3. **Summary:**
   - Total tests run, passed, failed
   - If failures: show the failing test name, file:line, and error message
   - If all pass: one-line confirmation

Keep output concise. Don't dump raw test output unless there are failures.
