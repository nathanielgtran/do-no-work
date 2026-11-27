# Changelog fragments
Each PR adds one file, `changelog.d/<id>.md`, where `<id>` is the change ID (`feat-13`, `fix-6`, `docs-2`, `chore-1`).
The file holds one markdown line: the description, without the ID. Get a free ID with `scripts/changelog.sh next <type>`.
`scripts/changelog.sh check` validates fragments (CI); `scripts/changelog.sh compile [--version vX.Y.Z]` folds them into `CHANGELOG.md` at release.
