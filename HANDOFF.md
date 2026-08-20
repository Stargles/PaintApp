# Handoff — 2026-08-20

**`TODO.md`'s "In flight" is empty and the performance programme is finished.** Thirteen branches
landed overnight. `main` is at **1426 fast-tier tests, 1423 passing, 0 failing, 3 skipped**, verified
on a fresh simulator *after* the merges rather than only on each branch's own base. No worktrees, no
`tmp/*` branches, no simulator debris.

**The one thing blocking everything now is the iPad.** It read `unavailable` all night, so nothing
below has been seen on hardware — every after-figure in `PERFORMANCE.md` is a Debug simulator, where
the *shape* of a result transfers and the multiplier does not.

## What shipped

**The owner's four reported bugs**

| what | the fix, in one line |
|---|---|
| Canvas border ignored padding | "The canvas edge" is the *artwork rect*, inset from the buffer by `canvasPadding`; the edge is now an unconditional barrier between pixels, not a gap-closing bridge conditional on nearby ink. |
| Lasso filled the whole canvas | Morphological hole filling per `LASSO_FILL.md`. Circling a closed box paints **0.4004** of the canvas — its exact footprint — against **1.000** before. |
| Cross eraser stubs, and its size doing nothing | `StrokeGeometry.intersections` clustered in *sample-index* units against a physical-distance tolerance, so one crossing arrived as 25–109 entries. Stub **10.0 pt → 0.0000 pt**. The footprint now selects every stroke whose centreline it covers. |
| A second fill broke the first | Each gesture claims a `fillGeneration` and the worker carries an immutable context snapshot, so pairing a new seed with an old session is *unrepresentable* rather than merely documented against. |

**Everything else**

- **The menu-interrupted stroke.** One closed set (`CanvasPresentation`), one central rule, and
  `StrokeGiveUp.interrupted` so an interrupted stroke keeps its ink. The census is settled at
  **BROKEN 7 · SAFE 56** — `Menu` absorbs the whole touch sequence, so the 12 unknowns are safe.
- **Add Text stages 1 and 3.** Place, type, style, move, bake on a raster layer; on a vector layer it
  stays a real editable element across save and load. Stages 4–6 (rotate/scale, projective distort,
  font packs) remain.
- **The performance programme, all fifteen items resolved** — thirteen built, item 10 measured and
  deliberately left alone, item 14 declined on a measurement.

## The numbers worth knowing

All MEASURED on a Debug simulator at **2048×1024**, machine idle unless noted.

| | before | after |
|---|---|---|
| **Live vector stroke, per dab** @2048×1024 | 8.0 ms | **2.2 ms** |
| — the same @4096², the owner's stress canvas | 47.1 ms | **3.9 ms** (21 → 253 fps ceiling) |
| **Project open**, 32 cels | 303.6 ms | **53.5 ms** |
| **`renderSources`**, the main-thread term on a playback tick | 78.2 ms | **23.9 ms** |
| **Leaving to the gallery**, 32 cels | 480.3 ms | **117.1 ms** |
| Undo budget | 300 MiB flat | 192 MiB, `physical/16` |

Two of these answer standing questions rather than just improving a number:

- **"Leaving to the gallery takes ~3 s" is arithmetic, not a mystery.** 95% of the wait was one call,
  `pngData()`. File I/O was 2%; the whole atomic-save machinery 1.6%. At 15.0 ms/cel, three seconds
  is a **~150-cel document** on the iPad 9.
- **Project open was ~3× cheaper than the standing guess** — 303.6 ms for 32 cels, so ~0.95 s at a
  hundred, not the "1–3 s" everyone assumed.

## What needs the owner's iPad

**Deploy is blocked, not skipped.** `~/.config/paintapp/.env` is present and the steps in `CLAUDE.md`
are ready — run them from the repo, not `deploy/deploy.sh`, which pulls `main` and so cannot ship
branch work.

**1. Add Text, keyboard-over-canvas. Still the priority** — nothing headless reaches it, and it is
the likeliest place a real defect is hiding.
   1. **Place a box near the bottom of the screen.** There is no `keyboardLayoutGuide` handling at
      all, so the box may sit under the keyboard. Most likely visible defect on `main`.
   2. Tap into a box, then open and close the text and colour panels.
   3. Zoom to ~0.3× and type.
   4. Scribble into the box with the Pencil, and drag-select inside it.
   5. **New from stage 3**: tap an *existing* label to re-open it. The target is the box, not the
      glyphs, with 6 pt of slop — and the same tap is also the place-a-new-box gesture, so only a
      finger can judge it.
   6. **Record one `ActionRecorder` session covering 1–5** and hand over the JSONL.

**2. Is the 17 fps gone?** A Release build on the 4096² document, and one sentence. If it still feels
like 17 fps, **treat item 11 as ruled out rather than suspect** — frame rate is not one cost, and the
remaining terms would then be somewhere nobody has looked.

**3. Does leaving to the gallery still feel like ~3 s?** If it feels instant, §5's dirty-tracking memo
stays unbuilt for good.

**4. Does opening a project feel faster,** and — the visible behaviour change — do the timeline's cel
blocks arriving blank and filling in over the next fraction of a second read as *loading* rather than
*broken*? That is item 9(c) working as designed.

**5. The lasso**, on the two scenes named: a shape with a gap in its outline, and a loop drawn well
outside the shape.

**6. The cross eraser's feel**, for both rulings.

**7. The app-switch freeze should already be gone** — fixed 2026-08-18, before this pass. If it isn't,
that is new information.

## What the owner owes a ruling on

**Answer these first — they change what gets built next**

1. **How many drawn cels does a real document carry?** A drawn raster cel costs **6.6 MiB resident**,
   measured. At 120 cels that is **787 MB, unbounded — more than all five budgets combined**, and
   item 14 becomes urgent. At 30 cels it is ~200 MB and the item does not exist. This is the largest
   open question in `PERFORMANCE.md`.
2. **Is 192 MiB of undo — about 12 whole-cel operations — enough?** And is trimming to *half* on a
   memory warning generous or stingy? Both are guesses wearing constants' clothes;
   `UndoHistory.currentCost` now exists so a real session can be sampled instead of argued about.

**New consequences of what shipped**

3. **The cross eraser deletes a covered line that crosses nothing, whole.** Always the rule, but the
   circle used to be a pinpoint and can now be 50 pt across, so one tap near a busy corner can wipe a
   stray line entirely.
4. **The cross eraser takes a stroke by its centreline, not its ink** — clipping only the edge of a
   thick line leaves it alone.
5. **A superseded lasso no longer says "nothing enclosed".** Draw a loop enclosing nothing, then fill
   elsewhere, and you get silence rather than a banner about the loop you abandoned.
6. **With the text tool selected, tapping an existing label always edits it** and never places a new
   box beside it. Illustrator's behaviour, chosen deliberately — but you cannot start a second label
   overlapping an existing one without moving the first.
7. **The toolbar colour swatch changes meaning while a text session is live** — it edits the text's
   colour, not the brush's.
8. **Add Text `autoSize` caps at the canvas edge and wraps** rather than growing forever, because
   there are no handles until Stage 4 to drag a runaway box back.
9. **Which five or six faces belong in the font favourites strip.** Shipped with all ~60–80 families
   grouped and no strip, because inventing a shortlist makes it the answer by default.
10. **Should a lasso leak get its own signal?** The collar tint cannot show one — a leak still paints
    the outline, so it is not an empty result and the signal never fires.

**Carried, still unruled**

- **Save semantics when a project loaded with something unreadable**: overwrite, refuse, or prompt?
- **A double-traced ellipse detects as a rectangle.** Pre-existing, verified, not a regression.
- **The smart oval has no arc-end handles.**

## What is worth doing next

Nothing in `PERFORMANCE.md` is left to build. The queue is:

1. **Add Text stages 4 and 5** — rotate/scale with handles, then the projective distort. Stage 5
   wants a Release build on the iPad 9 before merge, per `ADD_TEXT.md` §4 rule 9.
2. **A vector layer's transform is not undoable** — new in `BUGS.md`, and it wants its own branch. The
   obvious fix is wrong: the call site fires continuously during the drag, so per-call undo would
   push hundreds of steps for one gesture. It wants a bracket, and the two paths where
   `isVectorTransforming` turns off *without* a gesture ending are where a bracket would leak.
3. **Item 14, if the cel-count answer says so** — and it needs thumbnails persisted first, which item
   9(c) made a precondition.
4. **The Mode 3 eraser's ~95 ms per cutting sample** — measured, deliberately unfixed until the
   eraser rewrite settles. Note it compounds with the new footprint eraser, which cuts every stroke
   it covers rather than one.

## Five things this pass learned the hard way

- **The docs can be two days stale and read as authoritative.** `PERFORMANCE.md` and `BUGS.md` both
  described the `scenePhase` triple-save as outstanding for two days after it was fixed. Check
  `git log` for the file before building what a document says is outstanding.
- **Contention does not widen the error bar, it changes the answer.** The same test read 303 / 448 /
  527 ms for identical work depending on what other agents were doing. Measure both arms
  *alternately in one run* so the ratio is contention-proof by construction, and name an unchanged
  phase as a control.
- **A control test earns its keep on the first run.** The `Menu` measurement's first draft counted
  *raster* strokes on a vector-by-default layer — right answer, impossible reason. Its paired control
  caught it. Conversely, two of three earlier cross-eraser agents declared the stub hypothesis
  *refuted*; both were wrong, because every test they cited spaced samples wider than the tolerance
  it tested, which no real stroke does.
- **Concurrent agents share one scratchpad directory.** A fixed filename is silently overwritten, and
  one agent ran a whole suite on another's simulator. The xcresult's `deviceName` is what caught it.
- **`.git/hooks/post-checkout` regenerates the tracked `GRAPH_REPORT.md` on every branch switch.** So
  a branch switch inside the main worktree dirties the tree and can block another session's
  `--ff-only` merge. Use a separate worktree, per the protocol at the top of `CLAUDE.md`.
