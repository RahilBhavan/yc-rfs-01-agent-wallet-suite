# Agent-wallet comparison prototype

This local Foundry prototype compares a per-period ERC-20 budget in MetaMask's Delegation Framework and Coinbase
Spend Permissions. It asks whether the same spending intent and action sequence produce the same outcome.
It is part of Rahil Bhavan's build series responding to YC's October 2026 Crypto RFS, with no implied YC endorsement.

The recorded headline is a zero-value spend: MetaMask accepts `transfer(spender, 0)` while Coinbase reverts
`ZeroValue()`. No tokens move on either side. This is a design difference, not a security or harm claim.
[results.md](results.md) is the authoritative measured table, with its source commit, totals, predictions and limits.
[The completion checklist](docs/completion.md) maps the pinned scope to evidence and open acceptance gates.
Independent reproduction remains open; documentation completion does not close it.

## Run locally

Prerequisites: Git, GNU Make, Python 3 and Foundry **forge 1.8.6** on PATH. Initial setup needs network access to
fetch recursive submodules and install solc 0.8.23 and 0.8.30. Tests use local simulated wallets and test tokens;
no RPC URL, wallet credentials, funded account or running Anvil is required.

```sh
mkdir -p "$HOME/scratch/yc-rfs-builds"
git clone --recurse-submodules https://github.com/RahilBhavan/yc-rfs-01-agent-wallet-suite.git \
  "$HOME/scratch/yc-rfs-builds/wallet-local-run"
cd "$HOME/scratch/yc-rfs-builds/wallet-local-run"
forge --version
make test
make reproduce
```

`make test` bootstraps compilation; `make reproduce` invokes `forge test --offline`, validates the case rows and
prints the table and headline. Offline execution requires the compilers and sources to be present already.
This quick start tests the clone's default branch. Use the reproduction guide to select the recorded measurement
or a proposed integration commit explicitly. Choose an unused scratch directory for each run.
For a clone without submodules, run `git submodule update --init --recursive` before testing.
Use [the reproduction guide](docs/reproduction.md) for an exact recorded-commit checkout, dependency checks,
troubleshooting, the minimal headline trace and an independent review receipt.

## What is compared

MetaMask uses a real `DelegationManager` and an owner-signed delegation on a `HybridDeleGator` initialized behind an
`ERC1967Proxy`. Solidity constructs the Smart Accounts Kit's direct `erc20PeriodTransfer` scope bundle:
`ValueLteEnforcer(0)` followed by `ERC20PeriodTransferEnforcer`. Coinbase uses a real `CoinbaseSmartWallet` with
`SpendPermissionManager` added as an owner, then an approved `SpendPermission` redeemed by the spender.

This models the kit's direct delegation path (path A), not the MetaMask extension's ERC-7715 Advanced Permissions
grant (path B). The SDK, snap and docs were read at the scope's pinned revisions; their TypeScript was not executed.
The native-token row is a separate bundle control. Expiry and payee cases add explicit caveats as described in the
[pinned scope](docs/scope.md#metamasks-sdk-bundle).

Only like-for-like rows can supply the headline. Pause/resume uses different revocation primitives; Coinbase cannot
name a third-party recipient; configuration widths and unavailable calldata/method paths are separate comparisons.
In those rows, an “agree” label can mean both refuse an outcome, without matching API calls. Read each row's class
and actions before interpreting it as equivalent behavior. See [results limits](results.md#what-this-does-not-show).

## Find the evidence

| Path | Purpose |
|---|---|
| [docs/brief.md](docs/brief.md) | Original brief and publication gates; historical status text is not a completion record. |
| [docs/scope.md](docs/scope.md) | Pinned decisions, versions, rule, source citations, predictions and exclusions. |
| [docs/completion.md](docs/completion.md) | Acceptance checklist for each scope section and case; remaining gate owners/actions. |
| [docs/reproduction.md](docs/reproduction.md) | Clean-clone instructions, trace, troubleshooting and reviewer handoff. |
| [results.md](results.md) | Recorded `make reproduce` output at a named commit; no live totals maintained here. |
| [test/Differential.t.sol](test/Differential.t.sol) | Local setup, assertions, exact revert checks and per-case result logs. |
| [src/SpImports.sol](src/SpImports.sol) | Compiles Coinbase's manager separately; tests load artifacts through `vm.deployCode`. |
| [tools/reproduce.py](tools/reproduce.py) | Offline runner, row validation and headline selection. |
| [foundry.toml](foundry.toml), [remappings.txt](remappings.txt) | Mixed compiler configuration, Prague EVM and dependency import paths. |
| `lib/df`, `lib/sp` | Pinned upstream submodules, including recursive dependencies. Never edit upstream code here. |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | Recursive checkout, pinned Foundry, test and reproduction commands; configuration alone is not a passing run. |

## Sources and credit

Runtime sources are [MetaMask Delegation Framework](https://github.com/MetaMask/delegation-framework) in `lib/df`
and [Coinbase Spend Permissions](https://github.com/coinbase/spend-permissions) in `lib/sp`. Exact commits and
source-line references live in [the version ledger](docs/scope.md#versions-pinned); the comparison cites repository
code, not deployed bytecode. MetaMask Smart Accounts Kit, the gator-permissions snap and MetaMask docs supply the
read-only bundle rationale at the revisions in that ledger.

MetaMask's own enforcer tests and `test/utils/BaseTest.t.sol` inform the allowance and proxy setup. Coinbase's
Spend Permissions tests inform the spending, revocation and replacement checks. Warden, AgentScope and AgentTrust
are existing agent-wallet work named in the brief; no compatibility with or evaluation of those projects is claimed.
Rhinestone ModuleKit is credited as an existing smart-account module testing toolkit. kya-protocol is a related hub
project. These credits do not imply affiliation or endorsement.

## Limits and completion

Local prototype only: no real funds, mainnet interaction, investment advice, product recommendation or claim that a
company is operating. Hand-written sequences are not an exhaustive equivalence proof or a fuzz campaign. Delegation
chains, ERC-4337, paymasters, MagicSpend, SpendRouter and ERC-6492 wallet flows remain outside the comparison.
A validator artifact used during setup does not establish coverage of ERC-6492 wallet flows.

The control hub at `~/projects/yc-rfs-builds` owns independent-reproduction and publication gate records. This repo
supplies evidence; [the open-gate checklist](docs/completion.md#remaining-gates-and-integration) describes the handoff.
No license file is present at the repository root. This documentation grants no new license terms; upstream projects
retain their own notices and terms.
