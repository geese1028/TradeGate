#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
plugin="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
if [ -d "$plugin" ]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$plugin"
else
  swift test
fi
