# Handoff — 2026-08-21 (second pass)

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md. Continue the UX pass.

You are the orchestrator: delegate to agents, don't do worker-level tracing yourself. Workflows and
subagents are pre-authorized here.

`main` is green at 1531 fast-tier tests and **nothing is in flight** — no worktrees, no `tmp/*`
branches. A Release build of `09705e8` is on my iPad.

Start by asking me what I found on the device, then work the queue in TODO.md. Three things I have
just been given and have not tried yet, so ask about them specifically:

1. **The lasso fill's Edge Overlap slider.** It was hard-zeroed by mistake and now works; the fill
   should no longer leave a pale seam where it meets a soft line edge.
2. **Filling twice in a row quickly with the lasso.** The first fill used to vanish. Try to out-race
   it.
3. **The Move tool on a vector layer.** It used to cost ~100 ms per touch sample and now costs
   ~0.004 ms. The handles should also stay a constant size as you zoom — that part has never been
   checked by a finger, only by a test.

One thing I asked for that came back disagreeing with me, and I have not re-checked it: I said the
**gap closing** slider needed inverting in lasso mode like Edge Overlap did. It was measured instead
and found already correct — 0/2/4/8/16 seals breaks of 0/2/4/6/10 rows. If it still feels wrong when
you try it, that measurement is what to argue with; don't just re-invert it on my say-so.

Then: TODO.md's queued lasso/move asks (a), the perf programme's remaining Tier A items, and Add Text
stage 5.

Two questions I still owe you, unchanged for days — ask when they block work:
  - Save semantics when a project loaded with something unreadable: may saving overwrite the good
    original, refuse, or prompt?
  - Which faces belong in the font picker's favourites strip.

Two rulings you owe me, from work that merged today. Ask when you reach them, not before:
  - A double-traced ellipse (going round twice) detects as a rectangle. Pre-existing, not a regression.
  - The smart oval has no arc-end handles, so "I drew 100° and wanted 180°" means drawing it again.
```

### Notes on why that prompt is shaped this way

**Lead with the device questions.** The owner's observations have out-performed code-tracing agents
every single time this pass — five for five. Two of today's fixes exist only because they reported
something an agent had reasoned was fine, and one of them (Edge Overlap) was a defect *introduced* by
an orchestrator's armchair geometry.

**Flag the gap-closing disagreement rather than hiding it.** The owner asked for a change; the
measurement says it is unnecessary. Both could be right — the slider may be correct and still feel
wrong. Presenting it as an open disagreement is honest and cheap; silently not doing it is not.

**Do not re-open the lasso fill's design.** LASSO_FILL.md is the spec, the owner has ruled on the
semantics twice, and §2a records a ruling that closed two bugs by deleting work. In particular do not
build a cross-mode parity test and do not add a connected-component filter; both were orchestrator
suggestions the owner or the research overturned.

**Machine state.** Clean. No stray simulator clones in `~/Library/Developer/XCTestDevices`.

**Process traps that cost this session real time**, all now in CLAUDE.md or memory:
- `git merge --ff-only` run from inside a branch's own worktree prints "Already up to date" and merges
  nothing. It happened **four times** in one session. Run merges from the main worktree, as their own
  command, never chained onto a `cd`.
- The agent scratchpad is shared between sessions despite being documented as isolated. Prefix scratch
  files per agent.
- A `PerfBaselineTests` failure inside a full fast tier is environmental far more often than real.
  Confirm with a 30-second isolated re-run on a device of your own; do not re-run the suite to decide.
- A stale brief is worse than no brief. Three agents this session were dispatched against a `main`
  that was 65 commits old; two worked it out themselves and refused to build. **`git fetch` and read
  the log before writing any agent prompt.**

---

**All four of session 61's parked branches are merged, and both lasso bugs the owner reported today
are fixed.** `main` is at **1531 fast-tier tests, 1527 passed, 0 failed, 3 skipped**. No worktrees, no
`tmp/*` branches, no simulator debris. A Release build of `09705e8` is on the owner's iPad.

**The earlier half of this day is below and still true** — the performance programme confirmed on
hardware, the owner's seven device checks all clean, item 14 re-scoped. What follows is what changed
after it.

## What landed in the second pass

- **`tmp/move-overlay`** — owner asks (c) and (d). The Move drag cost **102.3 ms per touch-move sample
  and now costs 0.004 ms**; the branch had been measured but never got the verification run this repo
  requires, and that is the only reason it sat. 1513 / 1510 / 0 / 3, +32 accounted for by counting
  test functions in the source rather than trusting the run.
- **`tmp/lasso-active`** — owner ask (b), and the answer to the question nobody had recorded:
  **the selection already survived a tool change; only the toolbar readout lied.** Proved from the
  tree — the fix adds no code to any clearing path, no clearing site is a tool change, and
  `CanvasView` already handed the stroke view `selectionClipPath` regardless of the current tool, so
  brush, eraser and fill were clipped to the selection all along. Blast radius is the icon alone.
- **`tmp/lassomove-rulings`** — the owner's three lasso-move rulings folded into LASSO_MOVE.md.
- **`tmp/lassorace`** — both of today's lasso bugs, described below.

## The two lasso bugs, and what they turned out to be

**The second-fill race is not lasso-specific.** The owner: *"that bug is present in the lasso bug right
now. currently I havent found the normal fill to do it though."* Only failure mode (a) reproduced — the
first fill silently dropped — and **a bucket-fill probe of the same interleaving failed identically**,
so the hole is in `commitInteractiveFill`, shared by both tools. The owner sees it only on the lasso
because the *window* is far wider: a lasso session derives a ring mask and reference colours over the
whole canvas on the CPU, then runs two distance transforms per reference colour, against one wall pass
and one flood for a tap. `2226ef0`'s generation guard covers a fill that is rendered but not yet
published; this is the narrower case of not rendered at all. Fixed by
`awaitFillRenderIfNothingProduced()` before `endFillGeneration()` — waiting rather than deferring the
bake is forced by `beginCanvasEdit`'s contract, since the next `begin*Fill` composites its wall
reference two statements later.

**The Edge Overlap halo was my error, and both of my explanations of it were wrong.** I had instructed
that `fillExpand` be hard-zeroed in lasso mode, reasoning that inverting moved the antialiasing error
to the far side of the line. Then, told it bled, I guessed the fix was to dilate the collar — which
shrinks the fill and is backwards against the owner's stated semantic. **The pixels settled it**: the
fill stops exactly at the artwork's silhouette and never reaches clean paper, which looks right and is
the bug, because the fill composites *underneath* the line — a 64-alpha line over a 213-alpha fill
resolves to 223 and the background shows through the drawing's own soft edge. The fix is the ordinary
dilate, clipped to the loop mask because growing the result is the one thing that could push paint
across the fence.

**Gap Closing needed no change** and was never hidden. It already satisfied the owner's property and is
now pinned: 0/2/4/8/16 seals breaks of 0/2/4/6/10 rows, monotonic. The owner asked for both sliders to
be inverted; the measurement says one of them already was. **If it still feels wrong on device, that
measurement is the thing to argue with.**

The owner also ruled that the two fill modes are **not** meant to agree pixel-for-pixel, and that more
gap closing making the normal fill smaller while making the inverted fill bigger is *intended*. So the
properties pinned are single-mode and monotonic — the gap width that seals grows with the slider, the
filled area grows with edge overlap — not cross-mode parity. Do not build a parity fixture; it was my
idea and the owner rejected it.

## A ruling that closed two bugs by deleting work

Asked whether the lasso fill should paint over line art on the **same layer** it is filling, the owner
said: *"if the line art is on the same layer I am filling, its okay that the lineart is not filled
over, in fact I'd rather keep it that way."* Both BUGS.md entries tracking that since 2026-08-17 are
closed as not-a-defect and pruned. **LASSO_FILL.md §2a records the ruling and, more importantly, the
distinction it does not touch**: the filled *region* must still run underneath the ink, because
`fill = loopMask ∧ ¬reached` includes wall pixels and that is what stops a halo along every
antialiased edge. Lines staying visible is a compositing outcome; the region stopping short would be a
real defect. Easy to conflate, expensive to get wrong.

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
