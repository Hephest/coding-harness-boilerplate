---
paths:
  - "src/auth/**"
---

# Rules for src/auth (example: copy this file per sensitive area)

- Never expose raw tokens, session IDs or passwords in error messages or logs.
- All session mutations go through `SessionStore`; never write session state directly.
- Any change here needs a test in `tests/auth/` that fails without the change.

Enforced by: `scripts/verify.sh` runs the `src/auth` scoped sensors (see SCOPED_SENSORS there).
If you add a rule that a tool can check, add the check there and delete the sentence here.
