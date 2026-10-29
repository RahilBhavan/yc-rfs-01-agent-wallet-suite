# Final repository verification

Verified Oct 29, 2026. Final offline measurement: `b4c0302565af0af8bcca08c9645fd4f97fd25a97`. This is a producer-run clean-clone check, alongside
separate coverage, tooling and documentation agents; it does not close the independent-review hub gate.

A new recursive clone of the remote PR branch was created in disk-backed scratch. The integrated commits were
fetched from the producing repository before checkout. No build or cache artifacts were copied into the clone.
Foundry 1.8.6 and installed compiler binaries were available; this was a cold project build, not a fresh toolchain
installation. Commands executed in the clone:

```sh
PATH="$HOME/.foundry/bin:$PATH" make test
PATH="$HOME/.foundry/bin:$PATH" forge build --offline
PATH="$HOME/.foundry/bin:$PATH" forge test --offline --match-test test_case2_zeroValue -vvvv
PATH="$HOME/.foundry/bin:$PATH" make reproduce
git status --short
```

- Cold `make test` passed 27 Python checks and 16 Solidity cases at `1293d2f`.
- The original anchored headline filter selected zero tests despite returning success. The guide now uses
  `test_case2_zeroValue`; the corrected focused trace explicitly passed one test and showed Coinbase's `ZeroValue`.
  The preceding full build supplied dynamically loaded Coinbase artifacts.
- After the guide correction, offline reproduction passed at the full SHA above. Source and test code were
  unchanged between those two revisions. All rows and the headline match the previous measurement; complete
  unedited reproduction output is in [results.md](../results.md).
- Git status after the commands was empty. Top-level and recursive upstream pins remained unchanged.

The coverage agent verified every scoped case and exact rejection data without further Solidity edits.
A separate read-only check verified the citation repair and all 27 Python checks. Citations must be committed
regular source files, including matching parent gitlinks for nested dependencies; local Git metadata is refused.

Remote CI has not run: GitHub reports failed account payments or a spending limit requiring attention before
starting a runner. Independent reproduction and publication gate acceptance still belong to the hub owner;
no hub records were edited.
