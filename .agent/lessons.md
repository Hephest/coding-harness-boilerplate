# Lessons → Infrastructure

Every failure gets one line here and one permanent fix. A fix that lives only in a chat is lost.

The rows marked *example* show the format. They are not real failures: replace them with your own.

| Date | Failure | Class | Fix (where it lives now) |
|------|---------|-------|--------------------------|
| *example* | Agent edited generated file `src/gen/api.ts` | scope creep | Added `src/gen/*` to `.claude/protected-paths` |
| *example* | Missed null session on logout | logic bug | Regression test `tests/auth/test_logout_null_session.py` |
| 2026-11-04 | `skip_arith` exempted `(( ))` without looking inside, so `echo $(( $(git push) > 0 ))` passed unchecked | logic bug | Every lexer exemption ships with a paired row that runs a command inside it: `compare:` rows in `tests/harness/cases-guard-bash.sh` |
| 2026-11-04 | A must-finish row passed with or without the memo it was written to protect | logic bug | Row rebuilt so each level fails and still closes: `must-finish: 24 levels of not quite arithmetic`. Take the guarded code out once to prove a new row can fail |
| 2026-11-05 | The sourced `cases-*.sh` files have no shebang, so shellcheck failed them with SC2148 in CI. It is skipped when not installed, so every local run passed | tool gap | `tests/harness/run.sh` calls shellcheck with `-s bash`. Install shellcheck locally so that row runs before a push |

Classes: context gap (→ rule or doc) · tool gap (→ script/CLI) · permission boundary (→ settings.json/hook) · logic bug (→ test fixture) · scope creep (→ contract/guard)
