# Next session — the layer-compositing project, after the phase 8/9a checkpoint

Everything through phase 8 and phase 9a is on `main` and pushed. `main` is the checkpoint; there are
no `tmp/*` branches and no extra worktrees left. Start by branching off `origin/main` per CLAUDE.md.

Read [LAYER_COMPOSITING.md](LAYER_COMPOSITING.md) — the agreed design, settled with the product
owner. §11 is the build order and §10 is what is still open.

## What is actually left

| # | work | note |
|---|---|---|
| **9b** | effect as a 1-input **node** (§4.4's second wrapper) | small; the seam is already cut |
| **9c** | Sobel, sharpen/unsharp, outline (§7) | wants the multi-pass contract, not new abstraction |
| **§10.2** | which node ops take 2+ inputs beyond Mix | a starting position is in §10 item 2 |
| **§10.1** | delete the mask-tuning harness | **only once the owner confirms** — see below |
| **tests** | split the six heavy UI classes | owner-requested; measured prescription in CLAUDE.md |
| **tests** | `testMovingThePlayheadRebuildsTheBlendedCanvas` is order-dependent | in BUGS.md, fix in setup |

**The checkpoint's boundary suite: 961 total, 956 passed, 2 failed, 3 skipped, 25.7 min.** The three
skips are the two `PAINT_PERF_HEAVY` gates and the known `FillUITests` one. Both failures were
triaged on an erased simulator per CLAUDE.md and neither is a product defect:
`testAnAllNormalDocumentNeverEngagesTheSandwich` passed clean, and
`testMovingThePlayheadRebuildsTheBlendedCanvas` passes 1/1 genuinely alone but fails when any test
precedes it — leftover simulator project state, recorded in BUGS.md. `EffectLayerLogicTests` came in
at **21** (18 before the merge), which is how we know 9a's three new cases ran rather than silently
matching nothing, and `testASlotsOwnBlendModeIsInertButItsOpacityStillFades` was **seen green**,
which retires the last handoff's one blocking "unproven" item.

**The test-parallelism work is the cheapest big win available and the owner asked for it directly.**
`xcodebuild` parallelizes per test *class*, so the suite's ~1,950 s of UI work sits in six
indivisible classes across four workers — two clones idle on the home screen for most of the run.
CLAUDE.md's "Why the full run is 26 minutes" section has the measured per-class table and the
prescription. It is mechanical (move methods between classes in the same file; no `project.pbxproj`
edit) and it parallelizes perfectly across agents, one class each. **Verify by test count from the
xcresult, never the banner** — this is the exact change that could silently stop running tests.

**9b is smaller than it looks.** `RenderNode.effect` is *one field for both wrappers*, because the
wrapper is the position in the tree rather than the data. So 9b is `LayerFolder.effect` in storage,
one `decodeIfPresent`, and one grade call after `fold` in each backend. Nothing else branches on
which wrapper produced the input — keep it that way.

**What 9a established that 9b and 9c inherit:** an effect leaf derives with `blendMode: .normal`,
because a grade *replaces* its backdrop; `compositeEffectMix` is deliberately not source-over (an
effect preserves alpha, so compositing the graded texture over its own backdrop would inflate
coverage to `2a − a²` and thicken every antialiased edge — opacity and mask coverage go in as one
`amount` to a `mix`); and effect scoping *is* isolation, since `enclosesABlend` counts
`effect != nil` and without that an isolated all-normal group plus one effect declines a buffer and
the grade escapes. Both directions are pinned by test.

## Open with the product owner — do not decide these alone

1. **The antialias constant.** At `threshold 0.1` / `antialiasHalfWidth 0.01` the smoothstep spans
   alpha [0.09, 0.11]. Measured against a real `softRound` dab of radius 20 (hardness 0.15): the band
   is an annulus 18.1–18.5 px from centre, **~0.34 px wide, containing 24 fractional pixels** out of
   the ~1264 the dab touches. At the old 0.5/0.05 the same dab had 108 in a ~2 px annulus. **So the
   antialiasing is under a pixel wide and behaves as an effectively hard boolean on most edges** —
   two genuinely soft fixtures caught none at all. If they keep 0.01, say in §6.3 that the smoothstep
   is vestigial at the shipping value rather than leaving it claiming a purpose it no longer serves.
   If they want it back, that is a §6.3 binary-with-threshold design question, not a tuning one.
   **Do not delete the mask-tune harness until they answer.**
2. **The sandwich through a blending Mix.** Measured and pinned:
   `SandwichLogicTests.testTheSandwichThroughABlendingMixIsNotExactAndTheDeltaIsMeasured` asserts
   `["the active leaf in slot 0": 127, "the active leaf in slot 1": 255]`, where the `.normal`
   companion asserts 0. **255 means the mid-stroke pixel bears no relation to the final one.** The
   cause is structural rather than a bug — a fold applies its mode *once*, between two finished
   slots, so a cut inside a slot puts its pieces on opposite sides of the live layer. It snaps
   correct on lift. **Do not build the fix unprompted**; the owner chose to judge it on the iPad. If
   they ask: add `backdrop: CGImage?` to `RenderRequest` honoured by both backends, composite the
   above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from the same stack
   over transparency, emit `αs = c`, `Cs = (R − B(1−c))/c`. Cost is another composite per stroke in
   the latency-critical path.
3. **Drawing onto an active effect layer.** `addEffectLayer` makes the new layer active, matching
   `addLayer` — but ink drawn there goes into a cel nothing renders, i.e. it silently vanishes. There
   is no UI to create one yet, so this is not urgent. The sane default is to *select* it (so its
   properties are editable) while making a draw gesture either a no-op with feedback or a redirect to
   the nearest drawable layer. It is a taste call, not an engine one.
4. **Whether "pause this mask" should come back.** `isEnabled` now means exactly "has sources" — the
   Mask switch was the only way to pause a mask while keeping its sources, so there is no paused
   state left. If the owner wants it, it needs a new affordance and this decision revisited with it.

## Three things carried forward as UNPROVEN — check before you trust them

- **The `EffectPipelines.encode` decline path is reasoned-correct and uncovered.** The merge of
  `p9-layer` and `p9-multipass` created a real defect that git reported no conflict for, because the
  two changes touched different lines: `encode` returned `Void` on one branch and
  `@discardableResult -> Bool` on the other, so the merged caller discarded a "declined — fall back"
  signal and proceeded to `mix()` with an **unwritten pool texture**. Fixed with an explicit `guard`,
  but it only fires when the device declines a texture allocation, which a healthy simulator never
  does. Also in BUGS.md.
- **A green backend-parity test does not prove both backends ran.** These tests append Metal only
  `if CompositorMetalEngine.shared != nil`, and `xcresulttool get test-results activities` showed no
  activity naming the backend — so a pass is equally consistent with CoreGraphics-only execution. The
  fix is cheap and should be done once, generally: an `XCTContext.runActivity` recording the
  exercised backend per iteration.
- **Apple's four non-separable blend modes are still unmeasured against the spec.**
  `coreGraphicsBlendMode` returns `nil` for hue/saturation/color/luminosity, so phase 7's sweep
  compared our shader against our Swift. If Apple's agree, they could take a faster path.

## The hazard this project keeps producing, in five different disguises

**Verify numbers, never summaries — and check what a test actually compared.** Every one of these
passed every check that looked at exit codes, banners, or prose:

1. A fabricated measurement table, written before the sweep it reported was run.
2. A parity sweep that compared the app's own shader against the app's own Swift, while its comment
   claimed it measured us against CoreGraphics.
3. An empty `-destination` reading as `** TEST SUCCEEDED **`, exit 0, `totalTestCount: 0`.
4. A handoff's failure list filtered to fit its author's hypothesis — 12 of 16 named, the 4 that did
   not fit omitted.
5. **Changing one constant silently emptied two tests, and only one noticed.** At
   `antialiasHalfWidth` 0.01 a fixture's fractional annulus narrowed from ~2 px to ~0.34 px.
   `testNestedClipsAgreeByteForByteDespiteTheDoubleRounding` **failed loudly** because its author had
   written `XCTAssertGreaterThan(bothPartial, 0, …)` — an explicit assertion that the fixture is what
   the test thinks it is. `testAMaskWithAFractionalEdgeAgreesBetweenTheBackends` **stayed green while
   testing nothing**, because it had no such line and every pixel resolved to exactly 0 or 255.
   **Write the premise assertion.**

The general form: **a green test proves its two operands are equal, which is not always the two
things its name or its comment says it compared.** Read the `file:line` of a failure before believing
its name, too — two failures here looked like canvas-rendering bugs and were both a missing element
downstream of one swallowed tap.

**The effect abstraction has a structural version of this.** Both backends consume the *same*
Swift-resolved `kindCode`/`params`/`lookupTable` — and now `passes`/`weights` — so **a parity sweep
cannot catch a mistake in the resolution; both sides make it identically and pass green.** A
same-author re-derivation of the formula in the test is not independent either. What works: an
impulse response against mathematics, separable-vs-direct-2D convolution, hand-computed spot checks
at a degenerate radius, and an independent transcription in a different number of stages. **Any new
effect inherits the blind spot and owes the same defence.** The known gap: the directional/off-grid
blur path takes a bilinear-tap branch that only the self-comparing sweep covers.

## Machine and test-run discipline — each of these cost a cycle

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Read `totalTestCount` from the
  xcresult. Build `-only-testing` flags into a shell **array** and pass `"${SUITES[@]}"` — zsh does
  not word-split an unquoted `$VAR`, and one long bogus argument is ignored while reporting success.
- **A PASS under load is trustworthy; a FAIL under load is inconclusive.** Load produces false
  failures, never false passes. Re-run a failure on a quiet machine before letting it decide
  anything, and never wait on behalf of a pass. Proof: `testAMultiplyLayerLooksMultipliedOnTheLive
  Canvas` failed at ~0% idle and passed at 63.97% idle **on the same commit**.
- **Do not read durations as a load signal.** A failing XCUITest short-circuits, so its runtime is
  not comparable to a passing one, and the direction reverses depending on where it died.
- **`uptime` is meaningless on this Mac** — it read 404 with zero booted simulators and 94.6% idle.
  Use `top -l 2 -n 0 -s 2 | grep "CPU usage" | tail -1`, and sample twice.
- **Judge liveness by whether the in-progress `.xcresult` is growing** (`du -sk` twice, 25 s apart),
  never by log output, which your own pipeline may be buffering. Use `pgrep -x xcodebuild`.
- **A new test file needs a `project.pbxproj` edit** — `PaintSoftwareUITests` opts out of
  `PBXFileSystemSynchronizedRootGroup` and hand-lists its sources, so an unregistered file compiles
  nowhere, runs nothing, and prints green. App sources under `PaintSoftware/` are synchronized.
- **Never report a perf number from a Debug build** — 62× and 440× ratios measured here. A host-side
  `swiftc` harness runs the effect CPU reference with no simulator in ~5 s a loop.
- **Do not add a heavy case to the fast tier**; gate it behind `PAINT_PERF_HEAVY`.
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, boot, re-run the single
  test. Never re-run the 22-minute suite to decide whether a failure was real.

## If you delegate

The owner pre-authorized it (2026-08-14): **3 opus + 8 sonnet** concurrent, no need to ask per
fan-out. Opus for design-bearing work, sonnet for measurement, docs and survey reads. If your harness
carries a blanket "do not use subagents", the owner has overridden it for this project; it lives in
the system prompt and cannot be edited from a session, which is why it is recorded here.

**The agent cap is not the real ceiling — the simulators are.** Six concurrent workers once drove
this machine to 0.0% idle with nine `xcodebuild` processes and *zero* simulators booted, everything
stuck in boot-retry; that is what the owner sees as "Simulator quit unexpectedly". Use
`/Users/juliapark/.config/paintapp/simlock.sh`, and write the literal token **`@SIM@`** in the
destination — **never `$SIM_UDID`**, which the caller's shell expands to empty, after which
xcodebuild answers a malformed `-destination` by printing its help and exiting 0.

**One worktree, one worker.** A worker blocked on a background run reports as finished and is still
live; two of them once committed into the same index seven seconds apart. And **workers run only the
suites their own change touches** — the full suite runs once, at the boundary, on a quiet machine.

**`simlock.sh` still has a bug worth fixing:** its reap condition is `{ owner dead } || { age >
3600 }`, so a lock older than an hour is reaped *even when its owner is alive and running*, and the
reaper then `simctl erase`s the device out from under it. Reap on a dead owner unconditionally, and
apply the age check only when the pid is missing or unreadable.

**Forbid workers from running `graphify update` on a feature branch** — a 300-line GRAPH_REPORT diff
conflicts against every other branch in flight.

## Before you run out of context

Write the next session's prompt here and commit it, addressed to an Orchestrator, covering what is
genuinely left and what you learned that would otherwise be rediscovered — including this
instruction. Write it *early*; a handoff written while you still have room is worth more than a
complete one you never get to write. **Land it where the next session will actually look** — on
`main` if you merge, and on the most advanced branch otherwise, because the copy in a fresh worktree
is the one that lies. This file has been stale twice, and the second time cost a session real work.
