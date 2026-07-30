# Vector Eraser — Resume Here

Working state as of **Session 5 (2026-07-30)**. Read [VECTOR_ERASER_PLAN.md](VECTOR_ERASER_PLAN.md)
first — it is the spec, and §1/§4/§8 have been rewritten to match what actually shipped. This file is
only the bookmark.

## Environment correction (important, saves 10 minutes)

CLAUDE.md's "Remote testing (Tailscale → Mac, no Xcode on this machine)" section was written for the
**Windows** machine. If your session is on `Julias-MacBook-Pro` (darwin), you *are* the Mac: Xcode is
local, no SSH, no `parallel_test.sh`. Build directly, ~20s:

```bash
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser
```

Logic tests (**169** currently green — this is the regression net):

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser -only-testing:PaintSoftwareUITests/VectorEraserLogicTests -only-testing:PaintSoftwareUITests/VectorEraserHybridLogicTests -only-testing:PaintSoftwareUITests/StrokeGeometryLogicTests -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ProjectSaveLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/RasterVectorParityLogicTests
```

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

## Next session: start here

### 1. Nothing has ever been run in the simulator UI

All 169 tests are headless. The segmented mode picker has never been tapped, Mode 1's live preview
has never been seen, and Mode 3's cut-on-touch-down has never been felt. This is now the largest
untested surface by a wide margin, and the only remaining item that could invalidate a whole phase.

### 2. Give the dab lattice a reproducible anchor — the unlock

This is what buys back the geometric split, and with it plan §1's "grab one visual half with the Move
tool". Two candidate shapes:

- **Arclength-anchored dabs.** Place dabs at absolute multiples of `stampSpacing` measured from the
  stroke's origin, and give a piece its start arclength. Changes `BrushStamper` for every stroke.
- **A parametric visible range on `VectorStroke`.** A piece keeps the original samples and renders
  only the dabs inside its range, reusing the original lattice outright. Cleaner in principle;
  ripples into bounds, hit-testing, the spatial index, persistence and the Move tool.

Either one makes `testAPartialSplitDivergesOutsideThePunchWhichIsWhyItIsNotWired` fail, which is the
signal to re-wire `conservativeCuts` into `VectorCanvas.eraseHybrid`.

### 3. Then

- **Perf is unmeasured for Mode 1.** `hasResidue` probes the eraser's parametric domain and each
  probe does a spatial-index query — a per-erase cost nobody has timed. Plan §6/§8 want
  `PerfBaselineTests.testVectorLayerRenderCostAndMemory` extended with an erase-heavy scenario.
- **GPU rendering** — plan §11. Unblocked: §8's parity test exists and is its regression net.

### Carry-overs still open

1. **Two sub-spacing biases at stroke ends** (`advance` carries a remainder so the last dab falls
   short; the chain tapers where `stampStroke` ramps pressure). Mattered for the clean-cut margin;
   less critical now that the punch guarantees exactness regardless. Same root cause as §2 above.
2. **Two ordering decisions still unowned:** (a) `addFill` inserts *beneath* existing strokes — still
   right? (b) the `strokes`/`fills`/`images` setters collapse each kind into one contiguous run.
   Phase 4 is the first phase that interleaves — an `.erase` stroke is appended after the paint
   strokes and a later paint stroke lands above it — which is why the vector undo path moved to
   `elements`. Any *remaining* wholesale assignment through `strokes` is a latent bug;
   `CanvasManager+Shape.registerVectorStrokeUndo` and `CanvasManager+Fill.registerVectorFillUndo`
   were **not audited**.

## Multi-session protocol reminder

Work in a worktree off `origin/main`, never edit `main` directly.
