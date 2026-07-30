# Vector Eraser — Resume Here

Working state as of **Session 6 (2026-07-30)**. Read [VECTOR_ERASER_PLAN.md](VECTOR_ERASER_PLAN.md)
first — it is the spec, and §1/§4/§7/§8 match what actually shipped. This file is only the bookmark.

## Environment correction (important, saves 10 minutes)

CLAUDE.md's "Remote testing (Tailscale → Mac, no Xcode on this machine)" section was written for the
**Windows** machine. If your session is on `Julias-MacBook-Pro` (darwin), you *are* the Mac: Xcode is
local, no SSH, no `parallel_test.sh`. Build directly, ~20s:

```bash
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser
```

Logic tests (**171** currently green — this is the regression net):

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser -only-testing:PaintSoftwareUITests/VectorEraserLogicTests -only-testing:PaintSoftwareUITests/VectorEraserHybridLogicTests -only-testing:PaintSoftwareUITests/StrokeGeometryLogicTests -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ProjectSaveLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/RasterVectorParityLogicTests
```

UI tests (`VectorEraserUITests`, 8 tests; `VectorShapeAndRecoveryUITests`) — same command with those
suites added. They are slow: **~35–45 s each**, so budget several minutes and run them in the
background. The full green run at Session 6's end was **190 tests, 0 failures**.

**xcodebuild does not print assertion messages to stdout.** A failure line names the test and nothing
else. To read the actual message:

```bash
xcrun xcresulttool get test-results test-details --test-id "SuiteName/testName()" --path /tmp/dd-veraser/Logs/Test/<newest>.xcresult
```

`print()` from a test does not reach stdout either — it goes to the simulator's console. To get a
value out of a running test, put it in an `XCTFail` message.

Expect one or two `FBSOpenApplicationServiceErrorDomain` / `(ipc/mig) server died` launch failures
per run. xcodebuild retries and the run completes; they are not a broken simulator and do not need a
restart.

Phases 0–3 are described in the git history (`b6d8ede` and its parents) and have not changed.

---

## Mode 1, as it actually is

One sentence: **the eraser gesture is retained whole as an `.erase` punch, a stroke it covers end to
end is deleted outright, and nothing is ever cut partway.**

That is not what plan §1 originally proposed, and the difference is the most valuable thing in this
file. Two sessions of measurement produced it.

**Session 4** built `RasterVectorParityLogicTests` — plan §8's acceptance test — which renders a
scene twice, once by stamping into a `RasterLayerTexture` and erasing it and once as a `VectorCanvas`
display list, and compares premultiplied RGBA bytes. It established that **a retained `.erase`
element is byte-identical to raster erasing**: `maxChannelDelta == 0` across all 36 matrix cases. The
feared 1–2 LSB colour-space drift between `RasterLayerTexture`'s 8-bit deviceRGB context and
`renderLocalContent`'s renderer does not exist. Session 4 then wrote the hybrid commit on that
foundation.

**Session 5** wrote `VectorEraserHybridLogicTests`, which drives the real `VectorCanvas.erase` rather
than hand-built display lists, and found the commit did not do what it claimed. Four defects, all
fixed in `fd7c258`:

1. **Trimming the punch to the spans with a backdrop is not pixel-exact.** `residueSpans` is now
   `hasResidue` — a bit, not a set of spans — and the punch carries the gesture whole.
2. **The alpha gate was dead.** It judged `opacityPressure` at pressure 0, which no shipped brush
   survives. It now takes the gesture's own minimum pressure.
3. **`cleanCutRanges` returned per-segment fragments**, so the inset collapsed every one and the
   geometric path silently never fired.
4. **The partial split cannot be made pixel-exact at all**, and is gone.

### The one thing to understand before touching any of this

`BrushStamper.stampStroke` anchors **two** things at `samples[0]`: the **dab lattice** (dabs every
`stampSpacing`, carrying the remainder across segments) and the **pressure ramp** (`lastPressure`
starts there). So *any* sub-run of a stroke, re-stamped on its own, puts its ink somewhere new along
its entire length — not merely near where it was cut.

Defects 1 and 4 are both that fact, arriving from different directions:

- Retaining only part of the eraser's gesture re-phases the punch's own dabs, including the ones over
  the ink that justified retaining it. Measured: 4/255 over 22 px for a hard round eraser crossing
  diagonally; 27/255 over 81 px for the same gesture at opacity 0.4.
- Cutting a stroke re-phases the surviving piece's dabs, most visibly at its **far tip** — the end
  furthest from the eraser, and therefore the one the punch cannot cover. Measured on a 24pt line
  with a 48pt nib: divergence across x ∈ [41, 115] where the punch covers only x ∈ [40, 88], leaving
  118 stray pixels at up to 183/255.

The intuition that says "the cut is hidden under the eraser, so it cannot be seen" is right about the
ink *at* the cut and wrong about the piece as a whole. Widening the eraser does not help: it moves
the artefact further away rather than covering it, because the artefact's size is set by the
*stroke's* spacing and width, not the eraser's.

**Whole-stroke deletion is exempt**, which is why it survived. Deleting produces no new geometry, so
nothing is re-stamped and nothing can land anywhere new. It is exact, and it is what keeps §1's
"scribble a stroke out and it costs nothing" true.

### Notes worth not re-deriving

- **`isEntirelyCovered` checks the end caps separately.** A stroke's round cap sticks out half a
  width past its last parameter, so every cross-section can be covered while the caps are not.
  `StrokeGeometry.capsules(_:contain:radius:)` is the disc-in-capsule test; it is sufficient rather
  than necessary (a disc straddling two capsules reads as uncovered), which errs toward keeping a
  stroke — the recoverable direction.
- **The alpha gate takes the gesture's minimum pressure.** `opacityFraction` bottoms out at
  `1 - opacityPressure`; `hardRound` ships with `0.1` and `pen` with `0.05`, so judging at pressure 0
  rejected every built-in brush. The call site has the pressures, and dab pressure interpolates
  linearly, so the minimum over samples is the minimum over dabs.
- **`coveredSpans` closes a run at every segment boundary** and leaves rejoining to a downstream
  `mergedCuts`. Mode 2 does that in `effectiveCuts`. Anything consuming spans *before* that merge
  must merge first — `cleanCutRanges` now does it itself.
- **Re-erasing the same place stacks punches**, deliberately: an eraser *is* a stroke, so N gestures
  cost N elements exactly as N paint strokes do. `hasContentBeneath` asks about stroke geometry, not
  about ink still visible after earlier punches. §1 asked that an erase which *fully resolves* cost
  nothing, which it does.
- **`conservativeCuts` is kept, tested, and unwired.** It correctly solves the round-cap-versus-band-
  edge lens (≈ `0.43·w²`), which is a real second problem — just not the one blocking splitting.

---

## What Session 6 did

**The last handoff's item 1 is closed: the eraser has now been run through the real UI.**
`PaintSoftwareUITests/VectorEraserUITests.swift`, 8 XCUITests, commit `b51ef79`. Nothing was
invalidated — the picker, Mode 1's punch and whole-stroke delete, the live preview, and Mode 3's
per-crossing sweep all behave as the logic tests said they would. Two supporting changes were needed,
worth knowing before writing more UI tests:

- **`LayerRowModel` reports paint strokes and `.erase` punches as separate counts**, surfaced as
  `layerPanel.row.N.vector` = `"isVector,paintStrokes,erasePunches"`. Against a single total, "the
  stroke was cut in two" and "a punch was added over it" are the same number.
  `testHeldStrokeOnVectorLayerBecomesAVectorStrokeTheEraserSplits` had been asserting `strokes == 2`
  after a Mode 1 erase and passing on 1 paint + 1 punch — i.e. measuring nothing since Phase 4c. It
  is renamed and now asserts the shipped semantics.
- **`StrokeCanvasView.lastVectorGestureTrace`** (`"<scratchRole>,<livePreviewFrames>"`), surfaced on
  `canvas.host`'s `accessibilityValue`. **A live preview cannot be observed by an XCUITest
  directly.** `press(forDuration:thenDragTo:)` asserts main-thread, so the test thread is blocked
  inside the gesture for its whole duration and every screenshot it can take is post-lift — where
  the commit has erased the same pixels and a sighting proves nothing. Running the gesture on a
  background queue is exactly what that assertion exists to prevent: it crashes the runner (it did,
  and took the next test in the class down with it). So the app counts the frames it published and
  the test reads the count afterwards. **Don't re-attempt the background-queue approach.**

Two more things learned about the UI harness:

- **`drawLine`'s fast flick delivers too few touch samples for Mode 3.** A sweep across three lines
  acted on only two of them, because Mode 3 resolves at the tip and needs a sample to land within
  the nib's footprint of each line. Use `dragOnCanvas` (slow velocity) and a wider eraser. This is a
  property of XCUITest's synthesized input, not of `IntersectionDriver` — which is covered
  sample-by-sample in `VectorEraserLogicTests` and is correct.
- **The eraser panel overlays the right of the canvas**, so close it before any canvas gesture.
  `selectVectorEraserMode` / `setEraserSize` in the test file both do open→act→close for this reason.

**Carry-over 2(b) is resolved, and it was not a bug.** The last handoff flagged
`CanvasManager+Shape.registerVectorStrokeUndo` and `CanvasManager+Fill.registerVectorFillUndo` as
unaudited wholesale assignments through the kind-filtered accessors. They are correct. **Every**
insertion into `_elements` goes through `insertionIndex(forKind:)`, which orders by `Kind.rawValue`
(`fill` 0 < `image` 1 < `stroke` 2), and the punch's `_elements.append` lands exactly where that
would have put it because `stroke` is the highest kind. So the display list is sorted by kind as an
*invariant*, each kind is contiguous by construction, and the splice round-trips exactly.
`testAPunchLeavesEachKindContiguousSoTheUndoAccessorsStillRoundTrip` pins this.

The real consequence of that invariant, which *is* still open: **the list cannot express a fill or
image above a stroke at all**, so a flood fill made after an erase gesture is inserted beneath that
gesture and gets punched by it. That is carry-over 2(a) seen from the eraser's side;
`testAFillAddedAfterAnErasePunchLandsBeneathItAndIsPunched` records the current behaviour so whoever
settles the question changes it deliberately.

---

## Next session: start here

### 1. Give the dab lattice a reproducible anchor — the unlock

Unchanged from the last handoff and now the top item. This is what buys back the geometric split,
and with it plan §1's "grab one visual half with the Move tool". Two candidate shapes:

- **Arclength-anchored dabs.** Place dabs at absolute multiples of `stampSpacing` measured from the
  stroke's origin, and give a piece its start arclength. Changes `BrushStamper` for every stroke.
- **A parametric visible range on `VectorStroke`.** A piece keeps the original samples and renders
  only the dabs inside its range, reusing the original lattice outright. Cleaner in principle —
  `stampStroke`'s inner `advance` closure already receives each dab's `t` along its segment, so the
  skip is local to that loop — but it ripples into bounds, hit-testing, the spatial index,
  persistence and the Move tool.

Either one makes `testAPartialSplitDivergesOutsideThePunchWhichIsWhyItIsNotWired` fail, which is the
signal to re-wire `conservativeCuts` into `VectorCanvas.eraseHybrid`.

Budget it as a **whole session** — Session 6 deliberately did not start it rather than leave it
half-done.

### 2. Then

- **Perf is unmeasured for Mode 1.** `hasResidue` probes the eraser's parametric domain and each
  probe does a spatial-index query — a per-erase cost nobody has timed. Plan §6/§8 want
  `PerfBaselineTests.testVectorLayerRenderCostAndMemory` extended with an erase-heavy scenario
  (200 strokes, 50 erase gestures) and the numbers recorded in `REFACTOR_BASELINE.md`.
- **GPU rendering** — plan §11. Unblocked: §8's parity test exists and is its regression net.

### Carry-overs still open

1. **Two sub-spacing biases at stroke ends** (`advance` carries a remainder so the last dab falls
   short; the chain tapers where `stampStroke` ramps pressure). Mattered for the clean-cut margin;
   less critical now that the punch guarantees exactness regardless. Same root cause as §1 above.
2. **`addFill` inserts beneath existing strokes — still right?** Now sharpened by the finding above:
   this is not a local choice about fills, it is a property of the kind-sorted display list.
   Changing it means letting `_elements` hold an arbitrary order and dropping the kind accessors'
   splice contract — the `strokes`/`fills`/`images` setters and both `registerVector*Undo` paths
   would have to move to `elements`. What depends on the invariant is now pinned by
   `testAPunchLeavesEachKindContiguousSoTheUndoAccessorsStillRoundTrip`.
3. **The live-preview trace measures publication, not pixels.** `lastVectorGestureTrace` proves the
   punched copy reached the image view repeatedly during the drag; it does not prove a particular
   pixel was clear at that moment. Closing that gap needs a pixel read off the scratch texture,
   recorded in-app (`RasterLayerTexture` has a private `CGContext` whose `data` would serve). Low
   priority — the pixels themselves are `RasterVectorParityLogicTests`' job, and the preview shares
   `stampPath`/`isEraser` with the raster eraser precisely so they can be.

## Multi-session protocol reminder

Work in a worktree off `origin/main`, never edit `main` directly.
