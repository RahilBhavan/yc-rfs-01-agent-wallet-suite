# Agent-wallet attack test suite

A one-week prototype for the "Agent infra" ask in YC's October 2026 Crypto RFS, part of Rahil Bhavan's build series.
The question: whether the two enforce the same spending rule differently, with a minimal trace.

The control hub is `~/projects/yc-rfs-builds`. It owns the schedule, the gate records and the posts. This repo owns
the code, the tests and `results.md`. Do not edit the hub from here; report gate evidence back to it.

Start every session with the `build-week` skill (`.agents/skills/build-week/SKILL.md`), then read `docs/brief.md`
and `docs/scope.md` (if it is not pinned yet, pinning it is the first job).

## Rules

- Testnet or local only. Never send a transaction to a mainnet RPC, never handle real funds, never give investment
  advice or offer securities. The `chain_guard` hook blocks mainnet sends and raw keys in Claude sessions; Codex has
  no hook and must follow this by hand.
- Call this a prototype. Never imply YC endorsement or that a company is operating.
- A difference between systems is a design difference unless shown otherwise. Do not call it a bug or a
  vulnerability in code, results or commit messages.
- Every number in `results.md` comes from `make reproduce` at a named commit. Never type a result by hand.
- Report predictions honestly: when a test shows the scope's prediction was wrong, record "predicted X, got Y" and
  keep the observed outcome.
- Upstream code lives in pinned submodules under `lib/`. Never edit it; cite it as `file:line` at the pinned commit.
- Credit the existing projects listed in `docs/brief.md` in the README.
- Clones, installs and builds go in `~/scratch/yc-rfs-builds/<task>/`, not `/tmp`.
- Do not draft or publish X posts or exhibits here. The hub does that after the gates pass.
