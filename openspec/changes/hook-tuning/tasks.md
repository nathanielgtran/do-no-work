## 1. Tests first
- [x] 1.1 `tests/hooks_test.sh`: post-pr-create with and without a `claude-review` workflow
- [x] 1.2 `tests/research_hooks_test.sh`: stop-gate fingerprint (same tree once, changed file reruns, failure not stored)
- [x] 1.3 `tests/go_check_test.sh`: no `go test`, silent pass, stderr + exit 2 on vet, gofmt and lint failure
- [x] 1.4 `tests/hooks_test.sh`: settings example wiring (`if`, `async`, `asyncRewake`, `onFailure`)
## 2. Code
- [x] 2.1 `claude/hooks/post-pr-create.sh`
- [x] 2.2 `claude/hooks/go-check.sh`
- [x] 2.3 `claude/hooks/stop-gate.sh`
- [x] 2.4 `claude/settings.example.json`
## 3. Docs
- [x] 3.1 `docs/REFERENCE.md` entries and hook table
- [x] 3.2 `changelog.d` fragment
