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

**A bare item number in a spec or a code comment may name an item that has already left this file.**
That is the merge rule working, not a dangling reference: `git log` and the spec documents are where a
completed number resolves. Two are cited often enough to name here — **(10a)**, the Oklab colour ramps,
and **(38)**, the graph editor's bezier tangent handles and their tap grammar. Do not re-add a finished
item to this file to make a citation resolve.

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

## (39) The timeline freeze — a menu popover eats every drag

**Status** — reproduced and measured; the fix is chosen and unbuilt. (a) the pinch anchor and (b) the
dead area below the last row are fixed and gone from this item.

**While a timeline menu popover is up, every drag on the timeline is swallowed whole** — the track does
not scroll, the ruler does not scrub, and the popover does not dismiss. Only a tap dismisses it.
MEASURED: with the menu up a drag moves the cel block **0.0 pt**; with it gone the same drag moves it
**369 pt**.

`.popover` presents behind a screen-covering `_UIPassthroughGateGestureRecognizer`. `hitTest` still
returns the timeline row — the hierarchy is intact — but `touchesBegan` never fires. That gate is also
what prunes the recogniser set two earlier analyses misread as a detached row view.

**Three diagnoses were wrong before this one**, which is why the evidence doc
[docs/bug-evidence/timeline-freeze-2026-09-06.md](docs/bug-evidence/timeline-freeze-2026-09-06.md) is
worth reading before touching this: a detached view (refuted — the row's own delegate-less recogniser
was missing too), `require(toFail:)` accumulation (refuted — the failure-requirement set deduplicates
and holds weak references), and a cel created past the scene end (driven five ways, never reproduced).
**Nobody had reconstructed the gestures**: almost every "dead" touch in the owner's trace is a swipe,
which is *supposed* to scroll and leaves no model event, and every genuine tap in it worked.

**The decision, 2026-09-06 — stop using `.popover` for these menus rather than punching a hole in it.**
`UIPopoverPresentationController.passthroughViews` is the smaller change and lets the drag through, but
it keeps the menu up while the artist scrubs — and a cel menu names a *specific block*, so scrolling out
from under it leaves the menu pointing at something else. That is a worse bug than the one being fixed.
Reaching the presentation controller from SwiftUI is fragile too, and this way fixes the class rather
than one instance.

**Left to build**
- [ ] Replace the timeline menus with a view anchored **inside the app's own hierarchy** — no
      full-screen presentation, so it captures nothing it does not cover.
- [ ] Dismiss on a tap outside **and** on any gesture starting elsewhere, **letting that gesture
      through**: one drag should dismiss the menu and scroll the track, not cost two.
- [ ] There are four of them; find them all. `MenuInterruptionUITests` reproduces the defect and is the
      regression test.
- [ ] Sweep for the same shape: any other `.popover` over a scrollable surface has this defect.

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

## (41) Mid-list edits and two kinds of undo that still re-stamp the whole cel

**Status** — partly built, and **the owner has accepted where it stands**: *"Honestly it isnt that
bad so it can be marked as done."* What is left is real but is nobody's priority until it bites again.
The general undo/redo work shipped 2026-09-06 (PERFORMANCE.md §11.11a);
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

**Status** — not started, and **its prerequisite got harder rather than nearer**. A slider tick on a
selection is a *rewrite in place*, which is precisely the case (41) established cannot be bounded by
the damage-rectangle mechanism at all — the element keeps its id, so no rectangle from a caller says
which footprint stopped being true. This item needs that solved first, and it is a different idea from
the one that made undo cheap.

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
map, which is this item's own "Oklab still gets built, for interpolation" half. The code calls that
**(10a)** in nine places — `Effect.gradientTable`, `EffectSection`, `ColorMathOklabLogicTests`,
`EffectParityLogicTests` and `tools/oklab_ramp_ab.swift` among them. It is finished, so it left this
file by the merge rule and the citations stand; see the convention above.

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

**Status** — partly done. Named by the owner 2026-09-06:

> *"A lot of things are messy right now, so it may be worth sifting through to prune, organize, and
> just get the repository in a completely clean and up to date state at some point."*

This file was the first slice and is done. The 2026-09-06 audit that produced it found the same rot in
the specs, so the scope is now known rather than guessed — and the four checked boxes below were the
slice that needs no simulator. **Two of those four were already true when the audit wrote them down**,
which is the same failure the audit exists to catch, pointed at itself.

**Left to build**
- [x] **Fix what the specs assert that the code contradicts.** RENDER.md §5 stage 6 said the export
      driver was untested with no XCUITest; `FrameExportSessionLogicTests` is 13 tests and
      `ToolsAndSelectionUITests.testExportIsInTheActionsMenuAndRunsThroughToAShareableFile` drives it,
      so only `ExportSheet` and the device run are still owed. BRUSH.md §12 stage 2 had no DONE marker
      and §9.1's row was the only one in that table not struck through; all five names are absent from
      the app target and the two that survive — `noiseValue`, `supportsCleanCut` — are different
      tenants. **The third known item was already false**: neither `SelectionModels` nor LASSO_MOVE.md
      cites the lifted blocker any more, which is this list going stale in the direction of looking
      unfinished. Sweep the rest of the specs the same way — that is the last checkbox here.
- [ ] **Citation rot.** ~10 of one deleted item's 15 anchors and 5 of another's 11 had drifted, two
      because a file moved directory. Sweep the specs the same way and prefer symbols to line numbers.
- [x] **Dangling references.** Neither was rot. (10a) and (38) are **completed** items whose numbers
      survive in nine and six citations respectively; the convention note at the top of this file says
      so, and item (10)'s text no longer leaves the question open.
- [x] **Two commit shas cited in this repo's docs are not on `main`** (`2fa1725`, `83f7c0d` — pre-rewrite
      orphans). Both are gone: this bullet was the only remaining citation of either. Sweep for others
      when the spec sweep above runs.
- [ ] Decide whether BRUSH_ENGINE_EXTENSIBILITY.md and REFACTOR_BASELINE.md still earn their place.
- [x] The stash stack is empty. It held **two** entries, not the one this bullet recorded: the
      2026-08-14 vector-interpolation snapshot (48 files, 134 commits behind, superseded by interp
      phases 6-7) and a 2026-07-21 pre-rewrite working tree (5 files). Both were labelled cleared with
      the owner's approval and neither had been dropped. The owner ruled to drop both on 2026-09-06;
      their SHAs are `1b8845c` and `2e4e2ff` in that commit's message if either is ever wanted back.
- [ ] Re-run the 2026-09-06 audit itself. It found fourteen false assertions in this file and a dozen
      more across the specs; a session that shipped this much will have introduced its own.

---

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

- **(27) Screen-record the computer as a layer.** Requires (26). The app does have `Transferable` and
  `UTType` now; what is genuinely absent is the *drop* gesture — no `onDrop`, `dropDestination`,
  `NSItemProvider` or `fileImporter` anywhere.
- **(28) Audio.** Its stated blocker is **gone** — `PlaybackClock` is a drift-free wall-clock frame
  counter on the model, delivered by RENDER stage 1, which is exactly the hoist this item said it
  needed. `AVFoundation` is linked (for video), though no audio playback code exists.
- **(30) Video editor.** Its RENDER dependency is met — (29) shipped in full on 2026-09-06.
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
