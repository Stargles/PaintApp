# Vector Eraser — Resume Here

Working state as of Session 2 (2026-07-29). Everything below is **merged and pushed to
`origin/main`** at `8fb8b6b`. Read [VECTOR_ERASER_PLAN.md](VECTOR_ERASER_PLAN.md) first — it is the
spec; this file is only the bookmark.

## Environment correction (important, saves 10 minutes)

CLAUDE.md's "Remote testing (Tailscale → Mac, no Xcode on this machine)" section was written for the
**Windows** machine. If your session is on `Julias-MacBook-Pro` (darwin, Tailscale
`100.70.148.78`), you *are* the Mac: Xcode 26.6 is local, no SSH, no `parallel_test.sh`. Build
directly, ~11s:

```bash
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser
```

Logic tests (112 currently green — this is the regression net):

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,id=2AE27426-4D30-465F-9B93-A759CAEA8456' -derivedDataPath /tmp/dd-veraser -only-testing:PaintSoftwareUITests/StrokeGeometryLogicTests -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ProjectSaveLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests
```

## Done

**Phase 0** — `PaintSoftware/Engine/StrokeGeometry.swift` (741 lines) and
`StrokeSpatialIndex.swift` (220). Pure `CoreGraphics`, dual app+test target membership already wired
in the pbxproj. Capsule-chain coverage, polyline intersection (exact + width-tolerant), sample
interpolation, subdivision, `splitStroke(_:removing:)`, uniform-grid broad phase. 43 tests including
a brute-force march validating the closed-form coverage.

**Phase 1** — `VectorCanvas` now holds one ordered `[VectorElement]` (`.stroke`/`.fill`/`.image`);
`VectorStroke` gained `composite: StrokeComposite` (`.paint`/`.erase`, decodes to `.paint` on legacy
files). Compatibility accessors `strokes`/`fills`/`images` meant **only one** of ~160 call sites
needed changing (`ProjectStore.load`). Persistence stores the ordered list with legacy
fills→images→strokes fallback. Render output verified byte-identical.

**Brush-side fixes** (not in the original plan — found while auditing, see plan §9):
- Replayable dab randomness. `scatter`/`rotationJitter` used `CGFloat.random` inside `stampDab`
  while `renderLocalContent` replays every stroke on every invalidation, so finished artwork
  visibly crawled. Now a seeded splitmix64 `BrushStamper.DabRNG`, seeded from `stroke.id` at the
  render site. Live raster drawing stays unseeded (correct — those dabs are never replayed).
- Pressure now ramps across the dabs bridging two input samples instead of all taking the
  destination sample's pressure (was a visible staircase in width and opacity on fast drags).

## Next: Phase 2 (task #3)

`VectorEraserMode` enum + `CanvasManager` state + `EraserSettingsPanel` segmented control (vector
layers only) + `StrokeCanvasView` plumbing, then rewrite `VectorCanvas.erase(alongPath:radius:)`
onto the Phase 0 primitives. Plan §4 and §5 are the spec.

### Carry-overs the two foundation phases surfaced — do not lose these

1. **The clean-cut alpha gate needs `scatter == 0` and `rotationJitter == 0`.** Not for the
   nondeterminism reason (fixed) — because the capsule chain models the *un-scattered* sweep while
   scatter displaces each dab up to `radius * 2 * scatter` off the centerline, so a clean-cut
   verdict is unsound in both directions. Plan §1's gate must add these.
2. **Square/custom eraser will essentially never clean-cut.** `stampApproximateSquare` reaches
   `diameter/2 · √2` at the corners; the capsule chain models `diameter/2`. Errs toward retaining a
   punch, which is the safe direction. Accept it.
3. **Two sub-spacing biases at stroke ends** (`advance` carries a remainder so the last dab falls
   short; the chain tapers where `stampStroke` now ramps pressure). This is why the coverage margin
   epsilon in plan §1 is not optional.
4. **`erase(alongPath:)` currently cuts every stroke regardless of `composite`.** Nothing builds an
   `.erase` stroke yet so both readings are indistinguishable; Phase 2 must decide (almost certainly:
   skip `.erase` elements).
5. **Preserve id semantics:** today's `erase` keeps an untouched stroke's `id` and mints fresh UUIDs
   for split pieces. Keep that — and note `id` now also seeds the scatter pattern, so reusing an id
   preserves a stroke's dab placement while minting one re-rolls it.
6. **Two ordering decisions Phase 2 owns:** (a) `addFill` currently inserts *beneath* existing
   strokes so a flood fill doesn't cover the line it was poured beside — is that still right now
   that z-order is real? (b) The `strokes`/`fills`/`images` setters collapse each kind into one
   contiguous run; the first phase that deliberately interleaves must assign through `elements`
   instead. Documented at the accessors.
7. **Per-stroke cached `bounds`** (plan §3.2) was deliberately not done in Phase 0 — it needs
   `VectorStroke`/`VectorCanvas`, which was out of that phase's scope. `StrokeGeometry.bounds(of:padding:)`
   has the computation; add the stored field in Phase 2.
8. **`StrokeSpatialIndex.segments(near:)` mutates a per-query visit stamp** — safe under
   `VectorCanvas`'s existing lock, not safe for concurrent reads. One index per user, or rebuild
   behind the lock.
9. **`graphify-out/GRAPH_REPORT.md` is stale** — deliberately not regenerated while phases were in
   flight (guaranteed merge conflict, no benefit). Run `graphify update .` and commit the refreshed
   report once Phase 4 or 5 lands.
10. **Untested:** nothing has been run in the simulator UI. All 112 tests are headless logic tests.
    Phase 4's raster-vs-vector pixel comparison (plan §8) is the acceptance test that matters and
    does not exist yet.

## Multi-session protocol reminder

Work in a worktree off `origin/main`, never edit `main` directly:

```bash
git fetch origin && git worktree add ../PaintApp-<id> -b tmp/<id> origin/main
```

`../PaintApp-vector-eraser` (branch `tmp/vector-eraser`) still exists and is level with `main` —
reuse it or make a fresh one.
