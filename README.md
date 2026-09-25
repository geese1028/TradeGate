# TradeGate

TradeGate is a behavioral friction tool.

It is NOT a security boundary against an administrator, root user, malware, or a determined user.

TradeGate does not provide financial advice.

No telemetry. No cloud account. No broker credentials. No trading API access. Local SQLite database only.

This repository is at v0.1 Phase 1: the local plan model, SQLite store, and append-only audit hash chain. The menu bar app, launch daemon, and YubiKey control come in later phases.

## Phase 1

```sh
swift test
```

Financial prices are stored as exact decimal strings. Audit events can be inserted, and database triggers reject updates and deletes of `audit_events`.
