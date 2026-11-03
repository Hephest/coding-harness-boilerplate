# Lessons → Infrastructure

Every failure gets one line here and one permanent fix. A fix that lives only in a chat is lost.

The rows marked *example* show the format. They are not real failures: replace them with your own.

| Date | Failure | Class | Fix (where it lives now) |
|------|---------|-------|--------------------------|
| *example* | Agent edited generated file `src/gen/api.ts` | scope creep | Added `src/gen/*` to `.claude/protected-paths` |
| *example* | Missed null session on logout | logic bug | Regression test `tests/auth/test_logout_null_session.py` |

Classes: context gap (→ rule or doc) · tool gap (→ script/CLI) · permission boundary (→ settings.json/hook) · logic bug (→ test fixture) · scope creep (→ contract/guard)
