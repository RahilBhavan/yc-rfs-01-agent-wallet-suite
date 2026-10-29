# Agent-wallet attack test suite: whether the two enforce the same spending rule differently, with a minimal trace

Status: in progress, week of Nov 4, 2026. Prototype for the "Agent infra" ask in YC's October 2026 Crypto Request for Startups.
Testnet or read-only data only.

Stateful differential fuzzing of MetaMask's delegation framework vs Coinbase Spend Permissions.

## Results

Not measured yet. The headline number will come from `make reproduce` and be recorded in [results.md](results.md).

## How it works

To be written when the build is done. The pinned scope is in [docs/scope.md](docs/scope.md) once it exists, and
the original brief in [docs/brief.md](docs/brief.md).

## Run it

```sh
make test        # run the tests
make reproduce   # print the headline number
```

## Repository layout

- `docs/`: the brief and the pinned scope.
- `results.md`: the headline number, the command that produced it and the commit it ran at.

## Scope and limits

- Independent student prototype. Not affiliated with, or endorsed by, Y Combinator or any company named here.
- Testnet or read-only data only. No customer funds, no securities offered, no investment advice.
- Already working on this problem: Warden, AgentScope, AgentTrust, Rhinestone ModuleKit, MetaMask's own tests. Related hub project: kya-protocol.

## License

No license file yet.

Part of [Rahil Bhavan's projects](https://github.com/RahilBhavan).
