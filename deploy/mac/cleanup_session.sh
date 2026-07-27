#!/bin/bash
# Clean up a session's worktree, DerivedData, and any held simulator locks.
#
# Usage: cleanup_session.sh <session-id>
#        cleanup_session.sh --all    (clean up everything)

set -euo pipefail

MAIN_REPO="$HOME/PaintApp"
WORKTREE_BASE="$HOME/PaintApp-worktrees"
DERIVED_BASE="$HOME/PaintApp-derived"
LOCK_DIR="/tmp/paintapp-sim-locks"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

if [ "${1:-}" = "--all" ]; then
    log "Cleaning up ALL sessions"

    # Release all simulator locks
    if [ -d "$LOCK_DIR" ]; then
        rm -rf "$LOCK_DIR"/*
        log "Cleared all simulator locks"
    fi

    # Remove all worktrees
    if [ -d "$WORKTREE_BASE" ]; then
        for dir in "$WORKTREE_BASE"/*/; do
            [ -d "$dir" ] || continue
            name=$(basename "$dir")
            log "Removing worktree: $name"
            git -C "$MAIN_REPO" worktree remove "$dir" --force 2>/dev/null || rm -rf "$dir"
        done
        rmdir "$WORKTREE_BASE" 2>/dev/null || true
    fi

    # Remove all DerivedData
    if [ -d "$DERIVED_BASE" ]; then
        rm -rf "$DERIVED_BASE"
        log "Removed all DerivedData"
    fi

    log "All sessions cleaned up"
    exit 0
fi

SESSION_ID="${1:?Usage: cleanup_session.sh <session-id> | cleanup_session.sh --all}"
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-' | head -c 64)

WORKTREE_DIR="$WORKTREE_BASE/$SESSION_ID"
DERIVED_DATA="$DERIVED_BASE/$SESSION_ID"

# Release any held locks
if [ -d "$LOCK_DIR" ]; then
    for lock in "$LOCK_DIR"/*/; do
        [ -d "$lock" ] || continue
        if [ -f "$lock/info" ] && grep -q "^${SESSION_ID}:" "$lock/info" 2>/dev/null; then
            log "Releasing lock: $(basename "$lock")"
            rm -rf "$lock"
        fi
    done
fi

# Remove worktree
if [ -d "$WORKTREE_DIR" ]; then
    log "Removing worktree: $WORKTREE_DIR"
    git -C "$MAIN_REPO" worktree remove "$WORKTREE_DIR" --force 2>/dev/null || rm -rf "$WORKTREE_DIR"
fi

# Remove DerivedData
if [ -d "$DERIVED_DATA" ]; then
    log "Removing DerivedData: $DERIVED_DATA"
    rm -rf "$DERIVED_DATA"
fi

log "Session '$SESSION_ID' cleaned up"
