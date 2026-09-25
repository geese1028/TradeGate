# State machine

Idle states are derived from facts, in order: pending review, missing plan, entry signal not appeared, otherwise ready.

`READY` plus a normal unlock request moves to `UNLOCKING`, then `UNLOCKED`. The timer moves to `LOCKING`, then `LOCKED`. Emergency unlock is the only transition into `UNLOCKING` from review, plan, or signal states.

Removing the key during `UNLOCKED` moves to `LOCK_STATE_UNKNOWN`. The next insertion locks FIDO before another plan can start. A failed lock that cannot be confirmed stays at `LOCK_STATE_UNKNOWN`.
