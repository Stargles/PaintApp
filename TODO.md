# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

**At the start of a pass, empty "Done this pass".** It is a record of the pass you are in, not a
changelog — `git log` is the real history, and a list carried across passes stops meaning anything.
Prune it first, before adding the new asks.

Thoughts the owner has voiced but not yet asked for are recorded here too, **in their own words** —
the perspective-text requirement was nearly re-derived from scratch because it lived in only one
document. A quote is cheaper to keep than a decision is to rebuild.

**The measurement baseline lives in [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works
at 2048×1024, and every number this project collected before 2026-08-17 was taken at 4096², eight
times the pixels. Benchmark at the owner's size first and treat 4K as the stress case.

## In flight

Nothing yet — this pass has just opened. The four asks below arrived 2026-08-27 with the device
report and are unstarted.

## The device answered every open question, 2026-08-27

The five things blocked on someone holding the iPad are all answered, and the list is gone rather than
shortened. What each answer was:

- **The ink loss is REAL and was seen.** *"After I shrink the entire canvas and put in a line, the line
  does not bake properly, and only the part of the line in a box around the original object gets baked.
  This box is likely the canvas borders after it got shrunk, and I suspect that there is some kind of
  compositor or display think hiding the strokes outside. The only one quarter of it getting shown does
  not nessesarely seem the case."* So the defect is confirmed and **our predicted shape was wrong in a
  way worth keeping**: we said the top-left quadrant, the owner saw a box around the original object.
  BUGS.md's entry is updated from INFERRED to observed. **The whole case for
  [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) and item (12) now rests on evidence rather than on reading.**
  **And the owner ruled against fixing it directly** — see (15).
- **The freeze is not reproducible and is treated as solved.** *"I cant seem to replicate the freezing
  bug, so I'll let you know if I ever encounter it again. Chances are the new text UI could have fixed
  it, so treat it like its solved. I will bring it up if i ever see it."* The two reports were argued to
  be one bug (`Tool.paintsOnCanvas` false for exactly `.fill`, `.eyedropper`, `.text`), so BUGS.md's
  long-open Fill entry closes with it. The two regression nets stay.
- **(4) The Scribble fix is confirmed.** *"works pretty much properly now."* A pencil tap on a text box
  raises the keyboard. `ab7f736` is closed, and it was never verifiable on this Mac.
- **(5) Freeform is confirmed.** *"freeform works."* The one gap it left is now an ask — see (17).
- **The blue marching ants are confirmed.** *"lasso works."*

Only the three behaviour questions we raised ourselves are still unlooked-at, and they are judgements
rather than defects: the Cut eraser across a line thicker than the eraser, the crossing line that can
flicker during a cut drag (both [BUGS.md](BUGS.md)), and a fill chunk dropped on blank paper staying a
fill ([LASSO_MOVE.md](LASSO_MOVE.md) §5).

## Asked 2026-08-27, off the device report

### (15) Move with no selection becomes "the whole canvas was lassoed", and the legacy path is deleted

- [ ] The owner, 2026-08-27, ruling on the ink loss rather than asking for it to be repaired: *"I dont
      think you should try to fix this, as scaling the entire canvas should transform the objects
      coordinates in it, not the entire canvas coordinates as per the new proposed system. ... The move
      tool without the lasso tool would pretty much use the exact same code as if the entire canvas was
      lassoed around, then move was clicked on. Should be pretty easy to implement, and of course clean
      up and remove the legacy code cleanly."*
      **This is item (12) arriving as a behaviour change instead of a storage change**, and it is the
      cheaper door into it: the lasso-move path already bakes into canvas coordinates on commit
      (`FloatingPiece`, LASSO_MOVE.md §3), so pointing Move-with-no-selection at it *is* the bake, with
      no new machinery. It closes the ink loss by removing the path that loses the ink, and it deletes
      `_transform`'s reason to exist — the indirection LAYER_TRANSFORM.md counted **eleven of sixteen
      entry points** inverting away again.
      **It also carries a second reported defect**, see (16) below, which may or may not be subsumed.
      **The unknowns are settled and stage 1 is in build, 2026-08-27.**
      *"The entire canvas was lassoed"* is **every element id, with no path test and no split** — not a
      canvas rect. A rect through `membershipRuns` (`VectorLayer.swift:1450-1470`) would cut every
      stroke crossing the canvas edge into two permanent strokes with fresh ids and abandon content
      wholly outside it, and off-canvas content is real here; `localContentBounds()` is worse still,
      being an alpha scan of the *already-clipped* render, so it would exclude the very ink the fix
      exists for. Raster layers and the saved-document migration are **stages 2-3 and are not in stage
      1**, which deletes nothing.
      **Three artist-visible costs were put to the owner and accepted**, 2026-08-27: *"Accept all three,
      ship stage 1, then the double precision move comes later and integrates in with it."*
      (a) **The Move box inflates** — today's pivot and size come from `localContentBounds()`, invariant
      under `_transform`; the float's come from a geometric AABB of moved ink, so rotate +45° then −45°
      returns a bigger box, monotonically over repeated gestures. **Item (14) is the cure and the owner
      named it as the follow-up.** (b) **Undo goes from one step per Move session to one per gesture**,
      which is LASSO_MOVE §5.5's existing ruling. (c) **The Move bar appears where there was none**, with
      Freeform and Mirror greyed on any cel holding text or an image until (17) lands.
      **One hazard is not a cost but a defect the stage must fix**: `rasterizeLayer`
      (`CanvasManager.swift:433-455`) clears `isVectorTransforming` but never commits a vector float, and
      a whole-cel float suppresses *every* element id — so Rasterize or Merge Down with the Move box up
      would flatten the cel **to blank in the saved document**. LASSO_MOVE §6 names a stranded
      suppression as this design's one silent failure mode.

### (16) Move with no selection blocks the brush button — DONE `a506d66`

- [ ] The owner, 2026-08-27: *"A separate bug is discovered where if I click on move without lassoing
      first (so a canvas move), I cant click on a brush."* Reported alongside (15) and possibly cured by
      it — the owner's own read is *"since the canvas layer resize thing is going to be discarded and
      replaced, I dont think you need it"*. **Do not assume that**: confirm from the source whether the
      block lives in the whole-layer Move path or in the tool-switch arbitration, and if the latter,
      fix it on its own. It is a live defect on the shipped build either way.

### (17) Text is transformable — Freeform and Mirror must accept it

- [ ] The owner, 2026-08-27, an explicit ruling: *"when trying to select and move text, freeform is
      greyed out and i also cant mirror it. I rule text should be able to be transformed. Probably just
      isnt added yet."* Correct — Move stage 3a shipped with a piece carrying an image or a text box
      having the picker disabled and the reason shown in the bar, exactly as Mirror already refused
      (LASSO_MOVE.md §0). **The ruling is about text.** Placed images sit behind the same gate
      (stage 3c) and the owner has not ruled on them; report whether one change ungates both before
      ungating both.
      **Both sub-behaviours are SETTLED, 2026-08-27 — recorded as LASSO_MOVE.md §5 ruling 18, do not
      re-open them.** The owner chose *"Mirror reflects, stretch distorts the letters"*: a mirrored text
      box **reflects the rendered glyphs**, so the text reads backwards as in a real mirror and
      mirror-then-mirror-back is exactly the original — it does *not* re-lay-out the string
      right-to-left; and a non-uniform scale **distorts the letterforms**, same words on the same lines
      with wider or taller glyphs — it does *not* re-flow the line breaks. Both are what a transform
      means everywhere else on the canvas, and both are what the code does naturally with no renderer
      change. Ruling 17's area-root rule is for a stroke's one scalar width and has no text equivalent;
      a point size is not an ink weight.
      **Two blockers found by review, both real, both briefed into the build**: `warpedFrame` guards on
      `start.mode == .projective` (TextObject.swift:938), so a stretched *affine* frame falls through to
      `start` and every sizing grip on a stretched box would be **silently dead**; and the obvious
      stretch arm breaks ruling 17's *"Freeform contains Uniform"* discontinuously at `aspect == 1`,
      because the dispatch is an exact comparison (`CanvasManager+LassoMove.swift:262`) and the
      similarity arm scales `size` and `pointSize` where a corners-only stretch arm would not. The fix
      is to decompose the map and give the uniform part to `size`/`pointSize` exactly as the similarity
      arm does, leaving only the residual aspect in `corners`.

### (18) The bottom bars should be as tall as their contents — ATTEMPTED AND REVERTED, still open

- [ ] The owner, 2026-08-27, on (11) as shipped: *"bottom bars are alright. Try to make that menu shorter
      vertically because alot of them contain only 1 or 2 sliders which covers like half of it. You
      already added the vertical scrolling thing to the bottom bar for things with more, so it should be
      good."* So: content-driven height with a cap, and the existing scroll takes over above the cap.
      The height is the whole point of (11) — 45% → 85% of the paper visible, MEASURED — so this is
      finishing that change rather than adjusting it.
      **The obvious implementation was built, measured and reverted (`785f3f7`), and the dead end is the
      finding.** A `PreferenceKey` plus `.background(GeometryReader { … })` on the outer rows `VStack` —
      the standard way to read a resolved size without an unbounded scroll-axis proposal — measures
      **exactly 0** for every effect, collapsing the card to its header with the rows clipped away.
      `CurveEditor`'s own doc in that same file already names this failure for a *more direct* case;
      what is new is that **`.background` does not shield you from it**, which was the assumption both
      the brief and the implementer reasoned from.
      **The XCUITest passed against the broken build**, which is the part to remember: `XCUIElement.frame`
      reported plausible differing positions for the sliders while nothing was painted, because an
      accessibility frame does not reflect visual clipping. Only an on-screen debug overlay read back
      through a screenshot caught it — the banner-vs-count trap in a third costume, and the reason this
      item wants a *screenshot* as its acceptance test rather than a frame comparison.
      **The candidate next approach**, recorded on `maxRowsHeight`: measure an `.accessibilityHidden(true)`
      twin of the rows laid out *outside* any `ScrollView`, so the unbounded-proposal path is never
      entered at all. The new test stays, honestly re-scoped to the precondition it does verify.

### (19) An empty text object is deleted when it bakes — ALREADY SHIPPED, closed 2026-08-27

- [x] The owner, 2026-08-27: *"if there is a text object with nothing in it, delete it when it bakes."*
      **It already does, and has since `400b4de` on 2026-08-20** — 123 commits before the build on their
      iPad, so the behaviour they were asking for was already under their finger. The owner confirmed
      they were asking without having tested: *"I was asking for it, hadn't tested."*
      Kept as a closed entry rather than deleted, because the *checking* is the reusable part: the raster
      arm guards `!recipe.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`
      (`CanvasManager+Text.swift:339`) and the vector arm computes `isBlank` and passes a nil element
      (`:378-380`), which `VectorLayer.commitTextEdit` turns into `removeTextLocked` (`:753-766`).
      `TextBakeCharacterizationTests` pins both. **So whitespace-only counts as empty too** — a box
      holding only spaces or a newline is deleted, which the owner has been told and has not objected to.

### Chromatic aberration, and possibly every effect, is masked to the layer's own ink

The owner, 2026-08-27: *"Chromatic abberation seems to for some reason be masked to the objects on the
layers only. If it is transparent to the canvas, it doesnt affect it. Other effects and blend modes
might have this error too, so it's worth a check."* Filed in [BUGS.md](BUGS.md) — it is a defect we now
own, not an ask — but recorded here because **the owner asked for the sweep**, and a per-effect and
per-blend-mode answer is the deliverable, not a fix to the one effect they happened to notice.

**RULED 2026-08-27, and it is the more expensive of the two options offered**: *"Paper is part of the
picture, but rescue those three."* So the canvas paper becomes part of what an adjustment layer grades
and what a blend mode blends against — which fixes the reported effect, seven others and twenty blend
modes at once — **and** Outline, Bloom and Sobel keep a way to see the ink alone, rather than being
allowed to regress. That second half is a **new concept in this design** — an effect scoped to the
pixels below it rather than to the accumulated backdrop — and it wants its own short specification
before it is built, not an inline flag.

## Canvas geometry, and how a coordinate is stored

**Five asks, one programme.** They constrain each other and they share one number, so read the shared
part once and then the five in order.

**16,384 pt is the same number in three places** — the span of a stored coordinate, the maximum canvas,
and the canvas-plus-padding budget — and it should be defined in exactly one place in the code. The
storage rule that falls out of it, settled by the owner on 2026-08-27: **a sample is 16 bits an axis,
the origin sits at the centre of the canvas, and the grid is quarter-pixel.** 2^16 quarter-pixels is
16,384 pt of span; centred, that is **±8,192 pt**, which is exactly the maximum canvas with the sign
included. Everything below either sizes that field, decides what lives in it, or decides when the app is
allowed to leave it.

Dependency, in one line: **(8) needs nothing**; **(12)** is what narrows (8)'s field from 24 bits to 16;
**(14)** is the answer to the strongest objection against (12); **(13)** sets the 16,384 the field is
sized to; and **(9)** is independent of all of them *because* the width is fixed.

### (8) Fixed-point sample coordinates

- [ ] The owner, 2026-08-26: *"Storing it as a double takes up way too much memory per point. The key is
      the canvas size: if a canvas is x by y pixels, our variable size only needs to be the canvas size ...
      add two more bits so it can be placed in 4 places between each pixel ... 12 bits per coordinate is
      alot better than 64."*
      The `+2` buys quarter-pixel placement because a stamp is *not* rounded to the nearest pixel when
      rasterized — the owner's own caveat, and correct: `BrushStamper` places dabs at sub-pixel positions.
      **The worked example is off by one and the design is unaffected**: 2048 is 2¹¹, not 2¹⁰, so a
      2048×1024 canvas needs x: 13 bits, y: 12, not 12 and 11. 25 bits a point against 128 for two
      `Double`s is still the 5× the ask is really claiming.
      **`VectorSample` is three `CGFloat`, not two** — the third is pressure/force, a 0…1 quantity where
      8–10 bits is generous.

      **SETTLED, 2026-08-27 — 16 bits an axis, signed, origin at the canvas centre, quarter-pixel; 8
      bits of pressure. 40 bits = 5 bytes a sample against today's 24, a 4.8× win**, and far more on disk
      against the 89 bytes/sample the JSON currently spends.
      The centring is the owner's, and it is what buys the sign bit back for free: *"have something like
      the first bit represent a plus or minus, then center the origin to the exact middle of the canvas.
      14 bits which cover 16384 (maximum canvas size) which is across -8k to 8k, and the last two bits for
      quarter pixel res."*
      **Centring is an encoding concern, not a coordinate-system change.** In memory the samples stay in
      whatever space they are in today; encode subtracts the centre and quantises, decode dequantises and
      adds it back. Nothing above the storage layer needs to know.

      **The rulings attached to it**, none of which should be re-opened:

      - **Reversible transforms decode to `Double` and re-encode at the bake.** The owner:
        *"The exception to this data type would be during reversable transformations, in which it would be
        converted temporarely to a double as to not lose accuracy, then converted back when it bakes."*
        This answers the objection that quantising on every store fights the absolute-mapping discipline
        (every transform maps samples absolutely *from the lift*, so error cannot accumulate over many
        small drags). Decode once, work in `Double`, re-encode at the bake. See (14), which is the same
        mechanism asked for again at the tool level.
      - **Residual drift is closed, 2026-08-26 — do not re-open it.** The worry was that a bake still
        rounds, so repeated lift-bake-lift-bake cycles would random-walk at up to ⅛ px a bake. The owner:
        *"I dont see any reason why someone would transform, bake, and repeat for that many cycles. The
        only time that many transformations would happen is before something is baked, so it works out."*
        That is structural rather than a judgement call: the many-transform case lives inside a single
        unbaked session, where the samples are already `Double`, so the rounding has no path by which to
        accumulate. One bake, one rounding.
      - **Centre of *what* — the centre of the *current* canvas.** This file recommended a fixed 16,384
        address space, to keep the encoding resize-invariant; the owner overruled it: *"If such a feature
        gets implemented in the future, then yes I'd say the origin moves to assume the center of the new
        canvas. However, thats just a one time operation so it doesnt need to be particularly performance
        optimized, and asymmetric canvas crop isnt a current feature."* So an asymmetric crop re-encodes
        every sample, and that is acceptable because it is a one-off the artist explicitly asks for — the
        thing to avoid was a re-encode on *ordinary* operations. It is moot today: asymmetric crop does
        not exist.
      - **Past the field, ink clamps — it does not wrap.** *"If you draw outside the 16k, it should not
        wrap but rather clamp."* Unclamped, a 16-bit field wraps, so ink drawn past the edge does not stop
        there, it **teleports to the opposite side of the canvas**. Clamping makes the failure boring and
        local: a stroke that wanders far outside flattens against the boundary, where it is invisible
        anyway. Implement the saturation at the **encode boundary only**, so nothing above the storage
        layer changes behaviour and the in-memory samples stay exactly as they are.
      - **Zoom-out is the reason the clamp is needed, and the owner narrowed it correctly.** Their answer:
        *"zooming in the canvas shouldn't be an issue. zooming is basically just transforming canvas
        coordinates into screen coordinates ... The canvas size should be the resolution, not the screen
        you are drawing on."* Right, and it is about zoom **in**, which costs *precision* — and costs none
        here, because the quarter-pixel grid is in canvas space, so magnifying the view consumes no bits.
        The finding was about zoom **out**, which costs *range*, and quantified their judgement holds: on a
        2048-wide canvas a full-screen drag exceeds ±8,192 pt only below roughly **12%** zoom — the canvas
        an eighth of the screen — which nobody draws a deliberate full-screen stroke at. An edge case.
        **Nothing in the tree clamps today.** `CanvasView.swift:3074-3075` floors canvas zoom at 0.01 of
        fit and has **no ceiling** — its own comment says so: *"No upper bound on zoom; the tiny floor only
        guards against a pinch's fingers crossing."* A screen-wide drag at minimum zoom spans ~100× the
        canvas extent — **1,638,400 pt** at the 16,384 ceiling — against the ±8,192 pt this field buys,
        **200× short**. Filed in [BUGS.md](BUGS.md). **It is independent of (12)**: baking geometry into
        canvas space removes the layer-local blow-up and does nothing about zoom; the zoom bound is in fact
        *worse* than the one it replaces (1,638,400 against 409,600). So the clamp is needed whether or not
        (12) is ever built.
      - **The one honest caveat, and its shape is already accepted**: at a canvas of *exactly* 16k there is
        no margin left for ink outside the canvas, because the field *is* the canvas. Not a practical limit
        — at 2048×1024 the artwork occupies ±1024 × ±512 of a ±8,192 field, 8× margin in x and 16× in y for
        strokes that wander off the edge — and the owner has said the 16k canvas *"will likely never be
        used for animation."*

      **How the width got here, kept so it is not re-derived.** The owner delegated the question — *"you
      decide if you want the dynamic bit allocation ... or if we should just keep it at 20 bits with a max
      canvas size"* — having correctly spotted that a constant width sits awkwardly with a canvas that is
      not constant. **Fixed won, and dynamic-sized-to-the-canvas is not merely more complex, it is
      unsound**: CANVAS_RESIZE.md found three independent reasons a coordinate leaves `[0, extent)` as a
      matter of course — geometry stored **layer-local** (a layer at 0.1× stores coordinates 10× the
      extent, by construction), touches delivered after a drag leaves the canvas, and every shrink parking
      content outside the bounds. **The 20-bit proposal overflows on measured numbers**:
      `ObjectTransformFrame.minimumScale` is **0.02** (`ObjectTransformFrame.swift:260` — "below this the
      layer is a dot the artist cannot get back") and the canvas maximum is **8192**
      (`CanvasSizePickerView.swift:16`), so the worst-case stored coordinate is `8192 / 0.02 = 409,600 pt`
      while 20 signed bits at quarter-pixel reach only **±131,072 pt** — 3.1× short. (Fine on the owner's
      own 2048-wide canvas at 102,400 pt, which is exactly the kind of thing that ships and then breaks on
      someone else's document.) 22 bits was the tight fit at ±524,288 pt; **24 signed bits** was chosen —
      byte-aligned at 3 bytes an axis, ±2,097,152 pt, 5.1× headroom, 7 bytes a sample for a 3.4× win. That
      stands as the answer **if (12) is not adopted**. Adopting (12) removes the layer-local blow-up, and
      then the bound is the *addressable* extent instead, which is where the 16 bits above comes from.
      To go back to 20 bits, `minimumScale` would have to rise, which is a behaviour change and not worth
      it.
      **The payoff for fixing the width, and the reason the question was asked at all**: a resize
      re-encodes nothing, so **(8) and (9) are independent and can ship in either order.**

      *Note: [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) §6 and [CANVAS_RESIZE.md](CANVAS_RESIZE.md) §6 were
      written before this ruling and reached 24 and 20 respectively; `85fcbbf` corrected both in place
      rather than deleting the analysis, since each diagnosis held up where its number did not. This item
      is still the current answer, and those two sections now say so and explain how they got there.*

### (12) A layer should not have a *resolution* — bake geometry into canvas coordinates

- [ ] The owner, 2026-08-27, questioning the premise rather than the arithmetic: *"I'm not sure why layers
      themselves should ever be able to be shrunk. Only the objects in them should be. Every object in the
      vector layer should be given coordinates according to the canvas, and if the entire layer is
      'shrunk', then those coordinates of the objects should shrink, not the entire layer itself being
      transformed."*
      **Confirmed by the owner the same day, with the nuance that matters**: *"Transformations are allowed
      to exist yes. It's just that the entire layer being resized should just bake the stuff in that layer
      to their new canvas based coordinates, instead of resizing the entire layer to be at a smaller
      resolution."* So this is **not** "no transforms" — it is "no layer *resolution*". A whole-layer
      resize becomes a bake into canvas coordinates, and per-object transforms (a placed image's rectangle,
      a text frame) are untouched.
      **Where it came from**: their 15-bit arithmetic for (8) is correct *for canvas coordinates* and fails
      only because vector geometry is stored **layer-local** — `addStroke(canvasSpaceStroke:)`
      (`VectorLayer.swift:575`) maps every sample through `_transform.inverted()` and divides the width by
      the layer scale, so a stroke drawn across the canvas on a 2%-scaled layer stores coordinates 50× the
      extent.
      **Judge it on its merits, not on the two bytes.** Restructuring a core type to save bytes a sample
      would be a bad trade alone. The real argument is that the layer transform is an indirection most
      entry points invert away again — [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) counted **eleven of sixteen
      entry points** doing exactly that — and that it carries three defects that are properties of the
      indirection itself, one of which **silently discards ink the artist just drew** (BUGS.md, and the
      device check for it is in the waiting-on-the-owner list above). Its verdict is **adopt, with
      changes**.
      **The load-bearing unknown is answered: `_transform` is per *cel*, not per layer across the
      animation** (LAYER_TRANSFORM.md §4, three pieces of evidence). So baking rewrites **one drawing, not
      the animation**, and the cost estimate stays small.
      **Two things true before any analysis**: a placed image *is* a transformed rectangle
      (`VectorImageElement` carries its own `LayerTransform`) and text carries a `TextFrame`, so
      "everything is canvas coordinates" cannot be total — per-*object* transforms survive and only the
      cel's goes. And a whole-layer scale becomes O(samples) rather than O(1), which is fine on commit and
      not at 60 Hz — though the lasso float already solves exactly that shape (a latched bitmap moved by
      Core Animation, baked into geometry on release).
      **The future shape is on record and changes how this should be built**: *"when I add keyframes, I
      want a special type of layer called a transformation layer in which the stuff under it can be moved.
      This will just apply a transformation over the layers below it, so still no overflow problems, and
      whatever is being transformed of course is scoped with a maximum width of 16k."* An adjustment-layer
      shape — the transform lives on a layer that affects the layers **below** it, at render time, and is
      never baked into their coordinates. **Design (12) so that stays easy**: what is being removed is a
      transform baked into *storage semantics*, not the idea of a render-time transform, and the render
      tree already composites effect layers over the layers beneath them
      (`RenderTree.needsCompositorOnCanvas`, `node.effect != nil`) — that is the seam a transformation
      layer would use.
      **(8) is not blocked on this.** 24 bits works today with no other change; adopting (12) is what lets
      the field narrow to 16, which is a refinement rather than a prerequisite.

### (14) A reversible Move: keep the transform in doubles until you choose to bake it

- [ ] The owner, 2026-08-27: *"In the move tool have an option to store whatever the transformation is as
      doubles so it is reversible, and add an option in actions to bake everything down back to 16bits."*
      **This is the answer to the strongest objection against (12)**, and it arrived unprompted. The
      reviewer's case for keeping a layer transform was that it is the only operation in the app that is
      *exactly, infinitely and freely reversible* — scale a cel to 2% and back and the geometry is
      bit-identical because nothing touched it. Baking gives that up: MEASURED, 100 shrink-to-2%-and-regrow
      cycles drift only **6.0e-11 pt** and `stroke.size` returns bit-exact, so the *geometry* half of the
      objection is dead — but two artist-visible residues survive, and this ask covers both:
      - **`BrushStamper.stampSpacing`'s 1 pt absolute floor** (`BrushStamper.swift:67`): a stroke shrunk
        below the floor and regrown comes back with a different dab count. Not reversible in *pixels*,
        whatever the geometry does.
      - **The Move box itself inflates.** Its pivot and size come from `localContentBounds()`, an alpha scan
        of rendered ink, which is invariant under a transform today. After a bake it is recomputed from
        moved ink, and the axis-aligned box of a rotated drawing is larger — so rotate 45° then −45°
        returns a *bigger* box on a moved pivot, and repeated gestures inflate it monotonically.
      **Deferred precision fixes both**: hold the pose in `Double` while the artist is still working on it,
      bake on an explicit Actions command. Same shape as the float's latch, and same shape as the owner's
      earlier ruling on (8) — *"converted temporarely to a double as to not lose accuracy, then converted
      back when it bakes."* Two rulings, one mechanism.

### (13) Canvas padding shares one 16k budget with the canvas, and the base maximum rises

- [ ] The owner, 2026-08-27: *"the canvas plus the padding should have the maximum size of 16k, so the
      padding should hit a maximum limit when the canvas is set close to that 16k. The 16k canvas (or near
      it) will likely never be used for animation so it doesnt need canvas padding. Right now canvas padding
      just has a set maximum of something like 500px, I kind of want to make that maximum a bit higher like
      1000, unless of course it is bounded by the 16k canvas+padding limit."*
      Their fuller rationale, given in conversation 2026-08-27 and recorded here because it existed
      nowhere in the repo: *"a max size canvas would have no off canvas stroke room, but that's a very
      minor concern, since again, the 16k canvas would only ever be used for big concept art boards."*
      **Their memory was nearly exact**: `CanvasManager.canvasPaddingRange` is `0...512`
      (`CanvasManager.swift:30`), a flat constant consulted by `setCanvasPadding`
      (`CanvasManager+Document.swift:21`) and by the Actions slider (`ActionsMenu.swift:231`).
      **The rule to implement**: padding's upper bound stops being a constant and becomes
      `min(1024, (16384 - canvasExtent) / k)` — so it is 1024 on ordinary canvases and shrinks to nothing
      as the canvas approaches 16k. The base rises 512 → **1024**.
      **One ambiguity to settle in implementation, not to guess**: is `canvasPadding` per-*side* or the
      total added extent? `setCanvasPadding`'s offset is described as "one symmetric number", which
      suggests per-side and therefore `k = 2` — confirm against the code before writing the bound, because
      getting it wrong makes the cap either half or double what the owner asked for.
      **It also raises the canvas maximum**: `CanvasSizePickerView.maxDimension` is **8192** today
      (`CanvasSizePickerView.swift:16`); the 16k rule implies 16,384 as the addressable ceiling — the same
      16,384 that sizes (8)'s coordinate field.

### (9) Resize the canvas from the Actions menu

- [ ] The owner: *"a resize canvas option in actions would be nice, to which users can resize the canvas
      however they want. They should be able to control whether it gets cropped/expanded, or if everything
      gets scaled."* Two controls: a **scale** option that scales the existing artwork, and a **toggle** for
      it to scale automatically with the new canvas size. **On an aspect change it letterboxes** — *"Not in
      the conventional sense of adding black, just scaling the stuff so it fits."* i.e. fit the content
      inside the new extent preserving its own aspect, leaving real empty canvas rather than painted bars.
      **[CANVAS_RESIZE.md](CANVAS_RESIZE.md) is the specification** and it is written: §0 records that two
      thirds of this already exists under other names, §5 carries thirteen settled behaviours, and **§6 is
      five questions the owner has to answer before it can be built** — chiefly what the width/height field
      means (artwork rect or padded buffer), what undo does over raster content, and whether "fill" joins
      "fit". Its §6 question 1, on the encoding, is answered by (8) above.
      Note this is adjacent to report (6): the owner's freeze sequence originally named *"try to resize the
      canvas"*, and although that turned out to mean two-finger canvas movement, whatever exists on this
      path is still worth understanding before extending it.

## Queued

- [ ] **(10) Switch colour storage and processing to Oklab, from the Actions menu.** The owner: *"I also
      want the option in actions to switch the color storage and processing to oklab or other future
      models. Oklab may give better compositing."* It is an ask for a **document-level switch with room for
      future models**, not a one-way conversion.
      It is RGB today: `CodableColor` is four `Double`s (`ProjectManifest.swift:124`). **Not a memory
      argument** — colour is per *stroke*, not per sample (32 bytes × 190 strokes = 6 KB on the cel measured
      on the owner's own device). The argument is quality: perceptually uniform blending, better gradients,
      and better colour interpolation between interpolation keyframes, where RGB goes muddy through the
      middle between two saturated hues. The owner's *"better compositing"* is the sharpest version of it
      and is the thing to verify: compositing happens in `Composite.metal`, so a real Oklab mode is a shader
      change, not only a storage change. Costs a conversion at stamp time and a decision about whether the
      picker works in Oklab.

## Carried — deliberate, and not an ask

- **The raster Move's undo half of [LASSO_MOVE.md](LASSO_MOVE.md) §5 rulings 5 and 10 is not built**
  (the vector half and selection-at-bake shipped). A raster nudge changes only `FloatingPiece.transform`, which is
  transient and not in the document, so per-nudge steps must be transient — and the bake step then sits on
  top of them and its undo restores the pre-move cel, killing every step beneath. Making it work means the
  bake step's undo *re-creating the float* at its last transform, which doubles what a raster Move retains
  in history and needs `finalizePendingGesturesForHistoryAction` to grow a raster-float arm it has never
  had. That is a second feature. See LASSO_MOVE.md §3 stage 4.

## Done this pass

- **(16) The brush button works after a whole-canvas Move** (`a506d66`). `selectedTool`'s own `didSet`
  closes the Move, reaching all six writers by construction; `Tool.isMomentary` keeps an eyedropper round
  trip from committing the box, and `.text` is deliberately not momentary.
- **(17) Text mirrors and stretches** (`045d509`), owner ruling 18. Mirror reflects the glyphs, a
  non-uniform scale distorts the letterforms and does not re-flow. **Three of the brief's claims were
  refuted by the code**, including the layout test this orchestrator specified: "same per-line widths
  after a stretch" is not a scale invariant, because the system face has size-dependent tracking — a
  √3 scale moved a line from 0.630 to 0.587 of its box with the breaks bit-identical. Replaced with
  line count plus line *ranges* and a re-flow discriminator. **One behaviour rides along unruled**: a
  Freeform-stretched box inherits the distort-mode exemption and can be dragged smaller than its own
  text.
- **(15) stage 1 — Move with no selection lifts the whole cel into the lasso float** (`cf5de83`), which
  closes the ink loss the owner reproduced. **Measured, not predicted**: on a 64×64 canvas shrunk 0.3×
  about ink at (32,32) the surviving band was [22.4, 41.6] — the owner's *"box around the original
  object"*, not our predicted quadrant. Fast tier 1748 → 1755, 0 failed. The teardown audit it carried
  found **four more doors** that would have flattened a whole cel to blank, and one it deliberately left
  (see BUGS.md). Stages 2-4 — deleting `_transform` and the persistence migration — are not in it.
