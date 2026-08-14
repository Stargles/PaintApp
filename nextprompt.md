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

**The phase-8 regression.** The boundary suite is 901 total: 883 passed, **16 failed**, 2 skipped
(the 2 skips are the expected `FillUITests` and `PAINT_PERF_HEAVY` ones). Baseline was 846 with 1.
**16 is real — do not triage it away.**

**And do not inherit the previous session's diagnosis of it.** It described the 16 as "one cluster in
the layer panel" and listed 12 of them. The xcresult's own list includes
`ToolsAndSelectionUITests/testColorPanelControlsChangeBrushColorAndPaintedStroke` (a hue-slider drag)
and `TimelineAndUndoUITests/testInterpolateModeEndToEndFromGestureToScrub` (a canvas gesture sweep),
neither of which is in the layer panel. What all 16 share is that **a drag gesture does not land**.
**Generalise this: a summary of a test run can be filtered to fit its author's hypothesis. Re-read the
raw `xcresulttool` failure list, never the prose.** The competing hypotheses were (A) phase 8's
widening of `LayerRowModel.isFolder: Bool` into `kind: Kind` and its three affordance gates, versus
(B) something global — a gesture-recognizer conflict, a moved shared drag helper, or a composite
slowdown making timing-sensitive drags miss their window.

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

| # | work | done when |
|---|---|---|
| **8** | unblock the drag regression, then merge | boundary suite back to ~901 with 0 real failures |
| **9a** | effect **as a stack layer** (`LayerKind.compositing`, §4.4) | an adjustment layer grades what is below it in its container |
| **9b** | effect **as a 1-input node** (§4.4) | the same shader grades only what is in its slot |
| **9c** | Sobel, Sharpen/unsharp, Outline (§7) | wants the multi-pass infrastructure |
| **§10.1** | bake the mask constants the owner picks | awaiting the owner's two numbers |
| **§10.2** | which node ops take 2+ inputs beyond Mix | unblocked once phase 8's UI works |

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
