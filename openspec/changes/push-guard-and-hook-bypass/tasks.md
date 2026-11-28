## 1. Guard
- [x] 1.1 Add failing cases to `tests/hooks_test.sh` (refspec, `-C`, `-c` push to main; `--no-verify`, `-nm`, `SKIP=`, `HUSKY=`, `core.hooksPath`; less-mode push/merge; quoted-message and `git push-all` negatives)
- [x] 1.2 Add `claude/hooks/push-guard.py`
- [x] 1.3 `autonomy-gate.sh`: hook-bypass check, push-guard call at all levels, jq-built output
- [x] 1.4 Tamper guard answers `ask` for hook writes, `deny` for the dial; example settings move hook rules to `permissions.ask`
## 2. Install
- [x] 2.1 `scripts/install-manifest.sh` and `install.sh` include `claude/hooks/*.py`
## 3. Docs
- [x] 3.1 `docs/REFERENCE.md` entries for `autonomy-gate` and `push-guard.py`
- [x] 3.2 `changelog.d` fragment
