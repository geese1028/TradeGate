#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./Scripts/package.sh
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/TradeGate.app"
cp -R dist/TradeGate.app "$HOME/Applications/TradeGate.app"
echo "Installed $HOME/Applications/TradeGate.app"
echo "Open it to register the daemon. The first registration asks for administrator approval."
