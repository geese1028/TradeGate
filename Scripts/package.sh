#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
root="dist/TradeGate.app/Contents"
rm -rf dist/TradeGate.app
mkdir -p "$root/MacOS" "$root/Helpers" "$root/Library/LaunchDaemons"
cp .build/release/TradeGateApp "$root/MacOS/TradeGate"
cp .build/release/TradeGateDaemon "$root/MacOS/TradeGateDaemon"
# Default APFS is case-insensitive, so tradegate and TradeGate cannot share MacOS/.
cp .build/release/tradegate "$root/Helpers/tradegate"
cp Packaging/Info.plist "$root/Info.plist"
cp Packaging/com.tradegate.daemon.plist "$root/Library/LaunchDaemons/com.tradegate.daemon.plist"
app=$(shasum -a 256 "$root/MacOS/TradeGate" | awk '{print $1}')
src=$(shasum -a 256 .build/release/TradeGateApp | awk '{print $1}')
cli=$(shasum -a 256 "$root/Helpers/tradegate" | awk '{print $1}')
test "$app" = "$src"
test "$app" != "$cli"
echo "packaged dist/TradeGate.app"
