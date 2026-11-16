# Build 1 wrap note

Draft for the Thu Dec 3 Requested wrap post. Not approved, not posted. Rahil approves every post. Nothing here was rerun
for this note: every figure comes from the existing Oct 29-31 measured and reproduced runs.

## What was built
A local Foundry prototype that gives one spender the same budget (100 test-token units per day) in MetaMask's
Delegation Framework (kit `erc20PeriodTransfer` bundle on a `HybridDeleGator`) and in Coinbase Spend Permissions, then
runs the same action sequence on both. 16 hand-written cases, no chain, no funds, no fuzz campaign.

## Result
Measured Oct 29 (forge 1.8.6, solc 0.8.23 and 0.8.30; `results.md`, measured code `b4c0302`): 16 of 16 tests passed.
Of 10 like-for-like cases, 9 agree. All 16: 11 agree, 5 differ. The headline difference is case 2, a zero-value spend.
It is a design difference, not a bug or a harm claim: no tokens move on either side.

## Minimal trace (`test_case2_zeroValue`)
1. `vm.warp(S+10)`, with `S = 1_800_000_000`.
2. MetaMask: `redeemDelegations` with `token.transfer(spender, 0)` succeeds. The period enforcer only checks
   `amount <= available`, and 0 <= 100 (`lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:210`).
3. Coinbase: `spend(permission, 0)` reverts `ZeroValue()` (`lib/sp/src/SpendPermissionManager.sol:692`).
4. Both balances are unchanged. Run: `forge build --offline && forge test --offline --match-test test_case2_zeroValue -vvvv`.

## Evidence
| Check | Result | Reference |
|---|---|---|
| Reproduction 1, Oct 29 | REPRODUCED by Codex gpt-6.1-sol at `43205e7`: 16 passed, 0 failed, 0 skipped, all 16 rows matched | yc-rfs-builds `reviews/01-2026-10-29.md` |
| Reproduction 2, Oct 31 | REPRODUCED by Claude Sonnet 5.5 at `ba2d4d5`: 27 Python unittests OK, 16 Solidity passed, `make reproduce` byte-identical twice, mutation probe rejected | `docs/reviews/2026-10-31-independent-reproduction.md` |
| Final head | `2a02c93` (merged tree `874a421`): `make test` and `make reproduce` passed in local CI | yc-rfs-builds `docs/goals.json`, `finding_measured` |

Reproductions are independent agent runs, not human approval or a security assessment.

## Credit
MetaMask Delegation Framework and Smart Accounts Kit (`lib/df`, `b4b8c41`) and Coinbase Spend Permissions (`lib/sp`,
`e0004e6`) are the systems compared; their own test suites informed setup. Existing agent-wallet work named in the brief:
Warden, AgentScope, AgentTrust. Rhinestone ModuleKit is the existing smart-account module testing toolkit. No compatibility
with, evaluation of, affiliation with or endorsement by any of them is claimed, and none by YC.

## Limits
- Models the kit's direct delegation path, not the MetaMask extension's ERC-7715 grant. The SDK TypeScript was read, not run.
- Cites repository code at pinned commits, not deployed bytecode.
- Hand-written sequences do not prove equivalence. Rows outside the like-for-like rule (3, 10, 11, 12, 14, 15) are
  reported separately.
- Open gates for any post (`docs/goals.json`): `post_approved_by_rahil`, `published_link_recorded`. The exhibit review
  passed Oct 31 for the dark phone card; a human five-second test is still advised.
