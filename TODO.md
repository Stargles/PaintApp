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

- **(11) Move the effect-settings and Add Text menus to a bottom bar, like Move's** — `tmp/bottombar`.
  The owner, 2026-08-27: *"the effect settings menu right now takes beside the layers menu. Those two
  things take up about 80% of the canvas, making it hard to see what you are editing ... When the user
  clicks on effect settings, the menu is on the bottom, like the same kind of menu that the lasso or
  move tool uses. Same for the add text menu, make it the same type of menu."*
  **This is a "can't see my work while I edit it" complaint, and that is the acceptance test** — the
  fix is good when the artist can see the thing the slider is changing. Two panels move, not one.
  **The pattern to copy already exists**: `Views/MoveTransformBottomBar.swift` is the bar the Move tool
  raises, and the lasso/Select flow uses the same shape. Read it before designing anything.
  **What moves**: the effect settings UI (`Views/EffectSection.swift`, and `Views/MaskTuningSection.swift`
  is its neighbour — decide whether both move or only the first) and `Views/TextSettingsPanel.swift`.
  Both are reached today through `activePanel`, which is `@State` on `DrawingView` (`DrawingView.swift:15`,
  the panel is mounted at `:399`) — and `activePanel` is one of the four inputs `CanvasTouchOwner`
  arbitrates a canvas touch over, so a change here has to leave it meaning the same thing there.
  **Two things that are genuinely harder than they look, to settle in design rather than discover late**:
  1. *A Move bar is a handful of buttons; an effect panel is a stack of sliders per effect.* A bottom bar
     may need to scroll, or grow, or page. Say what happens with many effects before building one.
  2. *`TextSettingsPanel` carries three system presentations* — the font-family `Menu` (`:115`), the face
     `Menu` (`:150`) and a stock `ColorPicker` (`:202`) — and [BUGS.md](BUGS.md)'s *"`TextSettingsPanel`
     grew three presentations the census says it doesn't have"* records that the presentation census does
     not know about them. Re-hosting the panel changes what those present *from*.
     `MENU_PRESENTATION_CENSUS.md` is the document that has to stay true.

## Waiting on the owner's device

Five things are blocked on someone holding the iPad, not on more reading. Each already has its
experiment designed; none of them needs another pass over the source.

- **(4) The pencil-tap keyboard fix is merged (`ab7f736`) and unconfirmed.** Owner, 2026-08-27:
  *"yes, clicking with finger yields correct behaviour. Clicking with pencil however brings up that
  write to text thing which is annoying."* That thing is **iPadOS Scribble**, and the app-side path was
  clean all along — `beginTextSession` has one non-test caller, no pencil/finger branch, and
  `becomeFirstResponder()` *was* called; iOS suppresses the software keyboard for pencil input on a text
  input view and offers handwriting instead. **Both earlier theories were wrong in instructive ways**:
  the `allowedTouchTypes`-gate guess was refuted by reading, and the counter-claim that the responder was
  refused *for everyone* is refuted by the finger working. The owner's own instinct — the pencil is
  treated as writing — was right, in a more specific sense than they stated. The fix adds a
  `UIScribbleInteraction` that refuses `shouldBeginAt` everywhere; **a pencil tap on a text box should now
  raise the keyboard.** That is the thing to check.
- **(6) The UI freeze — one capture answers it for two tools.** Owner, 2026-08-27, correcting the one
  fact everything rested on: *"by 'try to resize the canvas' I meant moving the canvas with two fingers
  if I recall correctly."*
  **So it was never Canvas Padding**, and it is not a main-thread hang either: a synchronous loop would
  end on its own and would freeze everything, not two-finger canvas movement specifically. The symptom is
  *this class's* symptom — *"the canvas stops panning / pinching / rotating"* — which is
  `CanvasTransformFreezeUITests`, whose own fixed bug (`8ae8613`, a popover dismissed by the touch that
  began a stroke) is confirmed **not** this one.
  **`.fill` and `.text` are the same state, so this report and [BUGS.md](BUGS.md)'s still-open
  *"two-finger pan/pinch/rotate is dead while the Fill tool is selected, on device"* are one bug seen from
  two tools.** `Tool.paintsOnCanvas` is false for exactly `.fill`, `.eyedropper` and `.text` — the
  eyedropper is momentary, so the two non-momentary members are the two the owner has now reported. That
  property is what `CanvasView.shouldRequireFailure` reads (through `activeHostIsInteractive`) before
  staking pan/pinch/rotate on the active layer's stroke recognizer, so **the arbitration layer exonerates
  itself in both**, exactly as BUGS.md already records for Fill. The question is therefore one question,
  not two: *is two-finger transform dead whenever `paintsOnCanvas` is false?*
  **Two nets shipped, and both pass on the simulator** — `testCanvasStillTransformsWithATextBoxOpen` and
  `testCanvasStillTransformsAfterLeavingTextForTheBrush`, beside the existing Fill one. That is the same
  non-answer three earlier Fill attempts gave, and is further evidence the split is device-only.
  `canvas.host`'s label now carries a `text:<none|box|editing>` field so a UI test can see a text session
  at all; without it both tests passed having placed no box.
  **`CanvasManager.selectBrush`'s missing `.text` is closed structurally and is NOT the reported defect** —
  reachability was settled by reading and it is unreachable: `BrushSettingsPanel` is the only caller, it
  needs `activePanel == .brush`, and `TopToolbar.selectBrushToolAndTogglePanel` only reaches that panel
  from `.pen`/`.pencil`, having run `commitAllInteractiveState()` on the way. It is now
  `Tool.followsBrushPresetSelection`, an exhaustive switch, so a seventh tool or a second door into the
  brush panel cannot open the state.
  **What the capture has to show**: with the canvas dead, put two fingers on it and read the recording's
  `recognizer` lines for `canvas.pan` / `canvas.pinch`. If they never leave `.possible`, something is
  holding them — and the `failureRequirement` lines say what `shouldRequireFailureOf` answered and who it
  named. If they reach `.began` and the canvas still does not move, the freeze is not in the recognizers at
  all and the search moves to `applyTransform`. Take it **with the Fill tool as well as from the text
  keyboard**: the same file answering the same way for both is what turns two reports into one bug.
- **Does drawing on a shrunk vector cel really throw the ink away?** [BUGS.md](BUGS.md)'s newest entry is
  INFERRED from source and **has never been seen on a device**, and the whole case for
  [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) — and therefore for item (12) below — rests on it. Repro:
  vector layer → Move with no selection → drag a corner to half size → tap away → draw across the canvas.
  Expected: only the top-left quadrant's worth of the stroke survives.
- **Freeform (Move stage 3a) has not been reported on.** Shipped 2026-08-27; a corner drag now scales the
  two axes independently and the ink keeps its round shape at the map's area root, which was the owner's
  own 2026-08-26 default. Worth an eye before stage 3b is designed on top of it.
  [LASSO_MOVE.md](LASSO_MOVE.md) §6 lists the other lasso-move behaviours that want a finger rather than a
  test — the centreline rule at real line weights, the round caps at a cut, a moved punch biting a new
  backdrop, and whether four presses for four nudges feels right.
- **Three behaviour questions left over from the 2026-08-22 pass.** That pass's five changes were confirmed
  — *"five changes are behaving correctly."* — but these three were raised by us, not reported, so nobody
  has looked at them on real artwork: the Cut eraser across a line thicker than the eraser (visibly does
  nothing, and always did) and a crossing line that can flicker during a cut drag, both in
  [BUGS.md](BUGS.md); and a fill chunk dropped on blank paper staying a fill, in
  [LASSO_MOVE.md](LASSO_MOVE.md) §5's "Still needs a ruling". None is a defect; each is a judgement.

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

      **SETTLED, 2026-08-27 — 16 bits an axis, unsigned, origin at the canvas centre, quarter-pixel; 8
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

      *Note: [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) §6 and [CANVAS_RESIZE.md](CANVAS_RESIZE.md) §6 both
      predate the 16-bit ruling and still name 24 and 20 respectively. This item is the current answer.*

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

- **(4) A pencil tap on a text box raises the keyboard instead of Scribble** (`ab7f736`). Device
  confirmation still owed — see the waiting-on-the-owner list.
- **(3) closed on both halves** — the small-box fix cured the distort case too, and the owner confirmed it:
  *"text seems to show up in distort now."* The refuted CALayer *software-path* hypothesis stays refuted,
  and the elaborate distort experiment was never needed because fixing the cheaper, better-understood half
  first resolved the expensive one. The box-size ruling it shipped with is recorded in ADD_TEXT.md §5.
- **(5) Move stage 3a — Freeform on a lassoed vector piece** (`bd3bddd`, `f44a2e9`). A corner drag scales
  the two axes independently about the centre; the ink keeps its round shape at the map's area root. No
  renderer change and nothing new persisted. Stages 3b (the yellow box-only knob) and 3c (placed images
  holding a stretched shape) are deliberately not in it; a piece carrying an image or a text box has the
  picker disabled with the reason in the bar, exactly as Mirror already refuses. Written up in
  LASSO_MOVE.md §0.
- **Canvas Padding's resize held every cel's intermediates at once — 3.5 GB for 32 cels** (`c6b1b35`).
  MEASURED, not supposed, and **not** the owner's freeze: the per-cel buffer walk is 83% of it and
  `regenerateAllThumbnails()` — the thing everyone assumed dominated — is 17%.
- **The seven device reports and the geometry rulings were written up** (`da96c0c`, `73d0402`, `87ed588`,
  `1aacb74`, `0164eb3`, `c267322`, `35b541c`, `c919014`, `61ed6fa`, `69d1492`, `6a609ba`) — including
  [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md), whose review found the ink-loss defect now at the top of
  BUGS.md.
