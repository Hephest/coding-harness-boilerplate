# Changelog

All notable changes to this harness are documented here.
The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). See
[CONTRIBUTING.md](CONTRIBUTING.md#versioning) for what counts as a breaking change for a harness.

Projects created from this template: replace this file with your own changelog. Your harness
version is recorded in `.claude/HARNESS_VERSION`.

## [Unreleased]

### Added
- `README.md` for humans: what the harness is, quickstart, workflow, concepts, customizing,
  security model, versioning and credits.
- `docs/harness.md`: file map, the seven invariants, hook reference, maintainer mode.
- `tests/harness/run.sh`: self-test that checks the hooks against a throwaway git repo.
- Maintainer mode: `HARNESS_MAINTAINER=1 claude` lets maintainers of this boilerplate edit
  harness files. Secrets, local settings, `main` and contract scope stay protected.
- `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md`, this changelog.
- CI workflow running the self-test on Linux and macOS; opt-in `.githooks/pre-commit`.
- `.gitattributes` forcing LF line endings for shell scripts.
- Self-test: maintainer-only check that tracked files hold no personal strings.

### Changed
- `README-harness.md` moved to `docs/harness.md`.
- `scripts/verify.sh` exits `78` (not `1`) when no sensors are configured, so setup gaps can be
  told apart from failing code.
- `/finish` now runs verify → commit on the task branch → cold review → receipt, so the reviewer
  sees the work in `git diff main...HEAD`. Review fixes are new commits, and the receipt records
  the real SHA.
- Stop gate: `verify.sh` exit 78 blocks once per session, then allows the stop, and never counts
  toward the loop breaker.
- Loop breaker: it now counts blocked stops in a row (at most 3) and ignores the failure text,
  so output that changes on every run can't keep a session looping.
- The Stop hook has a 900-second timeout.
- `verify.sh --fast` on JSON uses `jq`, then `python3`, and warns and skips if neither exists.
- `CLAUDE.md` now covers `/task`, `/finish` and human-owned harness files, and links
  `docs/harness.md`.
- `.agent/lessons.md` labels its example rows, and `docs/architecture.md` says it's a template.
- The `release` skill only runs through `/release` and names `.claude/HARNESS_VERSION`.
- ADR-0001 has a real date and links the seven invariants.
- Public docs now match the Stop gate, the guard lists and the new `/finish` order, and name the
  real GitHub owner.

### Fixed
- `/task` on a fresh repo: the guard no longer blocks writing `.agent/` files on `main`.
- `.gitignore` no longer ignores `.agent/state/.gitkeep`; it also ignores OS and editor files.
- Removed a leftover project name from `CLAUDE.md`.
- `herdr-sub.sh` forwards `HARNESS_MAINTAINER=1` to subagent tabs, headless and interactive,
  but only when the caller has it set.

### Security
- The guard now blocks edits to `.claude/settings.local.json`, which could add allow rules.
- The guard fails closed: hook input it can't parse blocks the write.
- The guard checks the real path behind a symlink, so scope and danger-zone checks still apply.
- A detached HEAD is blocked like `main`.
- Secrets are blocked at any depth, now including `*.p12`, `*.pfx`, `id_rsa*`, `.npmrc` and
  `.netrc`, and `.git` internals are matched on the full path, which also covers worktrees.
- `.claude/commands/*` and `tests/harness/*` are now harness files.
- `settings.json` denies `git add -f` and `git add --force` (prefix match only, see
  [SECURITY.md](SECURITY.md)).

### Planned (v0.2)
- Guard shell writes (a PreToolUse `Bash` matcher for write-like commands).
- Contract approval, so the agent can't widen its own scope.
- Scope the reviewer agent's Bash access.
- `herdr-sub.sh` edge cases (orphaned tab on parse failure, argument parsing, quoting).
- `scripts/harness-init.sh` to automate the quickstart.
- The other limitations in [SECURITY.md](SECURITY.md): shell reads of secrets, force-add flags
  in any position, unguarded behaviour-shaping files, and the guard's fail-open without `git`.

[Unreleased]: https://github.com/Hephest/coding-harness-boilerplate/commits/main
