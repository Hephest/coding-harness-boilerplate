# Security policy

## What this harness is, and isn't

The hooks and permissions here are **guardrails for a cooperative agent, not a sandbox**. They
keep Claude Code inside the task you agreed on and make honest mistakes cheap. They are not
designed to contain a malicious or prompt-injected agent. Use them **together with** Claude
Code's permission prompts, git review before merging, and least-privilege credentials.

## Threat model

The Edit/Write guard is exact: it sees the path the tool will touch. The Bash guard is
**best effort**: it lexes the command, looks at the arguments of commands it knows, and passes
what it can't resolve (see Known limitations).

| In scope (the harness should stop it) | Out of scope (use other controls) |
|---|---|
| Claude editing secrets through Edit/Write: `.env`, `.env.*`, `.npmrc`, `.netrc`, `id_rsa*`, `*.pem`, `*.key`, `*.p12`, `*.pfx` at any depth, top-level `secrets/` | Shell commands the Bash guard doesn't know, or can't resolve (interpreter one-liners, variables, globs) |
| The same secrets through a known shell command: redirects, `tee`, `cp`, `mv`, `sed -i`, `cat`, `grep` and similar. Writing `.env.example` blocks too; reading it doesn't | A user who disables hooks or runs with `--dangerously-skip-permissions` |
| Claude editing on `main` or a detached HEAD instead of a task worktree, also by shell redirect or `sed -i` | Malicious code in your dependencies or MCP servers |
| Claude editing files outside the active contract or in a danger zone, also through a symlink or a known shell command | Compromised machine or Claude Code installation |
| Claude changing its hooks, `settings.json`, any file directly under `.claude/`, `CLAUDE.md`, `.claude/rules/`, agents, skills, slash commands, `protected-paths`, `verify.sh`, `herdr-sub.sh`, `harness-init.sh`, `contract-approve.sh` or the self-test in `tests/harness/`, by Edit, Write, NotebookEdit or a known shell command | |
| Claude editing `.git` internals, or writing to a whole repository at once: `git restore .`, `find . -delete`, a bare `tar -x` or `unzip` at the repo root all block | |
| Claude widening its own scope: a contract on a `task/<id>` branch has to be approved by a human (`scripts/contract-approve.sh <id>`), and an edit to it voids the approval | |
| Claude approving a contract itself: the guard and `settings.json` both refuse `contract-approve.sh`, also in maintainer mode | |
| `git push`, `git reset` and `git add -f` in any flag position (`git add -A -f`, `--force`, a shortened `--forc`): blocked by the Bash guard, and by `settings.json` deny rules for the plain forms. Also `git config` keys that run code or skip hooks (`core.hooksPath`, `alias.*`, `core.fsmonitor`, `include.path`), by the Bash guard only | |
| `rm`, `curl` and `wget`: blocked by `settings.json` deny rules alone. The Bash guard doesn't block them (it does check what `rm` would delete against the write policy), so they depend on Claude Code applying the deny rules | |
| The reviewer agent doing anything but `scripts/verify.sh` and `git diff|log|show|status`, piped into `head`, `tail`, `grep` or `wc`. Anything it can't check blocks | |
| A write or command going through unchecked because the hook input can't be parsed, or because `git` is missing or failing (both guards fail closed) | |
| Claude declaring "done" while `verify.sh` fails, for up to 3 blocked stops in a row (see limitation 11) | |

## Known limitations (v0.2)

1. **The Bash guard inspects known commands only.** Interpreter one-liners (`python -c`,
   `node -e`), `find -exec sh -c` with placeholders, targets held in variables or globs, and
   anything else it can't resolve pass, and are logged to `.agent/state/guard-bash.log`. A shell
   string inside a shell string is looked at one level deep. Read that log if you suspect
   something got through.
2. **Lexer limits pass and log.** A command past a limit (word length, path length, nesting
   depth, number of checked targets, or the 15-second clock) is treated as one the guard can't
   lex. It passes and is logged. The one exception is the reviewer role, which fails closed.
3. **Some git commands aren't blocked.** `git commit --no-verify`, `git update-ref`,
   `git stash`, `git clean` and `git merge` pass. Review what lands on your branch.
4. **No task, no contract enforcement.** On a branch not named `task/<id>` with no active task
   (`.agent/state/active-task`), neither the approval check nor the scope check applies. Only
   the protected paths, the harness files and the `main` rule do. On a `task/<id>` branch the
   approval is checked, but scope still needs an active task.
5. **Approval depends on `!` commands, which Claude Code doesn't document.** It isn't stated
   whether `!` commands are subject to deny rules. The deny on `contract-approve.sh` in
   `settings.json` may refuse your own `! scripts/contract-approve.sh <id>`. If it does, run it
   in a plain terminal. The approval itself (a hash under `.git/`) is only as strong as your
   habit of reading the contract before you approve it.
6. **A PreToolUse timeout doesn't block.** A hook that runs past its timeout fails open: the
   command runs unchecked and unlogged. The Bash guard works against this with hard limits (see
   2) and a 30-second timeout, but it is a limit of Claude Code, not something the harness can fix.
7. **The reviewer's Bash allowlist is enforced by the guard.** The reviewer is recognized by
   the hook's `agent_type` or by `HARNESS_ROLE`. If neither reaches the hook, the guard sees an
   ordinary session.
8. **Not every behaviour-shaping file is guarded.** `.agent/lessons.md` and a module's own
   `CLAUDE.md` stay writable: `/finish` appends to the lessons file.
9. **Self-written contracts are still possible before approval.** `.agent/` is writable so
   `/task` can create a contract. The approval step makes a changed contract visible; it
   doesn't stop the agent writing one.
10. **`ask` rules only suit sessions you are watching.** A prompt is only as good as whoever
    answers it. While testing this harness with unattended background sessions, `ask` prompts
    for `rm` were resolved with nobody answering them, and the cause wasn't found. So
    `git push`, `git reset` and `rm` are `deny` rules, which hold in every permission mode and
    show no dialog. Anything you add that must never run unattended belongs in `deny` too.
11. **The Stop gate is bounded on purpose.** It blocks at most 3 stops in a row, then allows
    the next one so a session can't be trapped. `verify.sh` exit 78 (no sensors) blocks once per
    session, then allows the stop. A stop that gets through this way isn't verified, so check
    the receipt before you merge.

## Scope changes in v0.2

These go further than the 0.1 contracts, so they can surprise you:

- **Everything directly under `.claude/` is a harness file**, not only the listed ones. Its
  subdirectories are not, except `hooks`, `agents`, `skills`, `commands` and `rules`.
- **Repo roots are protected.** A write that takes a whole repository (`git restore .`,
  `find . -delete`, a bare `tar -x` or `unzip` at the root) blocks,
  because it would take `.git` and the secrets with it. Name the paths inside instead.
- **`.env.example` is write-protected.** Writing it blocks, because it matches `.env.*`.
  Reading it (and `.env.sample`, `.env.template`) is fine. Edit it yourself.

## Reporting a vulnerability

If you find a way for the agent to get around a guardrail that this document says is
**in scope**, please report it privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
("Report a vulnerability" under the repository's **Security** tab). Please don't open a public
issue. Include the harness version (`.claude/HARNESS_VERSION`), your OS, and the steps or hook
input that reproduce it.

Gaps already listed under "Known limitations" can be discussed in public issues.

## Supported versions

Only the latest release gets fixes while the project is in 0.x.
