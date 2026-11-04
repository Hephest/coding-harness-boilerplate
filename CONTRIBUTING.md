# Contributing

Thanks for helping. This repo is developed **with its own harness**, so the workflow below is
also a live test of the boilerplate.

## Setup

```bash
git clone https://github.com/Hephest/coding-harness-boilerplate && cd coding-harness-boilerplate
git config core.hooksPath .githooks     # optional: run the self-test before every commit
tests/harness/run.sh                    # about 90 seconds; should end with "0 failed"
```

The pre-commit hook runs the same self-test, so every commit waits about 90 seconds.

You need `bash`, `git`, and `jq` or `python3`. `shellcheck` is optional locally; CI always
runs it.

## Maintainer mode

In a normal project the guards block Claude from editing harness files: `CLAUDE.md`, rules, hooks,
`settings.json` and every other file directly under `.claude/`, agents, skills, slash commands,
`verify.sh`, `herdr-sub.sh`, `harness-init.sh`, `contract-approve.sh` and the self-test.
That is the point. Here the harness files *are* the product, so maintainers start Claude with:

```bash
cd .worktrees/<task-id>
HARNESS_MAINTAINER=1 claude
```

Set it at launch, from inside the worktree. `.claude/settings.local.json` is gitignored and
doesn't exist in worktrees, so it can't carry the flag. In maintainer mode:

- the guards allow edits to harness files
- secrets, `.git` internals, whole repositories, `.claude/settings.local.json`, `main`, contract
  scope and contract approval are **still** enforced
- with no project sensors configured, `scripts/verify.sh` runs `tests/harness/run.sh`

Never ship maintainer mode as a default, and never document it as something template users
should turn on.

## Making a change

1. **Contract.** `/task <id> <goal>` writes `.agent/contracts/<id>.md` (≤5 target files) and
   creates the `task/<id>` worktree. Split bigger changes.
2. **Approve.** Read the contract, then run `scripts/contract-approve.sh <id>` yourself (the
   agent can't). Edits on the branch block until you do, and again after any change to the
   contract. On `task/<id>` the branch name sets the task, whatever `active-task` says. The
   agent being unable to approve is best effort, so read the contract yourself.
3. **Build** in the worktree. Every behaviour change to a hook or `verify.sh` gets a case that
   fails without the change. New cases go in `tests/harness/cases-<topic>.sh`, which `run.sh`
   sources; don't grow `run.sh` itself.
4. **Changelog:** add a line under `## [Unreleased]` in `CHANGELOG.md`.
5. **Verify:** `HARNESS_MAINTAINER=1 scripts/verify.sh` must exit 0.
6. **Finish:** `/finish` verifies, commits on the task branch, sends the `reviewer` agent to
   review `git diff main...HEAD` cold, and writes the receipt with the real SHA. Review fixes
   are new commits.
7. Open a pull request against `main`.

Contracts and receipts for this repo stay local (`.git/info/exclude`), so template users don't
inherit our task history. The CHANGELOG is the public record.

## Versioning

The harness follows [SemVer](https://semver.org). `.claude/HARNESS_VERSION` is the single source
of truth and travels into every project created from the template. It only changes in a release
commit. While in `0.x`, minor releases may still contain breaking changes, but they are always
called out.

| Bump | When | Examples |
|---|---|---|
| **Major** | Projects using the harness must act | contract or receipt format the hooks parse; renamed/removed script, command, agent or skill; new hook wiring in `settings.json`; renamed `verify.sh` CONFIG variable or exit-code meaning |
| **Minor** | New, opt-in capability | new agent, skill, rule, sensor, or a hook check that only blocks things that were already documented as forbidden |
| **Patch** | Nothing to do for users | bug fixes, docs, test-only changes |

Every breaking entry in the changelog gets an **Upgrading** note with the exact steps.

## Releasing

Releases are prepared by the `release` skill in a task worktree (the guard blocks edits on
`main`), and published by a human.

1. `/task release-vX.Y.Z`, then in its worktree:
   - `HARNESS_MAINTAINER=1 scripts/verify.sh` exits 0
   - move `## [Unreleased]` entries to `## [X.Y.Z] - YYYY-MM-DD` and add the compare link
   - write `X.Y.Z` to `.claude/HARNESS_VERSION` (only ever created or bumped here)
   - update the version badge in `README.md`
   - commit `release: vX.Y.Z`
2. Merge to `main`, then tag on `main`:
   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   ```
3. Publish (maintainer only, needs explicit approval when an agent prepares it):
   ```bash
   git push origin main --follow-tags
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <(awk '/^## \[X.Y.Z\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md)
   ```

## Reporting security issues

See [SECURITY.md](SECURITY.md). Please don't open public issues for bypasses of in-scope
guardrails.
