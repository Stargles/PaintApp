# Handoff — 2026-08-27 (session 71)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is at 1773 fast-tier tests (1769 passed, 3 skipped). There is ONE branch in flight —
`tmp/effectbackdrop`, four commits, unmerged — and its state is the first thing to establish.

**1. Fix the effect backdrop, then merge it. DO NOT MERGE `tmp/effectbackdrop` AS IT STANDS.**
   Stages 1-4 are committed and the mechanism is right — the owner's report goes from `[0,0,0,0]` to
   `[128,128,128,255]` — but three reviewers found four measured defects, written up as
   **EFFECT_BACKDROP.md §7**. Two are serious: the texture estimate **doubled** for a bloom document and
   turned `PerfBaselineTests` red *in a file the branch never opened*, which shrinks every composite on
   a memory-constrained device and is the owner's own crash scene; and an `.ink` effect composites the
   ink twice, so **adding an Outline layer darkens the layer beneath it by 40%** (MEASURED 102 → 41).
   The third is a parity break on fractional canvas padding that neither parity test covers, because
   both use integer padding. **The fourth is a question for the owner, not a fix** — see §2.1, where
   this document's own ruling turned out to be analysed for the mid-stroke case and false at rest.
   **Then stages 5 and 6**: Bloom's and Sobel's controls with their persisted fields and decode
   defaults, and the thumbnail flag. And confirm §4's table — it names twelve of thirteen effects,
   **Sharpen is missing**, and the build agent answered it `.backdrop` by reasoning rather than ruling.

**2. Get it on the iPad.** Two things shipped this pass that a person has to look at:
   - **Draw across the canvas after shrinking a whole vector cel.** The whole line must survive. This
     is the data loss you reported, and it is fixed — this is the confirmation.
   - **Move with no lasso now shows the Move bar**, where there was never one. Freeform and Mirror are
     live on text now; they still grey out on a placed image, which is deliberate.
   - Sobel's changed default is **not** on the iPad either — it is stage 5, unbuilt.
   - The onion-skin change is **not** on the iPad — it is on the unmerged branch, and §2.1 needs an
     answer first.

**3. Then TODO.md's canvas-geometry programme**, which is five asks and one number. (8) is settled and
   buildable today. (12) stages 2-4 are the clean-up you asked for — deleting the legacy whole-layer
   transform path now that stage 1 has replaced it — and stage 2 must take the xcresult test count
   before and after, because ~1,300 lines of test exist solely to pin what it deletes.

Three judgement calls have been waiting on real artwork since 2026-08-22, none of them defects: the Cut
eraser across a line thicker than the eraser, a crossing line that can flicker during a cut drag (both
BUGS.md), and a fill chunk dropped on blank paper staying a fill (LASSO_MOVE.md §5). One more joined
them: a Freeform-stretched text box can be dragged smaller than its own text.
```

---

## State

`main` = `6fc3205` plus this close-out. **Fast tier 1773 total / 1769 passed / 0 failed / 3 skipped**,
measured on the merged tree, up from 1748 at the session's start. One in-flight branch,
`tmp/effectbackdrop` (4 commits, unmerged, **reviewed and rejected** — see EFFECT_BACKDROP.md §7). No
simulator clones.

**The one red in that run was `ARAPLogicTests.testStrokesArePairedByPositionRatherThanDrawingOrder`
failing with `crashed with signal term`** — a SIGTERM in an interpolation test nothing this pass
touched. Isolated re-run on a freshly erased device: 1 test, 1 passed, no clones. Environmental, and
the cause is known — see the process-kill hazard below.

## What the owner's device report settled

Six checks went to the iPad and all six came back, which is why TODO.md no longer has a
waiting-on-the-owner section.

- **The ink loss is real** — *"only the part of the line in a box around the original object gets
  baked"* — and **our predicted shape was wrong in their favour**. We said the top-left quadrant, which
  assumed a scale about the origin; the Move box scales about the ink-bbox centre. Measured after the
  fact on a 64x64 canvas shrunk 0.3x about ink at (32,32): the surviving band was **[22.4, 41.6]**.
- **The owner ruled against repairing it in place**, which is why the fix is a replacement rather than
  a patch. Two more things they could not see from outside: the loss is in the **document**, not the
  display, and the **samples were intact** — the rasterizer dropped them, which is why baking recovers
  the ink.
- **The freeze is not reproducible and is ruled solved.** It closes BUGS.md's long-open Fill entry with
  it, since the two were argued to be one bug. Kept undiagnosed rather than pruned: nothing was ever
  found, and the two regression nets passed throughout, so a green suite is not evidence it is gone.
- **Scribble, Freeform and the lasso ants are confirmed working.** The pencil-tap keyboard fix could
  never have been verified on this Mac.
- **The empty-text ask was already shipped** — since 2026-08-20, 123 commits before the build on their
  iPad. Closed unbuilt. Whitespace-only counts as empty too.

## What landed

- **`a506d66` — the brush button after a whole-canvas Move.** Fixed at `selectedTool`'s own `didSet`,
  which reaches all six writers by construction. **It could not go in `commitAllInteractiveState()`**:
  `toggleMove()` calls that *before* toggling, so the close would zero the flag and the toggle would set
  it straight back, and Move could never be dismissed from its own button. Gated on an exhaustive
  `Tool.isMomentary` so an eyedropper round trip does not commit the box; `.text` is deliberately not
  momentary. **A second-order bug was found inside the work**: the first draft exempted a momentary
  transition on *either* side, which also exempted a direct switch away from an armed eyedropper and
  reopened the defect behind one extra tap. Its own test caught it.
- **`cf5de83` — Move with no selection lifts the whole cel into the lasso float.** The ink loss is
  closed. The regression test ships with the *old* mechanism driven inside it asserting the loss, so the
  positive half cannot rot into a vacuous pass and stage 2 has to delete that control deliberately.
  **The teardown audit is the part nobody asked for and the part that mattered**: a whole-cel float
  suppresses every element id, so any door that flattens while the box is up bakes the cel to blank in
  the saved document. **Five** doors were missing the commit — Rasterize, Merge Down, `moveCelToLayer`,
  `clearCel`, and `deleteLayer`, where the commit runs but the layer is already out of `layers`, and
  because the undo snapshot holds a reference type, **undo brought the layer back still blanked**. A
  sixth is filed rather than fixed (Canvas Padding, which belongs to the resize path being rebuilt).
- **`045d509` — text mirrors and stretches**, owner ruling 18: mirror reflects the glyphs, a non-uniform
  scale distorts the letterforms and does not re-flow. **Three brief claims were refuted by the code**,
  including the acceptance test this orchestrator specified — "same per-line widths after a stretch" is
  **not a scale invariant**, because the system face has size-dependent tracking, so a sqrt(3) scale moved
  a line from 0.630 to 0.587 of its box with the breaks bit-identical. Replaced with line count plus
  line *ranges* and a re-flow discriminator, so the passing assertion chooses between two live
  possibilities.
- **`785f3f7` — the bottom-bar height was attempted, measured and reverted**, and the dead end is the
  deliverable. See TODO (18): the standard `.background(GeometryReader)` measures **exactly 0**, and
  **the XCUITest passed against the broken build** because a clipped view's accessibility frame does not
  reflect what painted. A screenshot is that item's acceptance test now.
- **Docs**: [EFFECT_BACKDROP.md](EFFECT_BACKDROP.md) is new and fully ruled; TODO.md went 424 to 211
  lines at the owner's request, with answered questions folded into the items they answer.

## Two hazards learned the hard way, both now in CLAUDE.md

- **Killing by process name is machine-wide.** An agent sweeping for its own strays with
  `pgrep -f xcodebuild | kill` killed the orchestrator's verification run. **The damage does not
  announce itself as a kill**: the first attempt died with exit 144 and no output, the retry gave
  `Mach error -308` with zero tests passed — which CLAUDE.md already attributed to *contention*, so it
  was diagnosed as a loaded machine and restarted into the same hazard. Two runs and a wrong diagnosis.
  Same family as the shared simulator UDID and the shared `git stash`.
- **A passing XCUITest can be blind to a view that renders nothing.** Accessibility frames reported
  plausible differing positions while the rows were clipped away entirely. This is the
  banner-versus-count trap in a third costume, and the answer is the same: read the thing that actually
  measures what you care about.

## Still open, unchanged

`LASSO_MOVE.md` §5 carries **eighteen** owner rulings; do not re-litigate any. `ARCHITECTURE_REVIEW.md`
finding 1 is closed; findings 2-4 (eleven hand-written cache keys, silent save-failure returns, a layer
property living in four hand-kept structs) are open and unruled. `BUGS.md` carries the unclamped-zoom
coordinate, the `TextFrame.homography` decode with no validity check, the `.projective` re-rasterise per
invalidation, and PERFORMANCE.md item 14's expensive half.

Two behaviour questions have been owed for days and nobody is blocked on them: save semantics when a
project loaded with something unreadable (may saving overwrite the good original, refuse, or prompt? a
branch shipped "prompt once, then remember" — confirm it), and which faces belong in the font picker's
favourites strip.

## The review that did not merge, and why it was worth its cost

The effect-backdrop branch was built by one agent and then read by three, each given a different lens
rather than the same one three times. **Every one of the four defects came from the reviewers, none
from the build**, and two were measured rather than argued — a 40% darkening reproduced with a probe,
and a 204-channel parity delta reproduced with a fractional padding value no existing test uses.

The one to learn from is the **onion skin**, because the defect was in *this project's own
specification* and not in the code. EFFECT_BACKDROP.md §2.1 reasoned about the mid-stroke split, where
the sandwich really does have an `above` half covering the ghost, and stated a conclusion about "the
one behaviour change" as though it covered every state. At rest the whole tree is in the lower view,
`above` is nil and hidden, and every host is blanked — so there is nothing left to cover the ghost and
the two onion-skin placements collapse into one. The spec was confident, specific, and wrong about the
state the artist spends all their time in. A reviewer walked the six cases in a table; that is what
found it.
