# Vector Eraser — Resume Here

Working state as of **Session 7 (2026-07-30)**. Read [VECTOR_ERASER_PLAN.md](VECTOR_ERASER_PLAN.md)
first — it is the spec, and §1/§4/§7/§8 match what actually shipped. This file is only the bookmark.

## Environment correction (important, saves 10 minutes)

CLAUDE.md's "Remote testing (Tailscale → Mac, no Xcode on this machine)" section was written for the
**Windows** machine. If your session is on `Julias-MacBook-Pro` (darwin), you *are* the Mac: Xcode is
local, no SSH, no `parallel_test.sh`. Build directly, ~20s:

```bash
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser
```

Logic tests (**175** currently green — this is the regression net):

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser -only-testing:PaintSoftwareUITests/VectorEraserLogicTests -only-testing:PaintSoftwareUITests/VectorEraserHybridLogicTests -only-testing:PaintSoftwareUITests/StrokeGeometryLogicTests -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ProjectSaveLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/RasterVectorParityLogicTests
```

UI tests (`VectorEraserUITests`, 8 tests; `VectorShapeAndRecoveryUITests`) — same command with those
suites added. They are slow: **~35–45 s each**, and xcodebuild does not flush per-test results until
the whole run finishes, so a log that still looks empty ten minutes in is normal rather than a hang.
Budget several minutes and run them in the background. The full green run at Session 7's end was
**195 tests, 0 failures**.

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
end is deleted outright, and a stroke it covers full-width over a stretch is cut there into pieces
that keep rendering on the original's dab lattice.**

Three sessions of measurement produced that, and the middle one is the part worth not re-deriving.

**Session 4** built `RasterVectorParityLogicTests` — plan §8's acceptance test — which renders a
scene twice, once by stamping into a `RasterLayerTexture` and erasing it and once as a `VectorCanvas`
display list, and compares premultiplied RGBA bytes. It established that **a retained `.erase`
element is byte-identical to raster erasing**: `maxChannelDelta == 0` across all 36 matrix cases. The
feared 1–2 LSB colour-space drift between `RasterLayerTexture`'s 8-bit deviceRGB context and
`renderLocalContent`'s renderer does not exist.

**Session 5** wrote `VectorEraserHybridLogicTests`, which drives the real `VectorCanvas.erase` rather
than hand-built display lists, and found four defects, all fixed in `fd7c258`. Three were local bugs
(a punch trimmed to its residue spans, a dead alpha gate, fragmented clean-cut ranges). The fourth was
structural: **the partial split could not be made pixel-exact, so Mode 1 shipped without cutting
anything.**

**Session 7** made it exact and wired it back in. See below.

### The one thing to understand before touching any of this

`BrushStamper.stampStroke` anchors the **dab lattice** at `samples[0]`: dabs every `stampSpacing`,
remainder carried across segments. So *any* sub-run of a stroke, **re-stamped as a stroke of its
own**, puts its ink somewhere new along its entire length — not merely near where it was cut.

That fact is still true, and it still produces the two consequences the earlier sessions measured:

- Retaining only part of the eraser's gesture re-phases the punch's own dabs, including the ones over
  the ink that justified retaining it. Measured: 4/255 over 22 px for a hard round eraser crossing
  diagonally; 27/255 over 81 px for the same gesture at opacity 0.4. **`hasResidue` is therefore
  still a bit, not a set of spans, and the punch still carries the gesture whole.**
- Cutting a stroke re-phases the surviving piece's dabs, most visibly at its **far tip** — the end
  furthest from the eraser, and therefore the one the punch cannot cover. Measured on a 24pt line
  with a 48pt nib: divergence across x ∈ [41, 115] where the punch covers only x ∈ [40, 88], leaving
  118 stray pixels at up to 183/255.

**`DabLattice` removes the second consequence by removing its premise: a piece is no longer re-stamped
as a stroke of its own.** It carries the parent's samples and renders through them, drawing only the
dabs inside its own parametric range. The first consequence is untouched — a punch is one element, not
a piece of one, so there is nothing for it to share.

The intuition that says "the cut is hidden under the eraser, so it cannot be seen" is right about the
ink *at* the cut and wrong about the piece as a whole; that is what the lattice fixes. It is
*separately* wrong about the new round cap a cut creates, which is what `conservativeCuts` fixes by
insetting. **Both are needed — either alone still leaves stray ink outside the gesture**, and
`testTheSplitIsExactOnlyBecauseThePiecesShareTheParentsLattice` measures exactly that, in both
directions, in one scene.

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
- **The pressure ramp was never a defect**, despite two sessions of notes naming it alongside the
  lattice. `splitStroke` interpolates the boundary sample's pressure and pressure interpolates
  linearly, so a piece already reported the parent's pressure at every position. Only the lattice
  moved.

---

## What Session 7 did

**The last handoff's item 1 is closed: the dab lattice has a reproducible anchor, and the geometric
split is wired back into `VectorCanvas.eraseHybrid`.**

Of the two candidate shapes, **the parametric visible range shipped**, not arclength anchoring. The
deciding argument was exactness rather than elegance: arclength anchoring *recomputes* every dab
position through a different sequence of floating-point operations from the one that placed the
original dabs, and §8 is asserted at zero tolerance. A visible range recomputes nothing —
`stampStroke` walks the parent's samples with the same arithmetic and the same carry, and routes the
dabs outside the range to `DiscardedDabTarget`, so the dabs that land are the same calls with the
same arguments. (A second argument turned up while reading `advance`, and it is worth knowing: when a
segment is shorter than one spacing the walk carries its remainder and the following dabs are placed
along a **chord from an earlier carry point**, cutting the corner. Dab positions are therefore not a
function of arclength along the polyline at all, so arclength anchoring would have been approximate
even in exact arithmetic.)

`DabLattice` (in `VectorLayer.swift`, next to `VectorStroke`) stores the parent's samples, the
parameter each of the piece's own samples sits at, and the parent's `seedID`. Three things about it:

- **`samples` is still the truth about a piece's geometry** — bounds, spatial index, coverage tests,
  later cuts. The lattice is read in exactly one place, `VectorCanvas.stamp(stroke:into:isEraser:)`,
  and only to answer "where did the dabs go". That is what kept the change small: no geometric
  consumer had to learn that pieces exist.
- **Per-sample parameters rather than just a range** is what lets a piece be cut *again*: the second
  cut's parameters are in the piece's own domain and get mapped back through `parentParameter(of:)`,
  so a grandchild points at the original ancestor rather than at a chain of parents.
  `testCuttingAPieceAgainStaysOnTheOriginalLattice` drives two real erases through the canvas and
  checks the mapping and the resulting pixels.
- **Skipped dabs still go through `stampDab`**, so the dab RNG stays in phase, and the lattice carries
  the parent's seed. `VectorEraser.supportsSplitting` still refuses scattering brushes, but now for
  one reason only — the coverage test measures against a capsule chain that scattered ink does not
  respect — where it used to have two.

`VectorCanvas.splitCleanlyErasedStrokes` is the new pass, run after `removeFullyErasedStrokes` and
before the punch. `conservativeCuts` is wired into it and is no longer dead code.

Tests: `testAPartialSplitDivergesOutsideThePunchWhichIsWhyItIsNotWired` is gone, replaced by
`testTheSplitIsExactOnlyBecauseThePiecesShareTheParentsLattice`, which asserts both directions so the
reason the type exists stays pinned rather than remembered.
`testPartialCoverageNeverDeletesTheStroke` became
`testPartialCoverageSplitsOrPunchesButNeverDeletes`: a full-width crossing now yields two pieces, a
shave and a too-narrow nib still yield one, and every row is still raster-exact. Two new tests live a
tier down, where their claims actually are:
`BrushEngineLogicTests.testComplementaryVisibleRangesReproduceTheWholeStrokeExactly` (the stamper
property, no eraser involved) and
`testAPieceLatticeSurvivesEncodingAndAnOrdinaryStrokeDoesNotCarryOne` (persistence, plus that an
ordinary stroke writes no new key).

The UI tier moved with it: `testMode1PunchesAHoleWithoutCuttingTheStroke` is now
`testMode1CutsTheStrokeAndPunchesTheGap` (2 paint pieces *and* 1 punch — the cut gives the two
halves, the punch makes the visible edge, and dropping either is a regression the other's assertions
would miss), and `VectorShapeAndRecoveryUITests`' shape-then-erase test with it. Note what this did
to `testPickingCutModeMakesTheGestureCutInsteadOfPunch`: both modes now cut, so the piece **count**
no longer distinguishes them and `erases == 0` is the only assertion left proving the picker's
selection reached the commit. Its comment says so.

Two things deliberately left alone:

- **Modes 2 and 3 clear the lattice** on the pieces they produce. They delete geometry rather than
  hiding it, so a piece there really is a new stroke; inheriting the lattice would keep drawing the
  dabs the user just cut away. Consequence: a Mode-1 piece later cut by Mode 2 re-phases. That is
  visible and correct-by-intent — Mode 2 changing the pixels is the point.
- **A single-sample stroke is excluded from the split pass.** Its whole domain is the parameter `0`,
  so a covered cross-section there would delete it without anyone having checked its round cap — a
  second, weaker deletion path. `isEntirelyCovered` in the deletion pass stays the only way a lone dab
  goes.

---

## Next session: start here

### 1. Perf — now genuinely overdue

Two costs, both unmeasured, and the split just added the second:

- `hasResidue` probes the eraser's parametric domain and each probe does a spatial-index query.
- `splitCleanlyErasedStrokes` runs a full `cleanCutRanges` probe walk over **every** candidate stroke,
  and `removeFullyErasedStrokes` has just run one over the same strokes. Deletion is arithmetically a
  special case of the split — a whole-domain cut with both caps covered is exactly what
  `conservativeCuts` produces when it declines to inset — so the two passes could be one loop that
  computes the clean ranges once. They were kept separate this session because merging them is a
  behaviour change rather than a refactor: `isEntirelyCovered` requires *one* span covering the
  domain, where the split path would accept two abutting ones.

Plan §6/§8 want `PerfBaselineTests.testVectorLayerRenderCostAndMemory` extended with an erase-heavy
scenario (200 strokes, 50 erase gestures) and the numbers recorded in `REFACTOR_BASELINE.md`. Measure
first, then decide whether merging the passes is worth its risk.

### 2. Then

- **Per-element Move**, which is what the split was the unlock for — plan §1's "grab one visual half
  with the Move tool". Nothing in `DabLattice` obstructs it: translation does not change arclength, so
  a translated piece keeps its lattice unchanged. There is no per-element move today (moves are a
  layer-level `LayerTransform`), so this is a new feature rather than a fix.
- **GPU rendering** — plan §11. Unblocked: §8's parity test exists and is its regression net. One
  constraint it adds: the visible range is a *filter over a walk*, so a GPU rasterizer has to
  reproduce it as one — bin the dabs and drop those outside the range, never re-derive positions.

### Carry-overs still open

1. **Two sub-spacing biases at stroke ends** (`advance` carries a remainder so the last dab falls
   short; the chain tapers where `stampStroke` ramps pressure). Same root cause as the lattice above,
   and less pressing still now: a piece inherits the parent's biases rather than introducing its own.
2. **`addFill` inserts beneath existing strokes — still right?** Not a local choice about fills: it is
   a property of the kind-sorted display list. Changing it means letting `_elements` hold an arbitrary
   order and dropping the kind accessors' splice contract — the `strokes`/`fills`/`images` setters and
   both `registerVector*Undo` paths would have to move to `elements`. What depends on the invariant is
   pinned by `testAPunchLeavesEachKindContiguousSoTheUndoAccessorsStillRoundTrip`.
3. **The live-preview trace measures publication, not pixels.** `lastVectorGestureTrace` proves the
   punched copy reached the image view repeatedly during the drag; it does not prove a particular
   pixel was clear at that moment. Closing that gap needs a pixel read off the scratch texture,
   recorded in-app (`RasterLayerTexture` has a private `CGContext` whose `data` would serve). Low
   priority — the pixels themselves are `RasterVectorParityLogicTests`' job.
4. **A piece holds its parent's whole sample array.** In memory two pieces share it (arrays are
   copy-on-write) until something mutates one; a decoded project gives each its own copy. Point
   decimation is the natural place to settle this — it can rewrite a piece as a stroke of its own once
   nobody needs the parent's phase any more, which is a decision about visible drift, not about bytes.

## Multi-session protocol reminder

Work in a worktree off `origin/main`, never edit `main` directly.
</content>
