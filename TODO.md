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

## (41) Undo, redo and mid-list edits re-stamp the whole cel

**Status** — partly built, and **actively in flight**. The two eraser cuts and the undo of a drawing
gesture are bounded; every other edit and every redo still re-walks the cel.

> *"The want is that they all stand reasonably real time in terms of performance no matter the amount
> of strokes for UX."*
>
> *"Undoing and redoing while there are a lot of strokes can be laggy, a few hundred milliseconds
> sluggish."* — 2026-09-06, restating it after a first fix landed too narrowly

A vector cel re-stamps every dab it holds whenever its render memo is missed — MEASURED at 3.16 µs a
dab with **no per-stroke term at all**, so ~142 ms at the owner's own 190-stroke density, 745 ms at
1,000 and 2.98 s at 4,000. Appending a stroke is incremental and free. Everything that is *not* an
append pays the whole cel.

The seam exists and works. `VectorCanvas.Damage.region` plus `repairableBase(quality:)` repairs a
rectangle in the standing picture; `regionDamage(replacing:)` derives that rectangle from what the
replaced strokes last painted. `restoreElements(_:changedInk:)` is the same idea for a wholesale list
swap — **one rectangle serves undo and redo both**, because it bounds every pixel where the two lists
differ. **What is left is wiring, not design**, except where noted.

**The honest guarantee is that cost scales with the area touched**, not that it is always small. A
selection dragged across the canvas has a canvas-sized rectangle and pays for it.

**Left to build**
- [ ] **Redo of an append.** Currently unbounded — the returning ink "has never been drawn", so no
      footprint exists. It has been drawn, immediately before; a one-round-trip memory of what the last
      restore vacated fixes it, bounded to one edit's worth so it cannot grow. The escape check makes a
      stale remembered rectangle cost a retry, never a wrong picture.
- [ ] **`registerVectorElementsUndo`** — the fill, text and Clear-on-selection path. Each call site
      names its own rectangle or passes nil honestly.
- [ ] **Select-and-move** (`CanvasManager+LassoMove`), **recolour** and **Clear** (`SelectionModels`),
      **shape** (`CanvasManager+Shape`). 38 `bumpVersion()` sites remain across these.
- [ ] **Confirm what the artist is actually waiting for.** The render is dispatched *off* the main
      thread, so a slow undo should be the old picture standing there rather than a freeze — that is
      reasoned, not measured. Measure the main-thread span of a press, and check the thumbnail regen
      and the save-damage/bake invalidation, which are not the display-list walk.
- [ ] **Raster-layer undo is a different mechanism** (texture snapshots) and nothing here touches it.
      Measure it; if it is slow at the owner's canvas size it earns its own item.

**Blocks** (42). **Spec** PERFORMANCE.md §11, §11.10, §11.11.

---

## (43) Merging two vector layers produces a raster layer

**Status** — not started. Investigated and designed 2026-09-06; three further defects found in the
same code, two of them silent data loss.

> *"when you merge two layers it doesnt work for vector layers, the merged layer turns out as a raster
> layer. Make it vector compatible."*

`CanvasManager.mergeLayers` has **no vector arm at all** — it calls `rasterizeLayer` on both inputs
unconditionally, then hard-writes `kind = .raster`. This is deliberate and pinned by
`testMergeDownFromVectorLayerRasterizesTheSurvivor`, so it is a decision to re-open rather than an
oversight to patch.

**"Vector compatible" means vector when it can be and raster when it cannot, and the predicate is the
design.** Concatenating two display lists is genuinely the same picture for plain strokes — but not
when the upper layer carries a non-normal blend mode, opacity below 1, an alpha mask, `.clipToBelow`,
an effect, or **any `.erase` stroke**: a punch composites `destinationOut` against everything beneath
it *in its own list*, so after concatenation it starts eating the lower layer's ink. The repo already
computes exactly this question for the incremental-append path — `appendPreservesTheWalk` — so it is a
predicate to lift, not to derive.

**Three traps that will cost a cycle each if missed.** `VectorCanvas` is a `final class` and
`captureStructure` snapshots `layers` by value, so an in-place `elements =` makes both undo snapshots
alias one object and the undo a silent no-op — write a fresh canvas. The float settle
(`commitVectorFloatIfLifted`) currently lives *inside* `rasterizeLayer`, so a vector arm that skips it
bakes away a lifted lasso selection. And element ids are unique only within a cel, so the upper
layer's elements need re-iding, with `motionGroupID`/`animationGroupID` cleared or its ink silently
joins the lower layer's animation channels.

**Left to build**
- [ ] **Stage 0** — route Merge Down through `mergeLossKind` (only the *pinch* consults it today, so
      the same pair prompts on a pinch and discards silently on a menu tap), and add an `AlphaMask`
      case to it. Half a day, independently shippable, fixes live silent loss.
- [ ] **Stage 1** — the predicate `vectorMergeIsExact`, the vector arm, a `CanvasNotice` when it falls
      back to pixels, and the two existing UI tests rewritten. This is what the owner asked for.
- [ ] **Stage 2** — merge every frame. Today it flattens only the cel pair at the current frame and
      then deletes the whole upper layer, **losing its ink at every other frame**, and rasterizes all
      of the lower layer's frames to serve one merge. Write the characterization test against `main`
      first; it goes red today.
- [ ] Deferred, no measured need: `ValueFill` as a canvas-sized `.fill` element; relaxing the erase case.

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

## (39) Three timeline defects, all reported from the device

**Status** — not started. Two of the three causes are now located exactly and are small fixes.

**Left to build**
- [ ] **(a) Pinch-zoom anchors to the wrong frame once scrolled.** `TimelineTrackView` takes
      `location(in: scrollView).x`, which is *already* content-space, then adds `contentOffset.x` and
      later subtracts it as if it were viewport-space. The error is `contentOffset.x · (scale − 1)` —
      zero at frame 0, growing with scroll. The variable's own doc describes the correct quantity. One
      line, plus a test at a non-zero offset.
- [ ] **(b) Dead area below the last row.** `AnimationTimeline` sizes the track host to
      `rowLayout.contentHeight`, so the horizontal scroll view does not exist below the last row, and
      the gridlines get the same extent. One cause, both symptoms.
- [ ] **(c) The timeline freezes.** Needs an ActionRecorder trace from the owner — the reset idiom is
      intact and paired, so the filed suspicion is wrong. **A second suspect to check first:**
      `scrollView.panGestureRecognizer.require(toFail:)` against the row and ruler long-presses, which
      have `minimumPressDuration = 0`. An unresolved one blocks panning *and* taps while playback keeps
      running — the reported symptom set verbatim.

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

## (40) Onion skin z-order, and what Behind should mean

**Status** — **not started. This one is not fixed**, and the owner believed it was.

`CanvasView` fronts the onion-skin view and then fronts every layer host over it, and `updateOnionSkin`
fronts only the *In Front* view. So `.behind` still means "under all artwork, including the layers
below the active one" — exactly the reported defect. No commit since the item was filed touches it.

**One design objection is unanswered and blocks the build**, which is why this sits here rather than
higher: the owner's clarification is that Behind should mean *behind the current layer, not behind
everything* — but at rest, with the compositor engaged, there is no separate active-layer ink for the
skin to sit under. Answer that, then it is a small change.

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
