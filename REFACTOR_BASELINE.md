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

### After Stage 0's additions

Re-run at the end of this stage, with the 61 characterization tests and 5 perf tests in:

| | |
|---|---|
| Executed | **184** |
| Passed | **183** |
| Failed | **0** |
| Skipped | **1** (the same pre-existing one) |
| Test-execution wall clock | **1220.9 s** (20 m 21 s) |

| Suite | Tests | Failures | Seconds |
|---|---|---|---|
| `PaintSoftwareUITests` (XCUITest, end-to-end) | 63 | 0 (1 skipped) | 1211.8 |
| `ShapeDetectorLogicTests` | 27 | 0 | 1.7 |
| `CelCRUDCharacterizationTests` *(new)* | 26 | 0 | 1.7 |
| `ViewPresetCharacterizationTests` *(new)* | 19 | 0 | 1.2 |
| `LayerTreeCharacterizationTests` *(new)* | 16 | 0 | 1.0 |
| `BackupManagerLogicTests` | 15 | 0 | 1.2 |
| `BrushEngineLogicTests` | 13 | 0 | 0.8 |
| `PerfBaselineTests` *(new)* | 5 | 0 | 1.5 |

66 tests added for **&minus;10.5 s** of wall clock (run-to-run noise in the XCUITest suite dwarfs
them). A later stage can therefore run every non-XCUITest suite as a fast inner loop — all 121 of
them finish in about 9 seconds — and save the 20-minute end-to-end pass for pre-commit.

## Performance baseline

Measured by `PaintSoftwareUITests/PerfBaselineTests.swift`, which drives synthetic strokes through
the real pipeline (`StrokeStabilizer` → `BrushStamper.stampStroke` → `RasterLayerTexture` →
`CanvasManager.strokeEnded`) on a 2048×2048 canvas. It does **not** include UIKit touch delivery or
`CADisplayLink` presentation — no headless harness can reproduce those faithfully.

### As measured, 2026-07-28

| Measurement | Value |
|---|---|
| One 500-sample stroke, end to end | **27.6 ms** (0.055 ms/sample; the log line rounds that to 0.1) |
| Peak footprint delta during that stroke | **0.0 MB** (68.8 MB before, 68.8 MB peak) |
| Thumbnail regenerations per completed stroke | **1** |
| One thumbnail rasterize (2048×2048) | **4.4 ms** — ~16% of a stroke |
| 50 × `scheduleThumbnailRegen`, synchronous cost | **0.3 ms**, **0** rasterizes (debounce holds) |
| 20 consecutive 200-sample strokes, mean | **28.2 ms** each |
| Footprint growth over those 20 strokes | **0.0 MB** (68.7 → 68.6 MB) |
| Same path at 250 vs 1000 samples | 27.3 → 27.4 ms, **1.00×** |
| 1× vs 4× path length, same sample count | 26.8 → 81.5 ms, **3.04×** (ideal 4.00×) |

Four things a later stage should carry forward from these numbers:

1. **Cost is set by path length, not sample count.** `BrushStamper.stampStroke` derives its dab
   count from `distance ÷ (brushSize × spacingFraction)` per segment, so quadrupling the samples
   over the same path costs 1.00× — thinning input samples buys nothing. Any before/after
   comparison must hold path length fixed or it measures nothing. Scaling with path length is
   3.04× for 4× the path: linear, slightly sublinear from fixed per-stroke overhead.
2. **Thumbnail regeneration is 4.4 ms of the 27.6 ms stroke** and rasterizes the entire cel. It
   fires exactly once per completed stroke today; if a decomposition makes it fire per dab or per
   layer, `testSyntheticStrokeBaseline` fails on the count, not on a timing threshold.
3. **Steady-state memory is flat.** The cel's `RasterLayerTexture` is written in place, so repeated
   strokes plateau. Growth over 20 strokes is 0.0 MB.
4. **Beware the autorelease artifact when re-measuring.** `renderToUIImage()` materializes a
   canvas-sized CGImage (16 MB here) per regeneration. The app's run loop drains those every turn;
   a test method does not, so measuring without an explicit `autoreleasepool` reports ~16 MB/stroke
   of phantom growth (measured: 322 MB over 20 strokes). `PerfBaselineTests.stamp` pools
   deliberately — do not remove it and then read the growth number as a leak.

These are simulator numbers on an idle host, single-run, not averaged across runs. Treat a change
under ~2× as noise.

**Absolute footprint depends on what ran before it in the same process; the deltas do not.** The
table above is from an isolated `-only-testing:PerfBaselineTests` run, which starts at 68.8 MB. In
the full-suite run the same tests start at 98.1 MB, because the 63 XCUITest cases ran first in that
process. Timings and every delta match to within noise (27.6 vs 28.0 ms per stroke, 4.4 vs 4.7 ms
per thumbnail, 3.04× vs 2.94× path scaling, 0.0 vs 0.1 MB growth). Compare deltas, not the
starting footprint, and re-measure the way this table was measured.



To re-measure:

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:PaintSoftwareUITests/PerfBaselineTests
```

Then read the `PERF BASELINE |` lines out of the test log. The assertions in that file are
deliberately loose order-of-magnitude ceilings (simulator timings swing with host load) — they
catch catastrophic regressions only. Judge a performance change by the printed numbers, not by
whether the test passed.
