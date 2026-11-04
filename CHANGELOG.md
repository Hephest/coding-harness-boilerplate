# Changelog

All notable changes to this harness are documented here.
The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). See
[CONTRIBUTING.md](CONTRIBUTING.md#versioning) for what counts as a breaking change for a harness.

Projects created from this template: replace this file with your own changelog. Your harness
version is recorded in `.claude/HARNESS_VERSION`.

## [Unreleased]

This is breaking: it adds hook wiring to `settings.json` and a new approval step. It will ship
as v0.2.0, which `0.x` allows when it is called out. See **Upgrading** below.

### Added
- A Bash guard (`.claude/hooks/guard-bash.sh`). It applies the same rules as Edit/Write to
  shell writes (`>`, `tee`, `cp`, `mv`, `sed -i`, `tar -x`, `unzip`, `rsync`, `find -delete` and
  similar), blocks reading secrets with known commands such as `cat` and `grep`, and catches
  denied git forms that prefix rules miss. It is best effort: what it can't resolve passes and is
  logged to `.agent/state/guard-bash.log`. See [SECURITY.md](SECURITY.md).
- Contract approval. `scripts/contract-approve.sh <task-id>` records a hash of the contract.
  Until you approve it, and after any edit to it, the guard blocks work on that task. The guard
  and `settings.json` refuse the agent the known ways of running the script. That is best
  effort: see [SECURITY.md](SECURITY.md), limitation 12.
- One task id. On a `task/<id>` branch with a contract or an approval record, `<id>` alone sets
  the approval check, the scope check and the Stop gate's receipt check, and
  `.agent/state/active-task` is ignored there. Elsewhere `active-task` decides, and its contract
  has to be approved.
- The reviewer agent is limited to `scripts/verify.sh` and `git diff|log|show|status`, piped into
  `head`, `tail`, `grep` or `wc`. Anything else is blocked, and a command the guard can't check
  is blocked too.
- `scripts/harness-init.sh` copies the harness into a project and prints the next steps. It
  never overwrites a file.
- Self-test cases for the Bash guard, contract approval, the reviewer limits and
  `harness-init.sh`, in `tests/harness/cases-<topic>.sh`. The self-test now takes about 90
  seconds, which is also how long the opt-in pre-commit hook waits.

### Changed
- The Bash guard peels `sudo`, `doas`, `setsid`, `stdbuf` and `ionice` as well as the older
  wrappers, reads `$'...'` and `$"..."` literals as the text they stand for, and takes
  `--target-directory DIR` with a space. A relative target after a `cd` it can't resolve is judged
  from the last known directory, so `cd - && cat .env` blocks.
- The blocked `git config` keys are the wider list: `core` (whole section), `core.hooksPath`,
  `core.fsmonitor`, `core.sshCommand`, `core.pager`, `core.editor`, `alias.*`, `include.path`,
  `includeIf.*`, `diff.external`, `sequence.editor`, `filter.*`, `credential.*` and `gpg.*`.
  The check is skipped in maintainer mode.
- `scripts/harness-init.sh` warns loudly when it keeps an existing `.claude/settings.json` that
  lacks the guards.
- `scripts/verify.sh` picks `pytest` only when real Python tests exist outside `tests/harness`.
- `scripts/herdr-sub.sh --interactive` waits for the prompt to be taken, and a prompt that
  stalls fails the run and closes its tab.
- Every file directly under `.claude/` is now a harness file, as are `CLAUDE.md`,
  `.claude/rules/*`, `scripts/harness-init.sh` and `scripts/contract-approve.sh`.
- A write that would take a whole repository at once (`git restore .`, `find . -delete`, a
  bare `tar -x` or `unzip` at the repo root) is blocked.
- Writing `.env.example` is blocked, because it matches `.env.*`. Reading it is still allowed.
- Edit/Write and Bash checks share one write policy in `.claude/hooks/_lib.sh`.
- `NotebookEdit` goes through the same guard and the same post-edit check as Edit and Write.

### Fixed
- The guard no longer fails open when `git` is missing or refuses to run: it blocks.
- Force-add is caught in any position (`git add -A -f`), not only at the start of the command.
- The post-edit check resolves a relative path against the hook's working directory.
- Writing to `/` (for example `find / -delete`, `rm -rf /`) is caught by the whole-repository
  check. On Linux, with bash 5.2, the path came out empty and slipped past it.
- `herdr-sub.sh`: options can come before or after the arguments (`--` ends them), and a bad
  `--timeout` or an extra argument is an error instead of being ignored.
- `herdr-sub.sh`: when a run fails to start (unreadable pane id, `pane run`, `agent start` or
  `agent prompt` failing), its hidden tab is closed and the run is marked failed, so `list`
  doesn't show it running forever.
- `herdr-sub.sh`: repo paths with spaces, quotes or `$` no longer break the headless run script,
  and an interactive prompt keeps its newlines.
- `herdr-sub.sh wait` no longer returns at once on an interactive run that hasn't started
  working yet.

### Security
- Shell writes are checked, so `sed -i`, `tee` and `echo >` can no longer reach protected
  paths, the main branch or files outside the contract for the commands the guard knows.
- Shell reads of secrets (`cat .env`) are blocked for known commands.
- A contract has to be approved by a human, so an edit to it can't widen the agent's scope
  unseen. The guard and `settings.json` refuse the agent the known ways of running the approval
  script, also in maintainer mode. This is best effort: an agent that copies the script and
  `_lib.sh` elsewhere, or writes the approval record with a tool the guard doesn't know, gets
  past it.
- `git config` keys that run code or skip hooks (see Changed for the list) are blocked.
- Known limits, listed in [SECURITY.md](SECURITY.md): renaming a task branch drops its
  enforcement, `grep -r` can read a secret by recursion, `git log -p`, `git blame` and
  `git archive` aren't checked as readers, and `git am`, `cherry-pick`, `revert`, `rebase`,
  `pull` and `apply` can land changes in harness files.
- `CLAUDE.md` and `.claude/rules/` can't be edited by the agent.

### Upgrading
From 0.1.x. The harness files are human-owned, so you apply these yourself.

1. Copy these from the new release into your project. If you changed any of them, merge by hand
   instead of overwriting:
   - `.claude/hooks/*`: new `guard-bash.sh`, and changed `_lib.sh`, `guard-write.sh`,
     `post-edit-check.sh` and `stop-gate.sh`
   - `.claude/commands/task.md` and `.claude/commands/finish.md` (the approval step)
   - `.claude/agents/reviewer.md` (the read-only command limit)
   - `.claude/skills/herdr-subagents/SKILL.md`
   - `CLAUDE.md`: the workflow gains an approval step (steps are renumbered, `/task` now covers
     1-3 and `/finish` 5-8), plus the new hard limits. Merge these into yours.
   - `scripts/herdr-sub.sh`, `scripts/verify.sh`, and the new `scripts/contract-approve.sh` and
     `scripts/harness-init.sh`
   - `tests/harness/`: `run.sh` and the new `cases-*.sh` files

   Check that the scripts are executable (`chmod +x .claude/hooks/*.sh scripts/*.sh`).
2. Merge these entries into your `.claude/settings.json`:
   - `PreToolUse`: add `NotebookEdit` to the Edit/Write matcher
     (`Edit|Write|MultiEdit|NotebookEdit`), and add a second entry with matcher `Bash` that runs
     `"$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-bash.sh` with `"timeout": 30`.
   - `PostToolUse`: use the same `Edit|Write|MultiEdit|NotebookEdit` matcher.
   - `permissions.deny`: add `Bash(scripts/contract-approve.sh:*)` and
     `Bash(./scripts/contract-approve.sh:*)`.
3. For every task already in progress, review its contract and run
   `scripts/contract-approve.sh <task-id>` from the checkout that holds it. Without that, edits
   on its branch block with "the contract isn't approved". From now on, run it for each new
   contract after the agent writes it, and again after any edit to it. In Claude Code, use
   `! scripts/contract-approve.sh <task-id>`; if that is refused, use a plain terminal.
4. If you edited any of the files in step 1, or put your own rules in a file directly under
   `.claude/`, check them again: those files are now guarded, and `.env.example` can no longer be
   written by the agent.
5. Run `tests/harness/run.sh`. It takes about 90 seconds.

## [0.1.0] - 2026-11-03

First public release.

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
- `settings.json` denies `git push`, `git reset` and `rm` to the agent. These are `deny` rules,
  not `ask` rules, so they never depend on a prompt being answered. You run them yourself with
  the `!` prefix.

[Unreleased]: https://github.com/Hephest/coding-harness-boilerplate/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Hephest/coding-harness-boilerplate/releases/tag/v0.1.0
