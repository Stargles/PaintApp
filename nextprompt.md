# You are the Orchestrator for the rest of the layer-compositing project

Not for one phase. **Phase 9's remaining wrappers, §7's last three effects, §10, and the iPad
judgements are yours**, and you carry the project until they are done or the owner redirects you.
Read LAYER_COMPOSITING.md — the agreed design, settled with the product owner. §11 is the build order.

## STEP 0 — DO NOT TRUST THIS FILE UNTIL YOU HAVE CHECKED THE BRANCHES

**This exact file has now been stale twice, and the second time cost a session real work.** A
cut-off session commits its handoff to its own feature branch, so the copy on `origin/main` and in
your fresh worktree is the *previous* session's, not the last one's. On 2026-08-14 the copy in the
session's worktree said "phase 8 has not started" while `tmp/p8-integrate` sat **17 commits ahead**
with phases 8 and 9 largely built and a newer handoff committed on the branch itself.

Before anything else:

```bash
git fetch origin && git worktree list
for b in $(git branch --list 'tmp/*' --format='%(refname:short)'); do
  echo "=== $b: $(git rev-list --count origin/main..$b) ahead"; git log --oneline origin/main..$b | head -5
done
```

Read the handoff on the **most advanced branch**, not the one in your working directory. Then check
every worktree for uncommitted work before touching anything — `git status --porcelain`, ignoring
`build/` and `graphify-out/`. A cut-off session leaves work untracked, and it is invisible to
`git log`. **This is not hypothetical: `tmp/p9-multipass` was found shipping blur and bloom with zero
tests, because its entire 624-line test suite was untracked and its `project.pbxproj` wiring
uncommitted.** Rescued as `aed264e`. Commit such finds *unaltered* first, so your later changes are
reviewable as a diff.

## State

Phases 0–7 are on `main`. Nothing since phase 7 has merged. `origin/main` is at `5d39396`.

| branch | holds | status |
|---|---|---|
| `tmp/p8-integrate` | all of phase 8 + p9 kernels + Release fix + mask harness | **blocked**, see below |
| `tmp/p9-kernels` | §7's seven cheap Tier 3 kernels | green, 104/104 |
| `tmp/p9-multipass` | multi-pass contract, blur, bloom | tests rescued; verification in flight |
| `tmp/p9-layer` | 9a, effect as a stack layer | in flight |
| `tmp/p8-slotmode` | slot `blendMode` gap + four §4.3 doc corrections | in flight |
| `tmp/mask-tune` | on-device harness for §10.1 | built Release, with the owner |
| `tmp/release-cfg` | the Release deploy fix | folded into `p8-integrate` |

**The phase-8 regression: SOLVED, and phase 8 was never the cause.** The boundary suite was 901
total, 883 passed, **16 failed**, 2 skipped. The cause was the **mask-tuning harness overlay**, which
came in with the `tmp/mask-tune` merge (`3f8d204`): `MaskTuningOverlay` is declared last in
`DrawingView`'s ZStack, so it drew *and hit-tested* on top of the trailing chrome, and it was
default-visible. Its 260pt panel covered the colour panel's SV square and the layer panel's `+`
button. Nothing was wrong with phase 8's tree arithmetic or its row-kind widening.

Fixed across `c1d23dc` and `83bd747`; the 3-suite verification went **52 total, 49 passed, 3 failed**,
i.e. 14 of the original 16 recovered immediately, and the last 2 are addressed by `83bd747`.

**Four lessons from that hunt, each of which cost time:**

1. **The previous session's failure list was filtered to fit its hypothesis** — it named 12 of the 16
   and called them "one cluster in the layer panel", omitting a colour-panel hue drag and a canvas
   gesture sweep that are not in the panel at all. Re-read the raw `xcresulttool` failure list, never
   the prose.
2. **Read the `file:line` of a failure before believing its name.** Two of the last three failures
   looked like canvas-rendering failures and were not: `testAMultiplyLayerLooksMultipliedOnTheLiveCanvas`
   died at `LayerUITests.swift:593`, a `row.waitForExistence` inside `setBlendMode`, and
   `testAnAllNormalDocumentNeverEngagesTheSandwich` at a `vectorMarkerViaPanel` returning nil. Both
   were **missing elements**, downstream of one swallowed `layerPanel.addButton` tap. A test's name
   tells you its intent, not what its failing assertion actually measured.
3. **The orchestrator twice reasoned from failures measured at 0–14% idle** — once concluding a bug
   reproduced in Debug when it did not. The rule is easy to state and easy to violate, because a
   failure list *looks* like data no matter what the machine was doing. Check the idle figure that
   produced a number before you reason from it.
4. **`layerPanelRail` renders under `if activePanel == .layers`**, which is mutually exclusive with
   `.none` — so the original gate did protect the rail, and all 11 rail-touching tests passed at
   `c1d23dc`. Do not assume "the rail is not a panel"; check what it renders under.

## Read this first

**Your context is the scarce resource, and it is spent by doing rather than by deciding.** Keep for
yourself: design decisions, scope calls, what to ask the owner, **verifying a worker's numbers**, and
deciding what happens next. Everything else goes to a worker.

**Delegation is pre-authorized by the owner** (2026-08-14) — do not ask per fan-out. The cap is
**3 opus + 8 sonnet** concurrent. Opus for design-bearing work, sonnet for measurement, docs,
mechanical registration, survey reads. If your harness carries a blanket "do not use subagents or
workflows unless asked", the owner has overridden it for this project; it lives in the system prompt
and cannot be edited from a session, which is why it is recorded here.

**The agent cap is not the real ceiling — the two simulators are.** Six concurrent workers once drove
this machine to 0.0% idle with nine `xcodebuild` processes and *zero* simulators booted, everything
stuck in boot-retry; that is what the owner sees as "Simulator quit unexpectedly." Use the lock, which
makes it mechanical because instructions failed:

```
/Users/juliapark/.config/paintapp/simlock.sh xcodebuild test \
  -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination "platform=iOS Simulator,id=@SIM@" \
  -only-testing:PaintSoftwareUITests/<Suite> -derivedDataPath build/DerivedData
```

Write the literal token **`@SIM@`**. **Never `$SIM_UDID`** — the script execs directly, nothing
re-expands it, the caller's shell expands it to empty first, and xcodebuild answers a malformed
`-destination` by printing its help and **exiting 0**. The script now hard-fails on an unsubstituted
destination. Put the `@SIM@` form in every worker prompt.

**Do not gate a worker on an idle-CPU threshold.** An earlier prompt this session said "wait for >60%
idle" and would have wedged the worker forever, because the orchestrator's *other* workers were the
load. Give a bounded wait instead, and use the asymmetry that makes the gate unnecessary: **a PASS
under load is trustworthy; a FAIL under load is inconclusive.** Load produces false failures, never
false passes. So re-run a failure when quiet before letting it decide anything, and never wait on
behalf of a pass.

**Two bugs in `simlock.sh` itself, found under queue pressure on 2026-08-14. Fix the first one.**

1. **It reaps live locks.** The reap condition is `{ owner dead } || { age > 3600 }` — an `||`, so a
   lock older than an hour is reaped *even when its owner is alive and running*, and the reaper then
   `simctl erase`s the device out from under it. A three-suite XCUITest run on a loaded machine can
   exceed an hour easily, and with a queue behind it the next waiter will happily destroy it. The fix
   is to reap on a dead owner unconditionally, and to apply the age check **only** when the pid is
   missing or unreadable. Until it is fixed, refresh live locks periodically:
   `for d in "$TMPDIR"/paintapp-simlock/*; do o=$(cat "$d/pid"); kill -0 "$o" 2>/dev/null && touch "$d"; done`
2. **It does not bound the queue.** Seven runs were queued against two devices at once, all
   legitimate. The lock correctly prevented a third simulator from booting, but nothing stops workers
   from *queuing* faster than devices drain, and a worker that queues three runs (Debug triple,
   Release triple, single repro) blocks two others for an hour. Prefer one narrow run per worker;
   compare configurations on a **single test**, never on three whole suites.

**Do not dispatch a second worker into a worktree that already has one**, even if the first has gone
quiet. A worker blocked on a background run reports as finished and is still live — two of them
committed into the same index seven seconds apart on 2026-08-14. Earlier handoffs warned about
*resuming* a stalled worker blind; the sharper rule is that a stalled worker still **owns its
worktree** until it reports for real. One worktree, one worker.

**Workers run only the suites their own change touches.** The full suite runs **once**, at the
boundary, on a quiet machine, by a dedicated worker. Telling six workers to run the ~750-case fast
tier is what saturated the machine; the owner called this out directly.

**Verify numbers, never summaries.** Read `totalTestCount` from the xcresult yourself. This project
has now shipped **four** distinct instances of the same hazard — a fabricated measurement table, a
parity sweep comparing the wrong two things, an empty `-destination` reading as success, and a
handoff's filtered failure list — every one of which passed every check that looked at exit codes,
banners, or prose.

**Workers stall waiting on background runs.** Do not resume blind — `git -C <worktree> log`/`status`,
read the newest xcresult, `ps aux | grep xcodebuild`, *then* instruct. An in-progress `.xcresult` has
no `Info.plist` and `xcresulttool` errors on it; that means running, not corrupt. A mid-iteration
failure count is not a finding.

**Commit before every test run.** An interrupted agent loses uncommitted work and nothing else.

## What is left

| # | work | state |
|---|---|---|
| **LIVE** | live stroke invisible mid-gesture | **fixed at `309a573`; regression test never executed** |
| **8** | the 16-test regression | **fixed** (`c1d23dc`, `83bd747`); last 2 pending an isolated run |
| **9a** | effect as a stack layer | **DONE, `tmp/p9-layer`, 222/222 in Release** |
| **§10.1** | mask constants | **baked 0.1 / 0.01 on `tmp/p8-slotmode`**; §6.3 rewritten |
| **6.5b** | mask/fill-reference panel rework | in flight on `tmp/mask-ui`, spec below |
| **9b** | effect **as a 1-input node** (§4.4) | not started — the seam is described below |
| **9c** | Sobel, Sharpen/unsharp, Outline (§7) | not started; wants the multi-pass work |
| **blur/bloom** | `tmp/p9-multipass` | tests rescued and rewritten; counts pending |
| **§10.2** | which node ops take 2+ inputs beyond Mix | unblocked; a starting position is below |
| **MERGE** | nothing since phase 7 is on `main` | seven branches to converge — see below |

**9b is small and its seam is already cut.** `RenderNode.effect` is **one field for both §4.4
wrappers**, because the wrapper is the *position in the tree*, not the data. 9b is therefore:
`LayerFolder.effect` in storage, one `decodeIfPresent`, and one grade/mix call after `fold` in each
backend. Nothing else branches on which wrapper produced the input — keep it that way.

**What 9a established that 9b and 9c inherit:**
- **An effect leaf derives with `blendMode: .normal`** — a grade *replaces* its backdrop, so there are
  not two things to compose. (That is exactly what the node form gives you instead.)
- **`compositeEffectMix` is not source-over, deliberately.** An effect preserves alpha, so compositing
  the graded texture over its own backdrop would inflate coverage to `2a − a²` and thicken every
  antialiased edge. Opacity and mask coverage go in as one `amount` to a `mix`.
- **Effect scoping *is* isolation, not a new concept.** `enclosesABlend` counts `effect != nil`;
  without it, an isolated group of all-normal children plus one effect declines a buffer and the grade
  escapes to the outer backdrop. Pass-through deliberately lets it out. Both directions are pinned.
- **`renderSources` elides `.compositing` layers**, so there is no canvas-sized transparent rasterize
  per frame.

**One open UI decision, currently unreachable so not urgent.** `addEffectLayer` makes the new layer
active, matching `addLayer`/`addVectorLayer` — but drawing onto an active effect layer would go into a
cel nothing renders, i.e. ink would silently vanish. There is no UI to create one yet. When phase 9's
picker ships, decide it then; the sane default is to *select* it (so its properties are editable) while
making a draw gesture on it either a no-op with feedback or a redirect to the nearest drawable layer.
Ask the owner rather than guessing — it is a taste call, not an engine one.

## The live-stroke bug — ROOT-CAUSED and fixed at `309a573`, but not yet verified

The owner reported **ink does not appear while drawing** on the iPad. Found by *reading the call
graph*, not by running tests — the 22-minute suite was never going to point at this.

`updateSandwich(tree:engaged:)` (`CanvasView.swift:741`) is the **only** thing that unblanks the
active layer's host (`host.setBlanked(!drawsItself)`, :811). Its only callers are `reconcileLayers()`
(:603) and `finishSandwichRebuild` (:981), and `reconcileLayers()` is called only from `makeUIView`
(:234) and `updateUIView` (:247). **So the mid-stroke picture can only appear during a SwiftUI pass.**
`sandwichStrokeBegan` (:732) sets `isSandwichStrokeLive = true` and stops; nothing applies it. And a
stroke's first touch publishes nothing — `commitInteractiveFill`/`commitInteractiveShape` guard-return,
`interactionBegan` is guarded, `startShapeDetection` touches no `@Published`.

Net effect: **the first stroke on a frame draws, because the cel spawn publishes and buys a pass.
Every stroke after that on the same cel does not**, and the host stays blanked for the whole gesture.

The author had already reasoned this out one line away and applied it only to the mask —
`liveMaskStrokeBegan`'s comment (:851) says the mask is installed at touch-down "because there may not
be one: a dab publishes nothing, so the pass that would install it is the pass this stroke is
deliberately not causing." Blanking needed identical treatment and never got it.

**Latent since 5b (`389876b`), made reachable by 6a (`46a8cf6`)** — the `!node.masks.isEmpty` clause in
`needsCompositorOnCanvas` (`RenderTree.swift:368`) means *any masked document* now engages the
sandwich, where before only a blend mode or a faded/isolated group did. Release was a coincidence of
the same deploy, not a cause; it reproduces in Debug.

Both rival hypotheses were closed by construction rather than left dangling: every `.mask` write was
audited (`blankingMask` is one layer per host; `contentMasks` produces three distinct layers zipped
1:1 — no sharing, so no ownership collision), and the off-main rebuild's two caches
(`MaskResolver.MaskCache`, `PixelOps.rasterizeCache`) are `NSLock`-guarded with `ResolvedMask`
immutable.

**Still to do:** `testInkIsVisibleWhileTheSecondStrokeIsStillDown` (in `LayerUITests.swift`, registered)
is the regression test and **has never been executed**. It was written by someone who could not run
it, so a first-run failure is as likely to be the test as the fix. It probes with the touch still
down, which nothing else in the suite does — every other sandwich assertion samples after lift, where
`full` contains the stroke and the picture is right either way. Two traps it already dodges:
`thenHoldForDuration` is unusable because holding still 0.8 s fires `fireShapeDetection`, which
*reverts the stroke being probed*; and it settles the 400 ms thumbnail-regen debounce first, because
that publish would otherwise supply the very SwiftUI pass whose absence is the subject.

## §6.5 rework, specified by the owner 2026-08-14 — not yet built

The owner's judgement: the mask features are "all dumped in the edit menu" and the **Mask switch is
redundant**. Replace it with per-row controls:

- **Opening a layer's edit menu enters the mask-edit session for that layer.** The switch that used
  to enter it goes away; the edit menu already names the target, which is what made the switch
  redundant.
- **Keep the modal session and all of §6.5's protections** — the owner confirmed this explicitly.
  Illegal sources still filter through the same `canMask` cycle rule derivation uses (never a second
  copy), structural edits (swipe delete/duplicate, long-press reorder, pinch-merge) are still refused
  for the duration, and every mask edit still coalesces into **one** undo step via
  `beginMaskEdit`/`endMaskEdit`. Dropping the session would make each checkmark its own undo step;
  that is a regression, not a simplification.
- **Each layer row gains a "mask this layer" checkmark** while the edit menu is open.
- **A fill-reference button sits immediately beside it**, same treatment. It **defaults to ON**, and
  **defaults to OFF when the layer is hidden** — but the owner's exact words are that *"the user can
  change these at any moment"*, so these govern the automatic value only. **An explicit user choice
  always wins and must never be silently overridden**, including on a hidden layer. Note this is a
  change from today: §6.6 records that hiding a layer *clears* `isFillReference` outright.

## The mask constants, and the reasoning they overturned

Shipping values are now **`threshold` 0.1** and **`antialiasHalfWidth` 0.01**, chosen by eye on the
iPad against a soft brush, in Release. They replace 0.5/0.05, which were a reasoned guess.

**§6.3's stated rationale was wrong and has been corrected rather than left standing.** It argued that
`alpha > 0` "would make the mask substantially larger than the stroke looks" and that ~0.5 "tracks the
visually solid part of a stroke". 0.1 is close to `> 0`, so on real hardware the owner wanted the mask
to track nearly the whole soft dab, not its solid core. The structure of the argument survives (a
threshold rather than the source's own alpha ramp; a narrow smoothstep so a hard boolean edge does not
stair-step on diagonals); the specific claim about where 0.5 sits did not.

**The harness is still installed** (`MaskTuningOverlay`, the two `var`s, `tuningGeneration`) because
the owner may re-judge after the live-stroke bug is fixed — their tuning was done on a build where
they could not see strokes live. Delete it once they confirm; it is a clean revert, and
`AlphaMask.swift`'s MASK-TUNE comments name every piece.

**§4.4 is the whole of 9a/9b and it is smaller than it looks:** both wrappers are one shader; *only
the input-resolution rule differs* — "the accumulated backdrop so far in this container" versus "this
slot's composite." Both hand the same texture to the same kernel. Nothing else branches on which
wrapper was used. Container scoping is what keeps the layer form predictable.

**A starting position on §10.2, not yet tested against the UI.** Because `Mix(A,B,mode)` is measured
to equal stacking B over A with that mode (delta 0, all 25 modes), *every blend mode is already a
2-input op*, and per-slot opacity/blend/mask covers crossfade and weighting. So the honest answer may
be that almost nothing new is needed: what is genuinely missing is (a) variadic arity as ergonomics —
a variadic Add over N slots is a chain of `Mix(.add)` and buys only the absence of nesting — and (b) a
true matte/key op that consumes B as *coverage* rather than as colour, which no blend mode expresses.
Try it against the real node UI before committing to it.

## The iPad judgements

The owner has the full protocol and the hardware. **Do not re-explain it; ask whether they have run
it.** Build Release (`-configuration Release` — the scheme's LaunchAction is Debug, so a plain
`xcodebuild build -scheme PaintSoftware` ships `-Onone` to the device, and the mask path costs 62×
there) from the worktree; `deploy.sh` pulls `main` and never ships branch work. **Do not install to
the device yourself** — hand the owner the `devicectl` command with the device UUID
`E3B83820-DF74-5042-B52B-0D5BA17E4877`, never the device name.

1. **§10.1 mask constants.** `tmp/mask-tune` ships live sliders for `AlphaMask.threshold` (0.5) and
   `antialiasHalfWidth` (0.05); the overlay is open by default at launch. Moving a slider invalidates
   the mask cache but does not repaint drawn content — a fresh soft-brush stroke is needed to see it.
   Wanted back: two numbers. If nothing in range feels right, that is the *more* valuable answer — it
   means §6.3's binary-with-threshold decision needs revisiting, not the constants. **Delete the
   harness when the numbers are baked** (`MaskTuningOverlay.swift` plus the `var`s; a clean revert).
2. **The mid-stroke approximation**, below.

## Phase 8's finding, which the owner has seen and has not ruled on

**The sandwich degrades through a blending Mix**, measured and pinned:
`SandwichLogicTests.testTheSandwichThroughABlendingMixIsNotExactAndTheDeltaIsMeasured` asserts
`["the active leaf in slot 0": 127, "the active leaf in slot 1": 255]`; the `.normal` companion
asserts exactly 0. **255 means the mid-stroke pixel bears no relation to the final one.**

The cause is structural, not a bug: a fold applies its mode *once*, between two finished slots, so a
cut inside a slot puts its pieces on opposite sides of the live layer and neither half can fold
against the operand the whole document folds against. Same class as the three pre-existing 127 cases,
and it snaps correct on lift. **Do not build the fix unprompted** — the owner chose to judge it on the
iPad. If they ask: add `backdrop: CGImage?` to `RenderRequest` honoured by both backends, composite
the above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from the same stack
over transparency, emit `αs = c`, `Cs = (R − B(1−c))/c`. Cost is another composite per stroke in the
latency-critical path.

## Two things carried forward as UNPROVEN — check these before you trust them

- **`912d692` on `tmp/p8-slotmode` is unverified.** It makes a slot's blend-mode inertness the
  derivation's contract — `blendMode: folder.isInputSlot ? .normal : folder.blendMode.compositedMode`
  at `RenderTree.swift:546`. For every non-slot folder the false branch is textually identical to what
  it replaced, and a slot reachable through the UI always stores `.normal`, so both are no-ops. The
  case that is *not* a no-op: a slot with a genuinely non-normal stored mode (reachable only via a
  direct `setFolderBlendMode`, an undo of one, or a legacy document) also loses a buffer pass, because
  `needsOwnBuffer` keys on `blendMode.isBlending` (`RenderTree.swift:211`). Removing a buffer pass can
  in principle change bytes. The author's argument that it cannot here — the pass is a composite onto
  pure transparency, the same lossless copy §4.3's Mix correction established — is sound *inference
  from a pre-fix run*, not an observation. **`testASlotsOwnBlendModeIsInertButItsOpacityStillFades`
  must be seen green after the fix.** It runs inside the boundary suite, so the proof is free; just do
  not merge on the pre-fix green.
- **A green backend-parity test here does not prove both backends ran.** These tests append Metal only
  `if CompositorMetalEngine.shared != nil`, and `xcresulttool get test-results activities` on the run
  showed only Start/Set Up/Tear Down — no console log, no activity naming the backend. So a pass is
  equally consistent with CoreGraphics-only execution. This is the *same hazard* as the parity sweep
  that compared the wrong two things, wearing a different disguise: the test is honest, but its green
  under-determines what it exercised. Fix is cheap and should be done once, generally — an
  `XCTContext.runActivity` recording the exercised backend(s) per iteration.

## What phases 8 and 9 established — do not re-litigate

- **`Mix(A,B,mode)` equals stacking B over A with that mode, exactly — delta 0, all 25 modes, both
  backends.** Expected to be 1; it is 0 because the extra slot buffer is a copy onto transparency,
  lossless in premultiplied 8-bit. **No new kernel was needed and none should be added.**
- **Slot 0 is the backdrop and is the lowest row.** Each slot derives as its own `RenderNode`, which
  is what makes "always isolated" expressible and lets a slot keep its own opacity/blend/mask.
- **Splitting a `.fixed(2)` Mix yields a one-slot Mix** — a shape its own arity says cannot exist.
  Both backends render it correctly, but **no validator may assume arity holds for a sandwich half.**
- **§4.3's "no new tree arithmetic" is optimistic in three places.** Undeletable slots, contiguity,
  and *ordering*: the panel's "an empty folder sorts above everything" rule floats an empty Input A
  above a filled Input B and **silently inverts which slot is the backdrop**. Fixed by ranking an
  unfilled slot by its index. Do not undo it.
- **Slot rows refuse reordering** — deliberate; otherwise the stored index and the displayed order are
  two answers to one question. Operands are reordered by moving what is *inside* the slots.
- **The effect abstraction: one `Effect` enum, and neither backend switches on it.** Both consume a
  `kindCode`, a flat all-scalar `params` block, and a 256-entry `lookupTable`; interpretation happens
  once, in Swift. Params are all-scalar **deliberately** — a `float2`'s Metal alignment matches
  `SIMD2<Float>` only by luck, and a padding disagreement shifts every later field *without failing to
  compile*. Verified field-for-field at 17 fields / 68 bytes. **Both wrappers consume this unchanged.**
- **That abstraction's blind spot, and it now extends to `passes` and `weights`:** because both
  backends consume the *same* Swift-resolved values, **a parity sweep cannot catch a mistake in the
  resolution — both sides make it identically and the sweep passes green.** A same-author
  re-derivation of the formula in the test is *not* an independent check either. The defences that
  actually work here are an impulse-response test (blur a single white pixel: the output *is* the
  kernel, checkable against mathematics), separable-vs-direct-2D convolution, hand-computed numeric
  spot checks, and an independent transcription. Any new effect inherits the blind spot and owes the
  same defence.
- **Apple's four non-separable blend modes are still unmeasured against the spec.**
  `coreGraphicsBlendMode` returns `nil` for hue/saturation/color/luminosity, so phase 7's sweep
  compared our shader against our Swift. The open experiment: if Apple's agree, they take a faster path.
- **Backend agreement is not one number.** `.normal` and masks are exactly 0; blend modes hold to a
  measured ≤1 channel step; effects to a measured ≤1, with `gradientMap`'s 1 a bound **on a
  black-to-white ramp only** (it indexes by a dot product, which fast math may contract).
- **`RenderNode.masks` is a list**, applied in sequence as a product of coverages. **"Clip to below"
  never reaches a backend as a mode** — derivation turns it into `.normal` plus a mask. Adding a
  shader case for it is wrong.

## Gotchas that each cost a cycle — put these in every worker prompt

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Read `totalTestCount`, never the
  banner. Build `-only-testing` flags into a shell **array** and pass `"${SUITES[@]}"` — zsh does not
  word-split an unquoted `$VAR`, and one long bogus argument is ignored while reporting success.
- **A new test file needs a `project.pbxproj` edit** — `PaintSoftwareUITests` opts out of
  `PBXFileSystemSynchronizedRootGroup` and hand-lists its sources, so an unregistered file compiles
  nowhere, runs nothing, and prints green. App sources under `PaintSoftware/` are synchronized.
- **A test's stdout does not reach the build log from the runner app.** Put measurements in an
  `XCTContext` activity or they are unreadable afterwards.
- **Never report a perf number from a Debug build** — 62× and 440× ratios measured here. The test
  target compiles under `-configuration Release`; measure there rather than extracting loops.
- **Do not add a heavy case to the fast tier** — a ~400 MB case pushed an unrelated suite's case from
  0.073 s to 8.98 s, surfacing nowhere near its cause. Gate heavy ones behind `PAINT_PERF_HEAVY`.
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, boot, re-run the single
  test. Never re-run the 22-minute suite to decide whether a failure was real.
- **`uptime` is meaningless on this Mac** — its load average read 404 with zero booted simulators and
  94.6% idle CPU. Use `top -l 2 -n 0 -s 2 | grep "CPU usage" | tail -1`.
- A host-side `swiftc` harness runs the effect CPU reference with no simulator in ~5 s a loop.
- **Forbid workers from running `graphify update` on a feature branch** — a 300-line GRAPH_REPORT diff
  conflicts against every other branch in flight.

## At each phase boundary

Delegate these. Full XCUITest suite after the lock's erase/boot, and **say plainly if you skip it
rather than implying it passed**. Prune the shipped sections of LAYER_COMPOSITING.md — prune what is
done rather than appending status. **Delete `PHASE8_SURVEY.md` when phase 8 merges**; it is a working
document. Append the one-line SESSION_LOG.md entry and drop the oldest so only five remain. Refresh
the graphify report and commit it. Merge to `main` after the suite. Match the codebase's comment
density: it explains why, never what.

**Before you run out of context, write the next session's prompt to `nextprompt.md` and commit it** —
addressed to an Orchestrator, covering whatever is genuinely left, including what you learned that
would otherwise be rediscovered and this same instruction. Keep it about this long, and write it
*early*; a handoff written while you still have room is worth more than a complete one you never get
to write. **And land it where the next session will actually look** — on `main` if you merge, and on
the most advanced branch otherwise, because the copy in a fresh worktree is the one that lies.
