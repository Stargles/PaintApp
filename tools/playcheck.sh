#!/bin/bash
# **The install gate: the owner's playcheck, judged on the real memory of the render server and the app.**
#
#   tools/playcheck.sh <simulator-udid> [extra xcodebuild args, e.g. -configuration Release]
#
# Erases and boots the simulator (an iPad (9th generation) one — the owner's device), so its
# `backboardd` starts fresh and its peak is this run's; samples that `backboardd` and the app once a
# second from the Mac (tools/sim-footprint-sampler.sh); runs `PlaycheckGateUITests` against the
# samples (TEST_RUNNER_PLAYCHECK_FOOTPRINT_CSV), which asserts the budgets after every phase; then
# checks that exactly one test ran and passed. Exit 0 is green. No install without it (CLAUDE.md).
# Evidence goes to $PLAYCHECK_OUT (default ~/PaintWork/playcheck-<udid>), deleted by the caller.
set -u
UDID=${1:?usage: tools/playcheck.sh <simulator-udid> [xcodebuild args]}; shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${PLAYCHECK_OUT:-$HOME/PaintWork/playcheck-$UDID}
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$ROOT"

xcrun simctl shutdown "$UDID" 2>/dev/null
xcrun simctl erase "$UDID" || exit 1
xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b >/dev/null || exit 1

ARGS=(-project PaintSoftware.xcodeproj -scheme PaintSoftware -destination "platform=iOS Simulator,id=$UDID"
      -derivedDataPath build/DerivedData "$@")
# Built first, so the sampler's file is fresh when the test starts reading it.
tools/simlock.sh xcodebuild build-for-testing "${ARGS[@]}" > "$OUT/build.log" 2>&1 \
    || { echo "playcheck: BUILD FAILED — $OUT/build.log"; exit 1; }

tools/sim-footprint-sampler.sh "$UDID" "$OUT/footprint.csv" &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT
TEST_RUNNER_PLAYCHECK_FOOTPRINT_CSV="$OUT/footprint.csv" tools/simlock.sh xcodebuild test-without-building "${ARGS[@]}" \
    -resultBundlePath "$OUT/playcheck.xcresult" -only-testing:PaintSoftwareUITests/PlaycheckGateUITests -parallel-testing-enabled NO > "$OUT/test.log" 2>&1
kill $SAMPLER 2>/dev/null

grep "^PLAYCHECK " "$OUT/test.log"
SUMMARY=$(xcrun xcresulttool get test-results summary --path "$OUT/playcheck.xcresult" 2>/dev/null)
TOTAL=$(echo "$SUMMARY" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("totalTestCount",0), d.get("passedTests",0))' 2>/dev/null)
if [[ "$TOTAL" != "1 1" ]]; then
    grep -E "error:|failed" "$OUT/test.log" | head -20
    echo "playcheck: RED — tests run/passed: ${TOTAL:-none}; log $OUT/test.log"
    exit 1
fi
echo "playcheck: GREEN — evidence in $OUT"
