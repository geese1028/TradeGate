# Development

```sh
./Scripts/bootstrap.sh
./Scripts/test.sh
./Scripts/check-daemon.sh
./Scripts/check-cli.sh
./Scripts/check-xpc.sh
swift run TradeGateApp --in-process
```

`swift run TradeGateDaemon` does not register the Mach service, so `tradegate status` cannot see it. `Scripts/check-xpc.sh` loads a temporary user agent, reads status over XPC, and removes the agent.

The daemon polls once a second and relocks FIDO when the unlock window ends, even if the menu bar app is closed.

`Scripts/package.sh` builds a `dist/TradeGate.app` bundle with the daemon plist. The CLI is `Contents/Helpers/tradegate`, because a case-insensitive disk treats `tradegate` and `TradeGate` as the same file inside `Contents/MacOS`. Real key tests:

```sh
TRADEGATE_HARDWARE_TEST=1 ./Scripts/test.sh
```

Those tests only lock, unlock, and lock FIDO2/U2F. They do not reset the key. If the variable is set and `ykman` or a manageable key is missing, the test fails.
