# You are the Orchestrator for the rest of the layer-compositing project

Not for one phase. **Phase 9's two wrappers, §7's remaining effects, §10, and the iPad judgements are
yours**, and you carry the project until they are done or the owner redirects you. Read
LAYER_COMPOSITING.md — the agreed design, settled with the product owner. §11 is the build order.

## START HERE — phase 8 has a real regression and is NOT merged

**`tmp/p8-integrate` (at `cbb46fa`) holds all of phase 8 + phase 9's kernels + the Release fix + the
mask harness, and it does not merge to `main` until this is fixed.** Boundary suite:
**901 total, 883 passed, 16 failed, 2 skipped** (the 2 skips are the expected `FillUITests` and
`PAINT_PERF_HEAVY` ones). Baseline was 846 with 1. **16 is not environmental — do not triage it away.**

**The failures are one cluster: layer-panel drag, drop, delete and restack.**
`testDroppingLayerOntoFolderMovesItInside`, `testDroppingLayerOntoLayerCreatesFolderWithBoth`,
`testDroppingFolderOntoFolderNestsIt`, `testLongPressDragReordersLayersAndDropSticks`,
`testReorderingLayersIsUndoable`, `testDeletingLayerBelowActiveKeepsSameLayerActive`,
`testDeletingLayerIsUndoableAndRestoresContent`, `testSwipeRevealsDeleteAndDuplicateButNotEdit`,
`testHidingFolderHidesContentsOnCanvasAndReshowingRestoresThem`,
`testFolderOpacitySliderPersistsThroughSetFolderOpacity`,
`testRepeatedAddDeleteLayersDoesNotCrashOrFreeze`, plus phase 8's own
`testALayerDropsIntoAnInputSlotAndReportsItAsItsFolder`. Representative messages: *"Dropping a layer
onto another should create a folder holding both"* and *"Sanity-check the drag actually landed"*
(got `Vector 1`, expected `Vector 3`). **Drags are not landing at all.**

**Diagnosis already done — start from it rather than repeating it.** The *model* guards are correct
and permissive by default: `canDrop(inContainer:)` returns `true` for a nil container and for any
non-node folder ([CanvasManager+LayerTree.swift:148](PaintSoftware/Models/CanvasManager+LayerTree.swift#L148));
`canRestackFolder` refuses only slots (:159). The logic tier agrees — `LayerTreeCharacterizationTests`
is 26/26 green. **So the bug is in the panel's UI wiring**, i.e. phase 8's widening of
`LayerRowModel.isFolder: Bool` into `kind: Kind` plus the three affordance gates
(`canDelete`/`canDrag`/`acceptsDrop`) in `LayerRowModel`, `LayerStackCell.configure` and
`LayerStackListView`'s `dropBetween`/`dropOnto`. Suspect the gates defaulting wrong for the `.layer`
and plain `.group` kinds, or the drag lift being gated on a value only node/slot rows were meant to
set. Check `AnimationTimeline`'s row path too — the panel worker rerouted slot drag-lift there as well.

**Why no worker caught it:** each ran only its own suites (correct policy, and the owner's
instruction), and none of them owns the panel drag/drop suite. The boundary suite is the only thing
that sees cross-suite regressions, and it did its job. Keep the policy; just do not treat a worker's
green as the phase's green.

**Also unverified and unmerged:** `tmp/p9-multipass` (`c037c3e`) has blur, bloom and the multi-pass
contract committed but the orchestrator never read its numbers. Treat as unproven.

**Not started:** `tmp/p8-slotmode` — the slot-`blendMode` fix and four §4.3 doc corrections, fully
specified in the section below. A latent gap only: the panel suppresses the control, so it cannot be
reached through today's UI.

## State

Phases 0–7 are on `main`. **Phase 8 is built but blocked on the regression above.** Phase 9 is half
done: the effect **kernels** ship (104/104 green), **neither wrapper does**.

**The two git traps earlier handoffs warned about are gone.** The local `main` checkout at
`/Users/juliapark/Desktop/Kevin.P/PaintSoftware` is clean and fast-forwarded; the abandoned
vector-interpolation index was cleared 2026-08-14 with the owner's approval and is preserved in
`stash@{0}` there. Read `origin/main` anyway out of habit, but the checkout will no longer lie to you.

**Why that pile was safe to clear, since the reasoning was wrong in every previous handoff.** They all
said "that content is already merged upstream." The conclusion was right, the reason was not, and the
wrong reason is what made it unverifiable — a worker sent to check diffed the index against
`origin/main`, found 46 of 48 files differing, and correctly reported the stated claim was false. The
truth: it was an **older draft** staged against a base **134 commits** behind, from before phases 6–7
of the interpolation feature existed. The tell was `InterpolatePanel.swift` — the staged copy
implements an "Interpolate Mode" toggle that `origin/main` documents *deliberately removing*.
**Generalise this: diffing an old-base changeset against a newer tip measures evolution, not unmerged
work.** Ask whether the base is an ancestor and how far back, not whether content matches the tip.

## Read this first

**Your context is the scarce resource, and it is spent by doing rather than by deciding.** Keep for
yourself: design decisions, scope calls, what to ask the owner, **verifying a worker's numbers**, and
deciding what happens next. Everything else goes to a worker.

**Delegation cap is 3 opus + 8 sonnet.** Opus for design-bearing work, sonnet for measurement, docs,
mechanical registration, survey reads.

**But width is not test parallelism, and this session learned it the hard way.** Six concurrent
workers drove the machine to 0.0% idle with nine `xcodebuild` processes and *zero* simulators booted —
everything stuck in boot-retry, which is what the owner sees as "Simulator quit unexpectedly." There
are two dedicated devices and that is the hard ceiling on concurrent runs no matter how many agents
are alive.

**Use the lock. It is mechanical because instructions failed.** A worker booted a third simulator
despite being told twice not to.

```
/Users/juliapark/.config/paintapp/simlock.sh xcodebuild test \
  -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination "platform=iOS Simulator,id=@SIM@" \
  -only-testing:PaintSoftwareUITests/<Suite> -derivedDataPath build/DerivedData
```

Write the literal token **`@SIM@`**. **Do not write `$SIM_UDID`** — the script execs the command
directly, nothing re-expands it, the caller's shell expands it to empty first, and xcodebuild answers
a malformed `-destination` by printing its help and **exiting 0**. That reads as success and leaves an
xcresult with no `Info.plist`. The orchestrator wrote that bug into three worker prompts before
catching it; the script now hard-fails on an unsubstituted destination. Put the `@SIM@` form in every
worker prompt.

**Workers run only the suites their own change touches.** The full suite runs **once**, at the
boundary, on a quiet machine, by a dedicated worker. Telling six workers to run the ~750-case fast
tier is what saturated the machine; the owner called this out directly.

**Verify numbers, never summaries.** Read `totalTestCount` from the xcresult yourself. This session
that caught the empty-destination bug. Earlier sessions shipped a fabricated table and a parity sweep
that compared the wrong two things. **Three distinct instances of the same hazard, all of which passed
every check that looked at exit codes and banners.**

**Workers stall waiting on background runs.** Do not resume blind — `git -C <worktree> log`/`status`,
read the newest xcresult, `ps aux | grep xcodebuild`, *then* instruct. An in-progress `.xcresult` has
no `Info.plist` and `xcresulttool` errors on it; that means running, not corrupt. A mid-iteration
failure count is not a finding — check whether a newer run has already started before reacting.

**Commit before every test run.** An interrupted agent loses uncommitted work and nothing else;
worktree and commits persist, so re-launching a worker onto the same worktree is the cheap recovery.

## What is left

| # | work | done when |
|---|---|---|
| **9a** | Effect **as a stack layer** (`LayerKind.compositing`, §4.4) | an adjustment layer grades what is below it in its container |
| **9b** | Effect **as a 1-input node** (§4.4) | the same shader grades only what is in its slot |
| **9c** | Sobel, Sharpen/unsharp, Outline (§7) | may want the multi-pass infrastructure |
| **§10.1** | Bake the mask constants the owner picks | harness ships on `tmp/mask-tune`; awaiting the owner's two numbers |
| **§10.2** | Which node ops take 2+ inputs beyond Mix | phase 8's UI now exists, so this is unblocked |
| **iPad** | Two owner judgements — see below | |

**§4.4 is the whole of 9a/9b and it is smaller than it looks:** both wrappers are one shader; *only
the input-resolution rule differs* — "the accumulated backdrop so far in this container" versus "this
slot's composite." Both hand the same texture to the same kernel. Nothing else branches on which
wrapper was used. Container scoping is what keeps the layer form predictable.

## The two iPad judgements, already explained to the owner

The owner has the full protocol and is waiting on hardware. **Do not re-explain it; ask whether they
have run it.** Build Release (`-configuration Release`, now in CLAUDE.md's recipe) from the worktree —
`deploy.sh` pulls `main` and never ships branch work. **Do not install to the device yourself.**

1. **§10.1 mask constants.** `tmp/mask-tune` ships live sliders for `AlphaMask.threshold` (0.5) and
   `antialiasHalfWidth` (0.05). Soft brush, watch the mask edge against the brush edge. Wanted back:
   two numbers. If nothing in range feels right, that is the more valuable answer — it would mean
   §6.3's binary-with-threshold decision needs revisiting, not the constants. **Delete the harness
   when the numbers are baked** (`MaskTuningOverlay.swift` plus the `var`s; it is a clean revert).
2. **The mid-stroke approximation.** Long-deferred, and this session made the stakes worse — see below.

## Phase 8's finding, which the owner has seen and has not yet ruled on

**The sandwich degrades through a blending Mix**, measured and pinned:
`SandwichLogicTests.testTheSandwichThroughABlendingMixIsNotExactAndTheDeltaIsMeasured` asserts
`["the active leaf in slot 0": 127, "the active leaf in slot 1": 255]`; the `.normal` companion at
:690 asserts exactly 0. **255 means the mid-stroke pixel bears no relation to the final one.**

The cause is structural, not a bug: a fold applies its mode *once*, between two finished slots, so a
cut inside a slot puts its pieces on opposite sides of the live layer and neither half can fold
against the operand the whole document folds against. It is the **same class** as the three
pre-existing 127 cases (`testTheSandwichIsNotExact…`) and snaps correct on lift.

**Do not build the fix unprompted** — the owner chose to judge it on the iPad. If they ask: add
`backdrop: CGImage?` to `RenderRequest` honoured by both backends, composite the above stack over the
pre-stroke backdrop `B` to get `R`, take coverage `c` from the same stack over transparency, emit
`αs = c`, `Cs = (R − B(1−c))/c`. Cost is another composite per stroke in the latency-critical path.

## What phases 8 and 9 established — do not re-litigate

- **`Mix(A,B,mode)` equals stacking B over A with that mode, exactly — delta 0, all 25 modes, both
  backends.** §4.3's central claim, now measured rather than asserted. It was expected to be 1; it is
  0 because the extra slot buffer is a copy onto transparency, lossless in premultiplied 8-bit. **No
  new kernel was needed** and none should be added.
- **Slot 0 is the backdrop and is the lowest row.** Each slot derives as its own `RenderNode`, which
  is what makes "always isolated" expressible and lets a slot keep its own opacity/blend/mask.
- **Splitting a `.fixed(2)` Mix yields a one-slot Mix** — a shape its own arity says cannot exist. Both
  backends render it correctly, but **no validator may assume arity holds for a sandwich half**. Pinned
  by `testAHalfOfATwoSlotMixKeepsTheOpAndLosesASlot`.
- **§4.3's "no new tree arithmetic" is optimistic in three places, not one.** The survey named
  undeletable slots and contiguity. The third is *ordering*: the panel's long-standing "an empty folder
  sorts above everything" rule floats an empty Input A above a filled Input B and **silently inverts
  which slot is the backdrop**. Fixed by ranking an unfilled slot by its index;
  `testFillingTheUpperSlotFirstStillLeavesInputAAsTheBackdrop` is the fixture. Do not undo it.
- **Slot rows refuse reordering** — deliberate. Allowing it makes the stored index and the displayed
  order two answers to one question. Operands are reordered by moving what is *inside* the slots.
- **The effect abstraction: one `Effect` enum, and neither backend switches on it.** Both consume
  `kindCode`, a flat all-scalar `params` block, and a 256-entry `lookupTable`; interpretation happens
  once, in Swift. Params are all-scalar deliberately — a `float2`'s Metal alignment matches
  `SIMD2<Float>` only by luck, and a padding disagreement shifts every later field without failing to
  compile. **Both wrappers must consume this unchanged.**
- **That abstraction has a blind spot its author documented rather than hid:** because both backends
  consume the *same* Swift-resolved values, **a parity sweep cannot catch a mistake in the resolution —
  both sides make it identically and the sweep passes green.** The suite carries spec spot-checks and
  an independent Python transcription for this reason. Any new effect inherits the blind spot and owes
  the same defence.
- **Apple's four non-separable blend modes are still unmeasured against the spec.** Phase 7's sweep
  compared our shader against our Swift. The open experiment stands: if Apple's agree, they could take
  a faster path.
- **Backend agreement is not one number.** `.normal` and masks are exactly 0; blend modes hold to a
  measured ≤1 channel step; effects to a measured ≤1 with `gradientMap`'s 1 being a bound **on a
  black-to-white ramp only** (it indexes by a dot product, which fast math may contract — a steeper
  gradient moves further per shifted index).

## Gotchas that each cost a cycle — put these in every worker prompt

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Read `totalTestCount`, never the
  banner. Build `-only-testing` flags into a shell **array** and pass `"${SUITES[@]}"` — zsh does not
  word-split an unquoted `$VAR`.
- **A new test file needs a `project.pbxproj` edit** — `PaintSoftwareUITests` hand-lists its sources,
  so an unregistered file compiles nowhere, runs nothing, and prints green. App sources under
  `PaintSoftware/` are synchronized and need no edit.
- **A test's stdout does not reach the build log from the runner app.** Put measurements in an
  `XCTContext` activity or they are unreadable afterwards. One worker lost a table to `print()`.
- **Never report a perf number from a Debug build** — 62× and 440× Debug-to-Release ratios measured
  here. **The test target now compiles under `-configuration Release`** (fixed this session, BUGS.md
  entry deleted), so measure directly rather than extracting loops to a standalone harness.
- **Do not add a heavy case to the fast tier** — a ~400 MB case pushed an unrelated suite's case from
  0.073 s to 8.98 s, surfacing nowhere near its cause. Gate heavy ones behind `PAINT_PERF_HEAVY`.
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, boot, re-run the single
  test. Never re-run the 22-minute suite to decide whether a failure was real.
- A host-side `swiftc` harness runs the effect CPU reference with no simulator in ~5 s a loop.

## At each phase boundary

Delegate these. Full XCUITest suite after the lock's erase/boot, and **say plainly if you skip it
rather than implying it passed**. Prune the shipped sections of LAYER_COMPOSITING.md — prune what is
done rather than appending status. **Delete `PHASE8_SURVEY.md` when phase 8 merges**; it is a working
document. Append the one-line SESSION_LOG.md entry and drop the oldest so only five remain. Refresh
the graphify report and commit it — and forbid workers from running `graphify update` on a feature
branch, since a 300-line GRAPH_REPORT diff conflicts against every other branch in flight. Merge to
`main` after the suite. Match the codebase's comment density: it explains why, never what.

**Before you run out of context, write the next session's prompt to `nextprompt.md` and commit it** —
addressed to an Orchestrator, covering whatever is genuinely left, including what you learned that
would otherwise be rediscovered and this same instruction. Keep it about this long, and write it
*early*; a handoff written while you still have room is worth more than a complete one you never get
to write.
