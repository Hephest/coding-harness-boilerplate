# Runbooks

One file per operation, written so an agent or a tired human can follow it step by step.

Each runbook has:
1. **When to use it:** the trigger or symptom
2. **Preconditions:** access, versions, what must be true first
3. **Steps:** exact commands, one per line, with the expected output
4. **Verify:** how you know it worked
5. **Roll back:** how to undo it

Suggested first runbooks: `local-setup.md`, `release.md`, `database-migration.md`, `incident.md`.
Agents may read and follow runbooks, but steps that deploy, migrate production data or push
need the user's explicit yes, every time.
