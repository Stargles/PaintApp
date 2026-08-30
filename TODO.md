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

      **[KEYFRAMES.md](KEYFRAMES.md) is the specification.** Designed 2026-08-28 in the
      conversation that file names as each item's entry condition. **§2 carries twenty-five rulings — read
      it rather than re-deriving them**, and §8 is the build order. The three that shape everything else:
      a transform key stores a **quad** from day one, so Distort lands later with no migration; posed ink
      is drawn by **baking the dab walk in rest space** and mapping dab centres, which removes the
      shimmer *and* the per-sample-width problem at once; and **bake is an authoring feature, never a
      performance instruction** — smooth playback comes from a cache.

      Stage 0 is `renderTree(atFrame:)` and is behaviour-neutral. §8 also names one prerequisite that is
      not part of this feature and is worth doing first anyway: VECTOR_INTERPOLATION item 18's
      `ContentProvider` seam, which is what makes any derived content visible to thumbnails, onion skin
      and export — and which (29) is blocked on.

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

      **Verdict: do not.**

      **The paper is already in the composite**, so the tidiness argument is the only one left — the
      reachability one does not apply. `makeSandwichRequests` builds `full` and `below` with
      `background: paper` (`RenderRequest.swift:722-724`), both backends fill it
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
      `PixelOps.RasterizeKey`, `CanvasView.SandwichKey`, `RenderRequest.SandwichFullKey` and
      `MaskResolver`'s key all carry render inputs and none carries a colour-pipeline field, so a stale
      composite serves silently; `ProjectStore.swift:1158` rebuilds every tier on load with no format
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

### (26) Import videos — requires (21)

- [ ] > "Import videos: (requires #1) like import images, but exist as videos. Since videos have a
      > specified length, a vector layer containing a video can only have one video and must be a specific
      > length (but add that length able to be cropped). Should have the same option to bake to multiple
      > cels containing images instead of the video."

      **Why it truly requires (21)**: `InterpolationRecipe.t` is a parameter of the *cel*, not the frame,
      and a cel spans a range — so **nothing in the document varies across the frames one cel spans**. A
      video is exactly content that must. (21) introduces that; this is its first consumer.
      **A tripwire**: `"video"` is currently the **sentinel** for "a layer kind nothing implements" in the
      forward-compatibility tests. Implementing it takes that sentinel away and those tests need a new one.
      **The one live coupling**: a video element inherits whatever Move stage 3c decides about
      `VectorImageElement.transform`.
      **Ask first**: what "a specific length" means when the cel's `frameCount` and the video's duration
      disagree — resize, retime, or refuse; whether cropping trims or retimes; one video per *layer* or per
      *cel*; and at what rate a 30 fps source plays in a 24 fps document.

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
      timer living on the *view* (`Views/AnimationTimeline.swift:13-14`, timer at `:976-989`). It drifts,
      and nothing notices today because the only consumer is the playhead. Audio is a hardware clock, so
      drift becomes what the artist *hears*, and lipsync is where they *see* it. **Hoisting playback onto
      the model behind a monotonic time base is a timeline change, not an audio feature** — and (21)'s
      recording stage and (29)'s playback goal each need it too, which makes it the highest-leverage
      single change on this list.
      **Ask first**: is audio a property of the document or of a scene in (30); does a sound attach to a
      frame, a cel, or a free position on a time ruler that does not exist yet; and is lipsync automatic
      (analyse the audio, pick a mouth shape) or a manual chart — those are completely different features.

### (29) Rendering, export, and the bake-stream-and-size architecture

- [ ] > "rendering: add the ability to export animations as video or a frame as image"

      **There is no export feature at all, of any kind** — searched exhaustively for every share, file-export
      and photo-library API: zero hits in app code and tests. The one `ShareLink` shares a debug telemetry
      file. The word "Export" reaches the artist only as reassurance copy on the Render Resolution knob — a
      promise with no code behind it. Several documents name export as a consumer of some render path; read
      all of them as describing a **hypothetical** consumer.
      **The good news is bigger than expected**: `Compositor.composite(_:) -> CGImage?` is already pure,
      already headless, already runs in the test tier with no view, and `makeRenderRequest` is already
      frame-parametric. **What is missing is a driver loop, an encoder and a destination — not a renderer.**
      **What it collides with**: an export composites at *native* resolution, the one case
      `CompositorBudget.affordableSize` does not bound — passing no `fittingWithin` skips the cap by
      construction, the GPU admission gate then returns `.unavailable`, and the CPU path answers at a
      MEASURED **203.3 ms** per grading composite (iPad 9, Release, warm, 2048²). **INFERRED, arithmetic
      only**: a 240-frame export is ~49 s of CPU compositing, and real documents are 300-1000 cels.
      `CanvasManager+Document`'s reassurance that saving is bounded to 320x320 **stops being true the day
      export ships**.

      **The memory architecture is the other half of this item.** The owner:

      > "the ipad does not have much memory, so I want the paint program to not use much by storing as many
      > things it can to disk. Probably the current active cel is the only thing required to be in memory.
      > The paint program automatically pulls unbaked frames from disk (layers, compositing, etc), bakes the
      > compositing and stores it back straight to disk, so that when the play is pressed it can be played
      > at 24fps. This way, the program doesn't run out of memory even with a hundred layers and a thousand
      > cels. The memory is dynamically allocated: lets say we have layers 1 through 10 and the program has
      > only enough memory for 3: the three bottom layers are pulled, composited and stored, then the next
      > are pulled etc."

      > "(NOTE: This is my thinking on how it may work, it may not be the most optimal. The session is gonna
      > have to make a judgement on how exactly to do this. I eventually want to make it android and windows
      > compatible so dynamic allocation of some sort may be nice.)"

      And on what triggers a rebake: *"When something is modified, only the modified frames are rebaked."*

      **So the goal is fixed and the mechanism is delegated in writing.** The goal: a hundred layers and a
      thousand cels without running out, and 24 fps on press-play. **Portability is a stated requirement**
      — a budget hard-coded to an iPad, or an eviction signal only iOS emits, fails it.
      **Layer-chunked accumulation looks sound**: each layer blends against the accumulation *below* it,
      which is exactly what a bottom-up chunk holds. **INFERRED — prove it against `blendOver` and the six
      non-separable modes**, and check the `above` half of the sandwich and `RenderBackground`'s
      ink-exclusion walk, which are where it may not hold.
      **Three things are already built and must not be rebuilt**: propagating content versions, so a leaf
      edit bumps only its ancestors; **frame-scoped invalidation**, which is the owner's "only the modified
      frames are rebaked" and cost nothing; and a pure snapshot-driven composite that was built that way so
      adding a thread later is not a rewrite.
      **The memory arithmetic that decides the design**: one frame is 16.8 MB at 2048², so ten seconds at
      24 fps is **4 GB**, and 15 GB at 4000². *"Any design that holds baked frames as raw textures dies on
      the first real sequence."* So "gradually replaced with that baked video" is not a nicety, it is the
      only shape that works.
      **Two specs describe parts of this machine and must be unified before either is built**, or the app
      gets two frame caches and two eviction policies: LAYER_COMPOSITING §9.2 (sequencer scope — priority
      queue, disk LRU, evict on edit) and KEYFRAMES §4.6 (one keyframe span — eager and complete, and
      **ruled** by the owner 2026-08-28 in §2.19-20). They differ in one interesting way worth keeping: the
      *policy* is scoped, the *store* is not. PERFORMANCE §8 is the ranked evidence.
      **This item is already load-bearing even unbuilt**: KEYFRAMES §2.25 lets a derived frame cost more
      than 1/24 s *because* of this prebake — *"if it prebakes and can play at 24fps after, then the
      original ask is covered."* Anything that quietly drops this item takes that permission with it.
      **Ask first**: which container and codec, and does it need alpha (few codecs carry it, and the
      composite is not necessarily opaque); at what resolution; whether a slow correct export is acceptable
      given the arithmetic; whether a bake may be visibly stale while it catches up, the way a video buffer
      is; and what happens when the *disk* is full rather than memory.
      **Unruled**: whether a baked span survives a relaunch, and what sweeps it if the OS purges its cache.
      **Scrubbing backwards is the hard direction and it is the one an animator uses** — a long-GOP stream
      decodes forward from a keyframe, which probably forces an all-intra codec, larger on disk. A knowing
      trade, not a detail.

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
