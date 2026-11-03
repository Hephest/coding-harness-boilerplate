---
description: Start a bounded task - write the contract, create the worktree, mark it active
argument-hint: <task-id> <one-line goal>
---

Start task `$ARGUMENTS`.

1. Use `Explore` to find the files this goal touches. Do not read them yourself.
2. Copy `.agent/contracts/TEMPLATE.md` to `.agent/contracts/<task-id>.md` and fill it in.
   Max 5 target files. If it needs more, propose a split and stop.
3. Ask `architect` to check the contract. Apply its changes if they're reasonable.
4. Show me the contract and wait for my yes.
5. After my yes:
   - `git worktree add -b task/<task-id> .worktrees/<task-id> HEAD`
   - write `<task-id>` to `.worktrees/<task-id>/.agent/state/active-task`
   - copy the contract into the worktree's `.agent/contracts/`
   - tell me to continue the session from `.worktrees/<task-id>`
