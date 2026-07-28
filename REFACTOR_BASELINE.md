# Refactor baseline (Stage 0)

Hand-off numbers for the six-stage CanvasManager/CanvasView refactor. Every later stage branches
off `session/refactor`; none of those sessions can see this session's test output, so the numbers
live here.

**Do not edit the "as measured" numbers.** They are the "before" side of the comparison. Add new
rows below them as later stages re-measure.

## Environment

| | |
|---|---|
| Measured | 2026-07-28 |
| Branch | `session/refactor` off `origin/main` @ `9d16baa` |
| Xcode | 26.6 (17F113) |
| Simulator | iPad Pro 13-inch (M5), iOS 26.5 — dedicated clone `refactor-ipad` |
| Command | `xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=…'` |

Run locally on the Mac. The Tailscale/remote-Mac path in [CLAUDE.md](CLAUDE.md) is for the Windows
machine and was not used.

## Full-suite baseline

| | |
|---|---|
| Executed | **118** |
| Passed | **117** |
| Failed | **0** |
| Skipped | **1** |
| Test-execution wall clock | **1231.4 s** (20 m 31 s) |
| Build + test wall clock | **1328 s** (22 m 8 s) |

Per suite:

| Suite | Tests | Failures | Seconds |
|---|---|---|---|
| `PaintSoftwareUITests` (XCUITest, end-to-end) | 63 | 0 (1 skipped) | 1222.4 |
| `ShapeDetectorLogicTests` (pure logic) | 27 | 0 | 1.7 |
| `BackupManagerLogicTests` (pure logic) | 15 | 0 | 5.4 |
| `BrushEngineLogicTests` (pure logic) | 13 | 0 | 1.9 |

The skip is `testFillToolBridgesOpenContourGapWhenGapClosingEnabled`, a pre-existing
`XCTSkip("Disabled pending investigation — see BUGS.md")` — not a new drift.

### Drift against the last recorded baseline

[SESSION_LOG.md](SESSION_LOG.md) session 50 recorded **106 tests, 1 skipped, 0 failures**. This run
is **118 / 1 skipped / 0 failures**. The +12 is exactly the 12 tests session 51 added; that session
only ran a targeted 44-test subset, so this is the first full-suite run since. **No behavioral
drift — nothing regressed, nothing was lost.**

Note the shape of that number: 63 of 118 tests are XCUITest end-to-end tests and account for 99.3%
of the runtime. The characterization tests added in this stage are pure-logic and run in
milliseconds.

## Performance baseline

Measured by `PaintSoftwareUITests/PerfBaselineTests.swift`, which drives synthetic strokes through
the real pipeline (`StrokeStabilizer` → `BrushStamper.stampStroke` → `RasterLayerTexture` →
`CanvasManager.strokeEnded`) on a 2048×2048 canvas. It does **not** include UIKit touch delivery or
`CADisplayLink` presentation — no headless harness can reproduce those faithfully.

<!-- PERF NUMBERS INSERTED BY THE PERF-HARNESS COMMIT -->

To re-measure:

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:PaintSoftwareUITests/PerfBaselineTests
```

Then read the `PERF BASELINE |` lines out of the test log. The assertions in that file are
deliberately loose order-of-magnitude ceilings (simulator timings swing with host load) — they
catch catastrophic regressions only. Judge a performance change by the printed numbers, not by
whether the test passed.
