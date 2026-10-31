# Build 1 gate handoff

Repository: `RahilBhavan/yc-rfs-01-agent-wallet-suite`.
PR: https://github.com/RahilBhavan/yc-rfs-01-agent-wallet-suite/pull/2

## Evidence to reconcile

- Scope is pinned in docs/scope.md. The hub already records `scope_pinned` on Oct 29.
- Latest measured-code commit: `b4c0302565af0af8bcca08c9645fd4f97fd25a97`.
  Complete unedited measurement is in results.md, committed at `ba2d4d5d51145a764d012fc38cb24c005791cbba`.
- Headline: case 2 differs like-for-like. MetaMask accepts zero; Coinbase rejects with ZeroValue. No tokens move.
  Other like-for-like cases agree. Preserve the full denominators, case classes and limits in results.md.
- Latest independent reproduction: docs/reviews/2026-10-31-independent-reproduction.md. Claude Sonnet 5.5,
  different provider from this revision's Codex builder, returned REPRODUCED after a fresh GitHub clone of `ba2d4d5`,
  running the real test and reproduce commands under isolated local CI and checking a negative-control probe.
- Source, test, tool and upstream code did not change after the independent review. This handoff and the new
  receipt are documentation changes. The final delivered head gets its own local CI record.

## Hub records and publication package

The hub currently records the predecessor measurement and reproduction at `43205e7`. Retain that historical
evidence and append the newer receipt above; do not pretend the earlier review tested the newer revision.
No hub files are edited from this build repo, per AGENTS.md.

Existing hub draft: `posts/01-agent-wallet-suite-finding/post.md`.
Existing exhibit: `posts/01-agent-wallet-suite-finding/finding.exhibit.json` and its rendered PNGs.
Existing visual review: `posts/01-agent-wallet-suite-finding/review.md`.

The exhibit still cites the independently reproduced predecessor, whose rows agree with the current run.
Its source label is therefore historical but supported; do not silently relabel old bytes as a new measurement.
The post/exhibit require design acceptance and Rahil's approval. The draft also retains the unresolved series
placement and public-repository-link decision. Nothing is scheduled or published by this handoff.
Record `post_approved_by_rahil` only after approval of the exact package; record `published_link_recorded` only
with the real published X URL. Public release belongs to the hub's publishing workflow.
