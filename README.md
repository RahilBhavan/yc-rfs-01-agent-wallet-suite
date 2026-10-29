# Agent-wallet test suite: MetaMask and Coinbase agree on 9 of 10 like-for-like per-period spending cases

Prototype for the "Agent infra" ask in YC's October 2026 Crypto Request for Startups. Local Foundry only, no real funds.

This suite gives an agent the same per-period ERC-20 budget in two systems: MetaMask's Delegation Framework (a
`HybridDeleGator` with the Smart Accounts Kit's ERC-20 periodic caveat bundle) and Coinbase Spend Permissions
(`SpendPermissionManager` on a Coinbase Smart Wallet). Then it runs the same action sequence against both. It produces
a 16-row table of outcomes, one row per edge case in the pinned scope, and one headline chosen by the scope's
like-for-like rule.

## Results

Measured Oct 29, 2026 at commit `3bcc6ca`, against MetaMask delegation-framework `b4b8c41` and Coinbase
spend-permissions `e0004e6`. Source: [results.md](results.md), which holds the full `make reproduce` output.

- **Headline, case 2 (zero-value spend):** at `S+10`, MetaMask accepts `transfer(spender, 0)` and Coinbase reverts
  `ZeroValue()`. This is a design difference: Coinbase refuses zero spends
  (`lib/sp/src/SpendPermissionManager.sol:692`); MetaMask's period enforcer checks only `amount <= available`
  (`lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:210`). No tokens move on either side.
- **Like-for-like agreement:** the other 9 like-for-like cases agree. They cover the period boundary, the start, the
  end, a truncated last period, a mid-period allowance change, idle periods, two spends in one transaction and a
  failed token transfer.
- **Differences the rule excludes from the headline:** pause and resume (case 3: 60 left the MetaMask wallet in the
  period, 120 left the Coinbase wallet), the recipient (case 10: MetaMask's bundle lets the agent pay any address,
  Coinbase always pays the spender), `start = 0` (case 14) and amounts above `uint160` (case 15).
- **One prediction was wrong:** case 12's `transferFrom` is rejected by the calldata length check, not the method
  check the scope predicted. The details are in [results.md](results.md#predictions-that-were-wrong).

## How it works

- `test/Differential.t.sol` deploys both systems in one Foundry test contract. MetaMask: a real `DelegationManager`, a
  `HybridDeleGator` behind an `ERC1967Proxy` and a delegation signed by its EOA owner, redeemed by the agent.
  Coinbase: a real `CoinbaseSmartWallet` with the manager as an owner, an approved `SpendPermission` and `spend` from
  the agent.
- Each case is one test, `test_caseN_<what>`. It asserts what each side does and checks every rejection against its
  exact revert data (error string or custom-error selector with arguments), so a setup error cannot pass as an
  expected refusal. It then logs one result row.
- `src/SpImports.sol` compiles Coinbase's manager with solc 0.8.30, because it needs `^0.8.28`. The tests, pinned to
  0.8.23, load it with `vm.deployCode`.
- `tools/reproduce.py` runs `forge test --offline`, checks that all 16 cases ran and passed, prints the table and picks
  the headline. Timestamps are fixed with `vm.warp`, and the run uses no fuzzing, no RPC and no clock.

## Run it

Prerequisites: git, Foundry (`forge 1.8.6` was used), Python 3.

```sh
git clone --recurse-submodules https://github.com/RahilBhavan/yc-rfs-01-agent-wallet-suite.git
cd yc-rfs-01-agent-wallet-suite
make test        # forge test: 16 tests, 16 passed on Oct 29, 2026
make reproduce   # prints the 16-row table and the headline; exits non-zero if any case fails or is missing
```

If you cloned without `--recurse-submodules`, run `git submodule update --init --recursive` first. `make reproduce`
runs offline, so run `make test` once first to let Foundry install solc 0.8.23 and 0.8.30.

## Repository layout

- `test/`: the differential test contract, one test per scope case.
- `src/`: the one-line import that compiles Coinbase's manager with a newer solc.
- `tools/`: `reproduce.py`, the `make reproduce` script.
- `lib/`: pinned upstream submodules, `df` (MetaMask delegation-framework) and `sp` (Coinbase spend-permissions).
- `docs/`: the brief and the pinned scope.
- `results.md`: the `make reproduce` output, the headline, its limits and the wrong predictions.

## Documentation

- [docs/scope.md](docs/scope.md): the pinned scope, with the shared rule, the side-by-side semantics with
  `file:line` citations, the 16 edge cases with their predictions, and the headline rule.
- [docs/brief.md](docs/brief.md): the original one-paragraph brief and the gates before anything is posted.

## Sources

The suite runs upstream code at pinned commits, not bytecode deployed on any chain:

- [MetaMask/delegation-framework](https://github.com/MetaMask/delegation-framework) at `b4b8c41`, in `lib/df`.
- [coinbase/spend-permissions](https://github.com/coinbase/spend-permissions) at `e0004e6`, in `lib/sp`.
- [MetaMask/smart-accounts-kit](https://github.com/MetaMask/smart-accounts-kit) at `555dd20` and
  [MetaMask/snap-7715-permissions](https://github.com/MetaMask/snap-7715-permissions) at `60c8a92`: read only, as the
  source of MetaMask's caveat bundle. They are not dependencies.

## Scope and limits

- Independent student prototype. Not affiliated with or endorsed by Y Combinator, MetaMask, Consensys or Coinbase.
- Local Foundry only. No chain, no real funds, no securities offered, no investment advice, and no advice on which
  system to use.
- Each difference is reported as a design difference between two systems. None is claimed as a bug or a
  vulnerability.
- It covers MetaMask's direct delegation path on a `HybridDeleGator`, not the ERC-7715 grant from the MetaMask
  extension. The kit's TypeScript was read, not run. [results.md](results.md#what-this-does-not-show) lists what
  else the result does not show.
- It runs 16 hand-written sequences, not a fuzz campaign.
- Credits. These projects already work on this problem or this code, and this suite builds on them:
  MetaMask's own Delegation Framework tests (especially
  `test/enforcers/ERC20PeriodTransferEnforcer.t.sol` and the `HybridDeleGator` deployment in `test/utils/BaseTest.t.sol`)
  and Coinbase's Spend Permissions tests; Warden, AgentScope and AgentTrust (existing agent-wallet work); Rhinestone
  ModuleKit (module testing toolkit for smart accounts); and the related hub project kya-protocol.

## License

No license file yet.

Part of [Rahil Bhavan's projects](https://github.com/RahilBhavan).
