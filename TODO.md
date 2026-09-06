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

**Status** — not started.

> *"Lets say a brush is segmented, and that brush creates an enclosure, and that enclosure gets filled.
> Right now the fill would leak through the gaps in the segmented line. I want the fill tool to also
> make the line path itself behave like a wall too, so that if I fill the enclosure with the segmented
> lines, then it still fills the shape properly, bridging those gaps. (rough ink on low pressure does
> this segmentated line for example)"*

The fill works on **pixels** — it thresholds what is painted and floods between it. A brush whose dabs
do not overlap paints a dotted line, so pixel-wise there is no wall there and the flood walks straight
through. The **Gap Closing** slider is the existing answer and it is the wrong tool for this: it closes
gaps by radius, so a gap wide enough to matter needs a radius that also closes gaps the artist wanted
open, and Rough Ink at low pressure can leave gaps far wider than any safe radius.

**The ask is different in kind and that is what makes it a good one: a vector layer knows where the
stroke *is*, whatever it painted.** `StrokePath` is the curve every tier walks and it is continuous by
construction, so a fill on a vector layer can rasterize the stroke's *centre line* into the barrier
mask alongside the painted pixels. Segmentation stops mattering, and no radius has to be guessed.

**Questions to settle before building**
- Vector layers only — a raster layer has no path. Say so in the UI or accept that the two tiers fill
  differently. This is the kind of silent divergence CLAUDE.md's "a refusal with no notice" section is
  about.
- Which strokes count as walls: every stroke in the cel, only the visible ones, only ones above some
  opacity? A stroke at 5% opacity is invisible and would become an invisible wall.
- Does the centre line get the stroke's width, or a hairline? Width interacts with **Edge Overlap**,
  which for a lasso is an *erosion* radius — maximum means radius zero, so *lowering* it manufactures
  more of the diagonal pinch points that (44) turned out to be about.
- Does this replace Gap Closing on vector layers, or sit beside it? Two controls that do overlapping
  things is what §2.20 of BRUSH.md pushed back on elsewhere.

**Spec** LASSO_FILL.md §6 is the algorithm; step 3's collar flood is where a path-derived barrier
would join it.

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

**Status** — not started. Diagnosed by the owner from behaviour, and the code agrees exactly.

> *"The end of the animation timeline should be the last frame… if I do an extend to end on a cel, then
> it extends that cel to the 12th frame even if the last cel is not on frame 12. If I manually extend a
> frame to a further frame, then retract it back, then do an extend to end, then the extend to end goes
> up to that last frame I extended to. This points at a deeper issue… This variable is default set to
> 12, and increases whenever a cel gets put higher, but never falls back down when the last cel
> changes, only expands."*

**Confirmed.** `CanvasManager.sceneFrameCount` is `@Published var sceneFrameCount: Int = 12`, and
**every single write to it in the app is `sceneFrameCount = max(sceneFrameCount, …)`** — eight of them
across `CanvasManager+Timeline` and `CanvasManager+BlockDrag`. Nothing ever lowers it. It is also
**persisted** in `ProjectManifest`, so a document carries its high-water mark across save and reload,
and `captureStructure` snapshots it so undo restores the old mark rather than recomputing.

The owner's read that playback is unaffected is right and is the clue to the shape of the fix:
playback stops at the last cel, so **the true end is already derivable** — `layers.flatMap(\.cels).map(\.endFrame).max()`.
Nine files read `sceneFrameCount`; the question is whether each one wants the derived end, a
deliberately larger *canvas* of empty frames the artist can drag into, or nothing at all.

**Left to build**
- [ ] Establish what each of the nine readers actually means by it — `gapFrameRange` uses it as "the
      end", the timeline views may want scrollable empty space past the last cel, and those are
      different quantities wearing one name.
- [ ] Either make it derived and delete the stored field, or keep a stored *scene length* that the
      artist sets deliberately and make everything that means "the last frame" ask for that instead.
      **Do not simply add a recompute** — a value that is sometimes derived and sometimes stored is
      how this went wrong.
- [ ] Decide what a saved document with an inflated mark does on open, under the standing
      expendable-documents permission.
- [ ] Pin extend-to-end against a document whose last cel is short of the mark. That test goes red
      today, so write it first.

**Related** (39), which is the other three timeline defects, but this one is architectural rather than
a UI bug and does not share their causes.

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

## (12) Distort on ink, and Distort keyed across frames

**Status** — partly built. The raster tier ships. **The ink tier's stated blocker has lifted and the
code has not noticed.**

> *"The distort in move feature must still be built and integrated with keyframes."* — 2026-09-06

A four-corner drag on the raster floating piece works in both `.move` and `.duplicate`, previewed
through `CATransform3D` so the drag rasterizes nothing, and MEASURED at 0.0 disagreement between what
the finger sees and what bakes. **Ink is refused** — `distortUnavailableReason` still says *"Distort
needs a pixel selection"* — on the stated grounds that under a homography the local scale spans 1.3x
to 8.5x across one quad and no single scalar for `VectorStroke.size` is right.

**That reason is out of date.** KEYFRAMES §8 stage 4, the rest-space dab bake, merged 2026-09-02:
`BrushStamper.DabPose` holds a `Homography` and answers `localScale` and rotation **per dab** exactly
when the map is projective, and `PosedDabTarget` is wired into the shipped render. The machinery is
built and running; the refusal is unjustified by its own argument, and the stale sentence is in the
shipped source as well as in the spec.

**One design question is genuinely open and is named nowhere yet: what a projective float *commits*
to.** `restWalk` is transient and absent from `VectorCanvasData`, so baking cannot go through
`mapping(…)`'s one-scalar-into-`size` path. Either persist a per-stroke projective pose or re-sample
the geometry — that is a decision, not wiring.

**Left to build**
- [ ] A projective entry point: `posing(_:through:)` and `mapping(_:throughStretch:)` take
      `CGAffineTransform` only, and the app's sole `DabPose` construction is from an affine.
- [ ] `VectorFloat.poses` carries a `Homography`; `FloatingDistortDrag` stops refusing the delta; both
      arms of `distortUnavailableReason` go.
- [ ] **Decide and build the commit** — persist a projective pose, or re-sample. See above.
- [ ] Non-stroke arms: a fill is a `CGPath` and Béziers are not homography-closed; a placed image has
      no Distort door at all (six numbers plus a mirror bit where a homography needs eight). Text
      already has one by its own door.
- [ ] **Keyed across frames — KEYFRAMES §8 stage 5b.** `TransformKeyframes` only ever writes a
      `PoseQuad` built from an affine, and `PoseQuad.affineOrLinearised` linearises a projective pose
      at the box centre — wrong by up to 315% at a strong keystone. Store a genuinely projective quad,
      route the two render reads through `DabPose(Homography)`, blend two projective quads, and lift
      the container-pose Distort refusal.
- [ ] Port `FloatingPieceOverlayView` onto the stage 4 handle pattern (this one is a BUGS.md entry and
      may belong there instead).

**Spec** LASSO_MOVE.md §3 stage 4 · KEYFRAMES.md §8 stage 5b. **§5 is twenty-six owner rulings; do not
re-litigate any of them.**

---

## (39) The timeline freeze

**Status** — (a) and (b) are fixed; the recorder now watches the timeline's own recognizers. **(c) is the whole of what is left, it did not reproduce, and the analysis it was filed
under is wrong** — see below before spending anything on it.

The pinch anchors on the frame it started on at any scroll offset
(`TimelineKeyMarkers.PinchAnchor`), and the track fills its viewport rather than stopping at the last
row (`TimelineRowLayout.contentHeight(filling:)`), so there is no dead strip and the gridlines rule to
the bottom of the panel.

**Left to build**
- [ ] **(c) The timeline stops responding.** The owner captured it:
      [docs/bug-evidence/timeline-freeze-2026-09-06.md](docs/bug-evidence/timeline-freeze-2026-09-06.md)
      is the analysis and the `.jsonl` beside it is the trace. In the fifteen seconds they describe as
      frozen, 34 touch-downs land on a `TimelineRowView` and `currentFrame` moves twice. That much
      holds. **What that document concludes from it does not.**

      **The "detached row view" reading is refuted by its own data.** It says the row is on screen but
      its ancestor chain no longer holds the scroll views. Three things in the same trace say
      otherwise. `TimelineRowView.tapRecognizer` has **no delegate** and is added in `init`, so a live
      row offers it to every touch — MEASURED present in 100% of row touch-downs in a clean simulator
      capture — and it is **missing from 9 of the 14 dead touches**. Re-parenting a view cannot remove
      *its own* recogniser from `touch.gestureRecognizers`; it can only remove its ancestors'. At
      t=21.98 a `TimelineRulerView` keeps its own long press while carrying none of its ancestors'
      recognizers, so the ruler is affected too and it is not a recycled row. And the recogniser set
      already drifts *inside* the healthy window — one scroll pan at t=5.80, two at t=8.23; no
      delayed-touches at t=6.45, two at t=8.23 — so `grNames` is a noisier signal than the 17/17
      table implies. **What all of that does fit is the timeline's recognizers wedged in a
      non-`.possible` state**, which is why they stop being offered touches while the views stay
      hit-testable; a clean capture shows `timeline.scroll` sitting in `.failed` for seconds at a time
      between sweeps, so the state is reachable in the ordinary course of events.

      **The `sceneFrameCount` lead is refuted too.** Driven in the simulator — scrub to frame 20 with
      the scene still 12 long, draw there, then tap rows — the timeline keeps scrubbing. Five driven
      sequences in all (plain taps; a cel past the scene end; a gap menu raised and dismissed; repeated
      two-finger swipes across the track; a pinch), and none froze. `relayout` cannot orphan a row
      either: `rowViews` is only appended to, or truncated from the end when the layer count drops.

      **The concrete suspect worth starting from** is `scrollView.panGestureRecognizer.require(toFail:)`,
      which `relayout` calls once per row view **ever created** and never undoes — there is no
      un-require API. A pool that grows, shrinks and grows again therefore leaves the scroll pan
      requiring recognizers whose view is gone. Unproven, and it is a different shape of bug from the
      one this item was filed as.

      **The next capture is decisive and the instrument for it is in.** `timeline.scroll`,
      `timeline.pinch`, `timeline.rulerScrub`, `timeline.graphBand` and every row's
      `timeline.row<N>.tap` / `.press` / `.resize` are named for `ActionRecorder`, so a recording now
      carries their state transitions per touch instead of only the `grNames` column. Ask the owner
      for one capture of the freeze with the recorder on; it will say in one line whether a recogniser
      is stuck and which.

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
