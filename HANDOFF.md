# Handoff — 2026-08-21

**The performance programme is confirmed on hardware, not just the simulator.** The owner ran a
Release build of `38e22c6` on their iPad 9 and answered all seven checks this session's device pass
asked for. Every one came back clean: *"17fps is gone, good job. 4k screen displays full 60fps when
painting"* — the headline result of the whole programme — plus *"leaving the gallery is instant,"*
*"no issues"* opening a project, *"lasso fill works,"* *"cross eraser works as intended, very nice,"*
*"text handles are good,"* and *"not much of a problem"* for Add Text with the keyboard up. All four
of the owner's originally reported bugs are now confirmed fixed on hardware, not only headlessly.
`main` is at **1478 fast-tier tests passing, 0 failing, 3 skipped** (1481 total), up from 1423 at the
start of the day. No worktrees, no `tmp/*` branches, no simulator debris.

**One item moved anyway.** [PERFORMANCE.md](PERFORMANCE.md) item 14 (raster-cel residency) was
re-opened by the owner's stated intent for a real document, then re-scoped by reading their actual
iPad container directly — the largest of 25 real packages has 4 cels, so the alarm the intent raised
describes a document that has never existed. The expensive fix stays declined; a cheap, correctness-
clean half is newly justified and queued (see below).

**And four new owner asks arrived after the device pass**, about the lasso and move tools on a
vector layer — see "What is worth doing next."

## What shipped

**Confirmed on the owner's iPad, Release build `38e22c6`, 2026-08-21**

| check | the owner's words |
|---|---|
| Drawing on the 4096² stress canvas | *"17fps is gone, good job. 4k screen displays full 60fps when painting."* |
| Leaving to the gallery | *"leaving the gallery is instant."* |
| Opening a project | *"no issues."* |
| The lasso (gap-in-outline and loop-outside-shape scenes) | *"lasso fill works."* |
| The cross eraser | *"cross eraser works as intended, very nice."* |
| Add Text with the keyboard up | *"not much of a problem, text seems to be working properly enough."* |
| The text transform handles (Stage 4) | *"text handles are good."* |

This closes the standing debt every item in `PERFORMANCE.md` had carried since 2026-08-20 — every
after-figure in that document was a Debug simulator, where the shape of a result transfers and the
multiplier does not. The multiplier is now known: it transferred. Full per-check writeups, with the
figures each confirms, are in `PERFORMANCE.md` items 9, 11, 13 and 15, and in `ADD_TEXT.md` §3.

**Branches merged today**

| what | the fix, in one line |
|---|---|
| A vector layer's transform was not undoable | Bracket hangs off `CanvasManager.isVectorTransforming`'s own `didSet`, not the gesture callback that fires on every touch-move, so it cannot leak through the two paths that clear the flag without a gesture ending (`b100d65`). |
| Add Text Stage 4 | Nine grips in a non-warped sibling view, every dimension `screenPoints / canvasScale`; `.affine` gains rotation and independent-axis scale; Stage 1's canvas-edge growth cap is gone (`442dc16` and follow-ups). |
| Save semantics on a damaged project | Ruled: **prompt once, then remember.** An artist save on an unanswered damaged document asks and writes nothing; an automatic save never blocks and writes into version history instead (`cfdddb5`). |

**Two owner rulings, closing standing questions**

1. **192 MiB of undo (~12 whole-cel operations) is right, and trimming to half on a memory warning is
   right.** Both are decisions now, not guesses wearing constants' clothes — `PERFORMANCE.md` item 13.
2. **The font favourites strip ships with sensible defaults the owner can edit later.** Already
   recorded in `ADD_TEXT.md` §5 item 5 by the Stage 4 branch.

## What just got re-scoped: PERFORMANCE.md item 14

**The owner's stated intent for a real document**: 100–200 frames on 3–5 drawn layers, 300–1000 drawn
cels — OWNER-STATED, and an intention about the work they mean to do, not a count of cels in a package
that exists. **A direct read of the owner's iPad container over `devicectl` found the largest of 25
real packages — live, `Backups`, `Trash` — has 4 cels; both live projects have 1.** The app has never
once been asked to hold more than 4. This is forward work, not a fire.

The expensive half (evict-and-rehydrate the primary pixel data) **stays declined**: three
independently-scoped designs for it were each traced by adversarial review to a silent-artwork-loss
path in code that already exists (a `flipCanvas`/`setCanvasPadding` path that would blank the whole
document under a windowed scheme; an undo-restore path that would let a write-back LRU serve stale
pixels). None of the three is justified even against the document the owner intends.

**A cheap half is newly justified and queued**: stop writing and loading a raster tier for cels that
carry no raster content. `ProjectStore.writeCel` writes `cel.rasterImage` for every cel unconditionally
because `RasterLayerTexture.renderToUIImage()` has a non-optional return and mints a transparent
canvas-sized image rather than returning nil. Confirmed against the owner's own package —
`Untitled.paintproj`'s one **vector** cel carries a `_raster.png` of 161 KB it has no use for. It is
correctness-clean and does not need item 9(c)'s thumbnail-persistence precondition the expensive half
does. Full mechanism, citations and three corrected figures (787 MB → 6.558 MiB, MiB not MB; the
measured number is the *stamping* path, the *load* path is a never-measured 8.0 MiB; item 13's 656 MiB
double-counts headroom that isn't gone) are in `PERFORMANCE.md` item 14.

Three things are still unmeasured and listed there rather than assumed: the real pre-jetsam ceiling on
the iPad 9 (the 1.4 GB figure traces to the word "perhaps" in a doc comment), the residency slope on
the load path, and whether iOS's memory compressor absorbs cold cel residency — the one term that
could move the whole answer by a factor rather than a percentage.

## What is worth doing next

**Four new owner asks, given 2026-08-21 after the device pass — about the lasso and move tools on a
vector layer.** Full text and citations in `TODO.md`'s Queued section; in brief:

1. **A lasso selection should move only the selected part, not the whole drawing.** The owner's own
   ruling: move is currently correct for the whole-layer case and should stay that way; a lassoed move
   should split `VectorStroke` geometry at the selection boundary and cut a region out of a fill — the
   vector eraser's split/punch shape, pointed at a new gesture. **Text is explicitly excepted**: moving
   it whole is fine, since splitting a `TextFrame` mid-glyph is not sane.
2. **The lasso toolbar icon should stay highlighted while another tool is briefly in use.** A toolbar
   state question, not a canvas one.
3. **Move is extremely slow on a vector layer — down to ~5 fps, per the owner.**
4. **The move tool's handles don't hold a constant screen size across zoom and don't respond to
   touch.** This is the exact bug `ADD_TEXT.md` §1 predicted and told the text-tool build not to copy
   (`TransformHandleView`'s fixed `24×24` lives inside the transformed `container`). **Add Text Stage 4
   shipped the fix's pattern today** — `TextTransformOverlayView`, a non-warped sibling view with every
   dimension pushed from the coordinator. Port `ObjectTransformOverlayView` onto that pattern rather
   than designing a new one; it is likely also the fix for (3), and `BUGS.md`'s cleanup note on the
   duplicated transform-overlay code should converge on it too.

**Then, in rough order of value:**

5. **`PERFORMANCE.md` item 14's cheap half** — stop writing/loading a raster tier for cels with no
   raster content. See above; it is correctness-clean and ready to scope.
6. **Add Text Stage 5** — the projective distort. `ADD_TEXT.md` §3/§4 rule 9 requires a Release build
   on the iPad 9 before merge, same as every warp-touching stage.
7. **The Mode 3 eraser's ~95 ms per cutting sample** — measured, deliberately unfixed until the eraser
   rewrite settles. Compounds with the new footprint eraser, which cuts every stroke it covers rather
   than one.

## What the owner still owes a ruling on

**Carried, still unruled**

- **A double-traced ellipse detects as a rectangle.** Pre-existing, verified, not a regression.
- **The smart oval has no arc-end handles.**
- **Should a lasso leak get its own signal?** The collar tint cannot show one — a leak still paints the
  outline, so it is not an empty result and the signal never fires.
- **A superseded lasso no longer says "nothing enclosed."** Draw a loop enclosing nothing, then fill
  elsewhere, and you get silence rather than a banner about the loop you abandoned.
- **With the text tool selected, tapping an existing label always edits it** and never places a new box
  beside it — Illustrator's behaviour, chosen deliberately, but you cannot start a second label
  overlapping an existing one without moving the first.
- **The toolbar colour swatch changes meaning while a text session is live** — it edits the text's
  colour, not the brush's.

## Five things this pass learned the hard way

- **A document can carry an intention and a measurement that disagree, and both are worth recording.**
  The owner's "a real document is 300–1000 cels" is real and forward-looking; the device's "the largest
  package on it has 4" is also real and describes today. Neither should overwrite the other — item 14
  needed both to reach the right scope.
- **Reading the device directly settled in thirty seconds what an 11-agent scoping pass could not settle
  from code.** `devicectl` pulling the owner's actual package and manifest is what refuted the ~150-cel
  inference item 15 had stood on since 2026-08-20 — the same shape as §6's earlier lesson that a
  behavioural question is the owner's to answer, not a run's to infer.
- **A number can be right and its unit label wrong at the same time.** `PERFORMANCE.md` item 14's
  "787 MB" and "6.6 MiB" were only mutually consistent at 6.558 MiB, and both were MiB — a test helper
  divided by `1_048_576` and printed the literal string `"MB"`. Caught only by doing the division back
  from the reported total.
- **A budget that is a sum of ceilings is not a sum of occupancies.** Item 13's 656 MiB looked like
  headroom actually spoken for; four of its five terms cannot be reached at the owner's canvas size, so
  the real steady state is a third of the sum. Adding a new cost against the sum rather than the steady
  state double-counts.
- **Two stale pointers were caught before they cost a session.** Both this file and `nextprompt.md` had
  carried "a vector layer's transform is not undoable" as outstanding after it shipped this same day —
  the same class of staleness `CLAUDE.md`'s own notes warn about, just inside a single day rather than
  across two.
