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
| **Current phase** | **Phase 3 — done.** Phase 4 (interpolate mode UI, references, slider, Generate) not started. |
| **Branch** | `claude/vector-interpolation-design-9d5b83` |
| **Last known-green commit** | `f6986df`. **Full suite green with Phase 3 in: 450 tests, 449 passed, 0 failed, 1 skipped, `xcodebuild` exit 0**, no harness errors. The skip is the pre-existing `testFillToolBridgesOpenContourGapWhenGapClosingEnabled`. Wide pure-logic tier: 364 tests, 0 failures. |
| **Tree state** | Clean. |
| **Blocked on** | Nothing. |

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

### What is next

**Phase 4** in `VECTOR_INTERPOLATION_IMPLEMENTATION.md` — interpolate mode UI, references, the `t`
slider and Generate. The first phase where any of this is reachable from the app, and the first
usable milestone.

**Read §5.9 before starting** — what Phase 3 decided that Phase 4 inherits, in particular that the
evaluator needs a `ContentProvider` and never touches `CanvasManager` itself, and that the two
render qualities are what the slider drag/release should switch between.

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
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/OnionSkinLogicTests -only-testing:PaintSoftwareUITests/LatticeLogicTests -only-testing:PaintSoftwareUITests/ARAPLogicTests -only-testing:PaintSoftwareUITests/InterpolationModelLogicTests -only-testing:PaintSoftwareUITests/InterpolationRenderLogicTests
```

179 tests, all green as of `f6986df`. Add your own logic-test class to that filter as you create it.

**Wider, still fast (~4 min).** Every pure-logic class in the suite — 364 tests as of `f6986df`.
Worth running before a commit that touches persistence, rendering or `CanvasManager`, since the fast
filter above misses `ProjectSaveLogicTests`, the eraser classes and the characterisation tests:

```bash
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests -only-testing:PaintSoftwareUITests/OnionSkinLogicTests -only-testing:PaintSoftwareUITests/LatticeLogicTests -only-testing:PaintSoftwareUITests/ARAPLogicTests -only-testing:PaintSoftwareUITests/InterpolationModelLogicTests -only-testing:PaintSoftwareUITests/InterpolationRenderLogicTests -only-testing:PaintSoftwareUITests/StrokeGeometryLogicTests -only-testing:PaintSoftwareUITests/VectorEraserLogicTests -only-testing:PaintSoftwareUITests/VectorEraserHybridLogicTests -only-testing:PaintSoftwareUITests/RasterVectorParityLogicTests -only-testing:PaintSoftwareUITests/ProjectSaveLogicTests -only-testing:PaintSoftwareUITests/BackupManagerLogicTests -only-testing:PaintSoftwareUITests/CelCRUDCharacterizationTests -only-testing:PaintSoftwareUITests/LayerTreeCharacterizationTests -only-testing:PaintSoftwareUITests/ViewPresetCharacterizationTests
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
