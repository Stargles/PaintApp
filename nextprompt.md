# You are the Orchestrator for the rest of the layer-compositing project

Not for one phase. **Phase 6b, phases 8 and 9, and what is left of §10 are yours**, and you carry the
project until they are done or the owner redirects you. Read LAYER_COMPOSITING.md — the agreed design,
settled with the product owner. §11 is the build order; phases 0 through 7 are done, committed, green
and **merged to `main`**.

## Read this first

**Your context is the scarce resource, and it is spent by doing rather than by deciding.** Keep for
yourself: design decisions, scope calls, what to ask the owner, **verifying a worker's numbers**, and
deciding what happens next. Everything else goes to a worker — test runs, docs prunes, session-log
entries, graphify refreshes, conflict resolution. Ask the owner when two readings of a phase would
produce materially different work; do not ask about what §6–§9 already settle.

Delegation limits: **at most 2 sonnet + 1 opus at any one moment.** Opus for design-bearing work (node
graph, multi-pass effects, conflict resolution); sonnet for measurement, docs, mechanical registration.
**Branch a worker's worktree from the phase tip, not `origin/main`.**

**Verify numbers, never summaries.** Read `totalTestCount` from `xcresulttool` yourself — a worker
this session drafted a "measured" delta table into doc comments *before running the sweep*, caught it
itself, and rewrote it. The one before recorded a fabricated table that shipped; the truth was 70×
larger and was a real bug. The habit that catches this is cheap: read the worktree's xcresult yourself
rather than the prose.

**Workers stop while waiting on a background test run.** Three notifications this session were "standing
by for the run to complete" with nothing attached. Do not resume them blind — `git -C <worktree> log`
and `status`, read the newest xcresult, check `ps aux | grep xcodebuild`, *then* send instructions.
Twice the answer was already on disk and the round-trip was unnecessary.

## State

Phases 6a and 7 landed together. Fast tier **754/754** (718 baseline + 32 masks + 4 Tier 2), full
XCUITest suite **836: 834 passed, 1 failed, 1 skipped**. The skip is the FillUITests case already in
BUGS.md and is expected; no new skips. `Compositor.backend` is `.coreGraphics`.

**The one failure was environmental, and it is worth knowing which one.**
`LayerUITests.testTheBlendedCanvasComesBackInSyncAfterLayerSwitchVisibilityToggleAndUndo` failed in
the suite and then passed **three times out of three** in isolation on a freshly erased and booted
simulator. That clears CLAUDE.md's triage bar twice over — but note it sits **inside phases 5b/6a/7's
blast radius**, which is why it got three runs instead of the usual one: a genuine intermittent race
in the sandwich would look exactly like environmental noise at one sample. If you see it fail again,
it has now failed twice across sessions and deserves real suspicion rather than a fourth re-run.

**`main` is current.** The owner chose merge-now-then-per-phase; `origin/main` was fast-forwarded this
session and the branch is no longer a large unmerged pile. Keep that cadence: boundary suite, then
merge, one phase at a time.

**Do not trust the local `main` *checkout*.** `/Users/juliapark/Desktop/Kevin.P/PaintSoftware` sits far
behind with ~48 files of vector-interpolation work **staged but uncommitted** — content already merged
upstream, so it is a dead index another session abandoned. A previous handoff read that stale ref and
reported `main` as 27 commits behind when it was not. Read `origin/main`, never the local checkout.
Clearing it needs the owner's say-so.

## What is left

| # | work | done when |
|---|---|---|
| **6b** | Mask UI (§6.5) + live stroke feedback (§6.4) | mask-edit mode ships; ink clips live, not on lift |
| **8** | Compositor nodes: slot-as-folder storage, panel chrome (§4.3) | a 2-input Mix node renders |
| **9** | Tier 3 effects, as layer *and* node (§4.4, §7) | cheap per-pixel set first, then multi-pass |

**§10 is nearly closed.** Item 3 (pass-through shipping before it did anything) is **resolved** — phase
5 landed, the toggle changes pixels now. Item 1's "Clip to below" **shipped in 6a**. What remains of
item 1 is only tuning `AlphaMask.threshold` (0.5) and `AlphaMask.antialiasHalfWidth` (0.05), both in
`Models/AlphaMask.swift` feeding one function, `coverage(forSourceAlpha:)` — tune once 6b gives
something to look at. Item 2 (which node ops take 2+ inputs) still wants phase 8's UI first.

## Phase 6b — the seam is already built, do not rebuild it

- **`ResolvedMask.makeMaskImage()`** returns an RGBA image whose alpha is the coverage, ready for
  `CALayer.mask`. It is a **method, not a lazy property, deliberately**: one `ResolvedMask` is shared
  by every layer using it and is read from the sandwich's off-main rebuild, so a stored property filled
  on first access races the moment 6b becomes the second caller. Do not "optimise" it into one.
- **`layer.mask` is taken on `LayerHostView`.** Phase 5b's blanking installs a contentless `CALayer`
  there, because `isHidden` and `alpha` both make `hitTest` return nil and a blanked *active* host
  would swallow the first touch of every stroke. §6.4's mask goes on **`host.strokeView`**, a different
  layer. Move it up to the host and either blanking eats the mask or the mask eats blanking, depending
  on order — and it fails **silently**.
- Model API for the panel: `CanvasManager.setAlphaMask(_:forLayer:)` / `(_:forFolder:)`, one undo step
  each. §6.6 wants one step per mask-edit *session*, so bracket with
  `beginStructureGesture`/`commitStructureGesture` — they nest the way the opacity slider already does.
- The picker must not offer a cycle: call **`CanvasManager.canMask(_:with:)`**, the same reachability
  walk the derivation already filters with, rather than writing a second rule.
- **Unmeasured and worth measuring first:** `MaskResolver.apply` is a per-pixel CPU pass per masked
  node per composite (fully-covered and fully-clear pixels short-circuit). Invisible at 64²; nobody has
  run it at 2048². Phase 5b measured three composites at ~55 ms there, so if a sandwich rebuild
  regresses, this is the first place to look.

## What phases 6a and 7 established that you should not re-litigate

- **Masks agree between backends at delta 0, by construction.** §6.3's threshold is a step function, so
  the one channel step blend modes are allowed would land on opposite sides of it. `MaskResolver`
  therefore resolves through the **CoreGraphics reference whichever backend asked**, and the GPU only
  multiplies. Keep that shape for anything else with a hard edge.
- **`RenderNode.masks` is a list.** A layer that both carries a mask and clips to below carries two,
  applied in sequence — a product of coverages, so they intersect. No precedence rule needed.
- **"Clip to below" never reaches a backend as a mode.** Derivation turns it into `.normal` plus a mask
  whose source is the entry beneath. No shader case, no `CGBlendMode`. If you find yourself adding one,
  that is wrong.
- **`maskStacks` is built from the whole tree, never from `tree`.** A sandwich half is pruned, so a
  masked layer in `below` can be clipped by a source living in `above`; all three requests share one
  map. Visibility is forced on throughout each source stack, including inside a hidden group.
- **The cache key is phase 5b's, lifted not duplicated.** `LayerContentVersion` now lives in
  `RenderRequest.swift`; the request carries `contentVersions` and both the sandwich and the mask cache
  read it. Its trap is pinned by a test: a cel id outlives the buffers under it, so reopening a project
  rebuilds every `RasterLayerTexture` at counter 0 under the same id, and a version-only key serves
  pre-edit pixels.
- **Apple's non-separable modes are still unmeasured — do not repeat the claim that they agree.**
  Phase 7 reported that they agree with W3C within a rounding step, and that was wrong about what its
  own number measured. `coreGraphicsBlendMode` returns `nil` for `.hue`/`.saturation`/`.color`/
  `.luminosity`, so the CPU hand-rolls all four; the sweep therefore compared **the app's own W3C
  shader against the app's own W3C Swift**, and the deltas (hue 1, saturation 0, color 1, luminosity
  1) are float rounding between our two paths. Only `.exclusion` rides a `CGBlendMode` primitive, and
  only its 0 is a real CoreGraphics-vs-spec number. Tier 1's 141/249/16 *is* a genuine measurement and
  stays. **The open experiment:** if Apple's four do agree, they could take a faster path — measure
  before assuming either way. The lesson generalises: **a green parity sweep proves the two things it
  compared are equal, which is not always the two things the comment says it compared.**
- Six Tier 2 modes are hand-rolled **for absence from `CGBlendMode`**; the four HSL ones are
  hand-rolled **by choice pending that measurement**. The real Tier 2 trap was CPU-side and structural:
  `handRolledChannel`'s per-channel signature cannot express a non-separable mode, so the CPU path
  needed `handRolledTriple` and a per-pixel dispatch. Metal needed nothing — `blendChannels` already
  took a `float3`.
- **Backend agreement is not one number.** `.normal` is asserted at exactly 0 and must stay there;
  blend modes hold to a measured ≤1 channel step. §11's "delta 0" is true of the *walk*, not of blends.

## Open bug, deliberately not fixed

**`duplicateLayer` drops `blendMode`** — phase 5a's gap — **and now `alphaMask` with it.** Phase 6a
left it rather than smuggle a phase-5 behaviour change into a phase-6 diff. It is a one-line-ish fix
plus a test; do it in its own commit, not folded into a phase.

## Gotchas that each cost a cycle — put these in every worker prompt

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Build `-only-testing` flags into a
  shell *array* and pass `"${SUITES[@]}"` — zsh does not word-split an unquoted `$VAR`. Read
  `totalTestCount` from `xcresulttool`, never the banner. CLAUDE.md has the recipe.
- **A new test file needs a `project.pbxproj` edit** — `PaintSoftwareUITests` opts out of
  `PBXFileSystemSynchronizedRootGroup` and hand-lists its sources, so an unregistered file compiles
  nowhere, runs nothing, and still prints green.
- **Two simulators exist so two workers can run at once**: `eraser-mutex-test`
  (`75C8B97E-47AF-484B-B7D2-CA7EB1B51B03`) and `layer-phase0-ipad`
  (`E7576E92-8EB7-489B-962B-6A2E61852EC0`). Pin each worker to one **by UDID**, and forbid
  `simctl shutdown all` while another worker is running — it kills the other's run. `-destination
  name=...` for a device this Mac lacks does not error; it silently falls back.
- **After `simctl erase` you must `boot`**, or the runner fails behind a wall of
  `FBSOpenApplicationServiceErrorDomain` meaning only "nothing is booted".
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, boot, re-run the single
  test; a clean pass confirms environmental. Never re-run the 22-minute suite to decide.
- **Do not add a heavy case to the fast tier.** A phase-4 case allocating ~400 MB pushed
  `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` from 0.073 s to 8.98 s, and
  the failure surfaces in an unrelated suite looking nothing like its cause.

## Deliberately cut, with the answer worked out

Mid-stroke, layers above the active one render as Normal and snap on lift. **The owner was asked this
session and chose to leave it and judge it on the iPad first** — do not build it unprompted, and do not
re-ask unless they raise it. If they do: add `backdrop: CGImage?` to `RenderRequest` honoured by both
backends, composite the above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from
the same stack over transparency, emit `αs = c`, `Cs = (R − B(1−c))/c`.

## At each phase boundary

Delegate these; do not do them yourself. Full XCUITest suite after `simctl shutdown all` + `erase` +
`boot`, and say plainly if you skip it rather than implying it passed. Prune the shipped sections of
LAYER_COMPOSITING.md — prune what is done rather than appending status. Append the one-line
SESSION_LOG.md entry and drop the oldest so only five remain. Refresh the graphify report and commit
it. Merge to `main` after the suite, per the owner's cadence. Match the codebase's comment density: it
explains why, never what.

**Before you run out of context, write the next session's prompt to `nextprompt.md` and commit it** —
addressed to an Orchestrator, covering whatever is genuinely left, including what you learned that
would otherwise be rediscovered and this same instruction. Keep it about this long, and write it
*early*; a handoff written while you still have room is worth more than a complete one you never get
to write.
