# Vector Eraser — Resume Here

Working state as of Session 3 (2026-07-30). Read [VECTOR_ERASER_PLAN.md](VECTOR_ERASER_PLAN.md)
first — it is the spec; this file is only the bookmark.

## Environment correction (important, saves 10 minutes)

CLAUDE.md's "Remote testing (Tailscale → Mac, no Xcode on this machine)" section was written for the
**Windows** machine. If your session is on `Julias-MacBook-Pro` (darwin, Tailscale
`100.70.148.78`), you *are* the Mac: Xcode 26.6 is local, no SSH, no `parallel_test.sh`. Build
directly, ~15s:

```bash
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser
```

Logic tests (**136** currently green — this is the regression net):

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser -only-testing:PaintSoftwareUITests/VectorEraserLogicTests -only-testing:PaintSoftwareUITests/StrokeGeometryLogicTests -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ProjectSaveLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests
```

## Done

**Phase 0** — `Engine/StrokeGeometry.swift` (741 lines) and `StrokeSpatialIndex.swift` (220). Pure
`CoreGraphics`, dual app+test target membership. Capsule-chain coverage, polyline intersection
(exact + width-tolerant), sample interpolation, subdivision, `splitStroke(_:removing:)`, uniform-grid
broad phase. 43 tests including a brute-force march validating the closed-form coverage.

**Phase 1** — `VectorCanvas` holds one ordered `[VectorElement]` (`.stroke`/`.fill`/`.image`);
`VectorStroke` gained `composite: StrokeComposite` (decodes to `.paint` on legacy files).
Compatibility accessors `strokes`/`fills`/`images` meant only one of ~160 call sites changed.
Persistence stores the ordered list with a legacy fills→images→strokes fallback.

**Brush-side fixes** (plan §9) — seeded splitmix64 `BrushStamper.DabRNG`, so replayed strokes stopped
crawling; pressure now ramps across the dabs bridging two input samples.

**Phase 2** (this session) —

- `VectorEraserMode` in [Tool.swift](PaintSoftware/Models/Tool.swift): `.erase` / `.cutPoints` /
  `.cutToIntersection`, with `displayName` and `isStabilized`.
- `CanvasManager.vectorEraserMode` (`@Published`, default `.erase`), persisted in `ProjectManifest`
  via `decodeIfPresent` and round-tripped through `ProjectStore` save **and** load.
- `CanvasManager.activeLayerKind` — new, deliberately weaker than the existing `activeLayerIsVector`
  (it does not require a `VectorCanvas` on the current frame, so the picker shows on an empty vector
  layer).
- `EraserSettingsPanel` spends the shared panel's `accessory` slot on a segmented picker, shown only
  when `activeLayerKind == .vector`. Identifier `eraserPanel.vectorModePicker`.
- `StrokeCanvasView.vectorEraserMode`, pushed from `CanvasView.updateActiveLayerAndTool`. **It is
  also a field of `AppliedTool`** — that struct is the change-detection cache, so without it a mode
  change compares equal and the picker silently does nothing.
- Stabilization is now per mode, not per tool: `isEraser && !mode.isStabilized` takes the raw point.
- New [Engine/VectorEraser.swift](PaintSoftware/Engine/VectorEraser.swift) — pure geometry, dual
  target membership (pbxproj entries added by hand, ids `9A7B…D01/D02` and `…E01/E02`).
- `VectorCanvas.erase(alongPath:brush:size:mode:)` rewritten onto it. The old signature
  (`alongPath: [CGPoint], radius:`) is gone; there was one caller.
- 24 new tests in `VectorEraserLogicTests`, four named `…regressionOfDefectN` for the four plan §4
  defects.

### Design notes worth not re-deriving

- **Probing, not `subdivided`.** `VectorEraser.cutRanges` walks inside/outside probes along each
  *original* segment (step = the sweep's smallest radius, clipped to the sweep's bbox by
  Liang–Barsky) and bisects each crossing 16 times. Same resolution as densifying the samples, but
  nothing is inserted into the surviving pieces and the parameters come out in the original domain.
  `StrokeGeometry.subdivided` stays for liquify, where the extra samples are the point.
- **A zero-length segment claims `i...(i+1)`, not `i...i`.** A stalled finger emits coincident
  samples; claiming only the point fragments a cut into slivers around each of them. Test:
  `testRepeatedSamplesDoNotFragmentTheCut`.
- **`.erase` strokes are skipped** (old carry-over #4). Cutting a span out of an eraser would
  *restore* the ink beneath it. Phase 4 GCs them instead.
- **Per-stroke cached `bounds` was not added** (old carry-over #7) — deliberately. It would exist to
  reject a stroke before testing its segments; `VectorCanvas.strokeIndex()` rejects it without
  visiting it at all, which strictly dominates. Adding a derived stored field to a `Codable` struct
  whose `samples` are assigned from a dozen sites needs a mutator seam; build that with Phase 5's
  decimation, which needs the same seam.
- **`strokeIndex()` is version-keyed and lock-guarded.** `segments(near:)` mutates a visit stamp
  during a *read* (old carry-over #8), so concurrent queries would drop results. Segments are
  inserted with **no padding** — the index answers centreline questions, which is what Modes 2 and 3
  ask. Phase 4's coverage test asks about stroke *width* and must expand its query rect.
- **Id semantics preserved** (old carry-over #5): an untouched stroke keeps its `id`, and therefore
  its dab scatter pattern; split pieces mint fresh ones and re-roll.

## Next: Phase 4 (Mode 1), or finish Phase 3

**Phase 3 remainder** is small, and it is *gesture* work rather than geometry: cut on touch-**down**,
re-query per crossing so one drag across three lines cuts three spans, one undo entry for the whole
drag. Today `.cutToIntersection` resolves once on lift against the gesture's first sample. All the
geometry it needs exists and is tested.

**Phase 4** is the real one: live preview (copy the cel's cached render into a scratch
`RasterLayerTexture` and punch `.destinationOut` into it), the §1 hybrid commit, residue `.erase`
elements, GC, and — the acceptance test that actually matters — §8's raster-vs-vector pixel
comparison, which still does not exist.

### Carry-overs still open

1. **The clean-cut alpha gate needs `scatter == 0` and `rotationJitter == 0`** on top of hardness /
   grain / opacity×flow. The capsule chain models the un-scattered sweep, while scatter displaces
   each dab up to `radius * 2 * scatter` off the centreline, so a clean-cut verdict is unsound in
   both directions. Plan §1's gate must add these.
2. **Square/custom erasers will essentially never clean-cut.** `stampApproximateSquare` reaches
   `diameter/2 · √2` at the corners; the chain models `diameter/2`. Errs toward retaining a punch,
   which is the safe direction. Accept it.
3. **Two sub-spacing biases at stroke ends** (`advance` carries a remainder so the last dab falls
   short; the chain tapers where `stampStroke` ramps pressure). This is why plan §1's coverage margin
   epsilon is not optional.
4. **Two ordering decisions still unowned:** (a) `addFill` inserts *beneath* existing strokes — still
   right now that z-order is real? (b) the `strokes`/`fills`/`images` setters collapse each kind into
   one contiguous run, so the first phase that deliberately interleaves must assign through
   `elements`. Documented at the accessors; Phase 2 did not need to interleave.
5. **`graphify-out/GRAPH_REPORT.md` is stale** — deliberately not regenerated while phases are in
   flight. Run `graphify update .` and commit the refreshed report once Phase 4 lands.
6. **Nothing has been exercised in the simulator UI.** All 136 tests are headless logic tests. In
   particular the segmented picker has never been tapped.
7. **GPU rendering** — see the new plan §11 for the full argument. Short version: the per-frame layer
   composite is already GPU (Core Animation over `UIImageView`s); the cost is re-rasterizing one
   layer on mutation, at ~3.2 ms/stroke, which does not scale past a few hundred strokes. A GPU
   rasterizer is needed eventually, must cover **both** tiers (or §8's pixel test degenerates into
   shader-vs-Core-Graphics), and should land *after* Phase 4 so that test can be its regression net.

## Multi-session protocol reminder

Work in a worktree off `origin/main`, never edit `main` directly:

```bash
git fetch origin && git worktree add ../PaintApp-<id> -b tmp/<id> origin/main
```
