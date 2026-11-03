# Architecture

> **This is a template: fill it in.** Everything in `<angle brackets>` is a placeholder, and the
> paths below are examples. Until you replace them, this page says nothing about your project.
>
> One page. If it grows past ~150 lines, split a section into its own doc and link it.

## Purpose
<What the system does, for whom, and what "working" means.>

## Components
| Component | Path | Responsibility | Talks to |
|---|---|---|---|
| <api> | `src/api/` | <HTTP layer, validation> | <service> |
| <service> | `src/core/` | <business rules> | <persistence> |
| <persistence> | `src/persistence/` | <DB access, migrations> | <DB> |

## Data flow
<One request, end to end, in 5–8 steps.>

## Invariants
<Things that must always be true. Each one should have a test or a sensor in scripts/verify.sh.>
- <e.g. every write to sessions holds the session lock>

## Danger zones
<Modules where a small mistake is expensive. Each gets a local CLAUDE.md and an entry in
`.claude/protected-paths`.>
- `src/auth/`: <why>
- `migrations/`: <why>
