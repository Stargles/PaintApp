# Handoff — 2026-08-22

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate to agents, don't do worker-level tracing yourself. Agents are
pre-authorized, but the budget is the constraint rather than the permission — two Opus workers
building in parallel, one close-out, and the orchestrator doing the merging and the reading
inline. Last session a four-tracer workflow with a per-finding verify tier got killed inside a
minute; the two-worker shape landed both asks.

`main` is at 1541 fast-tier tests (1538 passed, 0 failed, 3 skipped), nothing is in flight, no
worktrees and no `tmp/*` branches. **A Release build of `3f174d1` is on my iPad.**

Start by asking me what I found on the device. Two lasso-fill changes are on it and neither has
been seen by an eye:
1. **Fill twice over the same place** — the second colour should win now. And filling over line
   art on the same layer covers it, which is what I asked for after testing.
2. **The Edge Overlap slider in Lasso mode** — the top of the range should sit exactly on the
   outer edge of my line, and lowering it should tuck the colour further underneath. Nothing
   should land on clean paper at any setting.

Three things I need to rule on once I have looked, written up below — ask about them after I
report, not before:
  - one pixel of the line's soft fringe is ~12% see-through at the top of the range, and there is
    a third option nobody built that would close it at the cost of jaggies;
  - the slider jumps when I switch between Flood and Lasso, because they now hold separate values;
  - the Select menu's own Fill and Clear were changed to match the tool, which I did not ask for.

Then work TODO.md's Queued: ask (a), the lasso *move* — only what is inside the selection travels
— then PERFORMANCE.md item 14's cheap half, then Add Text stage 5.

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

`main` = `3f174d1`. Clean tree, no worktrees, no `tmp/*` branches, no simulator clones. **Nothing has
been pushed** — `main` is three commits ahead of `origin/main`.

Merged tree verified as its own run, which is the one nobody had done when the branches were parked:
**1541 / 1538 passed / 0 failed / 3 skipped**, +10 over the 1531 base, matched by a static `func test`
count of 1647 against 1637 — so nothing stopped running silently under the merge. Release build
installed on the iPad (`NWError 54` on the first `install`, as always; the retry worked).

## What landed

Both of the owner's 2026-08-21 lasso-fill asks. Full writeups are in TODO.md's Done this pass; the
two things worth carrying forward are below.

**A fill now lands on top of everything already on the layer.** The owner's ruling was
*"the previous decision is overruled as I tested it. **Cover everything**"* — which overturns
LASSO_FILL.md §2a, given by the same owner the previous day. §2a is **rewritten, not annotated**,
because a spec carrying both readings makes the next reader guess.

**Edge Overlap's range moved rather than reversed.** The slider still means *up is more colour*; what
changed is where its top sits — the ink's outer edge instead of 6 px past it. `fillEdgeRadius(lasso:)`
is the one line that expresses it. The lasso keeps its own stored value so the bucket's default of 2
cannot ship as a 4 px retreat.

### The thing that would have shipped broken, and how it was caught

The two branches **merged clean and still disagreed with each other.** LASSO_FILL.md §6 step 7 and its
twin comment in `Fill.metal` both said the fringe pixel *"composites 64 over 213"* — the fill
underneath the ink, which the other branch had just inverted. Git had no way to see it: different
files, different lines, each branch internally consistent.

The number turned out to be right anyway, and the reason is worth keeping: `over` combines alpha as
`a₁ + a₂ − a₁a₂`, which is **symmetric**, so turning the stack over changes the fringe's colour and
not its opacity. 223 before, 223 after. Both copies now say so, specifically so a later reader does
not "correct" it back to the pre-merge wording.

This is the `@discardableResult` family from BUGS.md: two changes to different lines that compose into
a defect neither had alone. The general lesson — **when two branches touch one specification, the
merge is where the specification has to be re-read, not where it stops mattering.**

## What the owner has to decide, once they have looked

1. **~12% of the background shows through one pixel of the outline at the top of the range.** The
   fill's own fade has exactly three places it can live: on the paper (just rejected), inside the
   ink's own footprint (what ships), or nowhere — cut coverage hard at the ink's outer extent, which
   closes the halo *and* keeps paint off clean paper, at the cost of a jagged outer edge and of
   throwing away §6 step 6. **The third option is not built.** It is written into `lassoInvert`'s
   comment and §6 step 7 so it is not re-discovered as a bug. Measured filled fraction at slider 0…6
   on the closed-box fixture: 0.2906 → 0.4005, the last being the artwork's own footprint to four
   places.
2. **The slider jumps when you switch fill type**, since Lasso and Flood now hold different values
   (6 and 2 by default). It is what makes the per-mode default work, but it is visible behaviour.
3. **`fillMode` and `fillGestureIsLasso` can disagree for one gesture** — switching the picker while a
   fill is still adjustable makes the slider write the other mode's value and the live fill stops
   responding until the next tap. The alternative is cancelling the adjustable fill on a mode switch,
   which nobody asked for.
4. **The Select menu's Fill and Clear were changed to match the tool.** The ruling was about the fill
   tool; a worker extended it so "Fill" would not mean two things in one app. Say if you want the
   split back.

## A count that does not tie, worth thirty seconds

The 2026-08-21 handoff said `main` was **1531 / 1527 / 0 / 3**. Both workers, and this session's own
base reading, make it **1531 / 1528 / 0 / 3** — same total, same skips, one more pass. Three readings
against one, so 1528 is almost certainly right and the older figure was a transcription slip, but the
counts are the only signal this repo trusts and the discrepancy is recorded rather than smoothed over.

## Still true, carried forward

The performance programme is **confirmed on hardware** (Release `38e22c6`, iPad 9, seven checks, all
clean — *"17fps is gone… 4k screen displays full 60fps when painting"*, *"leaving the gallery is
instant"*). `PERFORMANCE.md` item 14: the expensive half stays declined, the cheap half — stop writing
and loading a raster tier for cels with no raster content — is queued and correctness-clean. Add Text
Stage 5 (the projective distort) is queued behind it and needs a Release build on the iPad before
merge, like every warp-touching stage. `LASSO_MOVE.md` §5's six owner rulings are settled; ask (a) is
unstarted and must not re-litigate them.

**Open, unruled, carried:** whether a lasso leak deserves its own signal (the collar tint cannot show
one — a leak still paints the outline, so the result is not empty); a superseded lasso no longer
saying "nothing enclosed"; the text tool always editing an existing label rather than placing a new
one beside it; and the toolbar colour swatch changing meaning while a text session is live.

## What this session learned

- **A ruling can be overturned by the owner testing it, one day after they gave it**, and
  *"the previous decision is overruled as I tested it"* is the only evidence that outranks a
  considered ruling. Rewrite the spec; do not leave both readings in it.
- **Ask when the two readings of a piece of feedback are a sign flip.** *"Edge overlap makes the fill
  expand out, not contract inwards"* had two coherent meanings, and the answer to one question was
  neither of the obvious two: the slider's *direction* was never wrong, its *anchor* was.
- **A per-mode default was the difference between shipping the fix and re-shipping the bug.** One
  shared `fillExpand` would have made the lasso's out-of-the-box behaviour the exact seam being fixed.
- **Merging is a re-reading, not a formality** — see above.
- **The Workflow tool's canonical verify fan-out picks its own width.** N tracers times an unknown
  number of findings is a number the first stage chooses after you can no longer see it. Bound the
  second stage or do not have one.
- **Delegate the building and the test run, not the looking.** Eight inline `grep`/`sed` reads had
  located both defects to file:line before any agent was launched; every tracer in the killed
  workflow would have been re-deriving them.
