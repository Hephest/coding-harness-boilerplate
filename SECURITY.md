# Security policy

## What this harness is, and isn't

The hooks and permissions here are **guardrails for a cooperative agent, not a sandbox**. They
keep Claude Code inside the task you agreed on and make honest mistakes cheap. They are not
designed to contain a malicious or prompt-injected agent. Use them **together with** Claude
Code's permission prompts, git review before merging, and least-privilege credentials.

## Threat model

| In scope (the harness should stop it) | Out of scope (use other controls) |
|---|---|
| Claude editing secrets (`.env`, keys, `secrets/`) through Edit/Write | Arbitrary shell commands that write files or read secrets |
| Claude editing on `main` instead of a task worktree | A user who disables hooks or runs with `--dangerously-skip-permissions` |
| Claude editing files outside the active contract or in a danger zone | Malicious code in your dependencies or MCP servers |
| Claude changing its hooks, `settings.json`, agents, skills, `protected-paths`, `verify.sh` or `herdr-sub.sh` | Compromised machine or Claude Code installation |
| Claude declaring "done" while `verify.sh` fails | |

## Known limitations (v0.1)

These are tracked for v0.2:

1. **Shell writes bypass the guard.** The guard runs on Edit/Write/MultiEdit only, so
   `sed -i`, `tee` or `echo >` through the Bash tool are not checked.
2. **Self-written contracts.** `.agent/` is writable so `/task` can create a contract, which
   means the agent could also widen its own scope. The human "yes" before a task starts is a
   convention, not an enforcement.
3. **Reading secrets via the shell.** `settings.json` denies the Read tool on `.env*`,
   `secrets/**`, `*.pem` and `*.key`, but not `cat .env` through Bash.
4. **`git add -f`** can stage an ignored secret. Review what you commit.
5. **The reviewer agent has unrestricted Bash** so it can run `verify.sh`.
6. **Not every behaviour-shaping file is guarded.** `CLAUDE.md`, `.claude/rules/`,
   `.claude/commands/`, `tests/harness/` and `.agent/lessons.md` stay writable through
   Edit/Write, and `NotebookEdit` isn't matched by the guard at all.

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
