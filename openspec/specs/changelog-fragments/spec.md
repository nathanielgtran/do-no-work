# changelog-fragments Specification

## Purpose
`scripts/changelog.sh` lets parallel PRs record changelog entries without ever editing `CHANGELOG.md`: each PR adds one fragment file under `changelog.d/`, CI validates fragments, and a release folds them into `CHANGELOG.md`.

## Requirements

### Requirement: Fragment format
A fragment SHALL be `changelog.d/<type>-<N>.md` where `<type>` is one of `feat`, `fix`, `docs` or `chore` and `<N>` is a whole number. It SHALL hold exactly one non-empty line, the description without the change ID. `changelog.d/README.md` SHALL be ignored. The script SHALL run from the root of the git repo that holds the current directory, or from the current directory when it is not in one.

#### Scenario: Valid fragment
- **WHEN** `changelog.d/feat-5.md` holds `add a thing`
- **THEN** `scripts/changelog.sh check` accepts it

### Requirement: Next free ID
`scripts/changelog.sh next <type>` SHALL print `<type>-<max+1>`, where `max` is the highest number used for that type either as an `<type>-<N>` ID anywhere in `CHANGELOG.md` or as a fragment name, or `<type>-1` when none is used. A type other than `feat`, `fix`, `docs` or `chore` SHALL print `unknown type: <type>` to stderr and exit 2.

#### Scenario: IDs from both sources
- **WHEN** `CHANGELOG.md` lists `feat-2` and `fix-7`, and fragments `feat-5` and `docs-1` exist
- **THEN** `next feat` prints `feat-6`, `next fix` prints `fix-8`, `next docs` prints `docs-2` and `next chore` prints `chore-1`

#### Scenario: Unknown type
- **WHEN** the user runs `scripts/changelog.sh next bogus`
- **THEN** it exits 2 with `unknown type: bogus`

### Requirement: Fragment validation
`scripts/changelog.sh check` SHALL print `changelog fragments ok` and exit 0 when every fragment is valid. Otherwise it SHALL print one line per problem to stderr and exit 1. Problems are: a file name that does not match the format (`bad filename`), a file that is empty or has more than one line (`must be exactly one non-empty line`), and a fragment whose ID already appears at the start of a `- <ID>:` line in `CHANGELOG.md` (`<ID> already in CHANGELOG.md`).

#### Scenario: Bad file name
- **WHEN** `changelog.d/oops.md` exists
- **THEN** `check` exits 1 and names `oops.md`

#### Scenario: Two lines or empty
- **WHEN** `changelog.d/fix-9.md` holds two lines, or is empty
- **THEN** `check` exits 1 and names `fix-9.md`

#### Scenario: ID already released
- **WHEN** `CHANGELOG.md` has `- feat-2: old two` and `changelog.d/feat-2.md` exists
- **THEN** `check` exits 1 and names `feat-2`

### Requirement: Compile at release
`scripts/changelog.sh compile [--version vX.Y.Z]` SHALL, when no fragments exist, print `no fragments to compile` and change nothing. Otherwise it SHALL fail with the `check` output if any fragment is invalid; create `CHANGELOG.md` and its `## Unreleased` heading if absent; insert one `- <ID>: <description>` line per fragment under `## Unreleased`, ordered `feat`, `fix`, `docs`, `chore` and by ascending number within a type; remove the fragments (`git rm` for tracked files, a move into `$TRASH_DIR`, default `~/.trash`, for untracked ones); and print `compiled N fragment(s) into CHANGELOG.md`. With `--version`, it SHALL first insert a heading `## <version> - <D Mon YYYY>` directly below `## Unreleased` and place the lines under that heading, so entries that were already under `## Unreleased` follow them under the version. `--version` without a value SHALL exit non-zero.

#### Scenario: Fold into Unreleased
- **WHEN** fragments `fix-9`, `feat-10`, `chore-1`, `feat-5` and `docs-1` exist and `CHANGELOG.md` already has entries under `## Unreleased`
- **THEN** after `compile` the new lines read `feat-5`, `feat-10`, `fix-9`, `docs-1`, `chore-1` above the old entries and `changelog.d/` holds only `README.md`

#### Scenario: Second compile is a no-op
- **WHEN** `compile` runs again with no fragments left
- **THEN** it prints `no fragments to compile` and `CHANGELOG.md` is unchanged

#### Scenario: Versioned release
- **WHEN** a fragment `feat-20` exists and the user runs `compile --version v1.2.3`
- **THEN** `CHANGELOG.md` has `## Unreleased` above a `## v1.2.3 - <date>` heading whose first line is `- feat-20: <description>`

#### Scenario: Invalid fragment blocks compile
- **WHEN** any fragment fails `check`
- **THEN** `compile` prints the problems, exits 1 and leaves `CHANGELOG.md` and the fragments unchanged

### Requirement: CI runs the check
`.github/workflows/ci.yml` SHALL run `scripts/changelog.sh check` on every pull request and every push to `main`.

#### Scenario: PR with a malformed fragment
- **WHEN** a pull request adds `changelog.d/oops.md`
- **THEN** the `Changelog fragments` step fails
