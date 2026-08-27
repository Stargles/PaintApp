# Handoff — 2026-08-26 (session 68)

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md, TODO.md and ARCHITECTURE_REVIEW.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. **The Opus cap is situational — I set it in both directions and you hold whichever I said
last.** I lifted it on 2026-08-26 ("you have a lot of budget"); four days earlier I had capped it at
three. Whatever the cap, `tools/simlock.sh` allows two concurrent `xcodebuild` runs, so a wide fan-out
should be reading or designing, not queueing for the same two simulators.

`main` is at 1709 fast-tier tests (1706 passed, 0 failed, 3 skipped), nothing in flight, no worktrees,
no `tmp/*` branches. **`main` has been pushed to `origin/main` — the remote is live now**, which it
was not for the previous seven sessions.

**The Move-tool expansion is the live thread and it is half built.** Stages 1 and 2 are on my iPad;
stage 3 is designed but not started, and the design is in the git history of this session — find it
before re-deriving it. The order I agreed:
  1. ~~the lassoed piece's rotate/scale nodes~~ — done
  2. ~~the Move menu~~ — done
  3. **Freeform + the yellow box-only knob + placed images holding a stretched shape** — designed,
     not started. Splits into three branches; 3a ships a working Freeform with **no renderer change**.
  4. ~~the shared `Homography` solver~~ — done, as ADD_TEXT Stage 5
  5. **Distort on both tiers**, consuming that solver, with my ink-deformation toggle defaulting off

Start by asking me what I found on the device. Four things are on it and none has been seen by an eye:
1. **Lasso a region on a vector layer and tap Move** — corner nodes and the green knob; the thing to
   check is that it *bakes* looking like it did while I dragged.
2. **The Move menu** — it now appears for a lassoed piece; Rotate 45°, Reset, no Warp, and the Select
   menu steps aside while anything floats.
3. **Text → Corners → Distort** — drag one corner and the words should lie down in perspective.
4. **Mirror with an image or text in the selection** — it should grey out and say why.

Then the two eyes-on judgements ADD_TEXT.md Stage 5 explicitly owes, which no test can make:
  - **Is the live preview visibly different from the baked result** on a strongly foreshortened quad?
    Measured at 7.63/255 mean channel difference on the worst trapezoid, ~15x the mild cases — but
    that figure came from an in-process software path, so it is a floor and a change detector, not
    the device number. ADD_TEXT.md §4: *"Do not let 'gated on it being visible' become 'never
    looked.'"*
  - **Does the resized-along-the-wall edge grip feel right at a fingertip?**

Three behaviour questions still waiting on my eye, not on another run:
  - **Cut eraser across a line thicker than the eraser now visibly does nothing.** It always did
    nothing — I used to find out on lift. Leave it, refuse the cut, or widen it?
  - **A line crossing the cut can flicker** during the drag, under 10% of what the cut removes.
    Fixing it exactly costs the ~95 ms that makes To Cross expensive. Only if I see it.
  - **A fill chunk dropped on blank paper stays a fill** — literally what I asked for, may still read
    as a mistake on real artwork.

Two questions still owed, unchanged for days — ask when they block work:
  - Save semantics when a project loaded with something unreadable: may saving overwrite the good
    original, refuse, or prompt?  (A branch shipped "prompt once, then remember"; confirm it.)
  - Which faces belong in the font picker's favourites strip.
```

---

## State

`main` = `db05296` plus doc commits, **pushed to `origin/main`.** Clean tree, no worktrees, no
`tmp/*` branches, no simulator clones.

Every merge verified as its own run: 1655 → 1666 → 1709, each delta matched against a static
`func test` count on the merged tree.

## What landed

Eight changes. TODO.md's "Done this pass" has the full writeups; what follows is only what a later
reader would otherwise rediscover the hard way.

**Three separate pieces of work turned out to be one, and the documents knew it before we did.** The
owner asked for a Move Distort, ruled it must wait until text could warp, and doubted the
perspective-text requirement had ever been recorded. It had — ADD_TEXT.md's **Stage 5 *is* the
projective distort**, Stage 4 had shipped leaving a clean seam, and **Stage 6 already listed
converting `FloatingPiece`'s `.distort` onto that same solver.** `TransformMode` likewise already
carried freeform/uniform/distort/warp. **Read the specs before scoping: two of three modes existed,
and the "blocking dependency" was the correct build order.**

**Verify the premise you hand a worker; twice this pass the brief was wrong and a measurement caught
it.** Stage 1 was told scaling a stroke's `size` alongside its geometry was exact — true, confirmed to
**1.3e-13 pt** over 480 cases, but the same sweep showed the spacing floor binds below **20 pt (Hard
Round) / 33 pt (Pen)**, not just on hairlines. Stage 2 was warned Mirror would trip the similarity
assert — a reflection *passes* it; what breaks is `atan2` and text corner order.

**The reviewers earned their cost on the warp.** One rebuilt the Heckbert solve independently and ran
the real kernel against the real reference on a GPU without producing a wrong pixel — then found a
**blocking** memory bug ADD_TEXT.md had *predicted* and the stage shipped without: the bake rendered
into the warped quad's unbounded box, so one off-canvas corner allocated hundreds of MB against a
192 MiB budget. And edge grips **silently flattened** a perspective box — a 49 pt far-corner jump with
no drag at all.

**An agent refused a test it was told to write, and was right.** Asked to pin the `w > 0` validity term
with a reviewer-supplied quad, it found that quad *valid*, swept 2,000,000 random quads plus a 41×41
grid, found **no** non-convex quad passing the convexity test, pinned the theorem instead, and
reported plainly that deleting the clause *"still leaves the suite green, and always will."*

**The owner corrected our own evidence in one sentence.** `CanvasTouchOwner`'s enumeration reported
1,678 double-claim combinations; the owner pointed out that a shape bakes when you pick the fill tool,
so many are unreachable. True — `commitAllInteractiveState()` runs before every tool switch. **The
count was inflated; the Drawing Guide rows are the reachable core**, and `isReachable` is still the
untested thing deciding what gets tested.

## Carried, deliberately not done

- **Move stage 3 and Distort** — see the paste block. Stage 3's design named two traps worth keeping:
  `allowedHandles` defaults to *all cases*, so new handles switch themselves on everywhere including
  the whole-layer box; and `ImageRef` uses synthesized `Codable`, so adding non-optional fields breaks
  every existing document.
- **`TextFrame.homography` has no validity check on the decode path** — a saved document carrying a
  non-convex quad is warped rather than refused. A behaviour change, so it was left.
- **The `.projective` vector flatten re-rasterises per invalidation, not per commit** (BUGS.md). The
  memo is blocked on `TextRecipe` being `Equatable` but not `Hashable`.
- **The raster Move's undo half** of ruling 4, and **PERFORMANCE.md item 14's expensive half** —
  unchanged from the last handoff.
- **Two owner thoughts, recorded as thoughts** in TODO.md with numbers measured off their device:
  narrower sample storage (**89 bytes/sample on disk vs 24 in memory**; the win is the encoding, and
  fixed-point in memory would fight the absolute-mapping discipline) and **Oklab**, which is a quality
  argument, not a memory one — colour is per stroke, not per sample.

## Traps this pass hit, for the next one

- **`CoreDeviceError 1011` has two causes.** `available (paired)` is a stale tunnel that
  `devicectl device info details` fixes; `unavailable` is a device nothing on this Mac can reach. The
  documented remedy "works" in both cases because `info details` answers from cache. Now in CLAUDE.md.
- **An agent that dies on a session limit leaves its work on disk.** Recover it — read the diff, work
  out what is done, and continue. One died mid-fix here and its work was parked as a WIP commit (this
  repo bans `git stash`) and finished by its successor.
- **`strings` finds enum raw values, not Swift function names.** A check that "the binary contains the
  new symbol" using `strings` proves nothing; `nm` does. Nearly shipped a stale build on that basis.

## Still true, carried forward

`LASSO_MOVE.md` §5 now carries **fifteen** owner rulings; do not re-litigate any. ADD_TEXT.md Stage 5
is shipped and Stage 6 is the deferred-polish list. `ARCHITECTURE_REVIEW.md`'s finding 1 is closed;
findings 2–4 (eleven hand-written cache keys, silent save-failure returns, a layer property living in
four hand-kept structs) are open and unruled.
