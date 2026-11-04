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
│   │   ├── guard-write.sh        #   PreToolUse (Edit/Write/NotebookEdit): reads the path, _lib.sh decides
│   │   ├── guard-bash.sh         #   PreToolUse (Bash): same policy for shell writes; best effort
│   │   ├── _lib.sh               #   shared: write policy, contract approval check, path helpers
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
├── scripts/contract-approve.sh   # a human approves a contract (hash under .git); the agent can't run it
├── scripts/harness-init.sh       # copy the harness into a project, print the next steps
├── tests/harness/run.sh          # self-test: proves the hooks still enforce what this doc says
├── tests/harness/cases-*.sh      #   test cases by topic, sourced by run.sh
└── .worktrees/                   # isolated task checkouts (gitignored)
```

## The seven invariants

A task only counts as safe when all seven hold. Each one is enforced by a file, not by a
sentence in a prompt.

| # | Invariant | What it means | Where it lives |
|---|---|---|---|
| 1 | **Contract** | Every task has written, bounded scope: ≤5 target files, testable acceptance criteria, an attempt ceiling. A human approves it, and an edit voids the approval. | `.agent/contracts/`, `scripts/contract-approve.sh`, enforced by `guard-write.sh` and `guard-bash.sh` |
| 2 | **Context** | The model sees only what the task needs: a short CLAUDE.md, with everything else loaded on demand. | CLAUDE.md <150 lines, `docs/` on demand, `.claude/rules/` and local `CLAUDE.md` per danger zone, `Explore` on haiku |
| 3 | **Tools / isolation** | Work happens in a throwaway checkout, never on the main branch. | git worktrees; the guards block edits on `main`/`master`, also by shell redirect |
| 4 | **State** | Progress lives on disk, not in the chat, so a crashed session loses nothing. | `.agent/`: contracts, receipts, active task |
| 5 | **Sensors** | "Done" is measured by tools, not claimed by the model. | `scripts/verify.sh`: fast check on every edit, full suite at Stop |
| 6 | **Policy** | Dangerous actions are denied outright, so nothing depends on a prompt being answered. A human runs them with the `!` prefix. | `settings.json` allow/deny; the guards protect secrets, the harness itself and `.claude/protected-paths`, and `guard-bash.sh` catches denied git forms |
| 7 | **Traces** | Every finished task leaves an audit record, and every failure becomes infrastructure. | receipts and `lessons.md` |

## Hooks in detail

| Hook | Event | Blocks when | Exit codes |
|---|---|---|---|
| `guard-write.sh` | PreToolUse on Edit/Write/MultiEdit/NotebookEdit | hook input it can't parse; git missing or failing; secrets or `.git` internals; a whole repository; local permission file; harness files (unless maintainer mode); edits on `main`, `master` or a detached HEAD; a contract that isn't approved; files outside the contract of the task; danger zones not named in the contract | 2 = blocked (reason goes to Claude), 0 = allowed |
| `guard-bash.sh` | PreToolUse on Bash (timeout 30 s) | the same write policy for the targets of known shell commands and redirects; known commands reading secrets; `contract-approve.sh`; `git push`, `git reset`, `git add -f` in any position and `git config` keys that run code or skip hooks (not in maintainer mode); for the reviewer role, anything off its allowlist | 2 = blocked, 0 = allowed. What it can't resolve passes and is logged to `.agent/state/guard-bash.log` |
| `post-edit-check.sh` | PostToolUse on Edit/Write/MultiEdit/NotebookEdit | `verify.sh --fast <file>` fails (format, lint, syntax of that one file) | 2 = error sent back to Claude to fix now |
| `stop-gate.sh` | Stop | branch has changes and `verify.sh` fails; or `verify.sh` passes and the task has no receipt | 2 = "keep working", at most 3 stops in a row; 0 = allowed |

`.agent/` is always writable, also on `main`, so `/task` can write a contract before the
worktree exists.

**What the guards protect.** Both run the same write policy (`path_policy` in `_lib.sh`).
`guard-write.sh` applies it to the path of an Edit, Write or NotebookEdit. `guard-bash.sh` lexes
the command and applies it to the targets of commands it knows (redirects, `tee`, `cp`, `mv`,
`sed -i`, `tar`, `unzip`, `rsync`, `find -delete` and others). It is best effort: interpreter
one-liners, variables and globs pass and are logged. See [SECURITY.md](../SECURITY.md). The
policy resolves symlinks first, then checks the real path:

- **Git internals:** any `.git` file or directory. This check runs before anything else.
- **Whole repositories:** a directory that holds a `.git`, or holds the repo you are in, also in
  maintainer mode. `git restore .`, `find . -delete` and a bare `tar -x` or `unzip` at the root
  block; name the paths inside instead.
- **Secrets**, also in maintainer mode, and for known shell commands that read them (a committed
  `.env.example`, `.env.sample` or `.env.template` can be read, not written): `.env`, `.env.*`, `.npmrc`, `.netrc`, `id_rsa*`, `*.pem`,
  `*.key`, `*.p12` and `*.pfx` at any depth, and everything under a top-level `secrets/`.
- **Local permissions**, also in maintainer mode: `.claude/settings.local.json`.
- **Harness files**, unless in maintainer mode: `CLAUDE.md`, every file directly under `.claude/`
  (`settings.json`, `protected-paths` and the rest), `.claude/rules/*`, `.claude/hooks/*`,
  `.claude/agents/*`, `.claude/skills/*`, `.claude/commands/*`, `scripts/verify.sh`,
  `scripts/herdr-sub.sh`, `scripts/harness-init.sh`, `scripts/contract-approve.sh` and
  `tests/harness/*`.
- **Unapproved contracts**, also in maintainer mode: with a task (see below), edits outside
  `.agent/` block until `scripts/contract-approve.sh <id>` has recorded the contract's hash, and
  again after any edit to it. Only a human runs that script: both guards and `settings.json`
  refuse the known ways of running it. That is best effort, not a lock: an agent that copies the
  script and `_lib.sh` elsewhere, or writes the record with a tool the guard doesn't know, gets
  past it (see [SECURITY.md](../SECURITY.md)). Run it with `! scripts/contract-approve.sh <id>`,
  or in a plain terminal if that is refused.

**Which task a write belongs to.** One id drives the approval check, the scope check and the Stop
gate's receipt check (`effective_task` in `_lib.sh`):

- On a `task/<id>` branch that has a contract or an approval record for `<id>`, `<id>` is the
  task. `.agent/state/active-task` is ignored there, because the agent can rewrite that file.
- On any other branch, and on a task branch with neither, `.agent/state/active-task` names the
  task, and its contract has to be approved too.
- With neither, there is no task: only the protected paths, the harness files and the `main`
  rule apply. Renaming a task branch (`git branch -m`) puts you here, and the guard doesn't stop
  it.

The Bash guard also peels `sudo`, `doas`, `setsid`, `stdbuf`, `ionice`, `env`, `nice`, `timeout`,
`xargs` and similar wrappers, reads `$'...'` and `$"..."` literals as the text they stand for, and
takes `--target-directory DIR` as well as `--target-directory=DIR`. After a `cd` it can't resolve
(`cd -`, `cd $X`), relative targets are judged from the last known directory, so `cd - && cat .env`
blocks. Readers are checked by named path only: `grep -r KEY .` and `git log -p -- .env` pass, and
`git am`, `cherry-pick`, `revert`, `rebase` and `pull` aren't looked into.

Both guards fail closed: hook input they can't parse (malformed, or no `jq` and no working
`python3`) blocks, and so does `git` missing or failing, because then a path can't be placed in
a repo. Outside a git repo there is nothing to guard, so that case is allowed on purpose. The
Bash guard's limits (a command it can't lex, or that is too big) pass and log, except for the
reviewer role, which blocks. A hook that outlasts its timeout isn't a block: Claude Code lets the
command run.

**How the Stop gate decides.** Subagent sessions (`HARNESS_ROLE` set) skip it, and so does a
branch with no changes against `main` outside `.agent/`. Otherwise it runs `verify.sh`, with a
hook timeout of 900 seconds:

- **Exit 78 (no sensors):** there is nothing to fix in code, so it blocks once per session and
  allows the next stop. This never counts toward the loop breaker, and the receipt isn't checked.
- **Any other failure, or a missing receipt:** a blocked stop. The loop breaker counts blocked
  stops in a row per session and ignores the failure text, which can differ on every run. The 3rd
  block is the last, and tells Claude to ask `architect` and report to the user. The next stop is
  allowed. A count that can't be saved also allows the stop, because it couldn't be bounded.
- **Exit 0 with a receipt, or no task:** the stop is allowed and the count resets. The task is
  the one the guard enforces (see above), so blanking `active-task` doesn't skip the receipt.

The counts live in `.agent/state/stop-blocks-<session_id>` and
`.agent/state/sensors-warned-<session_id>`.

`verify.sh` picks `pytest` only when real Python tests exist: a `test_*.py` or `*_test.py` file
under `tests/`, not counting `tests/harness`, which holds this harness's own shell self-test.

In Herdr, `herdr-sub.sh --interactive` waits until the agent has taken the prompt. A prompt that
stalls (nothing starts working within a few seconds) fails the run, closes its tab and says so,
instead of leaving a run that never began.

### `verify.sh` exit codes

| Exit | Meaning |
|---|---|
| 0 | every configured sensor passed |
| 1 | a sensor failed |
| 78 | no sensors configured: a human has to fill in the CONFIG block |

## Harness files are human-owned

The guards block Claude from editing `CLAUDE.md`, rules, hooks, `settings.json` and the other
files directly under `.claude/`, agents, skills, slash commands, `verify.sh`, `herdr-sub.sh`,
`harness-init.sh`, `contract-approve.sh` and the self-test in `tests/harness/`. Claude proposes
a change and you apply it. This is deliberate: an agent that can rewrite its own sensors has no
sensors.

**Maintainer mode** is only for developing this boilerplate itself. Start Claude with
`HARNESS_MAINTAINER=1 claude` from inside a task worktree, and the guard allows harness edits.
Secrets, `.git` internals, whole repositories, `.claude/settings.local.json`, main-branch isolation,
contract scope and contract approval stay enforced.
With no project sensors configured, `verify.sh` then runs `tests/harness/run.sh` instead. Don't
use maintainer mode in a normal project.

## The self-test

`tests/harness/run.sh` checks the hooks against a throwaway git repo and ends with a pass/fail
count. It takes about 90 seconds, so run it before you push rather than after every edit. Cases
live in `tests/harness/cases-<topic>.sh`, which `run.sh` sources just before its summary line.

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
