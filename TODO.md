# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. **An item leaves when merged, not when a
branch exists.** Three in flight at once unless the extras need no simulator — see `tools/simlock.sh`.

**Record an ask in the owner's own words, and fold a ruling into the item it rules on.** A quote is
cheaper to keep than a decision is to rebuild — the perspective-text requirement was nearly re-derived
because it lived in one document. But an item should read as *one current description*, not as the
transcript of the argument that produced it: this file reached 424 lines by appending each answer under
the question that prompted it, and the owner asked for it back. **A question the owner has answered stops
being a question** — the answer goes into the item and the exchange goes to [HANDOFF.md](HANDOFF.md).
What happened this pass belongs there and in `git log`, not here.

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure collected before 2026-08-17 was taken at 4096 squared, eight times the pixels.

## In flight

- **The effect backdrop, stages 4-6** — [EFFECT_BACKDROP.md](EFFECT_BACKDROP.md) §6. Stages 1-3 are on
  `tmp/effectbackdrop` (the onion skin's z-order, `Effect.input`, and the paper entering the composite);
  4 is the re-walk that makes the ink-only input real, 5 is Bloom's and Sobel's controls, 6 is the
  thumbnail flag.

## Canvas geometry, and how a coordinate is stored

**Five asks, one programme**, sharing one number. **16,384 pt is the span of a stored coordinate, the
maximum canvas, and the canvas-plus-padding budget**, and it should be defined once in the code.

Dependency in one line: **(8) needs nothing**; **(12)** is what narrowed (8)'s field to 16 bits;
**(14)** answers the strongest objection to (12); **(13)** sets the 16,384; **(9)** is independent of
all of them *because* the width is fixed, so a resize re-encodes nothing.

### (8) Fixed-point sample coordinates — SETTLED, build it

- [ ] **16 bits an axis, signed, origin at the centre of the canvas, quarter-pixel; 8 bits of pressure.
      40 bits = 5 bytes a sample against today's 24**, a 4.8x win, and far more on disk against the 89
      bytes/sample the JSON spends. `VectorSample` is three `CGFloat`, not two — the third is pressure,
      where 8-10 bits is generous.
      The centring is the owner's and is what buys the sign bit for free: *"have something like the first
      bit represent a plus or minus, then center the origin to the exact middle of the canvas ... which is
      across -8k to 8k, and the last two bits for quarter pixel res."* **Centring is an encoding concern,
      not a coordinate-system change** — in memory samples stay as they are; encode subtracts the centre
      and quantises, decode reverses it. Nothing above the storage layer changes.
      The `+2` buys quarter-pixel placement because `BrushStamper` places dabs at sub-pixel positions —
      the owner's own caveat, and correct.

      **Attached rulings. Do not re-open any of them.**
      - **Clamp, do not wrap, at the encode boundary only.** *"If you draw outside the 16k, it should not
        wrap but rather clamp."* Unclamped, a 16-bit field wraps and ink drawn past the edge **teleports
        to the opposite side of the canvas**. Saturating makes the failure local and boring.
      - **Reversible transforms decode to `Double` and re-encode at the bake** — *"converted temporarely
        to a double as to not lose accuracy, then converted back when it bakes."* See (14), the same
        mechanism asked for again at the tool level.
      - **Residual drift is closed** (2026-08-26). The many-transform case lives inside a single unbaked
        session where samples are already `Double`, so rounding has no path by which to accumulate. One
        bake, one rounding.
      - **The centre is the centre of the *current* canvas**, overruling this file's own recommendation of
        a fixed address space. An asymmetric crop therefore re-encodes every sample, acceptable for a
        one-off the artist asks for — and moot, since asymmetric crop does not exist.
      - **At a canvas of exactly 16k there is no off-canvas room**, accepted: *"a max size canvas would
        have no off canvas stroke room, but that's a very minor concern, since ... the 16k canvas would
        only ever be used for big concept art boards."* At 2048x1024 the artwork occupies +/-1024 x +/-512
        of a +/-8,192 field.

      **Why fixed and not sized-to-the-canvas, kept so it is not re-derived.** Dynamic is not merely more
      complex, it is unsound: geometry left `[0, extent)` as a matter of course for three independent
      reasons. **The 20-bit proposal overflowed on measured numbers** — `minimumScale` is 0.02 and the
      canvas maximum 8192, so a stored coordinate reached 409,600 pt against 20 signed bits' +/-131,072.
      **24 signed bits is the answer if (12) is not adopted**; adopting (12) removes the layer-local
      blow-up and is what lets the field narrow to 16.
      **Nothing in the tree clamps today**, and `CanvasView` floors zoom at 0.01 of fit with **no
      ceiling**, so a screen-wide drag at minimum zoom spans ~1,638,400 pt — filed in BUGS.md, and
      **independent of (12)**, which does nothing about zoom.

### (12) A layer should not have a *resolution* — bake geometry into canvas coordinates

- [ ] The owner: *"Every object in the vector layer should be given coordinates according to the canvas,
      and if the entire layer is 'shrunk', then those coordinates of the objects should shrink, not the
      entire layer itself being transformed."* And the nuance that matters: *"Transformations are allowed
      to exist yes. It's just that the entire layer being resized should just bake the stuff in that layer
      to their new canvas based coordinates, instead of resizing the entire layer to be at a smaller
      resolution."* So this is **not "no transforms", it is "no layer *resolution*"**.
      **Stage 1 shipped and is merged** (`cf5de83`) — Move with no selection lifts the whole cel into the
      lasso float, which bakes into canvas coordinates, and that closed the ink loss the owner reproduced.
      **What remains is the clean-up the owner asked for in the same sentence**: *"of course clean up and
      remove the legacy code cleanly."*
      - **Stage 2 — delete the legacy path.** `TopToolbar` was the only writer that could set
        `isVectorTransforming`, so the flag is now permanently false and every consumer is dead-but-live:
        the flag and its `didSet` bracket, `setVectorTransform`, `closeVectorTransformBracket`, the
        `CanvasTouchInputs` dimension, and both `CanvasView` arms. **Two things the deletion must decide
        rather than drop**: `moveBoxIsUp` loses its layer-visibility term with the whole-layer arm, so
        decide explicitly whether a Move box may be up on a hidden layer; and `CanvasTouchOwnerLogicTests`
        loses an enumerated input dimension, so **take the xcresult count before and after** — a test that
        stops running still prints green. ~1,300 lines of test exist solely to pin what is being deleted,
        including the negative control inside the new ink-loss regression test, which must be removed
        deliberately.
      - **Stage 3 — persistence goes advisory.** Bake the stored transform on decode and write identity on
        encode, keeping the field so an old build reads identity and draws baked geometry. Also bake
        `resized(to:offset:)` so `setCanvasPadding` stops writing a non-identity value. **Existing
        documents change appearance on first open** — a shrunk cel un-hides ink it was clipping — and that
        must be announced rather than discovered.
      - **Stage 4 — optional, judge after stage 1 has been on the iPad.** Delete `_transform` itself and
        the eleven entry points that invert it away. Buys clarity, not behaviour.
      **The future shape is on record and changes how this is built**: *"when I add keyframes, I want a
      special type of layer called a transformation layer in which the stuff under it can be moved."* An
      adjustment-layer shape, applied at render time to the layers below and never baked into their
      coordinates. What (12) removes is a transform baked into *storage semantics*, not a render-time
      transform, and `RenderTree` already composites effect layers over the layers beneath them — that is
      the seam a transformation layer would use.

### (14) A reversible Move: hold the transform in doubles until an explicit bake

- [ ] The owner: *"In the move tool have an option to store whatever the transformation is as doubles so
      it is reversible, and add an option in actions to bake everything down back to 16bits."*
      **This is the answer to the strongest objection against (12) and it arrived unprompted** — that a
      layer transform was the only exactly reversible operation in the app. The *geometry* half of that
      objection is dead by measurement: 100 shrink-to-2%-and-regrow cycles drift **6.0e-11 pt** and
      `stroke.size` returns bit-exact. Two artist-visible residues survive, and this ask covers both:
      - **`BrushStamper.stampSpacing`'s 1 pt absolute floor** — a stroke shrunk below it and regrown comes
        back with a different dab count. Not reversible in *pixels*, whatever the geometry does.
      - **The Move box inflates**, and this is now live rather than hypothetical: stage 1 of (12) shipped
        with it and the owner accepted it explicitly — *"Accept all three, ship stage 1, then the double
        precision move comes later and integrates in with it."* The float's box is a geometric AABB of
        moved ink, so rotate +45 degrees then -45 returns a bigger box, monotonically over repeated
        gestures. **(14) is the cure and the owner named it as the follow-up.**

### (13) Canvas padding shares one 16k budget, and the base maximum rises

- [ ] The owner: *"the canvas plus the padding should have the maximum size of 16k ... Right now canvas
      padding just has a set maximum of something like 500px, I kind of want to make that maximum a bit
      higher like 1000, unless of course it is bounded by the 16k canvas+padding limit."*
      Their memory was nearly exact: `canvasPaddingRange` is `0...512`, a flat constant.
      **The rule**: padding's upper bound becomes `min(1024, (16384 - canvasExtent) / k)` — 1024 on
      ordinary canvases, shrinking to nothing as the canvas approaches 16k. The base rises 512 to **1024**,
      and `CanvasSizePickerView.maxDimension` rises 8192 to **16384**.
      **Confirm `k` against the code rather than guessing**: is `canvasPadding` per-side or total added
      extent? `setCanvasPadding`'s offset is described as "one symmetric number", which suggests per-side
      and `k = 2`. Wrong either way makes the cap half or double what was asked.

### (9) Resize the canvas from the Actions menu

- [ ] The owner: *"a resize canvas option in actions would be nice ... They should be able to control
      whether it gets cropped/expanded, or if everything gets scaled."* On an aspect change it
      letterboxes — *"Not in the conventional sense of adding black, just scaling the stuff so it fits."*
      **[CANVAS_RESIZE.md](CANVAS_RESIZE.md) is the specification and it is written.** Its §0 records that
      two thirds of this already exists under other names (`setCanvasPadding` is a whole-document
      crop/expand; `VectorCanvas.mapping(_:throughSimilarity:)` is the exact vector scaler), §5 carries
      thirteen settled behaviours, and **§6 is five questions the owner must answer before it is built** —
      chiefly what the width/height field means and what undo does over raster content. §6's question on
      the encoding is answered by (8).
      **BUGS.md carries a defect on this path**: Canvas Padding while a vector Move is held cancels
      pre-resize geometry onto the resized cel. Left unfixed on purpose, because this item rebuilds that
      path.

## Open

### (18) The bottom bars should be as tall as their contents — attempted, reverted, still open

- [ ] The owner, on the bottom bars as shipped: *"bottom bars are alright. Try to make that menu shorter
      vertically because alot of them contain only 1 or 2 sliders which covers like half of it. You already
      added the vertical scrolling thing to the bottom bar for things with more, so it should be good."*
      Nine of thirteen effects have two controls or fewer, against a flat 300 pt cap.
      **The obvious implementation was built, measured and reverted (`785f3f7`), and the dead end is the
      finding.** A `PreferenceKey` plus `.background(GeometryReader { ... })` on the outer rows `VStack` —
      the standard way to read a resolved size without an unbounded scroll-axis proposal — measures
      **exactly 0** for every effect and clips the rows away entirely. `CurveEditor`'s own doc in that file
      already names this failure for a more direct case; what is new is that **`.background` does not
      shield you from it**.
      **The XCUITest passed against the broken build**, which is the part to remember: accessibility frames
      reported plausible differing slider positions while nothing was painted, because a clipped view's
      frame does not reflect what rendered. Only an on-screen debug overlay read back through a screenshot
      caught it. **So a screenshot is this item's acceptance test, not a frame comparison.**
      **The candidate next approach**, recorded on `maxRowsHeight`: measure an `.accessibilityHidden(true)`
      twin of the rows laid out *outside* any `ScrollView`, never entering the unbounded-proposal path.
      Scope is `EffectSettingsBar` alone — `TextSettingsPanel` is greedy by construction
      (`.frame(maxHeight: .infinity)` on its own body) and would need that deleted first, and the owner's
      own words suggest they consider Add Text fine.
      **Note the target moved slightly**: Bloom and Sobel each gain a control from the effect-backdrop
      ruling, so Sobel stops being the zero-control degenerate case.

### (10) Oklab colour storage and processing, from the Actions menu

- [ ] The owner: *"I also want the option in actions to switch the color storage and processing to oklab
      or other future models. Oklab may give better compositing."* A **document-level switch with room for
      future models**, not a one-way conversion.
      **Not a memory argument** — colour is per *stroke*, not per sample (32 bytes x 190 strokes = 6 KB on
      a cel measured on the owner's own device). The argument is quality: perceptually uniform blending,
      better gradients, and better interpolation between keyframes, where RGB goes muddy through the middle
      between two saturated hues. Their *"better compositing"* is the sharpest version and is the thing to
      verify: compositing happens in `Composite.metal`, so a real Oklab mode is a shader change and not
      only a storage change. Costs a conversion at stamp time and a decision about whether the picker works
      in Oklab.

## Carried — deliberate, and not an ask

- **The raster Move's undo half of [LASSO_MOVE.md](LASSO_MOVE.md) §5 rulings 5 and 10 is not built** (the
  vector half and selection-at-bake shipped). A raster nudge changes only `FloatingPiece.transform`, which
  is transient and not in the document, so per-nudge steps must be transient — and the bake step then sits
  on top of them and its undo restores the pre-move cel, killing every step beneath. Making it work means
  the bake step's undo *re-creating the float* at its last transform, which doubles what a raster Move
  retains and needs `finalizePendingGesturesForHistoryAction` to grow a raster-float arm it has never had.
  A second feature. See LASSO_MOVE.md §3 stage 4.
- **Move stages 3b, 3c and 5** — the yellow box-only rotate knob; placed images holding a stretched shape;
  Distort on both tiers consuming the shared `Homography` solver, with the ink-deformation toggle
  defaulting off. LASSO_MOVE.md §0 lists what each deliberately left out. **3c is now the only half of the
  Freeform/Mirror gate still closed** — text was opened 2026-08-27, images were not, because
  `VectorImageElement.transform` is a `LayerTransform` with nowhere to put a flip or a second-axis scale
  and so needs a stored field plus a decode migration, where text's four corners cost neither.
- **A Freeform-stretched text box inherits the distort-mode minimum-size exemption**, so it can be dragged
  smaller than its own text. Rode along with the 2026-08-27 text-transform change, is recorded in
  `sizedInBoxSpace`'s own doc with the two-line conditional that would undo it, and is **unruled**.
