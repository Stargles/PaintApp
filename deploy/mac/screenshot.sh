#!/bin/bash
# Take a screenshot of the iPad simulator claimed by a session.
#
# Usage:
#   screenshot.sh <session-id> [output-path]
#
# If output-path is omitted, saves to /tmp/paintapp-screenshots/<session-id>_<timestamp>.png
# Prints the path to the saved screenshot on success.
#
# Examples:
#   screenshot.sh my-session
#   screenshot.sh my-session /tmp/screen.png

set -euo pipefail

SESSION_ID="${1:?Usage: screenshot.sh <session-id> [output-path]}"
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-' | head -c 64)

LOCK_DIR="/tmp/paintapp-sim-locks"
SCREENSHOT_DIR="/tmp/paintapp-screenshots"

SIM_UUIDS=(
    "C90F0965-6F87-4FB7-BD97-941E03968E99"
    "2AE27426-4D30-465F-9B93-A759CAEA8456"
    "2728EC30-A6B1-49FF-BFE8-7A71945F631C"
    "37AB7750-D487-46A6-88CA-381462F31107"
    "BE6580AC-B13E-4E3B-BA09-45E8EDD43B9B"
    "A3A42701-53F0-4DE7-93D0-F092605D3354"
)
SIM_NAMES=(
    "iPad Pro 13-inch (M5)"
    "iPad Pro 11-inch (M5)"
    "iPad Air 13-inch (M4)"
    "iPad Air 11-inch (M4)"
    "iPad (A16)"
    "iPad mini (A17 Pro)"
)

find_sim_for_session() {
    for i in "${!SIM_UUIDS[@]}"; do
        local uuid="${SIM_UUIDS[$i]}"
        local info_file="$LOCK_DIR/$uuid/info"
        if [ -f "$info_file" ]; then
            local lock_session
            lock_session=$(cut -d: -f1 "$info_file" 2>/dev/null || echo "")
            if [ "$lock_session" = "$SESSION_ID" ]; then
                echo "$i"
                return 0
            fi
        fi
    done
    return 1
}

SIM_INDEX=$(find_sim_for_session) || {
    echo "ERROR: No simulator locked by session '$SESSION_ID'" >&2
    echo "Check active sessions with: bash ~/PaintApp/deploy/mac/status.sh" >&2
    exit 1
fi

SIM_UUID="${SIM_UUIDS[$SIM_INDEX]}"
SIM_NAME="${SIM_NAMES[$SIM_INDEX]}"

BOOTED=$(xcrun simctl list devices | grep "Booted" | grep -c "$SIM_UUID" || true)
if [ "$BOOTED" -eq 0 ]; then
    echo "ERROR: Simulator $SIM_NAME ($SIM_UUID) is not booted" >&2
    echo "The simulator may have shut down after the last test run." >&2
    exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

if [ -n "${2:-}" ]; then
    OUTPUT_PATH="$2"
else
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    OUTPUT_PATH="$SCREENSHOT_DIR/${SESSION_ID}_${TIMESTAMP}.png"
    mkdir -p "$(dirname "$OUTPUT_PATH")"
fi

xcrun simctl io "$SIM_UUID" screenshot --mask=ignored "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
