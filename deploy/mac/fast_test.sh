#!/usr/bin/env bash
# Run the test suite with XCTest's per-class parallelisation.
#
# The UI tests used to live in one 63-test class. XCTest parallelises by test *class*, so a single
# class meant a single worker and the suite ran serially at ~22 minutes, with the 63 XCUITest cases
# accounting for 99.3% of that. They are now split across five classes (see PaintUITestCase.swift),
# which lets Xcode fan them out over cloned simulators.
#
# Usage:
#   deploy/mac/fast_test.sh                          # whole suite, parallel
#   deploy/mac/fast_test.sh FillUITests              # one class
#   deploy/mac/fast_test.sh FillUITests/testRedoRestoresUndoneFill   # one test
#
# Env overrides: SIM (device name), WORKERS (parallel worker count), DD (derived data path).
#
# Measured on this Mac (M1 Pro, 6 performance + 2 efficiency cores, 16 GB), 2026-07-29:
#   serial (one class):   1231 s test execution
#   parallel, 5 workers:   611 s test execution, 192 passed / 0 failed / 1 skipped
# i.e. ~2x, not the ~5x the worker count suggests. The five UI classes are already well balanced
# (318 / 313 / 308 / 292 / 225 s), so the gap is not scheduling — it is simulator clone startup
# (~2-3 min before the first test completes) plus CPU and memory contention between five concurrent
# Metal-rendering simulators. WORKERS=5 is at or near this machine's ceiling; raising it will likely
# make things worse, not better. A machine with more cores and RAM would get closer to the ~318 s
# floor set by the slowest class.

set -euo pipefail
cd "$(dirname "$0")/../.."

SIM="${SIM:-iPad Pro 13-inch (M5)}"
WORKERS="${WORKERS:-5}"
DD="${DD:-/tmp/paintapp-dd-$(basename "$PWD")}"

ONLY=()
for filter in "$@"; do
  ONLY+=("-only-testing:PaintSoftwareUITests/$filter")
done

# Worth knowing: the pure-logic suites (BrushEngineLogicTests, ShapeDetectorLogicTests,
# BackupManagerLogicTests, the three *CharacterizationTests, PerfBaselineTests) are ~130 tests that
# finish in seconds because they never launch the app. If you only need those, name them explicitly
# rather than running everything — that turns a multi-minute wait into a few seconds.

start=$(date +%s)
xcodebuild test \
  -project PaintSoftware.xcodeproj \
  -scheme PaintSoftware \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DD" \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers "$WORKERS" \
  "${ONLY[@]}"
status=$?

echo "elapsed: $(( $(date +%s) - start ))s"
exit $status
