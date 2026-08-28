# Handoff — 2026-08-27 (session 73)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. Fast tier **1813 / 1810 / 0 / 3**; the full suite ran on this tree at **1932 / 1925 / 1 / 6**,
the one red confirmed environmental by an isolated re-run. **No branches in flight, one worktree, clean tree.**

**1. Build item (14), the reversible Move.** It is the head of the queue now that (8) is merged, and
   (8) is what it was waiting for: the quantiser exists, so "hold the transform in doubles until an
   explicit bake" finally has a thing to be reversible *against*. The owner named it as the follow-up
   to (12) stage 1 in their own words. Two artist-visible residues are what it has to fix, and both
   are recorded on the item: `BrushStamper.stampSpacing`'s 1 pt absolute floor (a stroke shrunk below
   it and regrown comes back with a different dab count), and the Move box inflating monotonically
   because the float's box is a geometric AABB of moved ink. The *geometry* half of the objection is
   already dead by measurement — 100 shrink-to-2%-and-regrow cycles drift 6.0e-11 pt.
   **Item (8) is done and closes one worry (14) might otherwise have inherited**: MEASURED, 5,000
   samples through a hundred consecutive saves drift **0.0 pt**, and through six canvas-padding
   changes **0.0 pt**. Storage is not a source of drift; only `stampSpacing` and the box are.

**2. Then (9), the canvas resize.** It is genuinely independent of everything else now — (8) settled
   CANVAS_RESIZE.md §6's first question, and the payload records the origin it was quantised about, so
   **a resize re-encodes nothing for correctness**. What (9) still needs before it is built is §6's
   *other four* questions, which are the owner's: what the width/height field means, what undo does
   over raster content, fit-only or fit-and-fill, and what the dialog does about a size that would
   blow the compositor's admission gate.

**3. Four things are still on the owner's iPad awaiting a look, none of them blocking.** The build
   there is `fe5e716`, now several commits behind; none of what has landed since is visible.
   - **Sobel is bright edges on opaque black now**, with no control. If it still reads grey, that is a
     different bug from the one fixed and it matters.
   - **An adjustment layer should grade blank paper**, and a blend mode should blend against it. This
     is the owner's original report and the whole point of that pass.
   - **Draw across the canvas after shrinking a whole vector cel** — the ink loss, still unconfirmed.
   - **Move with no lasso shows a Move bar**, where there was never one.

**4. (18) and (10) are still open** and unchanged. (18) is the bottom-bar height: the obvious
   implementation was built, measured and reverted, the candidate next approach is recorded on
   `maxRowsHeight`, and **a screenshot is its acceptance test, not a frame comparison**. (10) is
   Oklab, and the recommendation is written into the item: **not storage, not the compositor —
   interpolation, and linear light first**; render the A/B before building stage A.

**Do not re-litigate**: LASSO_MOVE.md §5's eighteen rulings; EFFECT_BACKDROP.md §5's four and §2.1's
three-pass onion-skin ruling; Sobel's deleted ink control; (8)'s five attached rulings, all of which
shipped intact.
```

---

## State

`main` = the item (8) merge. **Fast tier 1813 / 1810 / 0 / 3**, measured on the merged tree — +15 on
the 1798 / 1795 / 0 / 3 that session 72 closed on, which is exactly the new test file, so nothing
stopped running. No branches, no worktrees but the main one, no simulator clones.

**The full suite was run on the merge** — the first since `dee77ff`, seven merges back:
**1932 / 1925 / 1 / 6**, and the one red was environmental. `InterpolationWorkflowUITests.testInterpolateModeEndToEndFromGestureToScrub`
(the 170-second test that is the suite's whole critical path) failed with `afterCommit.isEmpty` while
its own diagnostic sweep printed ink; it passes clean in isolation, and it touches no save or reload,
so item (8)'s codec never runs inside it. Not a finding and it needs no fix.

## What landed

**TODO item (8), the fixed-point sample coordinate.** A persisted `VectorSample` is a signed 16-bit
quarter-pixel offset from a stored origin plus 8 bits of pressure — 40 bits, base64'd into one JSON
string. In memory it is still three `CGFloat`, which is what the ruling asked for, so the whole win is
on disk. MEASURED: **7.10 bytes a sample on the wire** against the ~77 TODO.md measures in the owner's
own `Untitled.paintproj` — **~11x**.

**The decision the build added, and the one to carry forward: the quantisation origin is written into
the payload.** The ruling puts it at the centre of the current canvas, which is what buys the sign bit
for free. But an origin *implied* by the reader's canvas size is an origin a caller can get wrong, and
getting it wrong shifts every coordinate by half a canvas — silently, reading as success. Writing it
costs ~24 bytes a stroke against ~380 a stroke saved, and in exchange **a payload cannot be decoded
wrong**: `init(from:)` needs no context at all, and a resize is free to leave old cels alone.

Encode still needs the origin and `JSONEncoder.userInfo` is the only channel `Codable` offers, so the
guard is **behavioural rather than a source scan**: `testInkNearTheEdgeOfAWideCanvasSurvivesASaveAndReload`
saves ink at x=11900 on a 12,000-point canvas, which only survives if `ProjectStore` passed the origin.
A forgotten origin costs addressable range, never a wrong coordinate.

Two things rode along, both on the path:

- **`ProjectStore.writeCel`'s `json()` stopped swallowing encode failures with `try?`.** A throwing
  encode used to leave `vectorFileName` nil and save the cel **empty** — the same silent-loss shape
  `VectorCanvasData`'s per-element decode was built to end, reached from the other direction.
- **BUGS.md gained the matching defect on the decode side**, found while reading that function: a cel's
  interpolation recipe is read with `try?`, so a recipe file that is present and damaged vanishes with
  no log line and no `ProjectLoadDamage` count — and the next save rewrites the manifest without the
  file name, which makes it permanent. The vector payload twenty lines above counts and logs every
  unreadable element. The missing-*file* policy beside it is correct and is not what this disputes.

## The pattern worth carrying

**The adversarial pass earned its cost on a test, not on the code.** Four lenses attacked the diff;
the arithmetic and the wiring came back clean and the one finding that survived refutation was in a
test *the change itself had edited*. 8-bit pressure legitimately broke a bit-exact `==` after a round
trip, so that assertion was restated as the fixed point the format is — and the restatement left **no
assertion at all comparing a decoded coordinate to the original**, so the test would have passed
against a codec that zeroed every coordinate. That is the third instance this week of a green test
that had stopped testing, and the first one reached by *fixing* a test rather than by changing what it
measured. When a lossy format makes an equality assertion fail, the reflex is to widen the tolerance;
the trap is widening it all the way to nothing.

**And the discovery pass was worth more than the build.** Five parallel readers ahead of a line of code
established that only two Codable trees reach disk with samples in them, that there are exactly four
production call sites, that no hand-written legacy sample JSON exists anywhere in the suite — which is
what made "no migration" cheap and certain rather than a hope — and that the UI-test target compiles
app sources **by explicit path**, so putting the codec in `ShapeGeometry.swift` avoided a `project.pbxproj`
edit for app code entirely. Each of those changed the design before it was written.

## Still open, unchanged

`ARCHITECTURE_REVIEW.md` findings 2-4 (eleven hand-written cache keys, silent save-failure returns, a
layer property in four hand-kept structs) are open and unruled. BUGS.md carries the raster-storage
entry (a persistent buffer at 16383² is ~1.02 GB and goes through no budget at all), the new
interpolation-recipe entry, the unclamped-zoom coordinate — **which item (8) makes concrete rather than
theoretical: a screen-wide drag at minimum zoom now saturates against the storage boundary instead of
wandering off into a `Double`** — `TextFrame.homography` decoding with no validity check, the
`.projective` re-rasterise per invalidation, and PERFORMANCE.md item 14's expensive half.

Two behaviour questions have been owed for days and nobody is blocked on them: save semantics when a
project loaded with something unreadable (may saving overwrite the good original, refuse, or prompt? a
branch shipped "prompt once, then remember" — confirm it), and which faces belong in the font picker's
favourites strip.

Four judgement calls wait on real artwork, none of them defects: the Cut eraser across a line thicker
than the eraser, a crossing line that can flicker during a cut drag (both BUGS.md), a fill chunk dropped
on blank paper staying a fill (LASSO_MOVE.md §5), and a Freeform-stretched text box draggable smaller
than its own text.

**And one standing permission worth re-reading before it is relied on again.** TODO.md's "everything on
the ipad right now is expendable" is what made item (8) cheap — no migration, no decode defaults, no
appearance warnings. It lapses the day the owner starts keeping real artwork in the app. Item (8) shipped
three lines that tolerate the old sample shape anyway, which buys a little slack; nothing else does.
