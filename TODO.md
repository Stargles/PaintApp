# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what *we* find.

## How to read and keep this file

Every item is a **status**, a short **description** a future session can pick up cold, and **what is
left** as a checklist. Items are in **queue order** — the top of the list is what to do next.

**An item leaves this file when it is merged, not when a branch exists**, and it leaves *whole* rather
than being marked done: `git log` and the spec documents are the history. The owner, 2026-09-06:
*"Basically I want to be able to read the tasks on TODO clearly without already finished tasks."*

**Three in flight at once** unless the extras need no simulator — the cap is about the machine, not the
plan (`tools/simlock.sh`).

**Before adding an item, check whether an existing one already covers it in different words.** A
restatement filed as a new item is how one feature came to be specified in six documents at three
scopes before a line of it was written. This file has since carried two live duplicates for weeks.

**Record an ask in the owner's own words, and fold a ruling into the item it rules on.** A quote is
cheaper to keep than a decision is to rebuild. But an item reads as *one current description*, not as
the transcript of the argument that produced it — what happened this pass belongs in
[HANDOFF.md](HANDOFF.md) and in `git log`.

**Cite a symbol, not a line number.** A 2026-09-06 audit found ~10 of one item's 15 `FILE:LINE`
citations and 5 of another's 11 no longer resolved — every named fact still true, every anchor wrong,
two of them because a file moved directory. A symbol name survives a refactor and a line does not.

**Verify a status before trusting it, including this file's own.** That same audit found fourteen
assertions here that the code contradicted — features called unbuilt that shipped weeks ago, a blocker
called live that had lifted, and two commit shas that are not on `main`.

**No document written so far has to survive.** The owner, 2026-08-27: *"Don't worry about legacy
documents right now, everything on the ipad right now is expendable."* A format change needs no
migration and no "existing documents change appearance" warning. This is standing permission, and it
lapses the day the owner starts keeping real artwork in the app — whoever notices that should say so
rather than assuming it still holds.

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure taken before 2026-08-17 was at 4096², eight times the pixels.

---

## (41) Mid-list edits and two kinds of undo that still re-stamp the whole cel

**Status** — partly built. **The general undo/redo work shipped 2026-09-06** (PERFORMANCE.md §11.11a);
what is left is two cases that are blocked on something a rectangle cannot fix.

> *"Undoing and redoing while there are a lot of strokes can be laggy, a few hundred milliseconds
> sluggish."* — 2026-09-06, after a first fix landed too narrowly

**What the artist is waiting for was measured rather than reasoned about, and it settles the shape of
the complaint.** The main-thread span of an undo press is **0.44–7.84 ms** across 200–4,000 strokes;
the render it causes is **5–2,275 ms**, 96–99.7% of the wait, and off the main thread. So the app
never stops responding — "laggy" is the old picture standing there. The **raster** arm is 0.02 ms a
press at both 2048x1024 and 4096² and needs nothing at all.

**The redo was 5.6–11.3x its own undo on the same one stroke**, which is the commonest pair of presses
in the app, and this item had written that off as permanent. It was wrong: the ink coming back *had*
been drawn, immediately before, by the walk that measured it. `VectorCanvas.vacatedInk` keeps that
measurement while the id is out of the list. MEASURED in Release: a redo at 1,000 strokes **571 →
51 ms**, at 4,000 **2,275 → 171 ms**.

**Left to build — and note this item's earlier "there is no design left to do" was wrong twice.**
- [ ] **A departing fill, image, text object or video forces `.everything`** whatever rectangle the
      caller passes, because `renderLocalContent` measures no footprint for those kinds. So the undo of
      a fill and the undo of a text commit still pay the whole cel, while their redos no longer do.
      The fix is to measure a fill's path bounds into `paintedBounds` — exact, unlike a dab walk — and
      teach `restoreDamage`'s departing loop to accept it. A text object's glyph extent and a placed
      image's quad are the same question.
- [ ] **A rewrite in place cannot be bounded by this mechanism at all.** Recolour, Apply Brush, a text
      re-edit, video crop and speed, motion-group retags, `keyPoseRestoringRest`, and **every
      lasso-move nudge** — `drawn(_:through:widthScale:)` preserves an element's id by explicit design.
      These declare `.rewritesInPlace` now instead of saying nothing, which is the honest state and not
      a fix. Bounding them needs a different idea: an id whose *content* changed needs its old
      footprint forgotten and its new one bounded, and no rectangle from a caller supplies that.
- [ ] **The four call sites with the tightest rectangles are exactly the ones whose departures are not
      strokes**, which is why the "measure what was replaced" recipe never reached them.

**Blocks** (42). **Spec** PERFORMANCE.md §11, §11.10, §11.11, §11.11a.

---

## (43) Merging two vector layers produces a raster layer

**Status** — **all three stages built on `tmp/vecmerge`, not merged.** Full fast tier green there; the
item stays here until the branch lands, per this file's own rule that an item leaves when it is merged
and not when a branch exists.

> *"when you merge two layers it doesnt work for vector layers, the merged layer turns out as a raster
> layer. Make it vector compatible."*

**What shipped on the branch.** `CanvasManager.vectorMergeIsExact` is the design: two vector layers
merge to a vector layer wherever concatenating their display lists draws what compositing their two
renders draws, and everywhere else the pixel bake runs as it always has with a
`CanvasNotice.mergedAsPixels` saying so. `VectorCanvas.splitPreservesTheWalk` is
`appendPreservesTheWalk` lifted rather than a second copy of the isolation rules.
`VectorMergeLogicTests` holds the predicate to its claim byte for byte in both directions.

Two silent losses in the same code went with it. "Merge Down" called `mergeLayers` bare while the
pinch consulted `mergeLossKind`, so one pair prompted on a pinch and discarded on a tap —
`requestMerge` is the single entry point now, and the predicate gained the clip on the upper layer
(an `AlphaMask` or `.clipToBelow`, both of which the bake has always dropped in as many words). And a
merge flattened only the cel pair under the playhead before deleting the upper layer whole, losing its
ink at every other frame; `alignCelBoundaries` + `mergeAlignedCels` walk the union of both timelines,
so a merge can now *increase* the survivor's block count where the spans disagree.

**Left**
- [ ] Merge `tmp/vecmerge` to `main`.
- [ ] Deferred, no measured need: `ValueFill` as a canvas-sized `.fill` element; relaxing the erase
      case; and relaxing `splitPreservesTheWalk`, which is conservative when the prefix ends in
      something that is not a paint stroke (it is shared with the incremental append, so tightening it
      moves that too).

---

## (46) A fill should treat a stroke's path as a wall, not just its ink

**Status** — **built on `tmp/skinfill`, not merged.** The item stays here until the branch lands.

> *"Lets say a brush is segmented, and that brush creates an enclosure, and that enclosure gets filled.
> Right now the fill would leak through the gaps in the segmented line. I want the fill tool to also
> make the line path itself behave like a wall too, so that if I fill the enclosure with the segmented
> lines, then it still fills the shape properly, bridging those gaps. (rough ink on low pressure does
> this segmentated line for example)"*

**What shipped on the branch.** `StrokeWallMask.mask` rasterises every wall stroke's **centre line** —
`StrokePath.flattened`, the same flattening the dab march walks — in **the colour that stroke paints**,
and `computeWalls` puts each path pixel through the same threshold test the reference's own pixels
take. So the rule is *"the path behaves as if the stroke had painted a continuous line of its own
colour"*, applied upstream of gap closing, of the bucket flood and of the lasso's collar flood, so all
three obey it and none of them needed changing. **No new control**, and the owner ruled the
vector/raster divergence needs no notice: *"let it be. It's just a property with vector layers."*

**Carrying the colour rather than a flag is the load-bearing part, and the first build got it wrong.**
An unconditional wall took the **Threshold** slider away on every vector layer;
`FillLiveAdjustUITests.testAdjustingThresholdAfterFillReappliesToUncommittedFill` caught it. That is
now pinned headlessly too.

**The other decisions, each argued in `StrokeWallMask`'s own doc comment.** A **hairline** (1.5 px,
antialiasing off — a 1 px stroke on an integer coordinate can rasterise to nothing at all), not the
stroke's width, because the dabs already wall as far as they cover and a wider wall would move the
flood boundary without moving the coverage ramp LASSO_FILL.md §6 step 7 anchors on. **Beside Gap
Closing, not replacing it** — no control added or removed. Paint strokes only: erase strokes, fills,
images, text and video are not lines, and a **suppressed** element is not drawn. A stroke that paints
nothing walls nothing, *derived* from the colour it writes rather than ruled by a threshold.

**Cost, MEASURED** (Debug, simulator, 2048x1024): 28 / 51 / 177 ms at 200 / 1,000 / 4,000 strokes,
once per gesture on `fillQueue`, against 621 / 3,097 / 12,345 ms for the cold `VectorCanvas.render()`
beside it. Not optimised; the lever if one is ever needed is a memo on `contentVersion`.

**One behaviour change that is not about gaps, and it is the thing to look at on the device**: a line
*inside* a flat region now splits it for a recolour wherever that line's own colour is outside
Threshold of the tapped one, where the flood used to cross it once the *pixels* were within tolerance
and the gaps between dabs were open. Same rule seen from the other side.

**Left**
- [ ] Merge `tmp/skinfill` to `main`.
- [ ] Nobody has yet drawn a segmented enclosure **with a pencil on the device** and filled it.
      XCUITest cannot synthesise pressure — `StrokeInput.init(touch:in:)` gives a finger 1.0 — so the
      low-pressure Rough Ink case cannot be driven from a UI test at all. It is pinned headlessly
      instead (`StrokeWallLogicTests`, which attaches a three-panel contact sheet of the drawn
      fixture, the leak and the containment through the production render and the production GPU
      session), and the app-level regression is `FillContainmentUITests` / `FillLiveAdjustUITests` /
      `FillUndoRedoUITests`, green.

**Spec** LASSO_FILL.md §6 step 2d.

---

## (47) A finger tap bakes a Move while the pen-only toggle is on

**Status** — not started. Small, and it costs the owner a mis-bake every time it happens.

> *"when you are moving an object with pen only draw on and then tap somewhere else on the canvas with
> your hand, it bakes the move. It should only do that when the pen is tapped on the canvas. Currently
> the pen part works, its just the finger tap bake that I want to change."*

`pencilOnlyDrawing` already reaches the canvas views (`CanvasManager.pencilOnlyDrawing`, pushed onto
`strokeView` and the overlay in `CanvasView`), so the setting is known where the tap is handled — the
commit-on-tap path simply is not consulting it. A finger tap while the toggle is on should do whatever
a finger tap does *outside* a Move (pan, or nothing), never commit.

**Left to build**
- [ ] Find the tap that commits a float and gate it on touch type when `pencilOnlyDrawing` is set.
- [ ] Check the same hole in the other commit-on-tap gestures — text, shape, the interactive fill —
      rather than fixing only the one that was reported.
- [ ] A test that a finger tap with the toggle on leaves the float lifted. **XCUITest cannot synthesise
      a pencil**, so the pen half cannot be driven from a test; assert on the touch-type decision
      directly rather than writing a UI test that silently downgrades to a finger.

---

## (50) `sceneFrameCount` is a high-water mark that never falls

**Status** — **built on `tmp/sceneend`, not merged.** The item stays here until the branch lands, per
this file's own rule that an item leaves when it is merged and not when a branch exists.

> *"The end of the animation timeline should be the last frame… if I do an extend to end on a cel, then
> it extends that cel to the 12th frame even if the last cel is not on frame 12. If I manually extend a
> frame to a further frame, then retract it back, then do an extend to end, then the extend to end goes
> up to that last frame I extended to. This points at a deeper issue… This variable is default set to
> 12, and increases whenever a cel gets put higher, but never falls back down when the last cel
> changes, only expands."*

**The diagnosis was exactly right and the field is deleted.** `CanvasManager.contentEndFrame` — which
already existed, and which playback already used, which is why the owner saw playback escape the bug —
is now the only account of where the scene ends. Every reader that meant "the end of the timeline"
asks it: extend-to-end, the gap menu's range, the loop clamp, the frame label, `BakeQueue`'s universe,
the export range, the graph band's drawn bound, and the length of a new layer's first block. The
twelve survives as `CanvasManager.defaultNewSceneFrameCount`, applied at the one moment it ever meant
anything — the first layer of a document that has none.

**The empty track past the last drawing was never this field**, which is what made deleting it safe:
it is `TimelineTrackExtent.displayedFrameCount`, two screenfuls past wherever the artist has scrolled,
now a testable static rather than a rule living inside `TimelineTrackView.Coordinator`.

**Two things the brief did not expect.** The field had **fifteen** app-side readers, not nine. And
`effectiveLoopRange` must *not* be re-pointed at the derived end: a loop marker placed in the empty
track is intent, and clamping it to the content silently retracts it — caught by
`testMarkersSetPastTheContentAreStillHonoured`, so the markers are floored at zero and not ceilinged.

**A saved document with an inflated mark** loses it: the key is gone from `ProjectManifest` and the
end is recomputed from the cels on load, under the standing expendable-documents permission.

**Driven, not only asserted.** `SceneEndReachabilityUITests` starts at the gallery, makes a canvas,
drags the block shorter and uses the real Extend to End row — and then puts a second drawing in the
empty track past it, which is the check that the shorter scene is not a shorter *timeline*.

---

## (40) Onion skin z-order — ruled, and built

**Status** — **built on `tmp/skinfill`, not merged.** The item stays here until the branch lands, per
this file's own rule that an item leaves when it is merged and not when a branch exists.

**The design, in the owner's own words** (2026-09-06):

> *"the onion skin always renders on top of the compositor. This is the idea for the 'in front'
> option. For the 'Behind' option, it is still rendered on top of the compositor, but then uses the
> inverse of the current drawing layer as an alpha mask. Thus, the onion skin is not affected by the
> compositor giving the animator a clear view at their art. When they set it to below, the onion skin
> gets masked out in the areas that the current layer is drawn."*

**What shipped on the branch.** There is **one** onion-skin view now, not two, and `updateOnionSkin`
fronts it above every layer host and above `sandwichAbove` on every pass — `reconcileLayers` no longer
threads a ghost through the stack and `OnionSkinKey` no longer carries a placement, because placement
changes no pixel of the composite. `OnionSkinClip.mask` is the ruling: §6.4's coverage with the current
drawing's alpha taken out of it by one `.destinationOut` draw, built at the *skin's* resolution rather
than the canvas's. `CanvasManager.onionSkinInkToSubtract` is the single reader of the placement setting
— In Front answers nil and the clip is byte-for-byte what it was — so the view coordinate, which no
headless test can reach, holds no decision of its own.

**Three decisions taken, each stated in the source.** A **hidden** current layer subtracts nothing
(a cut by ink nobody can see is the surprise). A **`.value`** layer subtracts nothing (a canvas-filling
flat colour would erase the whole ghost). Layer **opacity is not folded in** — the cut is full wherever
there is ink, because the ruling's stated purpose is a clear view of your own art and a proportional
cut puts the ghost back under half-opacity ink.

**One known gap, deliberately not closed here.** A current layer moved by an enclosing transformation
layer is cut where its ink *rests*, not where it is *drawn* — because nothing in the onion-skin
subsystem poses a skin either, and `OnionSkinRasterCache` has no `pose` argument. Cutting by a rule the
ghosts themselves do not follow would be worse than the gap.

**Left**
- [ ] Merge `tmp/skinfill` to `main`.

---

## (12) Distort keyed across frames

**Status** — partly built. **The raster tier and the ink tier both ship.** What is left is the
*animated* one: a projective quad keyed over time, which is KEYFRAMES.md §8 stage 5b.

> *"The distort in move feature must still be built and integrated with keyframes."* — 2026-09-06

A four-corner drag works on the raster floating piece (2026-09-02) and on a **lassoed drawing**
(2026-09-06). The ink tier's refusal — *"Distort needs a pixel selection"* — was a measurement that
had already expired: `VectorStroke.size` is a scalar and a homography's local scale spans 1.3x-8.5x
across one quad, but KEYFRAMES §8 stage 4's rest-space dab bake merged on 2026-09-02 and
`BrushStamper.DabPose` answers `localScale` and `rotation` **per dab**, so there is no single scalar on
that path to be wrong. `VectorCanvas.mapping(_:through: Homography)` is the entry point;
`VectorStroke.distort` is what a commit stores — the **map** plus the artist's own width, with the
pre-image rebuilt at render by `effectiveWalk`, which is why no cutter needed a rest-space arm.
What is refused now is a *kind*: a placed image or a video stores six numbers and a mirror bit where a
homography needs eight, so a float carrying one says so in a sentence.

**Left to build**
- [ ] **Keyed across frames — KEYFRAMES.md §8 stage 5b.** `TransformKeyframes` only ever writes a
      `PoseQuad` built from a `CGAffineTransform`, and `PoseQuad.affineOrLinearised` linearises a
      projective pose at the box centre — wrong by up to 315% at a strong keystone. Store a genuinely
      projective quad, route the two render reads in `TransformTrack` through `DabPose(Homography)`
      instead of `affineOrLinearised`, blend two projective quads (`PoseInterpolation`), and lift
      `distortUnavailableReason`'s container-pose arm. The engine below it is done: `posing`'s
      `Homography` overload, `restDelta`'s projective twin and `composedWalk` all exist and are tested.
- [ ] Port `FloatingPieceOverlayView` onto the stage 4 handle pattern (this one is a BUGS.md entry and
      may belong there instead).

**Spec** LASSO_MOVE.md §0 *"Distort, on a lassoed drawing"* · KEYFRAMES.md §8 stage 5b. **§5 is
twenty-six owner rulings; do not re-litigate any of them.**

---

## (39) The timeline freeze

**Status** — (a) and (b) are fixed, and the recorder watches the timeline's own recognizers
(`timeline.scroll`, `timeline.pinch`, `timeline.rulerScrub`, `timeline.graphBand`, and every row's
`timeline.row<N>.tap` / `.press` / `.resize`). **(c) is the whole of what is left. It is now
reproduced and its cause is known; what remains is a design decision, not an investigation.**

The pinch anchors on the frame it started on at any scroll offset
(`TimelineKeyMarkers.PinchAnchor`), and the track fills its viewport rather than stopping at the last
row (`TimelineRowLayout.contentHeight(filling:)`), so there is no dead strip and the gridlines rule to
the bottom of the panel.

**Left to build**
- [ ] **(c) A timeline menu eats every drag on the timeline and only a tap dismisses it.**
      [docs/bug-evidence/timeline-freeze-2026-09-06.md](docs/bug-evidence/timeline-freeze-2026-09-06.md)
      is the trace, the reproduction and the two refutations; read its last three sections.

      **Reproduced 2026-09-06.** While one of the four timeline menus is up, a drag anywhere on the
      timeline is swallowed whole — the track does not scroll, the ruler does not scrub, and the
      popover does not go away. Only a **tap** dismisses it. MEASURED from a new document: two 200 pt
      drags on the track leave the cel block at x 188.0 and the playhead at frame 7 with the menu
      still standing; a tap in the same place dismisses it; the identical drag then scrolls the track
      to −181.5. `MenuInterruptionUITests.testADragOnTheTimelineWhileABlockMenuIsUpIsSwallowedWhole`
      is that measurement and is **a characterization of a defect that is still open** — it goes red
      when this is fixed, deliberately.

      That is exactly the owner's trace. A tap 14 pt from the previous one raised the block menu at
      t≈20.5, `_UIPassthroughGateGestureRecognizer` appears at t=21.02, no timeline gesture fires
      again until they **tap** the toolbar at t=26.57. Reconstructing the gestures rather than the
      `grNames` column is what settles it: almost every "dead" touch is a **swipe** of 24–282 pt, and
      **every genuine tap in the trace worked**, so the freeze is five seconds long and not fifteen.

      **Two published analyses of this are refuted and both are worth not repeating.** The row view is
      *not* detached — 15 hit-tests during the dead drags all carry the row's own three recognizers,
      the pinch, `timeline.scroll` and both scroll pans, and `TimelineRowView.touchesBegan` never
      fires, so UIKit is declining to *offer* the touch, not missing the views. And
      `relayout`'s un-removable `require(toFail:)` does **not** accumulate: `_failureRequirements` is
      a deduplicating **weak** set and a recogniser does not retain its target, so a row leaving the
      pool takes its entry with it (`TimelineGestureArbitrationLogicTests`; the harness that seemed to
      show 3, 6, 9, … was measuring its own autorelease pool).

      **What is left is an owner decision**, because there is no in-app seam — the touch never reaches
      the timeline. `.presentationBackgroundInteraction(.enabled)` is a sheet API and measurably does
      nothing here. The two real options are to reach
      `UIPopoverPresentationController.passthroughViews` (not exposed by SwiftUI's `.popover`) and
      dismiss from the timeline once the touch arrives, or to stop using `.popover` for the four
      timeline menus and draw them as an overlay the timeline panel dismisses itself.

---

## (29) Rendering — the memory audit is all that is left

**Status** — stages 0 through 6 merged. **Stage 7 remains and is a real stage, not a leftover
heading**; none of it is built.

The owner thought this one was done, and it is ~90% done. The live stroke no longer scales with canvas
area, playback runs off the model's clock, the pen-up snapshot resolves off the main thread (MEASURED
174–313 ms of main-thread work down to **0.2 ms**), a frame composites one chunk at a time under a
memory ceiling byte-exactly on both backends, the canvas at rest and playback are served from LZ4
frames on disk, a frame too big for the budget is composited in horizontal strips at the size the
artist asked for, and export ships with tests.

**Left to build** — RENDER.md §5 stage 7, the memory audit. BUGS.md's twelve-site census is the list.
- [ ] A fill-session budget (`MetalFillEngine` has no budget or headroom check at all)
- [ ] Blanked hosts release their pixels — `setBlanked` installs a zero-alpha mask; it should nil
      `contents`
- [ ] Count-only caches become byte budgets (`vectorRenderCacheLimit` is still a count of 12), and the
      per-playback-tick evictor in `SelectionModels` goes
- [ ] A `MemoryPressure` seam — no such type exists anywhere in the app
- [ ] Vector-element undo charges real bytes rather than a per-element constant
- [ ] `SaveSnapshot` off the main actor
- [ ] Two device measurements: the compression ratio against the owner's own "UI Test" document, and a
      decode of a compositor-produced frame at their canvas size

**Spec** RENDER.md — **§2 is sixteen owner rulings; read them rather than re-deriving them.** Note
RENDER.md §5 stage 6 still claims the export driver and sheet are untested with no XCUITest; that is
stale in the *spec* — both landed at `8eb5aa5`.

---

## (21) Keyframes — four stages and four gaps

**Status** — partly built. Stages 0, 1, 2, 2b, 3a, 3b, 4, 5, 5a and 8 are merged; 6b was delivered by
(29); there is deliberately no stage 9.

A cel or an animation group carries a track of quad poses, ink is posed through the `sqrt(|det|)`
width rule with endpoints bit-exact, a pose channel has a six-curve graph-editor band that is
read-write, a transformation layer is reachable and usable, animation groups can be named, and every
pose key has a node.

**Left to build**
- [ ] **Stage 5b** — animated Distort. Shared with item (12); see there for the detail.
- [ ] **Stages 6, 7 and 10.** Which goes first is an owner question rather than a settled order.
- [ ] `LayerFolder.transform` exists in the model with **no UI entry** — `transformMoveRow` is in the
      layer options panel and never in the folder one. A row and a box, not new machinery.
- [ ] Graph-editor **node delete and tap-to-add**, still refused "for want of a writer".
- [ ] **Animation-group membership editing needs a design conversation first.** §2.29 rules that
      splitting one animated group into two is *"a different feature"*, and retagging an element is
      that question from the other side — every key on both groups' tracks changes meaning.

**Spec** KEYFRAMES.md — **§2 is twenty-eight owner rulings and §8 is the build order.** Four rulings
are superseded and kept; the file says which.

---

## (31) The 16383² canvas cannot be composited at all

**Status** — two of the three original symptoms are **fixed and closed**; this is what is left of the
third.

The owner is right that the reported problem is gone. The resolution knob is obeyed —
`CompositorBudget.affordableSize`, `budgetTextures` and `CompositorSizeGate` are all deleted, and
`StripedComposite` composites at the size asked for, pinned byte-for-byte on both backends. The
freeze after a stroke lift is gone: the main thread does four things at pen-up and none is
proportional to canvas area. The 16k crash is fixed (283.1 MB → 4.42 MB a gesture) and the
disappearing stroke with it.

**Left to build**
- [ ] At the maximum extent the image still cannot be composited in one piece and wants a **downscaled
      display proxy** — or a lower `maxCanvasExtent`, which is the cheaper answer if the owner does not
      need 16k.
- [ ] The remaining lag at that size is the owner's own deferral, pending an A/B they want to see.

---

## (42) Editing the strokes inside a selection, not just their colour

**Status** — not started, and blocked on (41)'s remainder.

> *"i plan to replace the change color of selection into a better tool where you can also change the
> brush type, size, etc. of the strokes inside the selection. The color changer also shouldnt be the
> current selected color, but instead show the color picker menu defaulting to the current color. all
> changes able to be seen live in the drawing."*

Half of it shipped: the Select panel's **Brush** button re-points a selection at a brush as one undo
step (BRUSH.md §2.10), and `applyBrushToSelection`'s own doc says size, opacity and colour are
deliberately untouched and points back here.

**The live requirement is the load-bearing one and it has a hard prerequisite.** Adjusting a selection
rewrites elements in place, so every tick of a slider is a mid-list edit — a whole-cel re-walk is
~142 ms at the owner's density and 745 ms at 1,000 strokes, so a slider driving one is unusable.
**(41) is a prerequisite, not an optimisation.**

**Left to build**
- [ ] Brush kind and size at selection scope, alongside colour
- [ ] A colour **picker** defaulting to the strokes' current colour, rather than applying the palette's
      current one blindly
- [ ] Preview-then-commit so a drag previews without an undo entry per tick and commits once

---

## (26) Import videos — one stage left

**Status** — stages 1 through 7 merged. Stage 8 alone remains.

A video is a real `VectorElement` case with persistence, Split Drawing has its row and its caller and
its suite, and the import path ships.

**Left to build**
- [ ] **Stage 8** — bake a video to cels of images (VIDEO.md §2.9). No bake verb exists yet.
- [ ] VIDEO.md §9's seven open questions.

**Spec** VIDEO.md §8.

---

## (22) Select multiple cels at once

**Status** — not started. The menu row exists and is `.disabled(true)` with an empty action; no
cel-selection state exists. The keyframe half of the same idea is real and shipping.

---

## (10) Linear light as an option on the blend mode

**Status** — not started, and **deprioritised by the owner**.

No colour-pipeline setting, no sRGB/linear enum, no transfer LUT, no `Composite.metal` change.

**One adjacent strand did ship**: `ColorMath`'s sRGB↔linear and Oklab conversions feed the gradient
map, which is this item's own "Oklab still gets built, for interpolation" half. The code credits that
to a "TODO (10a)" that does not exist in this file — either add it or change the comment.

---

## (37) The brush engine — one stage, and the owner has dropped it

**Status** — stages 0 through 11 merged. **Stage 12, the importers, is dropped for now by the owner**
(2026-09-06: *"skip the importer for now"*), so there is nothing actionable in this item today.

Twenty brushes in five groups with every asset generated and no third-party content; opacity and flow
split with a per-stroke buffer; canvas-anchored texture; the brushes menu and the full-screen editor
with orderable module chains, noise octaves and second inputs; relocatable storage; two-axis scatter.

**Left, when the owner wants it**
- [ ] Stage 12 — the `.abr` / Procreate `.brushset` / Clip Studio `.sut` importers. All three are
      undocumented and reverse-engineered, so the stage opens with a survey against real files, not
      with a parser. Test files are a real dependency. §2.21 makes it an **adapter** onto §6's
      modulation matrix rather than a bitmap reader.

**Owner-side, not ours**: their tuning pass over the other nineteen presets, and driving a real Pencil
to exercise tilt, which no test here can reach. BRUSH.md §13 has eight genuinely open questions; three
were offered on 2026-09-06 and declined.

**Spec** BRUSH.md — **§2 is thirty-three owner rulings.**

---

## (45) Prune the repository into a state that can be read

**Status** — not started. Named by the owner 2026-09-06:

> *"A lot of things are messy right now, so it may be worth sifting through to prune, organize, and
> just get the repository in a completely clean and up to date state at some point."*

This file was the first slice and is done. The 2026-09-06 audit that produced it found the same rot in
the specs, so the scope is now known rather than guessed.

**Left to build**
- [ ] **Fix what the specs assert that the code contradicts.** Known: `SelectionModels`'
      `distortUnavailableReason` and LASSO_MOVE.md both cite a blocker that lifted on 2026-09-02;
      RENDER.md §5 stage 6 says export is untested when it has 13 logic tests and an XCUITest;
      BRUSH.md §12 stage 2 has no DONE marker and is done.
- [ ] **Citation rot.** ~10 of one deleted item's 15 anchors and 5 of another's 11 had drifted, two
      because a file moved directory. Sweep the specs the same way and prefer symbols to line numbers.
- [ ] **Dangling references.** `Effect.swift` cites a "TODO (10a)" that does not exist; item (38) is
      referenced twice from the specs with no section anywhere.
- [ ] **Two commit shas cited in this repo's docs are not on `main`** (`2fa1725`, `83f7c0d` — pre-rewrite
      orphans). Sweep for others.
- [ ] Decide whether BRUSH_ENGINE_EXTENSIBILITY.md and REFACTOR_BASELINE.md still earn their place.

---

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

- **(27) Screen-record the computer as a layer.** Requires (26). The app does have `Transferable` and
  `UTType` now; what is genuinely absent is the *drop* gesture — no `onDrop`, `dropDestination`,
  `NSItemProvider` or `fileImporter` anywhere.
- **(28) Audio.** Its stated blocker is **gone** — `PlaybackClock` is a drift-free wall-clock frame
  counter on the model, delivered by RENDER stage 1, which is exactly the hoist this item said it
  needed. `AVFoundation` is linked (for video), though no audio playback code exists.
- **(30) Video editor.** Requires (29).
- **(35) Advanced masks** — colour-range masks and a colour-reassign blend mode. `MaskSource` has two
  cases and there are 25 blend modes with no reassign.
- **(36) Store projects in a folder the artist chooses.** Its stated ordering is **counterfactual now**:
  RENDER stage 6 shipped without a chosen folder by delivering through `ShareLink`, so there is no
  remaining RENDER dependency. `BrushStorage` already documents the security-scoped seam.

---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.
