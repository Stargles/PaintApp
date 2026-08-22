# Handoff — 2026-08-22 (session 67)

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md, TODO.md and ARCHITECTURE_REVIEW.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. **At most three Opus agents in flight AT ONCE, counted across every stream** — not three per
workflow. Three workflows each correctly capping themselves at three summed to seven on 2026-08-22,
and I capped it. Add up the widest phase of each live workflow before launching another.

**TODO.md's Queued list is empty.** Everything I asked for is merged and on my iPad. So the next
session is mine to point: I said it would be new large features, and ARCHITECTURE_REVIEW.md was
written for exactly that. Start by asking me what the features are.

Before building anything large, put finding 1 of ARCHITECTURE_REVIEW.md to me as a decision:
**fourteen places decide who owns a canvas touch and none of them is the place.** Four defects trace
to it, three in the last week, including one I found myself on 2026-08-22 (the pick tool dead under
the Select panel). It is structural rather than sloppy — `activePanel` is `@State` on `DrawingView`
while `selectedTool` and `floatingPiece` are on `CanvasManager`, so no object can see all the inputs
and no single function can be written. The remedy is one pure `CanvasTouchOwner` type, and it is the
one item that pays for itself on the **first** new tool. Ask me whether to do it before the features
or alongside them.

`main` is at `a5fa3b2`+docs, **1617 fast-tier tests, 0 failed**, nothing in flight, no worktrees, no
`tmp/*` branches. `main` is ~28 commits ahead of `origin/main` and **nothing has ever been pushed**.
A Release build carrying all five of this pass's changes is on my iPad.

Then ask me what I found on the device. Five things are on it and none has been seen by an eye:
1. **Lasso a region on a vector layer and tap Move** — only what is inside the loop should travel,
   with strokes cut at the boundary and the dashed outline travelling with the piece.
2. **The Cut eraser** — the ink should now disappear under the eraser as you drag, instead of
   waiting for the lift.
3. **The pick tool with the lasso Select panel open** — should now work; it was dead.
4. **Save and reopen a project** — cels you have not drawn on no longer write a raster PNG.
5. **Raster Move** — the marching ants now stay up and travel with the piece.

Three behaviour questions are waiting on my eye, not on another run. Ask after I have reported:
  - **Cut eraser across a line thicker than the eraser now visibly does nothing.** It always did
    nothing — I used to find out on lift. Leave it, refuse a cut too short to open a gap so the
    eraser reads as having missed, or widen the cut at the cost of not landing where I aimed?
  - **A line crossing the cut can flicker** during the drag, under 10% of what the cut removes.
    Fixing it exactly costs the ~95 ms re-render that makes To Cross expensive. Only if I see it.
  - **A fill chunk dropped on blank paper stays a fill** — literally what I asked for, may still read
    as a mistake on real artwork. Device question.

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

`main` = `a5fa3b2` plus doc commits, **~28 commits ahead of `origin/main` and unpushed.** Clean tree,
no worktrees, no `tmp/*` branches, no simulator clones.

Every merge verified as its own run rather than trusted from the branch: 1573 → 1583 → 1591 → 1617,
each delta matched against a static `func test` count on the merged tree.

## What landed

Five changes. TODO.md's "Done this pass" has the full writeups; what follows is only what a later
reader would otherwise have to rediscover.

**Two of the five inverted a premise the orchestrator handed the worker, and a test proved it both
times.** That is the pattern worth carrying: the brief was wrong, the worker followed it far enough to
measure, and the measurement turned it around.

1. **The Cut eraser's preview.** The brief said a footprint-shaped preview would show *less* than the
   cut removes, because the stroke's whole width goes. Backwards: `BrushStamper` gives the two
   surviving pieces round end caps that grow back into the gap by the stroke's own radius, so
   **cutting a 40 pt line with an 8 pt eraser changes zero pixels** — asserted at exactly 0, with the
   same test asserting a footprint punch *would* open a 250-pixel notch, so it cannot pass against a
   scene that fails to exercise the problem.
2. **The lasso move's eraser rule.** The design proposed that eraser marks never move and never
   split. The owner overruled it — *"If the hole is fully inside, it moves it. If its outside, it
   wont"* — making an erase element an ordinary element under the same centre-line test. Simpler than
   the carve-out, and consistent with this app's own "the eraser is a stroke" decision.

**The owner's redundancy theory about the two cutting erasers was refuted, and that is what justifies
not merging them.** `cutRanges` and `cutToIntersection` have one caller each and neither calls the
other; To Cross's extent comes from crossings with *other* strokes, not from the footprint. Remove the
cross feature and you get nothing, not Cut. ~18 lines of real duplication, and a dead `Sweep.mode`
(deleted). Merging would put a mode switch inside the shared body — a wash, declined.

**Item 14 was scoped by reading the owner's device, not by arithmetic.** Their live package: three
cels at 2048², every `_raster.png` exactly 73,558 bytes and **fully transparent**, the raster layer's
included. Two traps decided the design and both are pinned by tests: `validateProject` **gates the
atomic swap**, so simply not writing the file would have moved every staged package to Trash while
`save` reported success; and `rasterFileName` stays non-optional because its *absence* is what makes
PencilKit-era manifests fail to decode and be skipped rather than opened blank.

**The pick-tool bug is finding 1 of the architecture review in miniature.** One gate consulted
`activePanel`, the overlay's gate never consulted `selectedTool`, and the touch was owned by nobody.
Fixing it then exposed that the Select panel had been surviving `interactionBegan` **only by
accident** — its overlay swallowed every canvas touch, so no handler ever fired to close it. A test
failure found that, not review.

## What the owner has to decide, once they have looked

Carried in the paste block above: the Cut eraser on a thick line, the crossing-line flicker, and the
fill chunk on blank paper. Two more, not urgent:

- **Text placement tap is dead if you enter text mode first and then open Select** — the exact mirror
  of the pick-tool bug, left alone deliberately because Select is the more recent word there. Same
  one-line change if the owner disagrees.
- **Move nodes at zoom** — the lasso float borrows `ObjectTransformOverlayView`, so the owner's own
  item-(d) symptom will appear on this tool too. Expected, filed, not fixed.

## Carried work, deliberately not done

- **The raster Move's undo half** (one step per nudge). The vector half and selection-at-bake shipped.
  A raster nudge changes only `FloatingPiece.transform`, which is transient and not in the document,
  so per-nudge steps must be transient — and the bake step then sits on top of them and its undo
  restores the pre-move cel, killing every step beneath. Making it work means the bake step's undo
  *re-creating the float*, which doubles what a raster Move retains in history. That is a second
  feature. LASSO_MOVE.md §3 stage 4.
- **PERFORMANCE.md item 14's expensive half** stays declined, unchanged.

## Traps this pass hit, for the next one

- **`git stash` is one stack per *repository*, shared by every worktree.** A worker's `pop` landed
  another session's stash as ~45 conflicted files. Park work as a commit on your own branch. Now in
  CLAUDE.md.
- **Three Opus per *stream* is not three Opus.** Three workflows each capping themselves at three ran
  seven at once. Nothing sums them for you.
- **Timings taken at 5% idle with no `xcodebuild` running at all.** ~2.9 cores of Adobe background
  churn (`AdobeIPCBroker`, `Adobe Desktop Service`, `Creative Cloud`). Read
  `top -l 2 -n 0 -s 2 | grep "CPU usage"` before believing a millisecond, and mark contended figures
  CONTENDED rather than dressing them up.
- **The graphify `post-checkout` hook rewrites the tracked `GRAPH_REPORT.md`** on every branch switch
  and aborts `--ff-only`. `git checkout -- graphify-out/GRAPH_REPORT.md` before each merge.
- **A slice edit over a Markdown section removes everything between its anchors.** One such edit here
  silently deleted a queued item along with its intended target; caught by diffing the commit. Prefer
  anchored replaces to index slicing.

## Still true, carried forward

`LASSO_MOVE.md` §5 now carries **eleven** owner rulings, five taken 2026-08-22; do not re-litigate
any. `LASSO_FILL.md` §6 step 7 still opens with "Four specifications, and what each got wrong".
Add Text Stage 5 needs a Release build on the iPad before merge, like every warp-touching stage.
`ARCHITECTURE_REVIEW.md` is new and is written for the next session specifically.

**Open, unruled, carried:** whether a lasso leak deserves its own signal; a superseded lasso no longer
saying "nothing enclosed"; the text tool always editing an existing label rather than placing a new
one beside it; the toolbar colour swatch changing meaning while a text session is live.
