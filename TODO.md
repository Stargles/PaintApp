# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. **An item leaves when merged, not when a
branch exists.** Three in flight at once unless the extras need no simulator — see `tools/simlock.sh`.

**Before adding an item, check whether an existing one already covers it in different words.** A
restatement filed as a new item is how one feature came to be specified in six documents at three scopes,
with two eviction policies and two disk tiers, before a line of it was written.

**Items above "Later" are being built or are next. Items under it are the long-term features** — none
designed, each needing its own conversation with the owner before it starts.

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

- **(29) Rendering** — spec at [RENDER.md](RENDER.md), whose §2 is sixteen owner rulings and §5 the
  build order. **Stages 0 through 5 are merged**: the live stroke no longer scales with canvas area, the
  playback clock is the model's, the pen-up snapshot is a `FrameRecipe` minted on the main actor and
  resolved off it — MEASURED 174-313 ms of main-thread work at pen-up down to **0.2 ms** — a frame
  composites one chunk at a time under a memory ceiling, byte-exact on both backends, the canvas at rest
  and playback are served from LZ4 frames on disk, and a frame whose textures do not fit the budget is
  composited in horizontal strips at the size the artist asked for. **Stage 6, export, is merged and tested; stage 7, the rest of the memory audit, is what is left.**

  **Two things stage 5 still owes**, both on the device: the owner's own confirmation that the slider
  reads Full and the canvas is full on the "UI Test" canvas they reported it on, and the compression
  ratio measured against that same document rather than against the synthetic fixtures.

- **(21) Keyframes — stages 0 through 3b and stage 5 merged**, spec at [KEYFRAMES.md](KEYFRAMES.md).
  Stage 5 is the transform channel: a cel or an animation group carries a track of quad poses, ink is
  posed through `mapping(_:throughStretch:)`'s `sqrt(|det|)` width rule, and the blend is factored so
  the endpoints come back bit-exact. **A pose channel has a graph-editor band now** (§11.7): six
  decomposed curves — X, Y, Scale X, Scale Y, Rotation, Skew — grouped, foldable, and **read-only**, with
  a click on a row raising the Move box over the drawing that channel moves. What it does not have is
  write-back, because a node's frame is shared by all six sub-curves and retiming one is retiming the
  key; §11.7 says what that would need. **Animation groups still have no UI of their own.**
  **A Move at a posed in-between works**: it measures
  its box, its loop and its drag in the space the artist is looking at, and commits by conjugating the
  delta onto the channel, which is §2.27's `.key` arm.
  **(38)(c)'s rule is exactly true now**: every pose key has a node, including a transformation layer's
  and a folder's, which were two funnels the container-pose pass left open.

  **Stage 4, the rest-space dab bake, is merged**, and its tests reach the shipped dispatch now rather
  than an algebraic consequence of `DabPose.applied(to:)`. That unblocks **5b**, animated Distort — the
  projective case where no single scalar is the right width, wrong by 15% to 315% across one quad —
  because `DabPose` answers `localScale` per dab. **What remains is stages 5b, 6, 7, 8 and 10, plus the
  three gaps above**, and which goes first is an owner question rather than a settled order.

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

### (29) Rendering — the background baker and export

- [ ] > "rendering: add the ability to export animations as video or a frame as image"

      Spec at [RENDER.md](RENDER.md): §1 the ask in full, **§2 sixteen owner rulings**, §3 the design.
      The load-bearing ones: the baker **replaces** live main-thread compositing rather than sitting beside
      it; export **reads the bake** and re-renders nothing; the Render Resolution knob is the truth for
      both the canvas and the export, so a frame too large for the device's texture budget is cut into
      horizontal strips rather than composited smaller; playback may be visibly stale while the bake
      catches up, with the artist's current frame baked first; and the bake is dumped between launches
      unless the artist keeps it in the project folder.
      Item (31)'s three symptoms are this item's acceptance tests on a real device.

### (21) Keyframes — animating properties across the frames one cel spans

- [ ] The owner: *"Keyframes: (objects within a cel can get keyframed and move for the duration of that
      cel). Also applies to stuff like sliders for effects. Also includes interpolation curve
      customization. You should also be able to bake the cel containing animation into multiple cels
      (frames), and also set frame rate. Transformation layers adds transformation animation to whatever
      is under it."*

      **[KEYFRAMES.md](KEYFRAMES.md) is the specification.** Designed 2026-08-28 in the
      conversation that file names as each item's entry condition. **§2 carries twenty-eight rulings — read
      it rather than re-deriving them**, and §8 is the build order. The three that shape everything else:
      a transform key stores a **quad** from day one, so Distort lands later with no migration; posed ink
      is drawn by **baking the dab walk in rest space** and mapping dab centres, which removes the
      shimmer *and* the per-sample-width problem at once; and **bake is an authoring feature, never a
      performance instruction** — smooth playback comes from a cache.

      **What remains is stages 4, 5b, 6, 7, 8 and 10.** Stage 6b is not among them: §4.6's playback cache
      is delivered by (29)'s frame store, and that row is a cross-reference now rather than work.

### (26) Import videos — designed, spec at [VIDEO.md](VIDEO.md)

- [ ] > "Import videos: (requires #1) like import images, but exist as videos. Since videos have a
      > specified length, a vector layer containing a video can only have one video and must be a specific
      > length (but add that length able to be cropped). Should have the same option to bake to multiple
      > cels containing images instead of the video."

      **[VIDEO.md](VIDEO.md) is the specification** — §1 the ask and the design briefing verbatim, **§2 nine
      owner rulings**, §8 the build order. A video is a fifth `VectorElement` case in its own vector layer;
      the block's edges crop it in source time; Adjust Speed rewrites the block's length; Split Drawing cuts
      a cel in two at the cursor and works on ordinary cels as well.
      **The dependency on (21) is satisfied** and the seam it predicted is real: `derivedCelContent` already
      branches on an interpolation recipe, and a video is a third branch of that same accessor.
      **Stage 1 needs no video at all** — `splitCel` is fully written and has no caller outside four tests,
      so Split Drawing on ordinary cels is a menu row and the test it never had.
      **The bulk of the work is the fifth enum case**: `VectorElement` is switched exhaustively at ~two dozen
      sites, and several arms are a genuine refusal rather than a copy of the image arm.
      **A tripwire, still live**: `"video"` is the literal sentinel for an unimplemented element kind in
      `VectorCanvasDataLogicTests` and `SaveDamageGateLogicTests`. Implementing it takes the sentinel away.

### (37) The brush engine overhaul — designed, spec at [BRUSH.md](BRUSH.md)

- [ ] > "the ability to import paintbrushes would be nice. There is an md document which describes it, but don't
      > read it this session as this is a low priority task and can wait."

      **[BRUSH.md](BRUSH.md) is the specification** — §1 the ask verbatim, **§2 fourteen owner rulings**, §10
      the build order. [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) is the survey that
      preceded it and is still accurate about the seams.
      The rulings that shape everything else: the stored path becomes a **refit of the drawn curve at a fixed
      tolerance** independent of any brush, which deletes `StrokeSampleGate` and is a correctness requirement
      rather than a saving; **per-dab randomness is hashed from the stroke's seed and the dab's arc length**
      rather than drawn from a sequential stream, which is what survives a split, a refit, a spacing edit and
      an eraser punch alike, and which deletes `DiscardedDabTarget`; brushes are **deduplicated into a
      document-level table**, frozen per stroke with an explicit apply-to-existing verb; and **grain is
      deleted entirely**, canvas-anchored paper texture included.
      **Tilt does not ship and the architecture must accommodate it** — §5.5 is a build requirement of this
      item, not of the one that adds tilt, and it names the `StrokeInput` capture as an explicit exception to
      the standing delete-what-is-unused rule.
      **KEYFRAMES §2.16 is discharged rather than implemented**: the declined grain-on-Move ruling stops
      existing along with grain.
      **§2.14 is the standing no-legacy rule scoped to this item**, and §9 is its ledger: every stage
      deletes its predecessor in the change that replaces it, because there is no cleanup pass scheduled.
      Nothing on the device needs to survive, so the format changes rather than migrating.

### (12) Lasso move — the follow-ups its spec still lists as unbuilt

- [ ] Spec at [LASSO_MOVE.md](LASSO_MOVE.md); **§0 is what shipped and §3's stage 4 is what did not.**
      Stages 1-3 shipped together, Freeform is 3a, flips are in stage 2, the box-only rotate knob is 3b
      in all three phases, and the three membership rules moved to Select as item (23). What remains:

      - **Distort's ink tier.** The raster tier is **merged**: a four-corner drag on the raster floating
        piece, in both `.move` and `.duplicate`, previewed through `CATransform3D`'s perspective terms
        so the drag rasterizes nothing, and **exact rather than bounded** — MEASURED 0.0 disagreement
        between what the finger sees and what bakes. Ink is refused per float, in one sentence, because
        under a homography the local scale spans 1.3x to 8.5x across one quad and the best single scalar
        for `VectorStroke.size` is wrong by 15%-315%; **KEYFRAMES §4.2's rest-space dab bake is what
        unblocks it**. A **placed image** is the one kind with no Distort door at all — its placement is
        six numbers plus a mirror bit where a homography needs eight. Text already has one by its own
        door (Text panel → Corners). KEYFRAMES §8 stage 5b is the *animated* Distort — a quad keyed
        across frames — and is a different feature that meets this one with no migration.
      - **Port `FloatingPieceOverlayView` onto the stage 4 handle pattern** — the raster float still
        carries the older overlay.

      `beginDuplicate()`'s rasterize-on-a-vector-layer is **not** part of this; it is item (33) and a
      BUGS.md defect.

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
### (24) The canvas paper is its own code path — should it just be a value layer?

- [ ] The owner, 2026-08-30, on being told that ink-on-paper is blended somewhere the colour work cannot
      reach: *"I find it weird that the canvas itself is a separate piece of code. Value layers already
      exist and work, so I wonder why you can't just reuse the same code to make the canvas behave like a
      value layer colour only. That would remove alot of redundant code and tidy up architecture, unless
      there is a reason not to do that."*

      **Verdict: do not.**

      **The paper is already in the composite**, so the tidiness argument is the only one left — the
      reachability one does not apply. `SandwichRecipe.resolve()` builds `full` and `below` with
      `background: paper` (`Engine/FrameRecipe.swift:230-231`), both backends fill it
      (`Compositor.swift:713-716`, `MetalCompositor.swift:941-974`), thumbnails pass
      `includeBackground: true` (`ProjectStore.swift:311`), and `EffectLayerLogicTests:1491` is
      `testEveryBlendModeBlendsAgainstThePaper`. Only the disengaged Core Animation path draws the paper
      as a plain view (`CanvasView.swift:832-838` argues for no extra clause there), and that is the path
      where nothing is being blended anyway.

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

### (31) Large canvases: three symptoms of the compositor's sizing and threading

- [x] > "There is a resolution bug where the canvas renders at non full resolution even if the slider is set
      > to full. Happens on big canvases. If you want to check, on the iPad there is a canvas called UI Test."

      RENDER §2.12 rules the knob is the truth. **Confirmed on the owner's iPad 9 in Release
      (MEASURED 2026-09-02): the 4096² scene needed 512 MB of textures against a 183.7 MB budget, and
      `CompositorBudget.affordableSize` capped it to 2508².** The budget is `physicalMemory / 16`, and the
      device reports 183.7 MB where the docs had assumed 192.

      **Done 2026-09-02 (RENDER §3.8, stage 5).** `affordableSize` is deleted, and a frame whose textures
      do not fit is composited in horizontal strips at the size the artist asked for —
      `Engine/StripedComposite.swift`. **Still owed: the owner's own confirmation on the iPad, against
      the "UI Test" canvas they reported it on.** The fix is pinned byte-for-byte on both backends in the
      simulator; nobody has yet watched the slider say Full and the canvas be full on the device.

- [ ] > "A 16k by 16k canvas crashes the iPad app when you draw something. This is really odd, it should not
      > happen. I wonder if it could hint at a deeper issue where larger canvases take more memory per
      > brushstroke. Because it is vector, this should not happen. I wonder if it may be the compositor."

      **The crash is fixed** (stage 0: `Engine/StrokeScratch.swift`). The canvas is still unusable, and
      the owner's follow-up says how:

      > "I tried making a 16k canvas and then drawing on it with a brush. Although it does not crash, it is
      > broken. First off, the brushstroke disappears when you draw. Secondly, the framerate is very laggy.
      > [...] the only thing id really be doing in a 16k canvas is idea boards where the drawings are small
      > compared to the canvas."

      **Two causes, neither the one that looks obvious, and the first is fixed.** The canvas-sized
      allocation *succeeds* — a 16383² `VectorCanvas.render()` is MEASURED at 143.5 ms on the device with
      the ink present, because a `CGBitmapContext` is lazily committed. The stroke was drawn and never
      reached the screen for two reasons. **No artwork view set `minificationFilter`**, so a 5-point brush
      point-sampled to `fitScale` left **zero ink at 4096², 8192² and 12288²** — live on ordinary large
      canvases, not just 16k. That is fixed: the nine artwork layers ask for `.trilinear`. **What remains
      is that at 16383² the image cannot be composited at all**, which needs a downscaled display proxy.
      BUGS.md carries both, and marks the first FIXED.

      The lag is the owner's own diagnosis, confirmed: `recordSpacing` is in canvas points, so at
      `fitScale` one screen inch is 352 dabs at 2048² and **2815 at 16383²**. Scaling the sample gate by
      zoom is a permanent quality trade (coarser stored geometry feeds interpolation and the vector
      eraser) and is **deferred by the owner pending an A/B they can see**, not refused.

- [ ] > "Larger canvases seem to freeze the program momentarily after each brushstroke is lifted. I suspect
      > it is compositing, which is pretty bad. I want you to weigh moving the majority of the program to
      > another thread, so that the UX is responsive and doesnt lagspike when the user does opperations."

      RENDER §2.2 and §2.13 rule this: compositing leaves the main thread, and a split-second stale canvas
      is acceptable as long as the canvas can be moved and the next stroke laid during it.

### (32) Merging a blend layer down does not bake its blend into the layer below

- [ ] > "I tried having 2 layers: a vector layer and a value layer above it set to HSV. Then I merged those two
      > layers. The expected outcome is that the HSV gets baked into the vector layer (colors get
      > transformed). Right now it does nothing. This may be an issue other blend modes. Lower priority."

### (33) Select and duplicate produces a raster layer from a vector selection

- [ ] > "When I select and duplicate, it does not support vector (the duplicated selection is a raster layer
      > not a vector)."

      BUGS.md already carries this as "Duplicate rasterizes a vector layer, silently"; the entry names the path.

### (10) Linear light as an option on the blend mode — deprioritised by the owner

- [ ] The owner's original ask: *"I also want the option in actions to switch the color storage and
      processing to oklab or other future models. Oklab may give better compositing."* The complaint behind
      it: *"RGB goes muddy through the middle between two saturated hues."*

      **The ruling.** The owner, shown where the app actually mixes two colours: *"I do want linear light
      to be able to be used for compositing blend modes. Maybe instead of a global switch for that, it
      should be an option in the blend modes, with the global switch just being for the other stuff, like
      one brush stroke over another."* On priority: *"Task 10) isnt exactly a major priority for me, the
      other stuff on the roadmap may be more valuable."*

      **So linear light is an option ON the blend mode**, not a consequence of a document-wide flag, and
      the document-wide flag covers only the dab / stroke-over-stroke site. Per-mode opt-in means existing
      artwork does not move unless the artist asks it to, which removes the largest cost this item
      otherwise carries — every antialiased grey in every existing drawing getting lighter by up to 73/255
      (LINEAR_LIGHT_AB.md §4).

      **Five things any implementation must handle**, each found by reading the tree rather than guessed:
      `PixelOps.RasterizeKey`, `CanvasView.SandwichKey`, `MetalCompositor`'s `UploadCache.Key` and
      `MaskResolver`'s key all carry render inputs and none carries a colour-pipeline field, so a stale
      composite serves silently — and `FrameBakeKey` is the same hole on disk, where the filename *is*
      the digest and a missing field is the wrong picture with no error;
      `ProjectStore.swift:1158` rebuilds every tier on load with no format
      argument, so a document forgets the setting on reopen; `RasterLayerTexture.ensureContext` memoizes
      the backing format with no invalidation, so the setting cannot change mid-document; six other sites
      reconstruct a `RasterLayerTexture` and would drop its format; and a linear tier changes the PNG on
      disk, so the "no migration" claim is false.

      **Two sub-questions are settled, both by rendered evidence in `docs/linear-light-ab/`.** The way
      *out* of linear is a 12-bit integer-indexed table — an 8-bit linear intermediate collapses a 33-step
      near-black ramp to 5 levels (`Q1-shadow-banding.png`). And the six non-separable blend modes are
      **exempted**, keeping today's answer: linearizing their inputs while leaving `Composite.metal:145`
      alone shifts them by up to 78/255 and makes Lighter/Darker Color return the other layer on 7.81% of
      colour pairs (`Q2-nonseparable-modes.png`, measured over all 2,985,984 pairs).

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

## Later — the long-term features

**Every one of these carries the same entry condition**, given by the owner with the list:
*"When you get to these, prompt me to explain to you in more detail how they work."* **An item built from
its entry here alone was built wrong.** Its specification becomes its own document once that conversation
has happened, the way KEYFRAMES.md exists for (21).

**Dependencies the owner named**: (26)→(21), (27)→(26), (30)→(29). **Three the code adds**: (28) needs a
real playback clock; (21)'s bake-to-cels and (29)'s exporter are **the same frame walk**, so build it
once; and (29) was blocked on derived content being invisible to the render walk, which the
`ContentProvider` seam has since fixed.

### (27) Screen recording the computer as a layer — requires (26)

- [ ] > "screen recording computer as layer: (requires #2) This is the big feature. It should connect live
      > with the computer and display the screen live as a video or image like object in a vector layer.
      > Performance will be big here, so some kind of optimization where you can freeze it will be good,
      > along with it not updating when nothing is changing on screen. The objective is to be able to have
      > blender on my computer, use my mouse to pick an angle, then rotoscope it on the drawing app, move to
      > another perspective, and so on. This means another program for the windows computers side. I also
      > would like a feature where the computer can drop in an image or video file somewhere and it will
      > appear on the app, so I can directly pull out renders from blender and mash it with my animations."

      **Both of the owner's performance instincts are already how the render path works** — freeze, and
      don't update when nothing changed — because content versions gate recomposites. What is missing is
      **any dirty-rect or partial-upload path**: when a version *does* move, the whole layer re-uploads.
      **A correction worth keeping**: the existing "Windows" scripts in `deploy/` are unrelated to this —
      they are a build/deploy path, not a device link.
      **The drop-a-file half starts from nothing**: the app has zero drag-and-drop, `Transferable`,
      `NSItemProvider`, `fileImporter` or `UTType` code. **INFERRED: that half looks separable and much
      smaller, and could ship long before the live stream — worth asking.**
      **Ask first**, more than anywhere else, because this is a second program: is the Mac in the loop or
      does the iPad talk to the Windows box directly; is the goal a live *stream* or a still per camera
      move (the Blender workflow described sounds like the latter, and a still is enormously cheaper); what
      the layer shows when nothing is connected; and whether the last frame saves into the document.

### (28) Audio — needs a real playback clock first

- [ ] > "audio: implement the ability to add sounds to the animations, potentially including features like
      > lipsync. Also ability to drop in audio files from computer."

      **Nothing exists** — no audio framework is linked anywhere in the app.
      **The dependency the owner did not name, and it is the whole first move**: there is no clock to sync
      to. Playback is a `Timer` whose callback re-dispatches onto the main queue, with `isPlaying` and the
      timer living on the *view* (`Views/AnimationTimeline.swift:12-14`, timer at `:1004-1008`). It drifts,
      and nothing notices today because the only consumer is the playhead. Audio is a hardware clock, so
      drift becomes what the artist *hears*, and lipsync is where they *see* it. **Hoisting playback onto
      the model behind a monotonic time base is a timeline change, not an audio feature** — and (21)'s
      recording stage and (29)'s playback goal each need it too, which makes it the highest-leverage
      single change on this list.
      **Ask first**: is audio a property of the document or of a scene in (30); does a sound attach to a
      frame, a cel, or a free position on a time ruler that does not exist yet; and is lipsync automatic
      (analyse the audio, pick a mouth shape) or a manual chart — those are completely different features.

### (35) Advanced masks — colour-range masks and a colour-reassign blend mode

- [ ] > "right now we have alpha masks. I like the idea of more advanced masks. This includes the ability to mask
      > specific sets of colours (with a deviation threshold range), and a new special blend mode called colour
      > reassign, where you can select colours and reassign them to other colours of your choosing (you can recolour
      > your drawings). You dont have to get this done this session."

      Low priority. A colour-range mask is a second `AlphaMask` source kind whose coverage is a distance in colour
      space against a threshold; colour reassign is a per-pixel lookup grade rather than a blend in the
      `blendOver` sense, so it likely lands as an `Effect` with a palette parameter. Both read the accumulator
      only, so RENDER §3.4's chunking rules already cover them.

### (36) Store projects in a folder the artist chooses, outside the app container

- [ ] > "Right now, the app has a big drawback that if it is inexplicably deleted, then all the saves are deleted
      > with it. Make it so it stores the files in an outside folder that you can assign, sort of like blender.
      > Medium priority; arrange this so that if you think a feature would benefit from this feature being made as
      > a pre-requisite, then thats when you should probably make this."

      Medium priority. Every path the app writes derives from `.documentDirectory`
      (`Services/ProjectBackupManager.swift:55-69`); the project package is a plain directory written atomically
      through a same-volume rename (`Services/ProjectStore.swift:545-634`), which a security-scoped folder on iCloud
      Drive or an external volume may not honour — that is the design question. RENDER §3.5's "keep the bake beside
      the project" and §3.9's export destination both want a chosen folder, so this is a prerequisite of RENDER
      stage 6 and should land before it.

### (30) Video editor — requires (29)

- [ ] > "video editor: (requires #5) right now each animation is viewed in the gallery. This would be the
      > idea of being able to have them organized into scenes, episodes, etc, so an entire movie can be made
      > and exported."

      **It is really two features and only one needs (29)**: organising documents into scenes needs no
      renderer at all; *exporting the movie* does.
      **"Scene" in this codebase is a false friend** — `sceneFrameCount` is the laid-out length of the
      timeline, nothing to do with a scene in the film sense. Do not reuse the word in code.
      **The blueprint exists one level down**: the layer tree is already a complete, tested, persisted
      ordered hierarchy with folders. A gallery of scenes is that same shape at the document level.
      **What has to change beyond the tree**: a `.paintproj` is a package *directory*, and the gallery has
      no folders — so this is a new containment level, not a rename.
      **Ask first**: is a scene a *folder of documents* or a new document kind that references them; can a
      shot appear in two scenes; is the cut list part of a package or a separate file; what happens when two
      documents disagree on frame rate or canvas size; and — the question that decides the data model — is
      an exported movie re-rendered from the sources, or assembled from per-scene exports?

## Carried — deliberate, and not an ask

- **The raster Move's undo half of [LASSO_MOVE.md](LASSO_MOVE.md) §5 rulings 5 and 10 is not built** (the
  vector half and selection-at-bake shipped). A raster nudge changes only `FloatingPiece.transform`, which
  is transient and not in the document, so per-nudge steps must be transient — and the bake step then sits
  on top of them and its undo restores the pre-move cel, killing every step beneath. Making it work means
  the bake step's undo *re-creating the float* at its last transform, which doubles what a raster Move
  retains and needs `finalizePendingGesturesForHistoryAction` to grow a raster-float arm it has never had.
  A second feature. See LASSO_MOVE.md §3 stage 4.
- **Move stage 5** — Distort on both tiers consuming the shared `Homography` solver, with the
  ink-deformation toggle defaulting off. LASSO_MOVE.md §0 lists what it deliberately left out.
  **Stage 3b left this list on 2026-08-28** — the knob `330efd4`, the stretch axis `c78de6e`, the
  re-fitting box `5b5577e` — **and 3c left it on 2026-09-02**, which closed the Freeform/Mirror gate on
  its last kind: a placed image now stores `aspect`, `stretchAxis` and `mirrored` beside its
  `LayerTransform`, and no migration was owed. `canBeStretched`/`canBeMirrored` and the two bar captions
  they fed are **deleted**, because no kind could answer no any more.
  **3b phase 3's tripwire fired as predicted and is accepted**: the re-fitting box pads a placed image's
  disc with an axis-aligned pair, which was exact only while a float holding one could not be stretched.
  It can be now, so the pad is conservative rather than exact — loose by a fraction of the photo, and the
  same approximation a stroke's own reach already takes under a stretched box. The exact fix is still the
  frame's row norms rather than a scalar pair.
- **A Freeform-stretched text box inherits the distort-mode minimum-size exemption**, so it can be dragged
  smaller than its own text. Rode along with the 2026-08-27 text-transform change, is recorded in
  `sizedInBoxSpace`'s own doc with the two-line conditional that would undo it, and is **unruled**.
