# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

**At the start of a pass, empty "Done this pass".** It is a record of the pass you are in, not a
changelog — `git log` is the real history, and a list carried across passes stops meaning anything.
Prune it first, before adding the new asks.

## The canvas size that actually matters

**The owner works at 2048×1024, or 1080p — "likely the former" (2026-08-17).** Not 4096².

Every performance number this project has collected was measured at 4096², which is **eight times the
pixels** of 2048×1024. Any cost that scales with area is therefore overstated by roughly 8× against the
document the owner actually animates on, and a conclusion drawn at 4K may be about a canvas nobody uses.
Benchmark at 2048×1024 first and treat 4096² as the stress case, not the baseline. This applies to the
17 fps entry below, the gallery thumbnail, and the onion skin composite alike.

## In flight

- **(5) Move stage 3a — Freeform on a lassoed vector piece** — `tmp/freeform`. The mode picker is live
  for a vector float, a corner drag scales the two axes independently about the centre, and the ink
  keeps its round shape at the map's area root (the owner's 2026-08-26 default). No renderer change and
  nothing new persisted. Stage 3b (the yellow box-only knob) and 3c (placed images holding a stretched
  shape) are deliberately not in it; a piece carrying an image or a text box has the picker disabled
  with the reason in the bar, exactly as Mirror already refuses.

## Queued

Owner's thoughts, 2026-08-26 — **not asks yet**, recorded so they are not lost (the perspective-text
requirement was nearly re-derived from scratch this week because it was only in one document):

- [ ] **(8) Fixed-point sample coordinates sized to the canvas.** Now a real ask with a design, 2026-08-26,
      superseding the same item's "thought" form from the previous session. The owner: *"Storing it as a double
      takes up way too much memory per point. The key is the canvas size: if a canvas is x by y pixels, our
      variable size only needs to be the canvas size ... add two more bits so it can be placed in 4 places
      between each pixel ... 12 bits per coordinate is alot better than 64."*
      **The rule**: bits per axis = `ceil(log2(extent)) + 2`, the +2 buying quarter-pixel placement because a
      stamp is *not* rounded to the nearest pixel when rasterized (the owner's own caveat, and correct —
      `BrushStamper` places dabs at sub-pixel positions).
      **The worked example is off by one in the ask and the design is unaffected**: 2048 is 2¹¹, not 2¹⁰, so a
      2048×1024 canvas needs **x: 13 bits, y: 12 bits**, not 12 and 11. 25 bits a point against 128 for two
      `Double`s is still the 5× the ask is really claiming, and the arithmetic should be derived from the canvas
      extent at encode time rather than written down per size.
      **`VectorSample` is three `CGFloat`, not two** — the third component needs its own width decision, and
      pressure/force is a 0…1 quantity where 8–10 bits is generous.
      **The owner has now ruled on the objection this item carried.** The recorded caveat was that quantising on
      every store fights the absolute-mapping discipline (every transform maps samples absolutely *from the lift*
      so error cannot accumulate over many small drags). Their ruling: *"The exception to this data type would be
      during reversable transformations, in which it would be converted temporarely to a double as to not lose
      accuracy, then converted back when it bakes."* That is the right shape — decode once, work in `Double`,
      re-encode at the bake. **The residual drift objection is closed by owner ruling, 2026-08-26** — do not
      re-open it. It was raised here that a bake still rounds, so repeated lift-bake-lift-bake cycles would
      random-walk at up to ⅛ px a bake. The owner: *"I dont see any reason why someone would transform, bake,
      and repeat for that many cycles. The only time that many transformations would happen is before something
      is baked, so it works out."* That is correct and it is structural rather than a judgement call: the
      many-transform case lives inside a single unbaked session, where the samples are already `Double`, so the
      rounding has no path by which to accumulate. One bake, one rounding.
      **Coupled to (9)**: if the encoding's width is derived from the canvas extent, resizing the canvas changes
      the domain. Decide together whether a resize re-encodes every sample or the width is stored per document.

      **SUPERSEDED SAME DAY — see the revision at the end of this item.** The original decision follows
      because its arithmetic is still the arithmetic that applies if (12) is *not* adopted.
      **DECIDED 2026-08-27 — fixed width, 24 signed bits per axis at quarter-pixel.** The owner delegated
      this (*"you decide if you want the dynamic bit allocation ... or if we should just keep it at 20 bits
      with a max canvas size"*), having correctly spotted that a constant width sits awkwardly with a canvas
      that is not constant. **Fixed wins, and dynamic-sized-to-the-canvas is not merely more complex — it is
      unsound**, because the canvas extent was never a bound on the stored data. CANVAS_RESIZE.md found three
      independent reasons coordinates leave `[0, extent)` as a matter of course: vector geometry is stored
      **layer-local** (a layer at 0.1x stores coordinates 10x the extent, by construction), touches keep being
      delivered after a drag leaves the canvas, and every shrink parks content outside the bounds.
      **The 20-bit proposal overflows, and the number that kills it was measured rather than assumed**:
      `ObjectTransformFrame.minimumScale` is **0.02** (`ObjectTransformFrame.swift:260` — "below this the layer
      is a dot the artist cannot get back"), and the canvas maximum is **8192** (`CanvasSizePickerView.swift:16`).
      Worst-case stored coordinate is therefore `8192 / 0.02 = 409,600 pt`. Twenty signed bits at quarter-pixel
      reach only **±131,072 pt** — short by 3.1x. (It would be fine on the owner's own 2048-wide canvas, at
      102,400 pt, which is exactly the kind of thing that ships and then breaks on someone else's document.)
      **Sizing**: 22 bits is the tight fit (±524,288 pt); **24 is the choice** — byte-aligned at 3 bytes an
      axis, ±2,097,152 pt, 5.1x headroom over the worst case. With 8 bits of pressure a sample is **7 bytes
      against today's 24** (three `CGFloat`), a **3.4x** memory win, and far more on disk against the 89
      bytes/sample the JSON currently spends. Quarter-pixel resolution is kept exactly as the owner specified.
      **The payoff for fixing the width**: a resize re-encodes nothing, so **(8) and (9) become independent and
      can ship in either order** — which was the whole reason the question was asked.
      To go back to 20 bits, `minimumScale` would have to rise, which is a behaviour change and not worth it.


      **REVISED 2026-08-27, later the same day, once the owner ruled on (12).** With geometry stored in
      **canvas space** rather than layer-local, the 50x blow-up that forced 24 bits cannot happen, and the
      bound becomes the *addressable* extent instead: **canvas + padding, capped at 16,384 pt** (the owner's
      rule, see (13)). At quarter-pixel that is 65,536 units — which unsigned 16 bits covers **exactly**, with
      one quarter-pixel to spare.
      **But exactly is not enough, and the honest width is 18 signed bits per axis.** Sixteen unsigned works
      only if no stored coordinate is ever negative and none ever exceeds the padded extent — and today both
      happen: touches keep being delivered after a drag leaves the canvas, and content parked outside the
      bounds by a shrink keeps its true position. Taking 16 would mean **clamping ink at the storage
      boundary**, which bends a line visibly where part of it is still on screen. **18 signed bits gives
      ±32,768 pt — twice the limit in both directions — and preserves today's behaviour exactly.**
      **The saving being declined is half a byte a sample.** 18+18+8 = 44 bits = 5.5 bytes against 16+16+8 =
      5 bytes; across the owner's largest plausible document (1000 cels x 8,714 samples) the difference is
      ~4 MB, against a baseline win of 24 → 5.5 bytes, **4.4x**. Half a byte is not worth a clipping rule.
      (17 signed bits is the tight fit at ±16,384; 18 is taken for the headroom, and the encoding is a
      bitstream so byte alignment buys nothing here.)

- [ ] **(12) Should a *layer* have a transform at all?** Owner, 2026-08-27, questioning the premise rather
      than the arithmetic: *"I'm not sure why layers themselves should ever be able to be shrunk. Only the
      objects in them should be. Every object in the vector layer should be given coordinates according to the
      canvas, and if the entire layer is 'shrunk', then those coordinates of the objects should shrink, not the
      entire layer itself being transformed."*
      **Where it came from**: their 15-bit arithmetic for item (8) is correct *for canvas coordinates* and
      fails only because vector geometry is stored **layer-local** — `addStroke(canvasSpaceStroke:)`
      (`VectorLayer.swift:575`) maps every sample through `_transform.inverted()` and divides the width by the
      layer scale, so a stroke drawn across the canvas on a 2%-scaled layer stores coordinates 50x the extent.
      That is the only reason 24 bits was chosen over 15.
      **Judge it on its merits, not on the two bytes.** Restructuring a core type to save 2 bytes a sample
      would be a bad trade alone. The real argument is that the layer transform is an indirection most entry
      points invert away again — which is what the instinct is reacting to.
      **Two things visible before any analysis**: a placed image *is* a transformed rectangle
      (`VectorImageElement` carries its own `LayerTransform`) and text carries a `TextFrame`, so "everything is
      canvas coordinates" cannot be total — per-*object* transforms would survive and only the *layer's* goes.
      And a whole-layer scale becomes O(samples) rather than O(1), which is fine on commit and not at 60 Hz —
      though the lasso float already solves exactly that shape (a latched bitmap moved by Core Animation,
      baked into geometry on release).
      **The load-bearing unknown**: is `_transform` per-cel or per-layer-across-every-cel? If a layer transform
      spans the whole animation, baking rewrites every drawing rather than one, and the cost estimate moves by
      orders of magnitude. `LAYER_TRANSFORM.md` is being written to settle this, with an independent critic.
      **CONFIRMED BY THE OWNER, 2026-08-27, with the nuance that matters**: *"Transformations are allowed to
      exist yes. It's just that the entire layer being resized should just bake the stuff in that layer to
      their new canvas based coordinates, instead of resizing the entire layer to be at a smaller
      resolution."* So this is **not** "no transforms" — it is "no layer *resolution*". A whole-layer resize
      becomes a bake into canvas coordinates, and per-object transforms (an image's rectangle, a text frame)
      are untouched.
      **And the future shape is now on record, which changes how this should be built**: *"when I add
      keyframes, I want a special type of layer called a transformation layer in which the stuff under it can
      be moved. This will just apply a transformation over the layers below it, so still no overflow problems,
      and whatever is being transformed of course is scoped with a maximum width of 16k."* An adjustment-layer
      shape — the transform lives on a layer that affects the layers **below** it, at render time, and is
      never baked into their coordinates. **Design (12) so that this remains easy**: the thing being removed
      is a transform baked into *storage semantics*, not the idea of a render-time transform, and the render
      tree already composites effect layers over the layers beneath them (`RenderTree.needsCompositorOnCanvas`,
      `node.effect != nil`) — that is the seam a transformation layer would use.
      **Note (8) is not blocked on this** — 24 bits works today with no other change; adopting (12) is what
      lets the field narrow to 18, which is a refinement rather than a prerequisite.

- [ ] **(13) Canvas padding: one 16k budget shared with the canvas, and a higher base maximum.** Owner,
      2026-08-27: *"the canvas plus the padding should have the maximum size of 16k, so the padding should hit
      a maximum limit when the canvas is set close to that 16k. The 16k canvas (or near it) will likely never
      be used for animation so it doesnt need canvas padding. Right now canvas padding just has a set maximum
      of something like 500px, I kind of want to make that maximum a bit higher like 1000, unless of course it
      is bounded by the 16k canvas+padding limit."*
      **Their memory was nearly exact**: `CanvasManager.canvasPaddingRange` is `0...512`
      (`CanvasManager.swift:30`), a flat constant consulted by `setCanvasPadding`
      (`CanvasManager+Document.swift:21`) and by the Actions slider (`ActionsMenu.swift:231`).
      **The rule to implement**: padding's upper bound stops being a constant and becomes
      `min(1024, (16384 - canvasExtent) / k)` — so it is 1024 on ordinary canvases and shrinks to nothing as
      the canvas approaches 16k. The base rises 512 → **1024**.
      **One ambiguity to settle in implementation, not to guess**: is `canvasPadding` per-*side* or the total
      added extent? `setCanvasPadding`'s offset is described as "one symmetric number", which suggests
      per-side and therefore `k = 2` — confirm against the code before writing the bound, because getting it
      wrong makes the cap either half or double what the owner asked for.
      **Also raises the canvas maximum**: `CanvasSizePickerView.maxDimension` is **8192** today
      (`CanvasSizePickerView.swift:16`); the owner's 16k rule implies 16,384 as the addressable ceiling.
      **This is the same 16,384 that sizes (8)'s coordinate field**, so the three items — (8), (9) and (13) —
      share one number and it should be defined in exactly one place.

- [ ] **(9) Resize the canvas from the Actions menu.** The owner: *"a resize canvas option in actions would be
      nice, to which users can resize the canvas however they want. They should be able to control whether it
      gets cropped/expanded, or if everything gets scaled."* Two controls: a **scale** option that scales the
      existing artwork, and a **toggle** for it to scale automatically with the new canvas size. **On an aspect
      change it letterboxes** — *"Not in the conventional sense of adding black, just scaling the stuff so it
      fits."* i.e. fit the content inside the new extent preserving its own aspect, leaving real empty canvas
      rather than painted bars.
      Note this is adjacent to report (6): the owner's freeze sequence names *"try to resize the canvas"*, so
      whatever exists today on that path is worth understanding before extending it.
- [ ] **(11) Move the effect-settings and Add Text menus to a bottom bar, like Move's.** The owner,
      2026-08-27: *"the effect settings menu right now takes beside the layers menu. Those two things take up
      about 80% of the canvas, making it hard to see what you are editing ... When the user clicks on effect
      settings, the menu is on the bottom, like the same kind of menu that the lasso or move tool uses. Same
      for the add text menu, make it the same type of menu."*
      **This is a "can't see my work while I edit it" complaint, and that is the acceptance test** — the fix is
      good when the artist can see the thing the slider is changing. Two panels move, not one.
      **The pattern to copy already exists**: `Views/MoveTransformBottomBar.swift` is the bar the Move tool
      raises, and the lasso/Select flow uses the same shape. Read it before designing anything.
      **What moves**: the effect settings UI (`Views/EffectSection.swift`, and `Views/MaskTuningSection.swift`
      is its neighbour — decide whether both move or only the first) and `Views/TextSettingsPanel.swift`.
      Both are reached today through `activePanel`, which is `@State` on `DrawingView` (`DrawingView.swift:15`,
      the panel is mounted at `:399`) — **ARCHITECTURE_REVIEW.md finding 1 is about exactly this variable**, so
      a change here should read that finding first rather than adding a fourteenth place that decides a touch.
      **Two things that are genuinely harder than they look, to settle in design rather than discover late**:
      1. *A Move bar is a handful of buttons; an effect panel is a stack of sliders per effect.* A bottom bar
         may need to scroll, or grow, or page. Say what happens with many effects before building one.
      2. *`TextSettingsPanel` carries three system presentations* — the font-family `Menu` (`:115`), the face
         `Menu` (`:150`) and a stock `ColorPicker` (`:202`) — and [BUGS.md](BUGS.md)'s newest entry records that
         the presentation census does not know about them. Re-hosting the panel changes what those present
         *from*. `MENU_PRESENTATION_CENSUS.md` is the document that has to stay true.
- [ ] **(10) Switch colour storage and processing to Oklab, from the Actions menu.** The owner: *"I also want the
      option in actions to switch the color storage and processing to oklab or other future models. Oklab may
      give better compositing."* Supersedes the queued *thought* of the same name — it is now an ask, and it is
      an ask for a **document-level switch with room for future models**, not a one-way conversion.
      It is RGB today: `CodableColor` is four `Double`s (`ProjectManifest.swift:124`). **Not a memory argument** —
      colour is per *stroke*, not per sample (32 bytes × 190 strokes = 6 KB on the cel measured on the owner's
      own device). The argument is quality: perceptually uniform blending, better gradients, and better colour
      interpolation between interpolation keyframes, where RGB goes muddy through the middle between two
      saturated hues. The owner's *"better compositing"* is the sharpest version of it and is the thing to
      verify: compositing happens in `Composite.metal`, so a real Oklab mode is a shader change, not only a
      storage change. Costs a conversion at stamp time and a decision about whether the picker works in Oklab.



## Verified on the device

**All five of this pass's changes were confirmed by the owner on their iPad, 2026-08-22**: *"five changes are
behaving correctly."* That covers the lasso move, the Cut eraser's live preview, the pick tool under the Select
panel, the raster-tier omission on save, and the raster Move's travelling ants. Nothing from this pass is
waiting on an eye any more.

Three behaviour questions are still carried, and are **not** defects — each was raised by us, not reported:
the Cut eraser across a line thicker than the eraser (visibly does nothing, and always did); a crossing line
that can flicker during a cut drag, under 10% of what the cut removes; and a fill chunk dropped on blank paper
staying a fill. All three want the owner's eye on real artwork rather than another run.

## The owner's seven device reports, 2026-08-26

Found on their iPad testing the Move/text pass. Their words are quoted verbatim; their *observations*
are evidence, their *causes* are hypotheses. **(1), (2), (3), (5) and (7) are done — see "Done this
pass". (4) is diagnosed and being built. (6) is parked awaiting a reproduction.**

- [x] **(3) DONE — text is visible in distort, and both halves were one bug.** Owner confirmed on device
      2026-08-27: *"text seems to show up in distort now."* The small-box fix (`TextLayout.draw` no longer
      blanking when `CTFrameGetLines` returns zero lines) cured the distort case too, which is the shared-cause
      hypothesis the experiment was designed to test — and it was the *second* of the two branches, not the
      CALayer/render-server one. **Worth keeping**: the elaborate distort experiment (tap into the box, watch
      whether words reappear flat) was never needed, because fixing the cheaper, better-understood half first
      resolved the expensive one. The refuted CALayer *software-path* hypothesis stays refuted. The ruling
      *"the box should never be allowed to be smaller than the text size unless in distort mode"* shipped with
      the small-box fix and the distort exemption is honoured on both paths.
- [ ] **(4) A pencil tap raises Scribble instead of the keyboard — CAUSE CONFIRMED, fix in flight.** The
      experiment was run and it settled it. Owner, 2026-08-27: *"yes, clicking with finger yields correct
      behaviour. Clicking with pencil however brings up that write to text thing which is annoying."*
      **"That write to text thing" is iPadOS Scribble.** So the app-side path is clean exactly as the
      verification pass insisted — `beginTextSession` has one non-test caller, no pencil/finger branch, and
      `becomeFirstResponder()` *was* called; iOS then suppresses the software keyboard for pencil input on a
      text input view and offers handwriting instead. **Both earlier theories were wrong in instructive ways**:
      the original `allowedTouchTypes`-gate guess was refuted by reading, and the counter-claim that the
      responder was refused *for everyone* is refuted by the finger working. The owner's own instinct — the
      pencil is treated as writing — was right, in a more specific sense than they stated.
      **Being built**: prefer a seam where a pencil *tap* focuses and raises the keyboard while pencil
      *writing* still scribbles; fall back to switching Scribble off on the canvas text overlay. The API trap
      is that the wrong call compiles, runs and silently does nothing, so the fix must prove it engages.
- [x] **(5) Freeform / Uniform / Distort greyed out in Move — intentional, not a defect.** Confirmed in the
      code: `MoveTransformBottomBar.swift:24-27` says the picker is live only for a raster piece because a
      lassoed vector piece scales uniformly, and **Move stage 3 is what turns it on**. Distort is stage 5.
      Both are designed and unstarted (HANDOFF.md). Nothing to fix; the ask is to *build stage 3*.
- [ ] **(6) PARKED — the UI freeze, awaiting a reproduction the owner can trigger.** Owner, 2026-08-27:
      *"I'll tell you when I am able to recreate the freeze."* Do not spend another investigation pass on it
      until then; the candidate below is unproven in *reachability*, not in mechanism, and only the device can
      settle that. **The one question that splits the diagnosis in half, to ask the moment it locks: does the
      timeline still animate and do the marching ants still march?** Yes → a dead-input overlay. No → a real
      main-thread hang. Those have nothing in common as fixes. Original report: *"it seems like it happens when
      your in the edit text keyboard menu,
      then select pencil brush or try to resize the canvas in some kind of sequence of actions ... a
      previous session reportedly fixed the UI freezing canvas move bug, and somehow its still here."*
      Confirmed **not** the earlier bug: `CanvasTransformFreezeUITests`' defect (a stroke begun under an
      open timeline popover) was real and is fixed, and nothing in that path is text-specific. Strongest
      live candidate: `CanvasManager.selectBrush(_:)` (`CanvasManager.swift:557-568`) omits `.text` from
      its `selectedTool != .eraser && selectedTool != .fill` exclusion list, so picking a brush preset
      flips the tool off `.text` without `commitAllInteractiveState()`, leaving `textGestureActive` true
      while `reconcileLayers` re-enables the layer host — the same hand-maintained-list shape
      `Tool.paintsOnCanvas`'s own doc comment exists to prevent. **Reachability is unproven**:
      `BrushSettingsPanel.swift:20` is the only caller and needs `activePanel == .brush`, which the
      committing toolbar route (`TopToolbar.swift:174-182`) appears to block whenever `.text` is active.
      **The discriminating question for the owner, which no run can answer: when it locks, does the
      timeline still animate and do the marching ants still march?** Yes → a dead-input overlay. No → a
      real main-thread hang. A single `ActionRecorder` capture names it outright.


## Queued

New this pass (owner rulings, 2026-08-22, on the touch-ownership truth table):

- [ ] **(i) One touch, one actor.** Deriving `CanvasTouchOwner`'s contract enumerated the input space and found
      **1,678 reachable combinations where two things act on one touch** — drag a guide grip with Fill selected
      and the grip moves *and* a flood fill lands under it; with the pick tool armed, the brush colour changes
      too; drag a floating piece's box with Fill selected and the piece moves *and* a fill dumps under it. The
      cause is not a missing check anywhere: **every container recognizer sets `cancelsTouchesInView = false`**,
      so an overlay claiming a touch in `hitTest` does not take it away from the recognizer beneath. The rule
      to apply: **whatever chrome the artist actually grabbed wins, and the tool underneath does not also
      fire.** `handleTextPress` already works this way — it re-checks both text overlays before acting, and is
      the only handler in the app that does, which is exactly why text is absent from the collision list. It is
      the pattern the other thirteen sites need.
- [ ] **(j) A tap outside a floating vector piece commits it, as it already does for raster.** The same
      enumeration found **118 combinations owned by nobody**, all on a vector layer: mid-Move, or with a lassoed
      piece floating, a touch anywhere outside the box does nothing *and says nothing* — where a hidden layer
      would at least raise a banner. With the Select panel open the canvas is inert away from the box,
      including the lasso the open panel is for. **Owner's ruling, 2026-08-22: make the tap commit the float**,
      chosen over leaving it silent or raising a notice, because it makes the vector float behave like the
      raster one. The asymmetry today is structural: `FloatingPieceOverlayView` covers the whole container and
      commits a raster piece on a tap outside, while a vector float's `ObjectTransformOverlayView` claims only
      its own grips.


Nothing — the owner's list is empty. Two things are *carried*, both deliberate and neither an ask:

- **The raster Move's undo half of ruling 4 is not built** (the vector half and selection-at-bake shipped). A
  raster nudge changes only `FloatingPiece.transform`, which is transient and not in the document, so per-nudge
  steps must be transient — and the bake step then sits on top of them and its undo restores the pre-move cel,
  killing every step beneath. Making it work means the bake step's undo *re-creating the float* at its last
  transform, which doubles what a raster Move retains in history and needs `finalizePendingGesturesForHistoryAction`
  to grow a raster-float arm it has never had. That is a second feature. See LASSO_MOVE.md §3 stage 4.
- **[ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md)'s first finding**, unruled: fourteen places decide who owns
  a canvas touch and none of them is *the* place. Four defects trace to it, three in the last week. The remedy
  is one pure `CanvasTouchOwner` type, and it is the one item that pays for itself on the **first** new tool —
  which matters, because the next session is large features.

## Done this pass

- **(2) The lasso's live outline is now visible while dragging** (`043f219`). Two independent causes,
  not one: `liveShadowLayer.isHidden = true` permanently hid the blue half of the preview, leaving a
  1.5pt white dash invisible on white paper, and separately `liveLayer` never had the marching-ants
  animation added at all. Also wrapped the live path assignment in a `CATransaction` with actions
  disabled so the preview stops trailing the stylus (precedent: `ShapeOverlayView.swift:218-222`,
  `GuideOverlayView.swift:155-158`). Select and lasso-fill share one renderer, so both are covered.
  **No test**: `SelectionOverlayView` type-checks under `@testable import` but fails to *link* in the
  UI-test target, and is not among the pure Foundation/CoreGraphics sources compiled a second time
  into it. Pinned by the owner's eye only.

- **(1) The unbaked Move preview no longer disappears under an effect layer** (`81fe14d`).
  `isSandwichEngaged` (`CanvasView.swift:973`) had an escape hatch for the raster `floatingPiece`,
  written 2026-08-12 (`389876b`), before the vector lasso move existed; `vectorFloat` was never added
  beside it. Any effect/mask/blend/group-buffer anywhere in the tree makes
  `RenderTree.needsCompositorOnCanvas` true, which engages the sandwich, which blanks every layer host
  at rest — including the one holding the float's pixels. The hole is punched correctly
  (`suppressedElementIDs`); it was the float being dropped underneath it. **Two corrections to the
  owner's report, both in the fix's favour**: it is not "sometimes" — it happens on *every* move with
  any effect/mask/blend/group-buffer in the tree — and it is not specific to layers *over* the moved
  one, since `needsCompositorOnCanvas` walks the whole tree. Cost recorded in the doc comment:
  disengaging also does `setContentMask(nil)`, so alpha-mask clipping is lost while a piece floats.
  **No test** — `isSandwichEngaged` is private on the coordinator, unreachable from the fast tier; a
  real pin needs an XCUITest over a document with an effect layer and a live lasso move.

- **A stale canvas-touch comment, found and corrected before it caused a fourth defect** (`3e19624`).
  `handleTextPress` was the app's one bare `interactionBegan.send()`, against a capitalised "Do not
  send this directly" contract. **The archaeology was inverted in the brief and corrected**: the
  contract commit (`3a68adb`) was authored *before* Add Text stage 1 (`6d404d0`) by 23 minutes, but
  landed *after* it on `main` because the contract branch was rebased on top — proof: the contract's
  parent tree held five bare calls and converted four, leaving `handleTextPress`, so its "all four
  canvas-touch sites" comment was accurate on its own pre-rebase base and stale by the time it landed.
  A distinct hazard from the two-branches-that-cannot-see-each-other shape already in CLAUDE.md — one
  branch whose own count expired underneath it during a rebase. The same stale miscount in
  `CanvasPresentationLogicTests.swift:168` was fixed too. **This fix is not the owner's freeze (6)** —
  with `.text` selected the stroke recognizer receives no touches, so there was nothing to strand.

- **(7) Two images on a vector layer no longer collide** (`8336165`). Both imports were hard-coded to
  the canvas centre, so image 2 landed at a bit-identical `CGPoint` on image 1 — and
  `splitForLassoMove` decides membership purely by stored centre, so no lasso loop could ever contain
  one without the other. Fixed with `VectorCanvas.addImage(canvasSpaceElement:canvasPosition:canvasFit:)`
  (`VectorLayer.swift:670`, beside `addStroke`/`addFill`), mapping the canvas centre through
  `_transform.inverted()` and cascading 24pt per existing image in *local* units, all under one lock.
  **The first draft's arithmetic was wrong**: adding 24pt to a canvas-space centre that is then stored
  as local coordinates leaves the larger misplacement in place. **Appending was considered and
  rejected** — `addImage`'s kind-sorted insert is documented at `insertionIndex`'s header and pinned by
  `testAddingElementsKeepsTheKindOrderExceptForAFillWhichGoesOnTop`; it also would not have fixed the
  collision. 4 tests, verified non-vacuous: 3 of 4 fail against pre-fix code, the 4th correctly still
  passes (pins an invariant the original already satisfied).

- **(3) small-box half — a box shorter than one line of text now draws it, instead of nothing**
  (`daa6fac`, `3314086`, `ef64506`). `TextLayout.draw` fed CoreText `CGPath(rect:)` of the raw box,
  which drops any line that doesn't fit *entirely* — a box shorter than one line yields zero lines, a
  blackout, not a clip. MEASURED: a 64pt line needs a 76.7pt path. Fixed by anchoring the layout rect
  on the box's *top* so overflow hangs below, and by giving the box per-axis floors: height >= one
  measured line (via `measure`, never `font.lineHeight`, short by 3x at the top of the range), width >=
  the run CoreText will not subdivide. **A brief premise was empirically wrong and was corrected**: the
  brief said floor the width at "the widest unbreakable word", but MEASURED, CoreText's
  `.byWordWrapping` *breaks inside* an overlong word, one character per line — that floor would have
  pinned a one-URL box open at full width. The shipped floor asks the framesetter what it actually
  refuses to subdivide: 46.2pt for "Hello world", 86.2pt at 40pt tracking, 55.4pt for a Japanese
  sentence with no spaces. A literal "never smaller than its wrapped text" floor was rejected because
  it chases itself — narrowing increases required height — and would make boxes un-narrowable. Distort
  is exempted on both paths; the floor latches on `TextFrameDrag` at touch-down so a 60Hz drag runs no
  layout. 12 tests (5 + 7). The distort *half* of report (3) is still open — see above.

1725 fast-tier tests (1722 passed, 0 failed, 3 skipped) = 1709 + 16, static `func test` 1826 → 1842,
matching.
