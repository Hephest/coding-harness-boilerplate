---
description: Close the active task - verify, commit, cold review, receipt, commit the receipt
---

Finish the active task (id in `.agent/state/active-task`).

1. Send `scripts/verify.sh` to `test-runner`. If FAIL, fix (max 3 attempts), then re-run.
2. Commit the work on the task branch with message `<task-id>: <goal>`. `reviewer` reads
   `git diff main...HEAD`, which shows commits only: uncommitted work looks like an empty diff.
3. Send only the task id to `reviewer`. If REJECT, fix the listed problems as a new commit (don't
   amend) and go back to step 1.
4. Write `.agent/receipts/<task-id>.md` from the template, using real numbers from steps 1–3 and
   the short SHA of the last reviewed commit.
5. If anything failed along the way, add a line to `.agent/lessons.md` and propose the
   infrastructure fix (rule, test, script or hook). Don't edit hooks or settings yourself.
6. Commit the receipt (and lessons) with message `<task-id>: receipt`.
7. Don't push or merge. Tell me the branch name and the receipt status.
