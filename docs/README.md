# docs: where truth lives

Claude reads these on demand. CLAUDE.md only points here; it never copies them.

| Need | Read |
|---|---|
| How the system fits together | `architecture.md` |
| Why something is the way it is | `adr/` (one file per decision, newest wins) |
| How to operate, deploy, recover | `runbooks/` |
| Context for a dangerous module | that module's local `CLAUDE.md` (template: `templates/MODULE_CLAUDE.md`) |

Keep each file short and current. A wrong doc is worse than a missing one: when code and doc
disagree, fix the doc in the same task and mention it in the receipt.
