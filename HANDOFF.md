# Handoff — 2026-08-28 (session 74)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is `21cb9ea`. **Fast tier 1953 / 1950 / 0 / 3. FULL SUITE RUN AND CLEAN one docs commit
below the tip: 2073 / 2065 / 2 / 6, and both reds passed clean in isolation** — environmental, no fix
owed. **No branches in flight, one worktree, clean tree.**

**1. TODO.md has one item left, (10) Oklab, and its first move is not to build anything.**
   The recommendation is argued and **not yet seen**: stage A is *not* Oklab, it is compositing in
   **linear light** through a 256-entry LUT, on the theory that the muddy midpoint the owner
   described between two saturated hues is a gamma problem. **Render the A/B and show it before
   building.** The owner reversed a ruling once already this project on seeing an image they had
   accepted on reading a number (SESSION_LOG session 72, the onion skin). Stage B is Oklab for
   *interpolation only*; stage C is Oklab blend modes and breaks the `CGBlendMode` parity gate for
   eleven of them.

**2. Then it is ROADMAP.md, and every item there needs the owner before it needs a design.**
   The owner wrote the six-item long-term plan unprompted so architecture is not chosen blind, and
   asked to be prompted to explain each one properly when it comes up. **Do that rather than
   designing from the file.** Its three live findings: item (1) is mostly *somewhere to attach*
   machinery that already exists (`SpacingCurve` is arbitrary easing today; `fps` is persisted and
   only ever written by the load path); a video element inherits whatever **Move stage 3c** stores,
   so making 3c's field a shared placed-object pose is free now and a second migration later; and
   **export does not exist at all**, with a blocker that is not the compositor — `makeRenderRequest`
   drops in-betweens, so an export written today silently omits every one of them.

**3. Two behaviour questions are owed and nobody is blocked.**
   - **The save-failure banner is invisible on "leave to gallery"** (`ea51607`): `raise(.saveFailed)`
     and the screen flip land in the same render pass, and the banner lives in the editor. It works
     on the autosave path, which was the silent one. Fixing it means holding the artist in the editor
     on failure, which needs a retry affordance that does not exist. **Unruled.**
   - **`fillSelection` and `clearSelectionPixels` can write to a derived in-between's `VectorCanvas`**
     — BUGS.md, top. Move guards this in two places; those two never did. Deliberately not fixed
     while Clear was being repaired, because changing when two shipped buttons refuse is a behaviour
     change the owner has not been asked about. **Ask.**

**4. The iPad has today's build** (Release, `88a3fb4`, installed over cable). Five older things were
   already waiting there and three are new: **Resize Canvas**, **Recolour** in the Select panel, and
   the Move bar's **Enclosed · Cut · Touching** picker. Note the build predates `c35df15` and
   `ab45074`, so it has **no resize undo and no busy state**, and the effect bars are still the flat
   300 pt. Offer to redeploy from the worktree, not `deploy.sh` (it pulls `main` and never ships
   branch work). `devicectl list devices` first: `unavailable` means the owner must wake it and
   nothing on this Mac fixes it; `available (paired)` with a failed install means a stale tunnel.

**Do not re-litigate**: LASSO_MOVE.md §5's **twenty-five** rulings (§5.23-25 are from 2026-08-28);
CANVAS_RESIZE.md §5's fourteen and §6's five answered questions; EFFECT_BACKDROP.md §5's four and
§2.1's onion-skin ruling; (10)'s three-stage recommendation; Sobel's deleted ink control.

**The trap this pass paid for, and it is a measurement one.** A performance number is evidence about
*the fixture it ran on*. "A resize takes 3-4 s" was true and useless: that fixture's cels held raster
pixels and **no `VectorCanvas` at all**, and on a document shaped like the owner's real artwork the
same walk is **0.9 ms/cel**. A whole spec section had been planning against a tenth of the truth,
and the owner's own question is what surfaced it. Before optimising anything, check what the fixture
is made of.
```

---

## State

`main` = `ab45074`. **Fast tier 1953 / 1950 / 0 / 3** (1956 declared; the 3-line gap is the 3 skips).
Static `func test` across all test files 1985 → **2076**. No branches, no worktrees but the main one.

**FULL SUITE RUN AND CLEAN**, at `ab45074` (one docs commit below the tip), freshly erased simulator:
**2073 / 2065 / 2 / 6**, and **both reds passed clean on an isolated re-run** —
`LayerPanelUITests.testDroppingFolderOntoFolderNestsIt` (the one CLAUDE.md already names as
erase-sensitive) and `EraserAndPersistenceUITests.testEraserCanEraseAFilledSelection`. Environmental,
no fix owed. Note both classes are named differently from the files they live in, which is the trap
that makes a filename-derived selector match nothing and report success — resolve the class from
source before building a `-only-testing` selector.

## What landed

Twelve merges. **TODO item (9) closed in four stages, and with it the whole five-item storage refit**
— (12) stage 3, (13), (8), (14) and (9) are all merged and all out of TODO.md.

- **(9) stages 0-3** — `ea51607` a failed save says so; `3d0c7c4` Resize Canvas as crop/expand;
  `b42a67b` scale-to-fit **and** scale-to-fill; `c35df15` undo, refusal, save gate, busy state.
- **(19) Change Colour** `3ceaa12` — recolour a lasso selection whole, splitting nothing.
- **(20) Move's three membership modes** `41de342` + `88a3fb4` — `Enclosed · Cut · Touching` as a
  parameter on `splitForLassoMove`, defaulting to today's Cut.
- **Clear actually clears** `6f4abcb` — the owner's bug, plus an unreported second one.
- **(18) the effect bar is as tall as its rows** `ab45074`.
- **`ROADMAP.md`** `ecc7af1`, **CANVAS_RESIZE.md §6 closed** `89c0526`, **the resize measurement**
  `b7d5eeb`, housekeeping `19d9c3f`, TODO `91085c9` / `b198b57`.

## What each phase cost that nobody predicted

- **§2's letterbox factor was a ratio of the wrong rectangles.** Buffers, not artwork — so on any
  document with padding, "double it" silently grows the margin and shrinks the artwork. Exactly the
  "two controls fighting over one number" §6 Q3 had just ruled against, and **exactly zero at
  `k == 1`**, which is why stage 1 could not see it.
- **`CanvasResizeMap.inverse` picked Fit both ways.** Undoing a Fit needs a **Fill**
  (`1/min(rx,ry) == max(1/rx,1/ry)`). Unreachable until stage 3's undo existed.
- **§2 sized the undo step at ~410 MiB and worried it would evict itself.** The undo is the inverse
  resize *recomputed*: a map, a scalar, a weak self. **O(1)**, now pinned by a test. The measurement
  stage 3 owed had nothing to measure.
- **§0's vector-primitive row was stale in our favour** — `VectorCanvas.resized` has baked the map
  into the elements since (12) stage 3, so **stage 2's vector arm was already written**.
- **Enclosed fires `mayDiverge` *less* often than Cut, not more.** Its moved set is a subset. The
  scoping brief asserted the opposite confidently; a test now pins the ordering
  Touching ≥ Cut ≥ Enclosed.
- **(18)'s recorded dead end was misdiagnosed.** A `ScrollView` does *not* propose unbounded height
  to its content — asked with `height: nil` it reports the content's ideal size. The greedy behaviour
  is it reporting *its own* size upward once given a number. So the problem was never that the rows
  could not be measured; it was that the measurement had to reach a frame without forming a cycle.
  A custom `Layout` asks both questions in order, with no state and so no cycle to settle at zero.
- **Clear hid a second defect under the reported one.** `clipPath` stapled the loop onto *every* fill
  with no bounds test and forced even-odd, so two disjoint regions each winding once **both filled** —
  clearing bare paper painted it the colour of a fill elsewhere on the canvas.

## The trap to carry: a performance number is evidence about its fixture

The 3-4 s resize that started a whole design conversation was measured on a fixture whose cels had no
vector content. The owner asked why it cost anything at all, given samples are stored as ints about a
stored origin — and the honest answer had three parts: they are right that **nothing is re-encoded on
disk**; the cost is the **in-memory** walk, which is 97% of it on their documents; and that walk is
**0.9 ms/cel**, so a 300-cel resize is 0.27 s, a tenth of what the spec had been planning against.

Their proposed fix — put the translation back in a layer transform, which this code once had — **does
not skip the walk, it moves it to the next save**, because `VectorCanvasData.init(from:)` bakes any
carried transform on encode. It also reintroduces two of the three defects (12) removed it for, one
worse than before: a uniform per-cel offset shifts keyframes while in-betweens render unshifted.

This is the same family as CLAUDE.md's banner-versus-count and red-xcresult-is-about-a-binary traps,
reached from a third direction. **Check what the fixture is made of before believing what it measured.**

## Still open, unchanged

`ARCHITECTURE_REVIEW.md` findings 2-4 are open and unruled. BUGS.md carries the two new entries
(interactive-gesture CPU composites; Fill/Clear on a derived in-between), the raster-storage bound,
the unclamped zoom, `TextFrame.homography` decoding with no validity check, and PERFORMANCE.md item 14.

Two behaviour questions are owed: save semantics when a project loaded with something unreadable, and
which faces belong in the font picker's favourites strip.

Four judgement calls wait on real artwork, none of them defects: the Cut eraser across a line thicker
than the eraser, a crossing line that can flicker during a cut drag, a fill chunk dropped on blank
paper staying a fill, and a Freeform-stretched text box draggable smaller than its own text.
