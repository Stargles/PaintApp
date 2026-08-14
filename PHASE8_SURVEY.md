# Phase 8 survey — compositor nodes (§4.3)

Read against `origin/main` at `dbbaabc`, worktree
`laptop-tailscale-connection-78ec13`. All citations are `file:line` into files actually opened.

## The three things most likely to bite

### 1. Both compositor backends already loop over N input slots — into one shared buffer

`RenderNode.Content` is already `.node(op: CompositorOp, inputs: [[RenderNode]])`
([RenderTree.swift:60](PaintSoftware/Models/RenderTree.swift#L60)) — a nested array, ready for
arity > 1 at the type level. But **both backends' `.node` case renders every slot sequentially into
one shared accumulator**, which is exactly "stack" semantics and not "combine N independent
composites":

- `CoreGraphicsCompositor.draw`'s buffered path allocates *one* `UIGraphicsImageRenderer` and does
  `for input in inputs { draw(input, of: request, in: bounds, context: inner) }`
  ([Compositor.swift:435-438](PaintSoftware/Engine/Compositor.swift#L435-L438)); the unbuffered
  path does the same directly against the real context
  ([Compositor.swift:419](PaintSoftware/Engine/Compositor.swift#L419)).
- `CompositorMetalEngine.encode`'s buffered path allocates one `groupFront`/`groupBack` pair
  ([MetalCompositor.swift:294](PaintSoftware/Engine/MetalCompositor.swift#L294)) and does
  `for input in inputs { encode(input, ..., front: &groupFront, back: &groupBack, ...) }`
  ([MetalCompositor.swift:301-305](PaintSoftware/Engine/MetalCompositor.swift#L301-L305)).

For arity 1 (every folder today) this is invisible — one slot, nothing to conflate. For a real
2-input Mix, slot A's pixels are already baked into the shared buffer before slot B is drawn, so
there is no point at which "combine A and B" as a distinct operation is expressible — you only get
"draw B over whatever A left behind," which *is* `.stack`, not `Mix`.

The good news, and it's a real simplification: §4.3 states "`Mix(A, B, .multiply)` is deliberately
the same math as stacking B over A with blend mode multiply," and the shader already has exactly
that primitive — `compositeOver` takes one `backdrop`, one `layer`, an opacity and a mode
([Composite.metal:256-266](PaintSoftware/Engine/Composite.metal#L256-L266)), and
`CompositorMetalEngine.over` / `CoreGraphicsCompositor.draw(_:mode:opacity:...)` already wrap it
([MetalCompositor.swift:350-363](PaintSoftware/Engine/MetalCompositor.swift#L350-L363),
[Compositor.swift:465-475](PaintSoftware/Engine/Compositor.swift#L465-L475)). So a 2-input Mix
needs **no new kernel** — it needs each slot rendered into its *own* isolated buffer (transparent
start, per "an input slot is always isolated," §4.3) and then one more `over`/`draw` call folding
slot B's buffer onto slot A's. That's a walk change (one buffer per slot instead of one shared
buffer, plus a `switch op` case beyond `.stack`), not a math change. `needsOwnBuffer`
([RenderTree.swift:135-143](PaintSoftware/Models/RenderTree.swift#L135-L143)) and `enclosesABlend`
([RenderTree.swift:162-167](PaintSoftware/Models/RenderTree.swift#L162-L167)) already iterate
`inputs` generically and need no change themselves.

### 2. Nothing in storage can say "this folder is a node" or "this folder is a slot" — and delete/restack have no concept of undeletable or contiguous-adjacent siblings

`LayerFolder` is, in full: `id, name, isExpanded, isVisible, parentFolderID, opacity, blendMode,
isIsolated, alphaMask` ([LayerFolder.swift:3-40](PaintSoftware/Models/LayerFolder.swift#L3-L40)).
There is no role/kind field. `FolderManifest` mirrors it exactly, field for field
([ProjectManifest.swift:131-196](PaintSoftware/Models/ProjectManifest.swift#L131-L196)), and the
`CanvasManager` ⇄ manifest round-trip is a literal 1:1 map both directions
([ProjectStore.swift:205-210](PaintSoftware/Services/ProjectStore.swift#L205-L210) save,
[ProjectStore.swift:489-493](PaintSoftware/Services/ProjectStore.swift#L489-L493) load). The single
producer of `.node` in the render tree, `renderNodes(inContainer:)`'s `.folder` case, always builds
exactly one slot — `inputs: [renderNodes(inContainer: folder.id)]`
([RenderTree.swift:386](PaintSoftware/Models/RenderTree.swift#L386)) — because there is nothing on
`LayerFolder` yet to tell it there should be more than one, or which op to use instead of the
hardcoded `.stack` ([RenderTree.swift:386](PaintSoftware/Models/RenderTree.swift#L386),
`op: .stack` literal).

Two invariants §4.3 assumes don't exist today and aren't free:

- **Undeletable.** `deleteFolder` unconditionally promotes every child up to the grandparent and
  removes the folder — that's the *only* delete behavior that exists
  ([CanvasManager.swift:927-946](PaintSoftware/Models/CanvasManager.swift#L927-L946)). There is no
  "this folder refuses to be deleted" or "deleting this folder deletes its subtree instead of
  promoting it" anywhere in the model. A `.fixed(2)` Mix node's slot folders need one of those
  behaviors; a `.variadic` node's add/remove-slot controls need the opposite (an explicit,
  deliberate delete-with-contents). Neither exists.
- **Slot contiguity/adjacency.** `restackFolder`/`restackLayer`
  ([CanvasManager+LayerTree.swift:251-300](PaintSoftware/Models/CanvasManager+LayerTree.swift#L251-L300))
  accept an arbitrary `parentFolderID` and anchor for any drag; `clampInsertion`
  ([CanvasManager+LayerTree.swift:235-248](PaintSoftware/Models/CanvasManager+LayerTree.swift#L235-L248))
  only clamps into *one* folder's own span. Nothing stops a layer or an unrelated folder from being
  dropped as a direct child of a node folder (which per §4.3 should contain *only* its slot
  folders), or from landing between two slot folders and breaking "the node's span is the union of
  its adjacent slots' spans." `containerEntries`
  ([CanvasManager+LayerTree.swift:56-71](PaintSoftware/Models/CanvasManager+LayerTree.swift#L56-L71))
  ranks siblings by span with no notion that two of them are a matched pair that must stay adjacent.
  This invariant is new, not partially built.

### 3. The layer-panel row model is binary and can't tell a node/slot folder from an ordinary one

`LayerStackRow` has exactly two cases, `.folder`/`.layer`
([LayerStackRow.swift:7-9](PaintSoftware/Models/LayerStackRow.swift#L7-L9)). Because §4.3's storage
decision puts a node and its slots on the *existing* `LayerFolder` type with no new arithmetic, every
node folder and every slot folder will decode as plain `LayerStackRow.folder` and, unless changed,
render identically to a plain folder: same disclosure chevron, same opacity slider, same
`FolderOptionsPanel` (pass-through toggle + Rename)
([LayerPanel.swift:331](PaintSoftware/Views/LayerPanel.swift#L331),
[LayerPanel.swift:349-364](PaintSoftware/Views/LayerPanel.swift#L349-L364) for the toggle).
`LayerRowModel.init` switches on `LayerStackRow`'s two cases and sets a single `isFolder: Bool`
([LayerStackListView.swift:564-643](PaintSoftware/Views/LayerStackListView.swift#L564-L643),
switch at [598-642](PaintSoftware/Views/LayerStackListView.swift#L598-L642)); `LayerStackCell`
lays itself out as an `if model.isFolder { … } else { … }`
([LayerStackCell.swift:247-325](PaintSoftware/Views/LayerStackCell.swift#L247-L325)), and the cell's
whole geometry (constraints, leading anchors, icon vs. thumbnail) is hand-built around that boolean
([LayerStackCell.swift:69-212](PaintSoftware/Views/LayerStackCell.swift#L69-L212)). Getting a third
visual kind (node header with op/arity chrome, "Input A"/"Input B" slot rows) means widening three
call sites from a boolean branch to a real switch, not adding a new enum case somewhere isolated —
`LayerStackRow` itself, `LayerRowModel.init`, and `LayerStackCell.configure` all need the change
together, plus whatever new field on `LayerFolder` they read to distinguish the three.

Per the task brief: another worker just added mask-edit state to these three UI files on a branch —
expect these citations to have drifted a little by the time you read them; the shapes described
(binary `isFolder`, hand-laid-out constraints) are what to look for, not necessarily the exact line
numbers.

## Doc vs. code

No real disagreement found. §4.1's pseudocode (`RenderNode … .node(id, op: CompositorOp, inputs:
[[RenderNode]])`) is *already* the shipped type, not aspirational — the code comments say so
explicitly: `CompositorOp` "arrive[s] in phase 8 without reshaping anything here"
([RenderTree.swift:30](PaintSoftware/Models/RenderTree.swift#L30)). The doc's "no new tree
arithmetic" claim for storage is the one place I'd push back gently: it's true that containment,
restack, and row generation *mechanically* reuse `LayerFolder`, but two behaviors (undeletable,
adjacent-slot contiguity) that §4.3 leans on are not present anywhere in the current reuse — they
read as free in the doc's phrasing and are actually new guard logic in `CanvasManager+LayerTree.swift`
and `deleteFolder`. Worth calling out to the worker so "no new tree arithmetic" isn't read as "no new
code in the tree-mutation file."

## Inventory, item by item

**1. `RenderNode` today.** Defined [RenderTree.swift:54-101](PaintSoftware/Models/RenderTree.swift#L54-L101):
`id: UUID`, `content: Content` (`.leaf(layerIndex: Int)` or `.node(op: CompositorOp, inputs:
[[RenderNode]])`, [RenderTree.swift:56-61](PaintSoftware/Models/RenderTree.swift#L56-L61)),
`opacity: Double`, `isVisible: Bool`, `blendMode: BlendMode`, `isIsolated: Bool`, `masks:
[AlphaMask] = []` (phase 6a's list, [RenderTree.swift:100](PaintSoftware/Models/RenderTree.swift#L100)).
`CompositorOp` has exactly one case, `.stack`
([RenderTree.swift:31-35](PaintSoftware/Models/RenderTree.swift#L31-L35)). The only place a `.node`
is constructed is `CanvasManager.renderNodes(inContainer:)`'s `.folder` branch
([RenderTree.swift:378-396](PaintSoftware/Models/RenderTree.swift#L378-L396)); it always passes a
single-element `inputs` array (one slot = that folder's contents,
[RenderTree.swift:386](PaintSoftware/Models/RenderTree.swift#L386)) and always `op: .stack`. The
"clip to below" derivation phase 6a added lives right beside it: `masks(ofNode:declared:clippingTo:)`
([RenderTree.swift:414-425](PaintSoftware/Models/RenderTree.swift#L414-L425)) folds a declared mask
and an implicit "clip to below" source into the `masks` list, and `.clipToBelow` is resolved to
`.normal` plus that mask before it ever reaches a `RenderNode`
([RenderTree.swift:370-377](PaintSoftware/Models/RenderTree.swift#L370-L377) for leaves,
[391-395](PaintSoftware/Models/RenderTree.swift#L391-L395) for folders).

Already N-ary-safe without change: `needsOwnBuffer`/`enclosesABlend`
([RenderTree.swift:135-167](PaintSoftware/Models/RenderTree.swift#L135-L167)), `leafLayerIndices`
([RenderTree.swift:170-177](PaintSoftware/Models/RenderTree.swift#L170-L177)), `find`
([RenderTree.swift:200-209](PaintSoftware/Models/RenderTree.swift#L200-L209)), and — notably —
`split(atLeaf:)` for the sandwich, which already loops `inputs.enumerated()` and reasons about
"slots before/after the one holding the leaf"
([RenderTree.swift:282-318](PaintSoftware/Models/RenderTree.swift#L282-L318),
`half(inputs:)` at [328-333](PaintSoftware/Models/RenderTree.swift#L328-L333)). None of that needs
phase 8 changes; only the derivation's constructor and the two backends' walks do.

**2. What slot-as-folder attaches to.** See hard part #2 above for the gap. Structurally relevant
also: `folderSubtree(_:)` ([CanvasManager+LayerTree.swift:90-99](PaintSoftware/Models/CanvasManager+LayerTree.swift#L90-L99))
and `resolvedContainer(ofFolder:)` ([CanvasManager+LayerTree.swift:82-87](PaintSoftware/Models/CanvasManager+LayerTree.swift#L82-L87))
are both cycle-safe and both keyed purely on `parentFolderID` — they'd walk a node's slot folders
the same as any other nesting with no change needed. `groupLayers`
([CanvasManager+LayerTree.swift:305-325](PaintSoftware/Models/CanvasManager+LayerTree.swift#L305-L325))
is the nearest existing precedent for "wrap things in an auto-created folder" (used for the drag-two-
layers-together gesture) and is a reasonable model for "create a node + its slot folders," though it
creates one folder, not the node-plus-N-slots shape §4.3 wants.

**3. Both compositor backends' entry points.** `Compositor.composite(_:)`
([Compositor.swift:49-61](PaintSoftware/Engine/Compositor.swift#L49-L61)) dispatches to
`CoreGraphicsCompositor.composite` ([Compositor.swift:344-358](PaintSoftware/Engine/Compositor.swift#L344-L358))
or `MetalCompositor.composite` → `CompositorMetalEngine.composite`
([MetalCompositor.swift:38-40](PaintSoftware/Engine/MetalCompositor.swift#L38-L40),
[199-238](PaintSoftware/Engine/MetalCompositor.swift#L199-L238)), falling back to CoreGraphics if
Metal declines ([Compositor.swift:53-59](PaintSoftware/Engine/Compositor.swift#L53-L59)). The exact
spot both backends stop being able to express N inputs as anything but "concatenate onto one
buffer" is `CoreGraphicsCompositor.draw`'s `case .node(let op, let inputs):`
([Compositor.swift:398-445](PaintSoftware/Engine/Compositor.swift#L398-L445)) and
`CompositorMetalEngine.encode`'s `case .node(_, let inputs):`
([MetalCompositor.swift:281-318](PaintSoftware/Engine/MetalCompositor.swift#L281-L318)) — see hard
part #1. Masking of an assembled node composite already works generically off the single buffer
(`masked(_:by:of:)` [Compositor.swift:456-461](PaintSoftware/Engine/Compositor.swift#L456-L461);
GPU equivalent `maskTexture`/`apply` [MetalCompositor.swift:324-347](PaintSoftware/Engine/MetalCompositor.swift#L324-L347))
and should carry over once there's a single "assembled" buffer per node again, whatever produced it.
`Composite.metal`'s three kernels — `compositeOver`, `compositeFill`, `compositeMask`
([Composite.metal:256-296](PaintSoftware/Engine/Composite.metal#L256-L296)) — are unary-backdrop
primitives; per the doc's own §4.3 argument, `compositeOver` is sufficient to *combine* two already-
composited slot buffers, so no new kernel is obviously required for a first 2-input Mix.

**4. Persistence.** `FolderManifest`
([ProjectManifest.swift:131-196](PaintSoftware/Models/ProjectManifest.swift#L131-L196)) uses the
established forward-compat pattern throughout: custom `init(from:)`, `decodeIfPresent` per field with
identity defaults ([182-185](PaintSoftware/Models/ProjectManifest.swift#L182-L185)), and one field
(`opacity`) written unconditionally as a migration signal
([ProjectManifest.swift:186-190](PaintSoftware/Models/ProjectManifest.swift#L186-L190)) — the
"absence means pre-feature" convention `ProjectStore.migrateGroupVisibility` reads
([ProjectStore.swift:610-622](PaintSoftware/Services/ProjectStore.swift#L610-L622)). A node/slot role
field would follow the same recipe as `alphaMask` — optional, written only when present, `nil` means
"ordinary folder," no migration needed
([ProjectManifest.swift:146-151](PaintSoftware/Models/ProjectManifest.swift#L146-L151) is the
precedent). The op itself (`.stack` vs. future `.mix`/`.add`) would need its own persisted field on
`FolderManifest`, defaulted to whatever "not a node" decodes to. `LayerManifest`
([ProjectManifest.swift:208-224](PaintSoftware/Models/ProjectManifest.swift#L208-L224)) is untouched
by any of this — layers don't need to know they sit inside a node's slot rather than an ordinary
folder, since containment is still just `parentFolderID`.

**5. UI surface.** See hard part #3. Additional detail: `LayerRowModel` is constructed once per row
per table reload at [LayerStackListView.swift:133](PaintSoftware/Views/LayerStackListView.swift#L133)
from `canvasManager.layerStackRows`
([CanvasManager+LayerTree.swift:24-44](PaintSoftware/Models/CanvasManager+LayerTree.swift#L24-L44)),
which itself only ever emits the two `LayerStackRow` cases
([CanvasManager+LayerTree.swift:28-44](PaintSoftware/Models/CanvasManager+LayerTree.swift#L28-L44)).
Drag/drop and restack UI (`dropBetween`/`dropOnto`,
[LayerStackListView.swift:177-245](PaintSoftware/Views/LayerStackListView.swift#L177-L245)) calls
straight through to `restackFolder`/`restackLayer` with no awareness of slot membership — this is
where hard part #2's missing contiguity guard would actually need to be felt by the user (reject or
redirect a drop that would separate two slots of the same node, or that would drop a bare layer
directly under a node folder).

Reminder from the brief, restated: items 3 and 5's files (`LayerStackListView.swift`,
`LayerStackCell.swift`, `LayerPanel.swift`) had mask-edit state added on another branch concurrently
with this read; treat exact line numbers there as approximate, the structural claims (binary
`isFolder`, per-field manual layout) as solid.
