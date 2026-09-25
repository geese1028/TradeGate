#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
root="dist/TradeGate.app/Contents"
rm -rf dist/TradeGate.app
mkdir -p "$root/MacOS" "$root/Helpers" "$root/Library/LaunchDaemons" "$root/Resources"
cp .build/release/TradeGateApp "$root/MacOS/TradeGate"
cp .build/release/TradeGateDaemon "$root/MacOS/TradeGateDaemon"
# Default APFS is case-insensitive, so tradegate and TradeGate cannot share MacOS/.
cp .build/release/tradegate "$root/Helpers/tradegate"
cp Packaging/Info.plist "$root/Info.plist"
cp Packaging/AppIcon.icns "$root/Resources/AppIcon.icns"
cp Packaging/com.tradegate.daemon.plist "$root/Library/LaunchDaemons/com.tradegate.daemon.plist"
app=$(shasum -a 256 "$root/MacOS/TradeGate" | awk '{print $1}')
src=$(shasum -a 256 .build/release/TradeGateApp | awk '{print $1}')
cli=$(shasum -a 256 "$root/Helpers/tradegate" | awk '{print $1}')
test "$app" = "$src"
test "$app" != "$cli"
# SMAppService rejects a LaunchDaemon plist that is not sealed into the app signature.
codesign --force --sign - "$root/MacOS/TradeGateDaemon"
codesign --force --sign - --identifier com.tradegate.cli "$root/Helpers/tradegate"
codesign --force --sign - "dist/TradeGate.app"
codesign --verify --deep --strict "dist/TradeGate.app"
echo "packaged dist/TradeGate.app"
