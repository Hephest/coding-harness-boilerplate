# Receipt: <task-id>

- **Status:** PASSED | FAILED | ESCALATED
- **Branch / worktree:** task/<task-id> @ <short SHA>
- **Base commit:** <SHA of main at start>
- **Models:** builder <model> · reviewer <model> · architect <used? y/n>
- **Contract:** .agent/contracts/<task-id>.md

## Verified invariants
<!-- One line each, with the evidence that proves it. -->
1. <criterion 1> — `<test name>` passed
2. `scripts/verify.sh` — exit 0 (<runtime>s)
3. Reviewer verdict: ACCEPT

## Trace
- Files changed: <n> (+<added> / -<removed>) — all inside contract targets: yes/no
- Repair attempts used: <n>/3
- Cost (optional, from /usage): <tokens / $>

## Lessons
<!-- Anything that failed and how it became infrastructure. Copy one line to .agent/lessons.md. -->
- none
