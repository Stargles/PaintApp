# You are the Orchestrator for the rest of the layer-compositing project

Not for one phase. **Phases 8 and 9, what is left of §10, and the iPad Release-build fix are yours**,
and you carry the project until they are done or the owner redirects you. Read LAYER_COMPOSITING.md —
the agreed design, settled with the product owner. §11 is the build order.

## Start here, because the tree may not be where you would guess

**Check `origin/main` first, and check `tmp/integrate-6b` (worktree
`/Users/juliapark/Desktop/Kevin.P/PaintApp-integrate`) second.** Phase 6b — the mask UI, the live
stroke clip, the `duplicateLayer` fix, the docs prune — is complete and committed on that branch. It
merges to `main` once the full suite is green; if `origin/main` already has it, that landed and this
paragraph is history. If it does not, **finishing 6b's boundary is your first job, not phase 8**:
full suite, SESSION_LOG line, graphify refresh, merge.

Full-suite baseline to beat is **836: 834 passed, 1 failed, 1 skipped** at `dbbaabc`. Expect **two**
skips now — the `FillUITests` one in BUGS.md, plus the `PAINT_PERF_HEAVY`-gated
`testMaskedCompositeCostAtCanvasResolution` 6b added. Fast tier was 757/765 at the 6b worker tips.

If `LayerUITests.testTheBlendedCanvasComesBackInSyncAfterLayerSwitchVisibilityToggleAndUndo` fails,
know that it failed once in a suite before and passed three of three in isolation. It sits inside
5b/6a/7's blast radius. A second suite failure makes it a real suspect, not a fourth re-run.

## Read this first

**Your context is the scarce resource, and it is spent by doing rather than by deciding.** Keep for
yourself: design decisions, scope calls, what to ask the owner, **verifying a worker's numbers**, and
deciding what happens next. Everything else goes to a worker — test runs, docs prunes, session-log
entries, graphify refreshes, conflict resolution. Ask the owner when two readings of a phase would
produce materially different work; do not ask about what §6–§9 already settle.

Delegation limits: **at most 2 sonnet + 1 opus at any one moment.** Opus for design-bearing work
(node graph, multi-pass effects, conflict resolution); sonnet for measurement, docs, mechanical
registration. **Branch a worker's worktree from the phase tip, not `origin/main`** — last session is
the proof, since `origin/main` sat at `dbbaabc` while all of 6b lived on a branch.

**Verify numbers, never summaries.** Read `totalTestCount` from `xcresulttool` yourself. Two sessions
ago a worker recorded a fabricated "measured" table that shipped; the truth was 70× larger and was a
real bug. Reading the worktree's xcresult yourself is cheap and catches it.

**Workers stop while waiting on a background test run.** Do not resume them blind — `git -C
<worktree> log` and `status`, read the newest xcresult, `ps aux | grep xcodebuild`, *then* send
instructions. An in-progress `.xcresult` has no `Info.plist` and `xcresulttool` errors on it; that
means still running, not corrupt.

**A worker's test run is its child and dies when you stop the worker.** If you need to pause, let the
run finish first or accept losing it. Nothing else about a stopped worker is lost — worktree and
commits persist, so the cheap recovery is to re-launch a worker onto the same worktree.

## What is left

| # | work | done when |
|---|---|---|
| **8** | Compositor nodes: slot-as-folder storage, panel chrome (§4.3) | a 2-input Mix node renders |
| **9** | Tier 3 effects, as layer *and* node (§4.4, §7) | cheap per-pixel set first, then multi-pass |
| **§10.1** | Tune `AlphaMask.threshold` (0.5) / `antialiasHalfWidth` (0.05) | **unblocked, nobody has looked** — 6b gave it a UI. Judge on the iPad, soft brush |
| **iPad** | **Ship Release builds, not Debug** — owner-approved, never started | the deploy recipe passes `-configuration Release` |

§10 item 2 (which node ops take 2+ inputs) still wants phase 8's UI first.

**The Release-build task in full, because the owner approved it explicitly:** the scheme's
LaunchAction is Debug (`PaintSoftware.xcscheme:60`), which is what `xcodebuild build -scheme
PaintSoftware` ships to the device — so the iPad has run `-Onone` for this entire project, and §6.4's
mask path costs 62× there. Verify the app target compiles under `-configuration Release` against the
simulator first (no signing), then update CLAUDE.md's deploy recipe and any `deploy/` invocation.
**Leave the scheme's LaunchAction on Debug** — Xcode's Run should stay Debug for development; it is
the deploy command that changes. **Do not install to the device yourself.** The *test* target does
not compile in Release (BUGS.md has the entry, `ShapeDetectorLogicTests.swift:54`, a `largestGap`
`map`/`hypot` chain that wants splitting into annotated lets); if you fix it, delete the BUGS entry
in the same commit.

## Phase 8 — the survey is done, do not redo it

[PHASE8_SURVEY.md](PHASE8_SURVEY.md) is a 217-line file:line-cited map read against `dbbaabc`. It is
a **working document — delete it when phase 8 lands**, the way 6b's notes files were. Its three hard
parts, so you can scope without opening it:

1. **Both backends already loop over N slots — into one shared accumulator**, which is `.stack`
   semantics, not "combine N independent composites." For a real 2-input Mix, slot A is baked into
   the buffer before B is drawn, so "combine A and B" is never expressible. The fix is a **walk
   change, not a math change**: one buffer per slot instead of one shared, then one `over`/`draw`
   folding B onto A. §4.3 already says `Mix(A, B, .multiply)` *is* stacking B over A with multiply,
   and `compositeOver` already is that primitive — **no new kernel**. `needsOwnBuffer` and
   `enclosesABlend` already iterate `inputs` generically and need no change.
2. **Storage cannot say "this folder is a node" or "this folder is a slot."** `LayerFolder` has no
   role field, `FolderManifest` mirrors it 1:1 both directions, and `renderNodes(inContainer:)`
   hardcodes a single slot with a literal `op: .stack`. Delete and restack also have no concept of an
   undeletable child or contiguity-locked siblings.
3. **The layer-panel row model is binary** and cannot distinguish a node/slot folder from an ordinary
   one.

## What 6a/7/6b established that you should not re-litigate

- **Masks agree between backends at delta 0, by construction.** §6.3's threshold is a step function,
  so the one channel step blends are allowed would land on opposite sides of it. `MaskResolver`
  resolves through the **CoreGraphics reference whichever backend asked**; the GPU only multiplies.
  Keep that shape for anything else with a hard edge.
- **§6.4's live-vs-composite agreement is pinned as an *equality*, not a tolerance.** Both sides get
  back the *same `ResolvedMask` object*. Nested clips measured 0 difference against the expectation
  that double-quantization would show one. Two limits a later phase inherits: `RenderQuality` is in
  the mask cache key and the live path asks `.full`, so a §9.2 background renderer compositing at
  `.preview` would break the sharing; and the disengaged path carries no mask at all (pre-existing,
  reachable only through `isSandwichEngaged`'s escape hatches).
- **`CALayer.mask` takes ownership like a superlayer.** One mask layer assigned to three sublayers
  lands on the third and silently leaves two unmasked. Make one mask layer per target.
- **The mask image is canvas-space and needs no zoom compensation** — zoom is a transform on
  `containerView`, an *ancestor*, which scales a layer and its mask together. Checked, not hoped for.
- **`ResolvedMask.makeMaskImage()` is a method, not a lazy property, deliberately** — one instance is
  shared and is read from the sandwich's off-main rebuild. Do not "optimise" it into a stored one.
- **`layer.mask` on `LayerHostView` is taken** by 5b's blanking (which uses a contentless `CALayer`
  because `isHidden`/`alpha` make `hitTest` return nil and would swallow the first touch of every
  stroke). §6.4's mask goes on the host's **content sublayers**. A collision fails silently.
- **`RenderNode.masks` is a list.** A layer that both carries a mask and clips to below carries two,
  applied in sequence as a product of coverages. No precedence rule needed. **"Clip to below" never
  reaches a backend as a mode** — derivation turns it into `.normal` plus a mask. If you find
  yourself adding a shader case for it, that is wrong.
- **`maskStacks` is built from the whole tree, never from `tree`** — a sandwich half is pruned, so a
  masked layer in `below` can be clipped by a source in `above`; all three requests share one map.
- **Apple's four non-separable modes are still unmeasured.** `coreGraphicsBlendMode` returns `nil`
  for hue/saturation/color/luminosity, so phase 7's sweep compared **our own shader against our own
  Swift** — those deltas are float rounding between our two paths, not a CoreGraphics-vs-spec number.
  The open experiment: if Apple's four agree, they could take a faster path. **A green parity sweep
  proves the two things it compared are equal, which is not always the two things the comment says.**
- **Backend agreement is not one number.** `.normal` is asserted at exactly 0 and must stay there;
  blend modes hold to a measured ≤1 channel step.

## Measurement lessons that cost real time

- **Never report a raw perf number from a Debug build.** 6b's first mask figure was 1532 ms/node — a
  `-Onone` artifact. Extracting the loops and compiling them standalone at `-O` gave **62× and 440×
  Debug-to-Release ratios**; real cost is **~32 ms per clipped node per composite, ~7 ms to build a
  mask image**. What validated the extraction was that the `-Onone` build of it landed within 30% of
  what the test case reported — do that check, or the standalone harness measures something else.
- **`PerfBaselineTests`' timing assertions fail under concurrent-worker CPU load.** Twice in one
  session (`testCompositeCostGrowsRoughlyLinearlyWithLayerCount`, 14.6× against an expected <12×),
  passing in isolation both times. It is a property of the harness under parallel load. Do not run
  two workers' suites against a timing-sensitive tier at once.

## Gotchas that each cost a cycle — put these in every worker prompt

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Build `-only-testing` flags into a
  shell *array* and pass `"${SUITES[@]}"` — zsh does not word-split an unquoted `$VAR`. Read
  `totalTestCount`, never the banner. CLAUDE.md has the recipe.
- **A new test file needs a `project.pbxproj` edit** — `PaintSoftwareUITests` opts out of
  `PBXFileSystemSynchronizedRootGroup` and hand-lists sources, so an unregistered file compiles
  nowhere, runs nothing, and still prints green. The same holds for app sources the logic tests
  compile a second time, which is why 6b's session API went into the existing `CanvasManager.swift`
  rather than a new extension file.
- **Two simulators exist so two workers can run at once**: `eraser-mutex-test`
  (`75C8B97E-47AF-484B-B7D2-CA7EB1B51B03`) and `layer-phase0-ipad`
  (`E7576E92-8EB7-489B-962B-6A2E61852EC0`). Pin each worker **by UDID**, and forbid `simctl shutdown
  all` while another worker runs. `-destination name=...` for a device this Mac lacks does not error.
- **After `simctl erase` you must `boot`**, or the runner fails behind `FBSOpenApplicationServiceErrorDomain`.
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, boot, re-run the single
  test; a clean pass confirms environmental. Never re-run the 22-minute suite to decide.
- **Do not add a heavy case to the fast tier** — a ~400 MB phase-4 case pushed an unrelated suite's
  case from 0.073 s to 8.98 s, and the failure surfaced looking nothing like its cause.
- **Do not trust the local `main` checkout.** `/Users/juliapark/Desktop/Kevin.P/PaintSoftware` sits
  far behind with ~48 files of vector-interpolation work staged but uncommitted — a dead index
  another session abandoned. Read `origin/main`. Clearing it needs the owner's say-so.

## Deliberately cut, with the answer worked out

Mid-stroke, layers above the active one render as Normal and snap on lift. **The owner chose to leave
it and judge it on the iPad first** — do not build it unprompted, and do not re-ask unless they raise
it. If they do: add `backdrop: CGImage?` to `RenderRequest` honoured by both backends, composite the
above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from the same stack over
transparency, emit `αs = c`, `Cs = (R − B(1−c))/c`.

## At each phase boundary

Delegate these; do not do them yourself. Full XCUITest suite after `simctl shutdown all` + `erase` +
`boot`, and say plainly if you skip it rather than implying it passed. Prune the shipped sections of
LAYER_COMPOSITING.md — prune what is done rather than appending status. Append the one-line
SESSION_LOG.md entry and drop the oldest so only five remain. Refresh the graphify report and commit
it. Merge to `main` after the suite. Match the codebase's comment density: it explains why, never what.

**Before you run out of context, write the next session's prompt to `nextprompt.md` and commit it** —
addressed to an Orchestrator, covering whatever is genuinely left, including what you learned that
would otherwise be rediscovered and this same instruction. Keep it about this long, and write it
*early*; a handoff written while you still have room is worth more than a complete one you never get
to write.
