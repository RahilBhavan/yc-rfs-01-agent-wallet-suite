# Completion and scope traceability

Documentation audit of the agent-wallet comparison prototype on Oct 29, 2026. Baseline inspected:
`43205e7131c3932bfd10940721c9a5ea96044431`. The measured code revision is
`b9827800f1a5aec7ed67f6586e6193d48c69bc37`, named in [results.md](../results.md). Git history shows the test, runner and
Foundry configuration were last changed there at this audit baseline. Results totals remain in results.md rather than
being copied into this checklist.

This audit completes the documentation handoff, not every build/publication gate. “Recorded” below means evidence is
present in the committed results; “inspected” means source/configuration was read; neither means a fresh passing run
in this session. “Open” requires the stated action. The brief's “not started” and the scope's earlier harness counts,
“not run” notes and seed/launch paths are historical planning text. The case tests and named results are the execution
evidence; this audit does not rewrite those pinned documents.

## Acceptance checklist by pinned-scope section

Each row names the acceptance condition, the evidence actually available and what remains. Section names correspond
to [docs/scope.md](scope.md), including its decisions and resolved questions.

| Scope section | Acceptance and available evidence | Status / next action |
|---|---|---|
| Status / pinned scope | Scope header records the pin date and prototype/local-only boundary. | Inspected. Hub owner must verify `scope_pinned` is recorded; this repo does not read or edit the hub. |
| Decisions | Repo sources rather than deployed bytecode; exclude revocation-model headline; SDK bundle; HybridDeleGator proxy. `setUp` at test line 133, `_caveats` at 175 and runner `headline` implement these choices. | Inspected and recorded. Keep these choices in any integration; do not replace the account or bare enforcer silently. |
| Question | Same budget intent, same sequence, smallest observed difference. Case 2 test and results headline supply the acceptance/rejection trace. | Recorded. Independent reviewer must confirm the trace and its limits. |
| Versions pinned | `.gitmodules` plus Git gitlinks record DF `b4b8c41fc912455a1af2300bfcd1276676b92a2e` and SP `e0004e63edc4e17de7aa978293800ac7a16892e5`. SDK/snap/docs revisions are in scope; they are read-only references, not build dependencies. | Top-level gitlinks verified. Recursive dependency health failed locally; clean-clone check is open. No new re-audit of external read-only sources is claimed. |
| The shared rule | Test constants, fixed start in `setUp`, `_caveats` and `_permission` express the aligned periodic budget. Cases 1, 4-9 cover boundaries/replacement/no rollover. | Inspected and recorded. Preserve explicit expiry caveat for matched end comparisons. |
| MetaMask's SDK bundle | `_sdkPeriodicCaveats`, `_caveats`, `_withEnd`, case 10's payee control and case 11's native bundle show the modeled caveats. Owner signs through `_sign`; proxy initialized in `setUp`. | Inspected and recorded for Solidity model. SDK TypeScript and extension grant remain unexecuted; path B is contextual source reading, not a second runtime column. |
| Side-by-side semantics | Scope marks read/inferred/run claims; results links observed rows to upstream `file:line`. Case 7, 8 and 16 observations address the previously inferred truncation/reset/rollback predictions. | Recorded for tested claims only. Native twins, signatures, nonces, data widths and recipient choices do not imply full semantic equivalence. Keep read-only claims labeled. |
| Edge cases to run | Case-to-test ledger below covers each numbered case and controls, including cases originally marked not run. | Inspected and recorded. Fresh execution remains open in this environment. |
| Harness check | `foundry.toml`, `remappings.txt`, `src/SpImports.sol`, test `setUp` and `.github/workflows/ci.yml` implement the mixed-compiler local harness and toolchain pin. | Inspected; recorded run exists. CI configuration is not a CI-success receipt. Scope's `seed/` and `ops/launch.py` refer to launch context; run root Makefile here. |
| Method for the week | Root `make test` and `make reproduce`, full results, reduced headline and wrong-reason notes exist. Stateful fuzz was optional and not added. | Local work recorded. Independent review and later hub stages remain open; calendar rows are planned workflow, not proof of gate completion. |
| What counts as a finding | Case 2 has matched intent/primitives and a zero-spend action with different acceptance; results explains headline eligibility. Runner selects only like-for-like rows. | Recorded. Case 3 and 10 cannot become the headline; configuration and unavailable API rows are excluded too. No harm/security inference follows. |
| Out of scope | Harness is local, no RPC/deployment command is part of reproduction. README and results retain exclusions. | Inspected. No fuzz expansion, deployed-bytecode validation, extension grant, delegation chains, user-op/paymaster, MagicSpend, router or counterfactual-wallet coverage is claimed. |
| Credits | README credits upstream frameworks/tests, kit/snap/docs, Warden, AgentScope, AgentTrust, Rhinestone ModuleKit and kya-protocol, describing their roles without claiming compatibility. | Documentation addressed. Hub publication review still owns final credit/context review. No project license is invented. |
| Resolved questions | README and reproduction guide keep one path-A HybridDeleGator column. Gitlinks and recursive clone instructions implement the submodule decision. | Inspected. Path B remains contextual; verify recursive pins in the independent clone. |

## Case acceptance ledger

Evidence paths below are in [test/Differential.t.sol](../test/Differential.t.sol) at the measured code revision.
All rows have recorded observations in [results.md](../results.md#make-reproduce-output). The checklist action for an
independent reviewer is to execute each test through `make reproduce`, inspect exact refusal reasons when relevant,
and compare its row and class with the recorded output. Function presence alone does not close that action.

| Case | Acceptance / distinguishing control to inspect | Test evidence (function, starting line) |
|---|---|---|
| 1 | Full budget accepted, excess refused, fresh budget at period boundary. | `test_case1_periodBoundary`, 359 |
| 2 | MM zero spend succeeds; CB returns `ZeroValue`; both balance deltas zero. Headline eligible. | `test_case2_zeroValue`, 392 |
| 3 | Disabled/revoked refusal checked; same-hash CB reapproval fails; MM re-enable retains counter while new CB salt starts fresh. Revocation model only. | `test_case3_pauseResumeSamePeriod`, 416 |
| 4 | Spend accepted exactly at start on both sides. | `test_case4_exactlyAtStart`, 471 |
| 5 | Both refuse before start for the start-time reason. | `test_case5_beforeStart`, 493 |
| 6 | Matched expiry accepts before end and rejects at end; MM without expiry accepts at end. | `test_case6_endBoundary`, 523 |
| 7 | Full allowance in truncated final period; CB period end checked; excess refused. | `test_case7_truncatedLastPeriod`, 561 |
| 8 | New allowance/hash gets fresh budget; old authorization refused and new excess refused. Shared reset property. | `test_case8_allowanceChangeMidPeriod`, 593 |
| 9 | Idle periods do not accumulate budget; oversized request refused, one budget accepted afterward. | `test_case9_longIdleNoRollover`, 654 |
| 10 | Default MM pays X; CB pays spender; optional MM payee caveat refuses X and accepts spender. No matched CB recipient input. | `test_case10_recipient`, 687 |
| 11 | SDK native bundle refuses token calldata; bare native enforcer control accepts; native transfers work. CB has no calldata input. | `test_case11_nativeTwinArbitraryCalldata`, 733 |
| 12 | `approve` fails method check; `transferFrom` fails length check; spender's direct CB wallet call is unauthorized and creates no approval. No matched method input. | `test_case12_wrongMethod`, 777 |
| 13 | Two permission contexts / two spender-contract calls count cumulatively and roll back excess; fitting total works. Batch-mode refusal is a separate control. | `_expectBatchModeRefused`, 807; `test_case13_twoSpendsOneTx`, 824 |
| 14 | CB start zero accepted; hand-built MM zero start rejected on chain. SDK refusal is source-read only. | `test_case14_zeroStart`, 867 |
| 15 | MM wide amount works; CB wide ABI input rejected, with max-uint160 approval as valid-encoding control. Expressibility only. | `test_case15_amountAboveUint160`, 894; `_cbApproveWide`, 922 |
| 16 | Insufficient balance reverts with exact token error; available/spent counters remain unchanged. | `test_case16_underlyingTransferFails`, 956 |

Rejection checks use `_assertRevert` at line 316 to compare returned bytes, alongside direct `vm.expectRevert` for
the batch-mode control. This differs mechanically from expecting every revert through a cheatcode, but checks the
observed reason. The case 15 empty ABI-decode revert has an adjacent passing encoding control. Test assertions and
logs should be reviewed together; logged descriptions alone are not assertions.

Two reason predictions were wrong, as already recorded in results: predicted method rejection for case 12's
`transferFrom`, got earlier execution-length rejection; predicted period-enforcer batch rejection for case 13, got
first-caveat `ValueLteEnforcer` rejection. Preserve those corrections. No outcome mismatch is recorded. Case 11 uses
the scope's revised SDK-bundle prediction, with the bare-enforcer result explicitly separated.

## Validation of this documentation handoff

- Read AGENTS.md, build-week skill, brief, every pinned-scope section, README, results, tests, runner, build config,
  remappings, CI configuration and submodule metadata. Cross-checked the case names and starting lines above.
- Passed local Markdown link/anchor and fence checks, case/helper source-line checks, scope-section coverage and
  `git diff --check`. These are documentation checks, not runtime reproduction.
- Verified baseline and gitlink SHAs, plus that test/runner/Foundry-config history points to the measured code revision.
- Initial `make test` failed because `forge` was absent from PATH; initial `make reproduce` failed with Python
  `FileNotFoundError` for `forge`.
- `PATH="$HOME/.foundry/bin:$PATH" forge --version` confirmed installed forge 1.8.6. Re-running `make reproduce` with
  that PATH failed on missing upstream sources, including `lib/sp/src/SpendPermissionManager.sol` and `forge-std`.
  The runner then printed its generic no-JSON message. This was a setup failure, not a measured case outcome.
- `git submodule status --recursive` showed uninitialized/mismatched nested dependencies, and `git status --short`
  showed dirty `lib/df` and `lib/sp` before edits. They were left untouched. No clean-clone success or new results
  measurement is claimed. Dependency repair belongs in a separate disposable clone, as the reproduction guide explains.

The integration handoff should include the documentation commit, whitespace/link/ledger validation and these failed
runtime attempts. Only README and new docs are in this change; pinned scope, brief, results, code, CI, upstreams and
hub are not edited.

## Remaining gates and integration

Unchecked boxes are actions still required; repository evidence is not a hub gate record. This audit did not inspect
hub records, CI run history or a publication approval. The hub owner reconciles existing records before doing new work.

- [ ] **scope_pinned — verify hub record.** Evidence: pinned scope header and decision ledger. Hub owner records or
  confirms the authoritative gate without changing the scope here.
- [ ] **finding_measured — reconcile hub evidence.** Repository measurement is present at the full SHA in results.md.
  Hub owner associates repo URL, measured SHA, headline and `results.md` path with the gate. A docs-only integration
  SHA is not a replacement measured-code SHA; remeasure if the integrated code changes.
- [ ] **independent_reproduction — open explicitly in results.md.** A different reviewer follows the hub brief from a
  clean clone and returns the [review receipt](reproduction.md#independent-reviewer-receipt). Hub owner accepts or
  records blockers. This documentation audit cannot substitute for that reviewer.
- [ ] **exhibit_review_passed — hub-owned, not evidenced here.** After reproduction, hub owner arranges the required
  exhibit and review outside this repo. No exhibit is drafted here.
- [ ] **post_approved_by_rahil — hub-owned, not evidenced here.** Rahil must approve under the hub workflow; a code or
  docs commit is not post approval. No post is drafted here.
- [ ] **published_link_recorded — hub-owned, not evidenced here.** Record an actual published link only after the
  preceding approvals and publication; this repo does not publish.

For integration, take the scoped documentation commit, retain results.md as the measured record and run the guide
against the chosen integrated SHA. If it differs only in documentation, retain that distinction in the receipt.
If any case, pin or outcome changes, the code/results owner must rerun and record the new measurement rather than
editing counts in these docs. This task intentionally ends at a local commit: no push, PR, merge or hub write.
