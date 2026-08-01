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
| **Current phase** | **Phase 4.6 — done.** The second UI pass; the interpolate-mode layout is now settled. **Next is Phase 4.7 — engine correctness — *before* Phase 5**, because the engine fails all four of the product owner's test drawings (§8 items 27–30). |
| **Branch** | `claude/vector-interpolation-design-9d5b83`, **rebased onto `origin/main`** (Session 9's timeline work: infinite scroll, popover menus, the `onionSkinButton`/`transportControls` refactor). No upstream — ask before pushing. |
| **Last known-green commit** | **Full suite green at the 4.6 boundary: 512 tests, 511 passed, 0 failed, 1 skipped, `xcodebuild` exit 0**, first attempt after a `simctl erase` — five phase boundaries in a row. The skip is the pre-existing `testFillToolBridgesOpenContourGapWhenGapClosingEnabled`. |
| **Tree state** | Clean. |
| **Blocked on** | Nothing. Phase 4.7 is unblocked, but **ask the product owner for the papers' PDFs and any public repositories** at its start — they offered, and the phase is largely a reading exercise. |

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

### What is next

**Phase 4.7 — engine correctness** (`IMPLEMENTATION.md`), *before* Phase 5. The product owner's four
iPad test drawings all fail in ways no amount of motion grouping fixes: a line rotates 180° instead
of bending, a warp degrades to a scale-and-fade, two strokes will not merge into one, and
registration takes a minute on two strokes. **§8 items 27–30 are the four cases, with what was
expected and what happened.** Motion groups are a refinement of a correspondence that is wrong in the
base case; building them first makes them a workaround rather than a control, and writes every Phase
5 acceptance test against output that already looks wrong.

The product owner will supply the papers' PDFs and any public code on request — ask. If those methods
hit the same limits, say so and brainstorm rather than reimplementing a known-limited method
faithfully.

**Then Phase 5** — motion groups: tagging, auto-grouping, visualisation. **Read §5.10 before starting
it** — what Phase 4 decided that Phase 5 inherits, as amended by 4.5 and 4.6.

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
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/OnionSkinLogicTests -only-testing:PaintSoftwareUITests/LatticeLogicTests -only-testing:PaintSoftwareUITests/ARAPLogicTests -only-testing:PaintSoftwareUITests/InterpolationModelLogicTests -only-testing:PaintSoftwareUITests/InterpolationRenderLogicTests -only-testing:PaintSoftwareUITests/InterpolationWorkflowLogicTests
```

203 tests, all green as of `39f4365`. Add your own logic-test class to that filter as you create it.

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
