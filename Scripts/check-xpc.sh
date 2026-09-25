#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product TradeGateDaemon --product tradegate
daemon="$(pwd)/.build/debug/TradeGateDaemon"
cli="$(pwd)/.build/debug/tradegate"
uid="$(id -u)"
domain="gui/${uid}"
label="com.tradegate.daemon"
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
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>TRADEGATE_MOCK</key>
        <string>1</string>
    </dict>
    <key>MachServices</key>
    <dict>
        <key>${label}</key>
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
}
trap cleanup EXIT
launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true
launchctl bootstrap "$domain" "$plist"
sleep 1
status="$("$cli" status)"
printf '%s\n' "$status"
printf '%s\n' "$status" | grep -q "State: "
printf '%s\n' "$status" | grep -v -q "State: LOCK_STATE_UNKNOWN"
echo "cli reached the daemon over XPC"
