#!/bin/bash
# Optimised standalone harness over Engine/Deform — the registration cost curve, in seconds.
#
# The Deform module imports only Accelerate, CoreGraphics and Foundation (standing constraint A),
# so it compiles and runs natively with no simulator, no app and no test host. That is what makes
# it usable for numerical work: an experiment loop here is ~5s, against ~90s through `xcodebuild
# test`, and the test tier builds unoptimised so its wall-clock numbers are meaningless anyway
# (a 121-sample fit: 0.6s optimised, 598s in the test tier).
#
# Usage: bash deploy/interp-registration-benchmark/run.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
E="$ROOT/PaintSoftware/Engine/Deform"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/bench" "$HERE/main.swift" \
    "$E/Lattice.swift" "$E/DeformFactorization.swift" "$E/ARAPRegistration.swift" \
    "$E/ARAPInterpolation.swift" "$E/MotionGrouping.swift"
"$OUT/bench"
