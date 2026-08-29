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

- **(21) Keyframes — stages 0 through 3a merged**, spec at [KEYFRAMES.md](KEYFRAMES.md). `654f863`
  `renderTree(atFrame:)`; `c09ddf0` `AnimationCurve`; `c6ecb49` + `6a379bf` the effect
  parameter-descriptor table with the settings bar reading it; `4d55aae` one layer effect parameter
  animating end to end; `6158e8b` the same on a folder's grade (§2.21); `f2f85b5` **Animate mode and
  the keyframe button — the first stage the artist can see**. Fast tier **2066 / 2063 / 0 / 3**.
  **Next is stage 3b — the channel panel and the graph-editor drawer.**

## How a brush stroke is stored — one feature in five items, and all five are merged

**The owner's own framing, 2026-08-27:** *"there are alot of tasks in there currently which are all
parts of the same feature, being the refit to the way brush strokes are stored. (8), (12), (13), with
(9) and (14) are features of the feature."* Read the five as one refit — splitting them across
sessions is what let their premises drift apart in the first place.

**Done 2026-08-28**: (12) stage 3 `2fa1725`, (13) `83f7c0d`, (8) `e277f82`, (14) `7eef540`, and (9)
in four stages — `ea51607`, `3d0c7c4`, `b42a67b`, `c35df15`. `CANVAS_RESIZE.md` §4 stage 4 is deferred
polish nobody has asked for. **`CanvasManager.maxCanvasExtent` — 16383 — is the one number they
share**, defined once, with (8)'s codec deriving its bounds from `Int16` rather than restating it.

**The finding worth keeping now the programme is done, because it will be assumed wrong otherwise.**
(9) proved independent of the rest *because* the width is fixed and each payload carries the origin it
was quantised about — so a resize re-encodes nothing and an unresaved cel stays readable whatever the
canvas becomes. But the resize's cost was never the encoding: MEASURED at **0.9 ms/cel** on a document
shaped like the owner's real artwork (190 strokes x 46 samples a cel, blank raster tiers), **97% of it
the in-memory vector walk**, of which **84% is array allocation and 15% arithmetic**. The earlier
3-4 s figure came from a raster-only fixture whose cels held no `VectorCanvas` at all. And the obvious
fix — re-adopting a translation-only layer transform so a crop touches no sample — **does not skip the
walk, it moves it**: `VectorCanvasData.init(from:)` bakes any carried transform on encode, so the cost
lands in the next save, off a path the artist is told is loading. See PERFORMANCE.md item 18 and
LAYER_TRANSFORM.md.

## Open

### (21) Keyframes — animating properties across the frames one cel spans

- [ ] The owner: *"Keyframes: (objects within a cel can get keyframed and move for the duration of that
      cel). Also applies to stuff like sliders for effects. Also includes interpolation curve
      customization. You should also be able to bake the cel containing animation into multiple cels
      (frames), and also set frame rate. Transformation layers adds transformation animation to whatever
      is under it."*

      **[KEYFRAMES.md](KEYFRAMES.md) is the specification.** ROADMAP item (1), designed 2026-08-28 in the
      conversation that file names as each item's entry condition. **§2 carries twenty-four rulings — read
      it rather than re-deriving them**, and §8 is the build order. The three that shape everything else:
      a transform key stores a **quad** from day one, so Distort lands later with no migration; posed ink
      is drawn by **baking the dab walk in rest space** and mapping dab centres, which removes the
      shimmer *and* the per-sample-width problem at once; and **bake is an authoring feature, never a
      performance instruction** — smooth playback comes from a cache.

      Stage 0 is `renderTree(atFrame:)` and is behaviour-neutral. §8 also names one prerequisite that is
      not part of this feature and is worth doing first anyway: VECTOR_INTERPOLATION item 18's
      `ContentProvider` seam, which is what makes any derived content visible to thumbnails, onion skin
      and export — and which ROADMAP §0 already flags as blocking item (5).

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
  what each deliberately left out. **Stage 3b left this list on 2026-08-28, built and merged in three
  phases** — the knob `330efd4`, the stretch axis `c78de6e`, the re-fitting box `5b5577e`. **3c is now
  the only half of the
  Freeform/Mirror gate still closed** — text was opened 2026-08-27, images were not, because
  `VectorImageElement.transform` is a `LayerTransform` with nowhere to put a flip or a second-axis scale
  and so needs a stored field plus a decode migration, where text's four corners cost neither.
  **Stage 3b phase 3 left 3c a tripwire**: the re-fitting box measures a placed image exactly, but only
  because Freeform is refused on a float holding one, so its frame is always a rotation and the
  axis-aligned pad is exact. Teaching images to stretch breaks that, and the code note beside it says
  what the fit would then need — the frame's row norms rather than a scalar pair.
- **A Freeform-stretched text box inherits the distort-mode minimum-size exemption**, so it can be dragged
  smaller than its own text. Rode along with the 2026-08-27 text-transform change, is recorded in
  `sizedInBoxSpace`'s own doc with the two-line conditional that would undo it, and is **unruled**.
