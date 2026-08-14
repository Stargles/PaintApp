# Phase 6b — §6.4 live feedback while drawing

Worker notes. Findings in the order they were established.

## 1. `MaskResolver` at 2048² — the measurement

`PerfBaselineTests.testMaskedCompositeCostAtCanvasResolution`. Fixture: six layers at 2048², layer 0
is a half-canvas mask shape, layers 1–5 all clip to it (one distinct `AlphaMask`, so one resolution
shared by five nodes — the shape §6.1's cache is built for). Masked and unmasked composites are the
same stack, so the delta is the mask.

**Debug, simulator (`75C8B97E…`), five masked nodes, 2048×2048:**

| | ms |
|---|---|
| composite, unmasked | 49.9 |
| composite, masked, warm cache | 10173.7 |
| composite, masked, cold cache | 19249.1 |
| delta, warm | 10123.9 |
| delta, cold | 19199.2 |
| `MaskResolver.coverage`, uncached | 1143.7 |
| `MaskResolver.apply`, one node | 1532.4 |
| `ResolvedMask.makeMaskImage()` | 2458.1 |

Peak process footprint: 295.5 MB unmasked, 614.9 MB masked cold, 516.2 MB across the lone `apply`.

**A mask costs 200x the composite it clips, and it is the multiply, not the resolution.** Five
`apply` calls at ~1.5 s each are the whole of the warm delta; the resolution is cached and shared and
is 1.1 s once.

### How much of that is `-Onone`

Both loops extracted verbatim into a standalone file and run at 2048² on this Mac:

| | `-Onone` | `-O` | factor |
|---|---|---|---|
| `MaskResolver.apply` inner loop | 1969.5 ms | 31.9 ms | 62x |
| `makeMaskImage` inner loop | 3166.9 ms | 7.2 ms | 440x |

The `-Onone` figures land within 30% of what the test reports, which is what says the extraction
measures the same work. **So the optimised cost of a mask is ~32 ms per clipped node per composite,
and ~7 ms to build a mask image.** Real, worth knowing before a sandwich rebuild runs per dab, but
not a 200x.

### Two things that follow, neither of them mine to fix

1. **The scheme's Run configuration is Debug** (`PaintSoftware.xcscheme:60`), and CLAUDE.md's iPad
   deploy passes no `-configuration`. So the build on the iPad is `-Onone` and the artist is feeling
   the left-hand column, not the right one: a five-layer masked document rebuilds its sandwich in
   ~10 s. Archive/Profile are Release; Run and Test are not.
2. **The test target does not compile in Release.** `-configuration Release` fails at
   `ShapeDetectorLogicTests.swift:54` with "the compiler is unable to type-check this expression in
   reasonable time" (the `largestGap` `map`/`hypot` chain). Pre-existing, unrelated to phase 6 — but
   it is why the Release column above comes from a standalone harness rather than from the test.

### The case is gated out of the fast tier

36 s and a 615 MB peak is the profile that made a ~400 MB neighbour fail
`InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` whenever they shared a
runner process. `XCTSkipUnless(PAINT_PERF_HEAVY)`, numbers recorded in the doc comment. Gated rather
than deleted (which is what the phase-4 nesting measurement got) because this one wants re-measuring
whenever `apply` is touched.

## 2. §6.4 — what the live mask has to be resolved against

See section 3 below for what shipped.

- The compositor resolves a leaf's masks with `MaskResolver.coverage(for: node.masks, of: request)`
  (`Compositor.swift:457`), where `node` is the active layer's `RenderNode` and `request` is one of
  the three from `makeSandwichRequests`. All three share one `maskStacks` and one `contentVersions`
  (`RenderRequest.swift`), so *which* of the three does not matter — `full` is the one the canvas
  snaps back to on lift, and it is what the live view has to agree with.
- **`needsCompositorOnCanvas` counts a mask** (`RenderTree.swift:246`), so any document with a mask
  anywhere engages §5.2's sandwich. Mid-stroke the active layer is drawn by Core Animation and is in
  neither `below` nor `above` — which is exactly why its mask goes missing for the stroke's duration
  and why §6.4 exists.
- **Enclosing folders' masks have to be in the list too.** A masked *folder* clips its assembled
  composite, so at rest `full` clips the active layer through it; mid-stroke nothing does. The
  product of coverages `MaskResolver.coverage` already computes over a list is exactly the right
  answer, so the fix is to hand it the ancestor chain's masks rather than only the leaf's.

### Alignment — checked, not assumed

`CALayer.mask` is in the masked layer's own coordinate space and the mask image is canvas-space, so
this had to be established rather than hoped for.

- `containerView.bounds` is set to `canvasSize` outright (`CanvasView.swift:1379`), and
  `LayerHostView` and each of its three content views are pinned edge-to-edge to it. So a mask layer
  sized to `bounds` covers the canvas 1:1 — the same correspondence
  `fillImageView.contentMode = .scaleToFill` already relies on.
- **Canvas zoom/pan is a `CGAffineTransform` on `containerView`** (`applyTransform`), an *ancestor*
  of the masked layer. An ancestor transform scales the layer and its mask together, so the mask
  needs no compensation. Blanking — the other `CALayer.mask` in this view tree — has never needed a
  zoom clause either, for the same reason.
- **A vector layer transform is baked into the rendered pixels, not applied to the view.**
  `StrokeCanvasView.refreshDisplay` renders `VectorCanvas` (transform included) into the image its
  edge-pinned `imageView` displays; no `view.transform` anywhere in the host. Had it been a view
  transform, a canvas-space mask would have been wrong and this is where it would have shown.

## 3. What shipped

- `RenderNode.masksClipping(leafAt:in:)` (`Models/RenderTree.swift`) — the leaf's masks plus every
  enclosing group's, outermost first.
- `LayerHostView.setContentMask(_:)` (`Views/Canvas/LayerHostView.swift`) — installs the mask on the
  host's three content sublayers.
- `CanvasView.Coordinator.liveMaskStrokeBegan(host:)` / `resolveLiveMask(forLayerAt:)`, called from
  `onStrokeBegan`; maintained and released by `updateSandwich`.
- Five cases in `MaskParityLogicTests` under a new §6.4 heading (32 → 37 in that suite).

### The decisions, and why

- **The mask goes on the host's three content sublayers, never on `host.layer`.** Blanking owns
  `host.layer.mask`, and the collision fails silently in whichever direction install order decides.
- **All three content views, not `strokeView` alone.** Mid-stroke the active host is the only thing
  drawing the active layer — it is in neither sandwich half — so its `bakedImageView` and
  `fillImageView` are as unclipped as its live ink. Masking only the ink fixes the stroke and leaves
  baked content popping out from under the clip on the same first touch. **This is the one place I
  went past the brief's "the mask goes on `host.strokeView`"** — same constraint (nothing on
  `host.layer`), two more sublayers. Easy to cut back to one line if you want it narrower.
- **Three mask layers, not one shared.** `CALayer.mask` takes ownership the way a superlayer does, so
  one layer assigned to three masks lands on the third and silently leaves two unmasked.
- **Install/release rides on the same predicate as blanking** (`midStroke && id == activeID`) rather
  than on the touch callbacks. Trap 2 in `updateSandwich` keeps `midStroke` true until the rebuild
  lift asked for lands, so clearing on `onStrokeEnded` would drop the clip while the host is still
  what is on screen — a flash of the very glitch, at the other end of the stroke. `onStrokeBegan`
  still installs directly, because a dab publishes nothing and the SwiftUI pass that would install it
  is the pass the stroke is deliberately not causing.
- **Resolved once at `onStrokeBegan` and held** — §6.4's "static for the duration of a stroke", and
  the same window `makeSandwichKey` freezes the active layer's content version over.
- **Cached at the call site on the coordinator, keyed on `ResolvedMask` identity, and the entry
  retains the mask.** Retaining is what makes `===` sound: without it the old object could be freed
  and a new one land at the same address — the ABA hazard `LayerContentVersion` documents. Not a
  `lazy var` on `ResolvedMask`, which is shared across layers and read from the off-main rebuild.

### Does it actually agree with the compositor?

Yes, and more strongly than expected.

- **Same object, not an equal one.** Both sides call `MaskResolver.coverage`, whose cache is keyed on
  the masks plus the content versions they read; `resolveLiveMask` builds its request with
  `makeRenderRequest`, which shares `maskStacks` (derived from the whole tree) and `contentVersions`
  with all three sandwich requests. `testTheLiveMaskIsTheSameResolutionTheCompositorApplies` asserts
  identity.
- **`makeMaskImage()`'s alpha is `coverage` byte for byte**, so what Core Animation multiplies by is
  what `MaskResolver.apply` multiplies by.
  (`testTheLiveMaskImageCarriesTheCoverageInItsAlpha`.)
- **Nested clips agree byte for byte too — I expected them not to.** The compositor clips the leaf,
  quantizes, then clips the assembled group and quantizes again; the live path multiplies the two
  coverages into one and quantizes once. Two roundings against one should show up as ±1 across a
  feathered edge. Measured worst-case difference over a fixture whose two soft mask edges genuinely
  cross (asserted as a premise, or the equality would be trivial): **0**. Pinned as an equality
  rather than a bound, so a future drift is a decision rather than slack.

### Known gaps, none of them mine to close

- **A `.preview`-quality request would resolve a different coverage.** `resolveLiveMask` asks at
  `.full`, which matches what the sandwich rebuild uses today. If §9.2's background renderer ever
  composites the canvas at `.preview`, the live mask and the composite stop sharing a cache entry —
  `RenderQuality` is in `MaskResolver`'s key.
- **The disengaged path shows no mask at all**, at rest or mid-stroke. Reachable only via
  `isSandwichEngaged`'s floating-piece and in-between escape hatches (drawing is blocked outright
  during the first). Pre-existing, and outside §6.4.
- **`resolveLiveMask` runs `makeRenderRequest` on the main actor at stroke begin.** Cheap because
  `PixelOps.rasterize` is memoized on cel identity and the rebuild has just walked the same cels —
  but it is main-thread work on the first touch, and in a Debug build `makeMaskImage` behind it is
  the 2.5 s from section 1 the first time a given mask is used. The call-site cache makes it once per
  distinct mask rather than once per stroke; the rest is section 1's Debug-configuration problem.
