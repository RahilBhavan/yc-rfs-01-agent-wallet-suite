# Results

Prototype. Local Foundry only, no chain, no real funds. A difference below is a design difference between two
systems that encode the same rule in different ways. It is not a claim of a bug or a vulnerability in either.

| Field | Value |
|---|---|
| Headline | Case 2, zero-value spend: MetaMask accepts `transfer(spender, 0)`, Coinbase reverts `ZeroValue` |
| Command | `make reproduce` |
| Commit | `a2b29ce484c1dd5f8bd0627f844bd7a5966762c1` |
| Measured on | Oct 29, 2026 (forge 1.8.6, solc 0.8.23 and 0.8.30) |
| Upstreams | MetaMask delegation-framework `b4b8c41`, Coinbase spend-permissions `e0004e6` (submodules in `lib/`) |
| Tests | 16 of 16 passed, one per scope case |
| Independent reproduction | Not yet (hub gate `independent_reproduction`) |

## `make reproduce` output

Pasted unedited from the run at the commit above. `S = 1_800_000_000`, `P = 1 day`, `A = 100` unless a row says
otherwise. Each row comes from one test in `test/Differential.t.sol`; the test asserts every step shown and the
exact revert data of every rejection.

```text
commit a2b29ce484c1dd5f8bd0627f844bd7a5966762c1
MetaMask delegation-framework b4b8c41fc912455a1af2300bfcd1276676b92a2e, Coinbase spend-permissions e0004e63edc4e17de7aa978293800ac7a16892e5

| Case | Class | MetaMask (HybridDeleGator + kit ERC-20 periodic scope) | Coinbase (SpendPermissionManager) | Result | file:line |
|---|---|---|---|---|---|
| 1. period boundary | like-for-like | 100 at S+P-1 ok; +1 transfer-amount-exceeded; +1 at S+P ok | 100 at S+P-1 ok; +1 ExceededSpendPermission; +1 at S+P ok | agree | lib/sp/src/SpendPermissionManager.sol:540; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:254 |
| 2. zero-value spend | like-for-like | transfer(spender, 0) at S+10 accepted | spend(0) at S+10 reverted ZeroValue | differ | lib/sp/src/SpendPermissionManager.sol:692; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:210 |
| 3. pause and resume in one period | revocation model | 60 ok; disable+enable; 60 transfer-amount-exceeded; 60 moved | 60 ok; revoke; new salt; 60 ok; 120 moved | differ | lib/df/src/DelegationManager.sol:90; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:190; lib/sp/src/SpendPermissionManager.sol:658 |
| 4. exactly at start | like-for-like | 1 at S ok | 1 at S ok | agree | lib/sp/src/SpendPermissionManager.sol:519; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:199 |
| 5. one second before start | like-for-like | 1 at S-1 transfer-not-started | 1 at S-1 BeforeSpendPermissionStart | agree | lib/sp/src/SpendPermissionManager.sol:519; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:199 |
| 6. end boundary | like-for-like | with TimestampEnforcer: 1 at end-1 ok; 1 at end expired-delegation (bare bundle: ok at end) | 1 at end-1 ok; 1 at end AfterSpendPermissionEnd | agree | lib/sp/src/SpendPermissionManager.sol:521; lib/df/src/enforcers/TimestampEnforcer.sol:45 |
| 7. truncated last period | like-for-like | 100 at S+P ok; +1 at end-1 transfer-amount-exceeded | 100 at S+P ok (period ends at end); +1 at end-1 ExceededSpendPermission | agree | lib/sp/src/SpendPermissionManager.sol:546; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:254 |
| 8. allowance change mid-period | like-for-like | 60 ok; disable, sign A=150; 150 ok; 210 moved in the period | 60 ok; approveWithRevoke A=150; 150 ok; 210 moved in the period | agree | lib/sp/src/SpendPermissionManager.sol:367; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:190 |
| 9. long idle, no rollover | like-for-like | 10 in period 1; 200 in period 5 transfer-amount-exceeded; 100 ok | 10 in period 1; 200 in period 5 ExceededSpendPermission; 100 ok | agree | lib/sp/src/SpendPermissionManager.sol:551; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:258 |
| 10. recipient | recipient (CB cannot name one) | transfer(X, 50) ok, X got 50 (payee rule: X refused) | spend(50) paid the spender; X cannot be named | differ | lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:209; lib/sp/src/SpendPermissionManager.sol:425 |
| 11. native twin with ERC-20 calldata | no CB calldata path | kit scope: token.transfer(X, 1000) invalid-calldata, 0 TST moved (bare enforcer: ok, 1000 TST moved) | native spend has no calldata input; spend(1) moved 1 wei, 0 TST | agree | lib/df/src/enforcers/ExactCalldataEnforcer.sol:44; lib/df/src/enforcers/NativeTokenPeriodTransferEnforcer.sol:169; lib/sp/src/SpendPermissionManager.sol:731 |
| 12. wrong method | no CB method path | approve invalid-method; transferFrom invalid-execution-length | no entry point; spender's wallet.execute(approve) Unauthorized | agree | lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:183; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:188; lib/sp/lib/smart-wallet/src/CoinbaseSmartWallet.sol:80 |
| 13. two spends in one transaction | like-for-like | 60+60 in one redeemDelegations transfer-amount-exceeded, 0 moved; 50+50 ok | 60+60 from a spender contract ExceededSpendPermission, 0 moved; 50+50 ok | agree | lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:218; lib/sp/src/SpendPermissionManager.sol:712 |
| 14. zero start in config | configuration (kit refuses per source, not run) | hand-built startDate 0: invalid-zero-start-date | start 0 approved; spend(100) ok | differ | lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:194; lib/sp/src/SpendPermissionManager.sol:651 |
| 15. amount above uint160 | expressibility (CB is uint160) | periodAmount 2^160 signed; spend of 2^160 ok | approve with allowance 2^160 reverts in ABI decoding (2^160 - 1 approves) | differ | lib/sp/src/SpendPermissionManager.sol:37; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:157 |
| 16. underlying transfer fails | like-for-like | 60 with balance 50: ERC20InsufficientBalance; 100 still available | 60 with balance 50: ERC20InsufficientBalance; 0 spent in period | agree | lib/df/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol:195; lib/sp/src/SpendPermissionManager.sol:424 |

16 cases ran; 16 tests passed, 0 failed.
Headline: case 2 (zero-value spend) differs like-for-like: MetaMask transfer(spender, 0) at S+10 accepted; Coinbase spend(0) at S+10 reverted ZeroValue. The other 9 like-for-like cases agree.
```

## Headline and why it meets the rule

Headline: case 2 (zero-value spend) differs like-for-like: MetaMask transfer(spender, 0) at S+10 accepted; Coinbase spend(0) at S+10 reverted ZeroValue. The other 9 like-for-like cases agree.

The scope's headline rule (`docs/scope.md`, decision 2) asks for a like-for-like comparison: each side expresses the
same intent with its standard primitives, and the same action sequence then gets a different outcome. Case 2 meets it:

- Same intent: "this agent may move up to 100 TST per day from this wallet."
- Standard primitives: Coinbase's `SpendPermission` approved on `SpendPermissionManager`; MetaMask's caveat bundle
  from the Smart Accounts Kit's `erc20PeriodTransfer` scope (`ValueLteEnforcer(0)` + `ERC20PeriodTransferEnforcer`)
  on a `HybridDeleGator`.
- Same action: at `S+10` the agent asks to move 0 TST to itself.
- Different outcome: Coinbase reverts `ZeroValue()` (`lib/sp/src/SpendPermissionManager.sol:692`). MetaMask accepts:
  the period enforcer checks `amount <= available`, and `0 <= 100` (`lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:210`);
  `ValueLteEnforcer` limits native `value`, not the token amount. No tokens move on either side. The test also checks that the full MetaMask allowance remains available and Coinbase records no spend.

Minimal trace (`test_case2_zeroValue`): `vm.warp(S+10)`; MetaMask `redeemDelegations` with `token.transfer(spender, 0)`
returns; Coinbase `spend(permission, 0)` reverts with selector `ZeroValue()`.

The other like-for-like rows (1, 4-9, 13, 16) agree. Cases 3 and 10 also differ, but the rule excludes them: case 3 is
the revocation model (a pause that keeps the counter has no Coinbase equivalent) and case 10 is the recipient (Coinbase
has no way to name one). Cases 11, 12, 14 and 15 test something one side cannot express, so they are not like-for-like
either. In cases 11 and 12 "agree" means both sides refuse the outcome (no TST moves, no approval is granted), not
that both ran a matched action: Coinbase has no calldata or method input, and case 12's Coinbase attempt is the
spender calling the wallet directly, outside Spend Permissions.

## What this does not show

- It does not show harm. A zero-value spend moves nothing on either side (the test asserts both balances). Read from
  the code but not asserted: on MetaMask's side the accepted no-op still runs the enforcer's state update and emits
  `TransferredInPeriod` (DF enforcer L190-229). This run did not measure whether any indexer, agent or accounting tool
  treats the two outcomes differently.
- It covers one MetaMask path: the kit's direct delegation (path A) on a `HybridDeleGator`. It does not cover the
  ERC-7715 Advanced Permissions grant from the MetaMask extension, which uses an EIP-7702 account and adds a
  `NonceEnforcer` and optional caveats (`docs/scope.md`, "MetaMask's SDK bundle").
- The caveat bundle is built in Solidity to match the kit's source at `555dd20`; the kit's TypeScript was read, not
  run. Case 14's claim that the kit refuses `startDate = 0` is read from source (`delegation-core`
  `erc20TokenPeriodTransfer.ts` L103-104), not executed. Case 11's native bundle is likewise taken from the kit's
  `nativeTokenPeriodicScope.ts` L50-57 as cited in the scope.
- It tests the repo code at the pinned commits, not bytecode deployed on any chain (scope decision 1).
- It is 16 hand-written sequences, not a fuzz campaign. Agreement on these cases does not prove agreement everywhere.
- Delegation chains, ERC-4337 user operations, MagicSpend, `SpendRouter` and ERC-6492 wallets are out of scope.

## Predictions that were wrong

Every outcome matched the scope's prediction (case 11 against its revised prediction). Two reasons did not:

- **Case 12, `transferFrom` under the ERC-20 bundle.** Predicted: rejected as the wrong method
  (`ERC20PeriodTransferEnforcer:invalid-method`, DF L188). Got: rejected earlier by the calldata length check,
  `ERC20PeriodTransferEnforcer:invalid-execution-length` (DF L183), because `transferFrom` calldata is 100 bytes,
  not 68. `approve` (68 bytes) does hit `invalid-method` as predicted. The outcome (rejected) was right; the reason
  was not.
- **Case 13, batch mode.** Predicted: batch mode is rejected by the period enforcer (DF L130). Got: rejected one caveat
  earlier, by `ValueLteEnforcer`, the bundle's first caveat (`lib/df/src/enforcers/ValueLteEnforcer.sol:37`), with the
  same `CaveatEnforcer:invalid-call-type` string from the shared modifier. The outcome (rejected) was right; the
  enforcer that rejects it was not.

Predictions the run confirmed that the scope marked as inferred: case 7 (MetaMask keeps the full allowance in a
truncated last period when `TimestampEnforcer` sets the end), case 8 (a new delegation hash starts a fresh counter),
and case 16 (a failed token transfer rolls the counter back on both sides).
