# Development

```sh
./Scripts/bootstrap.sh
./Scripts/test.sh
TRADEGATE_MOCK=1 swift run TradeGateDaemon
swift run tradegate doctor
swift run TradeGateApp --in-process
```

`Scripts/package.sh` builds a `dist/TradeGate.app` bundle with the daemon plist. Real key tests:

```sh
TRADEGATE_HARDWARE_TEST=1 ./Scripts/test.sh
```

Those tests only lock, unlock, and lock FIDO2/U2F. They do not reset the key.
