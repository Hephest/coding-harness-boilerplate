# ADR-0001: Use an enforced harness for AI coding agents

- **Status:** accepted
- **Date:** YYYY-MM-DD

## Context
AI agents follow prose instructions unreliably under long contexts. They skip tests, edit outside
the intended scope and claim success without evidence.

## Decision
Rules that must always hold live in infrastructure, not prose: hooks (`.claude/hooks/`),
permissions (`.claude/settings.json`), one verify script (`scripts/verify.sh`), and bounded task
contracts (`.agent/contracts/`). Cheap models do reading and test runs; the top model only
plans and judges. Inside Herdr, subagents run in hidden tabs (`scripts/herdr-sub.sh`).

## Consequences
- "Done" means `scripts/verify.sh` exits 0 and a receipt exists. Nothing else counts.
- Changing a hook, the verify script or permissions is a human decision; the agent proposes it.
- Every recurring failure must end as a rule, test, script or hook (`.agent/lessons.md`).
