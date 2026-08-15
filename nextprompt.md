# Next session — the layer-compositing project, after the phase 9 close-out

You are the Orchestrator. `main` is the checkpoint and everything below is merged and pushed. Branch
off `origin/main` per [CLAUDE.md](CLAUDE.md). [LAYER_COMPOSITING.md](LAYER_COMPOSITING.md) §11 is the
build order, §10 is what is still open.

## What shipped this session

| what | note |
|---|---|
| **9b** — effect as a 1-input node | §4.4's second wrapper. `LayerFolder.effect`, one grade call after `fold` in each backend |
| **9c** — Sobel, sharpen/unsharp, outline | §7, on the multi-pass contract. Four independent defences, all live |
| **§4.3 redesign** — a node's children ARE its inputs | input-slot folders deleted from the product |
| **§4.5** — the value layer | non-drawable, one flat colour, plugs into a Mix or blends with what's below |
| **Mask sub-menu** | tapping Mask replaces the edit menu; Back returns. The tuning harness is now a feature |
| **Test splits** | six heavy XCUITest classes → 18. Longest single unit 424s → ~189s |
| onion skin ghosting a cel onto itself | fixed |
| `testMovingThePlayheadRebuildsTheBlendedCanvas` order-dependence | fixed in setup, not by re-running |
| `duplicateLayer` dropping `effect` | phase-9a bug, silent since 9a |

## Owner decisions — settled, do not re-ask

1. **The sandwich through a blending Mix: not yet.** Delta 255 is structural, snaps correct on lift.
2. **Drawing on a layer with no drawing surface**: stays selected, gesture is a no-op *with feedback*.
   One mechanism (`Layer.hasNoDrawingSurface` → the "No Drawing Surface" alert) serves both the
   effect layer and the value layer. Do not invent a second.
3. **"Pause this mask" does not come back.** `isEnabled` means exactly "has sources".
4. **The antialias constant stays 0.01.** §6.3's smoothstep is vestigial at that value (~0.34 px of
   ramp) — say so rather than claiming a purpose it no longer serves.
5. **§10.2 — ship neither new node op.** Not variadic arity, not the matte/key op. Masking on nodes
   shipped instead. Re-ask about matte against whatever that turns out not to cover.
6. **A Mix node has no blend mode of its own** — output is always Normal; wrap it in a folder to blend
   the result. **Deleting a node promotes its children**, like any folder.
7. **Value layers will be keyframable eventually, but not yet.** The seam is built and is the whole
   point: the colour resolves in `renderSources(atFrame:)`, which already has the frame, so
   `Compositor.swift`, `MetalCompositor.swift`, `Composite.metal` and `RenderTree.swift` have a
   **zero-line diff** from the feature. Keyframes change one function and touch neither backend.

## Verification owed — read this before you build anything

**The full XCUITest suite was not re-run this session.** The fast logic tier is green at
**930: 928 passed, 0 failed, 2 skipped** (the two `PAINT_PERF_HEAVY` gates) on the merged tip. But the
six-class → 18-class test split changed how the suite *schedules*, and that has never been validated
end to end. Run it once, on an erased simulator on a quiet machine, before trusting a boundary number:

```bash
xcrun simctl shutdown all; xcrun simctl erase 75C8B97E-47AF-484B-B7D2-CA7EB1B51B03
```

Expect roughly 990 tests. The split was verified three ways — the `func test` count held at 982 across
the merge, the test target compiles, and all 18 new class symbols are present in the compiled
`.xctest` with all 6 old names gone — so what is unproven is scheduling and wall-clock, not existence.

## Still open

- **`setLayerEffect` has no UI caller.** An effect layer is now *creatable* but not *configurable*: it
  arrives as an identity Brightness/Contrast and stays that way forever. This is the same gap that
  hid `addEffectLayer` and `addValueLayer` for three phases, one level in. An effect picker is a
  design decision — ask the owner what it should look like rather than guessing.
- **Onion skin overhaul.** The owner wants it to get its own menu and be customizable. Two things to
  fold in, both in [BUGS.md](BUGS.md): the ghost renders **unmasked** (reuse
  `resolveLiveMask(forLayerAt:)` / `RenderNode.masksClipping(leafAt:in:)`, do not write a second
  mask-resolution path, and mind §6.4's warning that a `CALayer.mask` slot collision fails silently);
  and a cel spanning many frames means "the previous drawing" is often nothing at all.
- **A full Mix node refuses new children**, so dragging a layer out of an operand folder *up into* the
  node is refused. Workaround is deleting the wrapper folder, which promotes in place. Rough edge the
  fixed slots did not have — worth a second look if the owner hits it.
- **No test uses a vector layer as a mask SOURCE.** Every `MaskParityLogicTests` fixture bakes raster
  content into the source; the two vector cases make the vector layer the *masked* one. The owner's
  original repro was vector-masked-by-vector, and the compositor was cleared by reading rather than
  running.
- **The solid for a value layer is minted per request with no memo.** Cheaper than a rasterize and off
  the drawing path, but canvas-sized. If it shows in `PerfBaselineTests`, key a memo on `(hex, size)`
  — a pure value, so it cannot go stale.
- §10 items the redesign did not touch.

## The two hazards this project keeps paying for

**1. A green test proves its two operands are equal — which is not always the two things its name
claims it compared.** Six instances now. The purest was
`testDefaultSourceReturnsExactlyThePreviousCel`, which compared the current cel against itself
because its fixture had only one cel. **Write the premise assertion**: assert the fixture is what the
test thinks it is before asserting anything about behaviour.

Corollary that cost real time this session: *merging* a branch cut before a deletion can silently
resurrect what was deleted. Splitting `LayerUITests` brought back four tests for input-slot UI that
no longer exists. Nothing complained — the only signal was the total reading 986 against a 982
baseline. **Take a count before you merge and compare after.**

Second corollary, and it is a trap specific to this codebase's UI tests: **a SwiftUI
`.accessibilityIdentifier` on a container propagates to its descendants and beats their own.**
`MaskTuningSection` carried one on its container stack, so both tuning sliders surfaced under the
container's name and `maskTuning.threshold` named nothing at all — a test querying it would have
found no element and, depending on how it asked, passed by never running. Wrapping a row in a
`Button` does the same thing for a different reason: the label's subviews fold into one element, so
`layerOptions.maskSummary` would have stopped existing as a `staticTexts` element. Put the tap target
in an `.overlay` beside the texts instead. When you add an identifier, query it once and confirm it
resolves before writing assertions against it.

**2. A red xcresult is evidence about a *binary*, not about your working tree.** `test-without-building`
reuses the last compiled bundle. This session spent an opus worker "fixing" three effects that were
already correct: the run predated the rebuild, and every reported byte was the ratio between the
draft constant (`1/4`) and the committed one (`1/√20`). **Before debugging a numeric failure, diff the
constant the test names against the value it reports.** Thirty seconds against hours. Now recorded in
CLAUDE.md next to the `** TEST SUCCEEDED **` warning, which is the same trap pointing the other way.

The effect abstraction has a structural version of hazard 1: both backends consume the same
Swift-resolved values, so **a parity sweep cannot catch a mistake in the resolution** — both sides
make it identically and pass green, and a same-author re-derivation in the test is not independent
either. What works: impulse response against mathematics, separable-vs-direct-2D, a hand-computed
spot check at a degenerate radius, an independent transcription in a different number of stages.

## Machine and delegation discipline

- Read `totalTestCount` from the xcresult, never the banner. Build `-only-testing` flags into a shell
  ARRAY and pass `"${SUITES[@]}"` — zsh does not word-split unquoted `$VAR`.
- A PASS under load is trustworthy; a FAIL under load is not. Read a failure's `file:line` before
  believing its name.
- **Set `model` explicitly on every delegated agent** — an omitted model inherits opus. Budget is
  3 opus + 8 sonnet; opus for design-bearing work, sonnet for measurement, code-tracing and surveys.
- The real ceiling is the two simulators, not the agent cap. Use
  `/Users/juliapark/.config/paintapp/simlock.sh` with the literal `@SIM@` token, never `$SIM_UDID`.
  One worktree per worker; workers run only the suites their own change touches.
- **Ask the owner product questions in plain language** and define any term the project invented.
  They judge behaviour, not internals.
- `simlock.sh` still reaps a lock older than an hour even when its owner is alive, then erases the
  device out from under it. Reap on a dead owner unconditionally; apply the age check only when the
  pid is missing.
- The graphify `PreToolUse` hook rebuilds in the background and leaves `graphify-out/GRAPH_REPORT.md`
  dirty in the main worktree, which aborts a `--ff-only` merge. `git checkout --` it before merging.

## Before you run out of context

Rewrite this file and commit it, addressed to an Orchestrator — including this instruction. Write it
early; a handoff written while you still have room is worth more than a complete one you never get to
write. Land it on `main`.
