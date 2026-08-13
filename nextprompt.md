Read LAYER_COMPOSITING.md first — the agreed design, settled with the product owner. §11 is the build
order. **Phases 0 through 5b are done, committed and green.** You are doing **phase 6: alpha masks
(§6)**, which is now the only thing between this project and "Clip to below" — §7 lists that in Tier
1 while admitting it is not a blend but the mask machinery with an implicit source, and phase 5a
deliberately shipped fourteen Tier 1 modes rather than fifteen because of it.

You are the orchestrator. Delegate to worker sessions and pick the model per task, but **at most
2 sonnet + 1 opus at any one moment**. Sessions keep dying mid-task on usage limits — two of the last
three did. **A dying worker's uncommitted work is recoverable from its worktree** (`git -C <worktree>
status`); check there before redoing anything, and commit a stopped worker's tree as an explicitly
unverified WIP rather than leaving it loose. **Branch a worker's worktree from the phase tip, not
`origin/main`** — every worker up to session 26 had to `merge --ff-only` onto the real tip first, and
branching correctly deletes that step entirely.

## State

Fast tier **718/718**. Full XCUITest suite run at the 5b boundary — see the session log for the
number and for anything environmental. `Compositor.backend` is still `.coreGraphics`.

## What phase 5b built, so you don't rediscover it

The live canvas finally shows blended layers. The owner's scope decision was **exact at rest, snaps
on lift**, not mid-stroke fidelity:

- At rest the canvas is one `composite(full)` with every host blanked — exact for every mode and
  every nesting, byte-identical to the thumbnail.
- While a dab is down, a below/live-host/above trio takes over. The active layer's own blend and any
  layers above it render as Normal for the dab's duration and snap on lift.
- `[RenderNode].needsCompositorOnCanvas` is the engage switch, and it is the risk containment: a
  document with no blend modes and no faded or isolated group keeps Core Animation's old flat-sibling
  path untouched.
- `[RenderNode].split(atLeaf:)` prunes the tree either side of the active leaf, keeping an enclosing
  group's properties on **both** halves. `SandwichLogicTests` (24 cases) pins the identity.
- Rebuilds run **off-main** on `CanvasView`'s sandwich queue, showing the previous images until the
  new ones land. Measured: snapshot 0.1 ms, three composites ~55 ms at 2048²/six layers. That async
  path is load-bearing, not incidental — 55 ms inline is a dropped frame at 60 Hz and several at 120.

## The two things in 5b that phase 6 will collide with

1. **`layer.mask` is already taken on `LayerHostView`.** Blanking a host for the sandwich installs a
   contentless `CALayer` as `host.layer.mask` (`LayerHostView.setBlanked`), because `isHidden` and
   `alpha` both make `hitTest` return nil and a blanked *active* host would silently swallow the
   first touch of every stroke. §6.4 wants the resolved alpha mask carried as a `CALayer.mask` on the
   **live stroke view** — `host.strokeView`, a different layer, so the two do not fight *as written*.
   Put phase 6's mask on the host instead and you will break blanking, or blanking will eat your
   mask, depending on order. Neither fails loudly. Decide this deliberately and comment it.
2. **The content-version key you need already exists.** §6.2 says the resolved mask texture is cached
   on the source subtree's `contentVersion`, and §9.1's `contentVersion` was *removed* in phase 2
   after being measured at a zero hit rate — because it keyed on the rendered `CGImage`, which
   `PixelOps.rasterize` mints fresh every call. 5b built the version that works: a per-layer key
   derived from **model** state (cel id, both tiers' object identity *and* version, fill/baked image
   identity), in `CanvasView`'s sandwich key. Reuse that derivation rather than reintroducing the one
   that could not hit. Note the trap it already handles: a cel id outlives the buffers under it, so
   reopening a project rebuilds every `RasterLayerTexture` with its counter back at 0 under the same
   id — a version-only key serves pre-edit pixels.

## What §6 has already settled, so don't reopen it

Read §6 in full, but the load-bearing calls are: masks resolve at **render time and are never baked**,
for raster as well as vector — non-destructive is *cheaper*, since the mask is cached once per
distinct mask and shared, while destructive makes undo retain the pixels it destroyed. Sources
**union** by `max` of alpha. A source that would create a cycle is **ignored, not diagnosed**. The
test is `sourceAlpha > threshold` (≈0.5) and **not** `> 0`, because `softRound`'s dab falls to alpha
≈ 0 across its whole radius and `> 0` would make every mask visibly larger than its stroke; a narrow
smoothstep across the threshold handles the diagonal stair-stepping without reintroducing a gradient.
A mask **ignores its source's visibility**, deliberately unlike `isFillReference`. Mask edits coalesce
to one undo step per mask-edit session.

`MaskParityLogicTests` is the phase's gate: a raster layer and a vector layer with identical content
and identical masks must composite pixel-identically. Insist on it structurally — `selectionClipPath`
is the cautionary tale already in the tree, clipping raster by reverting pixels at stroke-end and
vector by dropping samples, and its own comment admits the two disagree.

## Gotchas that each cost a cycle

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Build `-only-testing` flags into a
  shell *array* and pass `"${SUITES[@]}"` — zsh does not word-split an unquoted `$VAR`. Read
  `totalTestCount` from `xcresulttool`, never the banner. CLAUDE.md has the recipe.
- **A new test file needs a `project.pbxproj` edit.** `PaintSoftwareUITests` opts out of
  `PBXFileSystemSynchronizedRootGroup` and hand-lists its sources, so an unregistered file compiles
  nowhere, runs nothing, and still prints a green banner.
- **After `simctl erase` you must `boot`** (`xcrun simctl boot <udid>; xcrun simctl bootstatus <udid>
  -b`) or the runner fails behind a wall of `FBSOpenApplicationServiceErrorDomain` that means only
  "nothing is booted".
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, boot, re-run the single
  test; a clean pass is confirmation it was environmental. Never re-run the 22-minute suite to decide.
- **Do not add a heavy case to the fast tier.** A phase-4 case allocating ~400 MB pushed
  `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` from 0.073 s to 8.98 s
  and failed whenever they shared a runner process. Measure, record the number, drop the case.
- **Verify a worker's numbers, not its summary.** One session recorded a "measured" delta table it
  had never run; the real figure was 70× larger and was a genuine bug.

## Carried forward, with the answer already worked out

Mid-stroke, layers above the active one render as Normal. Recovering them exactly needs a `backdrop:
CGImage?` on `RenderRequest` honoured by both backends, plus a per-pixel unpremultiply against it:
composite the above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from the
same stack over transparency, emit `αs = c`, `Cs = (R − B(1−c))/c`. Cut from 5b deliberately —
whether that flicker actually bothers the owner is worth measuring rather than guessing. **Ask
before building it.**

## Constraints

Follow CLAUDE.md — multi-session protocol, build/test tiers, graphify. Run the fast `*LogicTests`
tier constantly; run the full suite at the phase boundary, and if you skip it say so plainly rather
than implying it passed. Match the surrounding comment density and idiom — this codebase explains
why, not what. Keep the docs short: prune what is done rather than appending status.

When phase 6 is done and verified: prune §6 and §11 to what shipped, append the one-line
SESSION_LOG.md entry (keeping only the last five), refresh the graphify report, and **write the next
session's prompt to `nextprompt.md` and commit it** — whatever is genuinely next (phase 7's Tier 2
modes are non-separable and need the whole RGB triple, and Apple's versions should be assumed to
disagree with the spec until measured, exactly as Tier 1's colorDodge/colorBurn/softLight did),
including what you learned that would otherwise be rediscovered, and this same instruction to write
the following session's prompt at the end. Keep it about this long.
