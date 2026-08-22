# Handoff — 2026-08-22

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. Two or three Opus workers at once, each in its own worktree with its own simulator, is the
shape that has landed everything here. Do not fan out a verifier tier per finding — I killed one of
those on sight, and eight inline greps had already found both defects it was going to look for.

`main` is at 1573 fast-tier tests (1570 passed, 0 failed, 3 skipped), nothing in flight, no
worktrees, no `tmp/*` branches, no simulator clones. **A Release build of `fdd2bad` is on my iPad
and carries all six changes below.** `main` is 9 commits ahead of `origin/main` and nothing has
been pushed.

Start by asking me what I found on the device. Six things are on it and none has been seen by an
eye:
1. **Fill twice over the same place** — second colour wins now, and a fill covers line art on the
   same layer.
2. **Edge Overlap in Lasso mode** — top of the range sits on the outer edge of my line, lower tucks
   it under. It should work at *every* slider position now; it was broken below full.
3. **Lasso through an already-filled area** — there should be no pale sliver along my loop.
4. **Drag a smart shape by its outline** — line, box and circle should all move. Nodes still resize.
5. **Pinch two stacked layers in the layers tab** — they should merge.
6. **Hold either size slider** — a real-size stamp of the actual brush should appear beside it.

Then the judgement calls waiting on me, written up below. Ask after I have reported, not before:
the ~12% see-through fringe pixel; the Flood/Lasso slider jump; the Select menu's Fill/Clear; the
shape outline's 22pt reach and whether the interior should move too; the two pinch thresholds; the
eraser preview's slate patch and its placement.

Then TODO.md's Queued: (f) the cut eraser's live feedback — **measure before promising, the cross
eraser's cutting pass is ~95 ms a sample** — then (a) the lasso move, then PERFORMANCE.md item 14's
cheap half, then Add Text stage 5.

Two questions still owed, unchanged for days — ask when they block work:
  - Save semantics when a project loaded with something unreadable: may saving overwrite the good
    original, refuse, or prompt?  (A branch shipped "prompt once, then remember"; confirm it.)
  - Which faces belong in the font picker's favourites strip.

Two rulings you owe me, from earlier work. Ask when you reach them, not before:
  - A double-traced ellipse (going round twice) detects as a rectangle. Pre-existing, not a regression.
  - The smart oval has no arc-end handles, so "I drew 100° and wanted 180°" means drawing it again.
```

---

## State

`main` = `fdd2bad`, **9 commits ahead of `origin/main` (`e8363a9`) and unpushed.** Clean tree, no
worktrees, no `tmp/*` branches, no simulator clones.

Every merge was verified as its own run rather than trusted from the branch: 1541 → 1544 → 1554 →
1560 → **1573**, each delta matched against a static `func test` count on the merged tree. The last
step is +13 in the fast tier against +14 `func test`; the extra one is an XCUITest, which the
fast-tier selector does not run.

Release build installed on the iPad four times today; `NWError 54` on the first `install` of a
session and never after, as always.

## What landed

Six changes, four branches. TODO.md's Done this pass has the full writeups; what follows is only what
a later reader would otherwise have to rediscover.

**A fill lands on top of what is already on the layer.** The owner overruled their own previous-day
ruling after testing — *"the previous decision is overruled as I tested it. Cover everything."*
LASSO_FILL.md §2a is rewritten, not annotated. One composite order was copied into four places and all
four moved together; the blast radius stayed small because every commit path passes `newFill: nil`, so
a cel at rest has no preview tier at all.

**Edge Overlap shipped broken and was rebuilt.** Three faults, one algorithm. The counter read a slot
nothing wrote; the erode retreated from the fence as well as the ink; and the pre-invert form the owner
asked for strands a fringe. That last one is the interesting one — see below.

**A smart shape's outline moves the shape.** The owner's symptom (*"it just creates a line (pencil), or
does nothing (finger)"*) was the whole diagnosis: the overlay's hit test claimed handles and declined
everything else, so the touch fell through to the canvas and the pencil-only gate decided the rest.

**Pinch-to-merge measured the wrong axis** — found from the owner's own recording, below.

**A real-size stamp preview beside the size slider**, using the real `BrushStamper` rather than a drawn
circle, sized from the live canvas scale.

## Three findings worth more than the fixes

**1. The owner's algebra was right, and following it exactly is what disproved the implementation.**
They said a dilation before the invert equals an erosion after it. True — for a *greyscale* dilation.
The collar is a binary mask and the coverage ramp lives on the far side of the invert, so a binary
pre-invert dilation cannot carry the ramp with the boundary and leaves a detached fringe: measured
`[0, 213, 0, 0, 255, …]` against the erode's `[0, 0, 0, 213, 255, …]` — a band of colour, then bare
ink, then the fill. Both profiles are now a regression fixture. **LASSO_FILL.md §6 step 7 has had four
specifications and now opens by saying so and naming what each got wrong**, because a reader who does
not know why the obvious pre-invert form was rejected will write it again.

**2. A gesture can have no reachable success state, and only a recording shows it.** The owner recorded
four seconds of pinching two layers. `PinchMergeGate` fired on the recognizer's *radial* scale below
0.6; the layer list is vertical. Their fingers closed **88% of the vertical gap** (89 → 10.5 pt) and
the best scale reached was 0.709 — because the fingers were **137 pt apart horizontally** throughout,
and that term dominates `hypot`. Hold it constant and drive the vertical gap to *zero* and the scale is
still 0.838: **the merge could not have fired however hard they pinched.** The old rule was reachable
below ~67 pt of horizontal separation, which is exactly how it survived hand-testing by someone holding
thumb and forefinger close together. Full table in BUGS.md.

**3. `Slider.onEditingChanged` does not fire on a press that never moves.** SwiftUI only reports editing
once a drag begins — measured against the real panel with the thumb parked dead centre so a press could
not have missed. The owner asked for a preview on press; wiring it to `onEditingChanged` would have
produced a control that works only if you wiggle. Touch-down is served by a simultaneous
zero-distance `DragGesture`; the XCUITest was watched failing on exactly that.

## What the owner has to decide, once they have looked

**From the lasso fill**

1. **~12% of the background shows through one pixel of the outline at the top of the Edge Overlap
   range.** The fade has three possible homes: on the paper (rejected), inside the ink's footprint
   (what ships), or nowhere — a hard cut at the ink's outer extent, which closes it *and* keeps paint
   off paper, at the cost of a jagged edge and of throwing away §6 step 6. **Not built.** Recorded in
   `lassoEdgeErode` and §6 step 7 so it is not refiled as a bug.
2. **The slider jumps when you switch Flood/Lasso**, since they hold separate values (2 and 6).
3. **`fillMode` and `fillGestureIsLasso` can disagree for one gesture** — switch the picker while a fill
   is still adjustable and the live fill stops responding until the next tap.
4. **The Select menu's Fill and Clear were extended to match the tool**, which the ruling did not cover.

**From the shape outline drag**

5. **Only the outline moves the shape, not the interior.** Faithful to "the line, not the node", and it
   keeps the inside of a pending circle drawable — but the Move box uses its whole interior. One line
   to change.
6. **22 pt of reach around the outline can no longer start a stroke** while a shape is pending. On a
   large shape that is a band across the canvas. Feel it before shrinking it.
7. **A partial arc's whole ellipse is grabbable**, because the blue guide strokes the whole outline.

**From pinch-to-merge**

8. **The two thresholds are feel, picked from one recording**: the vertical gap must fall to **45%** of
   its value at latch (33–50 pt on a 62 pt row list; it fires on the owner's samples with their fingers
   still 35 pt apart), with a floor of **20 pt** of travel so a two-finger rest never merges.
9. **A pair latching under 20 pt apart vertically cannot fire**, since touching is less travel than the
   floor. The agent tried a scaled floor to remove the dead zone, found the term was algebraically
   implied by the fraction test — dead code that would have *looked* like a safeguard — and removed it
   rather than ship the illusion. Unlike the bug being fixed, the remedy here (start further apart) is
   what aiming at two rows already means.
10. **A purely horizontal pinch on the layer panel now does nothing.** That is the axis change working,
    but it is a change.

**From the size preview**

11. **The eraser preview punches a hole in a fixed neutral slate**, not the artist's colour — their own
    colour would vanish the day they picked white. The one call with no obviously right answer.
12. **On a vector layer in eraser Mode 2/3, `eraserSize` is a selection radius, not a stamp.** The size
    is right in all three modes; the "hole in ink" imagery is literally wrong for Mode 3. May want
    revisiting when TODO (f) settles those modes.
13. **Placement** — above the rail slider, leading of the panel slider — was chosen without seeing a
    hand on the device. One-line enum change.

**Noticed, not ours to fix, now visible:** the rail's size sliders are `1...50` while the panels' are
`1...200`, so a size set above 50 from a panel pins the rail's slider at max.

## Traps this pass hit, for the next one

- **The graphify `post-checkout` hook rewrites the tracked `GRAPH_REPORT.md` on every branch switch**,
  and an `--ff-only` merge then aborts with "local changes would be overwritten". `git checkout --
  graphify-out/GRAPH_REPORT.md` before each merge. It bit three of the four merges here.
- **`git reset --soft main` is not a safe squash target while `main` is moving.** A worker rebased onto
  one SHA, squashed against the branch *name*, and silently reverted 52 lines another commit had added
  in between. Git reported nothing; it was caught by diffing `--stat` afterwards. Squash against the
  SHA you rebased onto.
- **`git fetch origin && git rebase origin/main`, as CLAUDE.md words it, rebases you backwards here**,
  because `main` is 9 commits ahead of an unpushed `origin/main`. Rebase onto local `main` until
  someone pushes.
- **A vacuous test is worse than no test, and this pass shipped one to the owner's iPad.**
  `testAFillTheEdgeOverlapErodesAwayEntirelyCommitsNothing` asserted an empty pixel count — and the bug
  it was meant to catch made the count always empty, so it passed against the defect. Every test
  written after that was watched failing against restored pre-fix wiring or a deliberate mutant, and
  each report names the assertion it failed on.

## Still true, carried forward

The performance programme is confirmed on hardware (Release `38e22c6`, iPad 9, seven checks, all clean).
`PERFORMANCE.md` item 14: the expensive half stays declined, the cheap half is queued and
correctness-clean. Add Text Stage 5 needs a Release build on the iPad before merge, like every
warp-touching stage. `LASSO_MOVE.md` §5's six owner rulings are settled; TODO (a) is unstarted and must
not re-litigate them.

**Open, unruled, carried:** whether a lasso leak deserves its own signal; a superseded lasso no longer
saying "nothing enclosed"; the text tool always editing an existing label rather than placing a new one
beside it; the toolbar colour swatch changing meaning while a text session is live.
