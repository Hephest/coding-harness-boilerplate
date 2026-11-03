---
description: Close the active task - verify, cold review, receipt, commit
---

Finish the active task (id in `.agent/state/active-task`).

1. Send `scripts/verify.sh` to `test-runner`. If FAIL, fix (max 3 attempts), then re-run.
2. Send only the task id to `reviewer`. If REJECT, fix the listed problems and go back to step 1.
3. Write `.agent/receipts/<task-id>.md` from the template, using real numbers from steps 1–2.
4. If anything failed along the way, add a line to `.agent/lessons.md` and propose the
   infrastructure fix (rule, test, script or hook). Don't edit hooks or settings yourself.
5. Commit with message `<task-id>: <goal>` and the receipt path in the body.
6. Don't push or merge. Tell me the branch name and the receipt status.
