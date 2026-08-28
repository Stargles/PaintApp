# Handoff — 2026-08-28 (session 73)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. Fast tier **1839 / 1836 / 0 / 3**. **Items (8) and (14) are both merged**; no branches in
flight, one worktree, clean tree. The last full suite was at the (8) merge (1932 / 1925 / 1 / 6, the
one red environmental); (14) added nine fast-tier tests and no full run since.

**1. Build Move stage 3b — a second knob that turns the handle box alone.** TODO item (20). The
   owner approved it on 2026-08-27 and **it is fully scoped**: LASSO_MOVE.md §5.19–21 are the three
   rulings, and none of them is open.
   - **The box never tilts by itself.** *"leave it straight up and down. Thats what the orange rotate
     node is for, rotating the box only"* — so the re-lift inflation of the box on already-tilted ink
     is **accepted**, not a defect, and hand-fitting is the cure. The knob the owner named **does not
     exist**: today's turns box and content together.
   - **A Freeform stretch on a hand-turned box stores the axis it was made about** — the owner chose
     to build it after pushing back, and the arithmetic is why it is not a hack: `R(ρ)·S·R(−φ)` is the
     SVD of a general 2×2, so `2 translation + 2 angles + 2 scales = 6` is *exactly* a general affine.
     The second angle completes the representation; nothing is left over, and it is still far short of
     Distort's 8.
   - **The box angle is chrome and never enters the geometry map.** `VectorFloat`'s lift invariant
     `VectorCanvas.affine(from: frame.transform, pivot:) == baseTransform` depends on that. At lift
     both angles are zero and the map is the identity.
   - **Turning the box costs no undo step** — free, like zooming, and an *exception* to §5.5 rather
     than an amendment: a box-only turn moves no ink, and as the first act after a lasso lift its undo
     would rejoin the cut stroke and dismiss the float (§5.8).
   - **Disclose, do not discover**: turning the box *after* a Freeform stretch cannot leave the ink
     perfectly still, because the stretch axes are what turn.
   **Two things are still open and neither blocks the build**: where the second knob sits on the box,
   and what colour it is. LASSO_MOVE.md says yellow, the owner said orange, and **orange already means
   "distort corner" on a text box** — put the pair to them before drawing it.

**2. Then (9), the canvas resize.** Genuinely independent of everything else: (8) settled
   CANVAS_RESIZE.md §6's first question and each payload records the origin it was quantised about, so
   **a resize re-encodes nothing for correctness**. What it still needs is §6's *other four*
   questions, all the owner's: what the width/height field means (artwork rect or padded buffer),
   what undo does over raster content, fit-only or fit-and-fill, and what the dialog does about a size
   that would blow the compositor's admission gate.

**3. Four things are still on the owner's iPad awaiting a look, none of them blocking.** The build
   there is `fe5e716` and is now far behind; nothing since is visible, including everything (8) and
   (14) shipped.
   - **Sobel is bright edges on opaque black now**, with no control. If it still reads grey, that is a
     different bug from the one fixed and it matters.
   - **An adjustment layer should grade blank paper**, and a blend mode should blend against it. This
     is the owner's original report and the whole point of that pass.
   - **Draw across the canvas after shrinking a whole vector cel** — the ink loss, still unconfirmed.
   - **Move with no lasso shows a Move bar**, where there was never one.
   Two new controls will be on the next build they take: **Keep Full Precision** on the Move bar and
   **Bake Precise Strokes** in Actions. Neither is a question — they are (14) — but they are the first
   thing on that bar that is a *preference* rather than a verb.

**4. (18) and (10) are still open** and unchanged. (18) is the bottom-bar height: the obvious
   implementation was built, measured and reverted, the candidate next approach is recorded on
   `maxRowsHeight`, and **a screenshot is its acceptance test, not a frame comparison**. (10) is
   Oklab, and the recommendation is written into the item: **not storage, not the compositor —
   interpolation, and linear light first**; render the A/B before building stage A.

**Do not re-litigate**: LASSO_MOVE.md §5's twenty-one rulings — §5.19–21 are the newest and they are
what stage 3b is built from; EFFECT_BACKDROP.md §5's four and §2.1's three-pass onion-skin ruling;
Sobel's deleted ink control; (8)'s five attached rulings and (14)'s choice of float32 over float64.
```

---

## State

`main` = the item (14) merge. **Fast tier 1839 / 1836 / 0 / 3** — +9 on the 1816 the scoping commit
left, which is exactly the nine tests added, so nothing stopped running. No branches, no worktrees but
the main one, no simulator clones. No `project.pbxproj` change in either commit: everything went into
existing test files.

**The last full suite was the one run at the (8) merge**: 1932 / 1925 / 1 / 6, the single red
(`InterpolationWorkflowUITests.testInterpolateModeEndToEndFromGestureToScrub`) confirmed environmental
by an isolated re-run. (14) has not had one, and it is the phase boundary that is owed it.

## What landed

**TODO item (14) — and three quarters of its brief was wrong, which is the finding.** The item asked
for a Move whose transform is held in doubles until an explicit bake. The doubles half **already
held**: every nudge maps `float.liftedInside`, the elements exactly as the lift produced them, so a
drag is an absolute map from the lift and there is no term for error to accumulate in. Both named
residues were misdiagnosed too — `stampSpacing`'s 1 pt floor binds at native sizes with no transform
near it, and the Move box does not inflate monotonically (it tracks a fresh lift's tilt in **both**
directions). All three corrections are now executable rather than assertions in a document.

**What survived was a defect the ask had not named: scale across a *save*.** The quantisation grid is
a fixed size in canvas points, so a stroke shrunk before a save has fewer usable bits and comes back
coarse when it is grown again. MEASURED, worst sample over 200: **0.33 pt at 50%, 1.75 pt at 10%,
8.57 pt at 2%**. Rotation and translation are already exact; it only shows after a reopen, because
memory never rounds.

**The cure is a second `PackedSampleRun` layout — `Float32` x, `Float32` y, `UInt8` pressure — behind
a `"p":"f32"` wire key written only in that mode**, so an ordinary stroke's payload is byte-for-byte
what it was. MEASURED **12.18 bytes a sample against 7.10, 1.72x**, taking those three errors to
**3.3e-5 / 3.9e-5 / 5.0e-5 pt**. The owner chose it over `Float64` shown both — doubles-as-bytes is
3.2x, doubles-as-JSON-text 8.5x, and the extra nine decimal places are below anything that renders.
`CanvasManager.preserveMovePrecision` is a **Keep Full Precision** toggle on the Move bar (off by
default); Actions gains **Bake Precise Strokes**.

Three decisions inside it are the ones to carry, because each had a plausible wrong answer:

- **`VectorStroke.precise` is derived from the wire form, not persisted beside it** — a stored copy
  can go stale, which is the argument `Lattice`'s own persistence extension already makes.
- **The flag is set inside `applyToVectorFloat`'s map, not at the commit.** The commit records
  nothing, so a flag set there would be a document change no undo step carries: undo would give back
  the geometry and leave the stroke writing nine bytes a sample for ever.
- **The bake had no precedent to copy and the two obvious ones are traps.** `flipCanvas` and
  `setCanvasPadding` are not undoable at all (`history.removeAll()`), and `withStructureUndo` cannot
  carry it either — `StructureSnapshot` copies the `Layer` structs but `Cel.vector` is a **class
  reference**, so the snapshot would share the very array the bake mutates.

**And one silence was closed rather than accepted.** A NaN coordinate landed at the origin
**unreported** on precisely the strokes the artist asked to keep exactly, because `clampedCount` means
"flattened onto the boundary" and float32 has no boundary. `nonFiniteCount` now counts it in both
layouts: a saturation is storage declining to hold ink, a NaN is a defect upstream, and the mode that
cannot notice the first must still notice the second.

**Item (8) merged earlier in this session as `e277f82`** — the fixed-point sample coordinate, 7.10
bytes a sample on the wire against ~77, with the quantisation origin written into each payload so a
payload cannot be decoded wrong.

## The pattern worth carrying

**Scope the item before scheduling it, and treat its brief as a hypothesis.** (14) was queued as a
build for weeks on three premises, and one survived. What made the difference was that the scoping
pass turned each correction into a *test* rather than a paragraph — including the number nobody
predicted: the tilted box measures **76.57, not 120/√2 = 84.85**, because `localBounds(of:)` takes the
AABB of the samples and pads by `stampRadius` afterwards, so the padding is re-applied axis-aligned at
every lift instead of travelling round with the ink. The shortfall is exactly `2·radius·(√2 − 1) =
8.284`, and "allow tolerance for the padding" would have hidden it — which is why it is pinned at 1e-4.

## Still open, unchanged

`ARCHITECTURE_REVIEW.md` findings 2-4 (eleven hand-written cache keys, silent save-failure returns, a
layer property in four hand-kept structs) are open and unruled. BUGS.md carries the raster-storage
entry (a persistent buffer at the maximum canvas is ~1.02 GB and goes through no budget at all), the
interpolation-recipe `try?` entry, the unclamped-zoom coordinate — **which (14) splits in two: an
ordinary stroke now saturates against the storage boundary and says so, and a *precise* one does not
clamp at all and wanders as a `Float32`** — `TextFrame.homography` decoding with no validity check,
the `.projective` re-rasterise per invalidation, and PERFORMANCE.md item 14's expensive half.

Two behaviour questions have been owed for days and nobody is blocked on them: save semantics when a
project loaded with something unreadable (may saving overwrite the good original, refuse, or prompt? a
branch shipped "prompt once, then remember" — confirm it), and which faces belong in the font picker's
favourites strip.

Four judgement calls wait on real artwork, none of them defects: the Cut eraser across a line thicker
than the eraser, a crossing line that can flicker during a cut drag (both BUGS.md), a fill chunk
dropped on blank paper staying a fill (LASSO_MOVE.md §5), and a Freeform-stretched text box draggable
smaller than its own text.

**And one standing permission worth re-reading before it is relied on again.** TODO.md's "everything on
the ipad right now is expendable" is what made both (8) and (14) cheap — no migration, no decode
defaults, no appearance warnings, and in (14)'s case no second wire key to negotiate. It lapses the day
the owner starts keeping real artwork in the app. (8) shipped three lines that tolerate the old sample
shape, which buys a little slack; nothing else does.
