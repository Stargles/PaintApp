# Layer Compositing

Plan for tree-ordered groups, **compositor nodes**, alpha masks, and blend / effect layers — which
are all one project, because they all need the same missing thing. **Phases 0–5b, 6a and 7 of §11 are
built and green; 6b is not.** §3 is the decisions; §10 is what is still open; §11 is what remains.

## 1. Why these are one project

The app had no compositor: "compositing" was two unrelated implementations, neither of which could
express any of this. [`Compositor`](PaintSoftware/Engine/Compositor.swift) is now the offline one —
a tree walk over an immutable `RenderRequest`, with a CoreGraphics reference and a Metal backend
behind a flag that agree byte for byte. The live canvas is unchanged:

| path | where | how |
|---|---|---|
| **Live canvas** | `CanvasView.reconcileLayers` ([CanvasView.swift:466](PaintSoftware/Views/CanvasView.swift:466)) | one `LayerHostView` per layer, all siblings in one flat container, z-order by `bringSubviewToFront`, per-layer `isHidden` + `alpha` — each now folding in every enclosing group's. **Core Animation does the compositing**, always source-over. |
| **Offline** | `Compositor.composite` | tree walk over a snapshot. One consumer: the project thumbnail. |

A folder is a compositing unit as of phase 4: it carries an opacity, a blend mode and an isolation
flag, and its `isVisible` gates its subtree instead of being written through to it. What is left is
the live canvas half:

- **Group opacity is exact offline and approximate on the live canvas.** `effectiveOpacity` folds a
  group's opacity into each child, which differs from fading the group's finished composite wherever
  children overlap. Core Animation, handed one flat sibling per layer, cannot do better; §5.2's
  sandwich is what closes it.
- **There is no seam for a blend mode on the live canvas at all.** Core Animation offers no per-view
  Multiply against arbitrary siblings, and the compositor does not drive the live canvas yet — the
  same sandwich, and the reason it now rides with phase 5's blend modes.

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

`LayerFolder` carries `opacity`, `blendMode` and `isIsolated`, persisted in `FolderManifest` and each
defaulted to its identity, so existing projects decode unchanged. `alphaMask` is **not** among them —
§6.2 puts a mask on `Layer` and `LayerFolder` together, and half of it early would only be reshaped
there. Every field decodes with `decodeIfPresent`, so a later additive one costs no migration.

`toggleFolderVisibility` no longer writes through to children: the group's own `isVisible` gates its
subtree. That write-through was destructive all along — hiding a group and re-showing it clobbered
whichever layers inside it the artist had hidden by hand.

**The migration (decided: migrate).** Loading an old project as-is looked safe because
the write-through already happened at save time, so those documents are self-consistent — but only
until the artist un-hides the group, at which point nothing comes back, because every child is still
independently hidden and nothing on screen explains why. So a folder that decodes *without* the
group-property keys and is hidden has its descendants shown, at any depth; the folder's own flag,
the one piece the artist actually chose, is left alone. Nothing is lost that the write-through had
not already destroyed. The signal is the absence of `opacity`, which is why `FolderManifest` writes
it unconditionally — omitting it when it happens to be 1 would re-arm a one-time migration forever.

Saved `ViewPreset`s need the same treatment, which is **a correction to an earlier draft of this
section**: a preset written under the write-through records every child of a hidden group as hidden,
so applying one re-creates exactly the state the migration cleared. Fixing the document alone would
mean the group comes back once and empties again the next time the artist flips views.

### 4.2 Isolated groups

Children start from transparent and blend only against each other; the finished buffer composites
into the parent with the group's own opacity / blend / mask. A `multiply` child at the bottom of a
group multiplies against nothing and therefore reads as normal — that is correct and intended.

**Pass-through** (children blend against the backdrop below the group, as Photoshop and CSP default)
is a per-group toggle in the folder's options panel, off by default.

**The toggle currently changes no pixel, and that is arithmetic rather than a gap.** With every child
at `.normal`, source-over is associative: children composited onto transparency and then drawn over
the backdrop equal children drawn straight onto it. Isolation only becomes observable when something
inside the group blends, i.e. in phase 5. It is stored, persisted and honoured by both backends now
so that phase 5 adds blend modes and nothing else — but the control ships ahead of its effect, which
is a product call worth revisiting if that reads badly.

`RenderNode.needsOwnBuffer` is where "does this group cost an intermediate buffer" is decided, once,
for both backends — previously it was two spellings of "opacity is not 1", one per backend, which
phase 5's extra clauses would have turned from duplication into disagreement. A buffer is not a
tunable: an intermediate re-quantizes to 8-bit once per nesting level, so allocating one where it is
not needed changes bytes, not just cost.

### 4.3 Compositor nodes

A second way to composite, alongside blend modes: a node added from the layers menu that takes **two
or more inputs below it**, each input holding layers or further nodes.

**A group is this same thing with one input slot.** One renderer covers both; a "folder" is
`.node(op: .stack, inputs: [children])`.

**Each input slot derives as its own `RenderNode`**, rather than being folded into a shared
accumulator the way an ordinary folder's children are — which is what makes "always isolated"
expressible at all, and is why a slot reads its own opacity, blend mode and mask off the folder the
same way any folder does. **Slot 0 is the backdrop, and it is the lowest row**: a Mix is "slot 1
composited over slot 0", the direction a plain stack already reads, so `inputSlots(ofNode:)` always
returns slot 0 first and the panel presents Input B above Input A for the same reason it presents any
higher layer above a lower one. (A slot's own *blend mode* is the one field this does not make live —
every slot draws into a backdrop the fold has just zero-filled, so it always reads as Normal by §4.2's
already-settled rule for the bottom of an isolated container, structural here rather than incidental;
the panel does not offer it a control for exactly that reason.)

**Storage — no new tree arithmetic, guarded in three places rather than the one this section used to
admit.** A node's input slot is stored as an ordinary `LayerFolder`, auto-created and tagged with its
owning node and slot index, and:

- **undeletable** — `CanvasManager.canDeleteFolder`/`deleteFolder` refuse it
  (`testDeletingAnInputSlotIsRefused`), because a slot exists because its op's arity says so, and
  deleting one would leave the node an operand short with nothing left to say why;
- **fixed in the panel** — `canRestackFolder` refuses to let a slot be dragged out of its node or
  reordered among its siblings (`testDraggingAnInputSlotOutOfItsNodeIsRefused`), because a slot's
  position among its siblings *is* its index; letting a drag move it would leave the stored index and
  the presented order as two answers to one question. An operand is reordered by moving what is
  *inside* its slot, never the slot itself;
- and **ranked by index while empty**, which is the one this section did not admit. An empty folder
  ordinarily floats to the top of its container — correct for an ordinary folder, wrong for a slot:
  filling Input B before Input A would otherwise float the still-empty Input A above it and silently
  invert which one is the backdrop. `containerEntries` ranks an unfilled slot by its index instead,
  fixed by `testFillingTheUpperSlotFirstStillLeavesInputAAsTheBackdrop` — do not undo it.

So containment, restack and the panel's row generation still reuse the existing machinery, but not
*unchanged*: the three guards above are new logic standing in front of it, not new arithmetic inside
it. The contiguity invariant itself does generalise cleanly, exactly as claimed — each slot is a
contiguous span, and the node's span is the union of its adjacent slots' spans.

```
▼ [Node] Mix                    ← CompositorNode row
   ▼ Input B                    ← slot folder (undeletable) — higher slot, presents on top
       Layer 1
   ▼ Input A                    ← slot 0, the backdrop — presents at the bottom
       Layer 3
       Layer 2
```

**Arity** is declared by the op: `.fixed(2)` for Mix, `.variadic(min: 2)` for Add/Max. Variadic nodes
get add/remove-slot controls. An input slot is **always isolated** — otherwise "input" is meaningless.

**Arity is a property of a whole document, not of every shape a node can take mid-gesture.** §5.2's
sandwich cuts the tree at the active leaf, and cutting a `.fixed(2)` Mix produces a one-slot Mix on
one side of the cut — a shape its own arity says cannot exist
(`SandwichLogicTests.testAHalfOfATwoSlotMixKeepsTheOpAndLosesASlot`). Both backends fold it correctly
regardless (`CompositorParityLogicTests.testAMixWithOneSlotIsThatSlotAssembled`), which is what makes
the sandwich legal — but no validator downstream may assume a node's slot count still matches its
op's arity. A sandwich half is not a document.

`Mix(A, B, .multiply)` is the same math as stacking B over A with blend mode multiply — **measured
now, not asserted**: 0 on every channel, for all 25 modes, on both backends
(`CompositorParityLogicTests.testMixIsTheSameMathAsStackingTheUpperSlotOverTheLowerOne`). A channel
step was the expected answer, the same reason `testNestedGroupOpacityCompounds` needs a tolerance: a
Mix runs slot 1 through a buffer of its own before folding it, one more 8-bit premultiplied
requantization than the stack pays. It comes out exact because that extra step is a *copy* — slot 1
composited onto transparency is lossless in premultiplied 8-bit, so the fold receives the identical
bytes the stack hands its blend. No kernel closes that gap, because there was never one open; none
should be added.

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

**Shipped in phase 5b, and it has two states rather than one.** The owner's scope decision is *exact
at rest, snaps on lift* — not mid-stroke fidelity.

At rest the canvas is a single `composite(full)` with every layer host blanked, so every blend mode
and every nesting is exact and byte-identical to the thumbnail. Only while a dab is down does the
three-view structure take over:

```
[ composite of everything BELOW the active layer ]   ← cached texture
[ the active layer's live stroke view            ]   ← Core Animation, unchanged, zero added latency
[ composite of everything ABOVE the active layer ]   ← cached texture
```

Stamping a dab invalidates neither cached texture, so the drawing path never enters the compositor.
The textures rebuild only when something other than the live stroke changes — layer switch, blend
change, mask edit, playhead move, undo. The mechanism is one rule: the active layer's content version
is in the invalidation key *only while no stroke is in progress*, which freezes the key for the dab's
duration and moves it on lift.

Two things are deliberately approximate for the dab's duration, both snapping correct on lift, both
pinned at their measured deltas by `SandwichLogicTests`: the active layer's own blend mode renders as
Normal (delta 127), and so do any layers above it (127), because a texture composited onto
transparency has no backdrop to blend against. An active layer inside a faded group drifts in alpha
too, not only colour (64). Recovering the layers above exactly needs a `backdrop: CGImage?` on
`RenderRequest` honoured by both backends, plus a per-pixel unpremultiply against it — composite the
above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from the same stack over
transparency, emit `αs = c`, `Cs = (R − B(1−c))/c`. Deferred, not unsolved.

**The engage switch is the risk containment.** `[RenderNode].needsCompositorOnCanvas` is false for
any document with no blend modes and no faded or isolated group, and such a document keeps Core
Animation's flat-sibling path untouched — it cannot regress. `LayerUITests` pins that.

**Blanking a host is a `CALayer` mask, never `isHidden`.** `UIView.hitTest` returns nil for a hidden,
`alpha < 0.01`, or interaction-disabled view, so a blanked *active* host would swallow the first
touch of every stroke with no error to show for it — `UIView.alpha` and `CALayer.opacity` are the
same property, so neither is an escape. UIKit does not consult masks when hit-testing.

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

**Live stroke inside a blended group:** phase 5b shipped the *fallback* — the live
stroke composites straight over the cached texture and snaps correct on lift — and not the
per-frame subtree recomposite, which nothing has yet needed. `split(atLeaf:)` keeps an enclosing
group's properties on **both** half-groups, so the middle view must carry the folded
`effectiveOpacity(ofLayer:)` for the halves to line up; changing one without the other breaks the
delta-0 identity. Masks do not need any of this; they have an exact answer (§6.4).

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

**What a sandwich rebuild costs, measured in phase 5b.** 2048², six layers, CoreGraphics, warmed,
median of nine: the `@MainActor` snapshot half is **0.1 ms** and the three composites are **~55 ms**.
The snapshot is no longer the expensive half — memoizing `PixelOps.rasterize` (`1e4d7d1`) retired the
276 ms that earlier drafts of this document quoted, because a layer switch, blend change or stroke
lift touches no cel content and so hits the memo on every leaf.

That leaves ~55 ms of composite as the whole cost, which is one dropped frame at 60 Hz and several at
120 Hz — **so the off-main rebuild is load-bearing, not incidental**, and so is showing the previous
images until the new ones land. Both grow with layer count and with canvas size, so the structure
matters more at 4000², not less.

**What a buffer actually costs, measured in phase 4.** Six levels of nesting: 41.6 ms flat, 46.0 ms
transparent, **1071.7 ms once every level buffers** — roughly 25× a whole flat composite, from ~400 MB
of intermediates. That is the number behind "a buffer is not a tunable" (§4.2) and behind the texture
pool above; it is also why `needsOwnBuffer` names only the cases that genuinely change the picture.

The standing perf case was **deliberately not kept**: its ~400 MB of intermediates pushed
`InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` from 0.073 s and passing to
8.98 s and failing whenever the two shared a runner process. Worth knowing before adding any heavy
case to the fast tier — the failure appears in an unrelated suite and looks nothing like its cause.

## 6. Alpha masks

### 6.1 Render-time, never baked — including raster

**The mask is resolved at render time and never written into the masked layer's pixels.** The layer
keeps its full buffer; the compositor multiplies its alpha by the mask when drawing it, so "mask on →
draw → change the source → draw again" re-clips *all* the content, not just what was laid down since.
Raster and vector share the one non-destructive path — cheaper than a destructive one, since the mask
is cached once per distinct mask and shared by every layer using it rather than stored per layer.
"Apply Mask" stays available as an explicit, opt-in bake for artists who want the pixels gone.

**Masks agree between the backends at delta 0, by construction.** §6.3's threshold is a step function,
so a source alpha differing between backends by even the single channel step the blend modes carry
(§11) would land on opposite sides of it. `MaskResolver` sidesteps the question by resolving through
the CoreGraphics reference regardless of which backend asked; the GPU only multiplies the result in.

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
- **`RenderNode.masks` is a list, not one mask.** A layer that both carries its own `AlphaMask` and
  clips to below (§7) carries two; the compositor applies them in sequence, a product of coverages, so
  they intersect and no precedence rule between them is needed.
- The resolved mask is cached per distinct mask, shared by every layer using it, keyed on
  `LayerContentVersion` (`RenderRequest.swift`) — the model-keyed content version phase 5b needed for
  the sandwich, moved out of `CanvasView.Coordinator` once `MaskResolver` needed the same answer.

### 6.3 Binary, with a threshold

The mask is a boolean coverage test on source alpha, not the source's own alpha ramp: `mask =
sourceAlpha > threshold`. A literal `alpha > 0` would make the mask substantially larger than the
stroke looks, since the default `softRound` brush's dab is a radial gradient falling to alpha ≈ 0
across its whole radius — threshold ≈ 0.5 tracks the visually solid part of a stroke instead, and
reduces to `> 0` for a hard brush. A narrow smoothstep across the threshold antialiases the resulting
edge (a hard boolean edge stair-steps on diagonals) without reintroducing the source's own falloff.

Both constants live in `Models/AlphaMask.swift`: `AlphaMask.threshold` (0.5) and
`AlphaMask.antialiasHalfWidth` (0.05), feeding the one function that defines the mask,
`coverage(forSourceAlpha:)`.

### 6.4 Live feedback while drawing

A mask applied only on lift reproduces the selection clip's glitch — ink visibly crossing the
boundary and snapping back. It does not have to: **the mask is static for the duration of a stroke**,
so the live host carries the resolved mask as a `CALayer.mask`, resolved once at the stroke's first
touch. Core Animation applies it in hardware, and the agreement with the compositor is literal
rather than approximate: both sides call `MaskResolver.coverage` with the same masks over a request
carrying the same `maskStacks` and content versions, so they get back *the same `ResolvedMask`
object*, and `makeMaskImage()`'s alpha is its `coverage` byte for byte. Nested clips agree byte for
byte too, against the expectation that they would not: the compositor clips the leaf, quantizes,
then clips the assembled group and quantizes again, where the live path multiplies the two coverages
and quantizes once. Measured difference across two genuinely crossing feathered edges is 0, and it
is pinned as an equality so a future drift is a decision rather than slack.

Four things the build settled that the paragraph above does not imply:

- **The mask goes on the host's content sublayers, never on `LayerHostView.layer`** — §5.2's blanking
  owns that slot, and a collision there fails silently in whichever direction install order decides.
  All three content views are masked, not only `strokeView`: mid-stroke the host is in neither
  sandwich half, so its baked and fill tiers are as unclipped as its live ink.
- **Every enclosing group's mask is in the live chain** (`RenderNode.masksClipping(leafAt:in:)`).
  The compositor clips a group's assembled buffer, which mid-stroke does not exist — so the leaf's
  own list alone would move the glitch one level up rather than remove it.
- Install and release ride on the same predicate as blanking, not on the touch callbacks: trap 2 in
  `updateSandwich` keeps the mid-stroke picture up until the rebuild lift asked for lands, and
  releasing on touch-up would drop the clip while the host is still what is on screen.
- **The mask image is canvas-space and needs no zoom compensation**, which was checked rather than
  hoped for: `containerView.bounds` is the canvas size outright and every content view is pinned
  edge-to-edge to it, and zoom/pan is a transform on `containerView` — an *ancestor*, which scales a
  layer and its mask together. Blanking has never needed a zoom clause for the same reason. A vector
  layer's own transform is baked into the rendered pixels rather than applied to the view, so it
  does not reach this question either.

**`MaskResolver.apply` is the cost to watch**, measured at 2048² by
`PerfBaselineTests.testMaskedCompositeCostAtCanvasResolution` (gated behind `PAINT_PERF_HEAVY`; it is
36 s and a 615 MB peak). ~32 ms per clipped node per composite optimised, and ~62x that at `-Onone`
— which is what the scheme's Run configuration builds, so it is what the iPad runs today.

Two limits a later phase inherits:

- **A `.preview`-quality composite would stop sharing the resolution.** `RenderQuality` is in
  `MaskResolver`'s cache key and the live path asks at `.full`, which is what the sandwich rebuild
  uses today; if §9.2's background renderer ever composites at `.preview` the two resolve separate
  coverages and the byte-for-byte agreement above is no longer structural.
- **The disengaged path carries no mask at all**, at rest or mid-stroke. Reachable only through
  `isSandwichEngaged`'s floating-piece and in-between escape hatches — drawing is blocked outright
  during the first — and pre-existing rather than introduced by §6.4.

### 6.5 UI

**Mask-edit mode is modal state on `CanvasManager`** (`maskEditTarget`), not view `@State`, so the
layer rows can double as the source picker and the live canvas can dim everything that is not a
legal source while a session is open. A Mask toggle sits beside Fill Reference in `LayerOptionsPanel`
and beside Pass Through in `FolderOptionsPanel` — §6.2 masks groups too, so both menus carry it.
Turning it on enters the session; the panel header becomes a "Mask Sources — *name*" bar with a
**Done** exit, since the options popover that opened the session is long closed by then.

- **The picker filters through the same `canMask` cycle rule derivation uses**, not a second copy of
  it, so it cannot offer a source the engine would then ignore (§6.2).
- **Structural edits are refused for the duration** — swipe delete/duplicate, long-press reorder,
  pinch-merge. Allowing one would nest it inside the session's open `beginStructureGesture` bracket
  rather than reject it, which is a stranger outcome than not starting.
- **Picking any row force-enables the mask.** So re-opening the picker on a mask paused from the
  panel and touching a row silently un-pauses it. Simpler than threading a stay-paused mode through,
  and the one place the session semantics could reasonably want a different answer.
- Fill's flood need not be bounded by the mask — spill outside is invisible anyway, so it is a
  nicety, deferrable.
- **`MaskParityLogicTests`**: a raster layer and a vector layer with identical content and identical
  masks composite to pixel-identical output. Precedent: `RasterVectorParityLogicTests`.

### 6.6 Lifecycle

- **A mask ignores its source's visibility** — a hidden source still contributes its alpha, so a
  dedicated invisible mask-shape layer works and an eye toggle never silently repaints. Unlike
  `isFillReference`, which hiding a layer does clear.
- **A deleted source drops out of `sources`**; an emptied list disables the mask rather than clipping
  everything. Undo restores both together (`withStructureUndo`).
- **Mask edits coalesce into one undo step per mask-edit session** — `beginMaskEdit`/`endMaskEdit`
  bracket with `beginStructureGesture`/`commitStructureGesture` and every edit between them nests
  through `withStructureUndo`'s depth guard, the same mechanism the opacity slider uses.

## 7. Blend modes and effects — the build list

Confirmed: **Tier 1 + Tier 2 + Tier 3, minus Kuwahara and Displacement/Warp, plus Sobel.**

**Tier 1 (fourteen modes) and Tier 2 (eleven modes) have both shipped**, on layers and groups, in both
backends — cases in `BlendMode`, math in `Composite.metal`'s `blendChannels` on the GPU and in
`CoreGraphicsCompositor`'s `CGBlendMode` primitives plus `handRolledChannel`/`handRolledTriple` on the
CPU (§11 below has the correction on which mode uses which). **Clip to below** ships alongside them but
is not a blend: `CanvasManager.renderNodes` derives it into `.normal` plus a mask whose source is the
entry directly beneath, so it never reaches a backend as a blend mode at all — no shader case, no
`CGBlendMode`.

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

Sequencing: Tier 3 splits into "cheap LUT/per-pixel" (one item covering the first six), then the two
that need the multi-pass buffer (blur, bloom), with Sobel/Sharpen/Outline alongside them.

**The first six have shipped as kernels** — `Effect` in [Effect.swift](PaintSoftware/Models/Effect.swift),
`applyEffect` in `Composite.metal`, `EffectReference` as the CPU reference, measured against each other
by `EffectParityLogicTests`. Curves ship alongside Levels: both resolve to the same 256-entry table in
Swift, so a third curve shape is a case in `Effect` and no shader change. **Neither §4.4 wrapper exists
yet** — nothing puts an effect into the tree, so no document can hold one; the wrappers are what add
`var effect: Effect?` to the manifest, with one `decodeIfPresent` and no migration.

Where an effect had a published definition it follows it, and the choice is recorded next to the code:
Photoshop/GIMP Levels, **CSS Filter Effects Level 1** for brightness and contrast, W3C Compositing
Level 1's `Lum` for the gradient map's index (the weighting the non-separable blend modes already use),
Fritsch–Carlson for the curve so a tone curve cannot overshoot. HSV is a real HSV rotation and
deliberately **not** CSS `hue-rotate()`'s matrix.

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

1. **Mask threshold and antialias constants** (§6.3) — `AlphaMask.threshold` (0.5) and
   `AlphaMask.antialiasHalfWidth` (0.05). **Unblocked, not done**: 6b shipped the UI and the live
   stroke clip, so there is now something to look at and nobody has looked. Tune against a soft
   brush on the iPad, where §6.4's `-Onone` cost is also felt. "Clip to below" itself shipped in 6a,
   as a mask whose source is implied.
2. **Compositor node ops** — §7 lists the *effects*; the multi-input ops themselves (Mix, and which
   others take 2+ inputs) want a pass once the node UI exists and there is something to try them on.

## 11. Build order

Foundation first — nothing user-visible until the compositor is proven, so that every feature after
it is small and none of them fight a moving substrate.

| # | work | done when |
|---|---|---|
| ~~**0**~~ | ~~Empty-vector render early-out (§8.1), then vector-as-default (§8)~~ | **done** |
| ~~**1**~~ | ~~`RenderNode` derivation + characterization tests~~ | **done** |
| ~~**2**~~ | ~~Metal compositor behind a flag; snapshot-driven entry point (§9.1)~~ | **done** — CoreGraphics and Metal agree exactly on the walk and on `.normal` (delta 0); blend modes hold to a measured ≤1 channel step, masks to exactly 0 |
| ~~**3**~~ | ~~Delete `PixelOps.compositeCanvas`~~ | **done** — thumbnail on one path, `PerfBaselineTests` green |
| ~~**4**~~ | ~~Group properties: isolated/pass-through, opacity, visibility migration (§4.1–4.2)~~ | **done** — groups composite as parentheses, both backends on one buffer rule |
| ~~**5a**~~ | ~~Tier 1 blend modes on layers and groups (§7)~~ | **done** — fourteen modes, both backends, picker and row badge |
| ~~**5b**~~ | ~~§5.2's sandwich, so the live canvas shows a blended layer~~ | **done** — exact at rest, snaps on lift |
| ~~**6**~~ | ~~Alpha masks (§6), incl. `MaskParityLogicTests`~~ | **done** — engine resolves masks in both backends at delta 0, raster and vector pixel-identically; the mask-edit UI picks sources through the same cycle rule; the live stroke is clipped by the same `ResolvedMask` object the compositor applies |
| ~~**7**~~ | ~~Tier 2 blend modes~~ | **done** — eleven modes, both backends, measured against the spec |
| **8** | Compositor nodes: slot-as-folder storage, panel chrome (§4.3) | a 2-input Mix node renders |
| **9** | Tier 3 effects, as layer *and* node (§4.4, §7) | cheap per-pixel set first, then the multi-pass ones |

Phases 0–3 are the risky ones; 4 onward are additive. §9.2's background renderer stays deferred
until the sequencer exists — only §9.1's substrate is in scope here, and it landed inside phase 2.

**One correction to §5.1 that phase 5 measured, and phase 7 tested again rather than assuming it would
repeat.** "The CoreGraphics one is the reference … the byte-for-byte definition of correct" holds for
the *walk* — order, buffers, alpha — and not for every blend function. `CGBlendMode`'s colorDodge,
colorBurn and softLight are the PDF 1.4 originals and disagree with W3C Compositing Level 1 by up to
249/255; the app follows the spec, which is what Photoshop and CSP do, and hand-rolls those three on
the CPU (`BlendMode.handRolledChannel`).

**Tier 2 only rides the primitive once.** Six modes — vividLight, pinLight, linearBurn, divide,
lighterColor, darkerColor — are hand-rolled because `CGBlendMode` has no case for them at all. Of the
five that do have a case, `coreGraphicsBlendMode` keeps it for `exclusion` alone (measured delta 0, a
real CoreGraphics-versus-spec result); hue, saturation, color and luminosity are hand-rolled by choice,
not measured disagreement. The GPU-vs-CPU sweep's deltas for those four (hue 1, saturation 0, color 1,
luminosity 1) compare the app's own shader against the app's own hand-rolled CPU, since the CPU already
hand-rolls them — not against `CGBlendMode`. Apple's non-separable primitives remain unmeasured against
the spec; that comparison is open, not concluded either way.

**Deferring the sandwich to phase 5 was right, and the reason generalises.** It rewrites the most
latency-critical code in the app, and until a layer had a blend mode there was nothing for it to
show that Core Animation could not already express — so it would have restructured `reconcileLayers`,
onion-skin z-order, the Move tool's floating piece and per-layer touch routing with no feature able
to demonstrate the result. Phases 6–9 are all additive for the same reason: build the substrate when
something consumes it.
