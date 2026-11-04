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
| The same secrets through a known shell command: redirects, `tee`, `cp`, `mv`, `sed -i`, `cat`, `grep` and similar, also behind `sudo`, `doas`, `setsid`, `stdbuf`, `ionice`, `env`, `nice`, `timeout` or `xargs`, and when the path is written as `$'...'` or `$"..."`. A relative path after a `cd` the guard can't resolve (`cd -`, `cd $X`) is judged from the last known directory, so `cd - && cat .env` blocks. Writing `.env.example` blocks too; reading it doesn't | A user who disables hooks or runs with `--dangerously-skip-permissions` |
| Claude editing on `main` or a detached HEAD instead of a task worktree, also by shell redirect or `sed -i` | Malicious code in your dependencies or MCP servers |
| Claude editing files outside the contract of its task or in a danger zone, also through a symlink or a known shell command. The task is the one id from the branch name on `task/<id>` (see limitation 4) | Compromised machine or Claude Code installation |
| Claude changing its hooks, `settings.json`, any file directly under `.claude/`, `CLAUDE.md`, `.claude/rules/`, agents, skills, slash commands, `protected-paths`, `verify.sh`, `herdr-sub.sh`, `harness-init.sh`, `contract-approve.sh` or the self-test in `tests/harness/`, by Edit, Write, NotebookEdit or a known shell command | |
| Claude editing `.git` internals, or writing to a whole repository at once: `git restore .`, `find . -delete`, a bare `tar -x` or `unzip` at the repo root all block | |
| Claude widening its own scope by editing a contract: work on a task needs a contract that a human approved (`scripts/contract-approve.sh <id>`), and an edit to it voids the approval | |
| Claude approving a contract itself, by the known routes: the guard and `settings.json` refuse `contract-approve.sh` run directly, through `sh` or `bash`, by a glob that matches it, or fed to `bash -s` on stdin, also in maintainer mode. **Best effort only**: see limitation 12 | An agent that copies the script and `_lib.sh` elsewhere, or writes the approval record with a tool the guard doesn't know |
| `git push`, `git reset` and `git add -f` in any flag position (`git add -A -f`, `--force`, a shortened `--forc`): blocked by the Bash guard, and by `settings.json` deny rules for the plain forms. Also `git config` keys that run code or skip hooks, by the Bash guard only and not in maintainer mode: `core` (as a whole section), `core.hooksPath`, `core.fsmonitor`, `core.sshCommand`, `core.pager`, `core.editor`, `alias.*`, `include.path`, `includeIf.*`, `diff.external`, `sequence.editor`, `filter.*`, `credential.*` and `gpg.*` | |
| `rm`, `curl` and `wget`: blocked by `settings.json` deny rules alone. The Bash guard doesn't block them (it does check what `rm` would delete against the write policy), so they depend on Claude Code applying the deny rules | |
| The reviewer agent doing anything but `scripts/verify.sh` and `git diff|log|show|status`, piped into `head`, `tail`, `grep` or `wc`. Anything it can't check blocks | |
| A write or command going through unchecked because the hook input can't be parsed, or because `git` is missing or failing (both guards fail closed) | |
| Claude declaring "done" while `verify.sh` fails, for up to 3 blocked stops in a row (see limitation 11) | |

## Known limitations (v0.2)

1. **The Bash guard inspects known commands only.** Interpreter one-liners (`python -c`,
   `node -e`), `find -exec sh -c` with placeholders, targets held in variables or globs, and
   anything else it can't resolve pass, and are logged to `.agent/state/guard-bash.log`. A shell
   string inside a shell string is looked at one level deep. After a `cd` it can't resolve, a
   relative target is judged from the last known directory, which may not be where the command
   really runs. Read that log if you suspect something got through.
2. **Lexer limits pass and log.** A command past a limit (word length, path length, nesting
   depth, number of checked targets, or the 15-second clock) is treated as one the guard can't
   lex. It passes and is logged. The one exception is the reviewer role, which fails closed.
3. **Some git commands aren't blocked.** `git commit --no-verify`, `git update-ref`,
   `git stash`, `git clean` and `git merge` pass. Review what lands on your branch. See
   limitation 14 for the commands that can bring in changes to harness files.
4. **One task id, and none without a task.** On a `task/<id>` branch that has a contract or an
   approval record for `<id>`, that id alone decides the approval check, the scope check and the
   Stop gate's receipt check. `.agent/state/active-task` is ignored there, because the agent can
   rewrite it. On any other branch, and on a task branch with neither a contract nor a record,
   `active-task` decides, and its contract has to be approved too. With neither a task branch nor
   an active task, only the protected paths, the harness files and the `main` rule apply.
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
   doesn't stop the agent writing one. Approval stops it being used unseen, nothing more.
10. **`ask` rules only suit sessions you are watching.** A prompt is only as good as whoever
    answers it. While testing this harness with unattended background sessions, `ask` prompts
    for `rm` were resolved with nobody answering them, and the cause wasn't found. So
    `git push`, `git reset` and `rm` are `deny` rules, which hold in every permission mode and
    show no dialog. Anything you add that must never run unattended belongs in `deny` too.
11. **The Stop gate is bounded on purpose.** It blocks at most 3 stops in a row, then allows
    the next one so a session can't be trapped. `verify.sh` exit 78 (no sensors) blocks once per
    session, then allows the stop. A stop that gets through this way isn't verified, so check
    the receipt before you merge.
12. **Self-approval is best effort.** The guard and `settings.json` refuse the known routes:
    running `contract-approve.sh` directly, through `sh` or `bash`, by a glob that matches it, and
    `bash -s` reading it from stdin. They don't stop an agent that copies the script and
    `.claude/hooks/_lib.sh` somewhere else and runs the copy (`cp` of either passes the guard), or
    that writes the record under `.git/harness/approved/` with a tool the guard doesn't know, or
    with a path it can't resolve (`$(git rev-parse --git-common-dir)/...` passes). The approval is
    a guardrail for a cooperative agent: it makes an unseen contract change visible, and it isn't
    proof that a human looked. Read the diff of a contract before you rely on it.
13. **Renaming a task branch drops its enforcement.** `git branch -m` and `-M` pass the guard.
    Once the branch isn't called `task/<id>`, the task id comes from `active-task` again, and with
    none set the approval and scope checks stop applying (limitation 4).
14. **Some commands can land changes in harness files.** `git am`, `git cherry-pick`, `git revert`,
    `git rebase`, `git pull` and `git apply` pass the guard whatever they write, because it doesn't
    look inside a patch or a commit. Named-path forms such as `git checkout <rev> -- <file>` and
    `git restore --source` are checked. Review the diff after any of them.
15. **Readers are checked by named path only.** `grep -r` and `rg` on a directory (`grep -r KEY .`)
    can read a secret by recursion, and a glob such as `grep KEY .env*` is unresolved. `git log -p`,
    `git blame` and `git archive` aren't checked as readers, so `git log -p -- .env` and
    `git archive HEAD .env` pass. `git show HEAD:.env` and `git diff HEAD -- .env` are checked.
    Keep secrets out of the repository and out of its history.

## Scope changes in v0.2

These go further than the 0.1 contracts, so they can surprise you:

- **One task id.** On a `task/<id>` branch with a contract or an approval record, `<id>` alone
  sets the approval, the scope and the Stop gate's receipt check; `active-task` is ignored there.
  Elsewhere `active-task` decides, and its contract has to be approved.
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
