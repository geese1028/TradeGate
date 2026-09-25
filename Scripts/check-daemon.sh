#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product TradeGateDaemon
log=$(mktemp)
TRADEGATE_MOCK=1 ./.build/debug/TradeGateDaemon >"$log" 2>&1 &
pid=$!
sleep 1
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  echo "daemon stayed up without the app"
else
  echo "daemon exited" >&2
  cat "$log" >&2
  exit 1
fi
