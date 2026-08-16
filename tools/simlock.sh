#!/bin/bash
# Run a command while holding one of N test slots, so concurrent sessions queue instead of
# saturating the machine.
#
# **Why this exists.** CLAUDE.md tells each session to take a simulator of its own, which prevents
# sessions from erasing each other's device — but it says nothing about how many may run at once,
# and `pgrep -fl xcodebuild` as a check fails exactly when it matters: six agents each look, each
# see an idle machine, and all six start. Measured 2026-08-16 with that guidance in force and every
# session obeying it: 8 cores, 5 booted simulators, 5 concurrent `xcodebuild` runs, 1-3% idle. Under
# that load an XCUITest suite does not merely run slowly, it produces *wrong answers* — a shape-hold
# test failed and passed on the same binary depending on contention, and an agent spent a cycle
# diagnosing a threshold constant against what was really CPU starvation.
#
# The device name `eraser-mutex-test` has implied a mutex since long before one existed. This is it.
#
# **Why slots rather than one exclusive lock.** The fast logic tier is ~250 s of work and the full
# UI suite is ~19 min (CLAUDE.md's cost model). Serialising everything would make three agents' logic
# runs take 12 minutes of wall clock for 4 minutes of work. Two slots keeps both cores-per-run and
# throughput reasonable on an 8-core machine; raise SIMLOCK_SLOTS on a bigger one.
#
# **Why mkdir and not flock.** macOS ships no flock(1). `mkdir` is atomic on every filesystem this
# repo will see, which is the whole requirement.
#
# Usage:
#   tools/simlock.sh xcodebuild test -project ... -destination ...
#   SIMLOCK_SLOTS=3 tools/simlock.sh ./some-long-run.sh
#
# Waits indefinitely by default; set SIMLOCK_TIMEOUT to bound it (exit 75 on timeout, the
# conventional EX_TEMPFAIL, so a caller can tell "never ran" from "ran and failed").

set -uo pipefail

SLOTS="${SIMLOCK_SLOTS:-2}"
TIMEOUT="${SIMLOCK_TIMEOUT:-0}"
LOCK_ROOT="${SIMLOCK_ROOT:-/tmp/paintapp-simlock}"

[ $# -gt 0 ] || { echo "simlock: no command given" >&2; exit 64; }

mkdir -p "$LOCK_ROOT"
held=""

release() {
    [ -n "$held" ] && rm -rf "$held"
    held=""
}
trap 'release' EXIT INT TERM

# A slot whose owning process is gone is debris from a run that was killed rather than finishing.
# Reclaim it: the alternative is that one ^C wedges the machine for every later session.
reap_stale() {
    for dir in "$LOCK_ROOT"/slot.*; do
        [ -d "$dir" ] || continue
        pid=$(cat "$dir/pid" 2>/dev/null) || continue
        [ -n "$pid" ] || continue
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "simlock: reclaiming slot from dead pid $pid" >&2
            rm -rf "$dir"
        fi
    done
}

waited=0
while :; do
    reap_stale
    for i in $(seq 1 "$SLOTS"); do
        if mkdir "$LOCK_ROOT/slot.$i" 2>/dev/null; then
            held="$LOCK_ROOT/slot.$i"
            echo "$$" > "$held/pid"
            date +%s > "$held/since"
            break
        fi
    done
    [ -n "$held" ] && break

    if [ "$TIMEOUT" -gt 0 ] && [ "$waited" -ge "$TIMEOUT" ]; then
        echo "simlock: no slot after ${waited}s (${SLOTS} in use)" >&2
        exit 75
    fi
    # Poll at 1 s, not 5: the timeout is checked once per iteration, so a coarser sleep silently
    # rounds SIMLOCK_TIMEOUT up to the sleep interval and a short timeout can never fire at all.
    [ $((waited % 60)) -eq 0 ] && echo "simlock: all $SLOTS slots busy, waiting…" >&2
    sleep 1
    waited=$((waited + 1))
done

echo "simlock: acquired $(basename "$held") after ${waited}s" >&2
"$@"
status=$?
release
exit $status
