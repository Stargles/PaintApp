#!/bin/bash
# Show current simulator lock status and active sessions.
# Usage: status.sh

set -euo pipefail

LOCK_DIR="/tmp/paintapp-sim-locks"

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

echo "=== Simulator Status ==="
echo ""
for i in "${!SIM_UUIDS[@]}"; do
    uuid="${SIM_UUIDS[$i]}"
    name="${SIM_NAMES[$i]}"
    lock="$LOCK_DIR/$uuid"
    if [ -d "$lock" ] && [ -f "$lock/info" ]; then
        session=$(cut -d: -f1 "$lock/info")
        lock_time=$(cut -d: -f2 "$lock/info")
        now=$(date +%s)
        age=$(( now - lock_time ))
        printf "  %-28s LOCKED  by %-20s (%dm ago)\n" "$name" "$session" "$((age / 60))"
    else
        printf "  %-28s FREE\n" "$name"
    fi
done

echo ""
echo "=== Active Worktrees ==="
if [ -d "$HOME/PaintApp-worktrees" ]; then
    for dir in "$HOME/PaintApp-worktrees"/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "?")
        printf "  %-20s  branch: %s\n" "$name" "$branch"
    done
else
    echo "  (none)"
fi
echo ""
