# Contract: <task-id>

**Goal (one sentence):** <what changes and why>

## Target files
<!-- Max 5. Globs allowed. The guard hook blocks writes anywhere else. -->
- src/<path>/<file>
- tests/<path>/test_<file>

## Acceptance criteria
<!-- Each one must map to a test or a sensor. "Looks right" is not a criterion. -->
1. <observable behaviour> → covered by `<test name>`
2. `scripts/verify.sh` exits 0

## Out of scope
- <things the agent must not touch or "improve" while it's there>
- No new dependencies (unless listed here: ...)

## Limits
- Repair attempts: 3 (then escalate to `architect`)
- Context: read via `Explore`; don't load whole files over ~300 lines

## Notes / known invariants
- <schema rules, API contracts, gotchas from .agent/lessons.md>
