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

Nothing yet — the seven device reports below are being root-caused, and an item enters this
section when a branch exists, not when it is understood.

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
- [ ] **(9) Resize the canvas from the Actions menu.** The owner: *"a resize canvas option in actions would be
      nice, to which users can resize the canvas however they want. They should be able to control whether it
      gets cropped/expanded, or if everything gets scaled."* Two controls: a **scale** option that scales the
      existing artwork, and a **toggle** for it to scale automatically with the new canvas size. **On an aspect
      change it letterboxes** — *"Not in the conventional sense of adding black, just scaling the stuff so it
      fits."* i.e. fit the content inside the new extent preserving its own aspect, leaving real empty canvas
      rather than painted bars.
      Note this is adjacent to report (6): the owner's freeze sequence names *"try to resize the canvas"*, so
      whatever exists today on that path is worth understanding before extending it.
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
are evidence, their *causes* are hypotheses. **(5) is answered and is not a defect.**

- [ ] **(1) The live unbaked Move preview disappears sometimes.** *"I think it happens when there are
      compositing layers over it like brightness/contrast."*
- [ ] **(2) No marching ants while the lasso is being drawn.** *"while I am actively drawing the lasso or
      even lasso fill, I cannot see the lasso outline marching ants. Make it the same blue and white as
      when the pen is lifted."* Covers lasso *select* and lasso *fill*.
- [ ] **(3) Text is invisible in distort mode, and invisible when the box is too small for it.** Carries a
      ruling: *"The box should never be allowed to be smaller than the text size unless in distort mode."*
- [ ] **(4) A pencil tap spawns the text box but does not raise the keyboard.** *"I need to click again on
      the box with my finger to bring it up."* Their theory — the pencil is treated as drawing — is the
      thing to test, not to assume.
- [x] **(5) Freeform / Uniform / Distort greyed out in Move — intentional, not a defect.** Confirmed in the
      code: `MoveTransformBottomBar.swift:24-27` says the picker is live only for a raster piece because a
      lassoed vector piece scales uniformly, and **Move stage 3 is what turns it on**. Distort is stage 5.
      Both are designed and unstarted (HANDOFF.md). Nothing to fix; the ask is to *build stage 3*.
- [ ] **(6) The UI freeze is back.** *"it seems like it happens when your in the edit text keyboard menu,
      then select pencil brush or try to resize the canvas in some kind of sequence of actions ... a
      previous session reportedly fixed the UI freezing canvas move bug, and somehow its still here."*
      The earlier one is pinned by `CanvasTransformFreezeUITests` — a stroke begun under an open timeline
      popover kills pan/pinch/rotate until the project is reopened. Whether this is that bug's second site
      or a different mechanism wearing the same face is the question.
- [ ] **(7) Funky behaviour adding two images to a vector layer.** Unspecified; the symptom list has to be
      derived from the code and then put back to the owner.


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

Empty. Filled as this pass merges.
