# Harness reference

This is the reference for how the harness is put together. For the introduction and setup, read
the [README](../README.md). It is built on two ideas:

- **The harness is the machine.** Rules that must always hold become hooks, scripts and
  permissions, not prose the model may or may not follow.
- **A model team.** Cheap models read and run things, mid-tier models build and review, and the
  top model only plans and judges.

## File map

```
.
├── CLAUDE.md                     # <150 lines: project, commands, workflow, who-does-what
├── .claude/
│   ├── settings.json             # POLICY: allow/deny + hook wiring + default subagent model
│   ├── rules/                    # CONTEXT: path-scoped rules, loaded only for matching paths
│   │   ├── auth.md               #   example: copy one per sensitive area
│   │   └── tests.md
│   ├── agents/                   # THE TEAM
│   │   ├── Explore.md            #   haiku  · read-only search, returns paths + lines
│   │   ├── test-runner.md        #   haiku  · runs verify.sh, returns failures only
│   │   ├── reviewer.md           #   sonnet · cold-context diff review → ACCEPT/REJECT
│   │   └── architect.md          #   opus   · plans, escalations, big changes, <200 words
│   ├── hooks/                    # SENSORS + POLICY, deterministic
│   │   ├── guard-write.sh        #   PreToolUse: no secrets, no main branch, contract scope only
│   │   ├── post-edit-check.sh    #   PostToolUse: fast lint/syntax on the edited file
│   │   └── stop-gate.sh          #   Stop: verify.sh must pass + receipt must exist; loop breaker
│   ├── commands/
│   │   ├── task.md               #   /task <id> <goal>  → contract + worktree
│   │   └── finish.md             #   /finish            → verify, commit, review, receipt
│   ├── protected-paths           # danger zones: edits need a contract that names the file
│   ├── HARNESS_VERSION           # which harness release this project started from
│   └── skills/                   # reusable expert modes
│       ├── herdr-subagents/      #   in Herdr: each subagent runs in its own hidden tab
│       ├── debug/  refactor/     #   debugging workflow · behaviour-preserving refactors
│       └── code-review/ release/ #   review checklist · release procedure
├── .agent/                       # STATE + TRACES on disk, survives crashed sessions
│   ├── contracts/TEMPLATE.md     #   bounded scope: ≤5 files, testable criteria, attempt ceiling
│   ├── receipts/TEMPLATE.md      #   15-second audit of every finished task
│   ├── lessons.md                #   failure → permanent fix log
│   └── state/                    #   active task, Stop gate counters, subagent runs (gitignored)
├── docs/                         # PROGRESSIVE CONTEXT: read on demand, never preloaded
│   ├── harness.md                #   this file
│   ├── architecture.md           #   components, data flow, invariants, danger zones (fill in)
│   ├── adr/                      #   one file per decision (0000 template, 0001 this harness)
│   ├── runbooks/                 #   step-by-step operations
│   └── templates/MODULE_CLAUDE.md#   local CLAUDE.md for danger-zone modules
├── scripts/verify.sh             # the only definition of "done"
├── scripts/herdr-sub.sh          # run/start/wait/list subagents as background Herdr tabs
├── tests/harness/run.sh          # self-test: proves the hooks still enforce what this doc says
└── .worktrees/                   # isolated task checkouts (gitignored)
```

## The seven invariants

A task only counts as safe when all seven hold. Each one is enforced by a file, not by a
sentence in a prompt.

| # | Invariant | What it means | Where it lives |
|---|---|---|---|
| 1 | **Contract** | Every task has written, bounded scope: ≤5 target files, testable acceptance criteria, an attempt ceiling. | `.agent/contracts/`, enforced by `guard-write.sh` |
| 2 | **Context** | The model sees only what the task needs: a short CLAUDE.md, with everything else loaded on demand. | CLAUDE.md <150 lines, `docs/` on demand, `.claude/rules/` and local `CLAUDE.md` per danger zone, `Explore` on haiku |
| 3 | **Tools / isolation** | Work happens in a throwaway checkout, never on the main branch. | git worktrees; the guard blocks edits on `main`/`master` |
| 4 | **State** | Progress lives on disk, not in the chat, so a crashed session loses nothing. | `.agent/`: contracts, receipts, active task |
| 5 | **Sensors** | "Done" is measured by tools, not claimed by the model. | `scripts/verify.sh`: fast check on every edit, full suite at Stop |
| 6 | **Policy** | Dangerous actions are denied outright, so nothing depends on a prompt being answered. A human runs them with the `!` prefix. | `settings.json` allow/deny; the guard protects secrets, the harness itself and `.claude/protected-paths` |
| 7 | **Traces** | Every finished task leaves an audit record, and every failure becomes infrastructure. | receipts and `lessons.md` |

## Hooks in detail

| Hook | Event | Blocks when | Exit codes |
|---|---|---|---|
| `guard-write.sh` | PreToolUse on Edit/Write/MultiEdit | hook input it can't parse; secrets or `.git` internals; local permission file; harness files (unless maintainer mode); edits on `main`, `master` or a detached HEAD; files outside the active contract; danger zones not named in the contract | 2 = blocked (reason goes to Claude), 0 = allowed |
| `post-edit-check.sh` | PostToolUse on Edit/Write/MultiEdit | `verify.sh --fast <file>` fails (format, lint, syntax of that one file) | 2 = error sent back to Claude to fix now |
| `stop-gate.sh` | Stop | branch has changes and `verify.sh` fails; or `verify.sh` passes and the active task has no receipt | 2 = "keep working", at most 3 stops in a row; 0 = allowed |

`.agent/` is always writable, also on `main`, so `/task` can write a contract before the
worktree exists.

**What the guard protects.** It resolves symlinks first, then checks the real path:

- **Git internals:** any `.git` file or directory. This check runs before anything else.
- **Secrets**, also in maintainer mode: `.env`, `.env.*`, `.npmrc`, `.netrc`, `id_rsa*`, `*.pem`,
  `*.key`, `*.p12` and `*.pfx` at any depth, and everything under a top-level `secrets/`.
- **Local permissions**, also in maintainer mode: `.claude/settings.local.json`.
- **Harness files**, unless in maintainer mode: `.claude/hooks/*`, `.claude/settings.json`,
  `.claude/protected-paths`, `.claude/agents/*`, `.claude/skills/*`, `.claude/commands/*`,
  `scripts/verify.sh`, `scripts/herdr-sub.sh` and `tests/harness/*`.

The guard fails closed: hook input it can't parse (malformed, or no `jq` and no working `python3`)
blocks the write. It has one known fail-open. It finds the repo with `git`, so if `git` is missing
every path looks like it's outside a repo, only the `.git` check runs, and the write is allowed.
Outside a git repo there is nothing to guard, so that case is allowed on purpose.

**How the Stop gate decides.** Subagent sessions (`HARNESS_ROLE` set) skip it, and so does a
branch with no changes against `main` outside `.agent/`. Otherwise it runs `verify.sh`, with a
hook timeout of 900 seconds:

- **Exit 78 (no sensors):** there is nothing to fix in code, so it blocks once per session and
  allows the next stop. This never counts toward the loop breaker, and the receipt isn't checked.
- **Any other failure, or a missing receipt:** a blocked stop. The loop breaker counts blocked
  stops in a row per session and ignores the failure text, which can differ on every run. The 3rd
  block is the last, and tells Claude to ask `architect` and report to the user. The next stop is
  allowed. A count that can't be saved also allows the stop, because it couldn't be bounded.
- **Exit 0 with a receipt, or no active task:** the stop is allowed and the count resets.

The counts live in `.agent/state/stop-blocks-<session_id>` and
`.agent/state/sensors-warned-<session_id>`.

### `verify.sh` exit codes

| Exit | Meaning |
|---|---|
| 0 | every configured sensor passed |
| 1 | a sensor failed |
| 78 | no sensors configured: a human has to fill in the CONFIG block |

## Harness files are human-owned

The guard blocks Claude from editing hooks, `settings.json`, `protected-paths`, agents, skills,
slash commands, `verify.sh`, `herdr-sub.sh` and the self-test in `tests/harness/`. Claude proposes
a change and you apply it. This is deliberate: an agent that can rewrite its own sensors has no
sensors.

**Maintainer mode** is only for developing this boilerplate itself. Start Claude with
`HARNESS_MAINTAINER=1 claude` from inside a task worktree, and the guard allows harness edits.
Secrets, `.git` internals, `.claude/settings.local.json`, main-branch isolation and contract scope
stay enforced.
With no project sensors configured, `verify.sh` then runs `tests/harness/run.sh` instead. Don't
use maintainer mode in a normal project.

## Costs (team routing)

Pick the session model before the first message: `claude --model sonnet` for building, or
`/model opusplan` for planning on Opus and building on Sonnet. Don't switch mid-task, because
the prompt cache resets. `CLAUDE_CODE_SUBAGENT_MODEL=haiku` in `settings.json` is the default for
subagents. An agent's own `model:` frontmatter wins over that default. Check `/usage` after a week
to see the subagent share.

## Credits

The core ideas (the harness is the machine, the model team, the seven invariants) come from these
posts:

- https://x.com/swadeshkumar_/status/2117564218803392849
- https://x.com/damkina7/status/2115794667706957858
- https://x.com/0xMfox/status/2115825484529311955

The Herdr integration, maintainer mode, the self-test and the packaging are this project's own
additions. Not affiliated with Anthropic or Herdr.
