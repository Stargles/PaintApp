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

**No document written so far has to survive.** The owner, 2026-08-27: *"Don't worry about legacy
documents right now, everything on the ipad right now is expendable."* So a format change needs no
migration, no decode default for a field that never existed, and no "existing documents change
appearance on first open" warning — **which is what unblocks (12) stage 3, and through it (8)**. This is
a standing permission and not a one-off; it lapses the day the owner starts keeping real artwork in the
app, and whoever notices that should come back and say so rather than assuming it still holds.

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure collected before 2026-08-17 was taken at 4096 squared, eight times the pixels.

## In flight

- **Nothing.** The effect backdrop's six stages are merged.

## How a brush stroke is stored — one feature in five items

**The owner's own framing, 2026-08-27:** *"there are alot of tasks in there currently which are all
parts of the same feature, being the refit to the way brush strokes are stored. (8), (12), (13), with
(9) and (14) are features of the feature."* Read the five as one refit and sequence them together;
splitting them across sessions is what let their premises drift apart in the first place.

**Five asks, one programme**, sharing one number. **16,384 pt is the span of a stored coordinate, the
maximum canvas, and the canvas-plus-padding budget**, and it should be defined once in the code.

Dependency in one line: **(8) needs (12) stage 3, and this file said for a day that it needed
nothing**; **(12)** is what narrowed (8)'s field to 16 bits; **(14)** answers the strongest objection
to (12); **(13)** sets the 16,384; **(9)** is independent of all of them *because* the width is fixed,
so a resize re-encodes nothing.

**The correction, found 2026-08-27 by reading rather than by building.** *"The centre of the current
canvas"* is only a well-defined encoding origin once a cel's geometry is in canvas coordinates, and it
is not: persisted samples are in layer-**local** space, so the origin is undefined for any document
whose `VectorCanvas._transform` is not identity. (12) stage 3 is what makes it identity. Until then a
quantiser would be measuring from a point that moves with the cel. Two more premises of (8) went the
same way and are folded into it below: the memory win and the bit budget.

### (8) Fixed-point sample coordinates — SETTLED, build it

- [ ] **16 bits an axis, signed, origin at the centre of the canvas, quarter-pixel; 8 bits of pressure.
      40 bits = 5 bytes a sample against today's 24.** **The "4.8x in memory" this item used to claim
      was wrong and contradicted its own attached ruling**: the ruling says in memory samples stay as
      they are, so **memory does not change at all** and the whole win is on disk — where it is much
      larger than 4.8x. MEASURED: the marginal cost of one full-precision sample in this app's own
      JSON is **~77 bytes**, not the 89 this item quoted; 89 was the whole-file average from the
      owner's `Untitled.paintproj` (776 KB / 8,714 samples), and the ~12 bytes/sample difference is
      per-stroke header — **dominated by a whole `Brush` struct embedded in every stroke, ~13.5% of
      that file, which this item does not touch and which may be the cheaper win.**
      **The field addresses ±8192.0 … +8191.75, a span of 16,383.75 rather than 16,384**, so with the
      origin at the centre the largest safe canvas dimension is **16383** — see (13), whose 16384 is
      one too large. At the maximum canvas the clamp therefore saturates a quarter-pixel *inside* the
      artwork on two edges, not merely at the boundary. `VectorSample` is three `CGFloat`, not two — the third is pressure,
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
      - **Stages 2 and 3 are merged** (`683983c`, `2fa1725`). Stage 2 deleted the whole-layer path after
        verifying its premise rather than assuming it — five sites wrote `isVectorTransforming` and every
        one wrote `false`. The brief's deletion list was **incomplete**: four more things were dead with
        it, including `StrokeCanvasView`'s entire `liveLayerTransformBase` latch trio and `Tool.isMomentary`.
        `moveBoxIsUp` is now exactly `hasVectorFloat`, and the question it forced was ruled: **a Move box
        may be up on a hidden layer**, because the lift is already out of the document. Test count
        1802 → 1782, accounted test by test (−22 for `VectorTransformUndoLogicTests`, whose every test
        drove the deleted flag; −2 for `Tool.isMomentary`; +4 persistence).
        **Stage 3 found a second door onto the owner's own ink loss.** After stage 2, `setCanvasPadding`
        was the *only* remaining producer of a non-identity cel transform, and it walks every cel of every
        layer — so one use of the padding slider left a non-identity transform on every cel in the
        document, each of which then clipped later canvas-space ink in local space. The same loss the
        owner reproduced through the Move box, reachable through the Actions menu instead. Baking
        `resized(to:offset:)` is what makes "no path writes a cel transform" true rather than nearly true.
      - **Stage 4 — judged and declined, not forgotten.** `_transform` is dead-*valued*, not trivially
        dead: ~20 read sites remain and five test files exercise non-identity transforms deliberately.
        LAYER_TRANSFORM.md §7 prices the removal at 2-3 days for clarity and no behaviour. Its two
        genuinely zero-caller accessors were taken. Re-open only if something else makes it cheap.
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

### (13) Canvas padding shares one 16k budget — MERGED `83f7c0d`

- [x] Built as ruled. `canvasPaddingRange` is a live instance property bounded by
      `min(1024, (16383 - artworkExtent) / 2)`; `CanvasManager.maxCanvasExtent = 16383` is the single
      named home and `CanvasSizePickerView.maxDimension` reads it. All three of the item's corrected
      numbers held against the code — `k = 2`, 16383 not 16384, and `canvasSize` already including the
      padding.
      **What raising the maximum exposed is bigger than the feature, and is filed in BUGS.md rather
      than fixed.** The compositor degrades gracefully — `affordableSize` scales a 16383² preview down
      to about 2896² on the owner's own iPad 9 before allocating anything, and a blank cel is lazy
      enough to cost nothing. But `CompositorBudget` only ever bounded compositor **scratch**: the
      persistent raster, fill and baked buffers a cel materialises once something is actually drawn on
      it go through no budget at all, and **one of them at 16383² is ~1.02 GB** — more than a 3 GB
      iPad's entire process budget. Whether a near-maximum canvas is understood to be vector-only is a
      product call, not a one-line fix.

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
      **Note the target moved slightly**: Bloom gains a control from the effect-backdrop ruling. Sobel
      gained one too and the owner deleted it the same day (EFFECT_BACKDROP.md §5.2), so **Sobel is still
      the zero-control degenerate case** this bar has to handle — a note and nothing else.

### (10) Oklab colour storage and processing, from the Actions menu

- [ ] The owner: *"I also want the option in actions to switch the color storage and processing to oklab
      or other future models. Oklab may give better compositing."* They then asked for a recommendation on
      whether to **store** Oklab or convert at use, guessing that storing it avoids a transform and is
      therefore faster, and asked for the call to be made for them.

      **RECOMMENDATION, 2026-08-27: do not store Oklab, and do not put it in the compositor. Three
      stages, and the first one is not Oklab at all.**

      **Storing Oklab moves a conversion rather than removing one, and moves it somewhere worse.** Colour
      is per *stroke* — 32 bytes x 190 strokes = 6 KB on the owner's own cel — while compositing is per
      *pixel*, every frame. Storing Oklab saves converting 190 colours once and does nothing for the
      composite; meanwhile every swatch, every export and every PNG needs sRGB, so the conversion is paid
      per *display* instead. The owner's performance intuition is the one part of their guess that
      inverts.

      **Three blockers, all specific to this tree.** Every texture is `rgba8Unorm`
      (`MetalCompositor.swift:173`), and Oklab's a/b are small signed values that band at 8 bits on
      exactly the saturated colours this is for — 16-bit float doubles every canvas-sized buffer, which
      is the resource `CompositorBudget`, `peakCompositeTextures` and the iPad 9 crash test all exist to
      manage. `CompositorParityLogicTests` gates the two backends **byte for byte**, with eleven blend
      modes additionally gated against `CGBlendMode`, and Oklab needs a **cube root** whose Metal and
      Foundation implementations are not guaranteed bit-identical — `Composite.metal`'s header says the
      byte-identical comparison is the whole reason the textures are unmanaged. And coverage compositing
      is averaging light, so a perceptual space is the wrong home for it regardless; Oklab's real win is
      **interpolating between two colours**, which is what the owner's "better gradients" and "better
      keyframe interpolation" instincts are actually about.

      **The finding that is probably bigger than the ask.** The compositor blends in **sRGB,
      unlinearized**, deliberately (`Composite.metal:8-12`). That is the classic gamma problem: a
      half-covered edge between two saturated hues lands at the sRGB midpoint rather than the light
      midpoint and reads muddy — which is nearly word for word the symptom this item already described as
      *"RGB goes muddy through the middle between two saturated hues"*. It is a **linear-light** problem,
      not an Oklab one.

      **And the distinction that decides the whole item: sRGB-to-linear is a *per-channel* function, so on
      8-bit input it is a 256-entry lookup table and therefore bit-identical on both backends by
      construction. Oklab's cube root sits *after* a matrix mix of the three channels and cannot be tabled
      that way.** One is compatible with the parity gate; the other is not.

      - **Stage A — composite in linear light through a 256-entry LUT.** Same class of win, cheaper,
        probably the thing the owner is seeing, and provably keeps parity. Verify the muddy-edge symptom
        first with a rendered A/B rather than assuming it.
      - **Stage B — Oklab for *interpolation only***: gradient map, keyframe colour tweens, the picker's
        gradients. Per-colour rather than per-pixel-per-frame, so the cost is nil, and all of it sits
        outside the parity gate.
      - **Stage C — Oklab blend modes**, only if A and B leave the owner still wanting them, and knowing
        it breaks the `CGBlendMode` gate for eleven modes.

      The *"document-level switch with room for future models"* the owner asked for should therefore be a
      property of **interpolation**, not of storage. Storage does not change.

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
