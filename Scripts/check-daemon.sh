#!/bin/sh
# AC-15: a client that talks to the daemon can exit, and the same daemon
# process keeps answering. This uses a temporary user agent, not SMAppService,
# so it does not ask for administrator approval.
set -eu
cd "$(dirname "$0")/.."
swift build --product TradeGateDaemon --product tradegate
daemon="$(pwd)/.build/debug/TradeGateDaemon"
cli="$(pwd)/.build/debug/tradegate"
uid="$(id -u)"
domain="gui/${uid}"
label="com.tradegate.daemon.ac15"
mach="com.tradegate.daemon.ac15"
support="$(mktemp -d "${TMPDIR:-/tmp}/tradegate-ac15.XXXXXX")"
agents="${HOME}/Library/LaunchAgents"
plist="${agents}/${label}.plist"
mkdir -p "$agents"
cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${daemon}</string>
        <string>--mock</string>
        <string>--mach-service=${mach}</string>
        <string>--support-dir=${support}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>TRADEGATE_MOCK</key>
        <string>1</string>
        <key>TRADEGATE_SUPPORT_DIR</key>
        <string>${support}</string>
        <key>TRADEGATE_MACH_SERVICE</key>
        <string>${mach}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${support}/daemon.out</string>
    <key>StandardErrorPath</key>
    <string>${support}/daemon.err</string>
    <key>MachServices</key>
    <dict>
        <key>${mach}</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
cleanup() {
  launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
  rm -rf "$support"
}
trap cleanup EXIT
live_db="${HOME}/Library/Application Support/TradeGate/tradegate.sqlite"
live_tail=""
if [ -f "$live_db" ]; then
  live_tail="$(sqlite3 "$live_db" "SELECT COALESCE(MAX(rowid), 0) FROM audit_events;")"
fi
launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true
launchctl bootstrap "$domain" "$plist"

ready=0
i=0
while [ "$i" -lt 40 ]; do
  if launchctl print "$domain/$label" 2>/dev/null | grep -q "state = running"; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 0.25
done
if [ "$ready" -ne 1 ]; then
  echo "daemon did not start" >&2
  launchctl print "$domain/$label" >&2 || true
  exit 1
fi

job_pid() {
  launchctl print "$domain/$label" | awk '/pid = / { print $3; exit }'
}

pid="$(job_pid)"
test -n "$pid"
parent="$(ps -o ppid= -p "$pid" | tr -d ' ')"
if [ "$parent" != "1" ]; then
  echo "daemon parent is $parent, expected launchd" >&2
  exit 1
fi

export TRADEGATE_SUPPORT_DIR="$support"
export TRADEGATE_MACH_SERVICE="$mach"
first=""
i=0
while [ "$i" -lt 8 ]; do
  first="$("$cli" status)"
  if printf '%s\n' "$first" | grep -q "State: PLAN_REQUIRED"; then
    break
  fi
  i=$((i + 1))
  sleep 0.25
done
printf '%s\n' "$first"
if ! printf '%s\n' "$first" | grep -q "State: PLAN_REQUIRED"; then
  echo "--- daemon stdout ---" >&2
  cat "$support/daemon.out" >&2 || true
  echo "--- daemon stderr ---" >&2
  cat "$support/daemon.err" >&2 || true
  exit 1
fi
printf '%s\n' "$first" | grep -q "Present"

# Stand-in for the menu-bar process: its own session, so quitting it cannot
# reap the daemon. It keeps an XPC conversation open, then the whole group dies.
perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/sh -c '
  cli="$1"
  while true; do
    "$cli" status >/dev/null 2>&1 || exit 0
    sleep 0.2
  done
' sh "$cli" &
client=$!
sleep 1
if ! kill -0 "$client" 2>/dev/null; then
  echo "menu-bar stand-in exited before the quit check" >&2
  exit 1
fi
kill -TERM -- -"$client" 2>/dev/null || kill -TERM "$client" 2>/dev/null || true
wait "$client" 2>/dev/null || true

# Longer than the daemon poll, and longer than a one-second liveness check.
sleep 3
if kill -0 "$client" 2>/dev/null; then
  echo "menu-bar stand-in is still running" >&2
  exit 1
fi
after="$(job_pid)"
if [ "$after" != "$pid" ]; then
  echo "daemon pid changed from $pid to ${after:-missing}" >&2
  exit 1
fi
if ! kill -0 "$pid" 2>/dev/null; then
  echo "daemon died when the client exited" >&2
  exit 1
fi
second="$("$cli" status)"
printf '%s\n' "$second" | grep -q "State: PLAN_REQUIRED"
printf '%s\n' "$second" | grep -q "Present"
if [ -n "$live_tail" ]; then
  now_tail="$(sqlite3 "$live_db" "SELECT COALESCE(MAX(rowid), 0) FROM audit_events;")"
  if [ "$now_tail" != "$live_tail" ]; then
    echo "daemon check wrote the normal database" >&2
    exit 1
  fi
fi
if [ ! -f "$support/tradegate.sqlite" ]; then
  echo "daemon did not use the temporary database" >&2
  exit 1
fi
echo "client exited; daemon $pid continued"
