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
scripts/        verify.sh (definition of done), herdr-sub.sh (background subagents)
.claude/        settings, hooks, rules, agents, skills
.agent/         contracts, receipts, lessons, run state
```

## Where truth lives

Don't load these up front; open the one you need.
- How it fits together → `docs/architecture.md` · Why it's built this way → `docs/adr/`
- How to operate it → `docs/runbooks/` · Module gotchas → the module's local `CLAUDE.md`
- If code and docs disagree, fix the doc in the same task.

## Skills

`debug` · `refactor` · `code-review` · `release` · `herdr-subagents`. Use the matching skill
instead of improvising the workflow.

## Commands

- Verify everything (the only "done" signal): `scripts/verify.sh`
- Fast check one file: `scripts/verify.sh --fast <file>`
- Run app locally: `<command>`

## Workflow: every non-trivial task

1. **Contract first.** Copy `.agent/contracts/TEMPLATE.md` to `.agent/contracts/<task-id>.md`
   and fill in: target files (≤5), acceptance criteria, out-of-scope, attempt ceiling.
   If the task can't be bounded to ≤5 files, split it before writing code.
2. **Isolate.** Work on a branch in a worktree, never on `main`:
   `git worktree add -b task/<task-id> .worktrees/<task-id> HEAD`
   (The guard hook blocks edits while on `main`/`master`.)
3. **Build** inside the contract's target files only.
4. **Verify** with `scripts/verify.sh`. Exit code 0 is the only evidence that counts.
   Never say "tests pass" without having run them in this session.
5. **Review** in cold context: send the contract, `git diff`, and verify output to `reviewer`.
6. **Receipt.** Write `.agent/receipts/<task-id>.md` from the template before calling the task done.
7. **Immunize.** If something failed along the way, add one line to `.agent/lessons.md`
   and turn it into infrastructure (a rule, a test fixture, a script, or a hook).

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

- Max 3 repair attempts per failure. If the same verify error appears twice, stop and ask `architect`.
- If `architect` can't unblock it, stop and report to the user with the failing output.

## Hard limits (also enforced in `.claude/settings.json`)

- Never read or print `.env*`, `secrets/`, keys or tokens.
- No network calls (`curl`, `wget`) and no `git push` without the user's explicit approval.
- No new dependencies unless the contract lists them.
