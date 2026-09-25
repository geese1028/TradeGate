#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
root="dist/TradeGate.app/Contents"
rm -rf dist/TradeGate.app
mkdir -p "$root/MacOS" "$root/Library/LaunchDaemons"
cp .build/release/TradeGateApp "$root/MacOS/TradeGate"
cp .build/release/TradeGateDaemon "$root/MacOS/TradeGateDaemon"
cp .build/release/tradegate "$root/MacOS/tradegate"
cp Packaging/Info.plist "$root/Info.plist"
cp Packaging/com.tradegate.daemon.plist "$root/Library/LaunchDaemons/com.tradegate.daemon.plist"
echo "packaged dist/TradeGate.app"
