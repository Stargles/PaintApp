# Handoff — 2026-08-28 (session 75)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md, KEYFRAMES.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is `4d55aae` plus this docs commit above it. **Fast tier 2022 / 2019 / 0 / 3. FULL SUITE RUN at `05a3e7c` (stages 0-1):
2125 / 2118 / 1 / 6, and the one red passed clean in isolation** — `SandwichCompositingUITests.
testAMultiplyLayerLooksMultipliedOnTheLiveCanvas`, a keyboard-focus flake, environmental, no fix owed.
**No branches in flight, one worktree, clean tree.**

**1. The keyframe feature is designed and its first three stages are merged.**
   [KEYFRAMES.md](KEYFRAMES.md) is the specification — ROADMAP item (1), designed 2026-08-28 in the
   conversation that file names as each item's entry condition. **§2 is twenty owner rulings; read them
   rather than re-deriving them. §8 is the build order and marks what is done.** Stages 0, 1 and 2 are
   in: the render tree takes the frame, `AnimationCurve` exists, effect parameters have an address, and
   one layer effect parameter animates end to end with save/load and undo. **Nothing is visible to the
   artist yet — that is stage 3**, the Animate mode (tap inserts a key, hold 0.8 s toggles the mode) and
   the graph-editor drawer that grows the timeline.

**2. Three things in that spec pay for the rest, and a future session will want to undo them.**
   A transform key stores a **quad** from day one, so Distort lands later with no migration — six
   scalars *are* a general affine and Distort needs eight (LASSO_MOVE §5.20). Posed ink is drawn by
   **baking the dab walk in rest space** and mapping dab centres per frame, which removes the shimmer by
   construction *and* dissolves the per-sample-width problem, because `Homography.localScale` is the
   local form of the `sqrt(|det|)` rule §5.17 already settled. And **bake is an authoring feature, never
   a performance instruction** — smooth playback comes from the span cache in §4.6.

**3. §9 has five open questions and one of them is owed by the owner, not by us.**
   Q6 is a 30-second check on the iPad: **do generated in-betweens visibly boil or crawl?** The
   interpolation evaluator already re-walks the dab lattice per in-between under a non-uniform map,
   which is the exact artifact §4.2 exists to prevent. If they look clean the stage-4 risk is smaller
   than it has been sized. The others: what an invalid in-between pose does; whether a value layer
   *below* a transform layer poses its sheet; whether folder effects animate; and where the span cache's
   disk tier lives.

**4. TODO (10) Oklab is untouched and its first move is still not to build anything.**
   Stage A is **linear-light compositing through a 256-entry LUT**, not Oklab, on the theory that the
   muddy midpoint is a gamma problem. **Render the A/B and show it before building.**

**5. The iPad build is now well behind** — Release `88a3fb4`, which predates the whole storage refit's
   tail *and* everything in this pass. Offer to redeploy from a worktree, not `deploy.sh` (it pulls
   `main` and never ships branch work). `devicectl list devices` first: `unavailable` means the owner
   must wake it and nothing on this Mac fixes it.

**Do not re-litigate**: KEYFRAMES.md §2's twenty rulings; LASSO_MOVE.md §5's twenty-five;
CANVAS_RESIZE.md §5 and §6; EFFECT_BACKDROP.md §5 and §2.1; (10)'s three-stage recommendation.

**The trap this pass paid for, and it is a verification one.** A characterization pin can be weaker
than it looks because of what is *in the test target*. `Views/EffectSection.swift` is not compiled into
`PaintSoftwareUITests`, so a fast-tier test **cannot see `EffectSettingsBar.rows` at all** — the pin
taken before refactoring it covered the table, not the bar. The gap was closed with two XCUITests, an
assertion that traps a wrong parameter id in debug, and a static id cross-check; the point is that
"pinned first" was not true in the way it was asked for, and only reading the target membership shows
that. The same fact has a second face: **a logic test costs four pbxproj ids, not two**, because the app
source it reaches is compiled into the test target a second time. Both are now in CLAUDE.md.
```

---

## State

`main` = `4d55aae`, plus the close-out docs commit above it. **Fast tier 2022 / 2019 / 0 / 3.** Static `func test` 2076 → **2145**.
No branches, no worktrees but the main one.

**FULL SUITE RUN at `05a3e7c`** (stages 0-1, freshly erased simulator): **2125 / 2118 / 1 / 6**, total
reconciling exactly — 2073 baseline + 1 (stage 0) + 27 (curve) + 24 (table). The one red,
`SandwichCompositingUITests.testAMultiplyLayerLooksMultipliedOnTheLiveCanvas`, **passed clean on an
isolated re-run** (1/1/0/0, zero "Clone" in the log). Environmental. Stage 2 has fast-tier coverage only.

## What landed

**The keyframe feature went from an unscoped roadmap line to three merged stages in one pass**, via a
design conversation that produced twenty rulings.

- **`dc169da` KEYFRAMES.md**, the specification. **`9a20195`** the span-cache ruling, after the owner
  refused the design this document first proposed.
- **`654f863` stage 0** — `renderTree(atFrame:)` plus `Layer.layerEffect(atFrame:)` and
  `LayerFolder.resolvedEffect(atFrame:)`, behaviour-neutral, with a pin asserting frame-invariance whose
  own comment says breaking it is the signal stage 2 landed.
- **`c09ddf0` stage 1a** — `AnimationCurve`: authored handles, five tangent modes, per-segment
  interpolation, per-channel step.
- **`c6ecb49` + `6a379bf` stage 1b** — the effect parameter-descriptor table, and the settings bar
  reading it instead of 25 hand-written literals.
- **`4d55aae` stage 2** — one layer effect parameter animating end to end: storage on the layer in
  absolute frames, `Effect.resolved(atFrame:through:)`, its own undo path, save/load round trip.
- **`05a3e7c`** the pbxproj four-ids note.

## What each stage cost that nobody predicted

- **`.autoClamped` needs a handle-*tip* value clamp, not the local-extremum flattening it is usually
  described as.** Keys at 0, 1, 10 have no extremum anywhere, yet the plain auto tangent drags the
  *first* segment to **−0.13** — a value going negative between two positive keys, in the mode whose
  whole job is preventing that. Clamping each tip into the interval between its own key and its
  neighbour subsumes the extremum case and turns a heuristic into a proof, since all four of a segment's
  value controls then lie between the key values and a cubic Bézier is a convex combination of them.
- **UI range and model domain differ in 22 of 25 parameters, not the two the brief guessed.** Only
  outline width, outline threshold and bloom threshold agree; most grades clamp nothing, so the model
  domain is infinite. **You can key a value past where the slider will drag.**
- **Three parameters quantise to whole pixels, not one.** `Blur.radius`, `Bloom.radius` and
  `Sharpen.radius` all reach `tapCount`, so radius 8.0 and 8.4 are byte-identical and an animated ramp
  renders as stairs. Recorded in the descriptor rather than left to be reported as a bug.
- **The cache-key test the stage-2 brief specified would have been vacuous.** Both sandwich keys carry
  `frame` outright, so two keys at two frames differ on unmodified `main`. The pin holds `frame` equal
  and derives the tree twice. The cache that would actually serve stale pixels is `MaskResolver`'s.
- **`withStructureUndo` is not a deep copy** — `StructureSnapshot`'s own doc says `Cel.raster`/`vector`
  are class references, shared not duplicated, and the 4096 is declared rather than measured. Avoiding
  it for keyframe writes is still right, but because of its equality early-out, not its price.
- **§10's `InterpolationPreviewKey` rule is not blanket.** It binds channels that feed the in-between
  *drawing* evaluation; a layer grade is applied at composite time and owed the key nothing.

## Still open, unchanged

TODO (10) Oklab. `ARCHITECTURE_REVIEW.md` findings 2-4. BUGS.md carries the interactive-gesture CPU
composites, Fill/Clear on a derived in-between, the raster-storage bound, the unclamped zoom,
`TextFrame.homography` decoding with no validity check, and PERFORMANCE.md item 14.

Two behaviour questions are owed: save semantics when a project loaded with something unreadable, and
which faces belong in the font picker's favourites strip. Four judgement calls wait on real artwork,
none of them defects.

One latent defect found and **not** filed, because it is unreachable: `MonotoneCubic`'s documented
"the later duplicate wins" is undefined — the dedup filter runs after `sorted(by:)`, which is introsort
and not stable. `CurveEditor` blocks duplicates upstream, so nothing can reach it.
