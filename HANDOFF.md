# Handoff — 2026-08-22

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate to agents, don't do worker-level tracing yourself. Agents are
pre-authorized — but the budget is the constraint, not the permission. Last session ran two Opus
workers and that was right; a four-tracer workflow with a per-finding verify tier was launched
first and I killed it. Two implementation agents plus one close-out is the shape that works.

**Two branches are built, green on their own, and unmerged — nothing else is in flight.**
`tmp/lassorefill` and `tmp/lassoedge`, worktrees `../PaintApp-lassorefill` and `../PaintApp-lassoedge`.
Merge them first, in that order, and read "The one collision" below before you do — the second
branch's specification paragraph rests on a premise the first branch deletes, and git will merge
both cleanly without noticing. The merged tree has never been built or tested.

Then get a Release build on my iPad and ask me to look at it. Both of these are things only my eye
can settle, and neither has been seen on hardware:
1. **Fill twice over the same place.** Second colour should win now. Also try filling over line art
   on the same layer — it will be covered, which is what I asked for after testing.
2. **The Edge Overlap slider in Lasso mode.** Top of the range should sit exactly on the outer edge
   of my line; lower it and the colour should tuck under. Nothing should land on clean paper at any
   setting.

Three things I need to rule on once I have seen it, all written up below — don't ask before I have
the build in my hands:
  - a single pixel of the line's soft fringe is ~12% see-through at the top of the range;
  - the slider jumps when I switch between Flood and Lasso, because they now hold separate values;
  - the Select menu's own Fill/Clear commands were changed to match the tool, which I didn't ask for.

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

`main` is at `e8363a9`, unchanged by this session apart from these docs. Two branches parked, both
one commit, both clean trees, both with their own fast-tier run. No simulator debris, no clones, no
`xcodebuild` running. **Nothing has been pushed.**

The session stopped at 98% of the five-hour window, on the owner's instruction, before merging.

### `tmp/lassorefill` — a fill lands on top of what is already on the layer

Commit `da71011`. **1537 / 1534 passed / 0 failed / 3 skipped**, base 1531 / 1528 / 0 / 3. +6, matched
by +6 static `func test`; **all six were watched failing against the base production code** with only
`PaintSoftware/` stashed. Six XCUITest classes most exposed to the view-stack change also ran:
49 / 48 / 0 / 1, the skip pre-existing.

The bug was one composite order copied into four places, so all four moved together:

| where | was | is |
|---|---|---|
| `CanvasManager+Fill.swift:470` (raster commit) | new fill under the existing `raster` tier | existing content built first, fill over it |
| `VectorLayer.swift:611`/`:753` (`addFill`) | kind-ordered insert, below every stroke | appended to the element list |
| `PixelOps.swift:279` + `ThumbnailRenderer.swift:20` | `fillImage` drawn first | drawn last |
| `LayerHostView.swift:56` | `fillImageView` under `strokeView` | above it |

A committed fill is folded into `raster` by that same call, which is why fill #2 went under fill #1.
**The blast radius is smaller than it looks, and that is load-bearing**: every commit path passes
`newFill: nil`, so a cel at rest has `fillImage == nil` and onion skin, thumbnails, export, Move's
lift, the eraser and `CompositorParityLogicTests` see no change at all. The view stack and `PixelOps`
had *disagreed* about this tier; they now agree.

The vector half is paid for rather than papered over. Appending breaks the kind-sorted invariant
`splicing` assumed, so it is now a **positional** splice — the i-th element of a kind is replaced
where it sits, the identity for any arrangement. `registerVectorFillUndo` is **deleted**: a
fills-bucket undo has to invent a z-position and would have restacked an appended fill under the line
art on redo. `registerVectorTextUndo` was already the whole-array swap for that reason and is renamed
`registerVectorElementsUndo`. Two existing tests were **deliberately inverted** and are named as such
(`VectorEraserHybridLogicTests…LandsOnTopOfIt`, `BrushEngineLogicTests…AFillWhichGoesOnTop`); the
first had a comment asking whoever settled the ordering to do exactly this.

### `tmp/lassoedge` — Edge Overlap's top is the ink's outer edge

Commit `d2dd2f3`. **1535 / 1532 passed / 0 failed / 3 skipped**, same base. Delta +4: two tests
removed because they encoded "6 px puts paint past the ink", six added. All six were watched failing
against restored pre-fix wiring — the silhouette one against a temporarily restored dilate kernel,
where it failed naming pixel (20, 18) as off the drawing. XCUITest tier **not run**; the one panel
test that touches this slider drives it in Flood mode, which is byte-for-byte unchanged, and that is
reasoning rather than a measurement.

`lassoEdgeDilate` became `lassoEdgeErode` — `min` over the disk instead of `max`, same stencil, same
`insideArtworkRect` guard. The re-anchoring itself is one line, `CanvasManager+Fill.swift:264`:
`lasso ? fillExpandRange.upperBound - fillLassoExpand : fillExpand`. Where the top of a slider sits
is a fact about a UI range, so the engine still just runs a morphological operator.

Two things worth knowing:

- **Lasso keeps its own stored value** (`fillLassoExpand`, defaulting to the top of the range) behind
  one accessor the panel, side toolbar, sideways drag and both setters go through. Without it the
  shared default of 2 would have shipped a 4 px retreat — the pale seam the owner reported that same
  morning — as the lasso's out-of-the-box behaviour.
- **The empty-result count is retaken after the erode**, which the brief did not ask for and is
  right: a dilate can never empty a non-empty result, an erosion can (lasso a 5 px blob at the bottom
  of the slider), and the old count would have baked a transparent fill and booked an undo entry for
  it — what §7.1 forbids.

### The one collision, and it will merge clean without telling you

Both branches edit `CanvasManager+Fill.swift`, in different regions, so git will take both. But
**LASSO_FILL.md §6 step 7 — and the same paragraph duplicated as a doc comment at
`CanvasManager+Fill.swift:235` — argues from a premise `tmp/lassorefill` removes**: *"the fill
composites **underneath** the artwork… so the stack comes out at alpha 223."* It no longer composites
underneath. **The conclusion survives** — with the fill on top the same pixel lands at α ≈ 0.87, still
short of opaque, so Edge Overlap still has a seam to close and the top of the range is still the right
place for it — but the arithmetic in both copies is wrong until someone rewrites it. This is the
`@discardableResult` family from BUGS.md: two changes to different lines that compose into a defect
neither had alone.

Merge `tmp/lassorefill` first, then `tmp/lassoedge`, then fix those two paragraphs, **then run the
fast tier on the merged tree** — no one has. Run merges from the main worktree as their own command;
`--ff-only` from inside a branch's own worktree prints "Already up to date" and merges nothing.

### Four things for the owner, once they have a build

1. **~12% of the background shows through one pixel of the outline at the top of the range.** The
   fill's own fade has exactly three places it can live: on the paper (just rejected), under the ink
   (what ships), or nowhere — cut coverage hard to 255 wherever the artwork has any alpha, which
   closes it *and* keeps paint off clean paper, at the cost of a jagged outer edge. The third option
   is not built. Written into `lassoEdgeErode`'s comment and §6 step 7 so it is not re-found as a bug.
2. **The slider jumps when you switch fill type**, since Lasso and Flood now hold different values.
3. **`fillMode` and `fillGestureIsLasso` can disagree for one gesture** — switching the picker while a
   fill is still adjustable makes the slider write the other mode's value and the live fill stops
   responding until the next tap. The alternative is cancelling the adjustable fill on a mode switch,
   a behaviour change nobody asked for.
4. **The Select menu's Fill and Clear were changed to match**, which the ruling did not cover. The
   argument for it is that "Fill" should not mean two things in one app; say if you want the split.

### A count that does not tie, worth thirty seconds

This file said `main` was **1531 / 1527 / 0 / 3** on 2026-08-21. Both workers measured the same base
commit at **1531 / 1528 / 0 / 3** — same total, same skips, one more pass. One of the two readings is
wrong and the counts are the only signal this repo trusts. Re-read the base xcresult before treating
either as the baseline.

## Still true from 2026-08-21

The performance programme is **confirmed on hardware** (Release `38e22c6`, iPad 9, seven checks, all
clean — *"17fps is gone… 4k screen displays full 60fps when painting"*, *"leaving the gallery is
instant"*). `PERFORMANCE.md` item 14 was re-scoped: the expensive half stays declined, and the cheap
half — stop writing and loading a raster tier for cels with no raster content — is queued and
correctness-clean. Add Text Stage 5 (the projective distort) is queued behind it. TODO.md's ask (a),
the lasso *move*, is unstarted; `LASSO_MOVE.md` §5's six owner rulings are settled and must not be
re-litigated.

## What this session learned

- **A ruling can be overturned by the owner testing it, one day after they gave it.** §2a's "I'd
  rather the lineart not be filled over" was theirs, considered, and recorded — and *"the previous
  decision is overruled as I tested it"* is the only evidence that outranks it. The branch rewrites
  the section rather than annotating it, because a spec that carries both readings makes the next
  reader guess.
- **Ask when the two readings are a sign flip.** "Edge overlap makes the fill expand out, not
  contract inwards" had two coherent meanings and one question settled it — and the answer was
  neither of the two obvious ones. The slider's *direction* was never wrong; its *anchor* was.
- **A per-mode default was the difference between shipping the fix and shipping the old bug.** One
  shared `fillExpand` would have re-shipped the seam by default at the very moment the halo was fixed.
- **The Workflow tool's canonical verify fan-out picks its own width.** Four tracers times an unknown
  number of findings is a number the first stage chooses after you can no longer see it. The owner
  killed it inside a minute. Bound the second stage or do not have one.
- **Delegate the building and the test run, not the looking.** Eight inline `grep`/`sed` reads had
  already located both defects to file:line before any agent was launched.
