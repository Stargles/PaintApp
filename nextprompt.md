Read LAYER_COMPOSITING.md first — the agreed design, settled with the product owner. §11 is the build
order. Phases 0 through 5a are done, committed and green. **You are doing phase 5b: §5.2's sandwich,
so the live canvas actually shows a blended layer.** It is the last thing standing between blend
modes and being usable, and it is the riskiest rewrite in the project — see below.

You are the orchestrator. Delegate to worker sessions and pick the model per task, but **at most
2 sonnet + 1 opus at any one moment**. Last session's opus worker died mid-task on a *weekly* usage
limit; its uncommitted work was recoverable from its worktree with `git -C <worktree> diff`. If a
worker dies, check its worktree before redoing anything.

## Why phase 5 is only half done

The compositor blends correctly — fourteen Tier 1 modes, both backends, verified — and the picker
and row badge ship. But `CanvasView.reconcileLayers` still hands every layer to Core Animation as a
flat sibling, and Core Animation has no per-view Multiply against arbitrary siblings (§1). So an
artist sets Multiply, sees it in the layer row and in the project thumbnail, and **sees no change on
the canvas they are drawing on.** That is the whole of your phase.

## The sandwich, and what it will cost you

§5.2's structure is three views, not N:

```
[ composite of everything BELOW the active layer ]   ← cached texture
[ the active layer's live stroke view            ]   ← Core Animation, unchanged, zero added latency
[ composite of everything ABOVE the active layer ]   ← cached texture
```

**A lower-risk implementation than it sounds, if you keep the host views.** `layerHosts` holds one
`LayerHostView` per layer, and other code reaches into it by identity — `updateFloatingOverlay`
inserts the Move piece *below a specific layer's host*
([CanvasView.swift:672](PaintSoftware/Views/CanvasView.swift:672)), which needs an anchor that still
exists. Hiding the non-active hosts and adding two image views around the active one keeps every
anchor and z-order relationship intact; deleting the hosts does not. Consider that before rewriting
the reconcile loop wholesale.

What else lives in that container and will notice: the onion skin, selection overlay, floating (Move)
overlay, shape overlay, guide overlay, transform overlay. Touch routing is already fine —
`shouldInteract` enables exactly the current layer's host, so the sandwich preserves it for free.

Invalidation: rebuild both textures when anything *other than the live stroke* changes — layer
switch, blend change, playhead move, undo, visibility, opacity. Stamping a dab must invalidate
neither, or the compositor is in the drawing path, which §2 forbids.

**The prerequisite is already done.** `PixelOps.rasterize` is memoized (commit `1e4d7d1`), which
addresses the measured 276 ms snapshot the sandwich would otherwise pay on every layer switch. The
old numbers in §11's closing paragraph predate that memo.

## What phase 5a built, so you don't rediscover it

- `Models/BlendMode.swift` — fourteen separable cases, `displayName`, `menuGroups` (picker order),
  `isBlending`. "Clip to below" is deliberately absent and lands in phase 6 as a mask with an
  implicit source; §7 lists it in Tier 1 while admitting it is not a blend.
- `RenderNode.needsOwnBuffer` — the single buffer rule both backends obey. All three clauses are
  live now. Do not re-spell it per backend; that drift is what phase 4 deleted.
- `BlendMode.handRolledChannel` in `Compositor.swift` — six modes the CPU computes itself. Three
  because `CGBlendMode` lacks them; **three because Apple's disagree with the spec.**

## The finding worth carrying forward

**CoreGraphics is not the authority on blend functions.** `CGBlendMode.colorDodge`, `.colorBurn` and
`.softLight` are the PDF 1.4 originals and differ from W3C Compositing Level 1 by up to 249/255 —
the two divisions have no zero-backdrop guard, so Color Dodge lifts a black backdrop to white where
the modern rule keeps it black, and soft light uses a different `D(cb)` curve. The app follows the
spec, which is what Photoshop and CSP do. §5.1's "byte-for-byte definition of correct" is now scoped
to the *walk* — order, buffers, alpha — and not to the blend maths. **Phase 7's Tier 2 will hit this
again**: Hue/Saturation/Color/Luminosity are non-separable, need the whole RGB triple, and Apple's
versions should be assumed to disagree until measured.

Measured GPU-vs-CPU max channel delta, all fourteen, leaf and group sweeps identical:

    normal 0 · multiply 1 · screen 0 · overlay 0 · add 0 · subtract 0 · darken 0 · lighten 0
    colorDodge 1 · colorBurn 1 · softLight 0 · hardLight 1 · linearLight 0 · difference 0

## Gotchas that each cost a cycle

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Use an array and `"${SUITES[@]}"`,
  read `totalTestCount` from `xcresulttool`, never the banner. CLAUDE.md has the recipe.
- **After `simctl erase` you must boot the device** (`xcrun simctl boot <udid>; xcrun simctl
  bootstatus <udid> -b`) or the runner fails behind a wall of `FBSOpenApplicationServiceErrorDomain`
  that means only "nothing is booted".
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, re-run the single test,
  treat a clean pass as confirmation. Never re-run the 22-minute suite to decide.
- **Do not add a heavy case to the fast tier.** A phase-4 perf case allocating ~400 MB pushed
  `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` from 0.073 s to 8.98 s
  and failing whenever they shared a runner process. Measure, record the number, drop the case.
- **A worker's worktree starts at `origin/main`**, many phases behind. Every worker so far has had to
  `git merge --ff-only` onto the real tip first. Tell them so in the prompt.
- **Verify a worker's numbers, not just its summary.** Last session's compositor worker recorded a
  "measured" delta table it had never run; the real figure was 70× larger and was a genuine bug.

## State

Fast tier **694/694**. `PerfBaselineTests` green. **The full XCUITest suite was not re-run after the
blend work** — run it at your phase boundary, after `simctl shutdown all` + `erase`.

Constraints: follow CLAUDE.md (multi-session protocol, build/test tiers, graphify). Run the fast
`*LogicTests` tier constantly; run the full suite at the phase boundary, and if you skip it say so
plainly rather than implying it passed. Match the surrounding comment density and idiom — this
codebase explains why, not what. Keep the docs short: prune what is done rather than appending
status. Append the one-line SESSION_LOG.md entry (keeping only the last five) and refresh the
graphify report.

When phase 5b is done and verified, end by writing the copy-paste prompt for the next session —
whatever is genuinely next (phase 6, alpha masks, which "Clip to below" is waiting on), including
what you learned that would otherwise be rediscovered, and the same instruction to write the
following session's prompt at the end. Keep it about this long. **Write it to `nextprompt.md` in the
repo root and commit it.**
