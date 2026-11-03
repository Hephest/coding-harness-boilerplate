---
name: release
description: Release procedure - prepare version, changelog and tag. Use when the user asks to cut, prepare or publish a release.
disable-model-invocation: true
---

# Release

The agent prepares; the user publishes. Never push, tag remotely or deploy without an explicit yes.

1. **Clean start.** In a task worktree (the guard blocks edits on `main`), working tree clean,
   `scripts/verify.sh` exits 0.
2. **Collect changes** since the last tag: `git log --oneline $(git describe --tags --abbrev=0)..HEAD`
   and the receipts in `.agent/receipts/` for those tasks.
3. **Pick the version** (semver): breaking → major, feature → minor, fix → patch. State why.
4. **Changelog.** Add a section to `CHANGELOG.md`: Added / Changed / Fixed / Removed, in plain
   words for users, not commit messages.
5. **Bump** the version where the project keeps it (package.json, pyproject.toml, …). The
   boilerplate's version file is `.claude/HARNESS_VERSION`: write `X.Y.Z` to it and follow the
   rest of [Releasing](../../../CONTRIBUTING.md#releasing).
6. **Verify again**, then commit `release: vX.Y.Z`.
7. **Stop.** Show the user the changelog section and the exact merge, tag and push/deploy commands
   from `docs/runbooks/release.md` (if it exists). The tag `vX.Y.Z` goes on `main` after the merge.
   Wait for their yes before running any of them.
