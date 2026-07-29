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

---

## Suite parallelisation (2026-07-29, between Stage 3 and Stage 4)

The 63 XCUITest cases used to live in **one** class. XCTest parallelises by test *class*, so the
suite had exactly one unit of schedulable work and ran serially regardless of how many simulators
were free. They are now split across five classes over a shared `PaintUITestCase` base (all 63 test
bodies byte-identical; the only edit to any helper was `private` -> internal, since subclasses now
live in other files).

Run with `deploy/mac/fast_test.sh`, or `-parallel-testing-enabled YES -maximum-parallel-testing-workers 5`.

| | Serial (before) | Parallel, 5 workers (after) |
|---|---|---|
| Test-execution wall clock | **1231.4 s** | **611.4 s** |
| Passed / failed / skipped | 117 / 0 / 1 (118 total) | **192 / 0 / 1** (193 total) |

**~2.0x.** Not the ~5x the worker count implies, and the reason is not class imbalance — the five
UI classes come out at 318 / 313 / 308 / 292 / 225 s, which is about as even as name-based grouping
gets. The remaining cost is simulator clone startup (2-3 minutes before the first test completes)
plus contention between five concurrent Metal-rendering simulators on an 8-core / 16 GB M1 Pro.
The floor on this hardware is the slowest class, ~318 s.

### Counting caveat, if you are reading a text log

Concurrent workers interleave their writes into the same stream, which **tears individual lines**
(`Test c` + a timestamp + `ase '...' passed`). Grepping the log therefore undercounts — it reported
189/1 for a run that actually passed 192/1. Take counts from the `.xcresult` bundle instead:

```
xcrun xcresulttool get test-results summary --path <DerivedData>/Logs/Test/<bundle>.xcresult
```

### What this means for later stages

The ~130 pure-logic tests (characterization, shape-detector, brush-engine, backup, perf) never
launch the app and total **~30 s**; the 63 XCUITest cases are still ~98% of the runtime. Naming the
logic suites directly is a far bigger win than parallelism for per-item verification — seconds
instead of minutes. Reserve the full parallel run for the pre-push check.

---

## Stage 5 (2026-07-29) — after

Same machine and simulator as Stage 0 (iPad Pro 13-inch (M5), iOS 26.5). Every row below is the
**median of 3 runs** per side, not a single sample: the Stage 0 table's own caution that a change
under ~2x is noise turned out to understate it for single runs (re-measuring the untouched
250-vs-1000-sample ratio gave 0.81x where Stage 0 recorded 1.00x). Path length was held fixed in
every comparison, per trap 1. Memory was measured inside an explicit `autoreleasepool`, per trap 2.

### Live stroke cost

The "Stage 0 recorded" column is that stage's own figure, reproduced here for continuity. The
ratio is computed from **re-measured**, i.e. this session's own baseline run of the unmodified
pre-5.1 code, so the whole chain comes from one measurement session on one machine state rather than
mixing two. The two baselines agree to within noise, which is itself the check that this
environment reproduces Stage 0's.

| Measurement | Stage 0 recorded | re-measured | after 5.1 | after 5.2 | Ratio |
|---|---|---|---|---|---|
| One 500-sample stroke, end to end | 27.6 ms | 27.1 ms | 14.8 ms | **6.5 ms** | **4.2x** |
| 20 consecutive 200-sample strokes, mean | 28.2 ms | 26.2 ms | 13.2 ms | **6.1 ms** | **4.3x** |
| Thumbnail rasterizes per completed stroke | 1 | 1 | 1 | **0** (1 per 400 ms idle) | |
| Footprint growth over 20 strokes | 0.0 MB | 0.0 MB | 0.0 MB | **0.0 MB** | unchanged |
| Path-length scaling, 1x vs 4x (ideal 4.00x) | 3.04x | 3.02x | 2.02x | **4.07x** | |

That last row is corroboration rather than a target: removing a *fixed* per-stroke cost is exactly
what makes the remaining cost purely dab-proportional, so 5.2 moving it to 4.07x against an ideal of
4.00x is independent evidence the thumbnail really did leave the per-stroke path.

Per-run spread on the single-stroke figure: Stage 0 side 27.1 / 27.0 / 27.7, after-5.1 side
14.8 / 13.9 / 15.0, after-5.2 side 6.8 / 6.5 / 6.5. No overlap between any two stages, so each step
is well clear of the noise floor.

### Other paths

| Measurement | before | after | |
|---|---|---|---|
| Vector layer first render, 20 strokes (5.3) | 70.9 ms | **63.6 ms** | 1.11x |
| Vector layer render, peak footprint delta (5.3) | 48.1 MB | **16.0 MB** | **3.0x** |
| Undo cost, small localised stroke (5.5) | 32.0 MB | **17,680 bytes** | ~1,900x |
| Undo cost, canvas-spanning sweep (5.5) | 32.0 MB | **24.9 MB** | 1.29x |
| Small strokes retained in the 300 MB budget (5.5) | **9** | 40 of 40 recorded (~0.7 MB) | |
| Dab gradient cache hit rate (5.1) | n/a | **100.0%** (2635 hits / 1 miss / 2636 dabs) | |

The 5.3 memory figure was identical across all three reps on both sides, so it is structural (one
canvas-sized buffer per render instead of three), not sampling. The two 5.5 rows are both reported
deliberately: dirty-rect cropping helps in proportion to how *localised* a stroke is, so quoting only
the first row would overstate it.

### Three things later work should carry forward

1. **`UIGraphicsImageRendererFormat.preferredRange` defaults to `.automatic`, which on a wide-colour
   iPad means an extended-range 16-bit-per-component context.** This cost 5.3 a 2.2x wall-clock
   regression (155 ms vs the old 70 ms) that the memory win would have hidden, and it silently
   doubles the size of any buffer whose bytes you are accounting for (5.5's undo patches). Pin
   `.standard` anywhere dabs are rasterized or a buffer's byte cost matters — `RasterLayerTexture`
   was always explicitly 8-bit deviceRGB, which is why this never showed up before.
2. **`CGImage.cropping(to:)` keeps a reference to the parent's pixel data.** A "crop" used to shrink
   what something retains does not shrink anything. `PixelOps.copiedSubimage` renders into a fresh
   buffer for this reason.
3. **Stage 0's 4.4 ms "one thumbnail rasterize" understated the real per-stroke cost.** It timed a
   *second* consecutive regen, whose `renderToUIImage()` was already cached. The regen that follows a
   stroke pays an uncached full-canvas `makeImage()` plus the `@Published layers` republish, and
   measures 5.9-7.8 ms — which is why 5.2 recovered 8.3 ms, not 4.3 ms.

### Full suite

| | Stage 0 | Stage 4 | Stage 5 |
|---|---|---|---|
| Passed | 183 | 198 | **213** |
| Failed | 0 | 0 | **0** |
| Skipped | 1 | 1 | **1** (the same pre-existing one) |
| Total | 184 | 199 | **214** |
| Wall clock | 1220.9 s (serial) | 611.4 s (parallel) | **541 s** (parallel, 5 workers) |

+15 over Stage 4 is exactly the 15 tests this stage added. **Counts read from the `.xcresult`
bundle, never from the text log** — parallel workers tear each other's lines and grepping undercounts
(the caveat above reported 189 for a run that passed 192).
