# Handoff — 2026-08-27 (session 72)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is `f99ca83`, fast tier **1798 / 1795 / 0 / 3**. **No branches in flight, one worktree,
clean tree** — unusually, there is nothing to establish before you start.

**1. Build item (8), the fixed-point sample encoding. It was blocked yesterday and is not now.**
   TODO.md's five geometry items are ONE feature — the owner's own framing, *"the refit to the way
   brush strokes are stored"* — and the order is forced: **(12) stage 3 → (13) → (8) → (14) → (9)**.
   The first two are merged, so **(8) is the head of the queue.** What unblocked it: nothing writes a
   cel transform any more, so a persisted sample IS a canvas coordinate and "the origin is the centre
   of the current canvas" finally has a fixed point to mean.
   Read (8) as it stands — **three of its premises were corrected on 2026-08-27** and the item carries
   the corrections: the memory win is zero (the ruling says memory is unchanged, so the win is
   disk-only and larger), a sample costs ~77 JSON bytes not 89, and the field reaches **+8191.75** so
   the maximum canvas is 16383. Its five attached rulings are settled; do not re-open them.
   **No migration is needed.** The owner ruled 2026-08-27 that *"everything on the ipad
   right now is expendable"* — no decode defaults for fields that never existed, no appearance-change
   warnings. It is at the top of TODO.md and it is what makes this cheap.

**2. Four things are on the owner's iPad awaiting a look, none of them blocking.** The build there is
   `fe5e716`, one commit behind `main` (`f99ca83` adds only item (12)/(13), which are headless).
   - **Sobel is bright edges on opaque black now**, with no control. If it still reads grey, that is a
     different bug from the one fixed and it matters.
   - **An adjustment layer should grade blank paper**, and a blend mode should blend against it. This
     is the owner's original report and the whole point of the pass.
   - **Draw across the canvas after shrinking a whole vector cel** — the ink loss, still unconfirmed.
   - **Move with no lasso shows a Move bar**, where there was never one.

**3. Then (18) or (10), both in TODO.md's Open section.**
   (18) is the bottom-bar height: the obvious implementation was built, measured and reverted, and the
   candidate next approach is recorded on `maxRowsHeight`. **A screenshot is its acceptance test, not
   a frame comparison** — an XCUITest passed against the broken build. Note Sobel is back to **zero**
   controls, so it is the degenerate case again.
   (10) is Oklab, and the recommendation is written into the item: **not storage, not the compositor —
   interpolation, and linear light first.** Stage A's premise (that the unlinearized composite is what
   makes saturated hues read muddy) is argued and **not yet seen**; render the A/B before building it.

**Do not re-litigate**: LASSO_MOVE.md §5's eighteen rulings; EFFECT_BACKDROP.md §5's four and §2.1's
three-pass onion-skin ruling; Sobel's deleted ink control (§5.2 says explicitly not to re-propose it);
(8)'s five attached rulings.
```

---

## State

`main` = `f99ca83`. **Fast tier 1798 / 1795 / 0 / 3**, measured on the merged tree. No branches, no
worktrees but the main one, no simulator clones.

**The full suite has NOT been run on this commit.** The last full run was at `dee77ff`, six merges ago:
1916 tests, four reds — two environmental (confirmed by isolated re-run), two the recovery-test bug that
is now fixed. Nothing since then touches a gesture or a view except item (12)'s deletions, which are
covered headlessly, but that is an argument and not a measurement. **Run one at the next phase
boundary**, and shut down and erase only after checking `pgrep -fl xcodebuild` — three sessions shared
this Mac today.

## What landed

- **The effect backdrop, all six stages** (`ca4c008`…`d90b329`, plus fixes). The owner's report —
  *"Chromatic abberation seems to be masked to the objects on the layers only"* — is closed, and with it
  seven other effects and twenty blend modes: the canvas paper was a `UIView` behind the composite, so
  every adjustment layer graded a transparent sheet. **All four of EFFECT_BACKDROP.md §7's defects are
  fixed**, and §8 is new: it records what §7's own *explanations* got wrong, which was more than what
  its findings got wrong.
- **Sobel**, twice. First `5f88302`: its ruled `.backdrop` default rendered a **transparent** canvas,
  not a black one, because the kernel emits `(m,m,m,m)` and a flat region has `m = 0`. The owner saw it
  on their iPad as grey — which is `paddingBackdrop`'s `UIColor(white: 0.85)`, byte 217, showing through
  a hole punched clean through the paper. **EFFECT_BACKDROP.md §2.2 asserted the opposite and was the
  entire justification for the ruled default.** Then `601c983`: shown that ink-only Sobel is
  arithmetically invisible on white paper and finds zero edges in black line art, the owner deleted the
  control outright.
- **Item (12) stages 2 and 3** (`683983c`, `2fa1725`), ~1,366 lines deleted. **Stage 3 closed a second
  door onto the owner's own ink loss**: after stage 2, `setCanvasPadding` was the only remaining producer
  of a non-identity cel transform, and it walks every cel — so one use of the padding slider left every
  cel clipping later canvas-space ink. The same loss, through the Actions menu instead of the Move box,
  and nobody had connected them. Stage 4 is **declined with a reason**, not forgotten: `_transform` is
  dead-*valued* rather than trivially dead, and LAYER_TRANSFORM.md §7 prices its removal at 2-3 days for
  clarity and no behaviour.
- **Item (13)** (`83f7c0d`). Built as ruled, and what it exposed outgrew it — BUGS.md's top entry:
  `CompositorBudget` only ever bounded compositor **scratch**, so the persistent raster/fill/baked
  buffers go through no budget at all and **one at 16383² is ~1.02 GB** against a 3 GB device's whole
  process budget. Whether a near-maximum canvas is vector-only is a product call.
- **Item (10) answered rather than built** — the owner asked for the call. Storing Oklab *moves* a
  conversion rather than removing one, and this tree adds three specific blockers: 8-bit textures band
  Oklab's a/b, the byte-for-byte parity gate cannot hold a cube root, and coverage compositing is
  averaging light. The staging turns on one fact: **sRGB→linear is per-channel, so on 8-bit input it is
  a 256-entry LUT and bit-identical on both backends by construction; Oklab's cube root sits after a
  matrix mix and cannot be tabled.**

## Two traps, both now in CLAUDE.md

- **A test class is not its file.** The 2026-08-15 split cut six heavy UI files into three classes each
  and left the filenames alone, so `VectorShapeAndRecoveryUITests.swift` holds `GalleryRecoveryUITests`.
  A selector built from the filename matches nothing and prints `Executed 0 tests` then
  `** TEST SUCCEEDED **`. Cost one four-test triage run.
- **A green test can be a test that stopped testing.** Twice today: `GalleryRecoveryUITests` asserted the
  **raster** stroke count of a **vector** layer and had been red-but-ignored since 2026-08-11 (and, before
  that, green off a bitmap heuristic that defaults to 1). And Sobel's impulse-response test would have gone
  **vacuous** — nine zeroes, passing against any stencil — when the alpha rule changed, had the fixture not
  been moved to an opaque ground.

## The pattern worth carrying

**Five of this pass's significant findings were wrong premises, not wrong code**, and two were caught by
the owner looking at a screen. §7's own suggested fix would have erased Outline's ring. §2.1 described
the onion-skin cost as "a little extra compositing work" when it was not extra work at all and the real
cost was the picture. §2.2's claim about Sobel's flat regions was false. (8) said it needed nothing and
needed (12). The "data loss" was a test that could never have passed.

**And the process lesson: render the cost, do not describe it.** Told the onion-skin split cost "121 of
255 channel steps", the owner accepted it. Shown the two pictures — a correctly multiplied dark navy
shape beside the raw blue it actually becomes — they reversed the ruling in one message. Both
descriptions were true.

## Still open, unchanged

`ARCHITECTURE_REVIEW.md` findings 2-4 (eleven hand-written cache keys, silent save-failure returns, a
layer property in four hand-kept structs) are open and unruled. BUGS.md carries the new raster-storage
entry, the unclamped-zoom coordinate, `TextFrame.homography` decoding with no validity check, the
`.projective` re-rasterise per invalidation, and PERFORMANCE.md item 14's expensive half.

Two behaviour questions have been owed for days and nobody is blocked on them: save semantics when a
project loaded with something unreadable (may saving overwrite the good original, refuse, or prompt? a
branch shipped "prompt once, then remember" — confirm it), and which faces belong in the font picker's
favourites strip.

Four judgement calls wait on real artwork, none of them defects: the Cut eraser across a line thicker
than the eraser, a crossing line that can flicker during a cut drag (both BUGS.md), a fill chunk dropped
on blank paper staying a fill (LASSO_MOVE.md §5), and a Freeform-stretched text box draggable smaller
than its own text.
