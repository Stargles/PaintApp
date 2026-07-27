#!/bin/bash
# PaintApp Parallel Test Runner
# Each session gets its own worktree + DerivedData + simulator, so multiple
# sessions can test concurrently without conflicts.
#
# Usage:
#   parallel_test.sh <session-id> <branch> [test-filter]
#
# Examples:
#   parallel_test.sh session-a main
#   parallel_test.sh session-a feature-branch
#   parallel_test.sh session-a main testCreateCanvasReachesEditorWithoutFreezing
#
# What it does:
#   1. Creates/reuses an isolated git worktree for <session-id>
#   2. Syncs that worktree to origin/<branch>
#   3. Claims a free iPad simulator (atomic mkdir lock, auto-reclaims stale locks)
#   4. Runs xcodebuild test with per-session DerivedData
#   5. Releases the simulator when done (even on crash/error)

set -euo pipefail

SESSION_ID="${1:?Usage: parallel_test.sh <session-id> <branch> [test-filter]}"
BRANCH="${2:?Usage: parallel_test.sh <session-id> <branch> [test-filter]}"
TEST_FILTER="${3:-}"

SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-' | head -c 64)

MAIN_REPO="$HOME/PaintApp"
WORKTREE_DIR="$HOME/PaintApp-worktrees/$SESSION_ID"
DERIVED_DATA="$HOME/PaintApp-derived/$SESSION_ID"
LOCK_DIR="/tmp/paintapp-sim-locks"
STALE_THRESHOLD=7200

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

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ─── Step 1: Set up isolated worktree ───────────────────────────────────────

log "Session: $SESSION_ID | Branch: $BRANCH"

mkdir -p "$LOCK_DIR" "$DERIVED_DATA" "$HOME/PaintApp-worktrees"

git -C "$MAIN_REPO" fetch origin --prune 2>&1

TRACK_BRANCH="session/$SESSION_ID"

if [ -f "$WORKTREE_DIR/.git" ] && grep -q "gitdir:" "$WORKTREE_DIR/.git" 2>/dev/null; then
    log "Reusing existing worktree"
else
    if [ -d "$WORKTREE_DIR" ]; then
        log "Removing stale worktree directory"
        rm -rf "$WORKTREE_DIR"
    fi

    CREATED=false
    if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        git -C "$MAIN_REPO" worktree add "$WORKTREE_DIR" -b "$TRACK_BRANCH" "origin/$BRANCH" 2>&1 && CREATED=true
    fi
    if [ "$CREATED" = false ]; then
        git -C "$MAIN_REPO" worktree add "$WORKTREE_DIR" -b "$TRACK_BRANCH" origin/main 2>&1 && CREATED=true
    fi
    if [ "$CREATED" = false ]; then
        log "ERROR: Could not create worktree for branch '$BRANCH'"
        exit 1
    fi
    log "Created worktree at $WORKTREE_DIR"
fi

git -C "$WORKTREE_DIR" fetch origin 2>&1
git -C "$WORKTREE_DIR" reset --hard "origin/$BRANCH" 2>&1 || \
    git -C "$WORKTREE_DIR" checkout "$TRACK_BRANCH" 2>&1 || true
log "Worktree synced to origin/$BRANCH"

# ─── Step 2: Claim a simulator ──────────────────────────────────────────────

claim_sim() {
    for i in "${!SIM_UUIDS[@]}"; do
        local uuid="${SIM_UUIDS[$i]}"
        local lock="$LOCK_DIR/$uuid"
        if mkdir "$lock" 2>/dev/null; then
            echo "${SESSION_ID}:$(date +%s)" > "$lock/info"
            echo "$i"
            return 0
        fi
        if [ -f "$lock/info" ]; then
            local lock_time
            lock_time=$(cut -d: -f2 "$lock/info" 2>/dev/null || echo 0)
            local now
            now=$(date +%s)
            local age=$(( now - lock_time ))
            if [ "$age" -gt "$STALE_THRESHOLD" ]; then
                log "Reclaiming stale lock on ${SIM_NAMES[$i]} (${age}s old)"
                rm -rf "$lock"
                if mkdir "$lock" 2>/dev/null; then
                    echo "${SESSION_ID}:$(date +%s)" > "$lock/info"
                    echo "$i"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

log "Claiming a simulator..."
SIM_INDEX=""
for attempt in $(seq 1 120); do
    SIM_INDEX=$(claim_sim 2>/dev/null) && break
    if [ $((attempt % 6)) -eq 0 ]; then
        log "All simulators busy, waiting... ($((attempt * 10))s elapsed)"
    fi
    sleep 10
done

if [ -z "$SIM_INDEX" ]; then
    log "ERROR: No simulator available after 20 minutes"
    exit 1
fi

SIM_UUID="${SIM_UUIDS[$SIM_INDEX]}"
SIM_NAME="${SIM_NAMES[$SIM_INDEX]}"
log "Claimed: $SIM_NAME ($SIM_UUID)"

release_sim() {
    rm -rf "$LOCK_DIR/$SIM_UUID"
    log "Released: $SIM_NAME"
}
trap release_sim EXIT

# ─── Step 3: Run xcodebuild test ────────────────────────────────────────────

log "Starting tests..."
log "Project: $WORKTREE_DIR/PaintSoftware.xcodeproj"
log "DerivedData: $DERIVED_DATA"
echo ""

XCODE_ARGS=(
    test
    -project "$WORKTREE_DIR/PaintSoftware.xcodeproj"
    -scheme PaintSoftware
    -destination "platform=iOS Simulator,id=$SIM_UUID"
    -derivedDataPath "$DERIVED_DATA"
)

if [ -n "$TEST_FILTER" ]; then
    XCODE_ARGS+=(-only-testing:"PaintSoftwareUITests/$TEST_FILTER")
    log "Filter: $TEST_FILTER"
fi

xcodebuild "${XCODE_ARGS[@]}" 2>&1
EXIT_CODE=$?

echo ""
log "Done (exit code: $EXIT_CODE)"
exit "$EXIT_CODE"
