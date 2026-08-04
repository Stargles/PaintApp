# Vector Interpolation — Handoff & Session Protocol

**If you are a fresh session picking up this work, read this file first, then follow §1.**

This is the *live* document. [VECTOR_INTERPOLATION_PLAN.md](VECTOR_INTERPOLATION_PLAN.md) (why) and
[VECTOR_INTERPOLATION_IMPLEMENTATION.md](VECTOR_INTERPOLATION_IMPLEMENTATION.md) (what, in order) are
stable references. This file is state: where the work actually is, what tripped over what, and what
to do next.

[VECTOR_ERASER_PLAN.md](VECTOR_ERASER_PLAN.md) is the fourth document you may end up in. The eraser
feature is finished, but that plan is cited from ~20 source files as the authority for decisions this
work depends on — "the eraser is a stroke" (§2.1), the display-list z-order (§2.2), erasing through
everything (§1) — and §12 holds its unstarted backlog. Its session-state handoff was deleted on
2026-07-31; the plan is the one eraser document now.

---

## 1. Start-of-session checklist

Do these in order. Do not skip 1.4 — sessions that skip it re-derive things that are already written
down, and burn the budget doing it.

1. **`git fetch origin && git status`** — confirm the branch and that the tree is clean.
2. **Read §2 (Current state)** of this file. That is the single source of truth for where the work is.
3. **Read the current phase's section** in `VECTOR_INTERPOLATION_IMPLEMENTATION.md`.
4. **Read §5 (Carry-overs)** of this file. These are non-obvious constraints earlier sessions paid to
   discover. They are not in the plan because they were not knowable until code was written.
5. **Skim `VECTOR_INTERPOLATION_PLAN.md` §0** (the product owner's brief) if you need the *why* for a
   design choice. Read §10 (Decisions) before proposing any change to an existing decision.
6. Run the fast test suite (§4) to confirm you are starting from green. **If it is red, stop and
   report — do not build on a broken tree.**

### Reading budget

Do not read all four documents in full every session. The plan is long and mostly rationale you do not
need. Read what §1 says to read; consult the rest on demand.

---

## 2. Current state

> **Sessions: update this section before you finish, every time. It is the only thing the next
> session can rely on.**

| | |
|---|---|
| **Current phase** | **Phase 5 — motion groups. In progress, roughly half done.** The engine and model half is built and committed (`2870773`); **no UI reaches any of it yet**, and there are **no new tests**. See "Where Phase 5 actually is" below — it is the thing to read before writing a line of code. |
| **Branch** | `claude/vector-interpolation-design-9d5b83`, **pushed; tracks `origin/`**. Rebased onto `origin/main` as of Session 8. |
| **Last known-green commit** | `2870773` — Phase 5's engine half. Builds; `InterpolationWorkflowLogicTests`, `InterpolationModelLogicTests`, `InterpolationRenderLogicTests` and `ARAPLogicTests` all pass. The last full fast-tier run is `ea85793`: 224 tests, 223 passed (see §5 for the one flake and why it is not real). The last *full*-suite run is still Session 9's 4.6 boundary: 512 tests, 511 passed, 0 failed, 1 skipped. |
| **Tree state** | Clean. |
| **Blocked on** | Nothing. |

**Papers: supplied and read — do not re-request.** [MoStyle/frite](https://github.com/MoStyle/frite)
and [Inria RR-9559](https://inria.hal.science/hal-04797216/file/RR-9559.pdf). **§5.11 is the
comparison**; the short version is that RR-9559 assumes registration is already solved, frite has no
global rotation search at all (which is our bug), and neither solves N→M stroke matching — the artist
does it, with a lasso. The product owner has also granted standing permission to **fork the repos and
experiment on the forks**.

**Experiment before you believe a fix.** `Engine/Deform` compiles standalone with `swiftc` (~5s a
loop, vs ~90s through `xcodebuild test`) — see §5's first Phase 4.7 entry. Session 10 refuted three
plausible fixes that way, one of which the reading positively recommended. Do not carry a hypothesis
from the papers into the engine untested.

**The XCUITest flakiness that cost Session 5 hours was the simulator, and erasing it fixed it.**
Session 6 opened by resetting `interp-ipad` (`simctl shutdown` + `erase`, §5) and then ran the full
suite **twice, both clean first time**: 433/433 on the unchanged Phase 2 tree, and 450/450 with
Phase 3 in. Session 5 never got a clean run in five attempts on effectively the same code. Do the
reset *before* the phase-boundary run, not after it starts failing.

### What is done

- Design and research complete. Engine chosen (lattice + ARAP over stroke correspondence); every
  product decision resolved and recorded in `PLAN.md` §10.
- **`PLAN.md`** — the product owner's brief (§0), rationale, architecture, decisions, standing
  constraints.
- **`IMPLEMENTATION.md`** — eight phases, each with work items, files, tests, acceptance criteria and
  a definition of done; plus the feature-level definition of done and the deferred list.
- **This file** — the session protocol.
- Environment verified end to end: Xcode 26.6, dedicated simulator `interp-ipad` created, baseline
  pure-logic suite green (exit 0), Accelerate sparse solver confirmed present on iOS (§5).
- **Phase 0 — Onion-skin seam and the vector onion-skin bug.** `CanvasView`'s onion skin now routes
  through `PixelOps.rasterize(cel:canvasSize:)` instead of reading `cel.raster` directly, so a
  `.vector` cel onion-skins correctly instead of blank. Added `OnionSkinSource`/`OnionSkinFrame`
  ([OnionSkinSource.swift](PaintSoftware/Views/OnionSkinSource.swift)) — the coordinator now asks a
  pluggable source what to show; `PreviousCelOnionSkinSource` reproduces today's "previous cel on the
  current layer" behaviour. New `OnionSkinLogicTests` (3 tests, all green). Definition of done met.

- **Phase 1 — the lattice + ARAP deformation engine.** New module `PaintSoftware/Engine/Deform/`,
  five files, importing only `Accelerate`, `CoreGraphics` and `Foundation` — no app type appears
  anywhere in it (standing constraint A). All eight work items done; definition of done met.
  - [Lattice.swift](PaintSoftware/Engine/Deform/Lattice.swift) — rest vs current configuration,
    `embedInRest`/`warp` (closed form), `embedInCurrent` (the inverse map, via inverse bilinear),
    and `expanded(toContain:)` with `LatticeExpansion`'s index translation.
  - [DeformFactorization.swift](PaintSoftware/Engine/Deform/DeformFactorization.swift) —
    `Matrix2x2` + polar decomposition, the Accelerate sparse Cholesky wrapper, and the ARAP normal
    equations. One factorisation per topology; every *t* is two back-substitutions.
  - [ARAPInterpolation.swift](PaintSoftware/Engine/Deform/ARAPInterpolation.swift) — per-triangle
    polar interpolation plus one global reconciling solve. **`t = 0` reproduces A and `t = 1`
    reproduces C to the last bits, through the general path.**
  - [ARAPRegistration.swift](PaintSoftware/Engine/Deform/ARAPRegistration.swift) — `PointCloudIndex`,
    `Similarity`, bidirectional multi-start ICP, and the ARAP fit with positional constraints.
  - [MotionGrouping.swift](PaintSoftware/Engine/Deform/MotionGrouping.swift) — coarse-to-fine
    splitting, one algorithm with two seeds.
  - Tests: `LatticeLogicTests` (29) and `ARAPLogicTests` (39). Fast suite 134 green.
  - Commits: `bae6a9c`, `20008a1`, `2f9fa1e`, `131e0d1`, `5e5785e`.

- **Phase 2 — data model, persistence and undo.** All nine work items; the feature is still inert
  (nothing in the app reads any of it). One commit, `49906ea`.
  - New: [InterpolationRecipe.swift](PaintSoftware/Models/InterpolationRecipe.swift) (`CelRef`,
    `InterpolationReference`, `InterpolationMode`, `SpacingCurve`, `MotionGroupBinding`, `LocalEdit`,
    `InterpolationRecipe`), [MotionGroup.swift](PaintSoftware/Models/MotionGroup.swift),
    [GuideStroke.swift](PaintSoftware/Models/GuideStroke.swift) (`TimedSample`, `GuideRole`,
    `KeyframeInterval`, `GuideStroke`),
    [CanvasManager+Interpolation.swift](PaintSoftware/Models/CanvasManager+Interpolation.swift)
    (every mutation, with its undo bracket; plus render-cache eviction).
  - Changed: `Cel.interpolation`; three optional fields on `VectorStroke` (`motionGroupID`,
    `visibilityThreshold`, `sampleVisibilityThresholds`); `Lattice: Codable`; `motionGroups` /
    `guideStrokes` on `CanvasManager` and in `StructureSnapshot`; manifest + store; `CodableColor`
    gained `Equatable`; `VectorCanvas.dropCachedImage()` / `hasCachedImage`.
  - Tests: `InterpolationModelLogicTests` (28).
  - Five full-suite attempts never produced a clean run, with a *different* set of tests failing each
    time and none failing twice. Session 6 established this was the simulator, not the code: one
    `simctl erase` and the same tree ran 433/433. See §2's note and §5's `failed to launch` entry.

- **Phase 3 — evaluation, isolated compositing and the preview tier.** All five work items; the
  feature is still inert. One commit, `f6986df`.
  - New: [InterpolationEvaluator.swift](PaintSoftware/Engine/InterpolationEvaluator.swift) —
    `evaluate(recipe:at:content:)` → forward/backward/localEdit display lists plus the two blend
    weights, and `composite(_:size:quality:)` / `render(recipe:at:size:…)` on top of it.
  - Changed: `RenderQuality`, `VectorCanvas.render(quality:)` and a second cache slot; the polyline
    preview drawing helper. **`renderLocalContent`'s element-walking logic is untouched** — only the
    per-stroke draw call branches on quality.
  - Tests: `InterpolationRenderLogicTests` (17). `t = 0` reproduces keyframe A and `t = 1` reproduces
    keyframe C at **zero** pixel tolerance, through the general path.

- **Phase 4 — interpolate mode UI, references, slider, Generate.** All six work items; **the feature
  is no longer inert.** Commits `6486f0e`, `3fa697a`, `e8b35da`, `39f4365`.
  - New: [InterpolatePanel.swift](PaintSoftware/Views/InterpolatePanel.swift) (mode toggle, Generate
    and Reproject as separate commands with their refusal reasons, the `t` slider, Remove
    Interpolation, the thickness-fade toggle) and `InterpolationReferenceOnionSkinSource` in
    [OnionSkinSource.swift](PaintSoftware/Views/OnionSkinSource.swift).
  - Changed: `CanvasManager` (`isInterpolateMode`, `interpolationReferences`,
    `interpolationThicknessFade`, `isRegisteringInterpolation`, `isScrubbingInterpolation`);
    `CanvasManager+Interpolation` (mode entry/exit, reference toggling, keyframe grouping,
    `interpolationContentProvider`, registration, `interpolate(mode:)` and its refusals,
    `interpolatedImage`); `TimelineTrackView` (the gesture split and the yellow highlight);
    `CanvasView` (the memoized preview pass and the mode-swapped onion skin); `StrokeCanvasView`
    (`setInterpolationImage`); `TopToolbar`/`DrawingView` (`ActivePanel.interpolate`);
    `CanvasManager+Timeline` (`addCel` now matches the layer's kind — see §5).
  - Tests: `InterpolationWorkflowLogicTests` (24) plus **one** XCUITest,
    `testInterpolateModeEndToEndFromGestureToScrub`.
  - **Reproject is stubbed** — it refuses with `.reprojectNotImplemented` rather than quietly
    behaving like Generate. Phase 6 item 1 owns it.

- **Phase 4.5 — the UI pass.** Not a planned phase: the product owner used Phase 4 on an iPad and
  gave layout feedback, and tying the layout down before Phase 5 builds motion-group UI on top of it
  was worth a session. Scope was UI only — the evaluator, the recipe and the undo mapping are
  untouched.
  - New: [InterpolateBar.swift](PaintSoftware/Views/InterpolateBar.swift) — **Set as Reference,
    Generate, Reproject and the timing bar, pinned directly above the animation timeline**, where
    the blocks they act on are visible. `InterpolatePanel` keeps only the mode switch and the
    settings that are set once (thickness fade, Clear References, Remove Interpolation).
  - **Press-and-hold on a timeline block means drag-reorder again, in every mode.** Phase 4's
    mode-switched recognizer is gone, along with `Coordinator.toggleReference` — the product owner
    scrapped it on sight, because it cost re-timing exactly while the artist is working on timing.
  - The claim that mode entry runs registration is **gone from the code and the plan**. Registration
    runs when Generate or Reproject is pressed, which is where it always ran; `IMPLEMENTATION.md`
    Phase 4 item 1 now says so rather than contradicting it.
  - The e2e XCUITest drives the bar's buttons instead of the block gesture. Still exactly one.

- **Phase 4.6 — the second UI pass, and the layout is now settled.** A second round of product-owner
  feedback from the same iPad build. Again UI only; the engine is untouched. `IMPLEMENTATION.md`
  Phase 4's "Phases 4.5 and 4.6" subsection is the record of the final shape.
  - **The entry point moved to the animation timeline's top bar** (`interpolateButton`, next to onion
    skin and loop) and is two-stage like the paint tools: tap once to enter the mode, tap again to
    open the options popover. `InterpolatePanel` is that popover — thickness fade, Clear References,
    Exit Interpolate Mode — with **no mode switch in it**, because the button is the switch.
    `ActivePanel.interpolate` and the canvas toolbar's interpolate icon are gone.
  - **The bar is two rows**: the timing slider on top, then reference counter far left · Set as
    Reference / **Generate** / Reproject centred on Generate · Remove Interpolation far right.
  - **Generate works from an empty slot** — `interpolateAtPlayhead` creates the block and attaches
    the recipe in one undo step (§8 items 21–23 done; this one was new this session).
  - **Generate is disabled on an already-interpolated cel** (`.alreadyInterpolated`). Reproject does
    not inherit it.

- **Phase 4.7 — engine correctness. All four failing drawings fixed.** Four commits: `b9100af`,
  `8a46b77`, `8733589`, `ea85793`. The engine changes are `ARAPRegistration.swift` and three lines
  of `MotionGrouping.swift`; the app change is `CanvasManager+Interpolation.swift`'s registration
  entry point. Nothing in the evaluator, the recipe, the UI or persistence was touched.
  - **`PointCloudIndex.nearest` walks the ring, not the (2·ring+1)² block** (item 28). Residuals
    bit-identical over 18,500 queries on seven cloud shapes; 250 samples 12 s → 412 ms.
  - **`icpRestarts: 1` and `allowScale: false`, together** (item 32). The multi-start was what
    *created* the 180° flip; the free scale was what bought a good residual by collapsing. Case 30's
    span at *t* = 1 went from 51 to 194.6 of the target's 200.
  - **Tier 0: the 1:1 arc-length correspondence** (item 31), which is what makes a line bend into a
    C: case 29's bend 0.17 → 0.985 against the C's own 1.072, ink coverage 0.31 → 0.96. `N:M` stays
    deferred and falls back to the point-cloud path.
  - **The registration cloud is capped at 250 samples** (item 35). Cost is now *flat* in the sample
    count: 2000 samples went 285 s → 78 ms, at coverage 1.00.
  - Tests: `InterpolationEngineDiagnosticsLogicTests` lost all three expected-failure wrappers and
    gained two characterisations; `ARAPLogicTests` gained seven. Wider pure-logic tier green.

- **Phase 5 — motion groups. HALF DONE.** One commit, `2870773`. The engine and model half only;
  see the next section for exactly what is missing.

### Where Phase 5 actually is

**Built and committed (`2870773`), all in `CanvasManager+Interpolation.swift`:**

- **`RegistrationFrame` now holds `RegistrationElement`s** (points, stroke-or-nil, tag) rather than a
  summed cloud, plus `restricted(to:)` — the slice that lets a keyframe be cut down to one part.
  A part made entirely of strokes keeps its 1:1 correspondence even when a *fill* elsewhere on the
  frame made the whole frame's `strokes` nil, which is exactly the lineart-plus-flats case.
- **`registerGroups(frames:existing:)`** — Phase 5's registration. `MotionGrouping` seeded by the
  artist's tags (PLAN §5.3's one algorithm, two seeds), grouping measured against the **last**
  keyframe, one lattice per part fitted to that part's own counterpart. Returns
  `GroupRegistration { bindings, invented, assignments }`.
- **The whole-frame answer is preserved exactly.** A drawing that groups into one part takes the
  Phase 4 path unchanged — one anonymous binding, no registered `MotionGroup`, no tags written. That
  is why every Phase 4 test stayed green without being touched.
- **Tags are written back onto both keyframes' strokes** (`applyMotionGroupTags`). This is the part
  that is easy to leave out and the part that makes the feature usable: without it the partition
  lives only inside the recipe's bindings, where nothing can show it and nothing can correct it.
- **`setMotionGroup` re-registers** every recipe reading a touched cel, in the same undo step
  (`reregisterInterpolations(reading:)`), so a retag changes the *motion* and not only the colour.
- **`tagMotionGroupsByStrokeColour(in:tolerance:)`** — PLAN §5.1.1's one-shot populate. Erasers
  skipped; refuses when there is only one colour.
- **Generate's undo bracket widened** from `withStructureUndo` to `withInterpolationUndo`, because
  it now writes stroke content. `interpolateAtPlayhead`'s outer bracket widened with it.

**NOT built. This is the whole of what is left:**

1. **No tests at all for any of the above.** This is the single highest-value next action and it is
   where the next session should start. The fixture to use is already written and known-good:
   `ARAPLogicTests.rectangleBody` + `triangleBody`, rect moved `+40` in x and the triangle left
   still — see `testTwoBodiesMovingDifferentlySplitIntoExactlyTwoGroups`. **Do not invent a new
   two-body fixture**; §5's Phase 1 entry lists four that looked obviously correct and were not.
   A new `InterpolationMotionGroupLogicTests` class needs a hand-edit to the UITests target's
   pbxproj (§5), and must be added to §4's fast filter.
2. **No UI whatsoever.** Nothing in the app can reach tagging, the colour bake, group modes, or
   solo/mute. `InterpolateBar` and `InterpolatePanel` are untouched. This is `IMPLEMENTATION.md`
   Phase 5 items 2, 3 and 4.
3. **No manual retagging gesture.** `setMotionGroup(_:forStrokeIDs:)` is the whole API and nothing
   calls it. The intended shape is: arm a group from its chip on the bar, then tap strokes on the
   canvas to assign them — hit-tested through `StrokeSpatialIndex`. §5.10's rule applies: put it on
   the bar, not on a timeline gesture.
4. **No "what did it decide?" overlay, and no solo/mute.** The cheap route for the overlay is the
   seam that already exists — `StrokeCanvasView.setInterpolationImage` — with a tinted polyline
   render of the cel's strokes in their groups' tag colours. Solo/mute wants a `hiddenGroups` set on
   `InterpolationEvaluator.Options`, and **it must go into `InterpolationPreviewKey` too** or it will
   appear to do nothing (§5, Phase 4).
5. **The per-group `.auto`/`.clean`/`.crossFade` badge** (`IMPLEMENTATION.md` Phase 5 item 3).
   `setMotionGroupMode` exists and is untested; nothing displays the mode, and `.clean` degrading to
   `.crossFade` has no visible state.

**One thing to put in front of the product owner before going further** (§3.5): **Generate now
writes motion-group tags onto the keyframes' strokes.** That is a real behaviour change — pressing
Generate modifies the reference drawings, not only the in-between. It is undoable in the same step
and the tags are inert outside interpolate mode, and it is what makes auto-grouping correctable at
all, so it is believed to be the right call. It was not a recorded decision, so say it out loud.

### What is next after that

**Read §5.10 before touching Phase 5** — what Phase 4 decided that Phase 5 inherits, as amended by
4.5 and 4.6 — and **§8 item 36's timing note**, which puts exactly one constraint on Phase 5's
design (keep a group's membership "which ink is in this group", not "which stroke pairs with which").
The design as built honours that: membership is a tag on a stroke, and nothing anywhere records that
stroke *X* pairs with stroke *Y*.

Two things 4.7 leaves on the table deliberately, both recorded rather than built: §8 item 24's
~10 fps scrub, which is a *separate* problem from registration cost and is still unfixed (§8 item 14's
`ScrubSession` is the shape of the fix), and §8 item 34's temporal visibility thresholds, which are
the honest answer to unmatched content and now have a way to know which content is unmatched.

### History note

A prior session launched a five-agent design workflow to produce the phasing and was cut off by its
usage limit before any agent returned; nothing was captured and the phasing was written directly
instead. That is why §3.4 exists. Do not re-run it — `IMPLEMENTATION.md` is complete.

---

## 3. Session protocol

### 3.1 Commit early, commit often

**Commit at every green checkpoint, not at the end of the session.** A session can be cut off at any
moment; uncommitted work is lost work.

- After each work item that builds and passes tests: commit it.
- Commit message: `interp(phase N): <what changed>`.
- If you must stop mid-item, commit anyway as `interp(phase N): WIP — <exact state>` and describe the
  half-finished state in §2. A WIP commit that builds is strongly preferred; if it does not build, say
  so **in the commit message itself**.
- Never edit `main`. This work lives on its branch.

### 3.2 The >92% usage handoff

The product owner will interrupt with a prompt when session usage approaches its limit. When that
happens, **stop feature work immediately** and do exactly this, in order:

1. **Commit** everything, WIP or not (§3.1).
2. **Update §2** of this file: current phase, last green commit, tree state, precisely what is
   half-done, and anything blocked.
3. **Append to §5** any carry-over you discovered this session — non-obvious constraints, dead ends,
   things that surprised you. This is the highest-value thing you write; it stops the next session
   repeating your mistakes.
4. **Append a line to §6** (Session log).
5. **Commit those doc updates.**
6. **Output the handoff prompt** for the next session, using the template in §7. Print it in a single
   fenced block so it can be copied in one action.

Do not start anything new once the handoff is requested. Finishing the handoff cleanly is worth more
than one more work item.

### 3.3 Scope discipline — when to stop

**When the feature's definition of done (in `IMPLEMENTATION.md`) is met, stop and say so.**

Do not keep finding more work. This project has an explicit end state, and reaching it is success.

If you notice further improvements — and you will — **write them down as suggestions and let the
product owner decide.** Add them to §8 (Suggested follow-on work) and mention them in your final
message. Do not implement them. Do not fold them into the current phase because they are "small".

The same applies within a phase: if you find work that belongs to a later phase, note it and move on.

### 3.4 Subagent budget — hard limits

**A design session burned its entire budget on five parallel Opus agents and captured nothing.** They
were still exploring when the limit hit, so all five transcripts were discarded whole. Do not repeat
this. The rules below are not guidance.

- **Maximum 2 subagents running at once.** Never five. Prefer **1**, and prefer **none** — if you have
  the context to do the task yourself, do it yourself. Spawning costs a cold start that re-derives
  what you already know.
- **Never fan out on a task you could finish inline.** Writing a document from decisions already
  recorded is inline work, not agent work.
- **Prefer short, well-scoped agent tasks that finish fast** over deep ones that may be cut off
  mid-flight. An agent that returns something small beats one that returns nothing.
- **Do not launch a multi-agent workflow without the product owner explicitly asking.** "ultracode" in
  their prompt, or a direct request, is the gate.

#### Model and effort, per task shape

Pick deliberately; do not default everything to Opus.

| Task shape | Model | Effort | Notes |
|---|---|---|---|
| Locate code, "where is X", broad search | **Sonnet 5** | low–medium | Use the `Explore` agent. Cheap and fast; this is most searching. |
| Mechanical multi-file edit from a precise spec | **Sonnet 5** | medium | Rename, thread a parameter, apply a known pattern. |
| Writing tests from an existing spec | **Sonnet 5** | medium | The spec is the hard part and it is already written. |
| Persistence / round-trip / back-compat work | **Sonnet 5** | medium | Pattern-following; the pattern is in `VectorStroke`. |
| UI wiring following an existing precedent | **Sonnet 5** | medium | e.g. plumbing mode state the way `VectorEraserMode` is plumbed. |
| **ARAP / numerics design or debugging** | **Opus 5** | high | Phase 1. Genuinely hard; the place Opus earns its cost. |
| **Debugging a subtle render/compositing bug** | **Opus 5** | high | e.g. the §5.6 isolation rule, dab-lattice-class problems. |
| **Adversarial review of a completed phase** | **Opus 5** | high | Worth it at phase boundaries; not mid-phase. |
| Anything touching a recorded product decision | **Opus 5** | high | And surface it to the product owner (§3.5). |

Default when genuinely unsure: **Sonnet 5, medium**, scoped small. Escalate to Opus only when the task
is actually hard, not merely important.

### 3.5 Never silently change a decision

`PLAN.md` §10 records decisions the product owner made. If implementation shows one is wrong, **stop
and say so** with the evidence. Do not quietly implement something else. Changing a recorded decision
is the product owner's call, not yours.

---

## 4. Build and test

**The Mac is local.** Ignore the Tailscale/SSH section in [CLAUDE.md](CLAUDE.md) — that is for the
Windows machine. Run `xcodebuild` directly.

Dedicated simulator for this project: **`interp-ipad`** (iPad Pro 13-inch M5, iOS 26.5). Use it rather
than a shared one, so concurrent sessions do not contend.

### Fast run — pure logic only (~1–2 min). Use this constantly.

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/OnionSkinLogicTests -only-testing:PaintSoftwareUITests/LatticeLogicTests -only-testing:PaintSoftwareUITests/ARAPLogicTests -only-testing:PaintSoftwareUITests/InterpolationModelLogicTests -only-testing:PaintSoftwareUITests/InterpolationRenderLogicTests -only-testing:PaintSoftwareUITests/InterpolationWorkflowLogicTests -only-testing:PaintSoftwareUITests/InterpolationEngineDiagnosticsLogicTests
```

215 tests as of `46e75c1` — 212 passing plus **three expected failures**, which are Phase 4.7's
pinned engine bugs (`InterpolationEngineDiagnosticsLogicTests`) and are a green run, not a red one.
`** TEST SUCCEEDED **` is the thing to check. If one of those three ever reports *"expected failure
but none recorded"*, the engine has changed under you — go read that test's comment before
assuming it is flaky. Add your own logic-test class to that filter as you create it.

**Wider, still fast (~4 min).** Every pure-logic class in the suite — 388 tests as of `39f4365`.
Worth running before a commit that touches persistence, rendering or `CanvasManager`, since the fast
filter above misses `ProjectSaveLogicTests`, the eraser classes and the characterisation tests:

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/OnionSkinLogicTests -only-testing:PaintSoftwareUITests/LatticeLogicTests -only-testing:PaintSoftwareUITests/ARAPLogicTests -only-testing:PaintSoftwareUITests/InterpolationModelLogicTests -only-testing:PaintSoftwareUITests/InterpolationRenderLogicTests -only-testing:PaintSoftwareUITests/InterpolationWorkflowLogicTests -only-testing:PaintSoftwareUITests/StrokeGeometryLogicTests -only-testing:PaintSoftwareUITests/VectorEraserLogicTests -only-testing:PaintSoftwareUITests/VectorEraserHybridLogicTests -only-testing:PaintSoftwareUITests/RasterVectorParityLogicTests -only-testing:PaintSoftwareUITests/ProjectSaveLogicTests -only-testing:PaintSoftwareUITests/BackupManagerLogicTests -only-testing:PaintSoftwareUITests/CelCRUDCharacterizationTests -only-testing:PaintSoftwareUITests/LayerTreeCharacterizationTests -only-testing:PaintSoftwareUITests/ViewPresetCharacterizationTests
```

### Reading a failure

`xcodebuild` prints `Test case '…' failed` and **not the assertion message** (§5). To see why:

```bash
xcrun xcresulttool get test-results test-details --test-id 'ARAPLogicTests/testTZeroReproducesLatticeAExactly()' --path "$(ls -dt /tmp/interp-dd/Logs/Test/*.xcresult | head -1)" --format json
```

The messages are the `name` fields of the `Test Case Run` nodes.

### Build only — fastest possible check that it compiles

```bash
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd
```

### Full run (~22 min, 63 XCUITests). Rarely — at phase boundaries only.

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd
```

**Budget note:** XCUITests are 99.3% of suite runtime ([REFACTOR_BASELINE.md](REFACTOR_BASELINE.md)).
Write logic tests, run the fast filter constantly, and save the full run for the end of a phase.
Reusing `-derivedDataPath /tmp/interp-dd` keeps incremental builds fast — do not clean it casually.

### After changing code

```bash
graphify update .
```

Cheap (AST-only, no API cost) and keeps the knowledge graph usable for the next session. Commit a
refreshed `graphify-out/GRAPH_REPORT.md` when it changes meaningfully.

---

## 5. Carry-overs

> Non-obvious constraints discovered during implementation. **Append here whenever something
> surprises you.** Each entry: what you expected, what was true, what to do about it.

Pre-existing constraints inherited from the design phase are in `PLAN.md` §2 ("Gaps found") and §10
("Standing constraints"). Verified facts recorded before implementation began:

- **Accelerate's sparse solver is available on iOS — verified, do not re-investigate.**
  `SparseFactor()` / `SparseSolve()` with Cholesky and QR factorisations are present in the iOS SDK
  at `Accelerate.framework/Frameworks/vecLib.framework/Headers/Sparse/Solve.h` (checked against
  iPhoneSimulator26.5.sdk). This is exactly the shape ARAP wants: factorise once per lattice topology,
  back-substitute per *t*. `import Accelerate`. No third-party solver is needed, and hand-rolling
  Gauss-Seidel is not necessary as a first resort.
- **The baseline was green before any feature work started.** `BrushEngineLogicTests` +
  `ShapeDetectorLogicTests` pass on `interp-ipad` (exit 0). If they fail for you, it is your change.
- **Simulator `interp-ipad` exists** (iPad Pro 13-inch M5, iOS 26.5, UUID
  `16B39106-1805-425B-BB75-02D436D36533`). Recreate with
  `xcrun simctl create "interp-ipad" "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"`
  if it goes missing. Note the device-type identifier has a RAM suffix (`-12GB`); the bare
  `iPad-Pro-13-inch-M5` is rejected.
- **The project file has no file-system-synchronized group for the app target's Sources phase** — that
  phase (`3FC5E351300DBDA400401D35`) is empty in `project.pbxproj`; Xcode auto-includes anything under
  `PaintSoftware/` by folder, so a new app source file needs no pbxproj edit. The **UITests target**
  (`8F45156FC43DA86204566A6D`) is still old-style and explicit: a new file that must compile into
  `PaintSoftwareUITests` (a pure-logic test, or an app source a logic test depends on) needs a
  `PBXFileReference` + `PBXBuildFile` pair added by hand, plus an entry in that Sources build phase's
  `files` list — see how `OnionSkinSource.swift`/`OnionSkinLogicTests.swift` were added for the
  pattern. `plutil -lint project.pbxproj` after editing it catches a malformed edit before you waste a
  build on it.
- **`PixelOps.rasterize(cel:canvasSize:)` composites more than the old onion-skin code showed for a
  raster layer.** The old code read `cel.raster.renderToUIImage()` only — live strokes, nothing else.
  `rasterize(cel:)` also draws `fillImage` and `bakedImage` underneath. For a plain cel (no fill/bake
  ops applied) these are nil and it's a no-op, so it's identical in the common case, but a raster cel
  that has had select-move/fill/clear applied will now onion-skin *more* content than before — a
  strict superset, not a regression, but worth knowing about since `IMPLEMENTATION.md`'s Phase 0
  definition of done says "behaviour-identical to today for raster layers" and this is not quite that
  in the fill/bake case. Work item 1 explicitly names `PixelOps.rasterize(cel:)` as the mechanism, so
  this was taken as the intended tradeoff rather than a bug — flagging per §3.5 in case the product
  owner disagrees.

### From Phase 1

- **`plutil -lint` does not catch a duplicate object ID in `project.pbxproj`.** It only checks plist
  syntax. Reusing an ID that was already taken (`DEC0DE…50`, which belonged to
  `CanvasManager+Timeline.swift`) linted clean and then made Xcode refuse the whole project with
  `-[PBXFileReference buildPhase]: unrecognized selector`, which points nowhere near the real cause.
  **After editing the pbxproj, check for collisions as well as lint**, and prefer a fresh ID prefix:

  ```bash
  grep -oE "DEC0DE[0-9A-F]{18}" PaintSoftware.xcodeproj/project.pbxproj | sort | uniq -c | awk '$1>3'
  ```
  A file reference legitimately appears 3 times and a build file 2, so anything above 3 is a
  collision. `xcodebuild -list` is the cheap end-to-end confirmation.

- **XCTest assertion messages do not appear in `xcodebuild`'s console output** in this project's
  configuration — you get `Test case '…' failed` and nothing else, which makes numeric debugging
  impossible. Pull them out of the result bundle instead:
  `xcrun xcresulttool get test-results test-details --test-id '<Class>/<test>()' --path <newest .xcresult> --format json`,
  and read the `Test Case Run` nodes' `name` fields. A `XCTFail(report)` with an interpolated string
  is the quickest way to probe numbers from inside a test.

- **Writing test fixtures for registration is harder than writing the registration.** Three separate
  fixtures asserted things that were simply not true of the geometry, and each looked obviously
  correct:
  - Bodies made of parallel strokes pin neither orientation nor position — point matching slides
    freely along them — so ICP explained two separately-moving bodies as one 153° rotation to within
    2.6 points.
  - "Two bodies move opposite ways" **is** a rigid rotation of the pair. One motion group is correct.
  - "One body moves sideways, the other stays" is *nearly* a rotation about the still one; at a
    70-point move across a 180-point gap the leftover error was 4.1 points, inside any sane
    threshold. Only motion **along the line joining the bodies** changes their separation, which no
    rigid motion can do.
  - Evenly spaced identical strokes alias: every stroke finds a neighbour's target nearer than its
    own. Use closed, unequal-sided outlines and irregular arrangements.

- **Automatic grouping does not reliably separate an attached limb from its torso.** There is no
  spatial gap to cut on, and residuals are a weak signal precisely there, because a fitted rotation
  makes each stroke's residual depend on where it sits. Tag-seeded grouping handles it and is
  characterised by a test. This is a known limitation, documented on `MotionGrouping` — see §8.

### 5.7 The lattice encoding — *answered, kept for the constraint*

Phase 1 left `Lattice`'s encoding to Phase 2, which chose it: the rest configuration is never written
(it is `cols`/`rows`/`restOrigin`/`restCellSize`, four numbers, so `vertices` is omitted entirely for
a rest lattice and rebuilt on decode) and **no indices are persisted at all**.

The second half of that is the part still worth knowing, because it constrains every later phase:
`LatticeExpansion` exists because adding a ring shifts every cell and vertex index, so anything
persisted that indexes into a lattice — an embedding, a per-cell attribute, a pinned vertex — must be
re-mapped when the lattice grows, or version-stamped so a stale index is detected rather than
silently misread. Storing no indices is what makes the current encoding expansion-proof, and it is
why the evaluator derives embeddings instead of caching them (§5.8).

### From Phase 2

- **`withStructureUndo` does not cover a stroke edit, and `IMPLEMENTATION.md` item 8 reads as if it
  does.** `StructureSnapshot` copies `[Layer]`, but `Cel.vector` is a *class reference*, so the
  snapshot shares each `VectorCanvas` rather than copying it: restoring it restores frame ranges,
  folder membership and recipes, and nothing whatsoever about the strokes inside. That is exactly
  right for a timeline edit and exactly wrong for a **group retag**, because the tag is a field on
  `VectorStroke`. Item 8 says "group retag → `withStructureUndo`"; taken literally that produces an
  undo step that silently does nothing.

  `CanvasManager.withInterpolationUndo(name:touching:)` is the fix — it snapshots the registries,
  the layer tree *and* the named canvases' display lists into one step. **Any later phase that edits
  stroke content from `CanvasManager` needs the same treatment**; the structure bracket alone is a
  trap. The slider drag is genuinely fine on `beginStructureGesture`/`commitStructureGesture`,
  because `t` lives in the `Cel` struct.

- **A degraded simulator fails XCUITests as a bare `XCTAssertTrue`, which looks exactly like a
  regression you just caused.** Two consecutive full runs failed differently — one test, then eight
  unrelated ones — every failure being `XCTAssertTrue(launchIntoEditor(app))` with no message, and
  `launchIntoEditor`'s own doc comment says it doubles as the launch-freeze regression test. It was
  neither. The log said so, well below the test output:

  ```
  Simulator device failed to launch Starg.PaintSoftwareUITests.xctrunner
    RequestDenied by SBMainWorkspace / FBProcessExit Code=64 "The process failed to launch."
  ```

  The **test runner harness** could not start, so the app under test never launched. It builds up
  over repeated runs that spawn parallel clones. **Check for `failed to launch` in the raw log before
  investigating a launch-assertion failure**, and reset the device rather than bisecting:

  ```bash
  pkill -f "xcodebuild test"; xcrun simctl shutdown 16B39106-1805-425B-BB75-02D436D36533; xcrun simctl erase 16B39106-1805-425B-BB75-02D436D36533
  ```

  The tell that it is environmental rather than a real regression: a *different* set of tests fails
  each run, and every failure is at launch rather than at an assertion about behaviour.

- **Do not build the timeline in a test with `addCel`.** `CanvasFixture.manager` gives each layer one
  cel spanning the whole 12-frame scene, so every `addCel` in frames 0–11 collides and returns
  `false`. Assign `layers[i].cels` directly (or use `CanvasFixture.setCelLayout`, which does not
  create `VectorCanvas`es) when the timeline is the premise rather than the subject.

### Settled — the reasoning now lives in the code

Eight engine facts from Phases 1–2 whose full explanation is commented at the site, often at more
length than it ever was here. Kept as one-liners so this section stays readable and so there is one
copy to keep true rather than two. **Read the linked comment before changing any of them** — each
records a measurement, and each is easy to undo by accident.

| Fact | Where the reasoning is |
|---|---|
| The ARAP solve is a correction to the anchor frame, not an absolute solve — the tiny anchor weight puts the condition number near 1e7 | [DeformFactorization.swift](PaintSoftware/Engine/Deform/DeformFactorization.swift) `solve`'s `anchors:` |
| The deformation energy is over **triangles**, not quads; a quad's map is bilinear and `t = 1` silently stops reproducing keyframe C | [Lattice.swift](PaintSoftware/Engine/Deform/Lattice.swift) `triangles` |
| ICP matches **both** ways, and restarts run to convergence rather than being screened cheaply | [ARAPRegistration.swift](PaintSoftware/Engine/Deform/ARAPRegistration.swift) `similarityICP` |
| A source→target fit with a free scale collapses when the source is only *part* of the target — `allowScale: false` | [ARAPRegistration.swift](PaintSoftware/Engine/Deform/ARAPRegistration.swift) `similarity` |
| `Lattice`'s encoder gates its rest-omission on `tolerance: 0`, not the default epsilon, or a save/load cycle drifts | [Lattice.swift](PaintSoftware/Engine/Deform/Lattice.swift) `encode(to:)` |
| A decoder must validate rather than reach a trapping initialiser — worth copying for any engine type made `Codable` later | [Lattice.swift](PaintSoftware/Engine/Deform/Lattice.swift) `init(from:)` |
| New stored properties keep the memberwise initialiser only if they have defaults *and* come last | [VectorLayer.swift](PaintSoftware/Engine/VectorLayer.swift) `VectorStroke` |
| Empty-means-everything is a trap when the thing can be emptied: deleting a motion group leaves its id dangling in guides rather than stripping it | [GuideStroke.swift](PaintSoftware/Models/GuideStroke.swift) `boundGroups`, `removeMotionGroup` |

### 5.8 For Phase 3's evaluator

What Phase 2 decided that Phase 3 inherits:

- **No embeddings are persisted, anywhere.** A `LatticeEmbedding` is derivable from geometry plus its
  lattice, and expansion invalidates every index in one — so the recipe stores geometry only, and the
  evaluator embeds on load. Do not "optimise" this by caching embeddings into the recipe without
  answering §5.7's re-map-or-version-stamp question first.
- **`t` is normalised across the *whole* reference span**, `0` at the first reference and `1` at the
  last — not per segment. With today's two references that is exactly the slider. Which segment a
  `t` between interior references lands in is the evaluator's choice (uniform is the obvious one),
  but note that once a spline ships, changing that mapping changes what an already-saved `t` means.
- **`InterpolationRecipe.mode` records Generate vs Reproject explicitly** rather than inferring it
  from whether the cel has content. §5.5 wants them to be two commands that are never conflated, and
  a cel can hold content under either (a `.generate` cel's content is derived; a `.reproject` cel's
  is the artist's own).
- **`isWellFormed` is the guard to check before evaluating.** A recipe can be malformed by editing
  *around* it — deleting a referenced cel, adding a reference without re-registering groups — and
  the evaluator should answer "not yet" rather than index off the end of `lattices`.
- **A recipe with no group bindings is legal**, and means "warp the whole frame as one group". It is
  the honest degenerate case (PLAN §10 decision 2), not an error.
- **Visibility is on the stroke**, as `visibilityThreshold` (whole-stroke τ) plus the sparse
  `sampleVisibilityThresholds`. A sample with no entry uses the whole-stroke value; nil means always
  visible. Erasers carry these like any other stroke, which is what §7.1 needs.

### From Phase 3

- **The simulator was the flakiness, and `simctl erase` is the fix — do it first, not last.** Session
  5 spent hours on five full-suite runs that failed differently every time. Session 6 shut down and
  erased `interp-ipad` before running anything and got 433 tests / 0 failures on the first attempt,
  on a tree that differed from Session 5's only in docs. Reset the device at the *start* of any
  phase-boundary full run.

- **`xcodebuild` printed no per-test output at all on the clean run.** No `Test Case '…' passed`
  lines, no `Executed N tests` summary — just `** TEST SUCCEEDED **`. Counting `Test Case` in the log
  to watch progress therefore reports zero for the entire run and looks like a hang. The result
  bundle is the source of truth for counts as well as for messages:

  ```bash
  B=$(ls -dt /tmp/interp-dd/Logs/Test/*.xcresult | head -1)
  xcrun xcresulttool get test-results summary --path "$B" --format json
  ```
  That gives `totalTestCount` / `passedTests` / `failedTests` / `skippedTests` directly. **One test is
  skipped by design** — `testFillToolBridgesOpenContourGapWhenGapClosingEnabled` — so 432/433 with one
  skip *is* a clean run, not a near miss.

- **Content that exists at one keyframe and not the other is invisible at the far endpoint, and that
  is the endpoint invariant, not a bug.** Three of this phase's tests were written asserting that a
  fill or a stroke present only in A was still visible at `t = 1`. It is not: at `t = 1` the frame *is*
  keyframe C, so the forward set's weight is 0. Read such content at `t = 0.9`, or assert on the
  evaluation rather than on pixels. Expect to trip over this once per phase that writes render tests.

- **Cross-fading two coincident opaque drawings gives 75% alpha at the midpoint, not 100%** —
  `½ + ½·½`. Mid-frames are visibly washed out relative to either keyframe. This is the known cost of
  engine C and precisely what engine D (correspondence) exists to fix (`PLAN.md` §3); it is not a
  compositing bug and no test should assert 255 at an interior `t`.

- **Thickness cross-fade is built but off by default, and the reason is a real gap.**
  `IMPLEMENTATION.md` Phase 3 item 1 asks for it and `PLAN.md` §7.1 wants fading content to *thin*
  rather than ghost. The mechanism is `InterpolationEvaluator.Options.thicknessFade` and it works.
  Defaulting it on would be wrong: thinning is right for a stroke with no counterpart at the other
  keyframe, and without correspondence *every* stroke looks like that, so both sets would thin and
  every mid-frame would be thin as well as washed out. Turning it on is one line the moment a matcher
  can identify unmatched strokes.

  **Product owner's steer (2026-07-31): ship it as a toggle in the Phase 4 panel** so both behaviours
  can be judged on real drawings. That is now `IMPLEMENTATION.md` Phase 4 item 5. The default stays
  `.none` until the comparison says otherwise.

- **`withStructureUndo` is still the trap §5's Phase 2 entry describes, and Phase 4 will meet it.**
  The `t` slider is genuinely fine on `beginStructureGesture`/`commitStructureGesture` because `t`
  lives in the `Cel` struct. Anything that writes *strokes* — Generate committing an in-between,
  Reproject re-posing one — needs `withInterpolationUndo(name:touching:)`.

### From Phase 4

- **`addCel` built a raster-only `Cel` on every layer, including `.vector` ones — and that made a
  second hand-drawn vector keyframe impossible to create.** "Add Drawing" in an empty timeline slot
  produced a cel with `vector == nil`; `StrokeCanvasView` then silently falls back to raster mode
  (it branches on `vectorCanvas != nil`, not on the layer's kind), so the drawing landed as *pixels
  on a vector layer*. Invisible to the eraser's geometric modes, to save/load's vector payload, and
  to interpolation, which reads `cel.vector` and finds nothing.

  It is fixed — `addCel` now matches `layers[layerIndex].kind`, as `addVectorLayer`'s own cel
  already did. Two things worth knowing. First, **the fix changes behaviour outside interpolation**:
  any vector layer's added frames are now vector cels, which is what they always should have been,
  but it is a real behaviour change and `CelCRUDCharacterizationTests` covers that area (it stayed
  green). Second, **the bug was invisible until an end-to-end test existed**, because every earlier
  vector test built its cels directly rather than through the timeline's own affordance. Expect more
  of this shape: paths that were never exercised because the feature was inert.

- **The e2e test could not tell the in-between from the onion skin, because in this mode the skin
  *is* both keyframes.** A pixel probe saw ink at each keyframe's position and read it as success
  for two runs. `timeline.onionSkinToggle` now has an accessibility identifier and the test turns
  the skin off. **Any later pixel assertion in interpolate mode has to do the same** — the mode's
  onion skin draws content at exactly the positions an interpolation test cares about.

- **A SwiftUI `Toggle`'s centre is not a tap target.** `app.switches["…"].tap()` lands in the dead
  gap between the label and the control and silently does nothing — the toggle reads `"0"`
  afterwards and the failure surfaces several steps later as something unrelated. Tap the trailing
  edge instead: `.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()`.

- **`xcodebuild` *did* print per-test output this session**, contradicting the Phase 3 note below.
  Both are true — it varies. The result bundle is still the thing to trust; do not conclude a run
  has hung from an empty `grep "Test Case"`, and do not conclude it is fine from a full one.

- **The derived in-between never enters the document, and the seam that keeps it out is
  `StrokeCanvasView.setInterpolationImage`.** `CanvasView.Coordinator` evaluates and pushes a
  `UIImage`; nothing writes to the cel's `VectorCanvas`. That is what makes "derived, never stored"
  (PLAN §4) true in the app rather than only in the model, and it is also what preserves §5.6's
  two-isolated-composites structure — a single display list could not hold both keyframes' erasers.
  **Do not "simplify" this by assigning the evaluation into `cel.vector`.** The cost is that the
  preview is a bitmap, so anything wanting the in-between *as vectors* (a Commit action, export)
  has to call the evaluator itself.

- **The preview pass is memoized on a key, and the referenced canvases' `version`s are in it.** That
  is what makes "edit keyframe A and the in-between updates for free" actually happen without an
  invalidation call at every site that can touch a keyframe. `updateInterpolationPreviews` runs on
  every SwiftUI pass, so anything added to the evaluation's inputs — a per-recipe option, a guide —
  **must be added to `InterpolationPreviewKey` too**, or it will appear to have no effect until
  something unrelated forces a re-render.

### From Phase 4.5 (UI pass)

- **An accessibility modifier on a SwiftUI *container* can hide everything inside it.**
  `.accessibilityIdentifier("interpolate.bar")` on the bar's outer `VStack` promoted it to a single
  accessibility element, and every button within it vanished from XCUITest — the rewritten e2e test
  failed on `waitForExistence` for a button that was plainly on screen. Identify the controls, never
  the container. The same trap is waiting for Phase 5's group chips.

- **The interpolate bar lives *outside* the timeline's height constraint.** `AnimationTimeline`'s
  body is `VStack { InterpolateBar; timelinePanel }`, and `.frame(height: timelineHeight)` is on
  `timelinePanel` alone. Putting the bar inside would make turning the mode on silently eat a track
  row out of a panel the artist had already sized. Anything Phase 5 adds above the timeline belongs
  in that same outer stack.

- **Every command targets the cel under the playhead on the current layer**, and that is now the
  whole selection model: Set as Reference, Generate, Reproject and Remove all resolve the same way.
  Phase 4.6 pushed it onto `CanvasManager` as `interpolationTarget`, so there is no longer a copy in
  the views — use it.

### From Phase 4.6 (second UI pass)

- **The layout is settled; do not re-derive it.** `IMPLEMENTATION.md` Phase 4's "Phases 4.5 and 4.6"
  subsection records the final shape and the reason for each placement. Phase 5's group controls hang
  off this bar, so start from that.

- **`interpolationTarget` can legitimately be nil, and Generate treats that as "make a block".**
  `interpolateAtPlayhead` creates the cel and attaches the recipe inside one `withStructureUndo`, and
  it works because both `addCel` and `interpolate` defer to an enclosing bracket rather than recording
  their own. Anything else that wants to compose two structural edits into one artist action should
  use that same property rather than inventing a new bracket.

- **`interpolationRefusalAtPlayhead` is what greys the buttons out, and it answers for a cel that
  does not exist yet.** The target-side checks (empty, not a reference, no recipe) are true by
  construction for a cel about to be created, so only the layer kind and the references are tested.
  If Phase 5 adds a precondition, add it to `referenceRefusal` if it is about the references and to
  `interpolationRefusal` if it is about the target — putting it in the wrong one silently changes
  whether Generate works from an empty slot.

- **A popover on a button inside the timeline's top bar works**, despite that bar carrying
  `simultaneousGesture(resizeGesture)` — the resize gesture has a 6pt minimum distance, so taps pass
  through untouched. `interpolateButton` closes its own popover on `isInterpolateMode` going false,
  because Exit Interpolate Mode lives inside it.

### From Phase 4.7 (diagnosis) — what is actually wrong with the engine

Session 10 was diagnosis only: no engine file changed. Everything below is **measured**, either by
`deploy/interp-registration-benchmark/run.sh` or by an experimental fork of `Engine/Deform` compiled
standalone. Where a hypothesis was refuted, the refutation is recorded too — three of them were, and
each would have been shipped as "the fix" if the reading had not been tested.

- **`Engine/Deform` compiles and runs standalone with `swiftc`, and that changes how numerical work
  on it should be done.** It imports only `Accelerate`, `CoreGraphics` and `Foundation` (standing
  constraint A), so no simulator, app or test host is needed. An experiment loop is **~5 seconds**
  against ~90 through `xcodebuild test`. `deploy/interp-registration-benchmark/run.sh` is the
  committed instance; copy the five files to a scratch directory to try engine changes without
  touching the repo. This is the single biggest practical finding of the session — the whole
  experiment set below would not have been affordable otherwise.

- **The test tier builds unoptimised, so wall-clock assertions in it are meaningless.** A 121-sample
  fit: **0.6s optimised, 598s in `PaintSoftwareUITests`.** That is why §8 item 28 is pinned by the
  benchmark and not by a test, and why nobody should add the slow version back.

- **The "180° rotation" is a *tie*, not a preferred minimum.** The product owner's hypothesis was
  that rotation is a cheaper minimum than deformation. It is sharper and worse than that: a straight
  line segment maps exactly onto itself under a 180° turn, so the point-cloud residual is **exactly
  invariant** — upright and flipped score identically to six decimal places, and the 8-restart
  multi-start picks between them on arithmetic noise. **No rotation penalty can fix a tie.**

  The proof arrived by accident and is worth keeping: the first version of `testCase27` asserted the
  flip, and **passed on the simulator while the same engine on the same input flipped on a native
  optimised build**. Do not assert the flip outcome anywhere — it is a coin toss that varies by
  build. Assert the *margin* between the two fits, which is deterministic.

- **The multi-start is what *creates* the flip, and dropping it fixes cases 27, 29 and 30's angle.**
  With `restarts: 1` (seed at the centroid/radius bootstrap, angle 0) no case flips. The multi-start
  exists because "ICP's basin of convergence is narrow" — it buys genuine large rotations and pays
  for them with a spurious 180° on any content with a symmetry, which straight lines all have.
  That is a real trade and it is the product owner's call (§3.5), not a bug to quietly fix.

- **The free scale is what causes both the collapse and the grow-and-fade, and locking it fixes
  case 30 outright.** Measured at `restarts: 1, allowScale: false`: case 30's y-span goes from
  **36.5 to 198.5 against the target's 200** — the collapse is gone. Cases 27/29 stop inflating 3×.
  Note this contradicts the standalone reading of `similarity(allowScale:)`'s own comment: locking
  the scale *with* the multi-start still in place trades the collapse for a 90° turn at triple the
  residual (`testLockingTheScaleTradesTheCollapseForADifferentWrongAnswer` pins that). **The two
  flags only work together**; either alone is a different wrong answer.

- **Rigidity is not the bend dial. Sweeping it 2.0 → 0.01 barely moves the bend** (case 29 stays at
  0.16–0.18 against the C's own 1.07). The bend failure is a *correspondence* failure, not a
  stiffness one: nearest-point matching gives a short straight source no reason to wrap around a long
  curved target, because the pulls from both sides of the arc cancel.

- **Arc-length correspondence fixes the bend completely — and it is the deferred `.clean` path.**
  Pairing source sample at fraction *u* to target sample at fraction *u* (with the stroke-direction
  ambiguity resolved as one discrete per-stroke bit, scored over the whole stroke) takes case 29's
  bend from **0.34 to 0.944** against the C's 1.072, and its arc length from 482 to 841 of 907. The
  line genuinely becomes the C. This used **zero** point-cloud data rows — the correspondence *is*
  the data. `IMPLEMENTATION.md` explicitly defers `.clean`, so this is a finding about a recorded
  decision and is written up as §8 item 31 rather than built.

- **REFUTED: a tangent/stroke-direction term does not break the tie.** The obvious fix for the
  degeneracy — penalise matches whose drawn direction disagrees — was tested and is **worse than
  doing nothing**. It left case 27 flipped (the tangent evidence actively *favoured* the flip) and it
  **broke case 29, which the plain objective gets right** (plain picks 0.5°, tangent picks 179.5°).
  The reason is simple in hindsight: between two independently drawn keyframes the drawing direction
  of the second stroke is arbitrary, so the term is a coin flip dressed as evidence. Do not revisit
  without a way to know the artist drew both keys the same way.

- **REFUTED: item 29 is not the cross-fade fallback.** The report read the grow-and-fade as the
  evaluator degrading to a cross-fade. It is not — `ARAPRegistration.Result.refined` is `true` and
  the elastic solve runs. The motion is wrong *inside* the warp path.

- **Mean residual is a lying metric and is why nothing caught this earlier.** Case 30 scores a mean
  residual of **3.6 points** — an excellent fit — while covering a quarter of the target's span.
  Piling the source onto the middle of the target is precisely how you win on distance-to-nearest.
  **Any quality gate added later must measure coverage**, i.e. how much of the target has something
  near it, not how near the source is to something.

- **The ~1 minute freeze is `PointCloudIndex.nearest`, and the fix is ~15 lines and verified.** The
  ring search generates the full (2·ring+1)² block of cell indices and filters it, which is O(ring²)
  of pure rejection per ring. On a *line-shaped* cloud the adaptive cell size makes a grid one column
  wide and hundreds of rows tall, so `maxRing` is in the hundreds and a single query costs millions
  of iterations — and a line is exactly what the product owner drew. Walking only the ring's own
  cells, clamped to the grid, gives **bit-identical residuals** and:

  | samples | before | after | |
  |---|---|---|---|
  | 100 | 1.3 s | 40 ms | 33× |
  | 250 | 12 s | 203 ms | 60× |
  | 500 | 45 s | 572 ms | 78× |
  | 1000 | 94 s | 1.5 s | 64× |

  **The residual stops improving past ~250 samples** (11.69 → 12.72 *worse* at 1000), so subsampling
  the registration cloud costs nothing and would take the remaining 1.5s to ~200ms. The lattice is
  ~56 vertices whatever the sample count — it is the point cloud that grows, not the solve.

### From Phase 4.7 (the fixes) — what applying them taught that the diagnosis had not

Session 12 applied items 31, 32 and 35. The diagnosis held up: every number Session 10 measured
reproduced, and the fixes did what it said they would. These are the things that only appeared once
the code was written.

- **A margin expressed relative to the score being beaten is a bug when both scores can be zero, and
  this cost the most time of anything in the session.** The direction bit started as "believe the
  reversal if it beats forward by 5%". Two *straight* strokes fit each other exactly in **both**
  directions, so both scores are ~1e-16 and the rule compares nothing but rounding noise. The
  symptom was not subtle and was nearly missed anyway: on a rigid L the direction bit flipped with
  the **sample count** — 8 → `Rf`, 16 → `fR`, 24 → `ff`, 32 → `Rf` — turning a motion the engine
  reproduces exactly into a 46-point error, non-monotonically, which reads exactly like tuning noise
  and is not. The fix is to make the margin **a fraction of the stroke's own arc length**, i.e. a
  geometric statement. Measured gap/length: 1e-16 for a straight stroke, 0.0073 for one whose last
  2% hooks away — thirteen orders of magnitude, with nothing in between, so the threshold is not a
  tuned number. `testTheFitDoesNotSwingOnHowManySamplesTheCorrespondenceUses` is the tripwire.

  The general lesson, worth carrying past this feature: **any comparison of the form `a < b × (1 − ε)`
  needs to know what happens when both sides are zero.** Normalise by something with units.

- **The correspondence has to *replace* the point-cloud data rows, not join them.** Measured on a bar
  bending into a parabola — a case the plain path already got right — mean residual is 0.62 with the
  cloud alone, **0.87 with cloud *and* correspondence**, and 0.00 with the correspondence alone.
  Adding good information to good information made it worse, because the nearest-point pulls are
  exactly the thing that will not wrap a stroke around a curve. This confirms Session 10's
  "correspondence *is* the data" the hard way, and it is why `RegistrationFrame.strokes` is nil for
  a frame holding anything that is not a stroke: with the cloud rows dropped, a fill would be left
  with nothing pulling it at all.

- **Two tests in the same class were direct logical contradictions, and the acceptance one was the
  wrong one.** `testCase27` asked the objective to prefer the upright fit "by a margin arithmetic
  noise cannot flip", while `testA180DegreeFitScoresIdenticallyToTheUprightOneOnALine` asserted the
  two are equal to 1e-6. The second is not a measurement but a **proof** — a straight segment maps
  onto itself under a half turn, so `F` and `F ∘ turn` send the source onto the identical point set;
  it holds with the scale free or locked, at any restart count, for any objective that sees only the
  two clouds. So the margin can never be anything but zero and `testCase27` was unsatisfiable as
  written. It now asserts what *survives* a tie — the line bends into the C — checked on the drawing
  as made **and** with keyframe C's stroke recorded the other way round, which is the input that
  flips the choice. Both branches clear the same bar, so no build can flip it.

  Worth generalising: when a pinned root cause and an acceptance criterion disagree, check whether
  the acceptance criterion is *achievable* before assuming the engine is at fault.

- **Registration's defaults are not grouping's defaults, and inheriting them silently broke two
  Phase 1 tests.** `MotionGrouping.Options.icpRestarts` read `ARAPRegistration.Options()`'s, so
  dropping the multi-start took it away from grouping too — and grouping is the one place it is
  doing real work, because it fits a *part* seeded where it already sits and exists to discover that
  something turned. It is now `8` with its own reasoning written next to it. **4.7 measured
  registration, not grouping; Phase 5 owns that dial.**

- **The coverage metric §8 items 32, 36 and 37 all want now exists twice, in test-local form.** It is
  in `InterpolationEngineDiagnosticsLogicTests.inkCoverage` and in the benchmark. Both measure
  distance from each target point to the warped **polyline's segments**, not to its samples — a
  stroke stretched five times over carries its samples 35 points apart, and sample-based coverage
  scores continuous ink as a dotted line. Whoever builds the shipping version should start from
  those two rather than from the definition; the segment detail is the part that is easy to get
  wrong and it makes a factor-of-three difference to the number.

- **The standalone harness paid for itself again, and the ratio got better.** Every number in the
  four commits was measured with `swiftc -O` in a scratch copy before any repo file changed — the
  flag matrix on the L test, the direction-margin sweep, the sample-count instability, the
  cloud-rows-versus-correspondence comparison. The sample-count bug in particular would have been
  impractical to find through `xcodebuild test`: it took eight fits per configuration across nine
  configurations, which is ~15 seconds optimised and would have been most of an hour in the test
  tier. Copy `Engine/Deform`'s five files to a scratch directory; do not experiment in the repo.

### From Phase 5 (the engine half)

- **`testPreviewIsSubstantiallyCheaperThanFull` flakes under CPU contention, and it is not a
  regression.** The session opened with 224 tests, 223 passing, and that one failing — then it passed
  in isolation on the same tree. It was running concurrently with a `graphify query`. It is a
  wall-clock *ratio* assertion in the unoptimised test tier, which §5's Phase 4.7 entry already warns
  is meaningless there. **Do not run anything heavy alongside the fast tier**, and re-run that one
  test alone before believing it.

- **The grouping's target and registration's target are different questions, and the difference is
  which keyframe.** `registerGroups` measures the partition against the **last** keyframe, not the
  next one, because grouping asks about the whole span: two parts that move differently are most
  separable where they have moved furthest apart. With today's two references they are the same
  frame, so this costs nothing now and is only visible once a spline ships — but with three or more
  keyframes, grouping against the adjacent one lets a part that barely moves in the first segment
  hide inside its neighbour.

- **Write-back is what makes group ids stable, and without it re-registration would mint a new group
  every time.** The chain is worth stating because each link looks optional and none is: a part
  reuses the tag its members already agree on; an untagged part has no tag to reuse, so it mints one;
  and if that id were not written back onto the strokes, the *next* registration would find them
  untagged again and mint another. Groups would accumulate one set per Generate. Tagging the
  strokes closes the loop, and after one round nothing is untagged.

- **A part that produces no binding must have its tag cleared, not left behind.** An empty part is
  skipped when the bindings are built, and a stroke still carrying that group's id would resolve to
  no warp and fall through to the *first* binding — silently riding another part's motion rather than
  its own. `registerGroups` prunes both the assignments and the invented groups against the set of
  ids that actually got a binding. Any later change to how bindings are built has to keep that prune.

- **Two bodies alone will not split — the fixture needs four strokes and three, not one and one.**
  `MotionGrouping.splinter`'s spatial radius is `proximityMultiple × median nearest-neighbour
  centroid spacing`, so with exactly two strokes the median *is* their separation and the radius is
  2.5× it: they are always "connected", the spatial cut cannot fire, and the residual split then
  grows the chosen side back over the other and returns nil. The known-good fixture is
  `ARAPLogicTests`' `rectangleBody` (4 strokes) plus `triangleBody` (3), the rectangle moved `+40` in
  x with the triangle still. Start from it rather than from a picture of two lines.

- **`interpolateAtPlayhead`'s outer bracket had to become `withInterpolationUndo`, and §5's Phase 2
  entry predicted exactly this.** That note says a vector-content edit nested inside an outer
  *structural* bracket is not undoable and that the fix is to widen the outer one rather than record
  twice. Phase 5 is the thing that needed it. The symptom if it is ever narrowed back: undoing a
  Generate that created its own block puts the block and the recipe back but leaves the motion-group
  tags on the keyframes.

### 5.11 What the papers do — and where they do not help

Read this before proposing an engine change; it is the answer to "what do the papers do at exactly
the failure points", and for two of the four cases the answer is "not what we assumed".

Sources: [MoStyle/frite](https://github.com/MoStyle/frite) (the actual code, cloned and read) and
[Inria RR-9559](https://inria.hal.science/hal-04797216/file/RR-9559.pdf). **The code was the useful
half** — the report is about occlusion and layout, not registration.

- **RR-9559 is not a registration paper and says so.** "We tackle an almost inverse problem:
  starting from **already registered** key drawings, we aim at propagating the layout." Its
  contribution is masks, depth ordering and visibility. It assumes our problem is already solved.

- **frite's registration is deliberately *not* a global search, which is exactly our bug.**
  `RegistrationManager::registration` is: `preRegistration` (rigid CPD — Coherent Point Drift, a
  soft-assignment fit — or centre-of-mass alignment, or a rigid transform from artist-**pinned**
  quads) and then alternating `pushPhase` + `Arap::regularizeLattice` to convergence. There is **no
  multi-start over rotations anywhere**. It never offers itself the flipped solution. Our
  `icpRestarts: 8` is the thing frite pointedly does not have.

- **Scale is factored out, not fitted.** CPD gives a *rigid* transform; the size change is captured
  separately as `m_preRegistrationScaling` and stored on the lattice via `setScaling`. Our tier-1
  similarity fits rotation, translation **and** scale in one objective, which is what lets case 30
  buy a good residual by shrinking to 15%.

- **The push phase is per-quad and rigid, ours is per-point and translational.** frite matches the
  points inside each quad, computes that quad's optimal *rigid* transform from its own matched pairs,
  and moves its four corners by it — damped by `k_stepSize` and averaged over the quads sharing each
  corner. Matches beyond `k_proximityFactor × cellSize` are **discarded**, and a quad with no matches
  simply does not move. Ours builds one data row per source point pulling toward its nearest target,
  with an outlier cut at a multiple of the *median* match distance — which admits everything when
  everything is far.

- **N strokes → M strokes is not solved algorithmically by either. The artist does it.** This is the
  plain answer §8 item 30 asked for. frite's drawings are "manually decomposed into a set of
  transient embeddings", registration runs **per user-defined part against a user-chosen target
  stroke set**, and the tool list is full of manual correspondence machinery —
  `CorrespondenceTool : public LassoTool`, `directmatchingtool`, `registrationlassotool`,
  `pickstrokestool`. The paper concedes even the part-level version is fallible: "Automatic layout
  propagation may not find the best **many-to-one mapping** between drawing parts in some tricky
  cases."

  So **the product owner's "this may be a problem for messy lineart" is correct, and the literature's
  answer is a UI, not an algorithm.** Building a fully automatic N→M stroke matcher would be past the
  state of the art, not a catch-up.

- **What the paper *does* give us for case 30 is a shippable answer we already have the data model
  for.** Content with no partner is not merged — it is **faded out progressively** via per-vertex
  temporal visibility thresholds (Eq. 4: the set `Xout` of vertices with no near counterpart, seeded
  at `Xseed` and diffused so the farthest-from-the-target disappear first). `VectorStroke` has
  carried `visibilityThreshold` and `sampleVisibilityThresholds` since Phase 2 and nothing sets them.
  That is the closest match between our model and the paper's, and it is unbuilt on our side.

### 5.10 For Phase 5's motion groups

What Phase 4 decided that Phase 5 inherits:

- **Phase 4's whole-frame binding registers no `MotionGroup`.** `registerWholeFrameGroup` mints a
  fresh `groupID` per recipe and leaves `motionGroups` empty, because a registered group is an
  artist-facing object (name, tag colour, mode badge) and inventing one per recipe would put
  document state in front of the artist that they never asked for. **Phase 5 must therefore handle a
  binding whose `groupID` has no registry entry** — either by adopting it into a real group when the
  artist first tags something, or by treating "no entry" as the implicit whole-frame group in the UI.
  `motionGroup(withID:)` returns nil for it today.
- **Nothing is tagged, and that is correct rather than unfinished.** Untagged content rides the
  recipe's first binding (§5.9), which is exactly right with one group and is the safe default with
  several (content carried by a neighbour's motion is a much quieter failure than content left
  behind). Phase 5 owns making tagging reachable; it does not have to backfill tags onto existing
  recipes.
- **Keyframes are grouped by `startFrame`.** `interpolationKeyframes` folds every flagged cel that
  starts on the same frame into one `InterpolationReference` — that is what makes requirement 5
  (lineart + flats interpolate together) work with no second gesture. Grouping by *overlap* was
  rejected: it folds a long held cel in with every short cel beside it.
- **The timeline's press-and-hold means drag-reorder in every mode, interpolate included.** Phase 4
  overloaded it by mode and the product owner scrapped that in 4.5: it took re-timing away exactly
  while the artist was working on timing. Interpolate's commands are buttons on `InterpolateBar`.
  **If Phase 5 wants a new timeline affordance, put it on the bar, not on a gesture** — two long
  presses of equal duration competing for one touch have no stable winner, and `require(toFail:)`
  between them does not help, which is why the mode-switch looked attractive in the first place.
- **`InterpolationRefusal` is the pattern for saying no.** Commands return a reason rather than a
  bool, the bar disables the button from the same call, and the message is on the enum. Phase 5's
  group commands should follow it rather than inventing a second failure style. Note 4.6 split the
  check in two — `referenceRefusal` (about the references) and `interpolationRefusal` (about the
  target) — so that Generate can answer for a cel that does not exist yet.

### 5.9 For Phase 4's UI

What Phase 3 decided that Phase 4 inherits:

- **The evaluator never touches `CanvasManager`.** It takes a
  `ContentProvider = (CelRef) -> [VectorElement]` and asks for each reference's display list. Phase 4
  supplies the closure that resolves a `CelRef` against the layer tree. Keep it that way — it is what
  lets every render test run without a document.
- **`.preview` during the drag, `.full` on release**, and the two cache in separate slots on
  `VectorCanvas`, so switching between them does not throw the other away. That is the whole reason
  scrubbing is affordable; wiring the slider to `.full` would make it ~4x more expensive per tick on
  a 24-stroke fixture and much worse on real art.
- **Untagged content rides the recipe's *first* group binding.** Phase 4 creates one automatic
  whole-layer group and does not need to tag anything for the warp to reach every stroke. Phase 5,
  which creates several groups, is the phase that has to actually tag.
- **`evaluate` returns nil for a malformed recipe.** The UI should read that as "not yet" — show the
  cel's own content or nothing — rather than treating it as an error.
- **`t` outside `0...1` extrapolates rather than clamping**, because `ARAPInterpolation` does. If the
  slider should not overshoot, clamp it in the UI.
- **The blend weights are frame-wide.** A per-group `spacing` retimes that group's *motion* only; the
  cross-fade weight comes from the recipe-level curve, because the two sets are composited as whole
  canvases and a canvas has one alpha.

---

## 6. Session log

> One line per session: `Session N — YYYY-MM-DD: <what changed>`. Mirrors the repo's
> [SESSION_LOG.md](SESSION_LOG.md) convention, scoped to this feature.

- **Session 1 (design) — 2026-07-30:** Researched the problem space, chose lattice+ARAP over stroke
  correspondence, resolved all product decisions, wrote `PLAN.md` (incl. the brief as §0) and this
  file. Verified toolchain, created `interp-ipad`, confirmed baseline green, verified Accelerate's
  sparse solver on iOS. **Ended early on usage limit; `IMPLEMENTATION.md` not written and the design
  workflow was aborted with no output captured.** No feature code.
- **Session 2 (planning) — 2026-07-31:** Confirmed the aborted workflow left nothing recoverable (no
  agent reached structured output). Wrote `IMPLEMENTATION.md` directly — eight phases with acceptance
  criteria, feature definition of done, and the deferred list. Added the subagent budget policy (§3.4)
  after the previous session's overrun. No feature code.
- **Session 3 (Phase 0) — 2026-07-31:** Fixed the vector onion-skin blank bug and added the
  `OnionSkinSource` seam (commit `3ecd1e2`). Added `OnionSkinLogicTests` (3 tests, green). Learned the
  UITests target's pbxproj Sources phase is still hand-maintained (§5). Phase 0 definition of done met;
  stopped there per §3.3 rather than starting Phase 1.
- **Session 4 (Phase 1) — 2026-07-31:** Built the whole lattice + ARAP engine — all eight work items,
  five files under `Engine/Deform/`, 68 new logic tests, five commits (`bae6a9c` … `5e5785e`). The
  endpoint invariant holds to the last bits, and it took a change of variables to get there (§5). No
  subagents; done inline on Opus 5 per §3.4. Recorded a real limitation in automatic motion grouping
  (attached limbs) rather than weakening a test to hide it — see §8.
- **Session 5 (Phase 2) — 2026-07-31:** Built the data model, persistence and undo — all nine work
  items, four new files, 28 new logic tests, one commit (`49906ea`). Chose the `Lattice` encoding
  §5.7 left open (rest configuration never written; no indices persisted at all, which is what makes
  it expansion-proof). Found that `withStructureUndo` cannot cover a group retag and wrote the
  bracket that does — the one place `IMPLEMENTATION.md`'s undo mapping is wrong (§5). No subagents.
  Commits `49906ea`, `49ef0cb`, `3c2d119`.
- **Session 6 (Phase 3) — 2026-07-31:** Built the evaluator, the isolated composite and the polyline
  preview tier — all five work items, one new file, 17 new logic tests, one commit (`f6986df`).
  Opened by erasing `interp-ipad`, which turned Session 5's five-attempt XCUITest flakiness into two
  clean full-suite runs, both first time — 433/433 before the phase and 450/450 after it (§5). `t = 0`/`t = 1` reproduce their keyframes at zero pixel
  tolerance through the general path. Built thickness cross-fade but defaulted it off, with the
  reason recorded, rather than shipping a default that thins every mid-frame (§5, §3.5). No
  subagents. Also compacted §5 (eight facts that duplicated a code comment became a pointer table)
  and, on the product owner's ask, deleted `VECTOR_ERASER_HANDOFF.md` after moving its unstarted
  backlog into `VECTOR_ERASER_PLAN.md` §12 — the plan stays, it is cited from ~20 source files.

- **Session 7 (Phase 4) — 2026-07-31:** Built the interpolate-mode UI — all six work items, one new
  view, 24 new logic tests and the single end-to-end XCUITest, four commits (`6486f0e` … `39f4365`).
  **The feature stopped being inert:** an artist can enter the mode, press-and-hold two blocks to
  set them as references, Generate, and scrub the in-between. Resolved the press-and-hold conflict
  by mode-switching the one recognizer rather than adding a competing one, and kept the derived
  frame out of the document entirely (`setInterpolationImage`), which is what makes "derived, never
  stored" true in the app and not just in the model. Reproject is stubbed and refuses out loud.
  The e2e test found a real pre-existing bug — `addCel` built raster-only cels on vector layers, so
  a second hand-drawn vector keyframe could not be created at all (§5). Full suite green at the
  phase boundary — 475 tests, 474 passed, 0 failed, 1 skipped, first attempt after a `simctl
  erase`, which is now three phase boundaries in a row where resetting first produced a clean
  run. No subagents.

- **Session 8 (Phase 4.5 — UI) — 2026-08-01:** The product owner's first real iPad session on Phase
  4, turned into a layout pass. Built `InterpolateBar` above the animation timeline and moved every
  command onto it; **deleted the mode-switched press-and-hold**, which was the session's headline
  correction — it was my judgement call in Phase 4, not a recorded decision, and it was wrong.
  Removed the "registration runs at mode entry" contradiction from the code and the plan rather than
  documenting it a third time. Rebased onto `origin/main` to pick up Session 9's timeline rework
  (32 commits replayed; conflicts were the regenerated graph report, one `CanvasManager+Undo`
  restore where both sides were wanted, and `AnimationTimeline`'s toolbar refactor). Recorded the
  product owner's four future items and the vector/raster divorce question as §8 items 21–26 rather
  than acting on any of them. No subagents.

- **Session 9 (Phase 4.6 — UI, and the engine verdict) — 2026-08-01:** The product owner's second
  iPad round. **The layout is now settled** — entry point moved to the timeline's own top bar and
  made two-stage, the panel became an options popover with the redundant mode switch gone, the bar
  became two rows with the timing slider on top and the commands centred on Generate, and Remove
  Interpolation joined the bar. Two behaviour fixes rather than layout: Generate now refuses on an
  already-interpolated cel (`.alreadyInterpolated`, §8 item 22), and Generate now works from an
  empty slot by creating the block and the recipe in one undo step (`interpolateAtPlayhead`) — that
  last one was new this session, not on any list. Five new logic tests; the e2e XCUITest enters the
  mode with one tap instead of a panel-and-switch dance. **The session's real output is §8 items
  27–30 and the new Phase 4.7**: the product owner ran four two-keyframe test drawings and the
  engine failed all four — 180° rotations instead of bends, a warp degrading to a scale-and-fade,
  no stroke merging, and a minute to register two strokes. That is why 4.7 goes before Phase 5.
  Full suite green at the boundary: 512 tests, 511 passed, 0 failed, 1 skipped. No subagents.

- **Session 10 (Phase 4.7 — diagnosis) — 2026-08-01:** No engine file changed; the output is a
  diagnosis, `InterpolationEngineDiagnosticsLogicTests` (4 characterisations + 3 pinned expected
  failures) and `deploy/interp-registration-benchmark`. Commits `46e75c1`, `…`. Found that
  `Engine/Deform` compiles standalone with `swiftc`, which made a ~5-second experiment loop possible
  and is why the session got past reading. **All four of items 27–30 are now measured causes**: the
  180° is an exact *tie* (a line maps onto itself, so upright and flipped score identically and the
  multi-start picks on float noise — proved when the first case-27 test passed on the simulator while
  flipping natively); the grow-and-fade is the free scale, not the cross-fade fallback; the collapse
  is that free scale again, and mean residual reports it as a good fit; the minute is
  `PointCloudIndex.nearest` degenerating on a line-shaped cloud, fixed 60–78× with bit-identical
  output. **Three plausible fixes were refuted by experiment** — a tangent/direction term (worse: it
  breaks the one case the engine gets right), lowering rigidity (the bend ceiling is correspondence,
  not stiffness), and locking the scale on its own. Read the papers' actual code rather than only the
  PDF, which is where the answer was: frite has no multi-start, factors scale out, and hands N→M to
  the artist via a lasso tool. Stopped before applying anything because item 31 is a product decision
  (§3.5). The product owner's mid-session correction — *don't split diagnosis and implementation
  across sessions, you can't test your hypotheses* — is why the refutations exist and is the reason
  this entry is worth reading twice.

- **Session 12 (Phase 4.7, second half — the fixes) — 2026-08-01:** Applied §8 items 31, 32 and 35
  and finished Phase 4.7. **All four of the product owner's failing drawings are fixed and the
  definition of done is met — the three `XCTExpectFailure` wrappers are off and the tests pass on
  their own**, on Session 10's own thresholds rather than loosened ones. Four commits, one per fix,
  each green before the next: `b9100af` (the ring walk — 250 samples 12 s → 412 ms, residuals
  bit-identical over 18,500 queries), `8a46b77` (`icpRestarts: 1` + `allowScale: false` — case 30's
  span 51 → 194.6 of 200), `8733589` (tier 0, the 1:1 arc-length correspondence — case 29's bend
  0.17 → 0.985 against the C's 1.072, case 27's 0.16 → 0.907, coverage 0.31 → 0.96), `ea85793` (the
  250-sample cap — cost now *flat* in the sample count, 2000 samples 285 s → 78 ms).
  Session 10's diagnosis reproduced exactly; three things it could not have known appeared only once
  the code existed, and all three are in §5: the correspondence has to **replace** the point-cloud
  data rows (keeping both is worse than either), the direction bit must be scored with each
  direction **self-aligned**, and its margin must be a fraction of the stroke's **arc length** — the
  relative version compared pure rounding noise on straight strokes and made the fit swing with the
  sample count. Two tests turned out to be direct logical contradictions and the *acceptance* one
  was the wrong one: `testCase27` asked for a margin between two provably identical scores, and now
  asserts what survives the tie, checked with keyframe C recorded both ways round. `MotionGrouping`
  was silently inheriting registration's restart count and is now pinned at 8 with its reasoning, on
  the principle that 4.7 measured registration and Phase 5 owns grouping. Answered the product
  owner's timing question on §8 item 36 (ink-to-ink matching): **a later pass, with one constraint
  on Phase 5** — keep group membership "which ink", not "which stroke pairs with which". No
  subagents. Stopped at the definition of done per §3.3; Phase 5 is a separate session.

- **Session 13 (Phase 5, first half) — 2026-08-04:** Built the engine and model half of motion
  groups and stopped on the usage handoff before any UI or any test. One commit, `2870773`.
  `RegistrationFrame` became a list of elements so a keyframe can be *sliced*, and
  `registerGroups(frames:existing:)` replaced the single whole-frame binding with one binding per
  part — `MotionGrouping` seeded by the artist's tags, measured against the last keyframe, each part
  fitted to its own counterpart. The whole-frame answer is preserved bit for bit, which is why every
  Phase 4 test stayed green untouched. Registration now **writes tags back onto both keyframes'
  strokes**, which is what makes the partition visible and correctable and is also a real behaviour
  change worth telling the product owner about (Generate modifies the reference drawings). `setMotionGroup`
  re-registers in the same undo step, so a retag moves the ink rather than only recolouring the
  label; `tagMotionGroupsByStrokeColour` is PLAN §5.1.1's populate. Generate's bracket widened to
  `withInterpolationUndo`, which §5's Phase 2 entry predicted three phases ago. **Nothing in the app
  can reach any of it and nothing is tested** — §2's "Where Phase 5 actually is" is the list. No
  subagents.

---

## 7. Handoff prompt template

When §3.2 is triggered, fill this in and print it in one fenced block.

```
Continue the vector interpolation feature in the PaintSoftware repo.

Worktree: /Users/juliapark/Desktop/Kevin.P/PaintSoftware/.claude/worktrees/vector-interpolation-keyframes-d484df
Branch: claude/vector-interpolation-design-9d5b83

Read VECTOR_INTERPOLATION_HANDOFF.md first and follow its §1 start-of-session checklist.

Where the last session left off:
- Phase: <N — title>
- Last commit: <sha> (<green | WIP, does not build>)
- Completed this phase: <items>
- Half-finished: <exact state, files, what is missing>
- Next action: <the single next concrete thing to do>
- Watch out for: <carry-overs added to §5 this session>

Follow the session protocol in §3: commit at every green checkpoint, stop when the phase's
definition of done is met, and suggest rather than implement anything out of scope.
```

---

## 8. Suggested follow-on work

> Improvements noticed during implementation but deliberately **not** done. The product owner decides
> whether any of these become work. Do not implement from this list without being asked.

### From Phase 1

1. **Automatic grouping cannot separate an attached limb from its torso.** The most substantive gap
   found. Splitting a spatially connected group has to come from residuals, and a stroke's residual
   is its true motion minus the group's fitted motion — so as soon as that fit contains a rotation,
   residuals inside one rigid part vary systematically across it and clustering on them cuts in the
   wrong place. Spatially *separate* bodies split reliably; a swinging arm does not.

   The tag-seeded path handles it today and is the same code, so the one-tap-per-body-part workflow
   is unaffected — this only limits how good "fully automatic" is on a jointed character. `PLAN.md`
   §5.3's bootstrap hints (a coarse optical-flow field between rasterised A and C, matching-tag
   alignment) are the designed route to fixing it, and none are built.

   **Product owner's steer (2026-07-31): this is expected, not a defect to chase.** The boundary
   between limbs is genuinely vague, and two reference frames is the minimum possible information —
   it is reasonable that it is hard. The intended mitigation is that the artist distinguishes limbs
   by colour in both reference frames, either as the paint colour itself or as the group attribute,
   which is **already `PLAN.md` §10 decision 4 and §5.1.1** ("Tag by stroke colour" as a one-shot
   populate action into `groupID`, not a live binding). So the fix for this limitation is work that
   was already planned rather than anything new, and Phase 5 should build the tagging path first and
   treat improving the automatic split as optional on top.

   The product owner also expects there are better approaches in the literature and in other
   software that they have not read yet, and may revisit this. Treat the above as the current
   position, not a closed decision.

2. **No turn-count control for rotations past 180°.** `ARAPInterpolation` unwraps angles across
   triangle *neighbours*, so the lattice cannot tear — but the global branch always takes the short
   way round, because nothing in two keyframes distinguishes a 200° turn from a −160° one. The
   standard remedy is an artist-set turn count per group. Cheap to add (the per-triangle angles are
   already computed and exposed); worth it only once someone hits it.

3. **`ARAPRegistration.fit` has no early-out on a converged ICP tier.** It always runs `iterations`
   alternations. Harmless now — registration happens once per keyframe pair, not per frame — but if
   Phase 5 ends up re-registering interactively while the artist edits tags, this is the first place
   to look.

4. **Grouping's pairwise "furthest residual poles" search is O(n²) in strokes per group.** Fine at a
   few hundred; the product owner's >1000-object vector layers (standing constraint C) would notice.
   A bounding-volume or sampled search would fix it if it ever matters.

5. **`MotionGrouping` never re-merges.** Splitting a badly-fitted group along its spatial components
   can over-split a drawing whose parts genuinely move together but are disconnected. The result
   still animates correctly and merging is one tap, so this is the safe direction — but a final
   "merge groups whose fitted motions agree" pass would make the automatic result tidier.

### From Phase 2

6. **A local edit can only be a stroke.** `LocalEdit` carries a `VectorStroke`, so drawing and
   erasing at an in-between are covered but a *fill* made there is not. Fills have their own
   unresolved question (`PLAN.md` §7.3) and `VectorFillElement` is fully `Codable` inline, so
   widening `LocalEdit` to an element enum later costs one `decodeIfPresent` — but it is a real gap
   in what "edit at the in-between" currently means, and Phase 6 is where it will be felt. Placed
   images at an in-between are a further step again, since those need file management.

7. **Nothing prunes a recipe whose referenced cel has been deleted.** `referencedCels` and
   `isWellFormed` make a stale recipe *detectable*, and the evaluator is meant to answer "not yet"
   rather than crash — but no cel-deletion path clears the recipes that pointed at it, so a document
   can accumulate recipes that can never evaluate. The right moment to fix it is when Phase 4 gives
   the artist a way to see interpolated cels; doing it now would be housekeeping for state nothing
   can create.

8. **`evictDistantVectorRenderCaches` counts cels, not bytes.** A limit of 12 canvas-sized images is
   ~190 MB at 2048² and ~770 MB at 4000², so the bound means very different things at different
   canvas sizes. A byte budget would be the honest version. Cheap to change (the policy is one
   function); worth doing if memory pressure shows up on a large canvas.

9. **Eviction only runs on a frame or layer change.** That is where the working set actually moves,
   so it is the right primary hook — but a session that renders many cels without changing the active
   context (an export, a thumbnail sweep) never triggers it. A second call site after any bulk render
   would close that.

### From Phase 3

10. **Fills are not corresponded, so their colours cross-fade instead of lerping.** `PLAN.md` §7.3
    makes the case that fills are the one place correspondence is *reliable* — there are few of them
    and colour is highly discriminative — and asks for a 1:1 match by colour+overlap with a
    cross-fade fallback. `IMPLEMENTATION.md` Phase 3 item 4 asks for the colour lerp specifically.
    Only the warping half is built. The matcher is engine D work that `MotionGroup.mode`'s doc
    already defers ("`.clean` degrades to `.crossFade` until the matcher lands"), so building it
    inside Phase 3 would have been a later phase's design decision taken early. Two differently
    coloured fills currently go through a muddy half-transparent middle, which is exactly the worry
    §7.3 names. The evaluator already carries a fill's `id` across the warp so a matcher has
    something to key on.

    **Product owner's steer (2026-07-31): cross-fading fills is acceptable for now, and instructions
    will follow after user testing.** Two things that steer settles for whoever picks this up. First,
    the *base* capability — interpolate handling a fill sensibly when both references have filled
    sections — is considered valuable and in scope; it is the colour lerp between matched fills that
    is deferred, not fill support. Second, "easy filling across multiple frames" may want to be an
    **entirely separate tool** rather than something interpolation grows into, so do not widen the
    recipe to chase it. Do not build the matcher speculatively — wait for the testing result.

11. **A fill cannot belong to a motion group.** `motionGroupID` is a field on `VectorStroke` only, so
    every fill and every placed image rides the recipe's first binding. Fine for Phase 4's single
    whole-layer group; wrong the moment a character's flats and its background are separate groups,
    which is Phase 5. The fix is either the same field on `VectorFillElement` or a group lookup by
    geometry; the first is cheaper and matches how strokes already do it.

12. **A placed image only travels — it does not deform.** `VectorImageElement` is a bitmap under one
    affine transform, so the evaluator warps its centre and leaves scale and rotation alone. A
    lattice that rotates or shears will visibly slide past the image sitting inside it. A mesh draw
    (`CGContext.drawImage` has no such thing; this would want Core Image or Metal) is the real fix,
    and it is only worth it if placed images turn out to matter inside an interpolated span.

13. **`.preview` under-inks a translucent brush.** Overlapping dabs accumulate alpha along a stroke,
    so a stroke at `opacity 0.4` renders much closer to opaque than one stroked path at alpha 0.4
    does. Preview therefore reads lighter than full for low-opacity brushes — shape and position are
    right, weight is not. A saturation curve (`1 − (1 − a)^k` for a k derived from spacing) would fix
    it cheaply if it bothers anyone; it is invisible for the opaque brushes most linework uses.

14. **Nothing caches the evaluation across slider ticks.** Every tick re-embeds each keyframe's
    geometry in its lattice, which is the expensive half of the warp (`embedInCurrent` builds a
    deformed-cell index), and re-runs the ARAP factorisation via a fresh `Interpolator`. Both are
    per-drag constants: the embeddings depend only on the keyframe lattices and the factorisation
    only on topology. `ARAPInterpolation.Interpolator` exists precisely to be held across ticks
    ("build one and hold it for the lifetime of a slider drag"), and this phase does not hold it.
    Phase 4 owns the drag, so Phase 4 is where a `ScrubSession` holding both belongs — worth doing
    there rather than retrofitting into the evaluator, which is stateless on purpose.

    **Still open after Phase 4.** Phase 4 memoizes the finished *image* against a key
    (`InterpolationPreviewKey`), which is what stops an idle SwiftUI pass re-rendering — but every
    distinct `t` still re-embeds and re-factorises from scratch, which is every tick of an actual
    drag. The `ScrubSession` is the remaining half and its home is `CanvasView.Coordinator`,
    alongside that key. Measure before building it: `.preview` quality made scrubbing usable enough
    on a 24-stroke drawing that this was not the bottleneck, and the product owner's >1000-object
    layers (standing constraint C) are where it will start to be.

### From Phase 4

15. **A reference on another layer looks identical to one on this layer.** `PLAN.md` §5.0 step 2
    asks for the highlight to distinguish "reference" from "reference on another layer feeding this
    one", because those read differently on the timeline. Today both are the same yellow. The data
    is all there (`CelRef` carries the layer), so this is a presentation change — a second tint, or
    a badge — and it only starts to matter once artists routinely reference across layers.

16. **The slider does not show where neighbouring in-betweens sit.** `PLAN.md` §5.0 step 4 asks for
    it, so the artist can judge spacing against the frames either side rather than in isolation. It
    is the same information the spacing chart shows (§6.2), in a second place, and it wants the
    recipes on the cels between the two references — which nothing currently gathers.

17. **There is no Commit action.** `PLAN.md` §4 names it: evaluate at the current `t`, write the
    result into the cel as ordinary content, drop the recipe — one-way, undoable, explicit, never
    automatic. Nothing in Phase 4 needs it, and Generate-then-Commit is what produces a frame that
    Reproject then works on, so it is worth building alongside Phase 6's Reproject rather than
    before it. Note it would be the first thing that writes stroke content from a recipe, so it is
    the first caller of `withInterpolationUndo` in this part of the feature (§5).

18. **An interpolated cel is blank everywhere except the canvas at the current frame.**
    `updateInterpolationPreviews` asks each layer for the cel under the playhead, which is exactly
    right for the canvas — but **thumbnails, the ordinary onion skin, and export** all go through
    `PixelOps.rasterize(cel:canvasSize:)`, which reads `cel.vector` and finds an interpolated cel
    empty. So an in-between shows as a blank timeline thumbnail today. Fixing it means giving
    `rasterize` a way to evaluate a recipe, and it cannot have one now because a `Cel` cannot
    resolve its own `CelRef`s without the layer tree — the `ContentProvider` seam again. Worth
    solving deliberately (pass a provider into `rasterize`) rather than by giving `Cel` a
    back-reference to the manager.

19. **`interpolationReferences` is not pruned when a referenced cel is deleted.** The same shape as
    item 7 but for the transient selection rather than a stored recipe: `interpolationKeyframes`
    skips refs it cannot resolve, so the effect is a silently-shrinking keyframe count rather than a
    crash. Cheap to fix wherever item 7 is fixed.

20. **Registration cost is untested at scale.** `latticeCellSize` targets ~10 cells across the
    longer side, so the ARAP factorisation is over ~150 vertices whatever the drawing — but the
    *point cloud* is every stroke sample at both keyframes, and ICP is run with 8 restarts to
    convergence. That is the number that grows with a >1000-object layer, not the lattice.
    `isRegisteringInterpolation` exists so the UI can say something; nothing has measured what it
    will need to say.

### From Phase 4.5 — the product owner's own list

These came from using the build on an iPad. They were raised explicitly as *future* work, not as
this session's scope, and are recorded here in their order of raising.

21. ~~**The toolbar icon should behave like every other tool: tap once to turn the mode on, tap again
    to open its menu.**~~ **Done in Phase 4.6.** The button moved to the timeline (item 23) and is
    two-stage; `InterpolatePanel` is now a popover holding thickness fade, Clear References and Exit
    Interpolate Mode, with no mode switch in it. The exit landed *in the popover* rather than on the
    right of the bar — the bar's right-hand slot went to Remove Interpolation, which is pressed far
    more often than leaving the mode.

22. ~~**Generate can be pressed twice and interpolates twice.**~~ **Done in Phase 4.6** —
    `.alreadyInterpolated`, exactly as sketched, and Reproject does not inherit it.

23. ~~**The interpolate entry point belongs in the animation timeline's top bar.**~~ **Done in
    Phase 4.6** — `AnimationTimeline.interpolateButton`, next to onion skin and loop.
    `ActivePanel.interpolate` is gone.

24. **Scrubbing runs at roughly 10 fps with four vector strokes.** Measured on the iPad, on a
    drawing far smaller than the >1000-object layers standing constraint C anticipates, so this is
    not the scale problem item 20 describes — it is the per-tick cost item 14 predicted, arriving
    much earlier than expected. **Item 14's `ScrubSession` is the designed fix and it is now
    measured rather than speculative**: every slider tick re-embeds both keyframes' geometry and
    re-runs the ARAP factorisation, both of which are constant across a drag. Start there, and
    profile before assuming it is the whole story at four strokes.

25. **Editing at a transient in-between — confirmed as the intent, and liquify does not fit the
    mechanism.** The product owner (2026-08-01) wants draw / erase / liquify at an in-between while
    it is still derived, with the slider still live afterwards. That is `IMPLEMENTATION.md` Phase 6
    items 2–3 and `PLAN.md` §5.4, and the model has carried `InterpolationRecipe.localEdits` since
    Phase 2, so nothing about it is new — but two parts of it are not covered by what exists. Erase
    is free (an eraser *is* a stroke, `VECTOR_ERASER_PLAN.md` §2.1, so it rides `localEdits` like
    any other). **Liquify does not fit `LocalEdit` at all**: `LocalEdit` carries an element back to
    keyframe space through the inverse map, and a liquify is a *deformation* — a warp composed with
    the interpolation's own warp, with no element to carry. Where it is stored (a per-recipe
    displacement field, a second lattice stacked on the group's) is an open design question and
    should be answered before Phase 6 starts wiring, not during. See also item 6: `LocalEdit`
    carrying only a `VectorStroke` already excludes a fill made at an in-between.

### From Phase 4.5 — noticed while working

26. **A vector cel still carries `fillImage` and `bakedImage`, so raster features allocate
    canvas-sized bitmaps on a vector layer.** Select+move, Clear and bucket fill all go through the
    raster path even when the layer is `.vector`, which means a vector layer can quietly acquire
    full-canvas images that the vector pipeline neither reads nor benefits from — memory cost, and a
    second representation of the same drawing that nothing keeps in sync. **The product owner wants
    vector fully divorced from raster features.** Raised as a design question this session and
    deliberately *not* acted on: it reaches well past interpolation (it is really about what a vector
    layer *is*), it would touch `PixelOps`, the fill tool, the selection tools and save/load, and item
    18 above wants a `ContentProvider` seam through `rasterize` that this work should be designed
    alongside rather than after.

### From Phase 4.6 — the engine does not do what it is supposed to do

**These four are the reason `IMPLEMENTATION.md` gained Phase 4.7, and why that phase goes *before*
Phase 5.** All four are the product owner's own test drawings on the iPad (2026-08-01), each a
two-keyframe scene of one to three strokes — the simplest cases the feature exists to handle. They
are recorded verbatim in substance because the *shape* of each failure is the diagnostic.

27. **A line rotates 180° instead of bending.** Keyframe A: a short vertical line. Keyframe C: a
    large, offset C shape. Expected: the line bends while travelling until it matches the C. Observed:
    a complete 180° flip. Product owner's own hypothesis, which is the right first thing to test:
    **a rotation produces a lower minimum than a deformation does**, so the ARAP objective prefers to
    spin the shape rather than bend it. If that is confirmed, the question is what the papers do about
    it — a rigid pre-alignment subtracted before the elastic fit, a rotation penalty, or a
    correspondence initialisation that never offers the flipped solution.

28. **Registration takes ~1 minute on two strokes.** Keyframe A a vertical line, keyframe C a C shape
    *encompassing* it; Generate froze the app for around a minute before producing output. Note this
    is registration, not scrubbing (item 24 is the scrubbing half). Both together mean the engine
    cannot currently be *evaluated* artistically, which is why performance is inside Phase 4.7 rather
    than deferred behind it.

29. **The warp degrades to a scale-and-fade.** Same drawing as item 28. Observed: the line did not
    bend at all — it grew in size and faded out, while the C appeared and scaled up to its keyframe
    size. That is the *cross-fade* path, not the warp path (`PLAN.md` §10 decision 2's honest
    degenerate case), which means the correspondence effectively failed and the evaluator fell back.
    **Whether it fell back deliberately or the lattice fit returned something near-identity is the
    first thing to determine** — they need different fixes, and today nothing distinguishes them in
    the output. Product owner asks specifically that this be checked against the papers' own results
    for the same class of input.

30. **Two strokes merging into one does not work.** Keyframe A: two vertical lines. Keyframe C: one
    vertical line between them. Expected: the two merge. Observed: another 180°, and no clean
    transform. This is the topology-change case (N strokes → M strokes), and the product owner's note
    is the important one: **"This may be a problem for messy lineart"** — real lineart is full of
    strokes that split and merge between keyframes, so this is not an edge case, it is the common
    case wearing a small disguise.

**Standing instruction from the product owner for Phase 4.7:** they will supply the papers' PDFs and
any public repositories on request, so the phase can read the actual math and code rather than infer
it. **If the papers' own methods hit the same limits, say so plainly and brainstorm new approaches
rather than reimplementing a known-limited method faithfully.**

**Session 10 answered all four; Session 12 fixed all four. DONE.** The diagnosis is §5's "From
Phase 4.7" and the paper comparison is §5.11. Where each ended up:

| | before | after | fixed by |
|---|---|---|---|
| **27** line spins instead of bending | bend 0.16, coverage 0.31 | bend **0.907**, coverage **0.96** | items 31 + 32 |
| **28** ~1 min registration | 1000 samples = 94 s | **77 ms**, and flat in the sample count | items 28-fix + 35 |
| **29** warp degrades to grow-and-fade | bend 0.17, arc length ×3 | bend **0.985** of the C's 1.072, length 853 of 907 | item 31 |
| **30** two strokes will not merge | span 51 of 200 | span **194.6** of 200 | item 32 |

Item 30's *merge* is still not solved and was never going to be by 4.7 — it is the N:M case (item
33), and what changed is that it is now watchable rather than a collapsing smudge. Item 34 is the
honest completion of it.

### From Phase 4.7 — the ordered fix list

These were written as suggestions per §3.3, but unlike the rest of §8 they were the *content* of
Session 12 rather than optional extras. **31, 32 and 35 are DONE** (commits `b9100af`, `8a46b77`,
`8733589`, `ea85793`); 33, 34, 36 and 37 remain open and are ordered notes for later.

31. **DONE (Session 12).** Un-defer the `.clean` correspondence path for the 1:1 case. **DECIDED 2026-08-01: yes, 1:1 only.**
    Built as `ARAPRegistration.StrokeCorrespondence` — a "tier 0" ahead of the two existing tiers,
    which is a shortcut rather than an escalation: where it applies there is nothing to search for.
    Delivered case 29's bend at **0.985** against the C's own 1.072 (Session 10 predicted 0.944) and
    ink coverage 0.96. Three things the plan did not anticipate, all in §5: the correspondence must
    **replace** the point-cloud data rows rather than join them; the direction bit must be scored
    with each direction **self-aligned**, not under a shared global alignment; and its margin must be
    a fraction of the stroke's **arc length**, not of the forward score. `N:M` falls back to the
    point-cloud path via `RegistrationFrame.correspondence(to:)`, which also refuses any frame
    holding a fill or a placed image.
    The product owner un-deferred it for equal-stroke-count pairings and kept N:M deferred, with the
    explicit note that handling messy and sketchy lineart *is* a real future goal — see item 36 for
    the approach they want brainstormed for it.
    `IMPLEMENTATION.md`'s "Explicitly deferred — do not build these" lists the `.clean` path, on the
    reasoning that cross-fade is an honest degradation. The measurement changes the premise: **the
    four failing drawings cannot be fixed without it.** Nearest-point matching gives a short straight
    stroke no reason to wrap around a long curved one at any rigidity, and arc-length correspondence
    takes case 29's bend from 0.34 to 0.944 against the target's 1.072 (§5). The scope that buys
    that is small — pair strokes 1:1, resample both by normalized arc length, feed the pairs as
    `ARAPRegistration.Constraint`s, resolve stroke direction as one discrete bit per pair scored over
    the whole stroke. The **N:M** case is the hard part and stays deferred (item 33). Per §3.5 this
    is the product owner's call, not the next session's.

32. **DONE (Session 12).** Change the two registration defaults, together, and only together: `icpRestarts: 1` and
    `allowScale: false`. **DECIDED 2026-08-01: change both.** The bill came in as forecast and is
    recorded on `testICPWithoutACorrespondenceRecoversARigidMotionOnlyApproximately`: without a
    correspondence a rigid motion now lands 3.47 off on an L 55 across, where the multi-start landed
    it exactly. The measured matrix in that test's comment also shows eight restarts missed 20° and
    120° *anyway*, so "exact" was a property of which seeds happened to be tried and never of the
    method — and with a correspondence the same motion comes back to within 0.08. One thing the
    decision did not cover: `MotionGrouping` was inheriting `icpRestarts` and is now pinned at 8
    with its own reasoning (§5), because grouping is where the multi-start earns its keep. The coverage-gated escalation described
    at the end of this item is *not* being built now — the product owner asked for it to be recorded
    as a future improvement, and it is item 37. Measured: no case flips, and case 30's collapse goes from a y-span of 36.5
    to 198.5 against the target's 200. Both are needed — either alone is a different wrong answer
    (§5), and `testLockingTheScaleTradesTheCollapseForADifferentWrongAnswer` pins the half-fix so it
    cannot be applied by accident. **The cost is real and is the product owner's call:** the
    multi-start is what lets a genuinely large rotation register at all, and
    `testICPRecoversARigidMotionWithoutAnyCorrespondence` is written against it. frite has no
    multi-start at all (§5.11), which is the evidence that dropping it is the mainstream choice, but
    a drawing that really does rotate 120° between keys will register worse afterwards, and
    `testICPRecoversARigidMotionWithoutAnyCorrespondence` will need revisiting rather than deleting.

37. **Coverage-gated rotation escalation — recorded as a future improvement, not for now.** The way
    to keep large-rotation registration without reintroducing the 180° tie: try the local fit first,
    and widen the rotation search *only* when the result fails a **coverage** test, rather than
    running the unconditional 8-way search every time. It needs the coverage metric that items 36 and
    32 both want, so build that first and this becomes cheap. Product owner asked for it to be noted
    when deciding item 32.

33. **N strokes → M strokes needs a UI, not an algorithm — and that is the literature's answer, not
    a shortcut.** §5.11 has the evidence: frite decomposes drawings into artist-defined parts and
    ships `CorrespondenceTool`, `directmatchingtool`, `registrationlassotool` and `pickstrokestool`
    to let the artist state the matching, and RR-9559 concedes even its part-level many-to-one
    mapping "may not find the best" answer. **Phase 5's motion groups are already most of this
    mechanism**, which is a strong argument that 4.7 should land 31/32 and then let Phase 5 proceed —
    the grouping UI is the correspondence UI. What should *not* happen is a speculative automatic
    stroke matcher; that is past the state of the art.

    The complement, for content that genuinely has no partner, is item 34.

34. **Temporal visibility thresholds are the paper's answer to unmatched content, and our data model
    already has the field.** RR-9559 §5 does not merge unmatched strokes — it fades them out
    progressively, farthest-from-the-target first, via per-vertex thresholds diffused from a seed set
    (Eq. 4). `VectorStroke.visibilityThreshold` and `.sampleVisibilityThresholds` have existed since
    Phase 2 and **nothing sets them**. This is the closest correspondence between our model and the
    paper's, it is the honest answer to "two lines become one" (one line retracts rather than
    merging), and it is also what makes the thickness-fade toggle (§8 item 13 / Phase 3) finally have
    unmatched strokes to act on. Cheap relative to its value, but it depends on 31 to know which
    strokes are unmatched.

36. **Messy/sketchy lineart: match ink to ink, not stroke to stroke — the product owner's proposal,
    and it wants its own brainstorming session.** Raised 2026-08-01 in response to the N:M finding.
    **Decided: not now** (item 31 is 1:1 only), but the product owner is explicit that handling messy
    and sketchy lineart is a real future goal, so this is recorded in full rather than as a one-liner.

    The proposal: stop trying to pair strokes at all. Instead fit the warp so that the **overlap
    between the deformed drawing's ink and the target drawing's ink is maximised**, while
    **minimising each stroke's displacement from where the uncorresponded fit already puts it** —
    i.e. the current rotate-and-translate answer becomes the regulariser rather than the answer. With
    a qualifier that is the sharpest part of the idea: **a higher local density of strokes must not
    read as more overlap** — many overlapping strokes of the same colour are the same ink as one
    stroke, so the objective is over the *ink footprint*, not over samples.

    Three reasons to take it seriously rather than file it:

    - **It dissolves the N:M problem instead of solving it.** There are no stroke identities in the
      objective, so "two strokes become one" stops being a question that has to be answered. That is
      exactly the right shape for sketchy lineart, where the stroke count is an artefact of how the
      artist happened to scribble and carries no meaning.
    - **It is the same metric the diagnosis independently arrived at.** §5's finding is that mean
      residual is a lying metric — case 30 scores 3.6 points while covering a quarter of the target,
      because distance-to-nearest *rewards* piling the source up. Coverage is precisely the measure
      that catches it, and item 32's escalation gate wants a coverage test too. Three separate needs
      converge on building one.
    - **There is literature, and it is the literature frite already leans on.** frite cites Sýkora
      et al., *"As-rigid-as-possible image registration for hand-drawn cartoon animation"* [31] for
      its matching — an **image**-based ARAP registration, not a stroke-based one. So the proposal is
      closer to the mainstream than our current stroke-cloud approach is, and there is prior art to
      read before designing. Get that paper for the brainstorming session.

    Open questions for that session, so it does not start cold: at what resolution is the footprint
    rasterised, and does the objective stay differentiable enough for the existing solver or does it
    become a search; how colour factors in (the "same colour counts once" rule needs a definition
    when colours are merely close); whether it replaces the point-cloud tier or becomes a third tier
    beneath it; and how it interacts with the eraser, whose ink is *negative* (`VECTOR_ERASER_PLAN.md`
    §2.1). Note also that it is a per-*group* objective, so it composes with Phase 5 rather than
    competing with it.

    **When to build it — the product owner's question, answered 2026-08-01 (Session 12).**

    **Recommendation: a later pass, after the phases. It does not need to come before Phase 5, and
    there is exactly one thing Phase 5 must avoid so that stays true.** The evidence is that
    Session 12 just did the structurally identical thing — added a whole new correspondence tier
    ahead of the existing two — and it touched one file plus a call site.

    Why it is modular enough:

    - **Registration already has the seam, and it was exercised this session.** Tier 0 went in
      without tiers 1 or 2 changing at all. The seam is `ARAPRegistration.fit`'s data-row
      construction: something decides what pulls where, and the alternatives to date are "nearest
      point in the cloud" and "the 1:1 correspondence". Ink overlap would be a third answer to the
      same question, in the same place.
    - **The output contract is one type and item 36 does not change it.** Everything downstream —
      the evaluator, the preview, the recipe, persistence, undo — consumes `MotionGroupBinding`'s
      fitted `Lattice` per keyframe and knows nothing about how it was obtained. That is what makes
      this swappable rather than load-bearing: modules stack on the *result* of registration, not
      on its method.
    - **Phase 5 supplies item 36 its input rather than blocking it.** It is a per-group objective;
      groups are what Phase 5 builds. Doing it first would mean building it against the single
      whole-frame group, which is the case it is least suited to.

    The one constraint, and it is a *product* constraint rather than a code one: **keep a motion
    group's membership "which ink is in this group", not "which stroke pairs with which".** Phase 5's
    grouping UI is also the correspondence UI (item 33), so it is the natural place to let an artist
    state stroke-to-stroke matching — and item 36's whole premise is that *there are no stroke
    identities in the objective*. If pairwise stroke identity gets written into the document model
    and its undo, item 36 stops being a new tier and becomes a migration. Group-of-ink membership
    keeps both readings open.

    Two things worth pulling forward regardless, because they are small and shared:

    - **The coverage metric.** Items 32, 36 and 37 all want it and it exists twice already in
      test-local form (§5). Promoting it is a few lines and it is the dependency all three share.
    - **Sýkora et al., *"As-rigid-as-possible image registration for hand-drawn cartoon animation"*
      — get the paper before that session**, per the note above. It is the prior art and frite
      already leans on it.

35. **DONE (Session 12).** Subsample the registration point cloud. `Options.maxRegistrationSamples`
    is 250 and caps what *drives* the fit; residuals are still reported for every source point,
    because motion grouping reads them per point. The target cloud is capped by
    `registerWholeFrameGroup`, which is the caller that owns the index. Registration cost is now
    **flat** in the sample count — 2000 samples went 285 s → 78 ms at coverage 1.00 — because the
    lattice was never what grew.
