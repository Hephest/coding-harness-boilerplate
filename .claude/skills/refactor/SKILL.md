---
name: refactor
description: Behaviour-preserving refactoring playbook. Use when restructuring, renaming, extracting or moving code without changing what it does.
---

# Refactor

A refactor changes structure, never behaviour. If behaviour must change, that's a separate task.

1. **Pin behaviour.** Make sure tests cover what you're about to touch. If they don't, add
   characterization tests first and commit them on their own.
2. **Green baseline.** `scripts/verify.sh` must exit 0 before the first edit. Record it.
3. **Small steps.** One mechanical move at a time (rename, extract, inline, move). Run the fast
   check after each; run `test-runner` after every 2–3 steps.
4. **No drive-by changes.** No new features, no dependency bumps, no reformatting of unrelated
   code. Note ideas in the receipt instead.
5. **Public surface.** If a signature, export or file path other code depends on changes,
   update every caller in the same task (find them with `Explore`) or keep a shim.
6. **Review.** `reviewer` checks the diff specifically for behaviour changes.

More than 5 files means the contract must be split, or `architect` must approve the plan first.
