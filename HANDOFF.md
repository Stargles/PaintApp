# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks **in queue order — the top of the list is what to do next**;
[BUGS.md](BUGS.md) is what we find.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**No branches, no worktrees, stash empty, no simulator debris.** 7 commits this pass.

**Fast tier: 3533 total / 3533 passed / 0 failed / 3 skipped**, Debug *and* Release, reconciled at each
step against the baseline it started from (3516 → 3518 → 3533, and each increment is exactly the tests
added).

**No full suite ran this pass, and that matters more than usual.** Two of the three changes are on the
render path and one of them touches the onion skin, the gallery tile and the `RenderResolution` knob —
all XCUITest territory. **The fast tier selects logic suites by filename and runs no XCUITest**, so
green in both configurations is not evidence about any of it. **A full run is owed before the next
merge.** CLAUDE.md carries the class table from the last one.

**A Release build of `b9f343c` is installed on the owner's iPad** (2026-09-08), for them to check the
two fixes below on the document that produced them.

## What shipped this pass

Both were owner bug reports with an `ActionRecorder` trace pulled off their iPad, and **neither was
what it looked like**. The traces are the reason; reach for the recorder before trying to reproduce a
device-only report in a simulator.

**The Move box baked when a resize node was let go** — and the resize path is innocent.
`handleMoveBoxCommit` asked `canvasChrome(at:)` about `recognizer.location(in:)`, which at `.ended` is
where the finger *left*. Two correct things compose into the defect: `uniformlyScaled(to:)` takes the
ratio of two radii and discards the drag's angle, so the box's corner is redrawn along the touch-down
bearing and finger and corner then sit on one circle about the anchor — every point of which but the
four corners is outside the box; and a `UITapGestureRecognizer` does not fail on movement, so a corner
drag arrives at the commit handler as an ordinary tap. The fix is the **rule**, not the site: a handler
asking *"was this touch on X?"* asks at touch-down. `FloatingPieceOverlayView.handleTapOutside` had it
identically against the raster box and is fixed with it.

**The undo lag was two independent O(canvas-area) main-thread costs, and the owner's padding theory was
wrong in a useful way.** Nothing on the path reads `canvasPadding`; padding was only their lever for
reaching `maxCanvasExtent`, and `Test1` is 6000² exactly — so the fixes help at any size.
* `VectorCanvas.lock` was held across the rasterize, so `restoreElements`, which undo reaches
  synchronously on main, blocked on a background render. MEASURED **25.57 → 1.70 ms** at 6000², with
  both renders at 29.7 ms, so the rows differ by where the waiting went rather than by how much work
  there was.
* The debounced thumbnail regen asked the vector tier for a **canvas-sized** image and shrank it into a
  480-point box, on the main thread, 400 ms after every stroke and every undo. MEASURED **34.1 →
  1.08 ms** at 6000². The same full-canvas-then-shrink shape sat behind the **onion skin**, the
  **gallery tile** and the **`RenderResolution` knob** — which therefore reduced the composite and not
  the work under it.

## Start here

**(56), (57), (58) — the top of the queue, and (58) is nearly free.**

**(58) first, because the owner's own hypothesis may already have closed it**: playback on `Test1` does
not hold 24 fps, *"sometimes taking 313ms per frame... even after hiding all layers"*. That report
predates the thumbnail work merging. **Re-measure before building anything.** If it survives, the
reading is worth more than the number: every layer hidden and still 313 ms a frame means the cost is
not in compositing content, so it is per-frame work scaling with canvas area rather than with what is
on the canvas.

**(56) is not finished and the honest remainder is one sentence**: the stalls in the owner's trace are
on `touch began` lines, which arrive *before* that tap's own undo work, so the main thread was already
busy from the previous undo. The thumbnail debounce fits the timing and is now fixed — but nobody has
re-measured the trace against the fix, and until someone does, the attribution is reasoning.

**The strokes that vanish are already filed and are the same root cause seen from a third door.**
BUGS.md's *"Starting a stroke before the last one has rendered leaves the last one off screen"*: the
base slot holds the picture from before stroke *n*, the new stroke has taken the scratch overlay, so
*n* is on screen nowhere. Its own text says the window *"scales with canvas area... so a bigger canvas
widens it again"*, and 6000² is 17x the baseline's pixels.

**All three converge on one thing: a small edit costs the whole canvas.** `renderLocalContent` builds a
`UIGraphicsImageRenderer` at the canvas's size on every walk — 144 MB at 6000² — and `Damage.region`
bounds which elements are *stamped*, never the allocation. **The feasibility is written up** (see the
thumbnail pass's report in `git log` and BUGS.md): `cachedImage` stops being one `UIImage`, 23 call
sites across 12 files, and it collides with RENDER.md §3.8's trap that three memos are keyed on buffer
*size*. **That is an owner decision, not a session's to take** — put the cost in front of them.

After that, in queue order: **(36)**'s one remaining box, **(41)**, then **(42)**.

## Waiting on the owner

- **Whether to spend the render-output rewrite above.** It is the root cause of (56), (58) and the
  vanishing strokes, and it is the largest single item in the file.
- **(21) stage 7's other half.** §5 asks for one mechanism on two surfaces and only the slider is built;
  the Move box needs rulings on resampling and tolerance for a **quad**, which `ValueRecording` cannot
  express. Stage 10 sits on a whole stage 7.
- **(21) animation-group membership** — retagging, which changes the meaning of every key on both
  groups' tracks. The refusal half shipped 2026-09-03 (§2.29).
- **(22)** and **(10)** deprioritised; **(37)**'s importer dropped.
- **BUGS.md's five remaining `.popover`s** have the timeline's swallow-every-drag defect. Three are
  colour pickers whose chrome would visibly change — the owner's call, as it was for the timeline's four.
- **The pencil half of (47)** cannot be driven by any test here: XCUITest cannot synthesise a pencil.
  **Nor can it reach the Move-box bake fixed this pass** — see `MoveBoxCommitUITests`, which records the
  five runs that established it so nobody spends them again.
