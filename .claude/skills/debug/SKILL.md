---
name: debug
description: Systematic debugging workflow. Use when a test fails, a bug is reported, or behaviour differs from what's expected and the cause isn't obvious after one look.
---

# Debug

Evidence first, theory second. Never change code to "see if it helps".

1. **Reproduce.** Get one command that shows the failure. Run it through `test-runner`
   (in Herdr: `scripts/herdr-sub.sh run test-runner "<command>"`). No repro, no fix: say so.
2. **Shrink.** Narrow to the smallest input, file and function that still fails.
   Use `Explore` to find callers and recent changes (`git log -p -S '<symbol>'`).
3. **Hypothesise.** Write down at most 3 causes, each with the observation that would confirm
   or kill it. Check the cheapest one first.
4. **Prove.** Write a failing test that captures the bug *before* fixing it.
5. **Fix** the cause, not the symptom. Stay inside the contract's target files.
6. **Verify.** `scripts/verify.sh` exits 0; the new test passes; nothing else regressed.
7. **Immunize.** Add a line to `.agent/lessons.md` with the failure class and where the fix now
   lives (test, rule, script or hook).

Stop and ask `architect` when the same hypothesis fails twice or the fix needs files outside the
contract.
