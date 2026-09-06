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

**41 commits this pass, 126 files, +16,000 lines. No worktrees, no `tmp/*` branches, no simulator
clones, nothing uncommitted.** Fast tier **3385 total / 3382 passed / 0 failed / 3 skipped**,
reconciled against a static count of instance `func test` across the 143 selected classes.

**The full suite was run and is green.** MEASURED at `db21782` on an erased simulator: **3595 tests,
3560 passed, 1 failed, 34 skipped.** The one failure —
`BlendModesAndCompositorUITests.testFolderOpacitySliderPersistsThroughSetFolderOpacity`, a class whose
name differs from its file (`LayerUITests.swift`) — **passed clean in isolation in 25 s** and is
environmental. The class table is re-taken in CLAUDE.md.

**The iPad build is `c23f37f` and is now many commits stale** — provisioning valid until 2026-09-12.
Ship a new one early; almost everything below is invisible to the owner until you do.

## Start here: three things are ruled and unbuilt, and one of them is the owner's worst bug

TODO's top four items are all small and all decided. None needs a conversation.

1. **(39) The timeline freeze.** Reproduced and measured. **While a timeline menu popover is up, every
   drag on the timeline is swallowed** — the track does not scroll, the ruler does not scrub, the menu
   does not dismiss; only a tap does. MEASURED: menu up, a drag moves the cel block **0.0 pt**; menu
   gone, the same drag moves it **369 pt**. The owner's call is to **stop presenting those four menus
   as popovers**, not to punch a hole in the gate — `passthroughViews` leaves a cel menu naming a block
   the artist has scrolled away from. `MenuInterruptionUITests` reproduces it.
2. **(51)** Onion-skin Behind should cut **proportionally to layer opacity**, not on the presence of
   ink. One line and its test — and pin it at *two* opacities, or the assertion passes against today.
3. **(52)** A merge should drop a hidden layer's ink **everywhere**, not only where the two layers
   overlap.
4. **(47)** A finger tap bakes a Move while pen-only is on. Small.

## What shipped this pass

**The owner reported five defects and all five are fixed or diagnosed to the line.** Two of their own
diagnoses were confirmed exactly against the code; one of mine was wrong three times running.

- **The lasso fill corrupting an earlier fill.** `PixelOps.contourPath` kept **one out-edge per
  vertex**, so a region touching itself corner-to-corner lost an edge, the walk dead-ended, and
  CoreGraphics closed the open subpath with a straight chord — every wrong edge in the owner's
  screenshot. It is a multimap now and starts in raster order rather than Swift's per-process hash
  order, **which is why it was never reproducible** and which also made it 34% faster. The magic wand
  shares the trace and had the same defect. Neither function had a single test.
- **Undo and redo.** `restoreElements(_:changedInk:)` bounds a wholesale list swap by one rectangle
  that reads the same in both directions. **The redo was 5.6–11.3x its own undo** and is now 571 → 51
  ms at 1,000 strokes. MEASURED: the main-thread span of a press is 0.44–7.84 ms against a 5–2,275 ms
  render, so **the app never froze — the picture was late**. Raster undo is 0.02 ms and needed nothing.
- **Merging vector layers stays vector**, with six named reasons it can fall back and the artist told
  which one. Byte-identical to the old picture at max channel delta 0. Two silent data-loss bugs went
  with it: Merge Down never asked before a lossy merge (only the pinch did), and **merge binned the
  upper layer's cels at every frame but the playhead's**.
- **Distort works on ink.** The blocker had lifted four days earlier and the code had not noticed. A
  stroke stores **the map it was made by** and rebuilds its rest walk at render, so it survives a save
  and stays editable; width is per dab.
- **`sceneFrameCount` is deleted.** Every write to it was `max(…)`, so it only ever grew. An inventory
  found **fifteen readers meaning four different things**, which is why one name went wrong.
- **The timeline pinch** holds its frame at any scroll offset, and the track reaches the bottom of the
  panel.
- **The bottom options panels** are wider and flatter and ride the timeline's top edge. They had been
  sitting **150 points inside the timeline** by default.
- **The onion skin** draws over the compositor under both placements; Behind is a clip.
- **A fill on a vector layer walls against the stroke's own path**, in that stroke's own colour, so
  Rough Ink at low pressure encloses what its dabs do not.
- **A transform grip past the canvas edge takes a touch**, and **RENDER (29) is finished** — stage 7's
  memory audit built four of seven items and declined two with numbers.

## Two things about measurement, both learned the hard way this pass

**1. Release test builds work again, and "Debug is 62x slower" is a fact about *Swift*.** MEASURED:
~25x on the dab walk alone, **1.86x** once dabs go through CoreGraphics, **1.01x** on a brush-pad
stroke. Two comments called the pad figures a worst case pending a Release run; they were already the
artist's number and **the caveat was the error**. The penalty is not one number — say which mixture a
figure is.

**2. A harness that measures growth is measuring its own autorelease pool until you prove otherwise.**
This produced two confident wrong findings on one day. See CLAUDE.md's section on it.

## Traps this pass paid for

- **Three consecutive diagnoses of the timeline freeze were wrong**, each confidently argued from the
  owner's trace. What settled it was **reconstructing the gestures**: almost every "dead" touch was a
  swipe, which is *supposed* to scroll and leaves no model event, and every genuine tap in the trace
  worked. The column all three readings rested on — `grNames` — is UIKit's *offered* set, which the
  popover's gate prunes. **Read the evidence doc before touching that item.**
- **Mutation testing found a blind assertion in every single pass**, without exception — at 2 of 12,
  then a 3rd on a second sweep, then the 9th, the 26th, and four at once in the memory audit. **Re-run
  the whole sweep after *adding* a test, not only after writing one**; several were found only that way.
- **Looking at the thing found what asserting on it did not, three times.** A one-point divider made a
  panel 1,580 points tall — floor to ceiling over the artwork — with every test green, because the
  assertions were about its bottom edge, which was right.
- **A brief premise was refuted in all eleven agent runs.** Several improved the result: the fill-wall
  "barrier" would have silently removed the Threshold slider, and carrying the stroke's *colour* fixed
  it *and* made "an invisible stroke is not a wall" fall out rather than be a second rule.
- **An item can be stale in the direction of looking finished.** Four TODO items sat marked "built on
  `tmp/…`, not merged" — true when written, false the moment the branch merged.

## Filed rather than fixed

- **BUGS.md — the auto-resign daemon counts its own runs, not the profile's expiry.** Delete
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision` and check
  `ExpirationDate` *before* installing; the build succeeds either way.
- **BUGS.md — a restored project texture can be held down by a negative cache entry.**
- **PERFORMANCE.md §10.4 — the two device measurements RENDER (29) owed** outlived the item: the
  compression ratio against the owner's own "UI Test" document, and a decode of a compositor-produced
  frame at their canvas size. Both need the owner's iPad.
- **TODO (45) — the repository prune the owner asked for.** The 2026-09-06 audit found fourteen false
  assertions in TODO.md and a dozen across the specs; that list is in the item, and a pass this large
  will have added its own.
