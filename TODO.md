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
- [x] **A departing fill, image or video forced `.everything`.** Closed 2026-09-10, PERFORMANCE.md
      §11.11d. **The fix this box proposed — measure a fill's path bounds into `paintedBounds` — was
      the wrong table, which is the third time this item's design has been wrong.** `paintedBounds` is
      a *promise that the element has not changed*, so an entry there has to be forgotten at every
      rewrite site and cleared on every `.everything`; none of that is needed, because the geometry
      these kinds are drawn from is stored **on the element** and a restore is handed the element.
      `VectorCanvas.derivedFootprint(of:)` is a pure function of the value, and the box closed by
      deleting a guard rather than by adding a cache. MEASURED in Release: the undo of a fill at 1,000
      strokes **537 → 45 ms**, at 2,000 **1,072 → 90 ms**, 9.8–12.1× across the range — larger than the
      eraser's 1.8–6.7× because a fill's rectangle does not grow with density the way a cut's does.
- [ ] **An `autoSize` text object still pays the cel, in both directions**, and it is the one of the
      four left on `.everything` on purpose. All three arms of `draw(text:into:quality:)` pass
      `clip: !frame.autoSize` into a real `CGContext.clip`, so a **sized** box bounds its own glyphs by
      proof — but a pristine box was grown by `CTFramesetterSuggestFrameSizeWithConstraints`, which is
      a *typographic* extent, and glyph ink runs past it by whatever a font's italic overhang, swashes
      or accents care to. Nothing measures a text object and a departure has no escape check behind it,
      so a rectangle that missed those pixels would be a permanent ghost. Closing it wants a
      **measurement** of glyph ink — `CTLineGetImageBounds` per line, which is what CoreGraphics
      actually rasterizes — not a bound derived from the box. `TextMeasure.inkBounds` is the obvious
      place for it and is deliberately *not* used here: it builds a superset out of line boxes
      (ascent + descent over typographic width), which is right in practice and is a claim about font
      files rather than about this code.
- [ ] **A rewrite in place cannot be bounded by this mechanism at all.** Recolour, Apply Brush, a text
      re-edit, video crop and speed, motion-group retags, `keyPoseRestoringRest`, and **every
      lasso-move nudge** — `drawn(_:through:widthScale:)` preserves an element's id by explicit design.
      Only Recolour, Apply Brush and the text re-edit actually declare `.rewritesInPlace` (through
      `registerVectorElementsUndo`); video crop and speed, motion-group retags,
      `keyPoseRestoringRest` and the lasso-move nudge still call `bumpVersion()` directly in their own
      undo closures and were never touched by this pass. Either way it is the honest state and not a
      fix. Bounding them needs a different idea: an id whose *content* changed needs its old footprint
      forgotten and its new one bounded, and no rectangle from a caller supplies that.
- [ ] **The four call sites with the tightest rectangles are exactly the ones whose departures are not
      strokes**, which is why the "measure what was replaced" recipe never reached them. **Three
      quarters of this is answered by §11.11d** — a fill, a placed image and a video no longer need
      that recipe, because they carry their own extent. What is left of it is the `autoSize` text box
      above, which is the row this observation still describes.

**Blocks** (42). **Spec** PERFORMANCE.md §11, §11.10, §11.11, §11.11a, §11.11d.

---

## (21) Keyframes — four stages and four gaps

**Status** — partly built. Stages 0, 1, 2, 2b, 3a, 3b, 4, 5, 5a, 5b, 8 and 10 are merged, and 7 is
merged except its Move-box surface; 6b was delivered by (29); there is deliberately no stage 9.

A cel or an animation group carries a track of quad poses, ink is posed through the `sqrt(|det|)`
width rule with endpoints bit-exact, a pose channel has a six-curve graph-editor band that is
read-write, a transformation layer is reachable and usable, animation groups can be named, and every
pose key has a node.

**Left to build**
- [ ] **Stage 7 is half shipped, and the half that is left needs the owner.** Merged 2026-09-07: the
      editable fps (clamped 1-60, presets, live during playback, no undo step, persisted) and the live
      take on **the slider surface** — captured at the control's own rate, resampled at `fps`,
      deviation-simplified, landing as one curve and one undo step, with five refusals and two
      auto-stop paths. 35 mutations, one survivor found and fixed.
      **§5 specifies *"one mechanism, two surfaces: a slider, and the Move box"*, and the Move-box
      surface is not built** — `ValueRecording` is scalar-only while a transform channel stores
      `PoseQuad` keys, so resampling and tolerance both need definitions nobody has ruled on. §5's
      *"slow motion is a capture-speed multiplier on the record control"* is also unbuilt. **Both are
      owner-facing design and want a conversation before anyone builds them.**
      **The owner has now ruled on that, and it reverses what this item called "the design".** This
      row used to end *"at 24 fps a new document's take is over before a person can react, because §5
      runs a take over the scene you have. That is the design."* It is not. 2026-09-09:

      > *"Right now I dont like where the record button is, and its behavior. The behavior should be
      > this: You open up graph editor and it displays the record button option. You press the record
      > button and it turns blue, but nothing happens. Then, you go and put your pencil on a slider or
      > move box, and playback automatically starts, recording the movement then putting it on the
      > graph. Currently when you press record it instantly plays the playback, giving you no time to
      > adjust the sliders or move box."*

      **That ruling is built and merged (2026-09-09), and only the Move-box surface is left of stage 7.**
      Arming and starting are two acts: the record button lives beside the graph editor's own button and
      is shown only while the band is open, pressing it turns it blue and moves nothing at all, and the
      take begins when the pencil lands on a slider — with playback starting at that instant. An arm ends
      in exactly three ways (a take begins, the button is pressed again, the graph editor closes) and
      survives everything else, so an artist can arm and then walk two menus to the slider. Arming costs
      no undo step and opens no gesture bracket. A landing on a *stepped* slider is refused out loud and
      keeps the arm. See KEYFRAMES §5.1, which also states the four things a new recordable surface has
      to implement — the trigger is `CanvasManager.beginArmedTake`, built once so that the Move box and
      stage 10's canvas plug in without rework.
      **What is left is the Move box itself, and it no longer waits on the owner.** Put to them on
      2026-09-10 as "resampling and tolerance for a quad" they answered *"i have no idea what the
      question is"* — correctly, because that sentence is entirely ours. In artist terms it is only
      this: recording a slider captures **one number** over time, and recording the Move box captures
      **a shape** — four corners. Both then get thinned, so a straight drag lands as two keyframes
      rather than sixty. The open part was never a preference; it was *"how much corner movement counts
      as a change worth keeping"*, which is a **number a person can only judge by feel, after they can
      see it**. So: build it with the slider's own thinning rule applied to the largest corner
      movement, in canvas points, and let the owner tune it once a recorded drag exists to look at —
      the same reasoning as [[render the cost, don't describe it]]. Do not hold the surface for a
      ruling that cannot usefully be given in advance.
      §5's *"slow motion is a capture-speed multiplier on the record control"* is also still unbuilt.
- [x] **Stage 10, the timing recorder (§7) — built and merged 2026-09-10.** The owner gave the full
      brief on 2026-09-09 and it is larger than §7's laser pointer.

      > *"The user primes the recorder and selects the brush. Then as they put their pen on canvas, the
      > recorder starts and the user can draw while recording. This is just useful for timing. The
      > stroke will go on the cel of the layer that is active. The start and end of the stroke in the
      > cel will be where the stroke started and ended while that cel was active."*

      So one continuous gesture is **cut at cel boundaries by when it was drawn**, while playback runs
      under the pen: each cel keeps the arc the artist drew during it. That is roughing timing out in
      real ink, and it is a different thing from §7's laser-pointer trail — §7 is the *tail*, this is
      the ink.

      **The owner named the fork themselves and left the call to us**, with a hard ceiling on cost:
      > *"it is possible that this feature by itself (with the brush) may require extensive changes to
      > the engine. I do not want that. It is meant to be a relatively light feature. In the case that
      > doing the stroke baking thing costs too much, then just do this alternative workflow: The user
      > primes the record tool, then lays their pen down on the canvas (no need to select brush tool).
      > It will then do basically the same record stroke as before, but this time you can make it a
      > separate simple and specialized stroke engine, as part of the record tool instead of branching
      > off the actual brushstroke tool. Might be better or worse for clean architecture. Your call."*

      **A — the real brush, split live at each cel change.** The artist's own brush, so the ink is ink.
      The cut is a mid-gesture commit: close the stroke on the outgoing cel, open one on the incoming
      cel at the same point, carrying pressure and velocity so the seam does not show. Note this lands
      squarely in the scratch/base overlay lifecycle — the same code the disappearing-strokes fix is in
      — so the two must not be built at once.
      **B — a specialised stroke engine inside the record tool.** No brush selection, no reach into the
      shipped drawing path, and it is what §7 already specifies (a trail from `StrokeGeometry
      .stampRadius(forPressure:brush:size:)` plus the capsule chain, with decay-since-touch-down
      standing in for pressure). Cheap and contained, at the cost of a second thing that draws ink.

      **Built 2026-09-10 as A, and the measurement that chose it refuted the fork's own premise.**
      Both arms assumed the cut has to be a *mid-gesture commit*; it does not. The gesture already
      accumulates one knot stream and `commitVectorStroke` already walks **several runs** of it —
      that is what the selection clip does — so the cut is a **partition** recorded as indices while
      the pen moves and spent once at pen-up, with the target canvas varying per run. `TimingStrokeCut`
      is that partition, 97 lines and pure. Nothing in the stroke lifecycle moved: the single-cel path
      below the new early branch is byte-for-byte what it was. B would have had to invent an ink
      representation or reuse `VectorStroke`, at which point it is A with a worse brush.
      **What A did cost, and B would have cost identically, is the display**: playback engages the
      compositor unconditionally (`sandwichEngagesOnCanvas`'s `isPlaying` clause) and blanking is a
      `layer.mask` over the whole host, so the live scratch was inside it — an artist drawing during a
      take would have seen no mark at all. The trail is drawn by a sibling of the hosts now.
      **Two premises in this row were wrong and are worth recording**: "nothing refuses a touch while
      `isPlaying`" is true of *refusal* and false of the outcome — `canvasInteractionBegan` **stops
      playback** on the first touch, and its own comment names the cel-crossing hazard this feature
      turns into the feature; and "this lands squarely in the scratch/base overlay lifecycle, so the
      two must not be built at once" is true of a mid-gesture commit and does not apply to a partition.
      A frame with no block gets one, by the rule that already ships for touching a blank frame. One
      gesture is one undo press, blocks included.
- [ ] **A folder's keyframes have no entry point, and that is now two channel kinds deep.** Folder
      opacity animates and renders correctly (merged 2026-09-10), and so have a folder's *grade*
      channels since stage 2b — but **Add Keyframe** lives only on a layer row's cel menu and the
      timeline has no folder rows, so an artist cannot place the first key on a folder at all. Model
      correct, feature unreachable, which is the exact shape of the three defects the owner found in a
      minute on 2026-09-03. **Asked on 2026-09-10, the owner ruled *"You decide how to do it"*, so this
      is a build item and not a question.** The obvious shape, not yet weighed against the code: a
      folder already has an options menu, and a layer's Add Keyframe lives on its cel menu — so the
      cheapest honest answer is probably the folder's own options menu, keyed at the playhead. Weigh
      that against giving folders timeline rows, which is a much larger change and would also answer
      several other things.
- [ ] **Stage 6, bake to cels**, parked by that same ruling rather than dropped. It is cheaper than
      when it was planned — it shares its frame-walker with RENDER (29), which shipped, and the video
      bake merged 2026-09-06 is the same shape of operation with a worked pattern to copy. §6.
- [ ] A folder's pose channels are modelled and drawn but **cannot be opened into a graph band**,
      because `graphBandExpansion` is keyed by `layerIndex` throughout. Widening it to a
      `KeyframeTarget` is a stage, not a row — surfaced by the folder-transform work, KEYFRAMES §11.7.
- [ ] **Animation-group membership editing — ruled 2026-09-10 and now buildable in full.** The owner,
      asked in artist terms whether a drawing moved between animated groups should stay where it looks
      on screen or snap to the new group's motion:

      > *"stay where it looks like on screen for animation groups. I'm not sure how you plan to
      > implement putting one thing out of one animation and in to another animation group but I'll let
      > you take the wheel. Along with that, the ability to add new selections to an animation group
      > (not only from another animation group) and remove selections from groups will be useful. I
      > will let you take it first, then notify you if there is any UX changes I want in the future."*

      **So it is three operations, not one**, and the third is the one the item used to be about:
      **add** a selection to a group, **remove** a selection from a group, and **move** a selection from
      one group to another. All three obey the same rule.

      **What "stays where it looks on screen" has to mean, stated before anyone builds it.** Read
      literally as *every* frame it is self-defeating: an element that looks identical at every frame
      after joining a group has not joined it in any observable sense, and it is not expressible anyway
      — only groups carry tracks, so per-frame compensation would need a per-element track that does
      not exist. The reading that is both implementable and useful is the one re-parenting has in every
      animation tool: **appearance is preserved at the frame the artist is on, and from there the
      element follows its new group.** Concretely — on **add** and on **move**, the element's stored
      geometry is rewritten so that the new group's pose *at the current frame* reproduces exactly
      where it was; on **remove**, the departing group's pose at the current frame is baked into the
      element so it stands still where it stood. **Say this back to the owner in those words when it
      ships**, because it is an interpretation of their sentence and not a quote of it, and they asked
      to be shown first and to give UX corrections after.

      **What it collides with, and must not quietly break.** §2.29 (shipped 2026-09-03) refuses a Move
      that catches *part* of a group and says so — that refusal is about a *Move*, not about membership,
      and must survive. §2.29 also rules that splitting one animated group into two is *"a different
      feature"*; adding and removing are not that, but a remove that empties a group, and an add that
      makes a group's track meaningless, are both edges to decide and state. Every key on both tracks
      changes meaning, so **one membership edit is one undo step** and the §2.28 union must still be
      computed by the one accessor rather than patched.
**Spec** KEYFRAMES.md — **§2 is thirty owner rulings and §8 is the build order.** Four rulings
are superseded and kept; the file says which.

---

## (42) Editing the strokes inside a selection, not just their colour

**Status** — not started. **The owner set the order 2026-09-07: (41) first, then this.** Its
prerequisite got harder rather than nearer. A slider tick on a
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

## (22) Select multiple cels at once

**Status** — not started, and **deprioritised by the owner 2026-09-07**. The menu row exists and is `.disabled(true)` with an empty action; no
cel-selection state exists. The keyframe half of the same idea is real and shipping.

---

## (10) Linear light as an option on the blend mode

**Status** — not started, and **deprioritised by the owner**.

No colour-pipeline setting, no sRGB/linear enum, no transfer LUT, no `Composite.metal` change.

**One adjacent strand did ship**: `ColorMath`'s sRGB↔linear and Oklab conversions feed the gradient
map, which is this item's own "Oklab still gets built, for interpolation" half. The code calls that
**(10a)** in eight places, corrected 2026-09-07 from a stale count of nine — `Effect.gradientTable`,
`EffectSection`, `ColorMathOklabLogicTests`, `EffectParityLogicTests` and `tools/oklab_ramp_ab.swift`
among them. It is finished, so it left this file by the merge rule and the citations stand; see the
convention above.

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
to exercise tilt, which no test here can reach. BRUSH.md §13 has **nine** genuinely open questions
(recounted 2026-09-07 — the sixteen bullets split seven answered/closed, nine still open; the "eight"
recorded here was a miscount on the day this line was written, not later drift). Three of the nine
were offered on 2026-09-06 and declined; which three is not recorded here and could not be verified
against a transcript this audit does not have.

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

**A quarantine audit on 2026-09-07 (branch `tmp/prune`, five commits) checked every claim the four
already-checked boxes and the branch's own commits made, then rebased onto `origin/main` and
re-checked again.** Nothing in the branch was found false; two small pre-existing numeric errors were
found and corrected in passing (this file's own (10)-and-(37) counts, above and below) along with nine
drifted `FILE:LINE` citations in ARCHITECTURE_REVIEW.md's finding 3, two more in its finding 4, and
finding 4's own miscounted "twelve of sixteen" (it is twelve of seventeen). The
rebase carried real content: `origin/main` had independently shipped `LayerFolder.transform`'s
options-panel entry and pose-node delete/tap-to-add (both were still listed as unbuilt in this
branch's stale copy of item (21)) and had reopened and rewritten item (31) around the owner's own iPad
having 3 GB of RAM. **As the queue stood on 2026-09-07 during that audit** — eight items, (53) through
(37) — every one was re-verified line by line against the rebased tree and every remaining status line
and "Left to build" bullet checked out. **That list is history, not the current queue**: (53), (31) and
(54) have shipped and left since, and (36) was fast-tracked in.

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
      **One more is known:** VIDEO.md §2.10 closes by saying a baked video's images *"split like any
      other ink, because by then it is ink"*, and they do not — `splitForLassoMove` refuses `.image`
      exactly as it refuses `.video`, by centre and whole. Stage 8 recorded it in VIDEO.md §9 with the
      two ways to make the sentence true rather than picking one.
      **Sweep completed, 2026-09-10** (branch `tmp/specs`): re-checked VIDEO.md §2.10/§9 against
      current `splitForLassoMove` — still true, left alone. Six new contradictions found and fixed
      across the rest of the corpus, all in the shape this box already names — a spec describing a
      refusal, a field or a wiring gap that has since shipped or moved: **KEYFRAMES.md** §4.4's "Two
      placed-object refusals ride along" (the refusal was never built; `VectorImageElement` got a
      stored shape instead, per its own "What the model pass found" item 3 — the original passage
      hadn't been updated to match) and §4.1's `renderTree` census (describes a pre-stage-0 "computed
      var"; the function has taken `atFrame:` since `654f863`); **LASSO_MOVE.md**'s `Kind` rawValues
      list (missing the `video` case added since), two `DabLattice.seedID` references (the field moved
      to `VectorStroke.seed`/`arcOffset` under BRUSH.md §4), `toggleMove()`'s derived-cel refusal (moved
      to `CanvasManager.activeVectorMoveTarget`) and `updateFloatingTransform` (renamed
      `updateFloatingPose`) — the last two reused in **VECTOR_INTERPOLATION.md** item 26, which cited
      the same stale `toggleMove` location, and item 34, whose "nothing sets" claim is now only half
      true (`visibilityThreshold` is set, by local edits, for an unrelated reason); and **ADD_TEXT.md**'s
      "`ActionsMenu` gains the ability to enter a mode" section, describing `activePanel` as unthreaded
      when Stage 1 (marked done four lines later in the same file) already threads it. Full table in
      the session report.
- [x] **Citation rot.** ~10 of one deleted item's 15 anchors and 5 of another's 11 had drifted, two
      because a file moved directory. Sweep the specs the same way and prefer symbols to line numbers.
      **Partial pass, 2026-09-07**: swept ARCHITECTURE_REVIEW.md's finding 3, the section this branch's
      own `dc3834d` re-affirmed as "kept as written... still accurate" — the prose was accurate but nine
      of its ten `FILE:LINE`/name anchors had drifted (`ProjectStore.swift:507→587` and three
      failure-return lines, `:751→948`, `:799→1000`, `ProjectManifest.swift:376→490`,
      `ProjectBackupManager.swift:471→477`, and `BUGS.md:131` replaced with the entry's own heading —
      only `ProjectBackupManager.swift:460` was already right), now fixed. Finding 4's two
      (`ProjectStore.swift:160→185`, `ProjectManifest.swift:242→304`) were dropped rather than
      repaired, since the symbol is already named in the same sentence — "prefer symbols to line
      numbers" applied rather than just restated.
      **Rest of the corpus swept 2026-09-10** (branch `tmp/specs`). RENDER.md, KEYFRAMES.md,
      LASSO_MOVE.md, CANVAS_RESIZE.md, LAYER_TRANSFORM.md and EFFECT_BACKDROP.md, ADD_TEXT.md each carry
      `FILE:LINE` anchors — 314 counted across the eight (VIDEO.md included); VECTOR_INTERPOLATION.md,
      LASSO_FILL.md and BRUSH.md cite files and symbols with no line numbers, so the sweep there was a
      symbol-existence check rather than a line check. **~130 of the 314 numbered anchors were flagged
      as drifted by distance-from-declaration; on manual check the large majority were real rot** (a
      handful were false positives — a citation into a doc comment a few lines above a declaration my
      checker matched instead) **and were fixed by dropping the line number where the sentence already
      names the symbol, or correcting it where it did not**, per the rule above. The remaining ~184
      anchors were spot-checked rather than each individually re-derived, given the corpus's size;
      several more rotted ones turned up that way and were fixed (listed with the contradictions
      above and in the session report). Two clusters were confirmed rotted but left unresolved because
      the described code has been refactored away rather than moved — RENDER.md §3.1's pre-stage-2
      pen-up table (several citations land on unrelated doc comments the surrounding files' growth has
      shifted past) and LAYER_TRANSFORM.md's `render()`/`_transform` bitmap-application claim (the
      literal `ctx.concatenate(_transform)` this cites no longer exists as such) — both noted in place
      rather than guessed at.
- [x] **Dangling references.** Neither was rot. (10a) and (38) are **completed** items whose numbers
      survive in several citations each — (10a) in eight, corrected 2026-09-07 from the nine recorded
      here; (38)'s six was not re-verified, since a bare "(38)" also matches unrelated numeric literals
      and re-counting it needs more care than this pass gave it. The convention note at the top of this
      file says so, and item (10)'s text no longer leaves the question open.
- [x] **Two commit shas cited in this repo's docs are not on `main`** (`2fa1725`, `83f7c0d` — pre-rewrite
      orphans). Both are gone: this bullet was the only remaining citation of either. Sweep for others
      when the spec sweep above runs.
- [ ] Decide whether BRUSH_ENGINE_EXTENSIBILITY.md and REFACTOR_BASELINE.md still earn their place.
      **Recommendation, 2026-09-07 (not acted on — the owner's call): keep both.**
      BRUSH_ENGINE_EXTENSIBILITY.md is not orphaned — BRUSH.md's own header calls it "still accurate
      about the seams" and says its ordering "survives into §12", §11 says its argument is "not to be
      lost", and it is cited live from ADD_TEXT.md, KEYFRAMES.md, CANVAS_RESIZE.md and one production
      doc comment (`TextObject.swift`). Its own stale parts (the pre-§12 "Order, if it is ever
      scheduled") are already self-marked DONE or deferred to BRUSH.md §12, which is the existing
      convention for a survey a spec has overtaken — deleting it would orphan seven live citations for
      no gain. REFACTOR_BASELINE.md is also live-cited three times (`ARCHITECTURE_REVIEW.md`,
      `TimelineAndUndoUITests.swift`, `PerfBaselineTests.swift`) for specific numbers, so it should not
      simply go — but unlike the brush document nothing has re-affirmed its figures recently, its
      "Full suite, wall clock" row (541-1231s) is from long before the thousands-of-tests, 18-36-minute
      runs CLAUDE.md now tracks, and its "Known remaining costs" §1 cites an `invalidate()` API that no
      longer appears in `StrokeSpatialIndex.swift` under that name. It wants a re-measurement or a fold
      into PERFORMANCE.md as a dated historical baseline, not deletion — flagged for the PERFORMANCE.md
      agent rather than acted on here.
- [x] The stash stack is empty. It held **two** entries, not the one this bullet recorded: the
      2026-08-14 vector-interpolation snapshot (48 files, 134 commits behind, superseded by interp
      phases 6-7) and a 2026-07-21 pre-rewrite working tree (5 files). Both were labelled cleared with
      the owner's approval and neither had been dropped. The owner ruled to drop both on 2026-09-06;
      their SHAs are `1b8845c` and `2e4e2ff` in that commit's message if either is ever wanted back.
- [ ] Re-run the 2026-09-06 audit itself. It found fourteen false assertions in this file and a dozen
      more across the specs; a session that shipped this much will have introduced its own.
      **Partial re-run, 2026-09-07**: this file's own numbered items — all eight live at the time
      ((53),(41),(21),(31),(42),(22),(10),(37)) — were checked line by line against the rebased tree.
      One had already been fixed and left the file entirely ((53)); the rest needed no correction
      except the two counts fixed above in (10) and (37), both pre-existing and both off by exactly
      one. The specs were not swept beyond ARCHITECTURE_REVIEW.md's finding 3 (see the citation-rot
      bullet above) — README.md, KEYFRAMES.md's header and §9, and BRUSH.md's two cited claims that
      this branch's own commits touch or introduce were separately checked against the code and held
      up. A full sweep of every remaining spec is still owed.

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
---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.
