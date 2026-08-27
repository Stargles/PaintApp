# Handoff — 2026-08-27 (session 70)

**A Release build of `ce0cfca` is installed on the owner's iPad** (2026-08-27 13:48, first `install` succeeded, no `NWError 54`). Everything below that says "on the device" is genuinely on it — blue ants, Freeform, the two bottom bars, the Scribble veto, the two-image cascade and the Canvas Padding pool. The owner will write their findings into the next session's opening prompt.

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```

**The build on the iPad is `ce0cfca`. Six things to check, in this order — the first is worth more than
the other five together.**

1. **THE INK-LOSS REPRO — do this first.** New vector layer → draw something → **Move** with no
   selection → drag a corner to about **half size** → tap away to commit → now **draw a long stroke
   right across the canvas**. Watch what survives. The prediction is that only the **top-left quadrant**
   of that new stroke is kept and the rest is silently discarded. It is [BUGS.md](BUGS.md)'s newest
   entry, it is **inferred from source and has never been observed**, and the entire case for
   [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) rests on it. Twenty seconds either way. If it does NOT
   reproduce, say so — that is just as valuable and it stops a week of work.
2. **The two-finger freeze — capture it TWICE.** Actions → **Record My Actions**, reproduce, **Stop
   Recording**. Once **from the text keyboard**, once **with the Fill tool selected**. Two long-open
   reports are believed to be one bug (`Tool.paintsOnCanvas` is false for exactly `.fill`,
   `.eyedropper`, `.text`, and the eyedropper is momentary), and the same recording answering the same
   way for both is what proves it. **If it locks while you are looking: does the timeline still animate
   and do the ants still march?** Yes = a dead-input overlay, no = a main-thread hang, and they share
   no fix.
3. **The pencil keyboard.** Actions → **Record My Actions** → Add Text → tap empty canvas **with the
   pencil** → Stop Recording. Keyboard comes up **and** the file contains `scribble.veto` lines = fixed.
   Keyboard stays down **with** veto lines = the veto works and something else suppresses the keyboard.
   **No veto lines at all** = iOS never asked and Scribble was never the mechanism. This one cannot be
   verified on this Mac at all — XCUITest cannot synthesise a pencil.
4. **Freeform.** Lasso a region on a vector layer → **Move** → **Freeform** → drag a corner. Expected:
   the ink thickens by the **area root** (ruling 17 — a 3× stretch in one axis thickens ~1.73×); a
   corner dragged along the box's own **diagonal** gives the same result **Uniform** would; and the bar
   **refuses and says why** if the piece carries an image or text. **A disclosed non-bug**: on a strong
   stretch the ink looks different *while your finger is down* than after you lift. That is the bitmap
   preview against the real bake, it corrects itself on release, and it cannot accumulate.
5. **The two bottom bars.** Effect settings and Add Text now dock at the bottom and the layer rail
   stands down with them — measured at **45% → 85%** of the paper visible. **The known wart**: both
   bars are taller than the Move/Select bars and **cover the timeline transport** while open. That is
   the existing docking convention, not something this change invented, but it is far more visible now.
   Say whether it bothers you.
6. **Blue marching ants while drawing a lasso** — both for lasso *select* and lasso *fill*. This is
   the one you already know was missing on the old build.


Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline.

`main` is at **1748 fast-tier tests (1745 passed, 0 failed, 3 skipped)**, nothing in flight, no
worktrees, no `tmp/*` branches, no simulator clones, pushed to `origin/main`.

**Start by asking me what happened on the iPad.** Four things are blocked on the device and on
nothing else. Each already has its experiment written; none of them wants another pass over the
source. TODO.md's "Waiting on the owner's device" is the same list at length.

1. **The ink-loss repro, and it outranks the other three.** BUGS.md's newest entry says drawing on a
   shrunk vector cel silently throws most of the stroke away, and it is **INFERRED from source and
   has never been seen on a device**. Repro: vector layer → Move with no selection → drag a corner
   to half size → tap away → draw right across the canvas. If only the top-left quadrant's worth
   survives, that is live data loss and the whole LAYER_TRANSFORM.md programme — TODO item (12) —
   is justified. If the stroke survives whole, the argument for that programme has lost its
   load-bearing half and wants re-reading before anyone builds on it. Everything else in the canvas
   geometry programme is downstream of this answer.
2. **The two-finger freeze — one capture, taken twice.** Record with the ActionRecorder while the
   canvas is dead: once from the **text keyboard**, once with **Fill** selected.
   `Tool.paintsOnCanvas` is false for exactly `.fill`, `.eyedropper` and `.text`; the eyedropper is
   momentary, so you have now reported **both non-momentary members of one set**, and the same
   answer in both files collapses this report and BUGS.md's long-open Fill entry into one bug. What
   to read: the `recognizer` lines for `canvas.pan` / `canvas.pinch`. Never leaving `.possible`
   means something is holding them, and the `failureRequirement` lines name who. Reaching `.began`
   with the canvas still dead moves the search out of the recognizers and into `applyTransform`.
3. **The Scribble fix (`ab7f736`) is merged and unconfirmed.** A pencil tap on a text box should now
   raise the keyboard instead of the handwriting strip. XCUITest cannot synthesise a pencil, so
   nothing but a pencil on the glass closes this; the delegate writes a `scribble.veto` line into a
   recording if you want the proof rather than the impression.
4. **Eyes on Freeform (Move stage 3a, shipped this pass).** A corner drag now scales the two axes
   independently, and the ink keeps its round shape at the map's area root. One cost was disclosed
   and accepted rather than hidden: **while your finger is down the preview stretches the ink and
   the bake does not** — one gesture's worth, non-accumulating, the latch dropped at the end of any
   gesture that changed the aspect. Worth knowing whether that reads as a bug before stage 3b is
   designed on top of it. LASSO_MOVE.md §6 lists the other lasso-move behaviours that want a finger
   rather than a test.

**Then the live threads, in the order they constrain each other:**

- **Canvas geometry is one programme, not five asks** — TODO.md's "Canvas geometry, and how a
  coordinate is stored", restructured this pass precisely because reading them apart made each look
  bigger and more independent than it is. **(12)** bakes vector geometry into canvas coordinates,
  which is what narrows **(8)**'s sample field to 16 bits; **(14)** is the answer to the strongest
  objection against (12); **(13)** sets the 16,384 that the field, the canvas maximum and the
  padding cap all share; **(9)**, the Actions-menu resize, is independent of all of them *because*
  the width is fixed. Two specifications are written and current — CANVAS_RESIZE.md and
  LAYER_TRANSFORM.md — and CANVAS_RESIZE.md §6 is five questions you have to answer before (9) can
  be built. (12) wants item 1 above answered first.
- **Move stages 3b, 3c and 5.** 3b is the yellow box-only rotate knob; 3c is placed images holding a
  stretched shape; 5 is Distort on both tiers, consuming the shared `Homography` solver, with the
  ink-deformation toggle defaulting off. LASSO_MOVE.md §0 records what 3a deliberately left out and
  why — including that edge nodes walk straight into `allowedHandles` defaulting to *all cases*.
- **(10) Oklab colour storage and processing** is queued and untouched.

Two questions still owed, unchanged for days — ask when they block work:
  - Save semantics when a project loaded with something unreadable: may saving overwrite the good
    original, refuse, or prompt? (A branch shipped "prompt once, then remember"; confirm it.)
  - Which faces belong in the font picker's favourites strip.
```

---

## State

`main` = `90f5791` plus this close-out commit, pushed to `origin/main`. Clean tree, no worktrees, no
`tmp/*` branches, no simulator clones.

Fast tier verified on the merged tree at `c5cd3b5`: **1748 total / 1745 passed / 0 failed / 3
skipped**, against 1725 at the `6ae201d` base. **The two counts reconcile exactly, which is worth
recording because they usually have to be argued about**: +15 (Freeform) +3 (Scribble) +4
(`ToolLogicTests`) +1 (`PerfBaselineTests`) = +23 runtime, and the four remaining new tests are
XCUITests — two in `CanvasTransformFreezeUITests`, two for the bottom bars — which sit outside the
fast tier's `LogicTests$|CharacterizationTests$|^PerfBaselineTests$` filter. So static `func test`
goes 1842 → **1869**, +27, and 1869 − 1748 is exactly the four. The three commits after `c5cd3b5`
are one UI change whose two tests are XCUITests and two documentation commits, so 1748 still stands
for `main`.

## What landed

**The pass was the last three of the owner's seven device reports, one Move stage, one measured
performance defect, one layout ask, and a day of geometry rulings.** Reports (1), (2), (7) and the
canvas-touch archaeology were session 69's work and are in `git log` before `6ae201d`; what this
pass did with (3) is confirm it rather than fix it.

**(3) closed on both halves, and the expensive experiment was never run** (`da96c0c`). The owner:
*"text seems to show up in distort now."* Session 69's small-box fix — `TextLayout.draw` no longer
blanking when `CTFrameGetLines` returns zero lines, which it does below a threshold, so a box shorter
than one line of its own text was a **total blackout and not a clip** — cured the distorted box as
well. That was the shared-cause branch the elaborate distort experiment existed to test, and fixing
the cheaper, better-understood half first resolved the expensive one. The refuted CALayer
software-path hypothesis stays refuted.

**(4) is iPadOS Scribble, and the app was never at fault** (`ab7f736`). *"Clicking with pencil
however brings up that write to text thing"* names it outright. `handleTextPress` → `focusEditor()`
→ `becomeFirstResponder()` is one path a pencil and a finger both take, exactly as the previous
pass's verification tier insisted; what follows is iOS's, which reads a pencil over an editable
`UITextInput` as handwriting and offers Scribble in the keyboard's place. `TextOverlayView` now adds
a `UIScribbleInteraction` and refuses `shouldBeginAt` everywhere — **the only switch there is**: no
SDK type carries an `isScribbleEnabled`, and iOS's own handwriting support is not an interaction that
can be removed. Two alternatives were rejected with reasons kept in the commit: a seam where a pencil
*tap* keyboards and a pencil *stroke* still writes is not expressible (the callback is asked once,
before either has happened, and is handed a location and nothing else), and
`UITextInputContext.current.pencilInputExpected` is process-wide rather than per-view. Scoped to the
canvas editor alone; the app's six other text fields keep handwriting. **Owed a device
confirmation** — the tests can prove the interaction is installed and adopted, not that iOS asks.

**(6) was reframed, not fixed, and the reframing is the finding** (`6a609ba`). The owner corrected
the one fact the investigation rested on: *"by 'try to resize the canvas' I meant moving the canvas
with two fingers if I recall correctly."* That rules out Canvas Padding, which the pass had opened
on, and rules out a main-thread hang — a synchronous loop ends by itself and freezes everything, not
two-finger movement specifically. What it *does* match is already open in BUGS.md, from the other
tool: `Tool.paintsOnCanvas` is false for exactly `.fill`, `.eyedropper` and `.text`, the eyedropper
is momentary, **so the owner has reported both non-momentary members of one set**, and one capture
answers both. `CanvasManager.selectBrush`'s missing `.text` was proven **unreachable** by reading —
`BrushSettingsPanel` is its only caller, needs `activePanel == .brush`, and
`TopToolbar.selectBrushToolAndTogglePanel` only reaches that panel from `.pen`/`.pencil` having
committed on the way — and was closed structurally anyway, because it was the *third*
hand-maintained exclusion list in that file's history: it is now `Tool.followsBrushPresetSelection`,
exhaustive, no `default:`. Two new nets pass on the simulator, which is the same non-answer three
earlier Fill attempts gave. **They did not pass at first for an instructive reason**: `canvas.host`
is an accessibility element and hides its subtree, so `canvas.textEditor` is real and unreachable,
and both tests passed **having placed no box** — `publishCanvasState` gained a fifth field,
`text:<none|box|editing>`, and the fixture asserts `editing`, because the report is about being in
the keyboard.

**Freeform — Move stage 3a** (`bd3bddd`, ruling in `f44a2e9`). The box's shape is one number,
`ObjectTransformFrame.aspect`, with the area factor left in `transform.scale`, and that split is not
cosmetic: it is what makes *"3:1 stays 3:1 and scales from there"* fall out instead of needing a
rule, and it makes a drag along the box's own diagonal produce the pose Uniform would have, so
**Freeform contains Uniform rather than sitting beside it**. The ink takes `sqrt(|det|)`, the map's
area root — **owner ruling 17**, LASSO_MOVE.md §5 — chosen over the literal *"no scaling"* (said of
Distort, where there is no global scale to read) precisely because the area root has no discontinuity
on the diagonal drag. Ships with **no renderer change and nothing new persisted**. One cost disclosed
and bounded rather than hidden: the latched preview is a bitmap, so a non-uniform transform stretches
ink the bake keeps round; the latch drops at the end of any gesture that changed the aspect, so it is
one gesture's worth and cannot accumulate. **Freeform added no new handle**, which is how it steps
around the trap the stage was warned about (`allowedHandles` defaults to all cases); it pays the tax
on the two defaults it did add, and `testTheWholeLayerBoxIsUnstretchedAndItsDragIsUniform` is what
holds them.

**Canvas Padding's resize, measured for the first time instead of supposed** (`c6b1b35`). Off report
(6)'s hook entirely, and a real cost anyway. **The brief's guess was backwards**:
`regenerateAllThumbnails()` is **17%**, the per-cel buffer walk **83%**, so deferring thumbnails —
the obvious fix, and `startThumbnailBackfill` already exists for it — takes about a sixth off.
**The headline is memory, and it is a code fact rather than a fixture artifact.** The double loop had
no `autoreleasepool` per cel and each cel autoreleases two canvas-sized images, so nothing drained
until the whole loop returned: 32 cels peaked at **3.5 GB** on a document that is 256 MiB at rest,
linear in cel count by construction. At the 300–1000 cels the owner intends, that is not a slow
operation on a 3 GB iPad, **it is a jetsam**. One pool per cel takes the peak to **1.8 GB** and the
wall clock 497 → 390 ms — the time falls too, because a gigabyte of un-drained intermediates is a
gigabyte of page faults. A factor of two, not a different shape: the walk is still linear and still
synchronous on the main actor, which is CANVAS_RESIZE.md stage 1's actual job. **`flipCanvas` has the
identical omission and was deliberately left alone** — the neighbour rather than the thing measured,
nothing pins its behaviour.

**(11) the effect and Add Text panels are bottom bars now** (`e0d5e57`), and **the load-bearing half
is that the layer rail also stands down**. Moving only the 240pt knob panel would have left the
~440pt rail and its options panel over the artwork — the larger half of the owner's 80% — so
`DrawingView` suppresses the rail's *presentation* while a grade is being tuned, exactly as it
already does for the Move bar, with `activePanel` still `.layers` so Back returns the artist to the
same node's options. **MEASURED on iPad Pro 13" / iOS 26.5, portrait, by counting unobstructed paper
pixels: 45% visible before, 85% with the effect bar docked, 83% with the text bar.** Three further
things settled themselves along the way: **no new touch arbitration**, checkable rather than asserted
(`CanvasTouchInputs` reads `panel` through exactly one predicate, `panel == .select`, and neither
`.layers` nor `.text` changes its value here), so ARCHITECTURE_REVIEW.md finding 1 gains no
fifteenth site; **the many-effects question does not exist**, because `Layer.layerEffect` is a single
`Effect?` and the two setters clear each other, so what varies is height and not paging; and
**`MaskTuningSection` did not move, as a decision** — its main control *is* the layer rail's own
rows, so a mask bar at the bottom would dismiss the panel it needs, and its sliders show only on the
*next* soft-brush stroke, so "let me see what the slider is changing" does not reach it. The four
docked surfaces became one column, not four overlays that drew on the same line.

**The geometry rulings, and the sample width was settled three times in one day, each narrower.**
The reasoning matters more than the number and is kept in TODO.md item (8) under a heading that says
so. 24 signed bits (`f44a2e9`) → 18 (`c267322`, from the observation that 16 *unsigned* covers
[0, 16384) exactly and leaves nothing for the negatives that occur today) → **16 bits an axis,
quarter-pixel, origin at the canvas centre** (`35b541c`). **Centring is what buys the sign bit back**,
and it was the owner's own fix in one sentence: 2¹⁶ quarter-pixels is 16,384 pt of span, centred is
±8,192, which is exactly the maximum canvas with the sign included — **5 bytes a sample against
today's 24**. Attached, and each settled rather than recommended:

- **Clamp, do not wrap** (`69d1492`), at the **encode boundary only**. Unclamped a 16-bit field
  wraps, so ink drawn past the edge teleports to the opposite side of the canvas; saturating makes
  the failure local and boring.
- **Centre of the *current* canvas** (`61ed6fa`), overruling the file's own recommendation of a fixed
  address space. An asymmetric crop therefore re-encodes every sample, which is acceptable because it
  is a one-off the artist asks for — and moot today, since asymmetric crop does not exist.
- **One 16,384 budget** (`c267322`): the coordinate field, the canvas maximum and canvas-plus-padding
  are the same number and should be defined once. Padding's cap stops being a flat 512 and becomes
  `min(1024, (16384 − canvas) / k)`; whether `k` is 1 or 2 must be **confirmed against the code**, not
  guessed — wrong either way makes the cap half or double what was asked. That is item (13).
- **(12): a layer should not have a *resolution***. A whole-layer resize bakes objects into canvas
  coordinates instead of scaling the layer; per-object transforms (an image's rectangle, a text
  frame) are untouched. **Transformations still exist** — the owner put the future on record, a
  **transformation layer** applying a transform to the layers below it at render time, for keyframes
  — so what is being removed is a transform baked into *storage semantics*, and (12) must leave that
  seam open. `_transform` is per **cel**, not per layer, so a bake rewrites one drawing and not the
  animation.
- **(14): hold a Move's transform in doubles until an explicit bake** (`61ed6fa`), which arrived
  unprompted as the answer to the reviewer's strongest objection — that a layer transform is the only
  exactly reversible operation in the app. Measurement had already killed the geometry half (100
  shrink-and-regrow cycles drift 6e-11 pt, `stroke.size` bit-exact); two artist-visible residues
  survive, the stamp spacing floor changing a regrown stroke's dab count and the Move box inflating
  because it is recomputed from an alpha scan of moved ink.

**Documentation.** `CANVAS_RESIZE.md` (`87ed588`) — two thirds of "resize the canvas" already exists
under two other names, `setCanvasPadding` and `VectorCanvas.mapping(_:throughSimilarity:)`; the
letterbox rule as one map verified on a scratch file to 1.8e-12 pt rather than asserted; undo as one
step holding no pixels because a snapshot would be 12.8 GiB against a 192 MiB budget.
`LAYER_TRANSFORM.md` (`0164eb3`) — **the census is the argument**: eleven of sixteen entry points map
a canvas-space gesture through `_transform.inverted()` before they can store or test anything, and
three defects fall out of the indirection, one of which is the ink loss now at the top of BUGS.md
(`c919014`). `c5cd3b5` restructured TODO.md 465 → 382 lines — in flight, then waiting on the owner,
then queued — with **29 quoted owner and code passages before and 29 after, checked mechanically**,
and four items ticked that had merged and were still listed open. `85fcbbf` swept the two new specs
for bit widths the same day's rulings had overtaken, correcting figures in place rather than deleting
the analysis, since each diagnosis held up where its number did not — LAYER_TRANSFORM.md §6 had
predicted *"no field width is safe without a saturating clamp"*, which is what the owner then ruled.
It also marked ARCHITECTURE_REVIEW.md finding 1 closed (`CanvasTouchOwner` shipped the day the review
was written and the file carried no marker) and **re-verified findings 2–4 against the tree rather
than trusting HANDOFF.md's summary**: all three still open.

## Still open, blocked on the owner's iPad

The four items at the top of the paste block, and TODO.md's "Waiting on the owner's device" is the
same list at length — it exists because five things were blocked on the same person and the same
device while being scattered across three documents. It also carries a fifth: three behaviour
questions left over from the 2026-08-22 pass that we raised rather than the owner, so nobody has
looked at them on real artwork.

## Carried, deliberately not done

- **Move stages 3b (the box-only rotate knob), 3c (placed images holding a stretched shape) and 5
  (Distort on both tiers)** — LASSO_MOVE.md §0 lists what 3a left out and the reason for each.
- **`flipCanvas` has Canvas Padding's exact `autoreleasepool` omission** and was left alone on
  purpose (`c6b1b35`).
- **The raster Move's undo half** of LASSO_MOVE.md §5 rulings 5 and 10 — a second feature, and TODO's
  "Carried" section says why.
- **`TextFrame.homography` has no validity check on the decode path**; **the `.projective` vector
  flatten re-rasterises per invalidation rather than per commit** (BUGS.md, blocked on `TextRecipe`
  gaining `Hashable`); **PERFORMANCE.md item 14's expensive half**. All unchanged.
- **The stock `ColorPicker` in the text bar** stays the open census question BUGS.md names — a tap is
  not the drag that measurement needs.

## Still true, carried forward

`LASSO_MOVE.md` §5 now carries **seventeen** owner rulings; do not re-litigate any. ADD_TEXT.md
Stage 5 is shipped, its §5.5 now holds the box-size ruling verbatim with the distort clause
corrected, and Stage 6 is the deferred-polish list. `ARCHITECTURE_REVIEW.md` finding 1 is closed and
marked; findings 2–4 (eleven hand-written cache keys, silent save-failure returns, a layer property
living in four hand-kept structs) are open, re-verified, and unruled.

**Two small inconsistencies this close-out found and did not silently rewrite**, both in TODO.md's
item (8): it calls the settled field *"16 bits an axis, **unsigned**"* while BUGS.md,
CANVAS_RESIZE.md and LAYER_TRANSFORM.md all say **signed** and the owner's own quoted words are
*"the first bit represent a plus or minus"* — the same ±8,192 field either way, but the word should
be made to agree once rather than re-argued later. The note at the end of (8) saying the two specs
*"still name 24 and 20 respectively"* was true when written and was overtaken by `85fcbbf` hours
later; it is corrected here to point at the corrections rather than at stale figures.
