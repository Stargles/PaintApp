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

- **(20) Move's three-way membership** — scoped and ruled, below. Unblocked: (19) merged the shared
  containment predicate, already shaped as a pure geometric classifier with the kind-skipping in the
  caller, and `testContainmentAnswersForEveryKindIncludingTheOnesARecolourSkips` goes red if anyone
  folds the skipping back down into it. **The refactor the scoping pass called stage 0 is not owed.**
- **(9) stages 2-4** — scale-to-fit with the Fit/Fill choice, then undo and the busy modal. Stage 2's
  vector arm is already written: `VectorCanvas.resized` bakes the map into the elements through
  `mapping(_:throughSimilarity:)` since item (12) stage 3, which §0 did not know.
- **(9) stage 0 is merged** (`ea51607`): a failed save now raises the `CanvasNotice` banner instead of
  failing silently, which this feature needs because after a resize the in-memory document is the only
  copy. **It is only visible on the autosave path** — on "leave to gallery" the banner is raised and
  the screen flips to the gallery in the same render pass, so nothing is seen. Making that visible
  means holding the artist in the editor on failure, which needs a retry affordance that does not
  exist; **unruled, and not blocking anything.**

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

### (9) Resize the canvas from the Actions menu — stages 0 and 1 merged

- [ ] The owner: *"a resize canvas option in actions would be nice ... They should be able to control
      whether it gets cropped/expanded, or if everything gets scaled."* On an aspect change it
      letterboxes — *"Not in the conventional sense of adding black, just scaling the stuff so it fits."*
      **[CANVAS_RESIZE.md](CANVAS_RESIZE.md) is the specification, it is written, and its §6 is answered
      in full (2026-08-28) — this item is unblocked.** Its §0 records that two thirds of this already
      exists under other names (`setCanvasPadding` is a whole-document crop/expand;
      `VectorCanvas.mapping(_:throughSimilarity:)` is the exact vector scaler). The owner's four rulings
      are folded into §5: the width/height field means the artwork rect (rule 9); a lossy resize undoes
      anyway and says so up front (rule 10); an aspect change offers Fit *and* Fill, Fit still the
      default (rule 2); and the compositor's admission gate warns and lets the artist proceed — which
      also corrects a stale reading of what that gate does (rule 14, CANVAS_RESIZE.md §6 Q5).
      **Stage 0 `ea51607`** (a failed save says so) and **stage 1 `3d0c7c4`** (Resize Canvas exists,
      crop/expand only, not undoable) are merged. Stage 1 also fixed three defects `setCanvasPadding`
      had all along — guides untransformed, `copiedCel` uncleared, lattices unmoved — because both now
      share one walk; §0 listed two of the three.
      **BUGS.md carries a defect on this path**: Canvas Padding while a vector Move is held cancels
      pre-resize geometry onto the resized cel. Left unfixed on purpose, because this item rebuilds that
      path.

## Open

### (20) Move should offer three membership rules, not one

- [ ] The owner, 2026-08-28: *"Additional feature for the move tool: There should be an option of
      three where instead of cutting the lines outside the selection, it moves all the lines including
      the ones partially inside the selection, or only the ones fully inside. The third option is the
      current behaviour. I think you could reuse the color change code on figuring out the stuff
      covered by the lasso."* **Their reuse instinct is right and understated**: mode Touching is (19)'s
      predicate, and mode Enclosed is *already computed* inside the function that does the cutting —
      `splitForLassoMove`'s `runs.count <= 1` fast path (`VectorLayer.swift:1581-1586`) is exactly
      "every sample inside". So this is one parameter on one function, not three implementations.
      **Names, ordered by how much travels, default in the middle:** `Enclosed · Cut · Touching`.
      **Two rulings, 2026-08-28.** Text and placed images **follow the mode** in Touching and Enclosed
      rather than keeping the centre rule — so each mode has one sentence true of every kind — while
      **Cut keeps the centre**, which is what it has always been: a rounding of the cut rule for kinds
      that cannot be cut. And **Enclosed catching nothing says so**, unlike §5.9's silent empty lasso,
      because there the paper was blank and here the rule is what excluded a loop full of ink.
      **Mode C is already a mixture**, which is the finding that reframes the ask: text and images
      already use a third rule inside the mode called "cut". The option makes an existing
      inconsistency visible and gives it vocabulary, rather than introducing one.
      **A and B are cheaper and safer than the mode that ships**, which inverts the usual expectation:
      no bisection, no boundary dab, no fresh ids, no lattice re-keying, and — the one that matters —
      **no interpolation-tier demotion**, since stroke count is unchanged. `beginVectorWholeCelMove`
      is the working proof: a float that splits nothing and shares every nudge, bake and teardown path.
      **The picker goes on the Move bar, live while `nudges == 0`, disabled with a reason after.** The
      Select panel is invisible while anything floats (§5.13), which is the one moment the artist can
      see what the rule did. Re-lift is `cancelVectorFloat()` **then** `beginVectorLassoMove()` — in
      that order, because the latter's first statement bakes the float. Re-lifting *after* a nudge is
      a day's work with stale-closure risk on the undo stack; deferred, written down, not discovered.
      **Two traps to carry.** (19)'s predicate skips erasers and images and Move's §5.7 rules the
      opposite, so the shared thing is a per-element **classifier** and the kind-skipping belongs to
      each caller. And in Touching the marching ants stop bounding the moving ink — the ants are the
      loop, and a stroke hanging outside it now travels whole. Both correct, both will read as bugs.
      `.cutting` is the default and the setting is **not persisted** — per-drawing intent, the line
      `preserveMovePrecision` already draws (`CanvasManager.swift:348-350`). Persisting it would make
      the *last used* the default, which is not what the owner asked for.

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
