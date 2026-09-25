# Security

TradeGate is a behavioral friction tool. It is not a security boundary against an administrator, root user, malware, or a determined user.

The daemon may enable or disable the FIDO2 and U2F USB applications on a managed YubiKey. It must not reset the key, delete credentials, or change the PIN. Production builds only run `ykman` from a fixed path that is owned by root and not writable by the user, or from the bundled helper. Development can opt into another path with `TRADEGATE_DEV_YKMAN=1`.

Audit events are append-only and hash-chained so casual database edits are visible. That chain does not stop someone with full disk access.

Report vulnerabilities by opening a private security advisory on the repository. Do not file public issues for undisclosed key-handling bugs.
