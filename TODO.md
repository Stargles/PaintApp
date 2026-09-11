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

## (61) The transform layer becomes its own layer type, with five new modes

**Status** — **shipped: stages 0–5** (2026-09-11) of [TRANSFORM_LAYER.md](TRANSFORM_LAYER.md) §8; the
item stays until stage 6 merges. The design document's §2 holds the owner's seventeen rulings
(2026-09-11) and §8 the build order. Stage 0 made the transformation layer its own `LayerKind` with its
own `+` entry and a mode picker; stage 1 made its bar mean "only here" (and an adjustment layer's bar
too), with a notice when Move is tapped outside it; stages 2 and 3 put Parallax and Rotate in the
picker — on a posed folder too — with the item list and the speed field on the panel; stage 4 put
Shake there with its three keyable amounts, a speed and Re-roll; stage 5 put Repeat there (on a layer
only — a folder has no bar to loop within) with a typed loop length pre-filled from where the drawings
beneath end, ink drawn on a repeated frame landing on the frame it repeats, and the repeated frames
ghosted on the timeline. **What stage 5 did not redirect** is listed in TRANSFORM_LAYER.md §5.5: the
Move box, the lasso, text and shape placement, the row thumbnail and the onion skin still read the
playhead's own frame on a layer beneath a Repeat. **Stage 6 depends on nothing.**

- [x] Stage 0 — the kind, the migration, the `+` entry, the panel.
- [x] Stage 1 — the span: pixel-less leaves act inside their bar; Move outside refused with a notice;
      keys past the bar kept and drawn.
- [x] Stage 2 — parallax (6a). - [x] Stage 3 — rotate (6b). - [x] Stage 4 — screen shake (6d).
- [x] Stage 5 — repeat (6c). - [ ] Stage 6 — duplicate offset (6e), as a value-layer effect.

> *"make the transform layer its own layer type instead of attached to the value layer. Additionally,
> add these modes to it: parralax, rotate, repeat, screen shake, duplicate offset."*

**6a — parallax.** > *"Parralax will look at all the child layers or groups directly under it in the
tree (child group counts as one item, stuff in the group do not). When moving, the move layer thing
proportionally applies to these layers, while each layers parralax % is adjustable (slider from 0 to
100, but also can input negative values or higher). Default is proportional, for example with 4 layers,
it is 100%, 75, 50, 25."*

**6b — rotate.** > *"In rotate you input the rotation speed. I also like the functionality of having an
easy interface for rotating in elipses like they are in perspective. I think it could easily be
achieved. Just make the center of rotation the center of the box. Perspective is achieved by if the user
wishes to switch to distort."*

**6c — repeat.** > *"repeat layer: this layer is a bit different from the others. It will simply repeat
the cels under it in a loop until the repeat cel ends."*

**6d — screen shake.** > *"screenshake is self explanatory. Shake x, shake y, rotate shake sliders would
be preferred so that they can be keyframed."* — so the three amounts are channels, which means they are
`TargetChannel` rows (KEYFRAMES §3.6) and the second, third and fourth non-pose channels after opacity.

**6e — duplicate offset.** > *"the idea behind this is that it duplicates whatever is undeneath it, makes
it a solid color, then you resize or offset it and blend it with whatever is underneath it. This is
useful for rim lighting and shadows. It should come with the option to color the rim (areas where
original layer present but not duplicate layer) or the intersection (areas where both bottom and top
layer are present), default to rim. Thus, this layer must have a color option, move box, and blend mode.
Note: this may not belong in the transform layers, it might be better suited for a value layer effect. I
prefer value layer effect but do whatever is cleanest."*

**What to settle in the design, because these are not all the same shape:** 6a, 6b and 6d are *poses* —
they produce a transform per frame, which is what a transformation layer already is. **6c is not a
transform at all** (it re-times the cels beneath it, which is a timeline operation), and **6e is a
compositing operation** (it reads what is below, derives a mask, and blends) — the owner has already
spotted that and prefers it as a value-layer effect. So the honest answer may be *three* homes rather
than one layer type with five modes, and the spec should say which and why rather than forcing them
together. The owner's own instruction is **"do whatever is cleanest"**.

---

## (21) Keyframes — four stages and four gaps

**Status** — partly built. Stages 0, 1, 2, 2b, 3a, 3b, 4, 5, 5a, 5b, 7, 8 and 10 are merged; 6b was
delivered by (29); there is deliberately no stage 9.

A cel or an animation group carries a track of quad poses, ink is posed through the `sqrt(|det|)`
width rule with endpoints bit-exact, a pose channel has a six-curve graph-editor band that is
read-write, a transformation layer is reachable and usable, animation groups can be named, and every
pose key has a node.

**Left to build**
- [x] **Stage 7, live recording and an editable fps — merged, all three surfaces.** Editable fps
      (clamped 1-60, presets, live during playback, no undo step, persisted); §5.1's two-act arming
      per the owner's 2026-09-09 ruling (record turns blue and moves nothing, the take begins when the
      pencil lands); and every surface is recordable — the slider (effect and opacity channels,
      merged 2026-09-07), the Move box (2026-09-10, §5.2, `PoseRecording` — a container pose's four
      corners rather than a slider's one number, thinned by the largest single corner displacement
      rather than a mean), and the canvas (stage 10 below). A raster lift and a lassoed vector float
      refuse the Move box out loud, with the arm surviving. §5's slow-motion multiplier is
      **declined**, by the owner, 2026-09-10 — the editable fps already is the capture multiplier at
      no cost (the playback tick is `1.0 / fps`, so a scene recorded at 12 fps gives exactly twice the
      wall clock to perform in). See KEYFRAMES §5-§5.3.
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
- [ ] **Stage 6, bake to cels**, parked by the owner's 2026-09-06 scheduling ruling (stage 7 before
      stage 6) rather than dropped. It is cheaper than when it was planned — it shares its
      frame-walker with RENDER (29), which shipped, and the video bake merged 2026-09-06 is the same
      shape of operation with a worked pattern to copy. §6.
- [ ] A folder's pose channels are modelled and drawn but **cannot be opened into a graph band**,
      because `graphBandExpansion` is keyed by `layerIndex` throughout. Widening it to a
      `KeyframeTarget` is a stage, not a row — surfaced by the folder-transform work, KEYFRAMES §11.7.
**Spec** KEYFRAMES.md — **§2 is thirty owner rulings and §8 is the build order.** Four rulings
are superseded and kept; the file says which.

---

## (42) Editing the strokes inside a selection, not just their colour

**Status** — not started. **The owner set the order 2026-09-07: (41) first, then this.** (41) has
now left this file whole (PERFORMANCE.md §11.11f, 2026-09-11): a slider tick on a selection is a
*rewrite in place*, and `VectorCanvas.restoreElements(_:changedInk:rewriting:)` bounds one by the
union of where each rewritten element was and where it will be — including a tick that lands before
the previous tick's render has measured anything. MEASURED in Release at 2,000 strokes for a
fifty-stroke selection: the press itself is ~4.5 ms and the render that follows is ~300 ms against
1,090 ms for the whole cel (~60 ms at 200 strokes). So the live requirement is buildable on the seam
as it stands; what a drag still needs is above it — preview-then-commit (the third box) and dropping
a render the next tick has made stale rather than queueing it.

> *"i plan to replace the change color of selection into a better tool where you can also change the
> brush type, size, etc. of the strokes inside the selection. The color changer also shouldnt be the
> current selected color, but instead show the color picker menu defaulting to the current color. all
> changes able to be seen live in the drawing."*

Half of it shipped: the Select panel's **Brush** button re-points a selection at a brush as one undo
step (BRUSH.md §2.10), and `applyBrushToSelection`'s own doc says size, opacity and colour are
deliberately untouched and points back here.

**The live requirement is the load-bearing one, and its prerequisite shipped.** Adjusting a selection
rewrites elements in place, so every tick of a slider is a mid-list edit — a whole-cel re-walk was
~142 ms at the owner's density and 745 ms at 1,000 strokes, and a slider driving one was unusable.
Since (41)'s last box a tick is bounded to the selection's own rectangle; the numbers are in the status
above. **The colour changer today applies the brush's current colour** — the Select panel's Recolour
uses `brushColor` — which is what the picker below replaces.

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
- [x] Decide whether BRUSH_ENGINE_EXTENSIBILITY.md and REFACTOR_BASELINE.md still earn their place.
      **The owner took the 2026-09-07 recommendation, 2026-09-11: keep both.**
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

## (63) Glare and Colour Wheels — two more effects

**Status** — not started, asked 2026-09-11. **Low priority — the owner: *"these are not high priority
so they can be put anywhere in the queue."*** Both are new `Effect` cases; (60)'s six merges of
2026-09-11 (`70f793e` Recolour and `47c2d6a` Computer Screen for a whole case, `5ac52f0` for a field) are
the worked examples, and their two lessons apply unchanged: **`BakeKeyEncoder` must see every new field
or the frame store serves stale pixels**, and a cold-start XCUITest that asserts what is *drawn* is what
found both of that pass's defects.

> *"glare, and color wheels. Glare operates like blender's compositor glare. Different types of glare,
> sort of like bloom, etc. Color wheels are a color grading tool allowing the user to edit the luminance
> saturation and hue and strength (or some other combo, look to common ones in other color grading
> programs). It has 4 of these, one for global, highlights, midtones, and shadows. Try to put some effort
> into making the UI for it nice. 4 color pickers, plus their respective sliders. Also the same pinch to
> merge into ability for these like the HSV so I can bake them to the actual colors."*

- [ ] **Glare.** Blender's compositor Glare node has four types — *Fog Glow* (a wide soft bloom),
      *Streaks* (N directional streaks at an angle, fading), *Ghosts* (lens-flare ghost images mirrored
      about the centre) and *Simple Star* (a four-armed star) — each with a threshold, a mix and a
      size/iterations control. `Effect.bloom` already ships as four passes; Fog Glow is close to it, and
      Streaks and Star are directional blurs of the thresholded pass, so the multi-pass contract
      (`Effect.passes`) is the plumbing. A new `case glare(Glare)` with a `type` picker rather than a
      mode of Bloom, because the parameters differ per type. Both backends, byte-for-byte parity.
- [ ] **Colour wheels.** The four-way corrector every grading program has — DaVinci Resolve's Lift /
      Gamma / Gain / Offset, Premiere Lumetri's Shadows / Midtones / Highlights / Global: each wheel is a
      hue-and-saturation offset (the wheel) with a luminance slider beside it and a strength; the three
      tonal ranges are weighted by luminance with smooth overlaps and Global applies everywhere. A new
      `case colorWheels(…)` with four wheels × (hue angle, saturation amount, luminance, strength) as
      keyable `EffectParameter`s, and a settings bar that draws **four actual wheels** — the owner asked
      for effort on the UI. Oklab for the offsets is consistent with the gradient map's ruling.
- [ ] **Merge-down bakes both** like every other grade — the `hsvShift` precedent, a `MergeBakeLogicTests`
      row each.

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
