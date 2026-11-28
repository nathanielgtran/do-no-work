# public-safety Specification

## Purpose
This repo is public, so `scripts/public-safety-check.sh` fails when a tracked file contains personal data: private network addresses, private keys, home-directory paths, values derived from the current machine and git identity, and patterns from a private deny list that is never committed.

## Requirements

### Requirement: Scope and result
The script SHALL scan the files named as arguments, or every tracked file (`git ls-files`) when none are given, skipping the script itself, `LICENSE`, and anything that is not a regular file. With no files to scan it SHALL exit 0. When no pattern matches it SHALL print `public-safety: ok (<N> files)` and exit 0. When any pattern matches it SHALL print each hit to stdout as `<file>:<line>: [<source>] ...`, print `public-safety: FAILED` to stderr, and exit 1. Matching SHALL be extended-regex and case-insensitive, and binary files SHALL be skipped.

#### Scenario: Clean tree
- **WHEN** no tracked file matches any pattern
- **THEN** the script prints `public-safety: ok (<N> files)` and exits 0

#### Scenario: Hit
- **WHEN** a tracked file `lan.txt` has a private IPv4 address on line 2
- **THEN** the script prints `lan.txt:2: [builtin] ...`, prints `public-safety: FAILED` to stderr, and exits 1

### Requirement: Built-in patterns
The built-in patterns SHALL match a private IPv4 address (10/8, 172.16/12 or 192.168/16, written as four dotted numbers), the header line of a PEM private key, a Unix home-directory path (a user name directly under `home` or `Users` at the filesystem root), a Windows user-profile path on drive `C:`, and the same profile reached through the WSL `/mnt/c` mount. A builtin hit SHALL echo the matching line.

#### Scenario: Home path
- **WHEN** a file contains a Unix home path with a user name
- **THEN** it is reported with source `builtin`

### Requirement: Machine-derived patterns
The script SHALL also derive patterns from the machine it runs on: the `USER` name (when at least 3 characters, not `root`, and not running under GitHub Actions) as a whole word, the git `user.email` (unless it is the owner's GitHub `noreply` address), and the git `user.name` (when at least 3 characters and not equal to the owner of the `origin` remote). A derived hit SHALL be reported as `[derived] matched private pattern` without echoing the line.

#### Scenario: Git email in a file
- **WHEN** a tracked file contains the configured git email address
- **THEN** the hit is reported with source `derived` and the address is not printed

### Requirement: Private deny list
The script SHALL read additional patterns, one extended regex per line with `#` comments and blank lines ignored, from the environment variable `PUBLIC_SAFETY_DENY_LIST` when it is non-empty, and otherwise from the file named by `PUBLIC_SAFETY_DENY` (default `~/.config/do-no-work/public-safety-deny`). A private hit SHALL be reported as `[private] matched private pattern` and the pattern and the line SHALL NOT be printed. When there is no list it SHALL print `public-safety: no private list at <path> (builtin + derived only)` to stderr and still run the other checks.

#### Scenario: Private pattern hit
- **WHEN** the deny list holds `acme-secret-client` and a file line reads `work for Acme-Secret-Client today`
- **THEN** the output has `note.txt:2: [private] matched private pattern` and does not contain the client name

#### Scenario: CI supplies the list
- **WHEN** `PUBLIC_SAFETY_DENY_LIST` is set and the deny file does not exist
- **THEN** the patterns from the variable are used

#### Scenario: No list
- **WHEN** neither the variable nor the file exists
- **THEN** the missing-list note is printed and builtin and derived hits are still reported

### Requirement: Allow marker
A line containing the text `public-safety: allow` SHALL NOT be reported, for any source.

#### Scenario: Marked line
- **WHEN** a line holds a private IP address and ends with `public-safety: allow`
- **THEN** the script exits 0

### Requirement: Enforcement points
The check SHALL run as a local `pre-commit` hook (`public-safety`, passing the staged file names) and as a step of the `test` job in `.github/workflows/ci.yml`, where `PUBLIC_SAFETY_DENY_LIST` comes from a repository secret.

#### Scenario: Commit with a leak
- **WHEN** `pre-commit` is installed and a commit stages a file with a builtin hit
- **THEN** the hook fails the commit
