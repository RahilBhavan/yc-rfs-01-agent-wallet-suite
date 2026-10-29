---
name: build-week
description: Run this repo's one-week build from pinned scope to a reproducible finding. Use at the start of every session in a yc-rfs build repo, and for "work on the build", "run the cases", "write results" or "make reproduce".
---

# Build week

One build, about 10 hours, one finding. If `docs/scope.md` is missing, pin it first and report it to the hub. Once
pinned, change it only by recording a decision at its top with the date and the reason.

## Day by day

| Day | Done when |
|---|---|
| Wed | Harness runs from a clean clone: `git submodule update --init --recursive && make test` passes. |
| Thu | Every edge case in the scope has one test that asserts the observed outcome on each side. |
| Fri | All cases run. Each wrong prediction is recorded as "predicted X, got Y". |
| Sat | `make reproduce` prints the results table and the headline, and `results.md` holds its output at a named commit. **finding_measured.** |
| Sun | An independent reviewer reproduces it from the hub's brief. Fix only what they could not run. |

## Tests

- One test per scope case, named `test_caseN_<what>`. Assert what each side does (accepts, reverts with which
  error, how much moved). Keep the assertion message as the case's plain-English claim.
- A test asserts the observed behaviour. If the scope predicted otherwise, the test still asserts what happened,
  and `results.md` records the mismatch.
- Check that each rejection fails for the stated reason (in Foundry, `vm.expectRevert` with the selector or
  message), not because of a setup error.

## make reproduce

- Deterministic: no network, no wall-clock time, no random seed that isn't fixed.
- Prints one row per case (case, side A outcome, side B outcome, agree or differ, `file:line` that explains it)
  and then one headline line.
- Exits non-zero if any case fails to run.

## results.md

Paste the `make reproduce` output with the commit hash and date. Then:

- The headline, and why it meets the scope's headline rule.
- What the result does not show.
- Predictions that were wrong.

## Done

Open a PR with the passing tests, `make reproduce` and `results.md`. In the PR body give the headline, the commit,
the test count and the exact command. Report to the hub: repo, commit, headline, and the `results.md` path, as the
evidence for `finding_measured`.
