# Vector Interpolation — Handoff & Session Protocol

**If you are a fresh session picking up this work, read this file first, then follow §1.**

This is the *live* document. [VECTOR_INTERPOLATION_PLAN.md](VECTOR_INTERPOLATION_PLAN.md) (why) and
[VECTOR_INTERPOLATION_IMPLEMENTATION.md](VECTOR_INTERPOLATION_IMPLEMENTATION.md) (what, in order) are
stable references. This file is state: where the work actually is, what tripped over what, and what
to do next.

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
| **Current phase** | **Phase 0 — done.** Phase 1 (lattice/ARAP engine) not started. |
| **Branch** | `claude/vector-interpolation-design-9d5b83` |
| **Last known-green commit** | `3ecd1e2` — `interp(phase 0): fix vector onion-skin blank bug, add OnionSkinSource seam`. Fast suite green. |
| **Tree state** | Clean. |
| **Blocked on** | Nothing. |

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

### What is next

**Phase 1** in `VECTOR_INTERPOLATION_IMPLEMENTATION.md` — the lattice + ARAP deformation engine, pure
logic, no knowledge of keyframes/cels/interpolation. The project's main technical risk; escalate to
Opus 5 per §3.4 if the numerics get hard.

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
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware -destination 'platform=iOS Simulator,name=interp-ipad' -derivedDataPath /tmp/interp-dd -only-testing:PaintSoftwareUITests/BrushEngineLogicTests -only-testing:PaintSoftwareUITests/ShapeDetectorLogicTests
```

Add your own logic-test class to that filter as you create it, e.g.
`-only-testing:PaintSoftwareUITests/LatticeLogicTests`.

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

*(Empty — nothing suggested yet.)*
