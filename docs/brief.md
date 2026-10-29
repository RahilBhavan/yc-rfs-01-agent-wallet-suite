# Build 1: agent wallet suite

Status: not started. YC RFS ask: Agent infra. Timebox: 1 week (about 10 hours).

This is the brief. It seeds the build's own private repo at launch (see `docs/operations.md`).

- **Prototype:** Stateful attack tests against MetaMask's delegation framework and Coinbase Spend Permissions.
- **Finding to publish:** Where the two enforce the same spending rule differently, with a minimal failing trace.
- **Already exists (credit these):** Warden, AgentScope, AgentTrust, Rhinestone ModuleKit, MetaMask's own tests. Related hub project: kya-protocol.
- **Gates before posting:** scope_pinned, finding_measured, independent_reproduction, exhibit_review_passed, post_approved_by_rahil, published_link_recorded.

Testnet or read-only only. No customer money, no offerings, no implied YC endorsement.
