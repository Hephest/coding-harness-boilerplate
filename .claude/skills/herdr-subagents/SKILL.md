---
name: herdr-subagents
description: Run the project's subagents (Explore, test-runner, reviewer, architect) as background Herdr tasks in hidden tabs instead of the built-in Agent tool, so nothing runs in the main agent's pane. Use whenever HERDR_ENV=1 and the workflow calls for searching, running tests or builds, reviewing a diff, or asking the architect.
---

# Herdr subagents

When you run inside Herdr (`HERDR_ENV=1`), every subagent job goes to its own **hidden Herdr tab**
via `scripts/herdr-sub.sh`. Your own pane stays clean: no test logs, no file dumps, no second
TUI, no focus change. Only the subagent's short report comes back to you.

## Precondition

```bash
test "${HERDR_ENV:-}" = 1 && command -v herdr && command -v claude
```

If that fails, you are not in Herdr: fall back to the built-in Agent tool with the same agent
names, and say so once.

## Rules

1. **Never use the built-in Agent tool** for `Explore`, `test-runner`, `reviewer` or `architect`
   while `HERDR_ENV=1`. Never run their work (searches across many files, test suites, linters)
   in your own pane either. Dispatch it.
2. **Never `herdr pane split` or `herdr agent start` in your own tab.** The script creates a
   separate tab with `--no-focus`; the user's view never moves.
3. **Only read the report.** Don't `herdr pane read` the subagent's tab unless the report is
   missing or the run failed.
4. **Close only what you started.** The script closes its own tab when the run ends. Never close
   tabs, panes or workspaces it didn't create.
5. **Don't resubmit on timeout.** A timeout means "still running", not "failed". Wait again.

## Commands

```bash
# One job, wait for the result (most common)
scripts/herdr-sub.sh run Explore "Where is session refresh handled? Files + lines only."
scripts/herdr-sub.sh run test-runner "Run scripts/verify.sh"
scripts/herdr-sub.sh run reviewer "Review task <task-id>. Contract: .agent/contracts/<task-id>.md"
scripts/herdr-sub.sh run architect @.agent/contracts/<task-id>.md

# Independent jobs in parallel: start all, then wait on each
a=$(scripts/herdr-sub.sh start Explore "Find all callers of SessionStore.refresh")
b=$(scripts/herdr-sub.sh start test-runner "Run scripts/verify.sh")
scripts/herdr-sub.sh wait "$a"
scripts/herdr-sub.sh wait "$b"

scripts/herdr-sub.sh list            # runs and status
scripts/herdr-sub.sh close <run-id>  # close a tab kept with --keep
```

Options for `run` / `start`:
- `--timeout MS`: default 600000 (10 min). Use 120000 for Explore and 900000 for full test suites.
- `--interactive`: start a real Claude session in the tab (`herdr agent start --kind claude`).
  Use it when the user wants to watch or steer the subagent. Default is headless (`claude -p`).
- `--keep`: leave the tab open afterwards, for the user to inspect.

`wait` takes only `--timeout MS`; `--interactive` and `--keep` are set when the run starts. `list`
and `close <run-id>` take no options.

`@file` passes a file's contents as the prompt (contracts, plans, diffs saved to a file).

## Reading results

| Exit | Meaning | What you do |
|---|---|---|
| 0 | Report printed | Use it. Full copy: `.agent/state/runs/<run-id>/report.md` |
| 1 | Subagent errored | Read the stderr tail in the output; fix the cause, then run once more |
| 3 | Blocked (interactive) | Tell the user: `herdr agent focus <run-id>` to answer it. Don't guess |
| 124 | Timed out, still running | `scripts/herdr-sub.sh wait <run-id>` again |
| 2 | Usage / not in Herdr | Fix the call, or fall back to the Agent tool |

## When to dispatch (maps to CLAUDE.md "Who does what")

- Reading more than 3 files or "where is X" → `Explore` (haiku, read-only)
- Any test, typecheck, lint or build → `test-runner` (haiku). Never run `scripts/verify.sh` in
  your own pane except as the final evidence check.
- Code written → `reviewer` (sonnet, cold context: give it only the task id / contract path)
- Plan before it's final, same error twice, change over 5 files → `architect` (opus)

Each tab gets `HARNESS_ROLE=<role>`, so the Stop gate skips subagent sessions and the
guard hook still applies to anything they try to write.

## Official Herdr skill

For general Herdr control (panes, servers, other agents), the official skill complements this
one: `npx skills add herdrdev/herdr --skill herdr -g`, or `herdr --skill` to print it.
