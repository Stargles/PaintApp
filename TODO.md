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
      conversation that file names as each item's entry condition. **§2 carries twenty-five rulings — read
      it rather than re-deriving them**, and §8 is the build order. The three that shape everything else:
      a transform key stores a **quad** from day one, so Distort lands later with no migration; posed ink
      is drawn by **baking the dab walk in rest space** and mapping dab centres, which removes the
      shimmer *and* the per-sample-width problem at once; and **bake is an authoring feature, never a
      performance instruction** — smooth playback comes from a cache.

      Stage 0 is `renderTree(atFrame:)` and is behaviour-neutral. §8 also names one prerequisite that is
      not part of this feature and is worth doing first anyway: VECTOR_INTERPOLATION item 18's
      `ContentProvider` seam, which is what makes any derived content visible to thumbnails, onion skin
      and export — and which ROADMAP §0 already flags as blocking item (5).

### (22) Keyframe UI — the workflow the owner wants, replacing Animate mode

- [ ] The owner, 2026-08-29, six asks in their own words:

      1. *"clicking on a keyframe's frame should bring up the option to remove it in the pop up, along
         with the others already implemented (copy, extend to end, select multiple, clear). Also the
         option to clear all keyframes in that cel."*
      2. *"right now lets say a layer is set to chromatic aberration, then the effect is changed. This
         should destroy the keyframes. Right now when you change it and go back they are still there
         which means they are being stored where they dont have to."*
      3. *"I'm not sure if I like the animation mode. Just make it this workflow: select on cel, tap
         again, tap add keyframe icon in the menu, everything gets saved at that point. Then select
         another frame, edit sliders etc, tap add keyframe again and the new keyframe data at that frame
         is saved. When tapping the keyframe button it brings up the list of things being animated and
         graph editor instead of placing a keyframe (icon and its name also may have to be changed to
         graph editor). This means removing the current keyframe mode UI. This means that animations
         will be added to the list when two keyframes are placed, and something changes in one keyframe
         which from the other."*
      4. *"The graph editor is going to have a lot more control for the animation keyframes (like graph
         editors are supposed to have, refer to something like maya or blender). The keyframes for the
         animations (basically anchor points) can be moved, added and removed from there."*
      5. *"I wonder if we can integrate the graph editor into the animation timeline, like it pops up
         above the layer that has it when on. That will save a lot of space and make it visually
         consistent with the timeline. The list of animations though I am not sure where to put.
         Probably as a scrollable menu may be best."*
      6. *"for the graph editor, the ability to use the select tool on it to select the keyframe nodes
         and move them could be a good idea, as well as the ability to use it on cels to select multiple
         at once in the future."*

      **Ask 3 supersedes KEYFRAMES §2.1, §2.23 and §2.24** — the tap/hold Animate mode, the auto-key on
      an already-animated channel, and the tap-keys-every-channel rule. That is the owner changing their
      mind about their own ruling and is not a re-litigation. §2.22 (the button lives in the timeline
      strip) and §2.17 (the graph editor grows the timeline upward) both survive and ask 5 sharpens §2.17
      from "above the timeline" to "above the layer row that owns it".

      **The curve model already covers ask 4.** `AnimationCurve` ships with bezier handles, five tangent
      modes, per-segment interpolation and per-channel step — `setKey` / `removeKey` are there. What is
      missing is the editor, not the model.

      **Merged 2026-08-29**: ask 2 in `de4e43e` — a grade's keyframes die with the grade, filtered by
      parameter id because *both* case-shaped tests in this tree are wrong for it (`kindCode` merges
      Levels with Curves at 0, `EffectCatalog.isCurrent` splits one `.blur` in two). Ask 3's whole model
      in `167e44a` — bare keyframe marks, held baselines, the five-arm slider rule, `addKeyframe` /
      `removeKeyframe` / `clearKeyframes`, and Animate mode deleted outright.

      **Merged since**: ask 1 in `4057e9d` — the cel menu's Add / Remove / Clear Keyframes, and a bare
      keyframe drawing hollow so the artist can see whether an edit landed on a channel. The graph
      editor's first stage in `4329e3d` — row geometry as a lookup over per-row heights, behaviour-
      neutral, because `AnimationTimeline`'s reorder drag counted rows by dividing by a fixed pitch and
      one tall row would have broken it silently. Both of the owner's device-reported bugs in `a85a316`,
      which were one divergence: a curve key and a keyframe mark drew identically and were different
      things, so a diamond could exist that the menu could not remove and the seeding logic skipped.
      §2.28 is the invariant that closed it.

      **Still open**: asks 4, 5 and 6 — the graph editor itself. **KEYFRAMES §11 is the design**, stages
      D2 (the band), D3 (the gestures, including the marquee) and D4 (the channel list). §11.3's three
      silent-failure modes are the brief for D2.
### (23) Selection membership modes belong to Select, not to Move — so Recolour can use them

- [ ] The owner, 2026-08-29: *"Right now the enclosed/cut/touching option for the select move is in
      move, but i feel like it would be better in select menu because i want it to affect recolour. For
      enclosed on recolour, it would have to split the strokes and other objects around the lasso border
      and then recolour the ones inside. Luckly, the splitting already exists in enclosed move, so you
      can reuse that. This task is not necessarily priority but put it in TODO.md."*

      **Not priority — the owner said so.** Recorded here rather than researched, per the standing rule.

      Two things the ask already settles, and they are the reason it is cheap. The **modes exist** —
      LASSO_MOVE §5.23-24 rules how Touching and Enclosed treat text and placed images, and §5.25 rules
      that Clear cuts at the loop rather than deleting every element it touches, which is the same
      split-at-the-border behaviour this asks Recolour to grow. And the **splitting exists**: Enclosed
      move already cuts strokes and fills at the lasso boundary, so Recolour-with-Enclosed is a new
      caller of a built operation rather than new geometry.

      What it is really asking is that membership stop being a property of *the Move tool* and become a
      property of *the selection*, which is the more honest home for it — every tool that consumes a
      lasso then inherits it for free instead of each one growing its own copy. Whether that is a move of
      the control or a duplicate of it is the one design question, and §5.25's precedent argues for a
      move.

### (10) A colour-pipeline switch per document — linear light now, Oklab where it earns its keep

- [ ] The owner's original ask: *"I also want the option in actions to switch the color storage and
      processing to oklab or other future models. Oklab may give better compositing."* The complaint behind
      it: *"RGB goes muddy through the middle between two saturated hues."*

      **Ruled 2026-08-29, having been shown the A/B**: *"toggle option between OKlab and normal (i believe
      its srgb). You decide the best route for the oklab, as i dont fully understand what this is asking me.
      The stored flag per document is minimal memory, and do try to keep performance and good architecture
      in mind with OKlab."* A per-document stored switch, and the technical route delegated.

      **The route, on that delegation: the switch's two positions are sRGB (today, the default) and
      *linear light* — not Oklab.** [LINEAR_LIGHT_AB.md](LINEAR_LIGHT_AB.md) is the rendered evidence and
      the owner has seen it. The muddy middle is a gamma artefact, worst case MEASURED at **73/255**, and
      linear light removes it. Oklab does not remove it any better and costs a cube root per pixel per
      frame, 16-bit textures — doubling every canvas-sized buffer, the resource `CompositorBudget` and the
      iPad 9 crash test exist to manage — and the parity gate, because a cube root sits *after* a matrix
      mix of the three channels and cannot be tabled. sRGB-to-linear is *per-channel*, so it is a
      256-entry LUT and identical on both backends by construction. **Store the setting as an extensible
      enum, never a `Bool`**, so Oklab becomes a third position with no format change — which is what the
      owner's *"or other future models"* asked for.

      **Oklab still gets built, for interpolation**: gradient map, keyframe colour tweens, the picker's
      gradients. Per-colour rather than per-pixel-per-frame, so the cost is nil and none of it is inside
      the parity gate. That is where the owner's "better gradients" instinct is right.

      **Storage does not change.** Colour is per *stroke* — 32 bytes x 190 strokes = 6 KB on the owner's
      own cel — while compositing is per *pixel*, every frame. Storing Oklab saves converting 190 colours
      once, does nothing for the composite, and makes every swatch, export and PNG pay a conversion per
      *display* instead.

      **What reading the shipped code changed about the plan, and it is the expensive part.**

      - **The compositor is one of three coverage sites, and not the one the artist paints on.** Every
        brush dab is a `CGGradient` in `PixelOps.deviceRGBColorSpace` drawn into a persistent 8-bit
        DeviceRGB bitmap (`RasterLayerTexture.swift:66-102`), and a cel's four tiers stack through
        `UIImage.draw(in:)` (`PixelOps.rasterizeUncached:296-332`). Only cross-*layer* work reaches
        `blendOver`. **A switch that linearizes only the compositor leaves the soft-dab ring in place
        whenever both hues are on one layer**, which is the ordinary way a painter works. The dab path is
        in scope; a compositor-only version is not worth shipping.
      - **Ten modes on the CPU backend are computed by CoreGraphics itself** (`Compositor.swift:429-455`,
        called at `:1078`), Normal among them, and `image.draw(in:blendMode:alpha:)` has no hook for a
        transfer function. Linearizing forces all ten onto `drawHandRolled`, documented at `:1092` as
        *"slow on purpose… three canvas-sized allocations for one draw"*. This is a shader edit **plus**
        the deletion of the reference backend's fast path.
      - **"Byte-for-byte parity gate" is half true.** Delta 0 holds for source-over and masks
        (`CompositorParityLogicTests.swift:906-942`); blend modes hold at `blendTolerance = 1` (`:968`),
        with eight already sitting at 1 in the measured table at `:991`. The LUT argument survives on the
        way **in** for every formula in the tree, the six non-separable modes included, since they mix
        already-transformed channels. It does **not** cover the way out: `blendOver`'s result is a
        continuous float, so linear→sRGB is either a `pow` on both backends (a last-ulp risk the delta-0
        Normal gate would catch) or an 8-bit-linear quantization that bands the shadows. **Unruled.**
      - **One design question the switch creates rather than inherits**: `lum`'s 0.3/0.59/0.11
        (`Composite.metal:145`) are specified on *non-linear* values, so linearizing changes what Hue,
        Saturation, Color and Luminosity **mean**. **Unruled.**

      **The cost side is currently free and will not stay free.** Every antialiased grey edge gets lighter
      by up to 73/255 — coverage 0.5 goes 128 → 188 — so hairlines, antialiased text and soft shading in
      existing artwork read thinner and paler. Defaulting the switch to sRGB makes that opt-in, and the
      standing expendable-documents permission at the top of this file means today is the cheapest this
      change will ever be.

### Playback at 24 fps, with in-betweens — the owner's goal, ranked and not started

- [ ] The owner, 2026-08-29: *"Basically I want the app to be able to play in realtime even with in
      betweens... if a smarter faster way is possible which doesnt require a lot of code, then sure."*

      **[PERFORMANCE.md](PERFORMANCE.md) §8 is the ranked list** — five entries, each naming what is
      already measured and what would have to be established. Nothing is started. Two facts decide how it
      reads: **composited playback already misses 24 fps on the device in Release before interpolation is
      involved** (§2 item 5), so this is not one delta away; and **KEYFRAMES §4.6's span cache does not
      cover it**, because §4.6 scopes itself to the transformation layer and export, so shipping stage 6b
      as specified changes nothing here.

      The two cheapest wins **share one prerequisite** — hoisting the playback clock onto the model, which
      ROADMAP §4 (audio) and KEYFRAMES §5 (recording) already require for their own reasons. That makes
      the clock the highest-leverage thing on this list and the natural first move.

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
