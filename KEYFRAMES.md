# Keyframes

**Animating properties across the frames one cel spans.** ROADMAP.md item (1), specified 2026-08-28
after the conversation that file names as each item's entry condition. This is the design; nothing is
built yet.

**What this is not.** It is not the interpolation feature. That one in-betweens *drawings* between two
reference cels and ships already ([VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)). This one moves
and grades content that is already drawn. They are complementary, they will sit in the same timeline,
and §2.8 is how the artist tells them apart.

**How to read it.** Blockquotes are the owner's own words. §2 is the settled rulings — twenty-two of
them, twenty from 2026-08-28 and two from 2026-08-29 — and TODO.md's rule applies: *a question the owner has answered stops being a
question*. Everything else is our reading of the tree at `2eb3e5f`, marked INFERRED where it is a guess.

---

## 1. The brief, verbatim

> "Keyframes: (objects within a cel can get keyframed and move for the duration of that cel). Also
> applies to stuff like sliders for effects. Also includes interpolation curve customization. You
> should also be able to bake the cel containing animation into multiple cels (frames), and also set
> frame rate. Transformation layers adds transformation animation to whatever is under it."

And, expanding it:

> "User has a cel selected to which they can then have the option in the animation menu to add a
> keyframe to that frame on that cel. Then, they go to another frame of the same cel, add another
> keyframe, and adjust whatever thing they want as long as it is not destructive or constructive (like
> adding a new stroke)."

> "when you press on the keyframe button again when a keyframe is already made, a menu will show up
> containing a list of every transformation that currently is changing with that keyframe as an anchor
> point. The user can now click on these and open up the graph editor similar to blender."

> "I also want a feature where the user can somehow record transformations live. For example, they
> press a record button and put their pencil on the slider, and then it starts recording the motion of
> that slider and puts it into the graph editor. Another example is say they want screenshake, the user
> will press move on the entire canvas and then record, place his pencil down on the box and then shake
> it, and it will record it."

> "I want a feature in which the user can record their own stylus on the canvas for timing… With the
> tool selected, it will start recording when the pen touches the paper, stop recording when its
> lifted, and after that generate a cel in the current vector layer at the selected position (unless it
> has no space) in which something akin to a laser pointer is displayed. Like a brush stroke, but the
> tail tapers and ends from the point at where it was on the previous frame."

Videos as vector-layer objects are **ROADMAP item (2)**, not this document. They inherit this feature's
pose channel and its bake, which is why item (2) is stated to require item (1).

---

## 2. Rulings — settled 2026-08-28 and 2026-08-29, do not re-litigate

1. **Tap the keyframe button inserts a key. Hold it 0.8 s enters or exits Animate mode.** In Animate
   mode any non-destructive change at the playhead writes a key on exactly the channel touched. The
   button is therefore both an action and a mode, and the channel list is a panel, not a second press.
2. **Transform channels must eventually cover all three Move modes — Uniform, Freeform and perspective
   Distort** — including the Distort that is not implemented today
   (`TransformMode.distort.isImplemented == false`, `Models/SelectionModels.swift:54`).
3. **A transformation layer re-poses the vector objects below it**, rather than resampling the
   composited pixels below it. The owner wants crisp lines, not a bitmap magnify. This answers the
   question ROADMAP.md:173-174 raised and called *"different features wearing the same name"*.
4. **Effect-parameter keys live on the layer, in absolute document frames** — not on the cel. The owner:
   *"for effects it really does not have to be anchored to one singular cel, in fact that would likely
   be better."*
5. **A transform key stores a pose, and it is written at commit.** The owner: *"as soon as it starts
   moving, it should save a state of the unmoved item at keyframe A, then when the move 'bakes' as in
   the box disappears, keyframe B receives the second position."* So the cel holds **one** drawing, in
   its rest position; keys hold poses; the render composes them. **A nudge writes no key** — §4.2.
6. **The value layer's "Blend Mode" menu is relabelled to follow what is set** — Blend Mode / Effect /
   Transform. The owner: *"that 'blend mode' is very vague since effects, blend modes, and now the
   transform will be added to it."*
7. **An editable fps control ships with this feature**, so the artist can take the document below 24.
8. **The two meanings of "keyframe" are separated in the UI as "animation keyframes" (this feature) and
   "interpolation keyframes" (the existing reference cels).** The collision is real and is in the code:
   `CanvasManager.interpolationReferences` is documented as *"the cels the artist has flagged as
   keyframes"* and groups them into `interpolationKeyframes` (`Models/CanvasManager.swift:114-119`).
9. **Bake is destructive and undoable.** The animated cel is replaced by the baked one-frame cels and
   the animation is gone, in one undo step. Consistent with Commit, which is one-way by design
   (`InterpolationEvaluator.flattened`) — and the reason to bake is to hand-edit the in-betweens, so a
   live rig underneath them would be a lie. **Bake is an authoring feature and never a performance
   instruction** — see §2.19 and §4.6.
10. **Every channel carries a step**: 1 = every frame, 2 = on twos, 3 = on threes. The curve is
    evaluated and then held. This is Blender's Stepped modifier and it exists because ink drawn on twos
    beside a perfectly smooth 24 fps camera move reads as CG.
11. **Membership is a named animation group, and there is no conflict prompt.** An object carries an
    `animationGroupID` the way a stroke already carries a `motionGroupID`. "Already animated" means
    "already in group A", shown in the channel list and reassignable by a tap. The brief's *"a prompt
    probably will be thrown so the user decides to remove the objects out of the previous one"* is
    superseded.
12. **A transform layer resamples raster content below it and re-poses vector content below it** — each
    tier in its own currency. Accepted consequence: a raster layer softens under a push-in while the
    vector layer beside it stays sharp. That difference is inherent, not a defect to chase.
13. **The keyframe substrate ships before Distort; Distort follows immediately after.** Enabled by §2.14
    — see §3.3. Keyframes ship with Uniform and Freeform working and Distort still greyed exactly as it
    is today.
14. **A transform key stores a quad — four corners plus a box size — from day one.** One representation
    expresses Uniform, Freeform *and* Distort, so §2.13 costs no migration. `TextFrame`
    (`Engine/TextObject.swift:239`) is the shipped precedent: `size` + `corners` + `mode`, `Codable`,
    with the 3×3 **computed and never stored**.
15. **Two poses are interpolated through their factored form** — affine × pure-projective — not by
    lerping matrix entries and **not** by lerping corners. See §4.3 for why corner-lerp is not the safe
    alternative it looks like.
16. **Brush grain travels with the ink.** Each dab's grain value is baked when the stroke is drawn, so
    the texture is part of the mark. Accepted consequence: a stroke you Move keeps its grain instead of
    re-sampling, which is a visible change to how existing artwork behaves under Move.
17. **The graph editor is a drawer that grows the timeline upward**, sharing the timeline's frame ruler
    and playhead, so a curve sits literally above the frames it controls — not a popover and not a
    full-screen sheet.
18. **A derived in-between carries no object channels.** It has no stable elements to key: the display
    list is computed. This mirrors what already ships — Move is refused outright on an interpolated cel
    in two places (`Views/TopToolbar.swift:142-143`, `Models/CanvasManager+LassoMove.swift:916-922`).
    Layer-scoped channels (§2.4) are unaffected, because their target is not the cel.
19. **Smooth playback comes from a cache, not from baking.** The owner: *"I would like not having to
    bake into frames while keeping performance."* Animation stays live and editable; a playback cache
    makes it fast. §4.6.
20. **That cache is span-scoped, complete and eager — not a lazy per-frame LRU.** The owner: *"we store
    the two keyframes, plus the cached frames in between. Then when something changes, the stuff in
    between can be overwritten using the new keyframes once, before its stored again."* Adopted over the
    LRU this document first proposed, because an LRU thrashes invisibly — playback is smooth or not
    depending on what else happens to be resident — while a span either is cached or is not, and the UI
    can say which. Three amendments in §4.6: recompute **on settle**, cache the **composite**, and store
    it **outside the project package**.
21. **A folder's effect animates exactly as a layer's does.** 2026-08-29, closing §9.3.
    `LayerFolder.effect` is a second home for the same grade and it gets the same track, rather than
    being declared un-animatable in writing. It costs one more storage site and one more arm on the
    resolver; the alternative costs a slider that silently refuses to key, which nothing reveals until
    the artist reaches for it.
22. **The keyframe button lives in the timeline's own control strip**, beside play, fps and add-cel —
    not in the top toolbar. 2026-08-29. It writes at the playhead and §2.17's drawer grows upward out
    of the same timeline, so the button, the frames it writes onto and the curve it opens are all in
    one place. It is chrome and **not a `Tool`**: `Tool`'s seven slots are explicitly full and every
    switch over it is exhaustive with no `default:` precisely so a new case cannot be missed
    (`Models/Tool.swift:22-24`, `:48-53`).

---

## 3. The model

### 3.1 Two time bases, each obviously right for its target

| channel target | stored where | time base | why |
|---|---|---|---|
| an object / animation group in a cel | on the **cel** | **cel-local frames** (offset from `startFrame`) | it rides the cel through move, split, duplicate and paste for free — the same argument `motionGroupID`'s doc makes for a field over a side table |
| a layer or folder (effect params, opacity, a transform layer's pose) | on the **layer** | **absolute document frames** | §2.4. Its target has no cel to ride |

There is no third notion and no fractional document time. `activeCelIndex(inLayer:atFrame:)`
(`Models/CanvasManager+Timeline.swift:12-15`) is the chokepoint every drawing path already funnels
through, and it is where cel-local time is resolved.

**Eleven cel operations each owe an answer** and none of them can be evidence of correct behaviour
today, because there is no keyframe data for them to touch: `addCel`, `duplicateCel`, `pasteCel`,
`deleteCel`, `extendCelToEnd`, `clearCel`, `resizeCelLeftEdge`, `resizeCelRightEdge`, `moveCel`,
`splitCel`, `addBlankCelAfter` (all in `CanvasManager+Timeline.swift`). The two that need a real rule
rather than "it falls out of cel-local time":

- **`splitCel`** — keys before the cut go left, keys after go right, and **a key is inserted at the cut
  in both** so the value is continuous across it.
- **`resizeCelRightEdge` / `resizeCelLeftEdge`** — keys keep their cel-local frame and are **clamped,
  not rescaled**. Rescaling would retime an animation as a side effect of dragging a cel edge, which no
  artist expects. A key pushed outside the new span is held, not deleted, so shrinking and re-growing a
  cel is lossless.

### 3.2 The curve

A new `AnimationCurve` type: an ordered list of keys, each `{ frame, value, inHandle, outHandle,
tangentMode }`, plus a per-channel `step` (§2.10) and an interpolation mode **per segment**, carried on
the key that begins it — which is how Blender stores it, and it is what lets one hold sit between two
eases.

**`SpacingCurve` is not this type and must not be widened into it.** It is a *time remap*: `eased(t)`
returns a new `t` fed to lattice deformation, its input is clamped to 0…1
(`Models/InterpolationRecipe.swift:74`), monotonicity is enforced in two separate places on purpose
(`Engine/GuidePath.swift:376-378`, `:387-392`) because a dipping curve runs an in-between backwards
mid-scrub, and both ends are pinned. Reusing it for bloom intensity silently imposes all three, and
**overshoot — the thing a bezier graph editor exists to give you — is structurally excluded.**

What *is* reused: `CurveEditor`'s gesture grammar verbatim (`Views/EffectSection.swift:665-885` —
`DragGesture(minimumDistance: 0)`, `hitRadius` 22 pt, `tapSlop` 5 pt, drag moves / tap-on-handle deletes
/ tap-on-empty adds, and its `Self.encode(points)` accessibility-value convention that the UI suite
reads); and `SpacingChart`'s **write-back discipline** — begin/drag/commit as one undo bracket, and a
chart that is a *view* of whichever curve is in force rather than a second store
(`Models/CanvasManager+Interpolation.swift:1544-1566`). Those three rules are what keep the existing
timing UI from creeping, and they are worth more than the widget.

**One-way bridge, offered not required**: an `AnimationCurve` can emit a `SpacingCurve.sampled`, so the
graph editor could drive an interpolation span's easing. Never the reverse.

### 3.3 The pose is a quad

§2.14. `Quad` (`Engine/Deform/Quad.swift:18`) exists with `isConvex`, `isSimple`, `isParallelogram` and
`mapped(by:)`, and `Homography` (`Engine/Deform/Homography.swift:31`) is a finished projective solver —
Heckbert closed form, exact `inverse`, an exact `affine()` decision, `linearised(at:)`, `localScale(at:)`
and `isValidQuad` — with 27 headless tests across `HomographyLogicTests` and
`WarpAgreementCharacterizationTests`. **`Quad` is `Equatable` but not `Codable`** and has no lerp; both
are needed.

**Why not the six-scalar pose the Move tool uses today.** `ObjectTransformFrame` is `position` +
`scale` + `rotation` + `aspect` + `stretchAxis`, and LASSO_MOVE.md §5.20 already establishes that those
six *are* a general affine *"with nothing left over for a later stage to invent"* and that it
*"stops well short of stage 5's Distort, which is a homography and needs 8"*. Storing six would force a
migration the day Distort lands. Storing a quad costs nothing extra now and none later.

**Trap, and it has a pinned test.** `boxAngle` and `stretchAxis` are opposites —
*"boxAngle draws and never maps, stretchAxis maps and never draws"* (`ObjectTransformFrame.swift:22-26`),
pinned by `testANonZeroBoxAngleChangesNoSampleAndNoPixel`. A channel list that offers "rotation of the
box" and stores `boxAngle` animates a value that reaches no geometry at all.

### 3.4 Animation groups

`AnimationGroup` mirrors `MotionGroup` exactly: a document-level identity carrying **no geometry** — id,
display name, tag colour — persisted in the manifest, with membership as an `animationGroupID: UUID?`
**field on the element**. That split is the codebase's own settled shape: `MotionGroup` is identity,
`MotionGroupBinding` inside the recipe is the geometry, and `motionGroupID`'s doc gives the reason for
the field — *"so it survives copy/duplicate/split/undo automatically and a cut piece keeps its parent's
tag"* (`Engine/VectorLayer.swift:52-54`).

**That reason is load-bearing here and not merely tidy.** Element ids **do not survive a lasso lift** —
the split mints fresh UUIDs on both pieces (`VectorLayer.swift:1146`, `:1234`) — so a channel keyed to
raw element ids is orphaned the moment the artist re-lassoes. A field is the only thing that survives.

**It must go on every element kind, not just strokes.** `motionGroupID` today is on `VectorStroke` and
`VectorTextElement` only, so fills and placed images ride the recipe's first binding and cannot be
tinted by the group overlay — VECTOR_INTERPOLATION.md items 11/41 already ask for this to be fixed.
Doing it once serves both features.

### 3.5 Persistence

- **The track sidecar.** A cel's animation goes in its own file beside the interpolation recipe, named
  from a new **optional** `CelManifest.animationFileName`, exactly as `interpolationFileName` works
  (`Models/ProjectManifest.swift:373-375`, written only when non-nil at
  `Services/ProjectStore.swift:829-838`). The stated reason applies verbatim: `manifest.json` is read in
  full for every gallery tile, so bulky per-cel data does not belong in it. A missing or unreadable
  sidecar costs the link, not the drawing.
- **Add it to the validator on day one.** `ProjectBackupManager.ManifestSkeleton.Cel`
  (`Services/ProjectBackupManager.swift:466-477`) checks the raster, fill, baked and vector files but
  **never `interpolationFileName`** — a cel whose recipe sidecar is missing still validates and the
  atomic save proceeds. That is a real, existing, silent gap. Do not inherit it: add
  `animationFileName` to the skeleton in the same commit that adds it to the manifest, and consider
  fixing `interpolationFileName` while the file is open.
- **Layer-scoped tracks** (§2.4) go on `LayerManifest` beside `effect`, optional, written only when
  present — the format is versioned by field presence, not by a number, and every persisted field in
  the tree follows that idiom.
- **A track outlives the effect it was written for, deliberately.** Key `bloom.intensity`, then switch
  the layer to a blur: the track is **kept and inert**. Inert falls out of evaluation walking the
  *effect's* descriptors rather than the track dictionary, and ids are `"<case>.<field>"`, so
  `blur.radius` and `bloom.radius` cannot collide. Kept rather than pruned on `Layer.valueFill`'s own
  asymmetry — a picker that silently destroys the other mode's setting is what a picker must not do —
  so flipping back restores the animation.
- **Precision.** Keys are `Double`. Do **not** route a pose through `PackedSampleRun`: its Int16
  quarter-pixel grid **saturates rather than throwing** (`Engine/ShapeGeometry.swift:783-791`), which for
  a handful of anchor values would silently teleport an out-of-range key. That encoding is tuned for
  thousands of samples a stroke; a key wants exactness over compactness.

---

## 4. Evaluation and rendering

### 4.1 `renderTree(atFrame:)` — the one structural change, and it is small

`renderTree` is a computed var with a single private producer (`Models/RenderTree.swift:751-761`,
recursing at `:832`). The effect is read at `:784` (`layer.layerEffect`) and `:891` (`folder.effect`),
**where the frame is not in scope** — so §2.4 forces the tree to become a function of the frame. That is
the whole cost, and it is six production call sites, five of which already hold a frame.

**Invalidation is free.** `SandwichKey` (`Views/CanvasView.swift:1398-1421`) and `SandwichFullKey`
(`Engine/RenderRequest.swift:462-494`) each already carry the resolved `[RenderNode]` **and** the frame,
`RenderNode` is `Equatable`, and its `effect` field is compared verbatim. A per-frame-resolved effect
moves the key with no new plumbing.

**The template already exists and says so.** `ValueFill.resolvedColor(atFrame:)`
(`Models/Layer.swift:203`) is `{ color }` today, and its doc comment cut this seam deliberately:
*"a keyframe phase would then have to cut this seam under a deadline instead of finding it already
cut."* `Effect.resolved(atFrame:)` is the same shape one level over.

**The cache that actually moves is not the one it looks like.** `SandwichKey` and `SandwichFullKey`
both carry `frame` outright, so two keys at two frames differ *whatever* the tree says — a test that
compares them across frames passes on unmodified `main` and proves nothing. Pin it by holding `frame`
**equal** and deriving the tree at two different frames. And the cache where staleness would actually
bite is **`MaskResolver`'s**, which is keyed on `LayerContentVersion` and carries neither the frame nor
the tree: it moves only because stage 0 put the frame-resolved effect *into* the version. Do not remove
that, or a grade that reshapes alpha will serve stale coverage. (Note `LayerContentVersion.hash(into:)`
deliberately omits `effect` while `==` includes it — legal, and it only costs collisions.)

**One thing §2.4 did not cover, now ruled, and one nobody has.** `LayerFolder.effect`
(`Models/LayerFolder.swift:73`) is a second effect home reached at `RenderTree.swift:891`, and §2.21
gives it the same track a layer's effect gets. And
`CanvasManager.compositorSizeGate` (`CanvasManager+Document.swift:546-550`) is frame-invariant **only
for as long as a key cannot turn an effect on or off**; it counts `effect != nil`, so the day a track
can add one, the resize dialog's admission gate becomes a function of the playhead and will answer for
one frame about a document that dies on another.

### 4.2 Posed ink: bake the dab walk in rest space

**This is the load-bearing engine idea and it makes posing cheaper than today, not dearer.**

Today a mapped stroke re-walks the dab lattice in destination space, so the dab count and phase are
re-derived per frame. At 24 fps that is the shimmer everyone fears. The fix is to bake the walk **once
in rest space** and then, per frame, map each dab's **centre** through the pose and scale its **radius**
by the pose's local area root. Dab count, phase and the seeded `DabRNG` become invariant across the
whole animation *by construction*. The per-frame walk arithmetic disappears, leaving four multiplies and
four adds per dab.

**This is not an invention — the tree already does it one level down.** `DabLattice`
(`Engine/VectorLayer.swift:82-126`) stores a cut piece's *parent's whole walk* and filters it, and
`BrushStamper.swift:144-162` states the rule to generalise: *"a filter over the original walk, not a
re-derivation"*, with its acceptance test asserted at zero tolerance. Generalising "the walk that
defines the lattice" from a cut parent to a rest pose is a small, well-precedented change. What is
missing is a `DabTarget` that **collects** instead of drawing — structurally identical to the existing
`DiscardedDabTarget` (`BrushStamper.swift:303-310`) — plus a replay entry point taking a point map.

**And it dissolves the per-sample-width problem completely.** LASSO_MOVE.md §5.17 settles that ink
scales by `sqrt(|det|)`, the map's own area root, *"not by one axis, and not by nothing"*, chosen because
for a similarity `sqrt(|det|)` *is* `k` and so **Freeform contains Uniform** rather than sitting beside
it. `Homography.localScale(at:)` (`Deform/Homography.swift:266-269`) is the *local* area root — the
sqrt of the Jacobian determinant — and reduces exactly to `sqrt(|det|)` for an affine and to `k` for a
similarity. So each dab's width comes from the pose at render time. **No per-sample width, no
`VectorSample` change, no wire-format change, no decode migration** — which was supposed to be the
expensive half of vector Distort.

**Build the pose as a point map, not a `CGAffineTransform`.** `drawn(_:through:widthScale:)`
(`VectorLayer.swift:2262`) and every CTM seam take an affine and cannot hold a homography; `CGContext`
has no projective CTM at all. One evaluator over `Homography.map` + `localScale(at:)` serves Uniform,
Freeform and Distort. Three separate arms do not.

**Do not implement §2.3 by concatenating the pose onto the CTM before stamping.** It is one line and it
would fix LAYER_TRANSFORM.md's defects A and B at once — but `drawRadialGradient` draws in user space,
so it turns every round dab into an ellipse, contradicting the shipped ink-keeps-its-shape default of
2026-08-26. The CTM route is the correct implementation of the *opposite* toggle setting.

**Three artifacts, named honestly.**

- **Grain is the real one** — §2.16. It is an absolute canvas-position noise field sampled at the
  *posed* stamp point (`BrushStamper.swift:250`, `:269-273`). `VectorLayer.swift:2075-2077` dismisses
  re-sampling as "no regression" because it already happens under a plain translation; that reasoning
  holds for a one-off Move and fails completely at 24 fps. **The baked dab record carries the
  multiplier, not the position.**
- **Square and custom brush shapes** re-derive a sub-dab grid from the posed diameter with 1 pt floors
  (`BrushStamper.swift:275-294`), so they shimmer while the five round built-ins do not, unless their
  sub-lattice is baked too.
- **Under Distort a dab is drawn as a circle at the local scale**, not the true projected ellipse — a
  sub-pixel error at reasonable distorts, and the same approximation `TextLayout.warpSourceScale`
  already makes.

**Two tiers, and the house pattern already exists.** During a scrub or a recorded drag, drive
`floatView`'s `UIView.transform` — PERFORMANCE.md:209-212 records that taking a Move drag onto that path
went from 96.1–107.8 ms a sample to **0.002 ms** — and accept the nearest-neighbour magnify. Re-stamp
crisply on the settled frame and at bake. §2.5's "the key is written at commit, not on every nudge"
points at the same seam, so the ruling and the performance pattern agree.

### 4.3 Interpolating two poses

§2.15. **Corner-lerp is not the safe alternative to matrix-lerp — it fails the same way.**
`DeformFactorization.swift:56` already warns that lerping matrix entries collapses a rotating arm to a
line at `t = 0.5` and re-expands; a vertex-wise lerp of two quads has the identical defect, because the
blended edge cross product goes negative when the two poses differ by a large rotation. **Convexity is
not preserved by corner lerp, so an in-between can be invalid between two valid keys.**

The construction: factor each pose as **affine × pure-projective**; interpolate the affine part through
the project's own `Matrix2x2.polar` / `interpolatedFromIdentity`
(`Engine/Deform/DeformFactorization.swift:62`, `:80`) with `ARAPInterpolation`'s angle unwrapping; lerp
the perspective row, which is small and well-behaved; recompose.

**That is not a guarantee, so a fallback is owed.** `Homography.isValidQuad` today is a *drag* clamp
whose failure mode is *"the handle feels like it sticks"* (`Homography.swift:310-312`) — a scrubbed
in-between has no finger to stick. **Open, §9.1.**

### 4.4 The transformation layer

§2.3 and §2.12. It is **not** a blend mode and cannot be: all 25 modes are per-channel colour functions
over two same-size, same-position images, with no positional argument anywhere in either backend's call
chain. It is an **arity-1 `CompositorOp`**, the shape the existing effect node already takes. §2.6's
relabelled menu is what makes that invisible to the artist — the value layer's menu already merges blend
modes and effects into one list, so a third kind of entry there is consistent with what ships.

**Scope is already defined and reusable verbatim**: a value layer with an effect grades *"everything
beneath it inside its own container"*. A transform layer uses the same rule.

**Where the pose is applied.** `renderNodes(atFrame:inContainer:)` accumulates a `Homography` down each
container using the same `below` / `containerIsNode` scope machinery it already has, and emits
`[layerIndex: Homography]` alongside the tree; `renderSources` maps the cel's elements through it and
hands the posed display list to `renderLocalContent(elements:)`. **Ink is stamped at the posed position
— it is never resampled afterwards.** Injecting at `VectorCanvas.render()`'s existing
`ctx.concatenate(_transform)` (`VectorLayer.swift:2916-2919`) is the one-line change any reader will
reach for and it is exactly LAYER_TRANSFORM.md's defect B — a bitmap magnify of an already-stamped
canvas — plus defect A, because `renderLocalContent` allocates a context of exactly `size` in local
space and clips ink the pose moves outward.

**A pose is not scoped by a buffer the way an effect is.** An effect's containment is enforced at
composite time by `needsOwnBuffer` / `isIsolated`. A pose applied at rasterisation has no buffer to be
bounded by, so the scope must be computed structurally in `renderNodes` and carried per layer index —
get it wrong and the pose silently leaves its folder with nothing downstream to stop it.

**Two placed-object refusals ride along.** `mapping(_:throughStretch:)` `assertionFailure`s on a placed
image (`VectorLayer.swift:2247`) and `canBeStretched` returns false for `.image` — so a transform layer
over a cel holding a photo trips an assert in debug and silently leaves the photo behind in release,
while the strokes around it move. That is Move stage 3c's gate
(`VectorImageElement.transform` is a `LayerTransform` with nowhere for a second axis), and it must be
refused out loud here rather than left to assert.

### 4.5 The caching trap — pin this on day one

An animated pose defeats `PixelOps.rasterize`'s flatten memo for every leaf beneath it, on every frame.
Neither `PixelOps.RasterizeKey` nor `LayerContentVersion` has a pose field.

**The failure is invisible in the obvious place.** `SandwichKey` compares the whole `[RenderNode]`, so
adding a pose to `RenderNode` invalidates the *sandwich* automatically — the composite dutifully
rebuilds, **from `rasterize`'s cached un-posed image.** Green tests, wrong pixels, and no key that looks
wrong. Both keys need the pose, and a test needs to pin it.

**The honest cost, and it splits sharply by blast radius.** *(INFERRED, arithmetic over MEASURED
components.)* Playback already re-composites every frame — the frame is in the cache key — so ~21 ms of
composite is the *existing* cost of pressing play, not something animation adds. What animation adds is
the defeated flatten, and how much of it depends entirely on how many leaves the pose reaches:

| what is animated | leaves whose flatten is invalidated | added cost per frame |
|---|---|---|
| one object, or a group, inside one cel | **one** | ~4 ms — **fits 24 fps with no cache at all** |
| a transformation layer over a six-layer container | **six** | ~22 ms — 43 ms total against a 41.7 ms budget, i.e. it misses |

So **per-object animation is not a performance problem and must not be designed as though it were.** The
transformation layer is, and §4.6 is its answer.

### 4.6 The playback cache — and why Bake is not the performance answer

**Owner's ruling, 2026-08-28**, and it corrects an earlier framing in this document:

> "if bake into frames is able to speed up the transformations, is it possible to automatically cache
> the transformations as baked so that they dont need to be recalculated every frame? Because I would
> like not having to bake into frames while keeping performance."

**Bake is an authoring feature, not an optimisation.** You bake when you want to *draw on* the
in-betweens. Nobody should ever be told to bake to get a smooth preview, and §6 is written for the first
reason only.

**The shape is the owner's, §2.20: span-scoped, complete and eager.** The frames between two animation
keys are computed as a unit, kept as a unit, and recomputed as a unit when anything they depend on
moves. This was chosen over a lazy per-frame LRU for a reason that is about the artist rather than the
machine: an LRU's hit rate is invisible, so playback is smooth or stuttery depending on what else is
resident, whereas a span is either cached or not and the timeline can show it. It also removes the
"first pass is always uncached" concession, which is what the owner objected to.

**Amendment 1 — "once" means *on settle*, not *on change*.** A span recomputed on every touch-move of a
curve handle recomputes sixty times a second. While a gesture is live, fall back to the live path (fast
for per-object work — §4.5); recompute when it commits, after an idle delay, cancellably.

**The app has exactly one precedent for this and it is a good one**: thumbnail regeneration is a Combine
`.debounce(for: .milliseconds(400), scheduler: RunLoop.main)` where the *payload* travels separately in
an accumulating `pendingThumbnailRegens: Set<CelLocation>` (`Models/CanvasManager.swift:966-981`,
`:1449-1461`) — so the debounce coalesces the timing while the set loses nothing, and ids are resolved
back to indices at drain time so a reorder or a delete in the window is survivable. It also keeps an
explicit **non-debounced** escape hatch for load and canvas resize (`regenerateAllThumbnails()`), on the
argument that queueing there "would only defer the same work by 400 ms while leaving the timeline
blank". A span cache wants all three properties. Nothing else in the app debounces a recompute — the
other `asyncAfter` sites are gesture disambiguation and fade timing.

**Amendment 2 — cache the composite, not the per-layer flattens.** The owner's "the cached frames in
between" means the *pictures*, and that is the cheaper unit by roughly the layer count: one image per
frame rather than one per layer per frame.

*MEASURED*: a canvas texture is 16.8 MB at 2048² (`Engine/MetalCompositor.swift:212`), and
PERFORMANCE.md's "six canvas-sized textures are 48 MiB at 2048×1024" gives **8 MiB a frame at the
owner's own working size**. At the 50% Render Resolution the app already ships that is **2 MiB a frame**.
So a 48-frame span is **384 MiB full-res and 96 MiB at half**.

**And it must key on `RenderResolution`.** `SandwichKey` and `SandwichFullKey` already do
(`Views/CanvasView.swift:1410`, `Engine/RenderRequest.swift:467`) and their comments say why in the words
to reuse: otherwise the setting becomes *"a control that visibly does nothing when you use it"*. Note
also what that setting actually reaches — **only `makeSandwichRequests`, the on-screen live composite**
(`RenderRequest.swift:195-199`). It does not scale the flatten, the thumbnail, the saved package or a
future export, and the Actions menu promises the artist exactly that. A preview-resolution span cache is
therefore consistent with what the control already means; a full-resolution one is a different tier.

**Amendment 3 — "stored" must mean outside the `.paintproj`.** Three reasons and the first is decisive:
the save path re-encodes **every** cel on **every** save with no skip-unchanged path, at a MEASURED
15.2 ms/cel of which 95.6% is `pngData()`, so cached frames inside the package would tax every future
save of that document. Second, `ProjectBackupManager.validateProject` gates the atomic swap on the files
the manifest names, so a large derived sidecar becomes a new way for a save to be refused. Third,
derived data living in the document is a class of problem this repo already has and wants out —
`fillImage` and `bakedImage` are the cautionary tale, and VECTOR_INTERPOLATION item 26 records that the
owner wants vector fully divorced from raster features. A cache that can be deleted at any moment by
anyone with zero loss is the only kind worth having.

**Two findings that change the cost, both from the 2026-08-28 survey.**

- **There is no multi-frame composite cache to extend — this is new machinery.** The sandwich holds
  **exactly one generation** (three canvas-sized images in `sandwichImages`, `CanvasView.swift:1128`),
  overwritten on every rebuild and **dropped entirely on disengage**, with the comment that names the
  principle: *"an address for pixels that have been released is not a cache"*
  (`CanvasView.swift:1500-1501`). There is no dictionary, no LRU and no count budget behind it.
- **Memory alone cannot hold a span, so the disk tier is required rather than nice to have.** The house
  rule for a large budget is `physicalMemory / 16` clamped to [64 MiB, 768 MiB] — **192 MiB on the
  owner's iPad 9** — and three budgets share that one function, pinned equal by
  `MemoryBudgetLogicTests.testTheThreeLargeBudgetsRunOnOneRule`. But that 192 MiB is already spent: it is
  the compositor's texture pool *and* `PixelOps.rasterizeCache`'s budget. A feature-scoped budget takes
  the other shape in the house table — a flat literal justified as a property of the frame rather than of
  the device, as `OnionSkinBudget.residentBudgetBytes` is at 64 MiB. **At 2 MiB a frame that is 32
  frames, about 1.3 seconds.** A 48-frame span does not fit.

**Where the disk tier lives is a genuine departure and should be taken knowingly.** The app has **no
on-disk derived-data store of any kind** — no `Library/Caches`, no temporary directory, not one hit.
Its only "outside the package" precedent is `ProjectBackupManager`'s named sibling folders under
`Documents/` (`Projects/`, `Backups/`, `Trash/`), app-managed, rotated by count with a 1 GB global cap
and purged at launch, never on a low-disk signal. **INFERRED recommendation: use `Library/Caches`
anyway.** It is the platform's home for exactly this — evictable derived data, purged by the OS under
disk pressure, excluded from backup — and `Documents/` is backed up and counted against the artist's
storage, which is wrong for bytes whose whole contract is that losing them costs nothing. This is the
case where the platform convention should beat the local one, and it is the first time the app would
need one. Say so in the commit rather than letting it read as an oversight.

**Eviction is by whole span, least-recently-played.** The owner's model is otherwise unbounded, and a
300–1000 cel document can hold hundreds of animated spans. Span granularity is the better unit anyway:
a half-evicted span is useless, so keeping fragments buys nothing. Note that
`PixelOps.rasterizeCache` is **FIFO, not LRU**, 24 entries under the shared byte budget, and is cleared
wholesale on a memory warning and on backgrounding (`Services/PixelOps.swift:210-250`) — a span cache
should honour the same two signals.

**Invalidation is the hard part, and it is the same requirement either design had.** A cached span dies
when the ink changes, when the curve changes, when the layer's effect changes, and — for a
transformation layer — when *anything below it* changes. `LayerContentVersion` already propagates
exactly this kind of dependency, which is why LAYER_COMPOSITING §9.1 lists propagating content versions
as substrate to build now. Get it wrong and §4.5's trap is waiting: the composite rebuilds happily from
a stale flatten, with green tests and no key that looks wrong.

**Two limits to state in the UI rather than let someone discover.** A span is **uncached until it has
been computed once**, which after amendment 1 means "until the edit settles" rather than "until you have
played it" — better, but not free. And **editing a curve throws away that span**, so the cache helps
review rather than authoring.

**Scope, unchanged: per-object animation needs none of this** (§4.5 — it already fits inside 24 fps).
This is machinery for the transformation layer and, later, for export.

---

## 5. Recording

§2.1's Animate mode with a clock. One mechanism, two surfaces: a slider, and the Move box.

**Capture at the pencil's own rate and resample on stop. Never sample at 24 Hz.** A 24 Hz sample of a
shake **aliases** — a fast shake records as a slow wobble. The intake already carries what is needed:
`onStrokeMoved: ((VectorSample, TimeInterval) -> Void)` hands over `UITouch.timestamp`, the pen's own
hardware clock, at the full coalesced rate, and its doc comment explains why the timestamp rides beside
the sample rather than inside `VectorSample` (a Codable migration on the format's most numerous type).
For a slider, sample its continuous `set` closure (`Views/EffectSection.swift:409-432`) on the clock —
**not** `WindowEventTap`, which is debug-only, thinned to ~20 Hz by design, and **cannot identify a
SwiftUI control on a real iPad** because no accessibility client is attached (`WindowEventTap.swift:435-461`,
verified on device).

**Then decimate and simplify.** `GuidePath.spacingCurve(resolution:)` (`Engine/GuidePath.swift:166-196`)
is the template for the resample — walk evenly spaced output stops, read the raw recorded stream at each,
pin the ends, and return `.linear` when the duration is zero rather than reading noise as intent. Drive
the stop count from `fps` × recorded duration rather than its fixed 33. A tolerance-based simplify then
turns a 3-second shake from 72 keys a channel into something a graph editor can hold. **Note the
opposite precedent and why it does not apply**: VECTOR_INTERPOLATION §3 fact 13 rejected Douglas-Peucker
for *stroke geometry*, because two points bend as a straight line under a warp that should curve them.
A value curve has no warp; deviation-based simplification is the right family here.

**Slow motion is a capture-speed multiplier on the record control, not the document fps.** §2.7 makes
fps editable, but changing it to get slow-mo retimes everything else in the document. Note also that
`GuidePath.spacingCurve` **discards absolute duration entirely** (it normalises both axes and pins the
ends), so "lower fps = slow motion" does not fall out of the existing derivation — the recorder must keep
real time.

**Two prerequisites.** Playback's `isPlaying` / `playbackTimer` live as `@State` on the timeline **view**
(`Views/AnimationTimeline.swift:13-14`) and the timer just adds 1 per fire with no wall-clock
comparison, so it drifts. The recorder needs a model-level clock — which is the same prerequisite
ROADMAP item (4) names for audio, so it is worth doing once and properly. And an fps stepper that only
writes `canvasManager.fps` will **silently play at the old rate** until playback is stopped and
restarted, because `togglePlayback()` captures `1.0 / fps` once (`AnimationTimeline.swift:729`).

**Expect it to feel twitchy before it feels good.** VECTOR_INTERPOLATION §5 open call 1 says exactly that
of the velocity→easing mapping, which has *"never met a real stylus"*. Smoothing is part of this feature,
not polish on top of it.

---

## 6. Bake

§2.9. Destructive, undoable, one step. **It exists so the artist can draw on the in-betweens.**
It is not the answer to a slow preview and must never be offered as one — that is §4.6.

**Follow `bakePreciseStrokes` exactly** (`Models/CanvasManager+Document.swift:982-1049`): call
`commitAllInteractiveState()` first so a float under the artist's finger is not baked mid-motion; walk
and **collect** per-cel edits; mutate; register **one** `recordUndo` over all of them. Its own comment
states the reason — *"rather than registering per cel, which would cost the artist one press per cel to
take back a single menu tap."*

**Mint fresh element ids, unlike every existing copy path.** `VectorCanvas.makeCopy()` preserves element
UUIDs verbatim, which is deliberate and correct for `duplicateCel` (a motion-group tag should travel).
For a bake it is wrong: 48 cels whose elements share ids will alias anything keyed by id.

**Bake at the channel's step (§2.10), not always at 1.** A cel animated on twos bakes to 24 cels, not 48.

**Two costs to disclose, not hide.**

- **There is no batch cel-creation primitive.** Every path — `addCel`, `duplicateCel`, `pasteCel`,
  `splitCel`, `addBlankCelAfter` — creates exactly one cel per call. A bake loops one of them inside a
  single bracket, and `withInterpolationUndo` **silently no-ops its own bracket when re-entrant**
  (`guard structureUndoDepth == 0, gestureSnapshot == nil`), which the loop must rely on deliberately
  rather than trip over.
- **Save cost is permanent.** `ProjectStore` re-encodes every cel on every save with no
  skip-unchanged-cel path, at a MEASURED 15.2 ms/cel at 2048×1024, **95.6% of it `pngData()`**,
  parallelised across cores. Baking one cel into 48 raises the cost of every future save **for the life
  of the document**. Say so at the bake, with the number.

**A range bake is also (5)'s exporter.** ROADMAP §0 notes both are "evaluate the document at frame N,
N+1, … and emit one picture per frame", and that `makeRenderRequest` is already frame-parametric. Build
the frame-walker once.

---

## 7. The timing recorder

The laser-pointer tool. It is §5's recorder with no target channel: capture `[TimedSample]` from the
canvas, then draw a trail whose tail tapers from where the point was on the previous frame.

Both halves exist. Taper is `StrokeGeometry.stampRadius(forPressure:brush:size:)` plus the capsule chain
— substitute a decay-since-touch-down scalar for pressure. Cel creation is `addCel(layerIndex:startFrame:
frameCount:)`, already `withStructureUndo`-wrapped. **INFERRED**: the cleanest shape is an animated dot
with a position curve, so it *is* an instance of this feature rather than a special case, and the trail
is a render style; baking it then falls out of §6.

**It enters through the Actions menu, not the toolbar.** `Tool` has seven slots and is explicitly full —
`.text` was routed through Actions for exactly that reason (`Models/Tool.swift:22-24`). And every switch
over `Tool` is exhaustive with **no `default:`** on purpose, because three past bugs shipped from
someone adding a case and missing a hand-maintained exclusion list (`Tool.swift:48-53`, `:78-104`).

---

## 8. Build order

Each stage is mergeable and leaves the app working.

| # | stage | notes |
|---|---|---|
| **0** ✅ | **`renderTree(atFrame:)`** — merged `654f863`. | Behaviour-neutral. Six production call sites, one recursion, ~60 fast-tier test references. Both §2.3 and §2.4 are blocked on it. Ship it alone so the frame-threading diff is not inside a diff that changes pixels. |
| **1** ✅ | **`AnimationCurve` + the effect descriptor table** — merged `c09ddf0`, `c6ecb49`, `6a379bf`. | The table is an exhaustive `switch self` with **no `default:`** — `Effect` cannot be `CaseIterable` and every existing all-effects sweep in the suite is a hand-typed literal, so a `default:` would silently miss a fourteenth effect. Make `EffectSettingsBar.rows` *read* the table so the two cannot drift; the 25 slider sites already carry range, format and target. |
| **2** ✅ | **One channel end to end: a layer effect parameter** — merged `4d55aae`. Continuous scalars only; the six stepped fields, the two array ones and `outline.color` are refused at the writer as well as the resolver, so the app cannot reach a track that stores and renders nothing. | `Effect.resolved(atFrame:)`, keys on the layer, absolute frames. Proves storage, evaluation, invalidation, undo, save/load. No new geometry. |
| **3** | **The Animate mode and the graph-editor drawer** | §2.1's tap/hold, the channel panel, §2.17's drawer. Every new popover **must** add a `CanvasPresentation` case and route through `.canvasPresentation`, or it reproduces the stroke-teardown bug that census exists to prevent. |
| **4** | **The rest-space dab bake + grain** | §4.2 and §2.16. Engine-only, testable in the fast tier, and `Engine/Deform` compiles standalone with `swiftc` in ~5 s. |
| **5** | **The transform channel** | Quad keys, animation groups, §2.5's write-at-commit, §4.3's factored interpolation. Uniform + Freeform. |
| **6** | **Bake to cels** | §6. Shares its frame-walker with ROADMAP (5). |
| **6b** | **The playback cache** | §4.6. Only stage 8 actually needs it — per-object animation fits the budget without it — so it lands beside the transformation layer, not before it. |
| **7** | **Live recording + editable fps** | §5. Needs the playback clock hoisted onto the model first. |
| **8** | **The transformation layer** | §4.4. Late because §4.6's cache is its real cost, and because it is the only stage that needs one. |
| **9** | **Real Distort** | §2.13. Raster tier first (the gesture is `TextFrameDrag.distortedFrame` and the bake is `ImageWarp`), then ink through §4.2's point map, then placed images behind Move stage 3c. |
| **10** | **The timing recorder** | §7. Small, sits on 7. |

**Stage 0 has one prerequisite that is not in this feature and is worth doing first anyway.** Derived
content is invisible to `PixelOps.rasterize(cel:)`, so thumbnails, ordinary onion skin and export see an
animated cel as **empty** — VECTOR_INTERPOLATION item 18, which names the fix as a passed-in
`ContentProvider` and **not** a back-reference from `Cel` to the manager. Every derivation source
inherits that hole at once, and it is the same gap ROADMAP §0 flags as blocking item (5). It is the
highest-leverage groundwork on the roadmap: it serves bake, export, thumbnails and onion skin, for both
animation systems.

---

## 9. Open questions

1. **What does an invalid in-between pose do?** §4.3's factored blend makes validity much easier to
   preserve but does not guarantee it. Clamp to the last valid pose (never draws anything broken, can
   visibly stutter), or refuse the key pair when it is authored (predictable, needs a message, can
   refuse a pair that only fails for a few frames)? **Cheap now, expensive once keys are on disk.**
2. **A value layer below a transformation layer has two irreconcilable readings.** In flat-colour mode
   it is a full-canvas sheet, so posing it means posing a quad and leaving transparency outside —
   plausible. In *effect* mode it holds no pixels at all and grades the accumulator, so there is nothing
   to pose. Same layer kind, two answers.
3. **What happens to a curve whose two keys have different cardinality?** Two of the thirteen effects
   have variable-length parameter arrays — `Curves.points` and `GradientMap.stops`. Tweening a 3-point
   curve to a 5-point curve needs a definition or a refusal.
4. **Where does the playback cache's disk tier live, and do cached spans outlive the session?**
   §4.6 settles that a disk tier is required rather than optional — 64 MiB of memory is about 32 frames
   at preview resolution and a 48-frame span does not fit — and recommends `Library/Caches` over the
   `Documents/` sibling-folder pattern `ProjectBackupManager` established, knowingly departing from the
   only local precedent because the OS purges Caches under disk pressure and excludes it from backup.
   Unruled: whether a span survives a relaunch at all, and what sweeps it if the OS does not.
5. **Do generated in-betweens visibly boil today?** The interpolation evaluator *already* re-walks the
   dab lattice per in-between under a non-uniform map — the exact artifact §4.2 exists to prevent. If
   they look clean on the iPad, this whole risk is smaller than it has been sized. **Asked; unanswered.
   It needs the device, not a test.**

## 10. Traps inherited from elsewhere

- **`InterpolationPreviewKey` must carry every input the evaluation reads** (`Views/CanvasView.swift:2116-2135`).
  VECTOR_INTERPOLATION settled fact 11: *"It has bitten three times."* Omission is silent — the canvas
  shows a stale frame forever. **But the rule is narrower than it sounds, and stage 2 established
  where the line is**: that key covers the in-between *drawing* evaluation — lattice and ARAP over
  vector geometry — so it binds **object** channels, which feed the evaluator. A layer-scoped grade is
  applied at composite time through `RenderNode.effect` and is not an input to it, so stage 2 owed the
  key nothing. Ask which side a new channel falls on rather than adding a field reflexively.
- **The compositor comes off the live canvas whenever an in-between is under the playhead.**
  `isSandwichEngaged` (`CanvasView.swift:1021-1030`) returns false if *any* layer's active cel carries a
  recipe, so blend modes, effects and masks fall back to Core Animation for that frame. An effect
  parameter animated near an interpolated cel is authored against a path where effects are off.
- **0.8 s matches nothing that ships.** Every long-press in the app is 0.5 s (row and block reorder) or
  0.0 s (tool touch-down). It must be a real gesture recognizer — not a `.contextMenu`, which absorbs the
  whole touch, and never `UIDragInteraction`, which **XCUITest cannot drive at all** (verified;
  `Views/LayerStackListView.swift:13-18`). Keep it off any element that already carries a 0.5 s press:
  *"Two long presses of equal duration competing for one touch have no stable winner"*
  (`Views/MotionGroupRow.swift:5-8`).
- **Timeline markers collide at minimum zoom.** `pixelsPerFrame` bottoms out at 10.5, and `CelBlockView`
  draws one thumbnail across the whole cel with **no per-frame subdivision at all** — plus resize-handle
  bars at each end. Key markers need a zoom-aware collapsed form, drawn in the UIKit coordinator rather
  than as a SwiftUI overlay, for the reason `TimelineTrackView.swift:4-17` already gives.
- **A test class is often not named after its file here.** `InterpolationWorkflowUITests` lives in
  `TimelineAndUndoUITests.swift`; `LayerPanelUITests` lives in `LayerUITests.swift`. A `-only-testing:`
  selector derived from a filename matches nothing and reports **success**.
- **`ImageWarp` is documented as wrong for a per-frame path** — it uploads and reads back per call,
  *"exactly right for a bake that happens once at commit"* (`Engine/ImageWarp.swift:240-241`). A keyframed
  distorted text box or placed image is one GPU round trip per in-between at bake time.
