#!/bin/bash
# Installs the auto-resigner from this checkout. No sudo. Re-run after changing tools/resign/.
#   1. pins tools/resign/resign.sh at ~/.config/paintapp/bin/resign.sh, so moving main never
#      changes the script under a running job;
#   2. points the root LaunchDaemon's program, ~/PaintApp/deploy/resign.sh, at that pinned copy;
#   3. loads the user LaunchAgent that ticks every 5 minutes.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG_DIR="$HOME/.config/paintapp"
PINNED="$CONFIG_DIR/bin/resign.sh"
SHIM="$HOME/PaintApp/deploy/resign.sh"
AGENT_LABEL=com.paintapp.resign-agent
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

bash -n "$HERE/resign.sh"
mkdir -p "$CONFIG_DIR/bin" "$(dirname "$SHIM")" "$(dirname "$AGENT_PLIST")"

tmp=$(mktemp "$PINNED.XXXXXX")
cp "$HERE/resign.sh" "$tmp"
chmod 755 "$tmp"
mv -f "$tmp" "$PINNED"

tmp=$(mktemp "$SHIM.XXXXXX")
printf '#!/bin/bash\n# Installed by tools/resign/install.sh; the LaunchDaemon runs this path.\nexec /bin/bash %q "$@"\n' "$PINNED" > "$tmp"
chmod 755 "$tmp"
mv -f "$tmp" "$SHIM"
rm -f "$(dirname "$SHIM")"/resign.sh.bak-*

cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$AGENT_LABEL</string>
	<key>ProgramArguments</key>
	<array><string>/bin/bash</string><string>$PINNED</string></array>
	<key>StartInterval</key><integer>300</integer>
	<key>RunAtLoad</key><true/>
	<key>StandardOutPath</key><string>/dev/null</string>
	<key>StandardErrorPath</key><string>$CONFIG_DIR/agent-stderr.log</string>
	<key>EnvironmentVariables</key>
	<dict><key>HOME</key><string>$HOME</string></dict>
</dict>
</plist>
PLIST
plutil -lint "$AGENT_PLIST" >/dev/null

domain="gui/$(id -u)"
launchctl bootout "$domain/$AGENT_LABEL" 2>/dev/null || true
launchctl bootstrap "$domain" "$AGENT_PLIST"
echo "Pinned $PINNED; shim $SHIM; agent $AGENT_LABEL loaded (every 300 s)."
