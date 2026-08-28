# Handoff — 2026-08-28 (session 73)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is `5b5577e`. **Fast tier 1863 / 1860 / 0 / 3. FULL SUITE RUN AND CLEAN at this exact
commit: 1982 / 1975 / 1 / 6, and the one red passed clean in isolation** —
`InterpolationWorkflowUITests.testInterpolateModeEndToEndFromGestureToScrub`, environmental, no fix
owed. **No branches in flight, one worktree, clean tree.**

**1. Item (9), canvas resize — the last of the five-item storage refit, and it is BLOCKED on the
   owner.** [CANVAS_RESIZE.md](CANVAS_RESIZE.md) is written; its **§6 is the questions the owner must
   answer before a line is built**, chiefly what the width/height field means and what undo does over
   raster content. §6's encoding question is already answered by (8). **Ask these first** — do not
   start building and discover them.
   §0 is why this is cheaper than it looks: `setCanvasPadding` is already a whole-document
   crop/expand and `VectorCanvas.mapping(_:throughSimilarity:)` is already the exact vector scaler.
   And a payload now carries the origin it was quantised about, so an unresaved cel stays readable
   whatever the canvas becomes — a resize re-encodes nothing.

**2. If the owner is not available, (18) or (10) are unblocked.**
   (18) is the bottom-bar height: the obvious implementation was built, measured and reverted, and
   the candidate next approach is recorded on `maxRowsHeight`. **A screenshot is its acceptance test,
   not a frame comparison** — an XCUITest passed against the broken build. Note the Move bar gained a
   two-line toggle this pass, though (18)'s scope is `EffectSettingsBar` alone.
   (10) is Oklab, and the recommendation is in the item: **not storage, not the compositor —
   interpolation, and linear light first.** Stage A's premise is argued and **not yet seen**; render
   the A/B before building it.

**3. Five things are on the owner's iPad awaiting a look.** The build there is old — it predates
   items (8) and (14) and all of stage 3b. **Offer to deploy before asking about any of them**, from
   the worktree, not `deploy.sh` (it pulls `main` and never ships branch work).
   - **Sobel is bright edges on opaque black now.** If it still reads grey, that is a different bug.
   - **An adjustment layer should grade blank paper**, and a blend mode should blend against it.
   - **Draw across the canvas after shrinking a whole vector cel** — the ink loss, still unconfirmed.
   - **Move with no lasso shows a Move bar**, where there was never one.
   - **NEW, and worth watching them use**: the yellow box knob, "Keep Full Precision", and
     "Bake Precise Strokes". A *second* stretch about a different axis genuinely rotates the ink, so
     the corner does not track the finger exactly — honest, but it reads as a bug the first time.

**Do not re-litigate**: LASSO_MOVE.md §5's **twenty-two** rulings (§5.19-22 are from 2026-08-28);
(8)'s five attached rulings; EFFECT_BACKDROP.md §5's four and §2.1's three-pass onion-skin ruling;
Sobel's deleted ink control.

**Two traps this pass paid for, both now in CLAUDE.md.** A worker's worktree is a *workbench*, not a
deliverable — harvest its **commits**, and wait for the *completion notification*, not a finished test
run. And a **green** check expires: the grep that verified a tree was true when it ran and false four
minutes later, and `main` shipped a deliberate mutation-test defect because of it.
```

---

## State

`main` = `5b5577e`. **Fast tier 1863 / 1860 / 0 / 3.** **The full suite was run at this exact commit**:
1982 / 1975 / 1 / 6, and the single red — `InterpolationWorkflowUITests.testInterpolateModeEndToEndFromGestureToScrub`
— passed clean on an isolated re-run against an erased simulator. Environmental. No branches, no
worktrees but the main one, no clones.

## What landed

Four merges, and three of them are one owner ask followed to the end.

- **Item (8), fixed-point samples** (`e277f82`). A persisted `VectorSample` is 16 bits an axis at
  quarter-pixel about a stored origin plus 8 bits of pressure — 5 bytes, base64'd, **~11x smaller on
  disk**. The origin is written into the payload rather than implied by the reader's canvas, which is
  what makes a payload impossible to decode wrong and leaves a resize re-encoding nothing.
- **Item (14), precise strokes** (`7eef540`). The owner found the defect (8) leaves behind, and it is
  about **scale**: the grid is a fixed size in canvas points, so a stroke shrunk before a save has
  fewer usable bits. MEASURED, worst sample, shrink/store/reopen/regrow: **0.33 pt at 50%, 1.75 at
  10%, 8.57 at 2%**. Rotation and translation are already exact. "Keep Full Precision" stores those
  strokes as float32 — **12.18 bytes/sample against 7.10, 1.72x** — taking the three errors to
  **3.3e-5, 3.9e-5, 5.0e-5 pt**; "Bake Precise Strokes (N)" in Actions puts them back, one undo step.
  The owner chose float32 over float64 shown that doubles-as-bytes is 3.2x and doubles-as-JSON-text
  is 8.5x.
- **Move stage 3b, all three phases** (`330efd4`, `c78de6e`, `5b5577e`). A yellow knob turns the box
  alone; a Freeform stretch records the axis it was made about; and the box now **re-fits the ink as
  it turns**. §5.19-22.

## What each phase cost that nobody predicted

- **§5.20's recorded formula was wrong.** It said `R(ρ)·S·R(−φ)`; only `R(ρ+φ)·S·R(−φ)` works, because
  `transform.rotation` must stay the *ink's* angle — the green knob adds to it and `FixedAngleRotation`
  steps it. As written, turning the green knob on a stretched piece would have **skewed** it.
- **The SVD is needed in one case, not three.** Routing every stretch through it returns
  `aspect == 1 ± ε` for a diagonal drag, and `applyToVectorFloat` dispatches on `aspect != 1`
  *exactly* — so §5.17's "Freeform contains Uniform" would break at the seam. The fast arm keeps the
  pre-phase-2 arithmetic bit for bit.
- **The re-fit was too slow, and the measurement bought the fix.** 2.223 ms/frame on a 24,000-sample
  cel — 27% of a 120 Hz frame — against **0.401 ms** with a per-element convex hull paid once at the
  lift. The reduction is exact, not a trade: the extreme point in any direction is a hull vertex.
- **The box's period is 90°, not 45°.** `s·(|cos β| + |sin β|)` peaks at 45° and returns at 90°. The
  owner's description of what they *see* is right; the handoff that briefed it wrote the period wrong.
- **"Constant for a circle" is exact only for a true disc** — a polygonal ring wobbles by
  `1 − cos(π/n)`, 1.2% at 20 samples. The test uses a dab (exact) and a ring (tolerance stated as that
  arithmetic).

## The trap that cost a broken `main`, and it is the one to carry

`87081de` shipped `leaked.rotation += float.frame.boxAngle` — the exact defect stage 3b exists to
prevent — under a commit message asserting the opposite. It was a **mutation-testing defect the worker
had deliberately written to disk**, to check its own new guard could catch a leak. The orchestrator saw
the worker's test run finish, grepped the tree, found it clean, and committed / merged / pushed it,
deleting the worker's worktree and branch while it was still running.

Two lessons, both now in CLAUDE.md. **A finished test run is not a finished agent** — there is a
completion notification and it is the only signal that means what you want. And **a green check is
evidence about the tree that existed when you ran it**: this file already warned that a *red* xcresult
is evidence about a binary rather than a working tree, and nothing warned that it runs the other way.
The grep was true when it ran and false four minutes later. The general rule is the plainer one: a
worker's tree is a *workbench* — it legitimately holds deliberate poison — so harvest its **commits**.

## Still open, unchanged

`ARCHITECTURE_REVIEW.md` findings 2-4 are open and unruled. BUGS.md carries the raster-storage entry
(`CompositorBudget` bounds only compositor scratch, so one persistent buffer at maximum canvas is
~1.02 GB), the unclamped zoom — which a *precise* stroke now survives, since float32 has no boundary to
saturate onto — `TextFrame.homography` decoding with no validity check, and PERFORMANCE.md item 14.

Two behaviour questions are still owed and nobody is blocked: save semantics when a project loaded with
something unreadable, and which faces belong in the font picker's favourites strip.

Four judgement calls wait on real artwork, none of them defects: the Cut eraser across a line thicker
than the eraser, a crossing line that can flicker during a cut drag, a fill chunk dropped on blank paper
staying a fill, and a Freeform-stretched text box draggable smaller than its own text.
