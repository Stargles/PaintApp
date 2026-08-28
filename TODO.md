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

- **Nothing.** Item (8) merged as `e277f82`; the five-item refit is down to (14) and (9).

## How a brush stroke is stored — one feature in five items

**The owner's own framing, 2026-08-27:** *"there are alot of tasks in there currently which are all
parts of the same feature, being the refit to the way brush strokes are stored. (8), (12), (13), with
(9) and (14) are features of the feature."* Read the five as one refit and sequence them together;
splitting them across sessions is what let their premises drift apart in the first place.

**Five asks, one programme**, sharing one number. Three are merged, two remain.
**`CanvasManager.maxCanvasExtent` — 16383 — is that one number**: the maximum canvas, the ceiling the
canvas-plus-padding budget is derived from, and what a stored coordinate can address. It is defined
once, and (8)'s codec derives its own bounds from `Int16` rather than restating it.

**Order, and it is forced rather than preferred: (12) stage 3 → (13) → (8) → (14) → (9).**
The first three are **merged** — (12) stage 3 `2fa1725`, (13) `83f7c0d`, (8) `e277f82` — and have
left this file. So **(14) is next** — and scoping it on 2026-08-27 found that (8) had *answered* it
rather than unblocked it: the quantiser (14) wanted something to bake back **to** turned out to be a
save-time codec with no resident 16-bit form, and the doubles it wanted the Move held in were always
what the Move held. (14) is therefore one question for the owner rather than a piece of work; see
below, and do not schedule it as a build until that question is answered. (9) is genuinely
independent *because* the width is fixed, so a resize re-encodes nothing — and more so now that a
payload carries the origin it was quantised about, which leaves an unresaved cel readable whatever
the canvas becomes.

### (14) A reversible Move: hold the transform in doubles until an explicit bake

- [ ] The owner: *"In the move tool have an option to store whatever the transformation is as doubles so
      it is reversible, and add an option in actions to bake everything down back to 16bits."* It
      arrived unprompted as the answer to the strongest objection against (12) — that a layer
      transform was the only exactly reversible operation in the app.
      **Scoped 2026-08-27, and the scope came back saying the mechanism already exists.** Nothing here
      is built or merged, so the item stays; but what remains of it is one owner question, not a
      branch.

      **The doubles half already holds.** Every nudge maps `float.liftedInside` — the elements exactly
      as the lift produced them — so a drag is an *absolute* map from the lift rather than an
      increment on the current geometry, and there is no term for an error to accumulate in.
      `VectorSample.x/y/pressure` and `VectorStroke.size` are plain `CGFloat` in memory and always
      were; (8) never touched them. Measured: 100 shrink-to-2%-and-regrow cycles drift **6.0e-11 pt**
      and `stroke.size` returns bit-exact. `LassoMoveLogicTests.testAScaleOutAndBackIsPixelIdentical`
      already scales a lassoed piece 2.5×, turns it 0.7 rad, drags the box back to the lift pose and
      asserts the drawing is pixel-identical.

      **The bake half has no referent.** (8) made the 16-bit form a *save* format: `PackedSampleRun`
      quantises on the way to disk and decodes back to `CGFloat`, so there is no resident 16-bit
      representation for an Actions item to bake down *to*. One save is one rounding — measured at
      0.0 pt drift over a hundred consecutive saves. If the owner still wants the option, what it
      would mean today is "snap every sample to the storage grid on demand", which is a different
      feature and worth asking about before building.

      **Both stated residues were misdiagnosed, and both corrections are now executable.**
      - **`BrushStamper.stampSpacing`'s 1 pt floor is not a Move residue.** It is
        `max(brushSize * spacingFraction, 1)` and binds at native sizes with no transform anywhere
        near it — Hard Round's fraction is 0.05, so a 9 pt brush wants 0.45 pt of spacing and gets
        1 pt, on a cel nobody ever lassoed. Precision cannot remove an absolute constant from a
        relative walk, so (14) was never its cure. It costs no ink (dab diameter still scales) and
        re-rolls nothing visible (every built-in has zero scatter and zero rotation jitter), and a
        scale out through it and back gives the identical dab count —
        `testTheSpacingFloorSurvivesAScaleRoundTrip`.
      - **The Move box does not inflate monotonically, and precision is not its cure either.**
        `contentSize` is written at the two lift sites and nowhere else — `applyToVectorFloat` writes
        the transform, the aspect and the mirror — so **no gesture re-measures the box**, and a full
        turn inside one lift is exact (`testTheBoxDoesNotInflateWithinOneLift`). What inflates it is a
        *fresh lift of already-tilted ink*, because `localBounds(of:)` re-applies its `stampRadius`
        padding axis-aligned instead of carrying it round with the ink. Measured on a 100 × 20 bar,
        over lift / rotate 45° / bake / re-lift / rotate back / bake / re-lift:
        **100 × 20 → 76.57 × 76.57 → 100 × 20**. Nothing feeds the box back into the geometry, so it
        tracks the tilt in both directions and never ratchets
        (`testARotateBakeAndReliftInflatesTheBoxAndTheRoundTripDeflatesItAgain`).

      **What is left is one question for the owner: should the Move box carry its own rotation?** An
      oriented rectangle around tilted ink is the only thing that would make a re-lift measure the
      same box twice, and it changes what the handles look like — a visible behaviour change, so it is
      the owner's call rather than ours. The existing acceptance — *"Accept all three, ship stage 1,
      then the double precision move comes later and integrates in with it."* — was given against the
      monotonic reading of the box, so the corrected one is worth putting in front of them with it.

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
