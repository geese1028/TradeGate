# Architecture

```text
TradeGate.app (SwiftUI, MenuBarExtra)
        | XPC
TradeGateDaemon
        | state machine, rule engine, audit
        | YubiKeyControlling
        |-- MockYubiKeyController (tests, --mock)
        |-- YkmanCLIController (FIDO2/U2F enable and disable only)
```

The app does not call `ykman`. Closing the app does not stop the daemon. If the daemon cannot prove that FIDO is disabled, the visible state is `LOCK_STATE_UNKNOWN`.

Prices are decimal strings. The audit log is insert-only, enforced by SQLite triggers, and each event hashes the previous event.
