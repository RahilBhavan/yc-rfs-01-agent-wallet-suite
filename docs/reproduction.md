# Reproduce the agent-wallet comparison

This guide reproduces a local prototype, with no RPC, credentials or real funds. The reference output and measured
commit are in [results.md](../results.md). Running the suite yourself does not by itself close the hub's
`independent_reproduction` gate: a different reviewer must record a clean-clone receipt against the hub brief.

## Clean clone and first build

Use Git, GNU Make, Python 3 and forge 1.8.6. Install Foundry through your trusted Foundry installation process and
select v1.8.6; CI pins that release too. Confirm `forge --version` before continuing. If Foundry is installed under
`~/.foundry/bin` but absent from PATH, use `export PATH="$HOME/.foundry/bin:$PATH"` in this shell.

On this machine, clones and builds belong on disk under `~/scratch/yc-rfs-builds/`, never `/tmp`. Choose an unused
clone directory; `git clone` should fail rather than overwrite an existing workspace.

```sh
mkdir -p "$HOME/scratch/yc-rfs-builds"
git clone https://github.com/RahilBhavan/yc-rfs-01-agent-wallet-suite.git \
  "$HOME/scratch/yc-rfs-builds/wallet-reproduction-review"
cd "$HOME/scratch/yc-rfs-builds/wallet-reproduction-review"
# Read the measurement SHA from this clone's results.md, then select it explicitly.
measured_revision=$(python3 -c 'import pathlib, re; print(re.search(r"^\| Commit \| `([0-9a-f]{40})` \|$", pathlib.Path("results.md").read_text(), re.M).group(1))')
git checkout --detach "$measured_revision"
git submodule update --init --recursive
forge --version
python3 --version
make test
make reproduce
```

Record the full checkout SHA in the receipt. To reproduce the recorded measurement exactly, use the commit named
in results.md before initializing submodules. For a proposed integration, replace the checkout command with
`git checkout --detach <full-integration-SHA>` using the actual full SHA supplied for review. A later integration
revision needs its own receipt. Save the original results reference: a measured code commit may precede the commit
that records its output in results.md, so results.md inside the detached checkout may describe an older run.

Network access is needed for cloning, recursive submodule downloads and initial compiler downloads. `make test`
allows Foundry to install the required solc versions. MetaMask's sources require 0.8.23; Coinbase's manager is compiled
with 0.8.30 through `src/SpImports.sol`, then loaded by tests via `vm.deployCode`. `foundry.toml` enables compiler
autodetection and the Prague EVM, which supports Coinbase's transient storage. Do not force a single compiler or
substitute a different EVM to make a setup failure disappear.

`make reproduce` runs `forge test --offline --json -vv`. It neither downloads missing compilers nor initializes missing
sources. Fixed `vm.warp` timestamps and hand-written sequences determine the outcomes. A warm local cache is sufficient;
this is not a claim of an air-gapped first build. The runner checks case presence, duplicate/unexpected rows and test
failures, then chooses the first differing like-for-like row as headline. It exits nonzero on a failed run.

## Check identity and preserve evidence

Run these before interpreting the output:

```sh
git rev-parse HEAD
git status --short
git submodule status --recursive
git -C lib/df rev-parse HEAD
git -C lib/sp rev-parse HEAD
make reproduce > ../wallet-reproduction-review-output.txt
```

Inspect the command exit status immediately (`echo $?` in a shell); an output file alone does not prove success.
The top-level submodule SHAs must match [scope versions](scope.md#versions-pinned) at the reference revision. In
recursive submodule status, a leading space means the recorded revision, `-` means uninitialized, `+` means a different
revision and `U` means a conflict. Also inspect `git status --short`: submodule status alone does not certify clean
contents. Do not use `git submodule update --remote`, edit `lib/`, or replace pinned dependencies.

The output header identifies the checkout, not the historical results commit unless that is what you checked out.
The integrated runner verifies Forge 1.8.6, top-level and recursive dependency pins, and case-to-test attribution.
It rejects changed upstream contents, including changes in recursive dependencies. Local tracked or untracked
harness/documentation changes receive a `+dirty` header; the runner fingerprints those contents before and after
execution and refuses to print a table if they changed during the run. It also checks that each citation resolves
inside a pinned upstream and names an existing source line; this does not verify the citation's interpretation.
Retain the status receipt. A clean integration revision can legitimately have a
different header; compare case order, classes, actions, outcomes, citations and headline against results.md, not just
the totals. Explain every difference. Preserve failures as well as successes; never hand-edit the measured table.

## Minimal headline trace

The shared intent is one agent's budget of `A = 100` test-token units per `P = 1 day`, aligned to
`S = 1_800_000_000`. After setup, the shortest measured action is a zero-unit spend at `S+10`:

1. MetaMask: the agent redeems its signed delegation through `DelegationManager.redeemDelegations` with
   `token.transfer(spender, 0)` and native `value = 0`. The direct SDK bundle accepts it.
2. Coinbase: the same spender calls `SpendPermissionManager.spend(permission, 0)` under an approved permission.
   It reverts `ZeroValue()`.
3. Both wallet token balances are unchanged. The result distinguishes acceptance from rejection, not money moved.

[The test](../test/Differential.t.sol), `test_case2_zeroValue`, asserts success, exact Coinbase revert data
and both balance deltas. `setUp` constructs the actual local accounts and managers; `_caveats`
constructs the bundle in Solidity rather than executing the SDK. For a focused call trace, build all artifacts first.
The Coinbase manager and its validator are loaded dynamically through `vm.deployCode`; a filtered test compilation
can omit their artifacts even when its Solidity imports compile successfully:

```sh
forge build --offline
forge test --offline --match-test test_case2_zeroValue -vvvv
```

At the pinned upstream commits, Coinbase's `lib/sp/src/SpendPermissionManager.sol:692` rejects zero; MetaMask's
`lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:210` allows `amount <= available`, and
`lib/df/src/enforcers/ValueLteEnforcer.sol:40` checks native value. These are source citations, not deployed-bytecode
verification. This trace excludes setup transactions from its minimal action sequence; it assumes the accounts,
signature and approval already exist. It shows no downstream harm, gas comparison or indexer behavior.

## Troubleshooting

| Symptom | Diagnosis and action |
|---|---|
| `forge: command not found` or `cannot run forge` | Check `command -v forge` and PATH; use the Foundry bin directory above if installed, then verify v1.8.6. |
| Missing `lib/sp/src/...`, `forge-std`, OpenZeppelin or another import | Inspect recursive submodule status. In a fresh clone, run `git submodule update --init --recursive` and retry `make test`. An empty directory is not an initialized dependency. |
| `+`/`U` submodules or dirty upstream contents | Do not reset a shared worktree or discard another worker's changes. Use a new clean clone at the target SHA. Initialization is a setup operation for that clone, not permission to alter shared `lib/`. |
| Offline compiler missing, version resolution failure | Run `make test` with network available to obtain solc 0.8.23 and 0.8.30. Retry offline reproduction afterward. |
| `forge printed no JSON` | Read the command diagnostics first; check missing compiler and source dependencies. The integrated runner reports nonzero Forge exits before parsing JSON. |
| Wrong compiler/EVM or missing `vm.deployCode` artifact | Check `foundry.toml`, `remappings.txt`, `src/SpImports.sol` and tool version at the selected SHA. After dependencies are correct, `forge clean` in your disposable clone followed by `make test` rebuilds artifacts. |
| GitHub authentication/repository access failure | Obtain access through the repository owner using your normal Git credentials. Do not insert secrets into commands, docs or receipts. |
| Missing/duplicate row, failed test, changed headline | Save stderr and exit status; build all artifacts with `forge build --offline`, then inspect the failing case with `forge test --offline --match-test '<exact test name>' -vvvv`. Report the failure and revision. Do not weaken assertions or update results to force agreement. |

No node/npm install, SDK build, deployment, key provisioning or testnet faucet is part of this procedure.

## Independent reviewer receipt

An independent reviewer should start from the hub's brief, use a new clone and return this evidence to the hub owner:

- Reviewer identity and date; repository URL; full target commit; OS and `forge --version` / `python3 --version`.
- Commands used, clean `git status --short`, recursive submodule status and top-level upstream SHAs.
- Exit statuses and complete output from `make test` and `make reproduce`; focused headline trace if inspected.
- Whether rows and headline match the reference; any mismatches, setup blockers or changes required to run it.
- Explicit confirmation that the reviewer is independent of the producing run. The hub owner records gate acceptance.

The hub then owns exhibit review, Rahil's post approval and published-link recording. This repo does not close those
gates or draft their artifacts. Retain receipts in the agreed review destination before deleting only your own scratch
clone. Never delete the shared `~/scratch/yc-rfs-builds/` parent.
