# Performance baseline

Current numbers, and the measurement traps that made earlier ones wrong. Measured on an iPad Pro
13-inch (M5) simulator, iOS 26.5, medians of 3 runs, path length held fixed.

Re-measure with:

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:PaintSoftwareUITests/PerfBaselineTests
```

`report(_:_:)` emits every `PERF BASELINE` line as an `XCTAttachment` with `.keepAlways`, because a
`print` goes to the *simulator's* console on a throwaway clone that is deleted with the run. Read
them back with `xcrun xcresulttool export attachments --path <…>.xcresult --output-path /tmp/att`.
The assertions in that file are loose order-of-magnitude ceilings — judge a change by the printed
numbers, not by whether the test passed.

## Where it stands

| Measurement | before | now | |
|---|---|---|---|
| One 500-sample stroke, end to end | 27.6 ms | **6.5 ms** | 4.2× |
| 20 consecutive 200-sample strokes, mean | 28.2 ms | **6.1 ms** | 4.3× |
| Thumbnail rasterizes per completed stroke | 1 | **0** (1 per 400 ms idle) | |
| Footprint growth over 20 strokes | 0.0 MB | **0.0 MB** | flat |
| Path-length scaling, 1× vs 4× (ideal 4.00×) | 3.04× | **4.07×** | |
| Vector layer first render, 20 strokes | 70.9 ms | **63.6 ms** | 1.11× |
| Vector layer render, peak footprint delta | 48.1 MB | **16.0 MB** | 3.0× |
| Undo cost, small localised stroke | 32.0 MB | **17,680 bytes** | ~1,900× |
| Undo cost, canvas-spanning sweep | 32.0 MB | **24.9 MB** | 1.29× |
| Small strokes held in the 300 MB undo budget | 9 | **40 of 40** (~0.7 MB) | |
| Dab gradient cache hit rate | n/a | **100.0%** (2635/2636 dabs) | |
| Erase-heavy scene, mean of the last ten gestures | 52.5 ms | **30.2 ms** | 1.74× |
| Full suite, wall clock | 1231 s serial | **541 s** parallel, 5 workers | |

The erase-heavy scene is 200 strokes on a 2048² vector layer, 49 measured eraser gestures, ending at
426 elements (376 paint strokes, 352 of them split pieces, plus 50 retained punches).

## Traps — read before measuring anything

1. **Cost is set by path length, not sample count.** `BrushStamper.stampStroke` derives dabs from
   `distance ÷ (brushSize × spacingFraction)`, so quadrupling samples over the same path costs
   1.00×. Any comparison that does not hold path length fixed measures nothing.
2. **Measure inside an explicit `autoreleasepool`.** `renderToUIImage()` materializes a
   canvas-sized CGImage (16 MB) per regeneration; the app's run loop drains those, a test method
   does not. Without a pool you get ~16 MB/stroke of phantom growth (measured: 322 MB over 20
   strokes) and read it as a leak. `PerfBaselineTests.stamp` pools deliberately.
3. **`UIGraphicsImageRendererFormat.preferredRange` defaults to `.automatic`**, which on a
   wide-colour iPad means an extended-range 16-bit context — it cost one change a 2.2× wall-clock
   regression that a memory win would have hidden, and it silently doubles any buffer whose bytes
   you are accounting for. Pin `.standard` wherever dabs are rasterized or byte cost matters.
4. **`CGImage.cropping(to:)` keeps a reference to the parent's pixel data**, so a crop taken to
   shrink what something retains shrinks nothing. `PixelOps.copiedSubimage` renders into a fresh
   buffer for exactly this reason.
5. **Absolute footprint depends on what ran before in the same process; deltas do not.** The same
   tests start at 68.8 MB isolated and 98.1 MB in the full suite, with every delta matching to
   within noise. Compare deltas.
6. **Read counts from the `.xcresult`, never from the text log.** Parallel workers tear each
   other's lines; grepping once undercounted 192 as 189.
7. **Warm-up contamination is real and one-sided-looking.** Roughly 5 runs in 12 start slow (first
   ten gestures at 56–154 ms instead of 23–26 ms) and begin at a higher footprint. It happens on
   both sides of a comparison and decays. Judge by `meanOfLastTen`, and treat any run whose
   `footprintBefore` is out of line as contaminated in its first-ten figures.
8. **Single-run differences under ~2× are noise.** Re-measuring an untouched ratio gave 0.81× where
   an earlier single run recorded 1.00×.

## Known remaining costs

1. **`StrokeSpatialIndex` is rebuilt from scratch on every `invalidate()`** — 7.2 ms over 11,800
   segments to answer a query returning 7 strokes, two to three times per erase gesture. The largest
   single term left, and fixable without touching any eraser decision: the passes append and remove
   at known indices, so the index could be patched rather than rebuilt. Belongs with a dirty-rect
   cache, which wants the same "what changed where" information.
2. **`maxPaintReach()` is O(elements) and is called three times per gesture.** Free the moment
   stroke bounds are cached.
3. **The eraser's deletion and split passes are deliberately *not* merged.** The duplicated geometry
   is at most 1.0 ms of a ~38 ms gesture, and usually far less because `isEntirelyCovered`
   short-circuits on two cheap cap tests before reaching `cleanCutRanges` — so for a stroke being
   split rather than deleted the clean-cut walk only ever ran once. Merging them is a behaviour
   change, not a refactor (`isEntirelyCovered` demands one span covering the domain where the split
   path accepts two abutting ones).
