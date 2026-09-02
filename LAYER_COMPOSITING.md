# Layer Compositing

Plan for tree-ordered groups, **compositor nodes**, alpha masks, and blend / effect layers — which
were all one project, because they all needed the same missing thing. **The build (§11) is closed.**
§3 is the decisions; §10 is what is still open.

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
9. **A mask ignores its source's visibility; fill reference follows it, unless the artist said
   otherwise.** A hidden layer still masks, so a dedicated invisible mask-shape layer works and an eye
   toggle never silently repaints — while fill reference defaults from visibility and is overridden by
   an explicit choice that nothing may recompute. The two differ on purpose. §6.6.
10. **Mask edits coalesce into one undo step per mask-edit session.** §6.6.
11. **Build order is foundation-first**: tree, then compositor, then features. §11.
12. **There are three layer kinds, not four.** `.value` is one kind with two modes, decided by
    whether `Layer.effect` is set — flat colour, or the adjustment-layer wrapper of decision 8. §4.5.
13. **A node's operation is one dropdown**: a blend op (two inputs) or an effect (one). No node has a
    blend mode of its own, and no layer or node carries both an op and a grade. §4.3.

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

A second way to composite, alongside blend modes: a node added from the layers menu that runs an
operation over its inputs and yields one output. The owner's model: *"like a blender node, where there
are layers inside of it which get combined in some kind of operation and then outputted."* How many
inputs is the operation's business — a blend op takes two, an effect op takes one.

**A node's children are its inputs.** One direct child, one input — a layer, a folder, or another
node. There is no separate slot object, and **input index is position**: the bottom child is input 0,
the backdrop, and the one above it is input 1, composited over it. That is the direction a plain
stack already reads, so a two-input node and a two-layer stack agree about which one is on top, and
**dragging one child above the other swaps the operands** — the affordance fixed slots never had.

**A group is this same thing with one input.** One renderer covers both; a "folder" is
`.node(op: .stack, inputs: [children])`, and a node is `inputs: children.map { [$0] }`.

**Each input derives as its own `RenderNode`**, rather than being folded into a shared accumulator
the way an ordinary folder's children are — which is what makes "always isolated" expressible at all,
and is why an input reads its own opacity and mask off the layer or folder it came from the same way
anything else does.

```
▼ [Node] Mix  Multiply         ← CompositorNode row; one dropdown, the op
   ▼ Highlights                ← input 1 — an ordinary folder, presents on top
       Layer 1
     Sketch                    ← input 0, the backdrop — a bare layer is as legal an operand
```

**Two fields the derivation refuses to read, for two different reasons.**

- **An operand's own blend mode**, by geometry. Every input draws into a buffer `fold` has just
  zero-filled, so an operand's mode always blends against transparency and reads as Normal by §4.2's
  rule for the bottom of an isolated container. Stating it in the derivation makes that a contract
  rather than a side effect of how `fold` zeroes its buffers. Opacity and masks beside it stay live —
  they scale what an operand draws regardless of the backdrop
  (`testAnInputsOwnBlendModeIsInertButItsOpacityStillFades`, both backends, every mode).
- **A node's own blend mode**, by decision. A node's output always lands Normal on whatever is
  beneath it, and the panel shows one dropdown per node — Mix Mode, the operation *inside* — because
  two dropdowns on one row read as clutter and the second one's job is still reachable: put the node
  in an ordinary folder and set the folder's mode
  (`testANodesOwnBlendModeIsInertButItsChildrensOpacityAndMasksAreNot`).

**`Clip to below` does not resolve inside a node.** It clips to the entry one step down in the same
container, which inside a node is the *other operand* — a cross-input dependency the isolation rule
exists to prevent. Suppressed in the derivation, measured on pixels in
`testAClipToBelowInputDoesNotClipToTheOtherInput`, with the ordinary-folder case asserted beside it so
the suppression cannot pass by clip-to-below having stopped working.

**Storage — no new tree arithmetic, and now one guard rather than three.** A node is an ordinary
`LayerFolder` carrying `compositorRole = .node(op:)`. Containment, spans, the restack arithmetic and
the panel's rows all reuse the existing machinery. The one thing standing in front of it is **arity**:
a `.mix` is `.fixed(2)`, so a third child is refused — in `canDrop(inContainer:moving:)`, which the
panel reads to decline a drag before it lands, and again in `restackLayer`/`restackFolder`, because a
stale row from before a structural edit goes through the same call. `moving:` is what keeps a
*reorder* inside a full node legal: the count does not grow when the thing being dragged is already a
child. Ordinary folders and variadic ops declare no maximum. The contiguity invariant generalises
unchanged — each input is a contiguous span, and the node's span is the union of its inputs' spans.

**The op dropdown holds blend ops and effects, and an effect op is the arity-1 case.** One dropdown,
two sections: pick a blend and the node takes two inputs; pick one of §7's thirteen effects and it
takes one, grading that input's composite as a unit. That second form is §4.4's node wrapper, and it
needed **no `CompositorOp.effect` case, no backend branch and no Metal change**: it is stored as
`op == .stack` plus `LayerFolder.effect`, because folding one input is exactly what `.stack` already
does and `RenderNode.effect` is already carried off the folder for any op and applied after the fold
by both backends. A whole enum case would have duplicated the grade's storage, forced a branch into
both `fold`s and both halves of `CompositorRole`'s `Codable`, and left two places a grade could live
that have to agree.

Three consequences, each settled:

- **Arity is stated on `LayerFolder.maxInputCount`, not on `CompositorOp.arity`.** `.stack` is
  genuinely variadic; what caps this node at one is the grade hanging beside it, and a `CompositorOp`
  is a value the folder holds and cannot see the folder holding it.
- **The two writers each clear what the other set.** `setNodeEffect` and `setMixBlendMode` are the
  only ones, and the pair must never both be live: an op that both blends two inputs and grades one
  is two unrelated answers to "what does this node do", with nothing to say which runs first.
- **A node already holding two children keeps both when the artist picks an effect**, so
  `maxInputCount` reads 1 against a real count of 2 and the node grades the assembled pair. Nothing
  is destroyed by a dropdown. `canDrop`'s `<` handles the over-count exactly right — no third child
  may land, and reordering the two that are there stays legal.

**Deleting a node promotes its children**, exactly like deleting an ordinary folder. There is no
special case and no `deleteCompositorNode`: that existed only because a promoted *slot* folder would
have been stranded, tagged as input to a node that no longer exists.

**Migration from the slot era.** A node saved before this design is a node folder plus child folders
tagged `{"kind":"slot", …}`. `CompositorRole.decodeIfSupported` reads that tag as *no role*, and the
document becomes a node whose operands are those folders in the order they already sat in — because
`parentFolderID` already named the node and `containerEntries` already ranked them bottom-to-top. The
folders keep their "Input A"/"Input B" names, which is harmless. No migration pass, and the operand
order is asserted rather than assumed
(`testANodeSavedWithInputSlotFoldersOpensWithItsOperandsInSlotOrder`).

**Arity is a property of a whole document, not of every shape a node can take mid-gesture.** §5.2's
sandwich cuts the tree at the active leaf, and cutting a `.fixed(2)` Mix produces a one-input Mix on
one side of the cut — a shape its own arity says cannot exist
(`SandwichLogicTests.testAHalfOfATwoSlotMixKeepsTheOpAndLosesASlot`). Both backends fold it correctly
regardless (`CompositorParityLogicTests.testAMixWithOneSlotIsThatSlotAssembled`), which is what makes
the sandwich legal — but no validator downstream may assume a node's input count still matches its
op's arity. A sandwich half is not a document.

`Mix(A, B, .multiply)` is the same math as stacking B over A with blend mode multiply — **measured
now, not asserted**: 0 on every channel, for all 25 modes, on both backends
(`CompositorParityLogicTests.testMixIsTheSameMathAsStackingTheUpperSlotOverTheLowerOne`). A channel
step was the expected answer, the same reason `testNestedGroupOpacityCompounds` needs a tolerance: a
Mix runs input 1 through a buffer of its own before folding it, one more 8-bit premultiplied
requantization than the stack pays. It comes out exact because that extra step is a *copy* — input 1
composited onto transparency is lossless in premultiplied 8-bit, so the fold receives the identical
bytes the stack hands its blend. No kernel closes that gap, because there was never one open; none
should be added.

That redundancy is the point (it is why Blender has both): the stack is ergonomic for painting, the
graph is ergonomic for effects with more than one input. Do not try to unify them away. **The node
earns its keep only when an input holds more than one layer** — with two single-layer operands it is
literally the stack, which under this design means the artist puts a folder in as one of the two
children.

### 4.4 Effects are both a layer and a node

Every effect in §7 ships in two wrappers over **one shader**:

- **As a stack layer** — a `.value` layer carrying `Layer.effect`, grading everything accumulated
  below it *within its own container*: the Photoshop adjustment-layer model. Fast for the common case.
- **As a 1-input node** — a `.stack` node carrying `LayerFolder.effect` (§4.3), grading that node's
  own composite: the Blender model. Precise, and composes with multi-input nodes.

Only the input-resolution rule differs: *"the accumulated backdrop so far in this container"* versus
*"this node's assembled input."* Both hand the same texture to the same kernel, and both store the
grade in a field named `effect` on the thing that wraps it, so `RenderNode.effect` is one field for
both — the wrapper is the *position in the tree*, not the data. Nothing else in the design branches
on which wrapper produced the input, and keeping it that way is the point.

Container scoping is what keeps the layer form predictable: an effect layer inside a group cannot
reach outside it. That is also what makes an isolated group (§4.2) the right default — the grade
stops at the parenthesis.

**The layer form has no blend mode of its own**, matching §4.3's rule for nodes. The renderer pins an
effect-carrying leaf to `.normal`, so a blend dropdown that stayed live in effect mode would be setting
a value nothing read. §4.5 is where that landed: rather than hiding a separate blend row in effect mode,
the row *is* the effect picker (`valueBlendModeRow`), so there is only ever one control and it can never
disagree with the renderer. Wrap the layer in a folder to blend a grade's result.

**The retired `compositing` kind — read this before touching `LayerKind`'s decoder.** The effect
layer was its own `LayerKind` for one phase, written to disk as the literal string `"compositing"`.
It is not a kind any more, and `LayerKind.decodeMigratingEffectLayers` reads that string as `.value`;
the grade is already sitting in the manifest's own `effect` key, and a non-nil `effect` on a `.value`
layer *is* effect mode, so nothing else in the document needs touching.

**Without that line the whole project fails to open, silently.** `LayerKind` is a bare
`String, Codable` enum with a synthesized decoder, and `decodeIfPresent` substitutes its default only
when the key is *absent* — a key that is present and unparseable throws. That throw escapes
`LayerManifest.init(from:)`, escapes `JSONDecoder.decode`, and lands in `ProjectStore.loadManifest`'s
`try?`, which turns it into nil and makes `load(from:)` return nil for the **entire** document. Not
one lost layer: the artist's project simply refuses to open with nothing anywhere saying why. An
unrecognised string still throws, deliberately — a silent fallback to `.raster` would present a
genuinely corrupt manifest as a layer whose content had been deleted.

**Proxy layers — explicitly deferred, do not build.** The same layer or group appearing in two
positions turns the tree into a DAG, needing cycle detection and a content-keyed render cache so the
shared subtree renders once. Worth noting only because **masks already need both** (a mask references
a subtree from elsewhere in the tree — that is already a DAG edge, §6.2), so when proxies are wanted
the infrastructure will largely exist. Nothing in this plan should assume a node has exactly one
parent.

### 4.5 Value layers

`LayerKind.value` holds no pixels, and is **two things chosen by one field**. With `Layer.effect`
absent it carries `Layer.fill` and *is* one flat colour across the whole canvas, alpha included —
Photoshop's Solid Colour layer. With `Layer.effect` set it is §4.4's stack wrapper — Photoshop's
adjustment layer. `Layer.valueFill` and `Layer.layerEffect` are the two accessors that read the mode
out; nothing else asks.

**One kind with two modes rather than two kinds**, and that is the owner's call rather than a tidying.
The two never coexist on one layer — an adjustment layer that is also a flat colour is not a picture
anyone can describe — so a kind apiece made the mutually-exclusive pair expressible twice, once as
`kind` and once as which payload happened to be set, with nothing keeping them honest. It also made
"change this layer from a grade to a colour" a kind rewrite, which every `kind ==` test in the app has
an opinion about, instead of the one-field edit it now is. The panel follows: **one Blend Mode menu**
listing every blend mode and the thirteen effects together (`LayerPanel.valueBlendModeRow`), not a
segmented control plus a separate picker. There is no "Flat Colour" entry — every blend mode in the
list already clears the effect, so leaving effect mode is picking the mode you want to land in rather
than picking "flat" and then a mode, and Normal sits first where "Flat Colour" used to. The row itself
is never hidden: it shows the effect's name in place of the blend mode's while a grade is set.

**Why the flat colour earns its keep.** `Mix(A, B, mode)` where A and B are single layers is identical
to stacking B over A with that mode (§4.3 says so, and that redundancy is deliberate). A value layer is
the honest answer to "why use a node at all": `Mix(folder-of-drawings, grey 50%, Multiply)` combines
the folder as a unit and *then* halves it, which a flat stack cannot express. It also blends with what
is beneath it like any other leaf, which is the flat-background and tint case.

**The fill resolves in `CanvasManager.leafSnapshots(atFrame:…)`, and that placement is the design.** A value layer
becomes an ordinary `LayerRenderSource` at the frame-aware boundary, so the compositor never learns
value layers exist and neither backend has a case for one. **Keyframed values are wanted eventually
and are deliberately not built** — the seam is what that phase bought: a later phase puts a track
inside `ValueFill`, `resolvedColor(atFrame:)` reads it, and that call site is already passing the
frame.

Two consequences worth stating rather than rediscovering. A value layer is **not a fill-tool reference
by default** (`Layer.isFillReference`): it is opaque everywhere, so the ordinary visibility default
would wall the fill tool in across the entire document. And **as a mask source it is a cliff, not a
gradient** — §6.3's threshold means any alpha above ~28/255 gives full coverage everywhere and
anything below gives none. Harmless, and deliberately not special-cased.

**A value layer and a node auto-rename to follow their effect, and stop the moment the artist does
not.** `hasCustomName` on both `Layer` and `LayerFolder` is the latch: `setNodeEffect` /
`setMixBlendMode` / the value layer's Mode menu rename as they reshape, and a hand-typed name turns
the latch on for good. The reason is sharpest on a node — a node does exactly one thing, so "Mix 1" on
a node since set to Gaussian Blur does not merely read stale, it names an operation the node no longer
performs.

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
sourceAlpha > threshold`. A literal `alpha > 0` would keep every pixel the default `softRound`
brush's dab touches however faintly, since its dab is a radial gradient falling to alpha ≈ 0 across
its whole radius; a threshold instead cuts that faintest skirt away, and reduces to `> 0` for a hard
brush regardless of where it sits. A narrow smoothstep across the threshold antialiases the resulting
edge (a hard boolean edge stair-steps on diagonals) without reintroducing the source's own falloff.

Both constants live in `Models/AlphaMask.swift`: `AlphaMask.threshold` (0.1) and
`AlphaMask.antialiasHalfWidth` (0.01), feeding the one function that defines the mask,
`coverage(forSourceAlpha:)`. Neither was derived — they were judged by eye on the iPad against a soft
brush, in a Release build, and they replaced 0.5/0.05, which had been a reasoned guess that threshold
≈ 0.5 would land on the visually solid part of a stroke. Measurement on hardware disagreed: the
shipped threshold tracks nearly the whole extent of a soft dab rather than only its solid core, so 0.1
sits close to the `> 0` this section argues against, not close to 0.5. The antialias half-width moved
with it to 0.01 — about a third of a pixel of ramp across a soft dab's falloff, so **the smoothstep is
vestigial at the shipped value** rather than serving the anti-stair-stepping purpose the paragraph
above describes for it. The number stays where the owner put it; what moved is the claim made for it.

The two are one setting with an invariant between them, enforced in `AlphaMask.setTuning`: the
half-width is kept strictly below the threshold. At or past it the ramp's low end reaches zero and
every pixel on the canvas picks up partial coverage — a transparent pixel stops being fully masked
out, which is a mask that hides nothing. The sliders reach that easily (half-width to 0.25 against a
threshold floor of 0.1), so the guard lives on the model rather than on the widget, and
`MaskGuardLogicTests` pins the property (`coverage(forSourceAlpha: 0) == 0` everywhere reachable)
rather than the clamp.

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

**An open options menu *is* the mask-edit session for the node it names.** There is no switch to
enter one: the menu already says which layer or group is being edited, so a control inside it saying
"…and mask this one" was a second answer to a question already answered. Every layer and group row
grows two trailing controls for as long as a menu is open — a **mask checkmark**, which is how
sources are picked, and a **fill-reference drop** (§6.6) beside it.

**Both settings live on the rows and nowhere else.** The menu is where a node's own properties are —
blend mode, invert, rename, the structural actions — and the rows are where per-layer answers to the
menu's question are given. A control that appeared in both places would be two ways to say one thing,
which is what the Mask switch was and what the labelled Fill Reference switch beside it became the
moment the rows could answer. `FillSettingsPanel` carries the sentence explaining what the drop does,
since a glyph cannot.

**Mask-edit mode is modal state on `CanvasManager`** (`maskEditTarget`), not view `@State`, so the
rows can double as the picker and the live canvas can dim everything that is not a legal source.
`syncMaskEditSession` is the only way in or out, driven from the one piece of view state that says
which menu is open, so there is no second path to forget. What stays in the menu is what has nowhere
in a row to live: the source count, and `invert`, which belongs to the mask rather than to any one
source.

- **The picker filters through the same `canMask` cycle rule derivation uses**, not a second copy of
  it, so it cannot offer a source the engine would then ignore (§6.2). An illegal row's checkmark is
  dimmed and inert rather than removed, and the node under edit gets its own glyph, since "this is
  what you are editing" reads differently from "this would cycle".
- **Structural edits are refused for the duration** — swipe delete/duplicate, long-press reorder,
  pinch-merge. Allowing one would nest it inside the session's open `beginStructureGesture` bracket
  rather than reject it, which is a stranger outcome than not starting. The menu's *own* structural
  actions (delete, duplicate, merge, rasterize, and the panel's "+") close the session first instead
  of being refused: the artist asked for a delete, not for a picker.
- **A row keeps everything else it had.** The eye, the thumbnail, the opacity slider and the options
  button all stay live, because a session is now the ordinary state of having a menu open rather than
  a mode entered on purpose. That is what makes `beginStructureGesture` nesting load-bearing (§6.6).
- **A row's tap keeps its ordinary meaning** — select, or expand. It meant "pick this as a source"
  only while the picker had no control of its own.
- **Picking a row enables the mask**, which is no longer an override: with the Mask switch gone there
  is no paused state to override, so `isEnabled` is exactly "has sources" — set on the first pick and
  cleared by `dropping(_:)` when the last one goes. Pausing a mask without discarding its list is an
  affordance the app no longer offers; un-checking the sources is how a mask is turned off.
- **A compositor node is a mask target and a mask source like any other folder.** It was excluded
  while §4.3 had input slots — a node held only its slots and a slot only what was dropped into it,
  so neither was content anyone clips. A node composites ordinary children now, and its mask clips
  the folded result (`testAMixNodesMaskClipsTheFoldedResultRatherThanItsSlots`).
- Fill's flood need not be bounded by the mask — spill outside is invisible anyway, so it is a
  nicety, deferrable.
- **`MaskParityLogicTests`**: a raster layer and a vector layer with identical content and identical
  masks composite to pixel-identical output. Precedent: `RasterVectorParityLogicTests`.

### 6.6 Lifecycle

- **A mask ignores its source's visibility** — a hidden source still contributes its alpha, so a
  dedicated invisible mask-shape layer works and an eye toggle never silently repaints. Deliberately
  unlike fill reference below; do not unify them.
- **A deleted source drops out of `sources`**; an emptied list disables the mask rather than clipping
  everything. Undo restores both together (`withStructureUndo`).
- **Mask edits coalesce into one undo step per mask-edit session** — `beginMaskEdit`/`endMaskEdit`
  bracket with `beginStructureGesture`/`commitStructureGesture` and every edit between them nests
  through `withStructureUndo`'s depth guard, the same mechanism the opacity slider uses. The bracket
  opens on the session's **first write**, not on entry: entry is now as ordinary as opening a menu, so
  bracketing there would record an empty step for every menu merely looked at — and creating the empty
  `AlphaMask` that used to give that step something to hold would hang a mask off every node whose
  menu was ever opened.
- **`beginStructureGesture` nests**, the way `withStructureUndo` always has: only the outermost
  bracket captures a baseline and only its close records. The rows stay live under an open menu
  (§6.5), so an opacity drag begins a bracket inside the session's — without the depth the inner
  `begin` overwrites the session's baseline and its `commit` consumes it.

**Fill reference is a decision with a default, and the two are stored apart.** `isFillReference` is
derived: `fillReferenceOverride ?? isVisible`. So a layer nobody has answered for is a boundary when
shown and not when hidden, and a layer somebody *has* answered for keeps that answer through every
visibility change, including while hidden. Only the nil case is ever recomputed.

The distinction is the whole rule, because the effective value cannot carry it: a hidden layer reading
"not a reference" could be either. Four places used to write the effective value through on a
visibility change — `toggleLayerVisibility`, `applyViewPreset`, clearing the view, and the §4.1 load
migration — and each of them silently discarded a choice the artist had made. All four are gone; the
default falls out of the derivation instead. Only the override persists (`LayerManifest`, written just
when it is non-nil), so absence in a manifest *is* "follow the default" and every older project
decodes to the behaviour it already had.

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
Swift, so a third curve shape is a case in `Effect` and no shader change.

**Sobel, Sharpen/unsharp and Outline (phase 9c) have also shipped as kernels**, on the same multi-pass
contract blur and bloom established — no new abstraction. Sobel is one direct 3×3 gather (kind 10);
sharpen is blur's own two passes (sharing its kind, precedented by Levels/Curves) plus a combine pass
shaped exactly like bloom's (kind 11); outline is one direct disc gather, exact Euclidean distance,
outside mode only (kind 12). Each carries the correctness defence the multi-pass blind spot demands —
an impulse response against the published Gx/Gy stencils, the identity at amount 0 plus the exact
relationship `sharpen(r, −1) ≡ blur(r)`, and a hand-counted width-1 spot check (4 painted pixels, not
8) — in `EffectMultiPassLogicTests`, not a parity sweep alone. Outline's colour is EffectParams' first
appended field (`colorR/G/B`, end-of-struct, both declarations); its cost is quadratic, so it is capped
by `Effect.maxOutlineRadius` rather than `maxBlurTaps`.

**All thirteen are now configurable, which they were not before.** `setLayerEffect` shipped with no UI
caller anywhere in `Views/` for two phases, so an effect layer was creatable and stayed the identity
grade forever. `EffectSection.swift` is that caller: one settings menu per effect behind the row's
**Effect Settings ▸**, including the two that needed real editors rather than sliders — a curve editor
for Curves and a stop editor for Gradient Map. Both §4.4 wrappers reach the same menu, since both store
the grade in a field called `effect`.

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

### 8.1 Prerequisite: an empty vector layer was made free

**An empty vector layer's storage was already free** — `Cel.fillImage`/`bakedImage`/`vector` are
nil-by-default optionals ([Cel.swift:12](PaintSoftware/Models/Cel.swift:12)) and creation costs a few
hundred bytes; an earlier draft of this document was wrong to say otherwise. **The actual tax was the
render cache**: `VectorCanvas.render()` had no empty early-out, so an empty layer held 16.8 MB of
transparent pixels at 2048² (64 MB at 4000²) the instant `StrokeCanvasView.vectorCanvas`'s `didSet`
rendered it — and vector-as-default would have multiplied that by every layer in every new project.
Fixed with an early-out in `render()` on an empty display list (deliberately not conditioned on the
transform too — an affine of nothing is still nothing) and `renderIfNonEmpty() -> UIImage?` so the
display path leaves the image view holding `nil` instead of a transparent bitmap.
`PerfBaselineTests` pins that an empty `VectorCanvas` retains no canvas-sized allocation after a
display refresh.

## 9. Background rendering

> **Superseded by [RENDER.md](RENDER.md).** §9.1's items 1 and 2 were never built as described — no node carries a
> content version (`Models/RenderTree.swift:116-118` records the rejection) and nothing inverts a cel's span into a
> dirty-frame map; only item 3, the pure snapshot entry point, shipped. §9.2's renderer is RENDER §3.5-3.7.

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

1. ~~Mask threshold and antialias constants~~ — **closed, and the harness became the feature.** The
   owner asked for the Mask row to open "a mask tune menu in place of the edit menu … also include a
   back button", so `MaskTuningSection` ships behind `LayerPanel.maskRow`/`maskMenu` rather than
   being deleted. The values stay where the owner judged them on the iPad (0.1 / 0.01); §6.3 records
   the guard that now keeps the pair legal. The numbering below is left alone because code comments
   cite these items by number.
2. **Compositor node ops** — §7 lists the *effects*; which ops take 2+ inputs beyond Mix is still
   open, but phase 8 narrowed it sharply. Because `Mix(A,B,mode)` is measured equal to stacking B
   over A with that mode, **every blend mode is already a 2-input op**, and per-input opacity, blend
   and mask cover crossfade and weighting. So the honest candidate list is short: variadic arity as
   pure ergonomics (a variadic Add over N inputs is a chain of `Mix(.add)` and buys only the absence
   of nesting), and a real matte/key op that consumes B as *coverage* rather than as colour, which
   no blend mode expresses. Try both against the shipped node UI before committing. Variadic arity is
   now also the *cheapest* of the three: with input index being position, a variadic op is simply one
   whose `canDrop` cap is absent.
3. ~~Effect as a 1-input node~~ — **closed.** It landed as an *op* in the node's own dropdown
   (§4.3), which is why it cost no enum case and no backend branch. The prediction that the seam was
   already cut held: `RenderNode.effect` carried both wrappers unchanged.
4. ~~§7's last three effects~~ — **closed.** Sobel, sharpen/unsharp and outline ship on the multi-pass
   contract blur and bloom established, with no new abstraction.
5. **A folder's grade cannot reach the mask cache key.** `MaskResolver`'s key is per-*layer*, via
   `stack.leafLayerIndices`, and a folder is not a leaf — so a group used as a mask *source* whose
   effect reshapes coverage (blur, outline, bloom, Sobel, sharpen) can serve a stale mask. Fixing it
   means putting node grades into the key, which is a change of its own rather than an extension of
   the per-layer version. Tracked in [BUGS.md](BUGS.md).

## 11. Build order

Foundation first — nothing user-visible until the compositor was proven, so that every feature after
it stayed small and none of them fought a moving substrate. All ten phases shipped, in order: the
render tree, the Metal backend behind a flag, deleting `PixelOps.compositeCanvas`, group properties,
Tier 1 blend modes, §5.2's sandwich, alpha masks, Tier 2 blend modes, compositor nodes, and Tier 3
effects as both a layer and a node — each additive on what came before, which is why phases 4 onward
carried none of 0–3's risk. `CompositorParityLogicTests`, `MaskParityLogicTests`, `SandwichLogicTests`
and `LayerUITests` are what still pin the guarantees this table used to narrate phase by phase. §9.2's
background renderer stays deferred until the sequencer exists — only §9.1's substrate shipped, inside
phase 2. What remains is in §10 and [BUGS.md](BUGS.md).

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
