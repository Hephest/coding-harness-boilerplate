---
name: code-review
description: Code review checklist for a diff or pull request. Use when asked to review changes, before calling a task done, or when the reviewer subagent needs the full checklist.
---

# Code review checklist

Review the diff (`git diff main...HEAD`) against its contract. Report problems only, most
serious first, as `severity · file:line · what breaks · how to trigger it`.

**Correctness**
- Does each acceptance criterion have a test that would fail without the change?
- Edge cases: empty, null, very large, concurrent, unicode, time zones, retries.
- Errors handled, not swallowed; no silent fallbacks that hide failures.

**Scope**
- Only contract target files changed; nothing in `.claude/protected-paths` unless listed.
- No new dependencies, config or migrations the contract didn't name.

**Interfaces**
- Changed signatures, exports, routes or schemas: are all callers updated?
- Backwards compatibility for stored data and public APIs.

**Security**
- No secrets, tokens or PII in code, logs or error messages.
- Input validated at the boundary; queries parameterised; auth checks not bypassed.

**Maintainability**
- Names say what things do; no dead code or commented-out blocks.
- Docs, ADRs or the module's local `CLAUDE.md` updated if the change makes them wrong.

Verdict line: `ACCEPT` or `REJECT: <failure class>`.
