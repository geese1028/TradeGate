# TradeGate

TradeGate is a behavioral friction tool.

It is NOT a security boundary against an administrator, root user, malware, or a determined user.

TradeGate does not provide financial advice.

No telemetry. No cloud account. No broker credentials. No trading API access. Local SQLite database only.

TradeGate keeps the FIDO2/U2F applications on a managed YubiKey disabled until a trade plan is approved, then enables them for a short unlock window. It does not reset the key, delete passkeys, or change the PIN. It does not place orders.

## Requirements

- macOS Ventura 13 or later
- Swift 6
- YubiKey 5 series controllable by `ykman` 5.9 or newer, and older than 6
- The managed key should be the only second factor on IBKR and Kraken if the friction is going to matter

## Develop

```sh
./Scripts/test.sh
swift run TradeGateDaemon
swift run tradegate status
swift run TradeGateApp --in-process
```

`--in-process` uses a mock key so the menu bar can be exercised without hardware. The normal app talks to `TradeGateDaemon` over XPC and does not call `ykman`.

Hardware tests that toggle a real key are off unless `TRADEGATE_HARDWARE_TEST=1`. They never reset a key.

## License

Apache License 2.0. See [LICENSE](LICENSE).
