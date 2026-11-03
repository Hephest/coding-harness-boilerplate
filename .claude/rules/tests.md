---
paths:
  - "tests/**"
---

# Rules for tests

- Tests are the acceptance criteria made executable: one test per criterion in the contract.
- Never delete, skip or loosen an existing assertion to make a change pass. If a test is wrong,
  say so and ask before changing it.
- No network, no real credentials, no sleeps. Use fixtures in `tests/fixtures/`.
- A bug that escaped once becomes a regression fixture here, named after the lesson in `.agent/lessons.md`.
