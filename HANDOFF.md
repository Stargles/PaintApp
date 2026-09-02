# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## State

`main` is clean at `f96cf42`, one worktree, no branches, no stray simulators.

**Fast tier: 2283 declared, 2280 passed, 0 failed, 3 skipped.** Three `testBrush` helpers match the
counting regex and are not tests, which is why the declared and executed numbers differ by three.

**The full suite has not been run since `72c7cc1`** — 2358 tests in 24.4 minutes, 1 environmental
failure. Eleven merges have landed since, several on the stroke path. Budget a full run before the
next phase boundary, and erase the simulator immediately before it.

**The iPad carries a Release build of `7c38ba2`.** Nothing merged since is on the device: not the
Oklab ramps, the dark colour scheme, the three graph-editor fixes, or any of this pass. The owner's
"UI Test" canvas, which is where they see the resolution bug, is on that build. Ask rather than
assume.

## What is being built: TODO (29), the background renderer

[RENDER.md](RENDER.md) is the specification. **§1 is the ask in the owner's own words, §2 is sixteen
rulings, §3 is the design, §5 is the build order.** Read §2 rather than re-deriving it.

The shape in one paragraph: the main thread stops compositing. A background baker composites each
frame and writes it to disk, keyed by a fingerprint of everything that affects its pixels, so an
unchanged frame is never rebaked and an anime hold is one file. Play reads baked frames. Export reads
the same files and re-renders nothing. Compositing walks the layer tree bottom-up under a memory
ceiling, which is what lets a hundred layers fit in a device that cannot hold them all at once.

**Stages 0 and 1 are merged. Stage 2 is next**, and it is the one that removes the pen-up freeze.

### Stage 2 — the recipe

The main thread still does two canvas-sized things at pen-up, and neither is the compositor:

1. **The committed cel is re-rasterised in full** — every dab of every stroke, into a fresh
   canvas-sized bitmap (`Views/Canvas/StrokeCanvasView.swift` `commitVectorStroke` → `refreshDisplay`
   → `Engine/VectorLayer.swift` `renderLocalContent`).
2. **The snapshot flattens every visible leaf** to a canvas-sized image, fanned over cores but
   blocking the caller (`Engine/RenderRequest.swift` `renderSources`, `@MainActor` by design).

Stage 2 introduces `FrameRecipe` and `LeafSnapshot` (RENDER §3.2): a value type minted on the main
actor in O(layers) with no pixel work, holding the tree and, per leaf, the immutable inputs its render
needs. The baker renders leaves from that on its own queue. `renderSources` leaves the main actor, and
the committed cel's re-render becomes asynchronous with the stroke's scratch window retained until the
new image lands — which is exactly the split-second stale canvas ruling §2.13 allows.

Pin it with a logic test that the recipe's pixels equal the live snapshot's, and a perf baseline for
main-thread time at pen-up. **§2.15 applies**: the synchronous path is deleted in the same change.

## What this pass established, and would otherwise be re-derived

- **Compositing already runs off the main thread** and has for some time — `Compositor.composite` on
  `CanvasView.sandwichQueue`, pure over a request that holds no live model object. The freeze is
  everything that *feeds* it. A design that starts "move compositing to a background thread" is
  starting from a false premise.
- **Bottom-up chunked compositing is exact**, with four rules, and RENDER §3.4 carries the proof:
  no blend mode and no effect reads a layer above it, the walk already quantises per step, and a
  readback-then-upload round trip is lossless. The four rules are the chunk unit being a node rather
  than a layer index, ink-input effects pinning their sources, masks resolving first, and `.stack`
  folders being transparent to the cut.
- **A hold is one cel spanning many frames**, so leaving the frame out of the bake key makes holds
  dedupe for free — an anime document's cheapest property, and it costs nothing to get.
- **`renderSources` is the memory problem, not the compositor's intermediates.** The compositor peaks
  at two canvas textures for a flat stack of any length; the snapshot holds one per visible leaf.
- **Two claims in LAYER_COMPOSITING §9.1 describe work as built that is not built**: nothing
  propagates a content version to an ancestor, and frame-scoped invalidation does not exist. TODO (29)
  repeated both as "already built and must not be rebuilt". Do not skip that work.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do.
2. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be", no narrating which premise an investigation
   overturned.
3. **A replaced path is deleted, not left beside the new one.** RENDER §2.15 in the owner's words:
   *"very clean and non-redundant, with no peculiarities, and no legacy code left by the previous
   functionality."* This is why stage 2 deletes the synchronous snapshot rather than gating it.

## Traps this pass paid for

- **A worker's working tree is a workbench.** One worker had to edit two hunks in a file another
  worker owned, because the alternative was shipping a wrong-pixels regression. Tell concurrent
  workers when `main` moves under them; do not let them discover it at rebase.
- **Establish the test baseline yourself.** Three workers were given a stale count and each corrected
  it. Count `func test` statically at your own base and at your head, and match the xcresult total to
  the head. A brief's number is a hypothesis.
- **`git checkout HEAD -- <dir>` after a commit discards uncommitted edits in that directory** — it
  restores to the commit, not to what is on disk. It cost one worker a round of test edits.
- **A test that pins a size must include something that would not fit**, or deleting the bound leaves
  it green. Two workers built their fixtures that way deliberately after the fourth occurrence of this
  shape.

## Everything else open

**The owner's asks**, all recorded in TODO: (31) the three large-canvas symptoms — the resolution bug
is `affordableSize` and is stage 5, the crash is fixed, the freeze is stage 2; (32) merging a blend
layer down does not bake the blend, lower priority; (33) select-and-duplicate produces raster from a
vector selection; (34) imported images should arrive in a move box, a small job that reuses the Move
code; (23) the membership control belongs to Select; (35) colour-range masks; (36) projects stored
where the artist chooses; (37) importing brushes. (26)-(28) and (30) are the long-term features and
each needs a design conversation before it starts.

**BUGS.md's memory audit** is twelve ranked sites, three closed this pass. Stage 7 takes the rest.
Two are worth naming here because they bite before then: the vector render cache and the mask cache
are bounded by entry count rather than bytes, and the evictor for the first walks every cel in the
document and takes a lock per vector canvas **on every playback tick**.

**KEYFRAMES §8 stage 5** — the transform channel — is where (21) stopped. The owner ruled it comes
before stage 4, and the gate that could have reversed that is already answered in the spec.

**Two behaviour questions are owed**: save semantics when a project loaded with something unreadable,
and which faces belong in the font picker's favourites strip.
