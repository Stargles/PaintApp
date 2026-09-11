# The transform layer and its five modes — TODO (61)

Design document, 2026-09-11, written at `73149b6` and ruled the same day. **§2 is the seventeen
rulings; §8 is the build order and says what has shipped.** §3–§7 say what each mode wants and the
cost of each alternative. Read KEYFRAMES.md §2, §3.1, §3.6 and §4.4 first — the transform layer's
model and render path are specified there and this document does not restate them.

## 0. What is already true — verified at `73149b6`, amended for stages 0 and 1

- **A transformation layer is a `.transform` layer carrying `Layer.transform: LayerPose`** — a stored
  `PoseQuad` (box + four corners), a `TransformTrack` in **absolute document frames** (§3.1), and a
  held `baseline` for §2.27's gap. `Layer.layerTransform` is `kind == .transform ? transform : nil`;
  **the kind is the discriminant** (ruling 2, stage 0). It was the third mode of `.value` until
  2026-09-11, chosen by presence with the precedence effect, then transform, then flat colour; a
  document saved that way decodes as the new kind (`LayerKind.migratingTransformModeValueLayers`).
  `LayerFolder.transform` is the same `LayerPose` on the folder (§2.21's twin).
- **It is applied in one place and never reaches the compositor.** `RenderTree.renderNodes(inContainer:
  atFrame:inheriting:poses:)` walks each container bottom-to-top, composes every transform layer's
  `mapping(atFrame:)` into `accumulated`, and records a per-entry `carried[position]` — an array,
  already per entry, assigned uniformly today. The result is `[layerIndex: PoseMap]`, spent in
  `leafSnapshots` on three consumers off one value: the vector derivation (§2.3's re-pose), the
  raster tiers' CTM (`PixelOps.FrozenCel.pose`, §2.12), and `LayerContentVersion.pose` (§4.5). A
  folder's own pose is composed on the way into its recursion ("inner first").
- **Scope is structural**: `carried` is a local, so a pose cannot leave its container; inside a
  compositor node the sibling carry is suppressed. **The accumulator reads the block** (ruling 1,
  stage 1): it composes a layer's pose only where `activeCelIndex` finds a cel, and the leaf
  derivation resolves a value layer's grade under the same test. **It reads `isVisible` too — shipped
  2026-09-11, BUGS.md's filing, both gates composing rather than one replacing the other**: a hidden
  transformation layer used to pose exactly as a shown one, where a hidden grade grades nothing;
  every mode below inherits both fixes.
- **The Move box is `FloatingPieceKind.containerPose`**, a box the size of the canvas with no pixels;
  `showContainerPoseLive` writes the pose on every tick so the preview *is* the render path;
  `commitContainerPose` routes through `KeyframeControl.write`'s five-arm rule and **every arm writes
  the stored base** (`LayerPose.resolvedPose` is a precedence, not a composition). `seedingContainer`
  seeds the *old* pose onto the immediate neighbouring keyframes. The graph band draws the pose as six
  decomposed rows (§11.7), per component.
- **The block gates it** (ruling 1, stage 1). `beginContainerPoseMove` refuses a transform layer's
  box at a frame its bar does not cover, with `CanvasNotice.moveOutsideTransformBlock`; before the
  ruling its cel gate had been deleted because `renderNodes` composed the pose *"with no cel test at
  all"*. The flat colour was always gated (`leafSnapshots` resolves it only where `activeCelIndex`
  finds a block); **the grade was not** — the compositor reaches a grading leaf by `node.effect`
  before it looks for a source — which is what BUGS.md's 2026-09-03 filing half-missed, and stage 1
  gates it in the leaf derivation so one rule covers every pixel-less leaf. `newLayerBlockLength` is
  `contentEndFrame`, so a new pixel-less layer's block already reached the scene's end at creation;
  the layer *"made early and used late"* is the one the scene grew past, and lengthening its bar is
  the timeline's own Extend to End. **TODO (62) sharpened the split, and its own review reversed the
  transform-layer half of it (2026-09-11, worktree `txcrop`)**: a cel's pose keys are cropped to its
  span; `effectTracks` is untouched *by construction* on every kind (a grade's channel is not gated by
  a block); but a `.transform` layer's own `channelTracks` (its mode scalars), `keyframeMarks` and
  `transform.track` now crop to the union of the layer's blocks exactly as a cel's keys crop to its
  span — ruling 17 was "kept, inert" and is now "cropped, with a boundary key first," on the owner's
  own *"I don't care about data loss if the cel is shortened then expanded."*
- **`TargetChannel` is the descriptor for "one `Double` a layer or folder owns"**: an undotted id,
  ui range, model domain, two labels and **a `WritableKeyPath` into each of the two homes**. One
  row in `TargetChannel.all` buys storage in `channelTracks`, a place in `KeyframeState` and §2.28's
  union, persistence, the recorder and the graph band. It needs the property on **both** structs.
- **`Effect` is an enum with associated values**; both backends run its `passes` and switch on no
  case. `EffectParams` is a flat block that already carries `offsetX/offsetY` (chromatic
  aberration's displacement), `colorR/G/B` (Outline's stroke), `mix`, `amount` and a `seed`. An
  effect declares its `Input` (`.backdrop` or `.ink`, the latter a re-walk into a transparent buffer
  — EFFECT_BACKDROP §3 option A), `reshapesCoverage`, `verticalKernelRadius(frameHeight:)` for
  RENDER §3.8's strip apron, and `readsAbsolutePosition`. A multi-pass combine may read the effect's
  original input as a constant binding (bloom). **No effect has a Move box, and no effect has a blend
  mode of its own** — the layer's stored mode is pinned to `.normal` while it grades.
- **`PoseInterpolation.blend(a, b, t:)` extrapolates** outside 0…1 and takes the nearer key when
  the result goes singular (KEYFRAMES §9.1). `FrameBakeKey` carries **no frame**: two frames whose resolved
  tree and leaf versions are equal are one file.

## 1. The ask

The owner, 2026-09-10 (TODO (61) carries the full text):

> *"make the transform layer its own layer type instead of attached to the value layer. Additionally,
> add these modes to it: parralax, rotate, repeat, screen shake, duplicate offset."*

Parallax distributes a Move over *"the child layers or groups directly under it"* — a folder is one
item — by a per-child percentage, default *"100%, 75, 50, 25"* for four, slider 0–100 accepting values
outside. Rotate takes a *speed*, turns about *"the center of the box"*, and gets perspective ellipses
*"if the user wishes to switch to distort"*. Repeat *"will simply repeat the cels under it in a loop
until the repeat cel ends"*. Screen shake is *"Shake x, shake y, rotate shake sliders… so that they
can be keyframed"*. Duplicate offset copies what is beneath, flattens it to a colour, is offset or
resized by a Move box, and is blended back where the original is present and the copy is not (rim,
the default) or where both are (intersection) — *"this may not belong in the transform layers… I
prefer value layer effect but do whatever is cleanest."*

## 2. Rulings — settled 2026-09-11, do not re-litigate

Seventeen questions were put to the owner in the wording quoted below (each was answerable without
reading anything in this repo, and carried a recommended answer); every one is now ruled. Questions
1, 2, 7 and 13 were answered in the owner's own words; the rest took the recommendation as written.

1. **The bar means "only here", for every mode.** *"Does a transform layer's bar in the timeline mean
   'only here'? … Should the end of the bar mean* stop here *— the drawing goes back to normal from
   25 on? The same would then hold for Rotate (spin from where the bar starts, stop where it ends) and
   Shake."* Yes. Outside its block a transform layer does nothing; §4's gate is the rule and stage 1
   built it — the accumulator composes a pose only where the layer has a cel, a Move raised outside
   the bar is refused with a notice, and a new layer's bar reaches the scene's end.
2. **"Transform Layer" is its own layer type** — a fourth `LayerKind`, its own `+` entry, no longer a
   mode a value layer is switched into. *"Should 'Transform Layer' be its own entry in the + menu,
   with its own panel for the five modes — and you can then no longer turn a value layer into a
   transform layer or back?"* Yes. Existing documents' transform-mode value layers migrate on open;
   an older build cannot open the new document. Stage 0.
3. **Parallax: only things that draw pixels count as items.** *"If there is also a colour tint (a
   value layer) sitting between them, should the tint count as one of the items … or be skipped? A
   folder counts as one item and nothing inside it is split up."* Skipped.
4. **Parallax: a number you typed stays.** *"Should the other four keep their numbers (only the new
   one gets a default), or does everything re-default? And if you drag that back layer out from under
   the Parallax layer and later back in, should it still say 10%?"* Typed numbers stay; new layers
   get the default for their position; a layer remembers its number when it leaves and comes back.
5. **Parallax: the percentage is keyframable.** *"Should a layer's percentage be something you can
   keyframe?"* Yes; it costs nothing.
6. **Rotate: speed is degrees per frame.** *"At 24 fps, a wheel set to 15° per frame turns once a
   second. If you then set the document to 12 fps, should the wheel still turn once a second on
   screen … or once every 24 frames?"* Per frame — what every other animation in the document does
   when the fps changes; the panel can also show "frames per turn".
7. **Rotate: a keyframe does not pause a spinning wheel.** *"If you place a keyframe on a Rotate
   layer, should the spin pause there (like a hold), or keep going while only the box's position
   holds?"* Keep going; key the speed to 0 to stop it.
8. **Rotate in perspective is Distort on the box.** *"You use Distort on the Rotate layer's box to lean
   it into a keystone; the wheel then travels in an ellipse on screen. Is that the 'rotating in
   ellipses' you meant?"* Yes, and nothing else is built for it.
9. **Shake: the box is the thing that shakes, and a shake is the same every time.** *"If you had first
   scaled the shake layer's box up 2× with Move, should a 10 px shake move things 10 px on screen or
   20? And should the shake be the same every time you play … with a 'new shake' button?"* 20; yes,
   with the button.
10. **Shake: one slider for how fast, not keyframable to start with.** *"Besides how far it shakes, do
    you want a slider for how* fast *— a new position every frame, or a smoother wobble?"* Yes, one.
11. **Repeat: you type the loop's length, pre-filled from where the drawings beneath end.** *"(a) You
    type 8. (b) It looks at where the drawings beneath it end — but then a background under it that
    runs to 48 would stop the walk looping."* (a), with the number filled in from (b) at creation.
12. **Repeat: everything beneath repeats.** *"If a layer beneath the Repeat also fades in over frames
    1–8 (opacity keyframes), does the fade repeat every cycle too, or only the drawings?"* Everything —
    what the first cycle looks like is what repeats.
13. **Repeat: drawing on a repeated frame lands on the original drawing it repeats.** *"At frame 13,
    which is showing drawing 5 again, you draw a line. Should it go onto drawing 5 (and so appear in
    every cycle), or should drawing be refused?"* Onto drawing 5.
14. **Duplicate offset paints only inside the drawing: rim and intersection.** *"Both are inside the
    original drawing's own outline, so this can never paint* outside *it … Is that right, or do you
    also want a third choice, 'where the copy is and the original is not'?"* Rim and intersection
    only, as asked.
15. **Duplicate offset's box slides, resizes and rotates — not Distort.** *"Enough?"* Yes.
16. **Duplicate offset blends with a layer blend mode at an opacity.** *"Is that the whole of 'blend it
    with whatever is underneath'?"* Yes.
17. **Keyframes past the bar are kept and inert, never deleted.** *"If you shorten a transform layer's
    bar past one of its keyframes, should that keyframe be deleted (as a drawing's keyframes now are
    when you shorten its block), or kept and simply do nothing until you lengthen the bar again?"*
    Kept — a layer's keyframes are drawn on its row whatever its bars do, so nothing is hidden; a
    layer may have several blocks, and they come back into force when the bar is lengthened. Stage 1.
    **Reversed 2026-09-11, on being shown the consequence drawn** (TODO (62), worktree `txcrop`): *"why
    are there keyframes outside of a transform cel? … I'm pretty sure I explicitly wanted keyframes to
    be clamped to inside the cels. … I don't care about data loss if the cel is shortened then
    expanded."* A transform layer's own tracks — `transform.track`, its mode scalars in
    `channelTracks`, and its `keyframeMarks` — now crop to the union of its blocks
    (`CanvasManager.transformLayerBlockCoverage`) exactly as a cel's own pose keys crop to its span
    (TODO (62)'s own rule, one level up): a boundary key lands on the new edge first, carrying the pose
    or value the track showed there, so the frames that remain keep the motion they had. §0's and §4's
    paragraphs below are corrected in place rather than left standing against this.

## 3. Homes — how many, and why

### 3.1 Three shapes, not five modes

| mode | what it produces, per frame | acts on |
|---|---|---|
| Move (today), **parallax**, **rotate**, **shake** | a **pose** per entry beneath it | the geometry, before rasterisation (§2.3) |
| **repeat** | a **frame** per entry beneath it | which cel — and which key, which opacity — each entry shows |
| **duplicate offset** | pixels | the accumulator, after rasterisation |

The first five share one property that repeat has too and duplicate offset does not: **a leaf with no
pixels whose whole effect is spent in the tree walk on the entries beneath it, in its own container.**
That is exactly what `renderNodes`' carry is — today `carried[position]` is a `PoseMap?`; widened to a
**view**, `(pose: PoseMap?, frame: Int)`, the same array carries a repeat's remapped frame beside a
transform's pose, spent at the same place (`leafSnapshots` asks `activeCelIndex(inLayer:atFrame:)`,
`provider.content`, `contentVersion` and — inside `renderNodes` — `layerEffect(atFrame:)`,
`opacity(atFrame:)`, `resolvedPoseMapping(atFrame:)` at the *carried* frame rather than the walk's).
Repeat is not a pose, and the document says so rather than pretending; but it is the same *kind of
leaf* with the same scope rule, and the owner listed it with the others. So **two homes**:

1. **The transform layer**, with five modes — Move, Parallax, Rotate, Shake, Repeat.
2. **`Effect.duplicateOffset`**, a case of the value layer's grade, which the owner already preferred.

### 3.2 "Its own layer type" — a new kind, or a mode on the payload

**Option A — a fourth `LayerKind`, `.transform`.** `Layer.transform` becomes that kind's payload and
gains a `mode`; the value layer keeps `effect` and `fill`; §2.6's row loses its Transform entry; the
`+` menu gains "Transform Layer"; the layer's options panel is a mode picker. Cost, counted:
**no exhaustive `switch` over `LayerKind` exists** (its own doc says so and a grep confirms — every
reader asks `kind == .value` or an accessor), and there are **twelve** code sites asking `kind ==
.value` (`Layer.hasNoDrawingSurface`, `isFillReference`, the three accessors, the three payload
writers and `setLayerBlendMode` in `CanvasManager`, `OnionSkinSource`, two in `LayerPanel`), each a
one-clause widening — and `setLayerBlendMode`'s `clearsTransform` arm simply goes. The manifest's
`kind` string gains `"transform"`, and a document saved with a `.value` layer carrying `transform`
migrates on decode in one line beside `LayerKind.decodeMigratingEffectLayers` (`transform != nil &&
effect == nil` → `.transform`). **An older build cannot open the new document at all** — an unknown
kind throws and `ProjectStore.load` answers nil for the whole project — which the standing
no-migration permission covers and which should be said. What is lost: §4.4's grade ↔ transform flip
("picking a grade leaves the pose stored and inert, flipping back restores the move *and its
keyframes*"), which the owner never asked for and which was a consequence of the payload recipe.

**Option B — keep `.value`, add `LayerPose.mode`, give the transform layer its own `+` entry and
panel.** Cheapest by a day; but the ask was a type, not an entry, and the three-payload recipe with a
stated precedence is at its limit — a fourth payload (repeat's period) with a fifth clause in
`valueFill` is the shape `Layer.effect`'s own doc argues against.

**A was ruled (ruling 2) and is stage 0, shipped.** The count above was the whole cost — the twelve
sites became `LayerKind.holdsPixels` where they were spelling that property and a kind test where they
were not; three exhaustive switches did exist after all (`Tool.textUnavailableReason`,
`CanvasManager.selectionMembershipUnavailableReason`, `CanvasActiveLayer.init(kind:)`) and answered the
new case at compile time, and `LayerKindLogicTests` walks `allCases` through all of them. It removed
the "you had to use the feature to be told how to use it" entry §4.4 paid for: an artist adds a
*Transform Layer* and its panel is a mode picker (Move alone until §8's later stages) and the Move row.
`setLayerTransform` and `HistoryActionLabel.valueLayerTransform` are gone; `addTransformLayer` and
`.addTransformLayer` replace them; the migrated layer's inert `fill` is dropped on decode, as is a
`.value` layer's pose left under a grade.

### 3.3 The modes' parameters are `TargetChannel` rows, not a third channel kind

Rotate needs a speed; shake needs three amplitudes; parallax needs a share **on each child**. Each is a
`Double` the artist keys. The precedent that fits is `TargetChannel` — *"a blend amount or an effect's
overall strength costs one more entry in `TargetChannel.all` and nothing else"* — so `rotateSpeed`,
`shakeX`, `shakeY`, `shakeRotation` and `parallaxShare` are five rows and five stored `Double`s. The
alternative, an `EffectParameter`-shaped descriptor family over a `TransformMode` enum with its own
track dictionary, is a third channel kind: a new store, a new union arm, a new persistence key, a new
recorder arm — every cost §3.6 lists as the reason `TargetChannel` exists.

**The row needs the property on `LayerFolder` too**, and the honest answer is that
`LayerFolder.transform` takes the four pose modes as well (not repeat: a folder has no block). The
accumulator's `inner` line reads the mode exactly as the layer's does. Declining that leaves five
keyable rows on a folder that key nothing — §2.23's dead control by a new door — so it is not optional
if the rows are. **Built in stage 2–3**: a folder's pose goes down its recursion as the topmost poser of
the folder's own stack rather than as a map composed onto `outer`, which is the only place a folder in
Parallax can hand each child its share; the folder's panel carries the same Mode picker and rows. **A
folder in Rotate integrates from frame 0**, since it has no bar to start from — the one place the two
homes differ, and a question for the owner if a folder's spin should have a start of its own.

What is **not** keyable lives on `LayerPose` beside the mode rather than on the two homes: repeat's
period (`repeatPeriod`), shake's frequency (`shakePeriod`) and seed (`shakeSeed`) — three fields, each
encoded only when it is not the default, so a pose in Move writes the manifest it wrote before. **Built
in stages 4 and 5**: that placement is what makes a folder's pose carry the shake's seed for free and
what keeps "a seed never outlives the pose it qualifies" structural, `LayerPose.track`'s own argument.

### 3.4 Duplicate offset is an `Effect`, and here is what it strains

It reads what is beneath (paper excluded — `Input.ink`, the re-walk that Outline and Bloom already
take), flattens the copy to a colour with the coverage kept, resamples that copy through a box, derives
**rim** = `orig.a · (1 − dup.a)` or **intersection** = `orig.a · dup.a`, and paints the colour there
through a blend mode over the accumulator. Both regions are subsets of the original's coverage, so it
**never reshapes coverage** — it is an adjustment in the strict sense, and it cannot draw a shadow
*outside* the drawing (§2 ruling 14). Two passes: a resample (the copy, gathered through the box's inverse
map, bilinear — chromatic aberration's tap generalised from a translation to an affine) and a combine
that reads the original as bloom's combine does. What it needs that no effect has:

- **A Move box as a writer.** The box's five numbers — offset x, offset y, scale x, scale y,
  rotation — are ordinary scalar `EffectParameter`s (keyable through `effectTracks`, drawn by the
  band, sliders in the bar), and a `FloatingPieceKind.effectBox` whose commit writes those five is a
  *second writer* onto them. Distort is refused by kind, as a placed image's is
  (`distortUnavailableReason`), since five scalars cannot hold a keystone.
- **A colour**: `Outline.color`'s exact shape, `colorR/G/B`, refused at the writer as not animatable.
- **A blend mode inside a kernel.** The Metal side is a `switch` on a mode code calling the blend
  functions `Composite.metal` already holds. The CPU twin is the cost: `Compositor.coreGraphicsBlendMode`
  reaches **nine** modes through CoreGraphics (normal, multiply, screen, overlay, darken, lighten, hard
  light, difference, exclusion) and hand-rolls the other sixteen; a per-pixel combine cannot go
  through CoreGraphics, so those nine separable formulas have to be written in Swift beside the
  sixteen and pinned byte-for-byte against the Metal ones (`EffectParityLogicTests`' gate). Bounded —
  the sixteen harder ones exist — and still the largest single item in this document.
- **Strips.** `verticalKernelRadius` is the box's largest vertical displacement over the frame's
  corners, plus one for the bilinear tap; `readsAbsolutePosition` is true, since the box is about a
  point in the frame. A large offset makes a large apron, which the planner already degrades to a
  whole-frame composite.

**Not a fourth payload of the value layer**: it grades the accumulator and needs nothing a grade does
not already have a home for, and a payload would have to reinvent `Input`, the strip apron and the
parity gate for one effect.

## 4. The span — which time base each mode lives in, and whether the block gates

This became a live question with TODO (62): a transform layer's keys are document-level, so shortening
its block crops nothing and it keeps posing on frames where it has no block. The five modes make the
question unavoidable, because **three of them need a start or a stop that nothing but the block can
supply for free**: rotate needs an origin frame, shake needs an end, and repeat's loop *is* its block
(*"until the repeat cel ends"*). Two coherent answers:

**Gate — the block is the span, for every mode and for the grade and flat colour too.** A pixel-less
layer acts on the frames its block covers and nowhere else. Rotate's angle starts at the block's first
frame; shake runs while the block runs; repeat loops within it; Move poses within it. Its keys stay in
absolute frames (§2.4 stands). **Reversed 2026-09-11 (TODO (62), worktree `txcrop`), on the owner's own
*"I don't care about data loss if the cel is shortened then expanded"*: a transform layer's own tracks
— `transform.track`, its mode scalars in `channelTracks`, `keyframeMarks` — are no longer inert outside
the block; they crop to the union of the layer's own blocks exactly as a cel's own pose keys crop to
its span, a boundary key landing on the new edge first so the frames that remain keep the motion they
had.** Opacity, and every layer-wide channel no mode reads, stays exactly as it was — it is not gated
by a block at all (an opacity key on a frame the layer has no cel on is in force today, same as ever),
so there is no "outside the block" for it to be inert or cropped in. What goes with the old rule is the
gap trick it made possible — a key placed between two of a layer's blocks purely to interpolate the
pose across the space between them — since a gap key is exactly a key outside every block, and is
pruned the next time either bordering block's span changes. BUGS.md's value-layer filing closes as *the
default is wrong, not the gate*: a new pixel-less layer's block is stamped to the scene's end, and
lengthening it after the scene grows is the timeline's own Extend to End, exactly as a held background
is. A Move raised at a frame outside the block is **refused with a notice naming the block**, which
reverses §4.4's deletion of that gate — there was nothing to refuse then; there is now.

**No gate — a transform layer is a rule, not a drawing.** It acts at every frame; time extent is
expressed with keys (speed to 0, amplitude to 0), rotate needs a start-frame number of its own, and
repeat is the exception that takes its extent from a block anyway — or from a start, a period and a
count. Two rules for one layer type.

**Gating was ruled (rulings 1 and 17) and is stage 1, shipped.** It is the owner's own vocabulary in
(62) and in *"until the repeat cel ends"*, it is what every timeline the owner has used does with an
adjustment layer's bar, and it makes the three time-function modes need no control they do not
already have. What stage 1 found while building it: the flat colour was already gated and **the grade
was not** — `Compositor.draw` reaches a grading leaf by `node.effect` before it looks for a source, so
`leafSnapshots`' cel test never reached it, and a 12-frame adjustment layer went on grading a 48-frame
scene while its bar visibly ended at 12. The value layer's two modes disagreed about what its own bar
meant. Stage 1 gates the grade in `RenderTree.renderNodes`' leaf derivation beside the pose gate, so
one rule covers every pixel-less leaf and both backends agree by construction (the tree is the same
tree). **That changes what an existing document with a short adjustment-layer bar looks like past
the bar**, which the standing no-migration permission covers and the fix for is Extend to End on the
bar. And the default was already right: `newLayerBlockLength` is `contentEndFrame`, so BUGS.md's
value-layer filing closed as *the bar is right, and the layer the scene grew past is lengthened from
the timeline*.

| mode | keys stored | time base | block |
|---|---|---|---|
| Move, Parallax | authored pose track, on the layer | absolute document frames (§2.4) | gates application; keys outside inert |
| Rotate, Shake | authored pose track + `TargetChannel` scalars | absolute | gates application, **and is the function's origin** |
| Repeat | none | absolute for the loop; the entries beneath are asked at a remapped frame | **is** the loop's extent |
| Duplicate offset | `effectTracks` on the value layer | absolute | gates, as every grade's does today |

## 5. The modes

### 5.1 Move — unchanged

Everything in §0 stands. Under a new kind it is `TransformMode.move` and the default.

### 5.2 Parallax

**Who is an item.** The entries beneath the parallax layer *in its own container* — `renderNodes`'
`stack` — top to bottom: a layer with a drawing surface is one item, a folder is one item and its
contents are not, and **a pixel-less layer (any transform layer, any value layer) is not an item and
takes no share**, so a tint dropped between two drawings does not shift the defaults (§2 ruling 3). Item
*k* of *n* defaults to a share of `(n − k + 1) / n` — 100/75/50/25 for four, the top item nearest the
parallax layer moving most.

**What a share of a pose is.** `PoseInterpolation.blend(rest, P, t: share)` — for a translation
exactly `share × P`; for a scale or a turn the factored blend, which is the one interpolation §2.15
allows; and beyond 0…1 the extrapolation the owner asked for (*"negative values or higher"*), clamped
to the nearer end only where it goes singular (KEYFRAMES §9.1). No new arithmetic.

**Where the share lives: on the child, nil meaning "positional default".** `Layer.parallaxShare` and
`LayerFolder.parallaxShare` as a `TargetChannel` row (§3.3), so it is keyable for free and the share
follows its layer through reorder, survives being dragged out from under the parallax layer and back
(inert storage in between, `valueFill`'s own asymmetry), and is destroyed by nothing but the artist.
Adding an item gives it the positional default and leaves explicit shares alone; two parallax layers
over one set compose, each through the child's one share. The alternative — a `[UUID: Double]` on the
parallax layer — dies with it, dangles on delete, cannot be keyed without a channel kind that does not
exist, and has to be recomputed on every add. **What stage 2 found building it**: a `TargetChannel`
key path is `WritableKeyPath<_, Double>` and cannot address an optional, so the row reaches the field
through a non-optional view (`parallaxShareValue`, nil reading as 1) and the render reads
`parallaxShare(atFrame:positionalDefault:)` instead; and because the channel funnel seeds keyframe A
from the *stored* number, `CanvasManager.setParallaxShare` writes the positional default through
before the first edit is routed, so A holds the 75% the artist was looking at rather than the view's 1.

**The accumulator.** On meeting a parallax layer at position *p*, each item *q* below it takes
`blend(rest, P, share(q))` composed onto whatever `carried[q]` already holds from transform layers
lower down; a folder item passes its share's pose into its recursion as `inherited`. `carried` is
already per entry; only the assignment stops being uniform.

**What the artist sees while dragging.** The Move box is the parallax layer's own — it moves 100% —
and the preview is the render path, so each item moves by its share under the finger with nothing
new to build. The panel lists the items with a slider each, defaults shown greyed until touched.

### 5.3 Rotate

**Pose at frame *f*** = `authored(f) ∘ R(θ(f))` about the **box's own centre, in box space** — the
rotation is applied *before* the stored quad's map. That order is the owner's perspective trick: a
circle in box space through a keystoned quad is an ellipse on screen, so Distort on the box gives
*"rotating in ellipses like they are in perspective"* with no second mechanism. The box's own
rotation (a Move) is the start angle for free.

**θ(f) = Σ speed(k) for k from the block's first frame to f − 1**, speed in **degrees per frame**
(§2 ruling 6), a `TargetChannel` row so it is keyable — and *integrated*, so a speed keyed 0 → 15 is a
wheel spinning up and a speed keyed to 0 is a wheel that stops where it is, rather than
`speed(f) × (f − f0)`, under which a keyed speed snaps the wheel backwards. A block restarts the sum;
several blocks are several starts.

**A keyframe holds the authored pose and the speed, not the angle** — see §6. The graph band draws
the authored pose's six rows and the speed row; the spin itself is not a curve and is not drawn, which
is §11.7's *"two truths, neither bent onto the other"*.

**`LayerPose.movesItsContents` must read the mode**: a rotate layer with an untouched box and a
non-zero speed moves everything beneath it, and that predicate is frame-invariant by contract.

### 5.4 Screen shake

**Pose at frame *f*** = `authored(f) ∘ T(ax·n₁(f), ay·n₂(f)) ∘ R(ar·n₃(f))`, in box space about the
box centre — one rule with rotate, and the same consequence: a box scaled 2× by Move shakes twice the
pixels (§2 ruling 9). With the default box, the whole canvas shakes about its centre, which is a screen
shake.

**`ax`, `ay`, `ar` are three `TargetChannel` rows** (the owner's *"so that they can be keyframed"*),
amplitudes in canvas points and degrees. **`n₁…n₃` are value noise**: a hash of `(seed, channel, beat)`
mapped to −1…1 at integer beats, smoothstepped between beat `⌊f / period⌋` and the next — the app's own
deterministic hashes (`DabRandom`, the effect kernel's `noiseValue`) are the shape. `period` in
frames is the **frequency** control (1 = a new position every frame); **not keyable at first**, since
a varying period needs phase integration to avoid jumps, exactly rotate's argument. `seed` is minted at
creation and re-rolled by a button, undoable, so two shake layers differ and one is stable.

**Determinism is by construction and must be pinned.** The resolved pose is a pure function of
`(seed, period, amplitudes at f, f)`; it reaches `LayerContentVersion.pose` and `FrozenCel.Identity.pose`
through the one value `leafSnapshots` already spends, so RENDER's *"the same frame renders the same
bytes"* holds and `FrameBakeKey` sees every jolt. Accepted consequence: a shake defeats the hold
dedupe (every frame is a different key) and §4.5's flatten memo for every leaf beneath it on every
frame — the "six-layer container, ~22 ms" row — which the bake absorbs and the live canvas does not.

### 5.5 Repeat

**A frame remap carried down the container.** For a repeat layer whose block starts at *s* with
period *p*, an entry beneath it asked at frame *f* in the block is shown at `s + ((f − s) mod p)`.
The first cycle is the identity. Everything beneath repeats — the cels, their cel-local keys (which
ride for free, §3.1), the entries' opacity and effect curves, and a transform layer beneath it — because
*"what the first cycle looked like"* is the only picture the loop can honestly show (§2 ruling 12).

**It hits the frame store with no new key field.** `FrameBakeKey` carries no frame; a repeated
frame's tree and leaf versions are the source frame's, so it *is* the source frame's file. A repeat
costs the bake nothing and needs no test of its own beyond pinning that equality.

**The period is a number on the layer**, pre-filled at creation from where the cels beneath end
(§2 ruling 11), never inferred at render time — a background running the whole scene beneath the walk
would otherwise silently stop the walk looping.

**Editing on a repeated frame is the trap, and it has the shape of CLAUDE.md's case 3.** At frame 13
showing frame 5, `activeCelIndex(inLayer:atFrame: 13)` finds no cel and `ensureCelAtCurrentFrame`
would mint a one-frame block the artist cannot see. Every "at the playhead" read on an entry beneath a
repeat — drawing, the Move box, the settings bar, `effectiveOpacity`, the channel-list navigator,
§3.4.1's compensation frame — has to go through the remap or refuse. **The redirect was built (stage
5, ruling 13)**: the edit lands on the source frame's cel (§5.27's *"a lasso means what it means on
screen"* applied to time), with the timeline drawing the repeated span as ghost blocks so the artist
can see it is one. `CanvasManager.displayedFrame(forLayer:atFrame:)` / `displayedCelIndex` read the
render walk's per-leaf source frame (behind a one-scan exit for documents with no Repeat), and **the
drawing path goes through them**: `ensureCelAtCurrentFrame` (which also *spawns* at the source frame
when it is empty), the live host's tiers, the stroke's lift, the spawned block, the selection clip, the
live derived preview, the thumbnail install, `activeLayerIsVector` and an imported image. **What still
reads the playhead's own frame, and is the remainder**: the Move box and the lasso (`SelectionModels`,
`CanvasManager+LassoMove`), text and shape placement, animation-group membership, the panel row's
thumbnail and the onion skin. On a repeated frame those see the cel the playhead sits on — a held block,
or none — exactly as they would on an empty frame today, which is the silent half of case 3 and is
listed here rather than left to be found. The ghost blocks are `TimelineRepeatGhostBand`: one dashed
outline over a dark wash per run of one source drawing, computed structurally
(`repeatGhostSegments`, the layout key cannot afford a walk per frame) and pinned against the walk on
a nested fixture.

**Not a cel operation.** Duplicate is a copy and Extend to End is a hold; both are destructive of the
relationship. A repeat is a reference — edit the walk once and every cycle follows — and it applies to
everything beneath, which no cel operation can express.

### 5.6 Duplicate offset

§3.4 is the design. The artist's surface is the value layer's Effect list: **Duplicate Offset** with a
colour swatch, a Rim / Intersection toggle (rim default), a blend-mode picker, a Move-box row that
raises the box, and the five scalars as sliders. Opacity of the effect is `mix`, as every grade's is.

## 6. What a keyframe means on a mode whose pose is a function of time

The (62) review found that the key writers — `seedAndKeyPose`, `poseDeltaForKeyframe`,
`seedingContainer` — seed neighbours from the layer's marks. A layer whose pose changes every frame
without a key has to say what a mark holds and what seeding writes, or the writers key the wrong
thing.

**The answer is a factorisation, and it costs the writers nothing.** The pose is
`authored(f) ∘ mode(f)`: `authored` is today's `LayerPose` — the stored quad, the track, the baseline,
written by the Move box and keyed by exactly the arms that exist — and `mode(f)` is a function of the
`TargetChannel` scalars and the frame that **never writes a key and is never seeded**. A mark on a
rotate layer holds the authored pose and the speed (both through the funnels that already exist);
the angle keeps accumulating through it. `commitContainerPose(restingAt:movedTo:)` measures the box's
delta on the authored pose, so a Move made mid-spin keys where the *box* went, and the render shows
the ink spinning about wherever the box now is — which is what the artist watched happen, since the
preview is the render path. Nothing in `KeyframeControl.write`, `seedingContainer` or the graph band's
`PoseEdit` gains an arm.

**Accepted and to be said on screen**: placing a keyframe does not pause the wheel or the shake. To
hold a rotation, key the speed to 0; to hold a shake, key its amplitudes.

## 7. What each mode must not break

| ruling | what it demands here | which mode is the risk |
|---|---|---|
| §2.28 union, computed never stored | mode scalars ride `channelTracks` through `KeyframeState`; no new store | none — by §3.3's choice |
| §2.4 / §3.1 time bases | layer tracks stay absolute; repeat remaps the **read**, never the storage | repeat |
| §3.4.1 compensation, `C` and `I` cancel | `I` is per entry under parallax and per frame under rotate/shake, but it is one value per cel, so it still cancels; under repeat it must be read at the **source** frame | repeat |
| RENDER §2.16 / §3.3, same frame same bytes | the resolved pose is the one value in the version; shake's noise is pure; repeat is the identity key. **And the baker has to be told** — `FrameBaker.StructuralStamp` reads the tree, which carries no pose by design, so it now stamps the container poses (base, track, mode, **the shake's seed and period, the repeat's period**) and the scalars (rotate speed, parallax share, **the three shake amplitudes**); before stage 3 a moved box after the first sweep was a permanent miss on the display path, found by the rotate cold-start test drawing the ink unturned. `FrameBakerLogicTests` drops each field and expects red | shake |
| §4.5 three keys | nothing new to carry — but a test over a **raster** fixture must go red if a mode's function is dropped from the resolved map | rotate, shake |
| §2.3 re-pose, never resample | the four pose modes ride the derivation; duplicate offset resamples *pixels* because it is a grade on the accumulator, which is what a grade is | — |
| §11.7 six rows | the band draws the authored pose; the function is not a curve | rotate, shake |
| `movesItsContents` frame-invariant | must read the mode and the scalars' *tracks*, not one frame | rotate, shake |
| (62) crop, reversed for a transform layer's own tracks (2026-09-11, txcrop) | its `transform.track`, mode scalars and `keyframeMarks` crop to the union of its own blocks; every *other* layer-level track (opacity, `effectTracks`) stays uncropped, ungated | all, under §4 |
| hidden layer contributes nothing | the accumulator reads `isVisible`; a hidden repeat does not remap | all (BUGS.md) |

## 8. Build order

Each stage merges alone and leaves the app working. Every visible stage carries a cold-start
reachability XCUITest from a fresh document and an assertion on what is drawn, per CLAUDE.md.

| # | stage | tested by |
|---|---|---|
| 0 ✅ | **The kind** — `LayerKind.transform`, the decode migration, the `+` entry, the options panel with a mode picker showing only Move. Behaviour-neutral for every posed document. **Shipped 2026-09-11.** The hidden-layer fix (BUGS.md) is a separate change and is not part of this row. | `TransformLayerLogicTests` / `TransformLayerEntryLogicTests` with their fixtures creating the kind (three tests about the old mode picker became three about the kind); a migration round trip through a real package rewritten to the old spelling, drawn on both backends; `LayerPanelControlsUITests` drives `+` → panel → Move row → box; `LayerKindLogicTests` walks `allCases` through every switch |
| 1 ✅ | **The span** (§4, rulings 1 and 17) — pixel-less leaves act inside their block, the grade included; Move outside the block refused with `CanvasNotice.moveOutsideTransformBlock`; BUGS.md's value-layer entry closed. **Shipped 2026-09-11.** | a pose at a frame past the block resolves to nil in `layerPoses`; a grade past its bar is the ungraded floor, byte for byte on both backends; shorten the bar → the composite past it equals the un-posed one and the keys beyond are still listed and still drawn; lengthen → byte-identical to before; the refusal and the notice, from the toolbar and the channel row; `TransformLayerSpanUITests` drives all of it from a fresh document |
| 2 ✅ | **Parallax** — `parallaxShare` row, item counting, the per-entry blend, the panel's item list. **Shipped 2026-09-11.** | `TransformLayerModesLogicTests`: four drawings → leaf maps at 100/75/50/25 of the box's translation; a folder is one item; a tint between them is none; −50 moves opposite and 150 overshoots; half a turn is 45° and half a 4× scale is 2.5× (the factored blend); a keyed share; reorder keeps a typed share with its layer and re-defaults the rest; the panel's list is the render's items; the first edit on a keyed item seeds keyframe A with the positional default; the box drag moves each item live; a folder in Parallax shares over its children. `TransformLayerModesUITests` drives `+` → Transform Layer → Mode → Parallax → the list → Move → drag from a fresh document and measures the four bands off the canvas |
| 3 ✅ | **Rotate** — `rotateSpeed` row, integration from the block start, box-centre pivot pre-composed, `movesItsContents`. **Shipped 2026-09-11.** | `TransformLayerModesLogicTests`: 15°/frame → 90° at `s + 6` about the box centre with `s = 4`, nothing at `s`, nothing before the block; keyed 15→0 integrates (no backward snap, holds where it stopped); a mark holds the box, not the angle, and keeps the mode; `hasContainerPoseInForce` reads the mode and the speed's track; under a keystoned box the orbit of one point is the conic (four extremes, and not a circle about the mapped centre); a raster fixture on both backends is drawn turned and reddens when the function is dropped from the map, same frame same bytes, the version differing across frames; a folder in Rotate spins its children from frame 0. `TransformLayerModesUITests` types 15 into the speed field, reads the frames-per-turn line, scrubs six frames in and measures the quarter turn off the canvas |
| 4 ✅ | **Shake** — `shakeX`/`shakeY`/`shakeRotation` rows, `LayerPose.shakePeriod` and `shakeSeed`, value noise smoothstepped between beats, Re-roll. **Shipped 2026-09-11.** | `TransformLayerModesLogicTests`: the noise pinned at one raw value against a Python splitmix64 and a second Swift spelling; a 10-point amplitude at rest moves a point `10·n(seed, 0, k)` at frame *k* and the same frame twice is the same map; two seeds differ; a 2× box shakes 20 for 10 and a Move key rides under the jolt (the order of composition); the period eases between beats with smoothstep; the beats count from the block's start so a slid bar shakes the same way; the mode switch mints a seed, Re-roll is one undo step named for it, the period is clamped and undoable; `movesItsContents` reads the three amplitudes' tracks; a raster fixture on both backends is drawn `10·n(k)` to the side, same frame same bytes, two versions for two frames; the seed, period and amplitudes round-trip through both manifests and a real package. `FrameBakerLogicTests`: the seed, the period and an amplitude are structural edits. `TransformLayerModesUITests` draws a band, `+` → Transform Layer → Mode → Shake, types 300, and reads the band moved on the bar's first frames, the same on the way back, elsewhere after Re-roll, and back after one undo |
| 5 ✅ | **Repeat** — the (pose, frame) carry in `renderNodes` / `leafSnapshots` / `contentVersion`, `LayerPose.repeatPeriod` typed and pre-filled, the edit redirect, the ghost blocks. **Shipped 2026-09-11.** | `TransformLayerModesLogicTests`: `leafFrames` is `s + ((f − s) mod p)` and the composite at a repeated frame is the source frame's bytes on both backends, blank past the bar; `FrameBakeKey(s + p + k) == FrameBakeKey(s + k)` (the cache, for free); an opacity curve, a Rotate layer and a folder beneath all repeat; a repeat under a repeat composes (periods 5 over 2, chosen to differ from the inner alone) and a hidden one loops nothing; `movesItsContents` reads the period; the pre-fill is where the drawings beneath end (a held background makes it 12, a tint counts for nothing, measured from the bar's start, the bar's length with nothing beneath), typed as one undo step, refused on a folder; drawing at a repeated frame is handed the source cel, spawns at the source frame when it is empty, and ignores a held block under the playhead; the ghost segments run by source drawing and agree with the walk frame for frame on a nested fixture; the period survives a manifest and a package. `FrameBakerLogicTests`: the period is a structural edit. `TransformLayerModesUITests` cuts the born block twice through the cel menu, draws on frames 1–3, `+` → Transform Layer → Mode → Repeat, reads the period pre-filled to 12, types 3, reads the ghost band's value off the row, and measures frame 5 drawing frame 2's band, frame 4 frame 1's, and a band drawn on frame 5 appearing on frame 2 and not on frame 3 |
| 6 | **Duplicate offset** — the case, two passes on both backends, the eleven CPU blend formulas, the box writer, strip reach. | parity byte-for-byte per mode; rim and intersection over a known shape; `testNoEffectChangesAlpha` holds; the box commit writes the five scalars; a strip seam test at a large offset |

Stage 6 depends on nothing here and is what remains. The mode picker in `LayerPanel.transformModeRow`
lists every case of `TransformLayerMode` (`Models/TransformLayerMode.swift`) on a layer and
`TransformLayerMode.folderCases` on a folder, which is all of them but Repeat — **not `TransformMode`,
which was taken**: that name is the Move bar's Uniform / Freeform / Distort picker, and stage 2 found
the collision on the day it introduced the enum. The mode lives on `LayerPose.mode`, so a folder's
pose carries it for free (§3.3); the scalars a mode reads are `TargetChannel` rows on the two homes,
because a key path through an optional payload is not writable; what is not keyable (§3.3's closing
paragraph) sits on `LayerPose` beside the mode.

**Two things stages 4 and 5 found that the design did not say.** A leaf inside a *folder* beneath a
Repeat is walked at the source frame, and the walk's per-leaf `frames` map has to record that leaf
against the **document** frame rather than the folder's own walk frame — recorded against the latter,
the leaf inside the folder read as its own source and `leafSnapshots` looked its cel up at the
playhead, so the folder half of ruling 12 was blank until `renderNodes` grew a `documentFrame`
parameter. And a container's rank is the topmost `layers` index it holds, so a fixture that restacks
a folder to the bottom and *then* adds a layer into it has lifted the folder back above the looper —
the nested-repeat tests state their order as a premise for that reason.
