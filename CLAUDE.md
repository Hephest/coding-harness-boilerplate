# CLAUDE.md

> Keep this file under 150 lines. Anything path-specific goes in `.claude/rules/`.
> Anything that must *always* happen goes in a hook or a script, not here.

## Project

- **What:** <project name>: <one sentence on what this repo does>
- **Stack:** <language, framework, DB>

## Repo map

```
src/            app code (danger zones have their own CLAUDE.md; see .claude/protected-paths)
tests/          tests, one per acceptance criterion
docs/           architecture, ADRs, runbooks: where truth lives (read on demand)
scripts/        verify.sh (definition of done), contract-approve.sh (the user approves a
                contract), herdr-sub.sh (background subagents), harness-init.sh (copy the
                harness into another project)
.claude/        settings, hooks, rules, agents, skills
.agent/         contracts, receipts, lessons, run state
```

## Where truth lives

Don't load these up front; open the one you need.
- How it fits together → `docs/architecture.md` · Why it's built this way → `docs/adr/`
- How to operate it → `docs/runbooks/` · Module gotchas → the module's local `CLAUDE.md`
- How the harness works (hooks, invariants, maintainer mode) → [docs/harness.md](docs/harness.md)
- If code and docs disagree, fix the doc in the same task.

## Skills

`debug` · `refactor` · `code-review` · `herdr-subagents`. Use the matching skill instead of
improvising the workflow. `release` only runs when the user types `/release`.

## Commands

- Start a task (steps 1–3 below): `/task <task-id> <goal>`
- Close a task (steps 5–8 below): `/finish`
- Verify everything (the only "done" signal): `scripts/verify.sh`
- Fast check one file: `scripts/verify.sh --fast <file>`
- Run app locally: `<command>`

## Workflow: every non-trivial task

`/task` covers steps 1–3 and marks the task active in `.agent/state/active-task`, which is what
makes the guard enforce the contract. `/finish` covers steps 5–8.

1. **Contract first.** Copy `.agent/contracts/TEMPLATE.md` to `.agent/contracts/<task-id>.md`
   and fill in: target files (≤5), acceptance criteria, out-of-scope, attempt ceiling.
   If the task can't be bounded to ≤5 files, split it before writing code.
2. **Approval.** The user approves the contract, not you: the guard blocks you from running
   `scripts/contract-approve.sh`. Ask them to run `! scripts/contract-approve.sh <task-id>`, or
   the script in a plain terminal if that is refused. Any later edit to the contract needs a
   fresh approval. Say so and stop; don't work around it.
3. **Isolate.** Work on a branch in a worktree, never on `main`:
   `git worktree add -b task/<task-id> .worktrees/<task-id> HEAD`
   (The guard hook blocks edits while on `main`/`master`.)
4. **Build** inside the contract's target files only.
5. **Verify** with `scripts/verify.sh`. Exit code 0 is the only evidence that counts.
   Never say "tests pass" without having run them in this session.
6. **Review** in cold context: send `reviewer` only the task id. It reads the contract and the
   diff and runs verify itself.
7. **Receipt.** Write `.agent/receipts/<task-id>.md` from the template before calling the task done.
8. **Immunize.** If something failed along the way, add one line to `.agent/lessons.md` and
   PROPOSE the infrastructure fix (a rule, a test fixture, a script or a hook). The guard blocks
   you from applying most of them, so give the user the change to apply.

## Who does what

Inside Herdr (`HERDR_ENV=1`): run every agent below through the `herdr-subagents` skill
(`scripts/herdr-sub.sh run <agent> "<task>"`), each in its own hidden tab. Never use the built-in
Agent tool for them and never run their work in your own pane. Outside Herdr: use the Agent tool.

- Searching the code or reading more than 3 files: send it to the `Explore` subagent.
- Running tests, builds or linters: send it to `test-runner`. Only failures come back.
- After code is written: `reviewer` checks the diff before you say done.
- Before a plan is final, after the same error twice, and before a big change is done: ask `architect`.
- Pick the model at the start of the session. Don't switch models in the middle of a task.

## Loop breaker

- Max 3 repair attempts per failure. The same error twice is the cue to ask `architect` before
  the third try.
- The Stop gate stops the loop after 3 blocked stops in a row, whatever the failure: stop, ask
  `architect`, then report to the user.
- If `architect` can't unblock it, stop and report to the user with the failing output.

## Hard limits (`.claude/settings.json` and the guard hooks enforce all but the last)

- Never read or print `.env*`, `secrets/`, keys or tokens.
- No network calls (`curl`, `wget`) without the user's explicit approval.
- `git push`, `git reset` and `rm` are denied to the agent. When one is needed, give the user the
  exact command to run themselves with the `!` prefix. Don't look for another way to do it.
- Contract approval is the user's. You never run `scripts/contract-approve.sh`. A contract that
  changed since approval blocks every write until the user approves it again.
- The Bash guard applies the same write and secret-read policy to shell commands (`sed -i`, `>`,
  `cp`, `cat .env`). Best effort: a command it can't resolve passes and is logged.
- Harness files are human-owned: root `CLAUDE.md`, everything directly under `.claude/` and its
  hooks, rules, agents, skills and commands, `tests/harness/`, and `verify.sh`, `herdr-sub.sh`,
  `harness-init.sh` and `contract-approve.sh`. Propose the change; the user applies it.
  See [docs/harness.md](docs/harness.md#harness-files-are-human-owned).
- No new dependencies unless the contract lists them.
