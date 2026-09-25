#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product tradegate
bin=./.build/debug/tradegate

run_expect_reject() {
  set +e
  "$bin" "$@" >/tmp/tradegate-cli.out 2>/tmp/tradegate-cli.err
  code=$?
  set -e
  if [ "$code" -ne 2 ]; then
    echo "expected exit 2 for: $*" >&2
    cat /tmp/tradegate-cli.err >&2
    exit 1
  fi
  grep -q "not available" /tmp/tradegate-cli.err
}

run_expect_reject unlock --force
run_expect_reject review --skip
"$bin" audit verify >/tmp/tradegate-cli.out
grep -q "audit chain ok" /tmp/tradegate-cli.out
echo "cli refuses bypasses and verifies the audit chain"
