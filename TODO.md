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

- **(14), on `tmp/revmove`.** Built, not merged, so it stays in this file. Item (8) merged as
  `e277f82`; the refit's last *unbuilt* member is (9).

## How a brush stroke is stored — one feature in five items

**The owner's own framing, 2026-08-27:** *"there are alot of tasks in there currently which are all
parts of the same feature, being the refit to the way brush strokes are stored. (8), (12), (13), with
(9) and (14) are features of the feature."* Read the five as one refit and sequence them together;
splitting them across sessions is what let their premises drift apart in the first place.

**Five asks, one programme**, sharing one number. Three are merged, (14) is built and awaiting a
merge, and **(9) is the only one left to build**.
**`CanvasManager.maxCanvasExtent` — 16383 — is that one number**: the maximum canvas, the ceiling the
canvas-plus-padding budget is derived from, and what a stored coordinate can address. It is defined
once, and (8)'s codec derives its own bounds from `Int16` rather than restating it.

**Order, and it is forced rather than preferred: (12) stage 3 → (13) → (8) → (14) → (9).**
The first three are **merged** — (12) stage 3 `2fa1725`, (13) `83f7c0d`, (8) `e277f82` — and have
left this file. **(14) is built on `tmp/revmove`** — scoping it found that (8) had *answered* three
quarters of it rather than unblocked it: the quantiser (14) wanted something to bake back **to** is a
save-time codec with no resident 16-bit form, and the doubles it wanted the Move held in were always
what the Move held. What survived was a defect the ask had not named, and that is what shipped. (9) is
genuinely independent *because* the width is fixed, so a resize re-encodes nothing — and more so now
that a payload carries the origin it was quantised about, which leaves an unresaved cel readable
whatever the canvas becomes.

### (14) A reversible Move: hold the transform in doubles until an explicit bake

- [ ] The owner: *"In the move tool have an option to store whatever the transformation is as doubles so
      it is reversible, and add an option in actions to bake everything down back to 16bits."* It
      arrived unprompted as the answer to the strongest objection against (12) — that a layer
      transform was the only exactly reversible operation in the app. **Built on `tmp/revmove`; it
      stays in this file until that merges.**

      **The defect it fixes is not the one the ask named — it is scale across a *save*.** The doubles
      half already held: every nudge maps `float.liftedInside`, the elements exactly as the lift
      produced them, so a drag is an *absolute* map from the lift rather than an increment, and
      `VectorSample.x/y/pressure` and `VectorStroke.size` are plain `CGFloat` in memory and always
      were. MEASURED: 100 shrink-to-2%-and-regrow cycles drift **6.0e-11 pt** with `stroke.size`
      bit-exact. What (8) *did* leave is that the quantisation grid is a fixed size in **canvas**
      points, so a stroke shrunk before a save has fewer usable bits and comes back coarse when it is
      grown again. MEASURED (200 samples, real codec, worst sample, shrink → store → regrow): **0.33 pt
      at 50%, 1.75 pt at 10%, 8.57 pt at 2%**. Rotation and translation are exact, and a hundred
      consecutive saves of an untouched project drift 0.0 pt — scale across a store is the whole of it,
      and it only shows after a reopen because memory never rounds.

      **The cure, in the owner's words:** *"when the option is turned on, it gets stored as doubles.
      Then there is an item in actions to bake any strokes stored as doubles on the canvas as 16bit
      integers."* **They chose float32 over float64**, shown both: MEASURED, float32 is **12.18 bytes a
      sample against the packed form's 7.10 — 1.72x** — where float64-as-bytes is 3.2x and
      float64-as-JSON-text 8.5x, and float32 takes the three errors above to **3.3e-5, 3.9e-5 and
      5.0e-5 pt**. The further nine decimal places float64 buys are below anything that renders.

      **What shipped.** `PackedSampleRun` gains a second record layout — `Float32` x, `Float32` y,
      `UInt8` pressure — declared by a `"p":"f32"` wire key written **only** in that mode, so an
      ordinary stroke's payload is byte-for-byte what it was. `VectorStroke.precise` is *derived* from
      the wire form rather than stored beside it, because a stored copy can go stale.
      `CanvasManager.preserveMovePrecision` (off by default) is a **Keep Full Precision** toggle on the
      Move bar, and the flag is set inside `applyToVectorFloat`'s map rather than at the commit: the
      commit records nothing, so a flag set there would be a document change no undo step carries, and
      undo would give back the geometry while leaving the stroke writing nine bytes a sample for ever.
      Actions gains **Bake Precise Strokes**, one step across every layer and cel, following
      `registerVectorElementsUndo`'s whole-array swap — `withStructureUndo` could not carry it, because
      `StructureSnapshot` copies the `Layer` structs while `Cel.vector` is a **class reference**.

      **Two behaviour differences, both deliberate.** float32 **does not clamp**, so a precise stroke
      cannot be flattened onto the storage boundary by BUGS.md's unclamped zoom, where an ordinary one
      saturates and says so. And `nonFiniteCount` now counts a NaN coordinate in **both** layouts: a
      saturation is storage declining to hold ink, a NaN is a defect upstream, and the mode that cannot
      notice the first must still notice the second.

      **Both residues the ask named were misdiagnosed, and both corrections are now tests rather than
      assertions in a document.** `BrushStamper.stampSpacing`'s 1 pt floor is
      `max(brushSize * spacingFraction, 1)` and binds at native sizes with no transform anywhere near it
      — a 9 pt Hard Round wants 0.45 pt of spacing and gets 1 pt on a cel nobody ever lassoed — so
      precision was never its cure, and a scale out through it and back gives the identical dab count.
      And the Move box does **not** inflate monotonically: `contentSize` is written at the two lift sites
      and nowhere else, so what grows it is a *fresh lift of already-tilted ink*, which deflates again on
      the way back. MEASURED on a 100 × 20 bar across lift / rotate 45° / bake / re-lift / rotate back /
      bake / re-lift: **100 × 20 → 76.57 × 76.57 → 100 × 20**. The tilted figure is 76.57 and not
      120/√2 = 84.85 because `localBounds(of:)` takes the AABB of the *samples* and pads by `stampRadius`
      afterwards, so the padding is re-applied axis-aligned at every lift — the shortfall is exactly
      `2·radius·(√2 − 1) = 8.284`, structural rather than tolerance. **The box stays axis-aligned by
      owner ruling** (LASSO_MOVE.md §5.19), so that inflation is accepted and its cure is item (20)'s
      box-only knob.

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

### (20) A second knob that turns the Move box alone — both phases BUILT

      **Phase 1 merged as `87081de`; phase 2 is on `tmp/stretch` and not yet merged**, so this item
      stays here until it is. A yellow knob
      off the box's *bottom* edge (green is the content knob; `systemOrange` already means "distort
      corner" on a text box) turns `ObjectTransformFrame.boxAngle`, and **that field reaches no
      geometry at all** — it appears nowhere in `VectorLayer.swift`, and in `CanvasManager+LassoMove`
      only in `turnVectorFloatBox`, which writes it straight onto the frame with no undo step, per
      §5.21. The drag arm returns `transform: start` bit for bit, so the ink is not touched by any
      arithmetic — not scaled by 1, not rotated by 0.
      `LassoMoveLogicTests.testANonZeroBoxAngleChangesNoSampleAndNoPixel` is the guard against a leak
      into the map, and **it caught a real one**: `87081de` shipped with two lines added to
      `applyToVectorFloat` that folded `frame.boxAngle` into the geometry map — a deliberate defect a
      mutation-testing script had left on disk, which was committed and pushed by a *different*
      session while the script was between runs. The commit that follows it reverts those two lines.
      It went red on exactly the two tests you would want: that one and
      `testEightPressesOfRotate45StayBitExactOnAHandTurnedBox`. Two lessons, both already in
      CLAUDE.md wearing other costumes: a green run taken before the last edit is evidence about a
      binary that no longer exists; and **a mutation left in a working tree is indistinguishable from
      the implementation** to anyone who harvests that tree, so commit first and mutate second.
      **Reset leaves the box angle alone**, which is where §5.16 meets §5.21 and they resolve the same
      way twice: a Reset made pressable by a turned box would fire a zero-delta nudge on an otherwise
      untouched float — `nudges == 1`, the step carrying the pre-split display list — so one Undo
      after it would rejoin the cut stroke and dismiss the float; and it would destroy a hand-fit no
      Undo could give back, since §5.21 keeps the angle off the stack in both directions.
      **Freeform greyed out while the box was turned** — *"The box is turned. Straighten it to
      stretch this piece."* — the one thing phase 2 removed. Uniform and both knobs kept working at
      any angle throughout: a uniform drag scales the ratio of two radii from the anchor and reads no
      rotation.

- [x] **Phase 2 — §5.20's second stored angle** — **BUILT on `tmp/stretch`, not yet merged.**
      `ObjectTransformFrame.stretchAxis` is the axis a stretch was made about, and
      `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` builds `R(ρ+φ)·S·R(−φ)` from it — the
      singular value decomposition of a general 2×2, so `2 translation + 2 angles + 2 scales = 6` is
      **exactly a general affine**. The term completes the box's transform rather than extending it,
      and stops well short of stage 5's Distort, which needs 8 for perspective. The owner, shown the
      constraint: *"i feel like there is some kind of clever fix, but if the skew is the sensible way
      to do it, go ahead and build the skew."* The Freeform gate is gone; the placed-image refusal
      stays, being a different one.
      **The consequence this item predicted did not happen, and §5.20 now carries the correction.**
      Turning the box after a stretch *does* leave the ink perfectly still, because the stretch
      records its axis instead of reading the live `boxAngle` — and §5.21 forces that, since a box
      turn that moved ink would change the document with nothing on the stack to give it back. What
      is true instead: a second stretch about a *different* axis composes two maps that do not
      commute, so the product carries a rotation of its own, `transform.rotation` moves and the box
      turns with it. `ObjectTransformFrame.decompose` reads the product back into the four fields.

- [ ] Asked whether the handle box should turn by itself to hug ink the artist had already rotated,
      the owner ruled it should not: *"leave it straight up and down. Thats what the orange rotate node
      is for, rotating the box only"* — and then approved building the knob they had just named,
      **because it does not exist**. Today's knob turns box and content together
      (`ObjectTransformLogicTests.testTheKnobTurnsAboutTheCentreAndScalesNothing`); a box-only knob is
      LASSO_MOVE.md stage 3b, on that spec's not-built list since it was written. It is **approved and
      next**, once (14) merges. **Not part of the storage refit** — that programme's last unbuilt
      member is (9), and this shares nothing with it.

      **What it is for.** A lift of already-tilted ink lands an axis-aligned hull around the ink, which
      is loose — and item (14) established that the looseness is structural (`localBounds(of:)` pads by
      `stampRadius` axis-aligned at every lift) rather than a rounding fault, so precision was never
      its cure. The knob lets the artist hand-fit the box instead. The three rulings behind it are
      LASSO_MOVE.md §5.19–21.

      **Turning the box costs no undo step — it is free, like zooming.** A deliberate exception to
      §5.5's *"one turn of a knob is one step"*, with the owner's own reason: a box-only turn moves no
      ink, and if it were the first thing done after lifting a lassoed piece, undoing it would rejoin
      the cut stroke and dismiss the whole float (§5.8) — wildly out of proportion to straightening a
      box.

      **A Freeform stretch on a hand-turned box gets one extra stored term, and the owner chose to
      build it after pushing back:** *"If you make a selection, rotate it, then freeform stretch it, it
      stretches diagonally, but you're telling me that if the box is generated in a rotated position it
      cannot stretch the drawing along its cartisean coordinates unless another variable is added?
      Welp, i feel like there is some kind of clever fix, but if the skew is the sensible way to do it,
      go ahead and build the skew."* **The arithmetic is why it is not a hack.** Today the map is
      `R(θ)·S` — stretch in the box's axes, then rotate — which is storable. Stretching along a box
      turned independently by φ needs `R(ρ)·S·R(−φ)`, a rotation on *both* sides of the scale, whose
      singular-value decomposition is the general 2×2. So `2 translation + 2 angles + 2 scales = 6` is
      **exactly a general affine**: the extra angle *completes* the representation rather than
      extending it, and nothing is left over. It stops well short of stage 5's Distort, which needs 8
      parameters for a perspective.

      **The intended shape**: the box angle stays **chrome** and never enters the geometry map — the
      lift invariant `VectorCanvas.affine(from: frame.transform, pivot:) == baseTransform` depends on
      that — while a *stretch* records the axis it was made about. At lift both are zero and the map is
      the identity. **One consequence to state honestly**: turning the box *after* a Freeform stretch
      cannot leave the ink perfectly still, because the stretch axes are what would be turning.

      **Two small things still open, neither blocking the build**: where the second knob sits on the
      box, and what colour it is. LASSO_MOVE.md says yellow; the owner said orange, and **orange
      already means "distort corner" on a text box** (ADD_TEXT.md).

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
- **Move stages 3c and 5** — placed images holding a stretched shape; Distort on both tiers consuming
  the shared `Homography` solver, with the ink-deformation toggle defaulting off. LASSO_MOVE.md §0 lists
  what each deliberately left out. **Stage 3b left this list on 2026-08-27** — the owner approved it, so
  it is item (20) above. **3c is now the only half of the
  Freeform/Mirror gate still closed** — text was opened 2026-08-27, images were not, because
  `VectorImageElement.transform` is a `LayerTransform` with nowhere to put a flip or a second-axis scale
  and so needs a stored field plus a decode migration, where text's four corners cost neither.
- **A Freeform-stretched text box inherits the distort-mode minimum-size exemption**, so it can be dragged
  smaller than its own text. Rode along with the 2026-08-27 text-transform change, is recorded in
  `sizedInBoxSpace`'s own doc with the two-line conditional that would undo it, and is **unruled**.
