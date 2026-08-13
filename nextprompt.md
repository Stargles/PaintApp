Read LAYER_COMPOSITING.md first — the agreed design, settled with the product owner. §11 is the build
order. Phases 0 through 5a are done. **You are finishing phase 5b: §5.2's sandwich, so the live canvas
actually shows a blended layer.** Half of it has landed and is verified; the other half is a draft
that has never been built. See "State" below before you touch anything.

You are the orchestrator. Delegate to worker sessions and pick the model per task, but **at most
2 sonnet + 1 opus at any one moment**. Sessions keep dying mid-task on usage limits — this one did,
and the one before it. **A dying worker's uncommitted work is recoverable from its worktree**
(`git -C <worktree> status`), so check there before redoing anything, and commit a stopped worker's
tree as an explicitly-unverified WIP rather than leaving it loose.

## State

| | |
|---|---|
| `claude/layer-system-redesign-f9afd9` | the phase branch, at `9925d51`. **Fast tier 718/718, verified from `xcresulttool`, not the banner.** |
| `tmp/5b2-sandwich-wiring` at `966b012` | the CanvasView wiring, ~630 lines. **Never built, never run.** |

The full XCUITest suite **has not been run since the blend work** — two phases ago now. Run it at the
phase boundary, after `simctl shutdown all` + `erase` + **boot**.

## The scope decision, taken by the product owner on 2026-08-12

§11's done-criterion reads "a Multiply layer looks multiplied while drawing", which is ambiguous
between "during a drawing session" and "mid-stroke, on the wet dab". **The owner chose: exact at
rest, snaps on lift.** Do not quietly widen this.

- **At rest** (no dab down) the canvas shows one image, `composite(full)` — byte-identical to what
  the thumbnail renders, every blend mode and every nesting exact, every layer host blanked.
- **Mid-stroke** the three-view sandwich takes over: `composite(below)` | the active layer's live
  host | `composite(above)`. The active layer's own blend degrades to Normal for the dab's duration,
  and so do any layers above it, because a texture composited onto transparency has no backdrop to
  blend against. Both snap correct on lift.

This is what keeps the compositor out of the drawing path, which §2 requires. Blending the wet stroke
itself needs a per-dab GPU upload scissored to `strokeDirtyRect` and is deliberately a later phase.

**Rejected, so nobody re-proposes it:** `CALayer.compositingFilter` would make the middle view blend
for free. It is private-ish on iOS *and* it would use Apple's blend maths, which phase 5a measured as
disagreeing with the spec by up to 249/255 on three modes — so mid-stroke would not match at-rest.

## What 5b-1 built and verified (commit `9925d51`)

```swift
extension Array where Element == RenderNode {
    var needsCompositorOnCanvas: Bool { get }                                    // the engage switch
    func split(atLeaf layerIndex: Int) -> (below: [RenderNode], above: [RenderNode])?
}
struct SandwichRequests { let full: RenderRequest; let below: RenderRequest; let above: RenderRequest }
extension CanvasManager {
    @MainActor func makeSandwichRequests(atFrame:activeLayerIndex:quality:) -> SandwichRequests?
}
```
`SandwichLogicTests`, 24 cases, pins all of it. **Measured, actually run:** the exact case is delta 0
across nine tree shapes; the approximations are 127 (a blending layer above the active one), 127 (the
active layer's own mode) and 64 (active layer inside a group at 0.5 opacity — sandwich RGBA
(64,128,0,192) against exact (0,128,0,128), so alpha drifts too, not only colour). Those are asserted
at their measured values, so they fail if the approximation improves *or* worsens.

Two honest caveats from that worker, worth not rediscovering:

- **Delta 0 holds because the fixtures are opaque.** The `above` half quantizes to 8-bit once more
  than the direct walk. One semi-transparent layer above costs 0; it takes four stacked fractional
  draws to reach 1. The `below` half is exact whatever the alphas are, and that is structural — it is
  a prefix of the same walk drawn into a still-transparent context. If you ever have to trust one
  texture, trust the lower one.
- **A faded group *above* the active layer** is not covered by the stated exact-case condition and is
  not exact either — same double-quantization, measured at 1.

## Gotchas the wiring session was handed, which the draft should already reflect — verify it does

- **`host.isHidden = true` breaks drawing, silently.** `UIView.hitTest` returns nil for hidden,
  `alpha < 0.01`, or interaction-disabled views, so a blanked *active* host never receives a stroke's
  first touch and the stroke simply does not happen. `UIView.alpha` and `CALayer.opacity` are the same
  property, so neither is an escape. Blank with `host.layer.mask` — a contentless mask layer is alpha
  0 everywhere and **UIKit does not consult masks when hit-testing**. Assign it once; do not allocate
  a `CALayer` per pass, `updateUIView` runs on every SwiftUI render.
- **Z-order**: in `reconcileLayers`, after the existing ordering pass, front `belowView`, then each
  host in order, then `aboveView` — giving `onionSkin < belowView < hosts < aboveView < chrome`. That
  keeps `updateFloatingOverlay`'s Move anchor (`insertSubview(overlay, belowSubview: hostAbove)`,
  CanvasView.swift:672) landing between the two sandwich views, which is where it belongs. The
  existing pass is gated on `orderedIDs != lastOrderedLayerIDs` and must also run when engagement
  changes.
- **Two async traps.** Do not blank the hosts until the first composite lands, or the first engage
  flashes an empty canvas. Do not flip to rest on stroke-end until the *new* `full` lands, or the
  artist watches their finished stroke vanish and reappear.
- **The active layer's content version belongs in the invalidation key only while no stroke is in
  progress.** That one rule gives both halves of the contract: frozen during a dab so stamping
  rebuilds nothing, unfrozen on lift so the canvas snaps.
- **Risk containment, and it is the point**: engage only when `needsCompositorOnCanvas`. A document
  with no blend modes and no faded/isolated group must take today's exact path and cannot regress.

## What is left

1. Build the WIP. It has never compiled. Then the fast tier — **718/718 is the bar**.
2. The XCUITests it was asked for and may not have finished: the mask-trick regression guard (set a
   blend mode, draw, assert the stroke landed), a Multiply layer looking multiplied at rest (§11's
   criterion), an all-normal document unaffected, and blend/layer-switch/visibility/undo/playhead
   each bringing the canvas back in sync.
3. **The rebuild cost, measured** — 2048², ~6 layers, CoreGraphics backend. The worker was killed
   immediately before taking this number. Record it; do not add the case to the fast tier, since a
   phase-4 case allocating ~400 MB pushed an unrelated interpolation test from 0.073 s to 8.98 s.
   `Compositor.backend` stays `.coreGraphics` — Metal for the sandwich is a follow-up, not this phase.
4. Full XCUITest suite at the boundary. Read CLAUDE.md's triage before diagnosing any failure: erase,
   **boot**, re-run the single test, treat a clean pass as environmental and say so.

## Carried forward to a later phase, with the answer already worked out

Mid-stroke, layers above the active one render as Normal. Recovering them exactly needs a `backdrop:
CGImage?` on `RenderRequest` honoured by both backends, plus a per-pixel unpremultiply against it:
composite the above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from the
same stack over transparency, and emit `αs = c`, `Cs = (R − B(1−c))/c`. Drawn source-over onto `B`
that reproduces `R` exactly. It was cut from 5b deliberately — it is real parity-test surface for a
case that degrades gracefully, and whether the mid-stroke flicker actually bothers the owner is worth
measuring rather than guessing.

## Constraints

Follow CLAUDE.md — multi-session protocol, build/test tiers, graphify. **A worker's worktree should be
branched from the phase tip, not `origin/main`**; every worker before this session had to `merge
--ff-only` onto the real tip first, and branching correctly deletes that whole step. Run the fast
`*LogicTests` tier constantly. **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran** — use a
shell array and `"${SUITES[@]}"`, read `totalTestCount` from `xcresulttool`, never the banner.
**Verify a worker's numbers rather than its summary**: one session recorded a "measured" table it had
never run and the real figure was 70× larger and was a genuine bug. Match the surrounding comment
density — this codebase explains why, not what. Keep docs short: prune what is done rather than
appending status.

At the phase boundary: prune §5.2/§11 to what shipped, append the one-line SESSION_LOG.md entry
(keeping only the last five), refresh the graphify report, and **write the next session's prompt to
`nextprompt.md` and commit it** — whatever is genuinely next (phase 6, alpha masks, which "Clip to
below" is waiting on), including what you learned that would otherwise be rediscovered, and this same
instruction to write the following session's prompt at the end. Keep it about this long.
