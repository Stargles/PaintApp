# Layer Compositing

Plan for tree-ordered groups, **compositor nodes**, alpha masks, and blend / effect layers — which
are all one project, because they all need the same missing thing. **Phases 0–3 of §11 are built and
green.** §3 is the decisions; §10 is what is still open; §11 is what remains.

## 1. Why these are one project

The app had no compositor: "compositing" was two unrelated implementations, neither of which could
express any of this. [`Compositor`](PaintSoftware/Engine/Compositor.swift) is now the offline one —
a tree walk over an immutable `RenderRequest`, with a CoreGraphics reference and a Metal backend
behind a flag that agree byte for byte. The live canvas is unchanged:

| path | where | how |
|---|---|---|
| **Live canvas** | `CanvasView.reconcileLayers` ([CanvasView.swift:466](PaintSoftware/Views/CanvasView.swift:466)) | one `LayerHostView` per layer, all siblings in one flat container, z-order by `bringSubviewToFront`, per-layer `isHidden` + `alpha`. **Core Animation does the compositing**, always source-over. |
| **Offline** | `Compositor.composite` | tree walk over a snapshot. One consumer: the project thumbnail. |

What still blocks everything below:

- **Folders do not exist at render time.** `toggleFolderVisibility`
  ([CanvasManager.swift:829](PaintSoftware/Models/CanvasManager.swift:829)) *writes through* to every
  descendant's `isVisible`. A folder is a panel affordance, not a compositing unit — there is nowhere
  to hang a group opacity, blend mode, or mask. The compositor carries both flags and interprets only
  the leaf's, so §4.1 stays a phase-4 decision rather than a side effect.
- **There is no seam for a blend mode on the live canvas.** Core Animation offers no per-view
  Multiply against arbitrary siblings, and the compositor does not drive the live canvas yet — that
  is §5.2's sandwich, still to build.

Express groups / nodes / masks / blends in the one compositor; do not grow a second.

## 2. What is *not* changing

- **`layers` stays a flat array with the contiguous-span folder invariant.** That arithmetic is
  load-bearing and hard-won (session 41, [CanvasManager+LayerTree.swift:24](PaintSoftware/Models/CanvasManager+LayerTree.swift:24)).
  A contiguous span *is* a subtree in array form — the tree is already there, it is just never
  derived. **This plan derives a tree; it does not restructure storage.** Every restack / group /
  merge operation and every view binding is untouched. §4.3 shows this survives compositor nodes too.
- **The drawing surface stays as it is.** `StrokeCanvasView` keeps stamping incrementally into
  `RasterLayerTexture` (O(dab area)); `VectorCanvas.render()` keeps its version cache. Stroke latency
  is the app's most valuable property and the compositor must not enter that path.
- **`PixelOps.rasterize(cel:)` stays.** It flattens tiers *within* one cel and has ~10 callers. It
  sits below the compositor.

## 3. Settled decisions

Cheap to break, expensive to relearn.

1. **The mask resolves at render time and is never baked into pixels — for raster *and* vector.**
   See §6.1. This is the decision the whole mask feature hangs on.
2. **Groups are isolated**, with a pass-through toggle in the group's options menu.
3. **Masks are binary, unioned**, with a threshold — not an alpha gradient. §6.3.
4. **A group is a 1-input compositor node.** Groups and nodes are the same mechanism at different
   arities, so there is one renderer, not two. §4.3.
5. **The compositor consumes an immutable snapshot, never live model state** — from day one, even
   though it runs on the main thread at first. This is what makes §9's background renderer possible
   without a rewrite, and the app has already learned this lesson once
   ([ProjectStore.swift:178](PaintSoftware/Services/ProjectStore.swift:178): "the background queue
   sees no shared mutable state").
6. **The sandwich keeps the compositor out of the drawing path.** §5.2.
7. **Vector is the default layer kind**, and empty vector layers must be free to match. §8.
8. **Every effect is available both as a stack layer and as a 1-input node** — same shader, different
   input-resolution rule. §4.4.
9. **A mask ignores its source's visibility.** A hidden layer still masks, so a dedicated invisible
   mask-shape layer works and an eye toggle never silently repaints. §6.6.
10. **Mask edits coalesce into one undo step per mask-edit session.** §6.6.
11. **Build order is foundation-first**: tree, then compositor, then features. §11.

## 4. The render tree

### 4.1 Structure

Derived and cached — not new storage:

```
RenderNode
  ├─ .leaf(layerIndex)
  └─ .node(id, op: CompositorOp, inputs: [[RenderNode]])     // N ordered input slots
  common: opacity, isVisible, blendMode, mask: ResolvedMask?, isIsolated, contentVersion
```

Built by the same recursion that already produces `layerStackRows`, invalidated on structure change.
Evaluation is bottom-to-top, **recursing into a node before compositing its result into its parent** —
which is exactly "groups are parentheses."

`LayerFolder` gains `opacity`, `blendMode`, `isIsolated`, `alphaMask` (persisted in `FolderManifest`,
all defaulted, so existing projects decode unchanged). `toggleFolderVisibility` stops writing through
to children; the group's own `isVisible` gates its subtree at composite time. That is a change to
shipped behaviour — hiding a group and re-showing it currently *clobbers* per-layer visibility, and
after this it will not. Restoring a `ViewPreset` saved under the old behaviour still works, since
presets snapshot both layer and folder visibility already.

### 4.2 Isolated groups

Children start from transparent and blend only against each other; the finished buffer composites
into the parent with the group's own opacity / blend / mask. A `multiply` child at the bottom of a
group multiplies against nothing and therefore reads as normal — that is correct and intended.

**Pass-through** (children blend against the backdrop below the group, as Photoshop and CSP default)
is a per-group toggle in the options menu, off by default.

### 4.3 Compositor nodes

A second way to composite, alongside blend modes: a node added from the layers menu that takes **two
or more inputs below it**, each input holding layers or further nodes.

**A group is this same thing with one input slot.** One renderer covers both; a "folder" is
`.node(op: .stack, inputs: [children])`.

**Storage — no new tree arithmetic.** A node's input slot is stored as an ordinary `LayerFolder`
that is auto-created, undeletable, and tagged with its owning node and slot index. The node itself
is a folder whose children are exactly its slot folders. So containment, restack, contiguity,
visibility, and the panel's row generation all reuse the existing machinery unchanged — only
*rendering* and *panel chrome* differ. The contiguity invariant generalises cleanly: each slot is a
contiguous span, and the node's span is the union of its adjacent slots' spans.

```
▼ [Node] Mix                    ← CompositorNode row
   ▼ Input A                    ← slot folder (undeletable)
       Layer 3
       Layer 2
   ▼ Input B
       Layer 1
```

**Arity** is declared by the op: `.fixed(2)` for Mix, `.variadic(min: 2)` for Add/Max. Variadic nodes
get add/remove-slot controls. An input slot is **always isolated** — otherwise "input" is meaningless.

`Mix(A, B, .multiply)` is deliberately the same math as stacking B over A with blend mode multiply.
That redundancy is the point (it is why Blender has both): the stack is ergonomic for painting, the
graph is ergonomic for effects with more than one input. Do not try to unify them away.

### 4.4 Effects are both a layer and a node

Every effect in §7 ships in two wrappers over **one shader**:

- **As a stack layer** (`LayerKind.compositing`, the case already reserved in
  [LayerKind.swift:9](PaintSoftware/Models/LayerKind.swift:9)) — it grades everything below it
  *within its own container*, the Photoshop adjustment-layer model. Fast for the common case.
- **As a 1-input node** — it grades only what is dragged into its input slot, the Blender model.
  Precise, and composes with multi-input nodes.

Only the input-resolution rule differs: *"the accumulated backdrop so far in this container"* versus
*"this slot's composite."* Both hand the same texture to the same kernel. Nothing else in the design
branches on which wrapper was used.

Container scoping is what keeps the layer form predictable: an effect layer inside a group cannot
reach outside it. That is also what makes an isolated group (§4.2) the right default — the grade
stops at the parenthesis.

**Proxy layers — explicitly deferred, do not build.** The same layer or group appearing in two
positions turns the tree into a DAG, needing cycle detection and a content-keyed render cache so the
shared subtree renders once. Worth noting only because **masks already need both** (a mask references
a subtree from elsewhere in the tree — that is already a DAG edge, §6.2), so when proxies are wanted
the infrastructure will largely exist. Nothing in this plan should assume a node has exactly one
parent.

## 5. The compositor

### 5.1 GPU, via Metal

- The infrastructure already ships: `MetalFillEngine` owns a device, queue, and nine compute
  pipelines; `Fill.metal` is in the build; the Metal toolchain is a documented prerequisite. This is
  a second consumer of an existing dependency, not a new one.
- Blend modes are per-pixel math over the whole canvas — 4.2M pixels at 2048², 16.8M at 4000², per
  node, per frame. CoreGraphics cannot do that at interactive rates.
- Blur, Sobel, chromatic aberration, dither are neighborhood or multi-pass filters. On CPU they are
  not practical; on GPU each is a kernel.
- **Vector is not an argument against GPU.** `VectorCanvas.render()` already produces a `UIImage`
  cached by `version`; the compositor uploads it as a texture keyed on that same version, so
  scrubbing does not re-upload. Vector and raster arrive as the same thing — which is what makes
  mask parity (§6.1) free rather than a matching exercise.

**Blend modes are one `switch` in one shader.** Adding a mode is a few lines and no new plumbing.
Effect nodes get a slightly larger contract (they read the backdrop, may need multiple passes and a
ping-pong buffer for separable blurs).

### 5.2 The sandwich

A naive "recomposite everything every frame" would be *slower* than today's Core Animation path for
an ordinary all-normal document. The structure that avoids it:

```
[ composite of everything BELOW the active layer ]   ← cached GPU texture
[ the active layer's live stroke view            ]   ← Core Animation, unchanged, zero added latency
[ composite of everything ABOVE the active layer ]   ← cached GPU texture
```

Stamping a dab invalidates neither cached texture, so the drawing path never enters the compositor.
The textures rebuild only when something other than the live stroke changes — layer switch, blend
change, mask edit, playhead move, undo.

This is one compositor, not two: **`PixelOps.compositeCanvas` is deleted** (phase 3) and the thumbnail
goes through `Compositor.composite`. The rest of that convergence list turned out to be smaller than
written, which is worth recording so nobody goes looking for the work:

- **Export does not exist.** There is no share sheet, photo-library write, or image-export feature in
  the app — the only PNG writes are project persistence. Nothing to converge.
- **`mergeLayers` is not a stack composite.** It flattens exactly two cels via `PixelOps.flatten`,
  chosen by the merge rather than by the tree, and sits below the compositor beside
  `PixelOps.rasterize` (§2).
- **The onion skin is not one either.** `InterpolationReferenceOnionSkinSource`
  ([OnionSkinSource.swift:106](PaintSoftware/Views/OnionSkinSource.swift:106)) flattens an arbitrary
  *cel set* at alpha 1, deliberately ignoring layer opacity and visibility. Routing it through the
  compositor would change what the onion skin shows, not merely how it is computed — a product
  decision, still open.

**Live stroke inside a blended group** (§10 decision 5, decided): recomposite **only the active
node's subtree** per frame — in practice a handful of layers — and fall back to compositing the live
stroke straight over the cached texture, snapping correct on lift, if that subtree exceeds a frame
budget. Masks do not need this at all; they have an exact answer (§6.4).

### 5.3 Performance

Memory is the constraint, not ALU.

- One RGBA8 canvas texture is 16.8 MB at 2048², **64 MB at 4000²**. Never allocate one per layer.
  Use a **texture pool with a scratch stack**: bottom-to-top evaluation needs ~2–3 live textures per
  nesting *depth*, and depth is small. Pool by size, reuse across frames.
- **Scissor the composite to the dirty rect.** `RasterLayerTexture.strokeDirtyRect` already proves
  the pattern for undo.
- **Effect nodes render at display resolution when zoomed out**, native only for export.
- Add compositor cases to `PerfBaselineTests`, which already asserts hard budgets on stroke cost,
  thumbnail regen, and undo memory.

## 6. Alpha masks

### 6.1 Render-time, never baked — including raster

**The mask is resolved at render time and never written into the masked layer's pixels.** The layer
keeps its full buffer; the compositor multiplies its alpha by the mask when drawing it. This is what
makes the stated edge case work — mask on → draw → change the mask source → draw again — because
nothing in the document remembers the old mask, so *all* content re-clips to the new one.

> **One correction to the §10 answers.** Raster does not need to be destructive, and it should not
> be. Non-destructive raster is not more expensive — it is *cheaper*. The mask is derived from its
> source layers and cached **once per distinct mask, shared by every layer using it**; it is not
> stored per masked layer, in either kind. So non-destructive costs zero extra bytes, while the
> destructive version costs *more*, because undo has to retain the pixels it destroyed. It would also
> break the parity requirement from the original brief and re-open the exact edge case above: old ink
> permanently cut to the old mask, new ink to the new one, unrecoverable.
>
> So: **both kinds non-destructive, one code path.** "Apply Mask" stays available as an explicit,
> opt-in bake for artists who want the pixels gone. If destructive raster is still wanted as the
> default, say so and it is a small change — but it is a strictly worse trade.

Parity is worth insisting on structurally because the app's nearest analogue *fails* it today:
`selectionClipPath` clips raster by reverting outside pixels at stroke-end
([StrokeCanvasView.swift:386](PaintSoftware/Views/Canvas/StrokeCanvasView.swift:386)) but clips
vector by dropping samples ([:586](PaintSoftware/Views/Canvas/StrokeCanvasView.swift:586)), which its
own comment admits "can't crisply clip a stroke that dips outside and back in." One implementation,
not two meant to agree.

### 6.2 Model

```swift
struct AlphaMask {
    var sources: [MaskSource]   // .layer(UUID) | .folder(UUID)
    var isEnabled: Bool
    var invert: Bool
}
```

on both `Layer` and `LayerFolder` — a group can be masked, which "select other layers **or groups**"
implies in both directions.

- **Sources union.** Composite each source subtree, take its alpha, `max` across sources.
- **Cycles are broken, not diagnosed.** A masks B while B masks A; a layer masked by a group
  containing itself; a layer masking itself. Precedent: `resolvedContainer(ofFolder:)` already treats
  a folder cycle as top-level rather than hanging. Rule: **a source that would create a cycle is
  ignored**, and the UI does not offer it.
- The resolved mask texture is cached, keyed on the source subtree's `contentVersion` (§9.1).

### 6.3 Binary, with a threshold

The mask does not carry the source's alpha ramp — it is a boolean coverage test, as requested.

But the test cannot be a literal `alpha > 0`. The default brush is `softRound`, whose dab is a radial
gradient falling to alpha ≈ 0 across its whole radius, so `> 0` would make the mask **substantially
larger than the stroke looks**. So: `mask = sourceAlpha > threshold`, threshold ≈ 0.5, which tracks
the visually solid part of a stroke and reduces to `> 0` for a hard brush.

A hard boolean edge also stair-steps on diagonals. Fix it with a narrow smoothstep across the
threshold — antialiasing only, one line of shader. That keeps the "no gradient" semantic (the mask
does not inherit the source's falloff) without jaggies. The threshold is a tunable constant.

### 6.4 Live feedback while drawing

A mask applied only on lift would reproduce the selection clip's glitch — ink visibly crossing the
boundary and snapping back. It does not have to: **the mask is static for the duration of a stroke**,
so the live stroke view carries the resolved mask as a `CALayer.mask`. Core Animation applies it in
hardware, free and exact, and it is the same alpha multiply the compositor does — so they agree by
construction.

### 6.5 UI

- Toggle in `LayerOptionsPanel` ([LayerPanel.swift:138](PaintSoftware/Views/LayerPanel.swift:138)),
  beside Fill Reference. Turning it on enters **mask-edit mode**: layer rows become
  include/exclude targets, with an explicit exit. Mask-edit mode is modal state on `CanvasManager`,
  so the canvas can dim non-source layers while it is on.
- Fill's flood need not be bounded by the mask — spill outside is invisible anyway, so it is a
  nicety, deferrable.
- **`MaskParityLogicTests`**: a raster layer and a vector layer with identical content and identical
  masks must composite to pixel-identical output. Precedent: `RasterVectorParityLogicTests`.

### 6.6 Lifecycle

- **A mask ignores its source's visibility.** A hidden source still contributes its alpha. This is
  what lets a dedicated, invisible mask-shape layer live in the document — the way people actually
  work — and it means toggling an eye can never silently change what is painted where. Note this is
  deliberately *unlike* `isFillReference`, which hiding a layer does clear
  ([Layer.swift:12](PaintSoftware/Models/Layer.swift:12)); a fill boundary is about what you can see,
  a mask is about where you may paint.
- **A deleted source is dropped from `sources`**; if that empties the list, the mask disables and the
  layer renders unmasked. Consistent with `resolvedContainer(ofFolder:)`, which treats a missing
  parent as "no parent" rather than vanishing the layer. Undo restores both together, since the
  deletion already runs inside `withStructureUndo`.
- **Mask edits coalesce into one undo step per mask-edit session** — everything between entering and
  exiting mask-edit mode is a single step, so one press restores the mask you started with. The
  bracket is the same `withStructureUndo` nesting that already coalesces multi-step structural edits.

## 7. Blend modes and effects — the build list

Confirmed: **Tier 1 + Tier 2 + Tier 3, minus Kuwahara and Displacement/Warp, plus Sobel.**

**Tier 1** — Normal · Multiply · Screen · Overlay · Add (Linear Dodge) · Subtract · Darken · Lighten ·
Color Dodge · Color Burn · Soft Light · Hard Light · Linear Light · Difference · **Clip to below**
(not a blend — clips to the alpha of the layer beneath; it is the mask machinery with an implicit
source).

**Tier 2** — Vivid Light · Pin Light · Linear Burn · **Hue · Saturation · Color · Luminosity**
(non-separable, needs the RGB triple; *Color* is what makes flat-colouring line art work) · Divide ·
Exclusion · Lighter Color · Darker Color.

**Tier 3, as effect nodes** — ordered by value per unit of work:

| effect | cost | note |
|---|---|---|
| Levels / Curves | cheap | per-pixel LUT; highest artistic value on the list |
| Brightness / Contrast, HSV shift | cheap | same machinery |
| Gradient map | cheap | LUT by luminance |
| Chromatic aberration | cheap | per-channel UV offset |
| Dither / posterize / halftone | cheap | per-pixel + screen pattern |
| Noise / grain | cheap | |
| Outline / stroke around alpha | cheap–moderate | distance field around alpha; high value for line art |
| **Sobel** | cheap–moderate | 3×3 gradient in x and y, then magnitude. Pairs with Outline: it can derive line art from a painting |
| Sharpen / unsharp mask | moderate | |
| Gaussian / directional blur | moderate | separable, two passes; needs the ping-pong buffer |
| Bloom / glow | moderate | threshold + blur + add; nearly free once blur exists |

**Dropped:** Kuwahara, Displacement/Warp.

Sequencing: Tier 1 is one work item (the shader `switch` plus UI). Tier 2 is nearly free after it.
Tier 3 splits into "cheap LUT/per-pixel" (one item covering the first six), then the two that need
the multi-pass buffer (blur, bloom), with Sobel/Sharpen/Outline alongside them.

## 8. Vector as the default layer

The plain **+** ([LayerPanel.swift:91](PaintSoftware/Views/LayerPanel.swift:91)) calls
`addVectorLayer()`. Also, for consistency: the new-canvas initial layer
([CanvasSizePickerView.swift:82](PaintSoftware/Views/CanvasSizePickerView.swift:82)) and the
"No Layers" alert's button ([DrawingView.swift:109](PaintSoftware/Views/DrawingView.swift:109)),
whose label becomes "Add Vector Layer". The explicit raster/vector choices in the + menu
([LayerPanel.swift:68](PaintSoftware/Views/LayerPanel.swift:68)) stay as they are.

XCUITests that add a layer and assume raster will need auditing.

### 8.1 Prerequisite: an empty vector layer must be free

**An empty vector layer's storage is already free**, and an earlier draft of this document was wrong
to say otherwise. `Cel.fillImage`, `bakedImage`, and `vector` are nil-by-default optionals
([Cel.swift:12](PaintSoftware/Models/Cel.swift:12)); `RasterLayerTexture.empty` allocates no bitmap
and documents it ("a blank cel holds no bitmap … blank cels are free"); `VectorCanvas.empty` is an
empty array. Creation costs a few hundred bytes. BUGS.md's tier-divorce item is about vector cels
*acquiring* raster tiers when raster features touch them — a real cleanup, but not a per-layer tax,
and not a blocker here.

**The actual tax is the render cache, and it is per empty layer.** `VectorCanvas.render()` has no
empty early-out ([VectorLayer.swift:1070](PaintSoftware/Engine/VectorLayer.swift:1070)): with zero
elements it still runs a full canvas-sized `UIGraphicsImageRenderer` and retains the result in
`cachedImage`. It is reached eagerly — `StrokeCanvasView.vectorCanvas` has `didSet { refreshDisplay() }`,
and `refreshDisplay()` calls `render()` — so the moment an empty vector layer is reconciled into the
view tree it holds **16.8 MB of transparent pixels at 2048², 64 MB at 4000²**. That is true today;
making vector the default multiplies it by every layer in every new project.

Fix, and it is small:

- Early-out in `render()`/`renderLocalContent()` when the display list is empty *and* the transform
  is identity.
- Add `renderIfNonEmpty() -> UIImage?` for the display path, so `StrokeCanvasView.refreshDisplay`
  sets `imageView.image = nil` — cheaper for Core Animation than a transparent bitmap.
- Keep `render() -> UIImage` non-optional for its ~10 existing callers by returning a shared 1×1
  transparent image; drawn stretched into the canvas rect it is visually identical and costs nothing.
- Pin it: a test asserting an empty `VectorCanvas` retains no canvas-sized allocation after a
  display refresh. `PerfBaselineTests` already measures retained bytes this way.

**Do this before flipping the default**, not after.

## 9. Background rendering

Aimed at the future video sequencer (many shots, many scenes chained). **Decision: build the
substrate now, the thread and the disk cache when the sequencer exists.** The substrate is not
speculative work — the compositor needs it anyway to avoid recompositing constantly.

### 9.1 Now — the substrate

1. **Propagating content versions.** Every node carries `contentVersion`, combining its own state
   with its children's. A leaf edit bumps only its ancestors; unrelated subtrees keep their caches.
   Cached composites key on it.
2. **Frame-scoped invalidation, which falls out of data that already exists.** A cel covers
   `[startFrame, startFrame + frameCount)`, so editing it invalidates exactly those frames and no
   others. That *is* "modify one frame, re-render one frame" — no new bookkeeping required.
3. **A pure, snapshot-driven entry point:** `composite(RenderRequest) -> Texture`, where the request
   carries an immutable tree snapshot, the frame, the canvas size, and a quality. No `@Published`
   reads, no UIKit view access, no live `RasterLayerTexture`/`VectorCanvas` reads.

Point 3 is the one that must be right from the start. The composite currently runs on the main actor
*specifically because* it reads live texture objects — `ProjectStore` documents the rule it is
preserving: "the background queue sees no shared mutable state"
([ProjectStore.swift:178](PaintSoftware/Services/ProjectStore.swift:178)). Building the compositor
against a snapshot from day one costs almost nothing and is the difference between adding a thread
later and rewriting for one.

### 9.2 Later — the renderer

4. **Priority queue**: current frame → neighbours (scrub-ahead) → rest of the shot. `MTLDevice` and
   `MTLCommandQueue` are thread-safe, so GPU work parallelises; what needs the thread is
   orchestration, readback, and encode.
5. **Disk-backed LRU, not RAM — this is the hard constraint.** At 2048², one frame is 16.8 MB, so
   24 fps × 10 s = 240 frames = **4 GB**; at 4000² the same shot is 15 GB. Baked frames must be
   compressed to disk with a small in-memory LRU of recent ones. Any design that holds baked frames
   as raw textures dies on the first real sequence.
6. Bake at the shot boundary, evict on edit via the same frame-scoped invalidation as (2).

## 10. Still open

1. **Mask threshold constant** (§6.3) — starting at 0.5, tunable once there is something to look at.
2. **Compositor node ops** — §7 lists the *effects*; the multi-input ops themselves (Mix, and which
   others take 2+ inputs) want a pass once the node UI exists and there is something to try them on.
3. **Group visibility migration** (§4.1) — whether projects saved under the old write-through
   behaviour need a one-time migration, or whether letting them load as-is is fine. Leaning as-is:
   the write-through already happened at save time, so those projects are self-consistent.

## 11. Build order

Foundation first — nothing user-visible until the compositor is proven, so that every feature after
it is small and none of them fight a moving substrate.

| # | work | done when |
|---|---|---|
| ~~**0**~~ | ~~Empty-vector render early-out (§8.1), then vector-as-default (§8)~~ | **done** |
| ~~**1**~~ | ~~`RenderNode` derivation + characterization tests~~ | **done** |
| ~~**2**~~ | ~~Metal compositor behind a flag; snapshot-driven entry point (§9.1)~~ | **done** — both backends agree byte for byte, delta 0 |
| **3** | ~~Delete `PixelOps.compositeCanvas`~~ **done**; swap in the sandwich (§5.2) — **not started** | thumbnail on one path ✓, `PerfBaselineTests` green ✓; sandwich outstanding |
| **4** | Group properties: isolated/pass-through, opacity, visibility migration (§4.1–4.2) | groups composite as parentheses |
| **5** | Tier 1 blend modes on layers and groups (§7) | the shader `switch` plus UI |
| **6** | Alpha masks (§6), incl. `MaskParityLogicTests` | raster and vector mask pixel-identically |
| **7** | Tier 2 blend modes | |
| **8** | Compositor nodes: slot-as-folder storage, panel chrome (§4.3) | a 2-input Mix node renders |
| **9** | Tier 3 effects, as layer *and* node (§4.4, §7) | cheap per-pixel set first, then the multi-pass ones |

Phases 0–3 are the risky ones; 4 onward are additive. §9.2's background renderer stays deferred
until the sequencer exists — only §9.1's substrate is in scope here, and it landed inside phase 2.

**The sandwich is the open question in phase 3.** It rewrites the live canvas, which is the most
latency-critical code in the app, and nothing consumes it until phase 5 gives a layer a blend mode —
the compositor cannot drive the live canvas usefully before there is something Core Animation cannot
already express. The measured case for deferring it to phase 5 is in `PerfBaselineTests`: at 2048²
with six layers the `@MainActor` snapshot costs 276 ms against an 84 ms CPU composite, so the
expensive half is building the snapshot, not compositing it, and a cache of composites does not
address that. Deciding this is what phase 4 should start from.
