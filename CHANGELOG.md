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

### Changed
- `README-harness.md` moved to `docs/harness.md`.
- `scripts/verify.sh` exits `78` (not `1`) when no sensors are configured, so setup gaps can be
  told apart from failing code.

### Fixed
- `/task` on a fresh repo: the guard no longer blocks writing `.agent/` files on `main`.
- `.gitignore` no longer ignores `.agent/state/.gitkeep`; it also ignores OS and editor files.
- Removed a leftover project name from `CLAUDE.md`.

### Security
- The guard now blocks edits to `.claude/settings.local.json`, which could add allow rules.

### Planned (v0.2)
- Guard shell writes (a PreToolUse `Bash` matcher for write-like commands).
- Contract approval, so the agent can't widen its own scope.
- Scope the reviewer agent's Bash access.
- `herdr-sub.sh` edge cases (orphaned tab on parse failure, argument parsing, quoting).
- `scripts/harness-init.sh` to automate the quickstart.

[Unreleased]: https://github.com/OWNER/coding-harness-boilerplate/commits/main
