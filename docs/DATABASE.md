# Database

SQLite with `foreign_keys=ON`, WAL, and versioned migrations. Tables: `managed_devices`, `trade_plans`, `plan_revisions`, `executions`, `reviews`, `unlock_sessions`, `emergency_overrides`, `audit_events`, `settings`.

`audit_events` has `BEFORE UPDATE` and `BEFORE DELETE` triggers that abort. `event_hash` is SHA-256 of `prev_hash` concatenated with a canonical JSON payload. The genesis previous hash is 64 zero characters.

Plan edits insert a new `plan_revisions` row. They do not overwrite older snapshots.
