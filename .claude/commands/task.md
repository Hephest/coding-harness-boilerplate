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
5. After my yes, I approve the contract, not you: the guard blocks you from running
   `scripts/contract-approve.sh`. Tell me to run, with the `!` prefix:
   `! scripts/contract-approve.sh <task-id>`
   If that is refused, tell me to run `scripts/contract-approve.sh <task-id>` from the repo in a
   plain terminal. The approval is stored under the git common dir, so it works from the main
   checkout before the worktree exists and covers every worktree. Then stop and wait until I say
   it's done.
6. After I confirm the approval:
   - `git worktree add -b task/<task-id> .worktrees/<task-id> HEAD`, unless `task/<task-id>`
     already exists (the guard says so when it blocks a hand-made task branch): then skip this
     step, and add the worktree for the existing branch with
     `git worktree add .worktrees/<task-id> task/<task-id>` if it has none
   - write `<task-id>` to `.worktrees/<task-id>/.agent/state/active-task`
   - copy the contract into the worktree's `.agent/contracts/` with `cp`, unchanged: a changed
     byte voids the approval
   - tell me to continue the session from `.worktrees/<task-id>`

If the contract needs an edit after approval (even a typo), it needs a fresh approval. Say so,
stop, and ask me to run the approve command again. Don't try to work around the block.
