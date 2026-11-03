# AI coding harness boilerplate

Drop these files into a new repo. Based on two ideas:
**the harness is the machine** (rules become hooks, scripts and permissions, not prose) and
**a model team** (cheap models read and run, mid models build and review, the top model only plans and judges).

```
.
├── CLAUDE.md                     # <150 lines: project, commands, workflow, who-does-what
├── .claude/
│   ├── settings.json             # POLICY: allow/ask/deny + hook wiring + default subagent model
│   ├── rules/                    # CONTEXT: path-scoped rules, loaded only for matching paths
│   │   ├── auth.md
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
│   │   └── finish.md             #   /finish            → verify, review, receipt, commit
│   ├── protected-paths           # danger zones: edits need a contract that names the file
│   └── skills/                   # reusable expert modes
│       ├── herdr-subagents/      #   in Herdr: each subagent runs in its own hidden tab
│       ├── debug/  refactor/     #   debugging workflow · behaviour-preserving refactors
│       └── code-review/ release/ #   review checklist · release procedure
├── .agent/                       # STATE + TRACES on disk, survives crashed sessions
│   ├── contracts/TEMPLATE.md     #   bounded scope: ≤5 files, testable criteria, attempt ceiling
│   ├── receipts/TEMPLATE.md      #   15-second audit of every finished task
│   ├── lessons.md                #   failure → permanent fix log
│   └── state/                    #   active-task, failure counters (gitignored)
├── docs/                         # PROGRESSIVE CONTEXT: read on demand, never preloaded
│   ├── architecture.md           #   components, data flow, invariants, danger zones
│   ├── adr/                      #   one file per decision (0000 template, 0001 this harness)
│   ├── runbooks/                 #   step-by-step operations
│   └── templates/MODULE_CLAUDE.md#   local CLAUDE.md for danger-zone modules
├── scripts/verify.sh             # the only definition of "done"
├── scripts/herdr-sub.sh          # run/start/wait/list subagents as background Herdr tabs
└── .worktrees/                   # isolated task checkouts (gitignored)
```

## Setup

1. Copy into the repo root, then `chmod +x .claude/hooks/*.sh scripts/verify.sh`.
2. Fill in the CONFIG block in `scripts/verify.sh` (typecheck, lint, test commands).
   Until you do, it fails on purpose — no sensors means nothing is verified.
3. Fill in the Project and Commands sections of `CLAUDE.md`.
4. Requires `git`, `bash`, and `jq` or `python3` (for reading hook input).
5. Optional, Herdr: install [Herdr](https://herdr.dev), run `herdr integration install claude`
   for accurate agent states, then start `claude` inside a Herdr pane. The `herdr-subagents`
   skill then routes all subagents to hidden tabs (`scripts/herdr-sub.sh`).

## The loop

`/task` → contract + worktree → build (guard + fast sensor on every write)
→ Stop gate runs `verify.sh` → `/finish` → cold review → receipt → commit (no push).

## Map to the seven invariants

| Invariant | Where it lives |
|---|---|
| Contract | `.agent/contracts/`, enforced by `guard-write.sh` |
| Context | CLAUDE.md <150 lines (purpose, map, rules), `docs/` on demand, `.claude/rules/` + local `CLAUDE.md` per danger zone, `Explore` on haiku |
| Tools / isolation | worktrees; guard blocks edits on `main` |
| State | `.agent/` on disk: contracts, receipts, active task |
| Sensors | `scripts/verify.sh`: format + check on every edit, full suite at Stop |
| Policy | `settings.json` deny/ask lists; guard protects secrets, the harness itself and `.claude/protected-paths` |
| Traces | receipts + `lessons.md` |

## Costs (team routing)

Pick the session model before the first message (`claude --model sonnet` for building,
or `/model opusplan` for plan-on-Opus / build-on-Sonnet). Don't switch mid-task: the cache resets.
Check `/usage` after a week to see the subagent share.
