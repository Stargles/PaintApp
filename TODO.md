# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. **An item leaves when merged, not when a
branch exists.** Three in flight at once unless the extras need no simulator — see `tools/simlock.sh`.

**An ask that restates a ROADMAP feature belongs in ROADMAP, under the item it extends.** Added
2026-08-30, at the owner's instruction, after their memory-and-baking architecture was filed here as a new
item (25) when [ROADMAP.md](ROADMAP.md) §5b had been its home since 2026-08-29 and already held an earlier
statement of the same thing. The test is not "is this new words?" but "is there already an item this is a
more detailed version of?" — and the cost of getting it wrong is what the owner saw: one feature specified
in six documents at three scopes, which is how it acquired two eviction policies and two disk tiers before
a line of it was written. **This file is asks being built or next. ROADMAP is the long-term features, none
designed, each needing its own conversation first.**

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

**Nothing.** No branches, no worktrees, clean tree.

- **(21) Keyframes — stages 0 through 3b merged**, spec at [KEYFRAMES.md](KEYFRAMES.md). 3b's last
  half was the graph editor, D1 through D4: `4329e3d` row geometry, `931b859` the band, `bf423f0` the
  channel list, `56b0479` + `bccbfc2` the gestures and the marquee. **§8's next unbuilt stage is 4**,
  the rest-space dab bake — and **Distort is 5b now**, not last. Fast tier **2227 / 2224 / 0 / 3**;
  the full suite has not been run since two heavy classes were split, so CLAUDE.md's 22.3 min is stale
  in the optimistic direction.

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

### (22) Select multiple cels at once — the half of ask 6 the owner put in the future

- [ ] The owner, 2026-08-29: *"for the graph editor, the ability to use the select tool on it to select
      the keyframe nodes and move them could be a good idea, as well as the ability to use it on cels to
      select multiple at once in the future."*

      **The keyframe half shipped** — D3's marquee rubber-bands the keys in the band and carries the set
      as one body (KEYFRAMES §11.4). **The cel half is what is left**, and it is the owner's own *"in the
      future"*: "Select Multiple" already sits in the cel menu, `.disabled(true)`, which is the seam.

      The shape is settled by the half that shipped and should be copied rather than re-invented: a drag
      in empty space rubber-bands, a grab on any member carries the whole selection, and the selection is
      view state that dies with the surface it was made on. What a cel marquee adds is that its members
      are document objects rather than curve keys, so the undo bracket is the question D3 did not have to
      answer.

      Everything else in this item's six asks is merged and its history is in `git log` and
      [HANDOFF.md](HANDOFF.md); KEYFRAMES §11 is the graph editor's record and §2.26-§2.28 the
      workflow's.
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

### (24) The canvas paper is its own code path — should it just be a value layer?

- [ ] The owner, 2026-08-30, on being told that ink-on-paper is blended somewhere the colour work cannot
      reach: *"I find it weird that the canvas itself is a separate piece of code. Value layers already
      exist and work, so I wonder why you can't just reuse the same code to make the canvas behave like a
      value layer colour only. That would remove alot of redundant code and tidy up architecture, unless
      there is a reason not to do that."*

      **Investigated 2026-08-30. Verdict: do not — and the investigation refuted the premise this item
      was created on, which is the more useful half.**

      **The premise was that the paper is outside the composite. It is not, and has not been since
      `2a0379d` / `d90b329` / `5c00201` shipped EFFECT_BACKDROP §6.** `makeSandwichRequests` builds `full`
      and `below` with `background: paper` (`RenderRequest.swift:722-724`); both backends fill it
      (`Compositor.swift:713-716`, `MetalCompositor.swift:941-974`); thumbnails pass
      `includeBackground: true` (`ProjectStore.swift:311`); and there is a test called
      `testEveryBlendModeBlendsAgainstThePaper` (`EffectLayerLogicTests.swift:1491`). **So ink-over-paper
      IS reachable by effects, blend modes and any colour work — on the compositor-engaged path.** On the
      disengaged path a plain document is still drawn by Core Animation with the paper as a view behind
      it (`CanvasView.swift:832-838` argues deliberately for no extra clause there), but that is the case
      where nothing is being blended anyway.

      **How the false premise got here, because the trap will be walked into again:** it was read out of
      [EFFECT_BACKDROP.md](EFFECT_BACKDROP.md) **§0**, headed *"What is already true, verified rather than
      assumed"* and carrying the two commits it was checked at. **A spec's what-is-already-true section
      describes the world before that spec was built.** Once the spec ships, that section becomes the most
      confidently-worded stale text in the file — it reads exactly like a freshly verified statement of
      current behaviour, and it is a statement of the past. Check a §0 against the build order below it.

      **The three things that break if the paper becomes a bottom value layer**, each named rather than
      hand-waved. (1) **`RenderBackground` is the definition of "ink".** The `.ink` sub-walk is *the same
      tree with `background: nil`* (`Compositor.swift:1040`, `MetalCompositor.swift:659`) and
      `paperInBackdrop` is literally `request.background != nil` (`Compositor.swift:695`). Make the paper a
      leaf and that flag is always false, so **Outline reverts to a no-op** (it keys on `src.a > threshold`,
      `Composite.metal:696-698`) and Bloom's shipped `.ink` default (`Effect.swift:1142`) breaks. (2) **The
      padding margin.** `RenderBackground.rect` insets by `canvasPadding` (`RenderRequest.swift:605-615`)
      while `LayerRenderSource.solid` fills the whole `canvasSize` (`:84-102`), so a bottom value layer
      paints canvas colour over the grey margin — pinned by
      `testThePaperIsTheArtworkRectAndThePaddingMarginIsNotPaper`. (3) **The Behind onion skin vanishes on
      the disengaged path**, which is the default: `CanvasView.swift:793-798` fronts every layer host above
      the onion view, and `paperView` is never fronted — an opaque bottom layer would be.

      **The owner's premise that this removes redundancy is refuted numerically**: ~99 non-comment lines
      would go, against paper-leaf identity, a per-leaf margin inset, ink-exclusion, delete/reorder/mask
      guards and a migration. Net deletion is negative. `LayerRenderSource.solid` also allocates a full
      unmemoized canvas buffer per snapshot (8 MB at 2048x1024) where `RenderBackground` allocates zero.

      **But the owner sensed something real and it is worth keeping.** The canvas colour genuinely has
      three spellings — `paperView.backgroundColor` (`CanvasView.swift:567`), `UIRectFill`
      (`Compositor.swift:716`) and a Metal dispatch (`MetalCompositor.swift:969`). **That duplication is
      not the paper's separateness; it is the two-path live canvas** (Core Animation vs compositor), and a
      bottom value layer would have two spellings of its own. If the redundancy is the thing worth
      removing, the target is the dual live-canvas path — a much larger question, and one to put to the
      owner on its own rather than smuggle in under this item.

### (10) Linear light as an option on the blend mode — deprioritised by the owner

- [ ] The owner's original ask: *"I also want the option in actions to switch the color storage and
      processing to oklab or other future models. Oklab may give better compositing."* The complaint behind
      it: *"RGB goes muddy through the middle between two saturated hues."*

      **Ruled 2026-08-30, and it splits this item in two.** Shown in plain terms where the app actually
      mixes two colours — stroke over stroke, layer over layer, and colour ramps — the owner ruled: *"just do the ramps first for now. I do want linear light to be able to be used
      for compositing blend modes. Maybe instead of a global switch for that, it should be an option in the
      blend modes, with the global switch just being for the other stuff, like one brush stroke over
      another."* And on where it sits: *"Task 10) isnt exactly a major priority for me, the other stuff on
      the roadmap may be more valuable."*

      **(10a), the Oklab ramps, shipped 2026-08-30** (`e95828a`, `20014c0`) and has left this list.
      Its pictures are `docs/oklab-ramps/`, its generator `tools/oklab_ramp_ab.swift`, and the owner
      ruled on its one cost — a black-to-white Gradient Map darkens midtones by up to 31/255 — that the
      rule applies everywhere, greys included. That ruling lives in `Effect.gradientColour`'s doc. What
      is left of (10) is the switch:

      - **(10b) The pipeline switch — deprioritised, and RE-SCOPED by the ruling above.** Linear light for
        blend modes becomes **an option on the blend mode**, not a consequence of a document-wide flag; the
        document-wide flag covers only the dab/stroke-over-stroke site. That is a better shape than the one
        this item was written around and it changes the design: per-mode opt-in means existing artwork does
        not move unless the artist asks it to, which removes the whole "reopening a finished drawing changes
        it" cost that LINEAR_LIGHT_AB.md §4 spends its longest section on. **Do not build (10b) from the
        nine-stage plan drafted on 2026-08-30** — three adversarial reviews found it unbuildable as written
        (five cache keys serving stale pixels, a document that forgets the setting on reopen, a memoized
        accumulator format with no invalidation, and a real PNG migration the plan claimed did not exist),
        *and* the per-mode ruling above invalidates its central architecture anyway.

      **The evidence that settled the two questions this item left unruled**, both rendered rather than
      argued, in `docs/linear-light-ab/` with `tools/linear_light_q1q2.swift` as the generator:
      `Q1-shadow-banding.png` kills the 8-bit-linear intermediate on sight — 5 output levels where there
      were 33 on a near-black ramp — so the way *out* of linear is a 12-bit integer-indexed table.
      `Q2-nonseparable-modes.png` settles the six colour-judging blend modes: **exempt them**, keeping
      today's answer exactly, because linearizing their inputs and leaving `Composite.metal:145` alone
      shifts them by up to 78/255 and makes Lighter/Darker Color return *the other layer* on 7.81% of
      colour pairs — MEASURED by search over all 2,985,984 pairs, not by example.

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

### Playback, baking and memory — these live in ROADMAP §5b, not here

- **Moved 2026-08-30 at the owner's instruction**: *"the feature that I just told you about the memory
  allocation render baking belongs in ROADMAP.md 5. Rendering and export... it may be a good idea to clean
  up and organize the ideas properly instead of it being everywhere (todo and roadmap)."*

  Two items left this file for [ROADMAP.md](ROADMAP.md) §5b — the disk-streaming memory architecture, and
  "playback at 24 fps with in-betweens", which was always the same feature seen from the performance end.
  **§5b is now the single home**, and it names the four other documents that specify parts of it so they
  can be read as subordinate rather than parallel.

  **The boundary this restores, because it is what let the idea scatter:** TODO.md is asks that are being
  built or are next; ROADMAP.md is the long-term features, none of which is designed and each of which
  needs its own conversation with the owner first. An ask that is a *roadmap feature stated in new words*
  belongs in ROADMAP under the item it extends — not as a new TODO entry, which is the mistake made
  earlier today when this arrived as item (25).

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
