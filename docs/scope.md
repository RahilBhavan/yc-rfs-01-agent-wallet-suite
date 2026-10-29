# Build 1 scope draft: one spending rule, two implementations

Status: pinned Oct 29, 2026, with Rahil's decisions. Written Oct 28. Finding
measured by Sat Nov 7. This is a prototype. Testnet and local Foundry only. No real funds.

## Decisions (Rahil, Oct 29, 2026)

1. Cite the repo code at the pinned commits, not deployed bytecode. No deployed-bytecode check.
2. Case 3 (pause and resume) stays in the results table as a revocation-model difference. It cannot be the headline.
   **Headline rule:** the headline must be a like-for-like comparison. Each side expresses the same intent with its
   standard primitives, and the same action sequence then gets a different outcome.
3. MetaMask's side uses the caveat bundle that MetaMask's own SDK produces for a periodic ERC-20 allowance, not the
   bare `ERC20PeriodTransferEnforcer`. The bundle is recorded under "MetaMask's SDK bundle" below.
4. MetaMask's side uses `HybridDeleGator`, deployed as an ERC1967 proxy plus `initialize`, the way the framework's own
   tests do. It replaces the EIP-7702 stateless delegator.

Decision 2 was the assistant's call; decisions 1, 3 and 4 are Rahil's.

## Question

MetaMask's Delegation Framework and Coinbase Spend Permissions both let a wallet give an agent a
per-period token budget. Do they enforce "the same" rule the same way? Where they differ, what is the
shortest action sequence that shows it?

## Versions pinned

| Repo | Commit | Tag / describe | Commit date |
|---|---|---|---|
| https://github.com/MetaMask/delegation-framework | `b4b8c41fc912455a1af2300bfcd1276676b92a2e` | `v1.3.0-186-gb4b8c41` | Oct 22, 2026 |
| https://github.com/coinbase/spend-permissions | `e0004e63edc4e17de7aa978293800ac7a16892e5` | `spend-router-v1.0.0-1-ge0004e6` | Mar 24, 2026 |
| https://github.com/MetaMask/smart-accounts-kit (SDK; read only) | `555dd2043a69d4febba108465c5d79aabc65abdb` | `v38.0.0` (`@metamask/smart-accounts-kit` 2.0.0, `@metamask/7715-permission-types` 2.0.0) | Sep 29, 2026 |
| https://github.com/MetaMask/snap-7715-permissions (ERC-7715 path; read only) | `60c8a92a9d26198963075484d7da369a3a086fa0` | `@metamask/gator-permissions-snap@2.5.0` | Sep 4, 2026 |
| https://github.com/MetaMask/metamask-docs (docs; read only) | `f58d8cc892fea000e08fd43c255f5de94929b019` | none | Oct 26, 2026 |

Toolchain: Foundry `forge 1.8.6`. Per decision 1, the finding cites these repo commits, not the contracts deployed on
any chain. `MetaMask/delegation-toolkit` now redirects to `smart-accounts-kit` (same HEAD). The SDK, snap and docs are
read for the caveat bundle only; they are not build dependencies.

Citations below use `DF/` for `delegation-framework/`, `SP/` for `spend-permissions/`, `SAK/` for
`smart-accounts-kit/packages/`, `SNAP/` for `snap-7715-permissions/packages/gator-permissions-snap/src/` and `DOCS/` for
`metamask-docs/smart-accounts-kit/`, at those commits.

## The shared rule

A wallet lets one spender move up to `A` units of one ERC-20 token per period of `P` seconds. Periods
start at a fixed time `S` and are aligned to it: period `n` covers `[S + nP, S + (n+1)P)`. Unused budget
does not carry over. Coinbase expresses this as one `SpendPermission` struct checked by
`SpendPermissionManager` (`SP/src/SpendPermissionManager.sol`). MetaMask expresses it as a delegation
carrying the `ERC20PeriodTransferEnforcer` caveat (`DF/src/enforcers/ERC20PeriodTransferEnforcer.sol`),
checked when the delegate redeems through `DelegationManager`. Coinbase also has an `end`; MetaMask needs a
second caveat (`TimestampEnforcer`) for that.

## MetaMask's SDK bundle

The SDK has two paths to a periodic ERC-20 allowance. Both put `ValueLteEnforcer(0)` next to the period enforcer.

**Path A, `createDelegation` with the ERC-20 periodic scope (used in the harness).** `createDelegation`
(`SAK/smart-accounts-kit/src/delegation.ts` L363-368, L384-405) calls `resolveCaveats`, which builds the scope's caveats
first and appends any extra caveats the caller passes (`SAK/smart-accounts-kit/src/caveatBuilder/resolveCaveats.ts`
L36-59). Scope type `erc20PeriodTransfer` maps to `createErc20PeriodicCaveatBuilder` (`.../caveatBuilder/scope/index.ts`
L69-73), which adds, in this order (`.../caveatBuilder/scope/erc20PeriodicScope.ts` L24-33):

| # | Enforcer | Terms |
|---|---|---|
| 1 | `ValueLteEnforcer` | `maxValue = 0`, one 32-byte word (`SAK/smart-accounts-kit/src/caveatBuilder/valueLteBuilder.ts` L28; `SAK/delegation-core/src/caveats/valueLte.ts` L61) |
| 2 | `ERC20PeriodTransferEnforcer` | `token (20 bytes) ‖ periodAmount ‖ periodDuration ‖ startDate`, each number 32 bytes, 116 bytes total (`.../erc20PeriodTransferBuilder.ts` L44; `SAK/delegation-core/src/caveats/erc20TokenPeriodTransfer.ts` L107-113) |

`args` is empty for both. The encoder rejects `periodAmount <= 0`, `periodDuration <= 0` and `startDate <= 0` before
signing (`SAK/delegation-core/src/caveats/erc20TokenPeriodTransfer.ts` L95-105). The docs page for this rule shows the
same scope and says it "automatically disallows native token transfers" (`DOCS/guides/delegation/use-delegation-scopes/spending-limit.md` L20-53).

**Path B, ERC-7715 `erc20-token-periodic` (Advanced Permissions).** A dapp calls `requestExecutionPermissions`; the
MetaMask extension's gator-permissions snap builds and signs the delegation. The snap takes the base caveats from
`createErc20TokenPeriodicCaveats` (`SNAP/permissions/erc20TokenPeriodic/index.ts` L1, L39), which returns
`[ERC20PeriodTransferEnforcer, ValueLteEnforcer(0)]` with the same terms as path A, in the other order
(`SAK/7715-permission-types/src/permissions/caveats/erc20TokenPeriodic.ts` L142-195). The snap's locked version, 1.0.0,
returns the same two caveats. The snap then appends (`SNAP/core/grant/GrantedPermissionResolutionService.ts` L128-163):

| # | Enforcer | When | Terms |
|---|---|---|---|
| 3 | `TimestampEnforcer` | if the request has an expiry rule | `after = 0`, `before = expiry` (`SNAP/core/expiryCaveat.ts` L25-42) |
| 4 | `RedeemerEnforcer` | if the request has a redeemer rule | allowed redeemer addresses (`SNAP/core/redeemerCaveat.ts` L25-37) |
| 5 | `AllowedCalldataEnforcer` | if the request has a payee rule | `startIndex = 4`, payee padded to 32 bytes; one payee only for ERC-20 (`SNAP/core/payeeCaveat.ts` L40-51, L83-117) |
| 6 | `NonceEnforcer` | always | the account's current nonce (`GrantedPermissionResolutionService.ts` L152-163) |

The SDK's decoder for this type agrees: period, value-lte and nonce enforcers are required; timestamp, redeemer and
allowed-calldata are optional (`SAK/7715-permission-types/src/permissions/caveats/erc20TokenPeriodic.ts` L43-56). The
SDK forwards `expiry` as an expiry rule when set (`SAK/smart-accounts-kit/src/actions/erc7715Mapping.ts` L48-60).

**Which path the harness uses, and why: path A.** The docs present two tools for two settings. Regular delegations are
for a delegator account the dapp sets up and has signed; Advanced Permissions are for asking a MetaMask extension user
through its UI (`DOCS/concepts/advanced-permissions.md` L35-45). This harness controls the delegator, which is the
first setting, and the docs page for the per-period ERC-20 rule uses path A (`spending-limit.md` L20-53). Path B also
does not fit decision 4: the snap treats a user as upgraded only if the EOA delegates to `EIP7702StatelessDeleGator`
(`SNAP/core/accountController.ts` L204-216), not a `HybridDeleGator`. Caveat order does not change any outcome here,
since every caveat's hook must pass for the redemption to succeed. Path B's extra caveats are noted per case below.

**Delegator account.** A `HybridDeleGator` implementation behind an `ERC1967Proxy`, initialized with
`initialize(owner, [], [], [])`: an EOA owner and no passkeys. This is how the framework's tests deploy it
(`DF/test/utils/BaseTest.t.sol` L101, L459-485; also `DF/test/HybridDeleGatorTest.t.sol` L91-96) and the deploy
parameters the docs show for an EOA signer (`DOCS/guides/smart-accounts/create-smart-account.md` L20-44). The manager
checks the delegation signature through the account's ERC-1271 `isValidSignature` (`DF/src/DelegationManager.sol`
L171-179), which accepts a 65-byte ECDSA signature from the owner (`DF/src/HybridDeleGator.sol` L369-373).

Other candidates checked and set aside: `ERC20TransferAmountEnforcer` and `NativeTokenTransferAmountEnforcer`
(lifetime cap, no period), `ERC20StreamingEnforcer` and `NativeTokenStreamingEnforcer` (linear accrual,
a different rule), `MultiTokenPeriodEnforcer` (several tokens in one caveat; same idea, more surface). All
exist in `DF/src/enforcers/`. `NativeTokenPeriodTransferEnforcer` is the native-token twin of the chosen
enforcer and appears in the table.

## Side-by-side semantics

"Read" means I read it at the cited line. "Inferred" means I did not see it stated directly.
"Run" means the harness below executed it.

| Aspect | Coinbase `SpendPermissionManager` | MetaMask `ERC20PeriodTransferEnforcer` + `ValueLteEnforcer(0)` on a `HybridDeleGator` |
|---|---|---|
| Account | `CoinbaseSmartWallet` with the manager added as an owner | `HybridDeleGator` proxy; signature checked by ERC-1271 (DF `DelegationManager.sol` L171-179, `HybridDeleGator.sol` L369-373) |
| Where state lives | `_lastUpdatedPeriod[hash]` keyed by the permission's EIP-712 hash (SP L121, L712) | `periodicAllowances[msg.sender][delegationHash]`, i.e. per DelegationManager and delegation hash (DF enforcer L35, L190) |
| Rule parameters | `allowance` (uint160), `period` (uint48), `start` (uint48), `end` (uint48) in the signed struct (SP L29-48) | 116-byte terms: token, `periodAmount`, `periodDuration`, `startDate`, all uint256 (DF enforcer L149-160). No end. |
| Period index / alignment | `start = t - ((t - S) % P)` (SP L540-543). Aligned to `S`. | `currentPeriod = (t - S) / P + 1` (DF enforcer L254). Aligned to `S`, first period is index 1. Same alignment as Coinbase (read; equivalence inferred, then run in case 1). |
| Period boundary | Period is `[start, end)`; a new period is chosen when `t >= lastUpdatedPeriod.end` (SP L531, L534) | New period when the computed index differs from `lastTransferPeriod` (DF enforcer L256) |
| Limit check | `value + spent > allowance` reverts, so `spent + value == allowance` is allowed (SP L698, L704) | `amount <= available` passes (DF enforcer L210, L260) |
| Unused budget | Not carried over: a new period starts at `spend: 0` (SP L551) | Not carried over: reset to 0 on a new period (DF enforcer L213-216; NatSpec L14-15 says "forfeited") |
| Before start | Reverts `BeforeSpendPermissionStart` if `t < start`; `t == start` is allowed (SP L519-520) | Reverts `transfer-not-started` if `t < startDate` on first use; `t == startDate` allowed (DF enforcer L199) |
| End | Exclusive: reverts `AfterSpendPermissionEnd` if `t >= end` (SP L521-522). `end` is required and must be `> start` (SP L651) | None in this enforcer. Needs `TimestampEnforcer`, whose upper bound is also exclusive (`t < before`, DF `TimestampEnforcer.sol` L45) and whose lower bound is strict (`t > after`, L40) |
| Last partial period | Truncated at `end` but keeps the full allowance (SP L546-549; NatSpec L511) | No end, so no truncation. With `TimestampEnforcer` the last partial period also keeps the full amount (inferred) |
| Zero values in config | `period == 0`, `allowance == 0`, zero token, zero spender revert at approval (SP L632-648). `start == 0` is allowed. | The SDK refuses `startDate`, `periodAmount` or `periodDuration` of 0 before signing (SAK `delegation-core/src/caveats/erc20TokenPeriodTransfer.ts` L95-105). On chain, the enforcer reverts on them at first redemption (DF enforcer L193-196) |
| Zero-value spend | Reverts `ZeroValue` (SP L692) | Allowed: `0 <= available` (DF enforcer L210). `ValueLteEnforcer` reads only native `value`, which is 0 (DF `ValueLteEnforcer.sol` L40-42). Run: accepted (case 2). |
| Native value with the ERC-20 permission | Cannot move native token: the permission names one token (SP L731-751) | `ValueLteEnforcer(0)` rejects any call with `value > 0` (DF `ValueLteEnforcer.sol` L40-42) |
| Who can spend | Only `spender`, enforced by `requireSender` (SP L420-422) | `delegate` or anyone if `delegate == ANY_DELEGATE` (DF `DelegationManager.sol` L156) |
| Recipient | Always `spender`; the manager does `approve` then `transferFrom` to `spender` (SP L425, L743-751) | Any address in the `transfer(to, amount)` calldata. Neither caveat in the SDK scope reads the recipient (DF enforcer L187-188, L209; `ValueLteEnforcer.sol` L40). Path B can add an optional payee rule (`AllowedCalldataEnforcer`, SNAP `core/payeeCaveat.ts` L40-51). Run: case 10. |
| Call target | The token is fixed in the struct; the manager makes the call (SP L743-751) | Pinned to the token by the period enforcer itself (`token_ == target_`, DF enforcer L186) |
| Which calls count | Only `spend` / `spendWithWithdraw` (SP L420, L437) | Only single-call mode, default exec type (DF enforcer L130-131; `ValueLteEnforcer.sol` L37-38), target must be the token, selector must be `transfer`, calldata exactly 68 bytes (DF enforcer L183-188) |
| Approval step | On-chain `approve` or `approveWithSignature` before any spend; spend checks `isValid` (SP L277-306, L695) | No on-chain approval. Signature checked on every redemption (DF `DelegationManager.sol` L159-180) |
| Revocation | `revoke` / `revokeAsSpender` set `_isRevoked[hash] = true`; permanent. Re-approving the same hash returns `false` (SP L397-411, L658, L675-684). Run: case 3. | The account calls its own `disableDelegation`; `enableDelegation` undoes it (DF `DeleGatorCore.sol` L364-375, which call `DelegationManager.sol` L90-107). Enforcer state is untouched, so the period counter survives (L186-188). Path B adds a `NonceEnforcer`, so bumping the account's nonce also revokes every delegation signed under the old nonce (read; not run). Run: case 3. |
| Changing the allowance | New struct = new hash = fresh counter. `approveWithRevoke` swaps them, guarded by an expected last-period check against front-running, but does not carry `spend` over (SP L367-390) | New terms = new delegation hash (terms are hashed, DF `EncoderLib.sol` L18-27) = fresh counter (inferred from keying at L190) |
| Native token | Same manager, `token = 0xEeee...EEeE` (SP L106, L731-740) | Separate `NativeTokenPeriodTransferEnforcer`. It reads only `value`; target and calldata are discarded (DF `NativeTokenPeriodTransferEnforcer.sol` L169), although NatSpec at L158 says calldata "must be empty". Both SDK paths add `ExactCalldataEnforcer("0x")` by default, which enforces empty calldata (SAK `smart-accounts-kit/src/caveatBuilder/scope/nativeTokenPeriodicScope.ts` L50-57; SAK `7715-permission-types/src/permissions/caveats/nativeTokenPeriodic.ts` L182-187; DF `ExactCalldataEnforcer.sol` L42-44). Read; not run. |
| Value range | Spend and allowance capped at uint160 (SP L701, L37) | uint256 (DF enforcer L25) |
| Failed transfer | Whole `spend` reverts, so the counter rolls back (inferred from SP L424-425 ordering in one tx) | Whole `redeemDelegations` reverts, so the counter rolls back (inferred) |

## Edge cases to run

Each is a hypothesis until run. "Agree" means both accept or both reject. t is `block.timestamp`.
Defaults: `A = 100`, `P = 1 day`, `S = 1_800_000_000`. MetaMask's side is the SDK's path A bundle on a `HybridDeleGator`
unless a case says otherwise.

1. **Period boundary.** Spend `A` at `S+P-1`, then 1 at `S+P-1`, then 1 at `S+P`.
   Prediction: both accept, reject, accept (SP L531, L540; DF L254). **Run: agree.** Same result with the SDK bundle on
   a `HybridDeleGator` (Oct 29): `ValueLteEnforcer` passes because every spend has `value = 0` (DF `ValueLteEnforcer.sol`
   L40-42), and the account type changes only the signature check.
2. **Zero-value spend** at `S+10`. Prediction: Coinbase rejects (SP L692). MetaMask accepts (DF L210).
   **Run: diverge. MM accepted, CB reverted.** Same result with the SDK bundle (Oct 29). `ValueLteEnforcer(0)` limits
   native `value`, not the token amount, so a `transfer(spender, 0)` still passes it (L40-42). Path B adds no amount
   floor either. This meets the headline rule: both sides use their standard periodic allowance and the same action.
3. **Pause and resume inside one period.** Spend 60. Pause. Resume. Spend 60.
   MetaMask pause = `disableDelegation` then `enableDelegation`; the counter survives, so the second 60 fails
   (DF DelegationManager L90-107; enforcer L190). Coinbase cannot un-revoke (SP L658), so resume means a new
   permission with a new salt, which starts at 0 spent; the second 60 succeeds.
   **Run: diverge. 60 left the MetaMask wallet in the period, 120 left the Coinbase wallet.** Same result with the SDK
   bundle on a `HybridDeleGator` (Oct 29). Pause now goes through the account's own `disableDelegation` /
   `enableDelegation` (DF `DeleGatorCore.sol` L364-375); the counter is still keyed by manager and delegation hash, not
   by account type (DF enforcer L190).
   Caveat for framing: if MetaMask "resume" is done by signing a new delegation, it should also reset (case 8).
   The difference is that MetaMask offers a pause that keeps the counter and Coinbase does not. Per decision 2, this is
   a revocation-model difference in the table, not the headline.
4. **Exactly at start.** Spend 1 at `t = S`. Prediction: both accept (SP L519; DF L199). Agree.
5. **One second before start.** Spend 1 at `S-1`. Prediction: both reject. Agree.
6. **End boundary.** Coinbase `end = S+5P`; MetaMask adds `TimestampEnforcer(after=0, before=S+5P)`.
   Spend at `S+5P-1` and `S+5P`. Prediction: both accept then reject (SP L521; DF TimestampEnforcer L45). Agree.
   Without the extra caveat, MetaMask accepts at `S+5P` (no end). Report both setups.
7. **Truncated last period.** `end = S + P + P/2`. Spend `A` at `S+P`. Prediction: both accept the full `A`
   (SP L546-549; MetaMask inferred). Agree.
8. **Allowance change mid-period.** Spend 60 under `A=100`. Replace with `A=150` (Coinbase `approveWithRevoke`;
   MetaMask disable old, sign new). Spend 150. Prediction: both accept; 210 leaves in one period on both sides
   (SP L367-390, L121; DF L190 keyed by hash). Agree, worth stating as a shared property.
9. **Long idle, no rollover.** No spend for 3 periods, then spend `2A`. Prediction: both reject. Agree.
10. **Recipient.** The agent sends to a third address `X`. Rechecked against the SDK bundle: neither `ValueLteEnforcer`
    nor the period enforcer reads the recipient; the target is pinned to the token (DF enforcer L186-188, L209;
    `ValueLteEnforcer.sol` L40). Prediction: MetaMask accepts `transfer(X, 50)`. Coinbase has no way to name a
    recipient; funds always go to `spender` (SP L425). **Run (Oct 29): diverge by construction. MM accepted
    `transfer(X, 50)` and X received 50; Coinbase's spend of 50 went to the spender.** Path B's optional payee rule
    pins the recipient: with `AllowedCalldataEnforcer(4, spender)` added, `transfer(X, 10)` reverted
    (`AllowedCalldataEnforcer:invalid-calldata`, DF `AllowedCalldataEnforcer.sol` L88) and `transfer(spender, 10)`
    passed. This does not meet the headline rule as it stands, because Coinbase cannot express "pay X". It shows a
    default: MetaMask's SDK scope leaves the recipient open, and the ERC-7715 path offers an opt-in rule.
11. **Native-token twin with arbitrary calldata.** Execute `token.transfer(X, 1000)` with `value = 0`. Rechecked against
    the SDK: both native periodic paths add `ExactCalldataEnforcer("0x")` (see the Native token row), so the call
    reverts (DF `ExactCalldataEnforcer.sol` L44). Revised prediction: with the SDK bundle, MetaMask rejects. Coinbase
    native permissions can only move native token (SP L731-740). Agree. The bare enforcer still accepts it (DF Native
    L169), which stays a documentation row: NatSpec L158 says calldata "must be empty" and the SDK adds the caveat
    that enforces it. Not run.
12. **Wrong method.** MetaMask with `approve` or `transferFrom` calldata. Prediction: rejected (DF L188).
    Coinbase has no equivalent path. Not a divergence; documents the surface.
13. **Two spends in one transaction.** MetaMask: two permission contexts in one `redeemDelegations` call (batch mode
    itself is rejected, DF L130). Coinbase: a spender contract calls `spend` twice. Prediction: both count both;
    total over `A` reverts. Agree.
14. **Zero start in config.** `S = 0`. Prediction: Coinbase approves and runs (SP L651 allows it). MetaMask's SDK
    refuses to build it (SAK `delegation-core/src/caveats/erc20TokenPeriodTransfer.ts` L103-104); a hand-built
    delegation is rejected at first redemption (DF L194). Diverge at configuration, not at spend time.
15. **Amount above uint160.** Prediction: Coinbase cannot express it (SP L37, L701). MetaMask accepts the terms.
    Low interest; include only as a row.
16. **Underlying transfer fails** (wallet balance below the spend). Prediction: both revert and the counter does not
    move. Agree.

## Harness check (done Oct 28, revised Oct 29)

Both repos build as-is with `forge build` (MetaMask about 76 s cold, 240 artifacts; Coinbase about 3 s). Only lint
warnings.

The two cannot share one compiler version. MetaMask pins `pragma solidity 0.8.23` and `evm_version = london`.
Coinbase's manager needs `^0.8.28` (it uses transient storage). One Foundry project still works:

- `auto_detect_solc = true`, `evm_version = "prague"` (kept from the EIP-7702 setup; it also covers the transient
  storage Coinbase's manager uses).
- The test file is pinned to 0.8.23 and imports MetaMask's `DelegationManager`, `HybridDeleGator`,
  `ERC20PeriodTransferEnforcer`, `ValueLteEnforcer`, `AllowedCalldataEnforcer`, OpenZeppelin's `ERC1967Proxy`, and
  Coinbase's `CoinbaseSmartWallet` + factory (`^0.8.23`).
- A one-line `src/SpImports.sol` at `^0.8.28` makes forge compile `SpendPermissionManager` with 0.8.30. The test
  loads it with `vm.deployCode` and calls it through a small interface.
- MetaMask side: a real `DelegationManager`, a `HybridDeleGator` proxy owned by an EOA, a root delegation carrying
  the SDK's path A bundle signed by that owner, and `redeemDelegations` from the delegate.
- Coinbase side: a real `CoinbaseSmartWallet` from its factory, the manager added as an owner, `approve` from the
  wallet, `spend` from the spender.

Result on Oct 28: `forge test -vv` compiled 37 files with 0.8.30 and 82 with 0.8.23, then 3 tests passed (cases 1, 2,
3 above). Result on Oct 29, after decisions 3 and 4: 37 files with 0.8.30 and 104 with 0.8.23, then 4 tests passed
(cases 1, 2, 3 and 10). Cases 1-3 kept their outcomes. Each rejection was checked in the trace to fail for the
expected reason (period limit, `ZeroValue`, disabled delegation, revoked permission, payee calldata), not a setup
error. The harness lives in `seed/` and `ops/launch.py 1` moves it into the build repo.

## Method for the week

About 10 hours. Deterministic table first. Fuzz only if time is left.

| Day | Hours | Work |
|---|---|---|
| Wed Nov 4 | 1.5 | Create the build repo. Add both upstreams as submodules at the pinned commits. Move in the harness. One command reproduces cases 1-3 and 10. |
| Thu Nov 5 | 2 | Rahil pins this scope. Write the remaining cases (4-9, 11-16) as tests, one test per case, each asserting the predicted outcome per side. |
| Fri Nov 6 | 2 | Run all cases. Fix wrong predictions honestly (record "predicted X, got Y"). Write `results.md`: case, MM outcome, CB outcome, agree/diverge, file:line. |
| Sat Nov 7 | 2 | Pick the headline divergence under the headline rule (decision 2). Reduce it to the shortest trace. Finding measured. If time remains: a stateful fuzz that drives one random sequence (warp, spend, pause, replace) into both and records total moved per period. |
| Sun Nov 8 | 1 | A different reviewer runs the one committed command from a clean clone and gets the same table. |
| Mon Nov 9 | 1 | Exhibit through research-exhibit: the agree/diverge table, or the one trace. Visual review. |
| Tue Nov 10 | 0.5 | Rahil approves or rejects. Post drafting follows the hub's x-growth skill. |

## What counts as a finding

Either of these:

- A divergence: one action sequence, same intent on both sides, each side using its standard primitives (Coinbase's
  `SpendPermission`, MetaMask's SDK bundle), different outcome. It comes with a minimal trace (timestamps, calls,
  amounts, which side accepts) and the file:line that explains it. Rows like case 3 (revocation model) and case 10
  (no recipient argument on one side) stay in the table but cannot be the headline.
- A negative result: "the two agree on all N cases we ran", with the table.

A divergence is a design difference unless shown otherwise. It is not a bug or vulnerability claim. Several rows are
deliberate choices documented in the code (for example Coinbase's permanent revocation, MetaMask's stacked caveats).

## Out of scope

- Mainnet, real funds, or any deployed contract interaction beyond optional read-only checks.
- Streaming enforcers, lifetime-cap enforcers, `MultiTokenPeriodEnforcer`.
- Delegation chains and re-delegation; ERC-4337 user operations; paymasters; MagicSpend (`spendWithWithdraw`).
- `SpendRouter` and ERC-6492 counterfactual wallets.
- Security claims, severity ratings, or disclosure. If something looks like a real fault, stop and tell Rahil first.
- Advice to anyone on which system to use.

## Credits

Named in the brief; their exact scope still needs one sentence each before posting.

- MetaMask Delegation Framework and its tests, especially `DF/test/enforcers/ERC20PeriodTransferEnforcer.t.sol`,
  `NativeTokenPeriodTransferEnforcer.t.sol`, `MultiTokenPeriodEnforcer.t.sol`, and `DF/test/utils/BaseTest.t.sol` for
  the `HybridDeleGator` deployment.
- MetaMask Smart Accounts Kit (caveat scopes, ERC-7715 permission types) and the gator-permissions snap: the source of
  MetaMask's side's caveat bundle.
- Coinbase Spend Permissions and its tests, especially `SP/test/src/SpendPermissions/getCurrentPeriod.t.sol`,
  `spend.t.sol`, `revoke.t.sol`, `approveWithRevoke.t.sol`.
- Warden, AgentScope, AgentTrust: existing agent-wallet work named in the brief.
- Rhinestone ModuleKit: module testing toolkit for smart accounts.
- Related hub project: kya-protocol.

## Resolved questions

1. Account type versus the ERC-7715 path (assistant default, Oct 29; Rahil can override). Keep one MetaMask column:
   `HybridDeleGator` with the SDK's direct delegation bundle. MetaMask's extension grants ERC-7715 permissions only from
   an EOA upgraded to `EIP7702StatelessDeleGator` (SNAP `core/accountController.ts` L204-216), so the results say they
   model the SDK's direct path, not an extension grant. No outcome in cases 1-3 or 10 depends on the account type, and a
   second column would not fit the 10-hour week. It is a follow-up if the finding holds.
2. Submodules (Oct 28): pinned at the commits above. `ops/launch.py 1` adds them and moves the harness in from
   `seed/`. A fresh seeded repo passed `make test` (4 of 4 on Oct 29).
