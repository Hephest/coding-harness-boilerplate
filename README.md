# Coding Harness Boilerplate

**A drop-in harness that makes Claude Code work in bounded, verified, reviewable tasks.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Harness version](https://img.shields.io/badge/harness-v0.1.0-informational.svg)](CHANGELOG.md)

Copy it into a new or existing repo, fill in a few placeholders, and Claude Code starts working
the way a careful engineer does. It writes down the scope first, works on a branch, runs the
tests before saying "done", gets a second opinion, and leaves a receipt.

---

## Why

Left alone, coding agents tend to:

- **drift out of scope**: "while I was there, I also refactored…"
- **claim success without evidence**: "all tests pass" when no tests ran
- **loop**: they retry the same failing fix until the context runs out
- **touch what they shouldn't**: secrets, generated files, the main branch

Writing "please don't" in a prompt helps a little. This boilerplate rests on two ideas instead:

1. **The harness is the machine.** Every rule that must always hold is a hook, a script or a
   permission, not a sentence the model may forget 40 messages later.
2. **A model team.** Cheap models search and run tests, a mid-tier model builds and reviews, and
   the most expensive model only plans and judges. You get better results and pay less.

## What you get

| Piece | Where | What it does |
|---|---|---|
| **Guard (Edit/Write)** | `.claude/hooks/guard-write.sh` | Blocks writes to secrets, to `main`, to harness files and danger zones, and to anything outside the contract of the current task (the id in a `task/<id>` branch name, else `.agent/state/active-task`). Also blocks all work on a contract you haven't approved, or that changed since you did |
| **Guard (Bash)** | `.claude/hooks/guard-bash.sh` | Applies the same write policy to shell commands (`sed -i`, `>`, `cp`, `tee`…), blocks shell reads of secrets and the denied git forms, and limits the `reviewer` to read-only commands. Best effort, see the limits below |
| **Contract approval** | `scripts/contract-approve.sh` | You run it to approve a contract. The guard refuses the agent the usual ways of running it (best effort, see the limits below). Any edit to the contract needs a fresh approval |
| **Fast sensor** | `.claude/hooks/post-edit-check.sh` | Checks each file right after Claude edits it: syntax always, plus format and lint where ruff, prettier or eslint is installed |
| **Stop gate** | `.claude/hooks/stop-gate.sh` | Claude can't end its turn while `verify.sh` fails or the task has no receipt, with a loop breaker after 3 blocked stops in a row |
| **Definition of done** | `scripts/verify.sh` | One script for typecheck, lint and tests. Exit 0 is the only proof that counts |
| **Agent team** | `.claude/agents/` | `Explore` (haiku), `test-runner` (haiku), `reviewer` (sonnet, read-only commands only), `architect` (opus) |
| **Slash commands** | `.claude/commands/` | `/task <id> <goal>` writes the contract and, once you've approved it, sets up the worktree; `/finish` verifies, commits on the task branch, gets a cold review and writes the receipt |
| **Skills** | `.claude/skills/` | `debug`, `refactor`, `code-review`, `release`, `herdr-subagents` |
| **Policy** | `.claude/settings.json` | Allow and deny lists: no `curl`, `git push`, `git reset` or `rm` for the agent, no reading `.env` |
| **Task state** | `.agent/` | Contracts, receipts and a lessons log on disk, so they survive a crashed session |
| **Docs on demand** | `docs/` | Architecture, ADRs and runbooks that Claude opens only when it needs them |
| **Self-test** | `tests/harness/run.sh` | Proves the hooks still block what they should |
| **Installer** | `scripts/harness-init.sh` | Copies the harness into another project without overwriting anything (see Quickstart) |

The full file map and design notes are in [`docs/harness.md`](docs/harness.md).

## How a task flows

```mermaid
flowchart LR
    A["/task id goal"] --> B["Contract<br/>≤5 files, criteria"]
    B --> Y["You approve<br/>contract-approve.sh"]
    Y --> C["Worktree<br/>task/id branch"]
    C --> D["Build"]
    D -- every write --> G{{"Guard + fast sensor"}}
    G --> D
    D --> S{{"Stop gate<br/>verify.sh"}}
    S -- fails --> D
    S -- passes --> F["/finish<br/>verify.sh"]
    F -- fails --> D
    F -- passes --> K["Commit<br/>task branch"]
    K --> R["Cold review<br/>reviewer agent"]
    R -- REJECT --> D
    R -- ACCEPT --> P["Receipt + commit<br/>(you push)"]
```

`/finish` commits before the review so the reviewer can see the work in `git diff main...HEAD`.
Review fixes are new commits, and the receipt records the real SHA.

Nothing is pushed or merged for you. The agent prepares the work and you publish it. The agent
is blocked from approving its own contract by the usual routes: you do that between the contract
and the worktree.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)
- `git` (worktrees need a first commit), `bash` (3.2+ works, so the macOS default is fine)
- `jq` **or** `python3`, used by the hooks to read Claude Code's JSON input
- Optional: [Herdr](https://herdr.dev) to run subagents in hidden terminal tabs, and `shellcheck`
  for a stricter self-test

## Quickstart

### 1. Get the files

Pick one:

```bash
# A. New repo on GitHub: click "Use this template" on the repo page, then clone your copy.

# B. New local project without git history
npx degit Hephest/coding-harness-boilerplate my-app && cd my-app

# C. Existing project: copy the harness in (check for clashes with your CLAUDE.md / .gitignore)
git clone --depth 1 https://github.com/Hephest/coding-harness-boilerplate /tmp/harness
cp -R /tmp/harness/{.claude,.agent,scripts,tests,docs,CLAUDE.md} .
cat /tmp/harness/.gitignore >> .gitignore
```

Option C also has a script. It does the same copy without overwriting anything (existing files are
skipped and reported, `.gitignore` gets only the missing lines, and no task history comes along):

```bash
/tmp/harness/scripts/harness-init.sh --name "My App" --stack "Python, FastAPI, Postgres" --dry-run ./my-app
/tmp/harness/scripts/harness-init.sh --name "My App" --stack "Python, FastAPI, Postgres" ./my-app
```

It works on an empty directory too. It runs no git commands and makes no network calls. It prints
the sensors it detected and the steps left for you (step 2 below, then the first commit). If your
project already has a `CLAUDE.md`, it keeps yours; merge the two by hand.

### 2. Make it yours

1. **`CLAUDE.md`**: fill in the `<placeholders>` (project, stack, run command) and adjust the
   repo map. Keep it under 150 lines.
2. **`scripts/verify.sh`**: set `TYPECHECK_CMD`, `LINT_CMD` and `TEST_CMD` in the CONFIG block.
   It auto-detects common setups (npm `lint`/`test` scripts, `tsc`, ruff, pyright, pytest), but
   explicit commands are clearer. If it finds no sensors at all, it exits `78` ("no sensors
   configured") on purpose, because with no sensors nothing is verified.
3. **`.claude/protected-paths`**: list your danger zones (auth, billing, migrations, infra…).
4. **`README.md`, `CHANGELOG.md`, `LICENSE` and `SECURITY.md`**: these describe the boilerplate.
   Replace them with your project's own. `.claude/HARNESS_VERSION` keeps a record of which
   harness release you started from.

> **You edit the harness files, Claude doesn't.** The guard blocks Claude from changing the root
> `CLAUDE.md`, hooks, `settings.json`, `protected-paths`, rules, `verify.sh`, `herdr-sub.sh`,
> `harness-init.sh`, `contract-approve.sh`, agents, skills, slash commands and the self-test,
> with the Edit/Write tools and with shell commands. It can propose a change, and you apply it.
> An agent that can rewrite its own sensors has no sensors.

### 3. First commit, first task

```bash
git init -b main          # skip if the repo already exists
git add -A && git commit -m "chore: add coding harness"
claude
```

Then, inside Claude Code:

```
/task add-health-endpoint Add GET /health that returns {"ok": true}
```

Claude writes the contract and asks the `architect` to check it, then shows it to you. After
your "yes", you approve it yourself, because Claude is blocked from doing so:

```
! scripts/contract-approve.sh add-health-endpoint
```

If Claude Code refuses that, run `scripts/contract-approve.sh add-health-endpoint` from the repo in
a plain terminal. Then tell Claude. It creates `.worktrees/add-health-endpoint` and tells you to
continue from there. The approval is stored under the git common dir, so it works before the
worktree exists and covers every worktree.

## A day with the harness

```text
you     /task fix-login-redirect Users land on /home instead of ?next= after login
claude  Contract written: 2 target files, 3 acceptance criteria. OK to start?
you     yes
claude  Please approve it: ! scripts/contract-approve.sh fix-login-redirect
you     ! scripts/contract-approve.sh fix-login-redirect
        Approved 'fix-login-redirect' (sha256 …).
claude  Worktree ready. Continue from .worktrees/fix-login-redirect
        … edits src/routes/login.ts …
guard   BLOCKED: 'src/routes/redirect.ts' is outside the contract for 'fix-login-redirect'.
claude  That file needs to change too. I'll add it to the contract. That voids your approval, so
        please run the approve command again.
you     ! scripts/contract-approve.sh fix-login-redirect
        … tries to stop …
gate    NOT DONE (blocked stop 1/3): scripts/verify.sh failed (exit 1). Last lines: …
        … fixes the test …
you     /finish
claude  verify: PASS · committed on task/fix-login-redirect
        reviewer: ACCEPT · receipt: .agent/receipts/fix-login-redirect.md
        Not pushed.
```

Each message from the guard or the gate tells Claude exactly what to do next. If the contract
changes after you approved it, every write is blocked until you approve it again. When something
keeps failing, the gate blocks at most three stops in a row, even if the failure text changes
each time. The third block tells Claude to ask the `architect` and report to you, and the next
stop goes through, so a stuck task doesn't burn tokens.

## Concepts

| Concept | In one paragraph |
|---|---|
| **Contract** | `.agent/contracts/<id>.md`: the goal, **at most 5 target files** (globs allowed), acceptance criteria that map to tests, what's out of scope, and an attempt ceiling. If a task needs more than 5 files, split it. The guard only allows writes to the listed files. |
| **Approval** | You run `scripts/contract-approve.sh <id>`, which stores a hash of the contract under the git common dir. The guard blocks work on a task whose contract has no approval or has changed since. The guard and `settings.json` refuse the agent the usual ways of running the script, and it can still edit the contract (`.agent/` stays writable) but must ask you to approve again. On a `task/<id>` branch the id in the branch name decides which contract is approved and enforced; `.agent/state/active-task` is ignored there. |
| **Worktree** | Each task gets its own checkout on a `task/<id>` branch under `.worktrees/`. `main` stays clean, and you can throw a failed attempt away with one command. |
| **Guard** | PreToolUse hooks that run before every Edit/Write/NotebookEdit and every Bash command. Exit 2 blocks it and tells Claude why. |
| **Sensors** | Tools that measure "done": the fast check per edit, and the full `verify.sh` at the Stop gate. |
| **Stop gate & loop breaker** | Claude can't finish while `verify.sh` fails or the task has no receipt. The gate blocks at most 3 stops in a row, whatever the failure text says, and then lets Claude stop so it can escalate. "No sensors configured" (`verify.sh` exit 78) blocks once per session, then allows the stop, and never counts toward the loop breaker, so a fresh project doesn't trap you. |
| **Receipt** | `.agent/receipts/<id>.md`: a 15-second audit covering status, verify result, reviewer verdict, files changed and attempts used. |
| **Lessons → infrastructure** | Every failure gets one line in `.agent/lessons.md` **and** a permanent fix: a rule, test fixture, script or hook. A fix that lives only in a chat is lost. |
| **Danger zones** | Paths in `.claude/protected-paths`. They can only be edited when the active contract names them specifically. Give each one a local `CLAUDE.md` ([template](docs/templates/MODULE_CLAUDE.md)). |
| **Model routing** | Start the session on the model you build with (`claude --model sonnet`), or `/model opusplan` to plan on Opus and build on Sonnet. Subagents bring their own model. Don't switch mid-task, because the cache resets. |

## Customizing

- **Add a rule for a path:** (you do this) copy `.claude/rules/auth.md`. The `paths:` frontmatter makes Claude
  load it only when it works on matching files.
- **Add a sensor:** add a command to the CONFIG block in `scripts/verify.sh`, or add a
  path-scoped sensor to `SCOPED_SENSORS` so it runs only when those files change.
- **Add a danger zone:** add a glob to `.claude/protected-paths` and a local `CLAUDE.md` in
  that folder.
- **Add an agent or skill:** (you do this, the guard blocks Claude from it) drop a Markdown file into `.claude/agents/` or
  `.claude/skills/<name>/SKILL.md`.
- **Safe to delete:** `.claude/rules/auth.md` and the example rows in `.agent/lessons.md` (both
  are examples), and the Herdr skill and `scripts/herdr-sub.sh` if you don't use Herdr.

## Optional: Herdr

[Herdr](https://herdr.dev) is a terminal multiplexer for coding agents. If you start `claude`
inside a Herdr pane (`HERDR_ENV=1`), the `herdr-subagents` skill runs every subagent through
`scripts/herdr-sub.sh` in its own hidden tab. Your pane stays clean: no test logs and no file
dumps, only the subagent's short report.

```bash
herdr integration install claude   # once, for accurate agent states
```

Without Herdr, the same agents run through Claude Code's built-in Agent tool. Nothing else
changes.

## Security model and limitations

These are **guardrails, not a sandbox**. They stop an agent that is following its instructions
and keep honest mistakes small. They do not stop a determined adversary.

What v0.2 enforces:

- **Writes.** The Edit/Write/NotebookEdit guard and the Bash guard share one write policy. A shell
  `sed -i`, `>`, `cp` or `tee` is judged like an Edit.
- **Approval.** A human approves the contract with `scripts/contract-approve.sh`. The guard and
  `settings.json` refuse the agent the known ways of running it (best effort, see below), and a
  changed contract blocks all work until you approve it again.
- **One task id.** On a `task/<id>` branch with a contract or an approval record, `<id>` alone
  sets approval, scope and the Stop gate's receipt check. Elsewhere `.agent/state/active-task`
  decides, and its contract has to be approved.
- **Secrets.** `settings.json` denies the Read tool on `.env*`, `secrets/`, `*.pem` and `*.key`,
  and the Bash guard blocks shell reads of the same paths in the commands it knows.
- **Behaviour-shaping files.** The root `CLAUDE.md` and `.claude/rules/` are harness files now,
  like the hooks.
- **Git.** `git add -f` is caught in any position, and the guard fails closed when `git` is
  missing or broken, instead of letting the write through.

Known gaps in v0.2:

- The Bash guard is best effort. It lexes the command and checks the commands it knows. Interpreter
  one-liners (`python -c`, `node -e`), targets built from a variable or a glob, and commands it
  can't lex pass and are logged to `.agent/state/guard-bash.log`. A command that outlasts the
  hook's timeout runs unchecked.
- Approval fixes the contract's content, not your judgement. Read it before you approve. It is
  also best effort: an agent that copies the script and `_lib.sh` elsewhere, or writes the
  approval record with a tool the guard doesn't know, gets past it.
- Work on a branch that isn't named `task/<id>`, with no active task, is judged only by the
  generic rules. Renaming a task branch (`git branch -m`) drops that task's enforcement.
- `grep -r` can read a secret by recursion, because only named paths are checked. `git log -p`,
  `git blame` and `git archive` aren't checked as readers. `git am`, `cherry-pick`, `revert`,
  `rebase` and `pull` can land changes in harness files.
- Not everything is guarded. `.agent/` stays writable on purpose (contracts, receipts and
  `.agent/lessons.md`, which `/finish` appends to), and so does a module's own `CLAUDE.md`.
- Reading a secret through an interpreter, or any program the guard doesn't know, isn't blocked.

The guard itself fails closed: if it can't parse its input (malformed, or no jq and no working
python3), it blocks the write. It checks the real path behind any symlink, blocks a detached
HEAD like `main`, and blocks `.env`, `.env.*`, `.npmrc`, `.netrc`, `id_rsa*`, `*.pem`, `*.key`,
`*.p12` and `*.pfx` at any depth, as well as a top-level `secrets/` and `.git` internals.

`git push`, `git reset` and `rm` are denied to the agent in every permission mode, so they never
depend on a prompt being answered. When one is needed, Claude gives you the command and you run
it with the `!` prefix, for example `! git push origin main`. To let the agent do it with a
prompt instead, move the rule from `deny` to `ask` in `.claude/settings.json`, but only if you
always watch your sessions.

Run Claude Code with its own permission prompts on, and review diffs before you merge. See
[SECURITY.md](SECURITY.md) for the threat model and how to report a problem, and
[docs/harness.md](docs/harness.md) for how each hook works.

## Versioning and upgrading

The harness uses [Semantic Versioning](https://semver.org). The current version is in
`.claude/HARNESS_VERSION`, and every change is listed in [CHANGELOG.md](CHANGELOG.md).

- **Major:** something you must act on, such as a changed contract format, a renamed script or
  command, or new hook wiring.
- **Minor:** a new opt-in agent, skill, rule or sensor.
- **Patch:** fixes and docs.

To upgrade a project that started from an older version:

```bash
cat .claude/HARNESS_VERSION                     # e.g. 0.1.0
# In a clone of this repo, see what changed in the harness files since then:
git diff v0.1.0 v0.2.0 -- .claude scripts tests/harness CLAUDE.md .agent/contracts/TEMPLATE.md .agent/receipts/TEMPLATE.md
```

Read the "Upgrading" notes in the [CHANGELOG](CHANGELOG.md) for each version in between, apply
the diff to your project, and update `.claude/HARNESS_VERSION`. Going from 0.1 to 0.2 adds
`guard-bash.sh` and `contract-approve.sh`, and changes the hook wiring and deny list in
`.claude/settings.json`, so merge that file by hand instead of overwriting yours. Contracts that
are already active need one approval each. The CHANGELOG's Upgrading steps list every file to take.

## Credits

The core ideas (*the harness is the machine*, *the model team* and the seven invariants) come
from these posts:

- https://x.com/swadeshkumar_/status/2117564218803392849
- https://x.com/damkina7/status/2115794667706957858
- https://x.com/0xMfox/status/2115825484529311955

The Herdr integration, maintainer mode, the self-test and the packaging are this project's own
additions. Not affiliated with Anthropic or Herdr.

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to work
on the harness with the harness, including maintainer mode.

## License

[MIT](LICENSE)
