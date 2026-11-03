# <module name>: local context for AI agents

> Copy to `<module path>/CLAUDE.md`. Claude Code loads it when it works on files here.
> Keep it under 40 lines. Short must/never rules can go in `.claude/rules/<module>.md` instead;
> this file is for *why*: the hidden complexity a newcomer would get wrong.

## What this module owns
<one or two sentences>

## Why it's dangerous
- <e.g. a missed lock here corrupts sessions silently; nothing fails until production>

## Invariants (each enforced by)
- <invariant>: `<test or sensor that proves it>`

## Before you change anything here
1. Read `<doc or ADR>`.
2. The contract must list the files here explicitly (this path is in `.claude/protected-paths`).
3. Add a test that fails without your change.

## Known gotchas
- <the thing that bit someone last time, linked to its lesson in .agent/lessons.md>
