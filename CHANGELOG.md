# Changelog

## 0.1.0

- Local SQLite plans, revisions, executions, reviews, and an append-only audit hash chain.
- Gate state machine that blocks a normal unlock until a plan is ready and required reviews are done.
- Emergency override with a confirmation phrase, countdown, audit events, and a required review.
- Menu bar app, launch daemon, XPC boundary, and `ykman` adapter for FIDO2/U2F only.
- Mock key for tests. Real hardware tests stay behind `TRADEGATE_HARDWARE_TEST=1`.
