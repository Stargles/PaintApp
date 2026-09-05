# The brush engine overhaul

TODO item (37). The specification for how a brush stroke is captured, stored, and stamped, and for the
artist-facing brush editor that makes every parameter sensor-driven.

[BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) is the assessment that preceded this and
is still accurate about the seams; where the two differ, this document is the specification and that one
is the survey. Its ordering — image primitive, then tip enum, then grouping, then parsers — survives
into §12 with one stage added in front of it.

---

## 1. The brief, verbatim

> "Right now, my understanding of the brushstroke is this: When you put your pen down, it places a
> string of connected points making up the shape of your brushstroke. After that, it populates the line
> that it makes with sprites evenly distributed across it. I think this is a rather redundant way to
> make it if it is correct, and a great simplification can be that points are the sprites, one for each
> point.
>
> Here is where I need some brainstorming. I am unfamiliar with what mechanics clip studio paint or
> adobe uses for their brushes, so I need to talk with you to specify how the brush engine will work.
> From my knowledge, when you place your pen down, it stamps a string of sprites from your pen. However,
> that means we need to add stuff like randomized rotation, translation, and size to each stamp as well
> as im guessing the distance between each stamp too. I know there has to be a feature in which the
> rotation of your brush follows your brush's painting direction too. Also, there is the thing about
> never sampling only at mouse events, with reconstructing a continuous stroke first, then using that
> instead. This allows stabilization. Also, I think brush grain could potentially be removed since that
> is going to be attributed to the brush sprite itself. This means cleanly removing all traces of it as
> if the feature never existed. I also know that the brush option menu should have a procreate like edit
> brush option, in which you can adjust the parameters for that brush, for example the pressure curve,
> randomness, etc. Every parameter should be able to be sensor driven. Like clip studio paint, we have
> inputs (pressure, tilt x, tilt y, velocity, etc) and outputs (size, opacity, flow, angle, etc)
>
> Note: I still want the points themselves to have the least possible memory usage. Right now they have
> position and pressure. I can already see this being not enough, so let me know which ones to add and
> if there are smarter ways to add them which take less memory. For example, rotation and scale may be
> one of them."

And, separately, the constraint that shaped §4:

> "Lets say you have a randomness that displaces the brush stroke x and y location from its origin. Now
> lets say the brush stroke is split. You need to handle randomness in a way such that the randomness
> seed does not reset for half of the brushstroke now that it did that."

---

## 2. Rulings — settled, do not re-litigate

**2.1 The brief's description of today's engine is correct.** A polyline of samples is stored and
`BrushStamper` walks it, emitting dabs at a spacing. Dabs are interpolated *between* stored samples with
pressure ramped linearly across each segment, not placed *at* them.

**2.2 One sprite per stored point is refused, and the redundancy the brief names is real but lives
elsewhere.** Sample rate is a property of the hardware and of hand speed — the Pencil reports ~240 Hz,
so a slow stroke yields hundreds of points per inch and a flick yields five. One sprite per point makes
a slow stroke a solid dark blob and a fast one a dotted line: **the same brush at the same pressure
would change darkness with hand speed.** It also deletes spacing, which is the parameter that
distinguishes a marker from a dotted trail and is the defining control of a stamp brush.

The genuine redundancy is that the stored path is captured at input rate. **The fix is to store fewer
points, not more dabs** — §5.

**2.3 The stroke is reconstructed as a continuous curve before anything walks it.** Owner: *"I agree,
reconstruction could be better, lets go with that."* This is not an optimisation; §5.3 makes it a
correctness requirement.

**2.4 Grain is deleted in full.** Owner: *"Delete all of grain."* Including canvas-anchored paper
texture, which a sprite cannot reproduce — a sprite travels with the stroke, paper does not. Removal is
total: no vestigial field, no disabled control, no "this used to be" comment. §9 is the inventory.

**2.5 KEYFRAMES §2.16 is discharged by §2.4, not implemented.** That ruling — *"a stroke you Move keeps
its grain instead of re-sampling"* — was declined and inherited by this item on the reasoning that grain
would change when brushes became importable. It changes by ceasing to exist. The tests that pin
grain-travels-with-posed-ink are deleted with the feature rather than rewritten.

**2.6 No barrel roll.** Owner: *"For memory, no barrel roll."* Apple Pencil Pro rotation is not a sensor,
and on the owner's hardware it could not be one: barrel roll needs a Pencil Pro, which needs an M2 iPad,
and theirs is a 9th-generation iPad taking a first-generation Pencil. So unlike §2.7, this ruling does not
turn on the storage cost and is not reopened by measuring it.

**2.7 Tilt ships — altitude and azimuth are both sensors.** The owner deferred it on storage grounds and
reversed that on the measurement: a thousand strokes of geometry is **0.9 MB** ([PERFORMANCE.md](PERFORMANCE.md)
§11), so two more bytes a point is not a cost worth a feature. Owner: *"Since I now know that brushstroke
memory usage is minimal, i will go ahead and make the assertion to add in the pencil tilt that i previously
canceled."*

**It lands in §12 stage 4, which is where the record is built anyway**, so it is two more channels rather
than a change of plan — the seam §5.5 required was built for exactly this and is now carrying a shipping
feature instead of a hypothetical one. What it unlocks is the class of brush the app could not have at all
without it: **anything that shades broadly when the Pencil is leaned over** — charcoal, a soft graphite
edge, a chisel whose nib angle follows the hand rather than the stroke. §8.6's Sketching group is where
that shows up.

**Azimuth is stored in the space the samples are in**, so a stroke's ink does not change on re-render
after the artist turns the canvas, and a nib angle rotates *with* the drawing when a lasso or a layer
transform turns it — which is both what a physical nib does against paper and what §4.1 already decided
for arc length by measuring in brush widths.

**This section used to say the capture was in view space and had to be converted, and building it
refuted that.** `UITouch.azimuthAngle(in:)` expresses the angle in the given view's coordinate system
exactly as `location(in:)` does the point, and `StrokeInput` reads both from the *same* view — a
`StrokeCanvasView`, which sits under the `container` that carries the canvas's zoom and rotation. So the
capture is already in the space the position is in and there is nothing to subtract; the invariant is
that the two are read from one view, and `StrokeInput.init(touch:in:)`'s single `view` parameter is what
enforces it. **The conversion that really was missing is one level in**: the vector layer's own
transform, the lasso's, and a canvas resize's, none of which capture can know. All three arrive at
`StrokeSamples.transformed(by:)`, which turns every angle channel by the affine's polar rotation
`atan2(b - c, a + d)` — the same rotation `DabPose` picks for an image dab, and for the same reason. A
non-affine map (an interpolation lattice warp) has no single rotation and carries the angle unchanged;
§13 holds that open.

**Every stroke carries tilt, whether or not its brush reads it.** The alternative — capture only when the
selected brush has a tilt modulation — costs 0.4 MB a thousand strokes to avoid and would make §2.10's
apply-to-existing verb lie: re-pointing an old stroke at a tilt-driven brush would render it with the
neutral and no explanation. The neutral stays regardless, because a **finger** has no tilt and never will.

**2.8 The sensors are pressure, tilt angle, tilt direction, stroke direction, taper distance, random, and
velocity.** Direction is
the brief's *"rotation of your brush follows your brush's painting direction"*. Taper distance is
position along the stroke. Velocity is the only one of the five that costs storage.

**2.9 Brushes are deduplicated into a document-level table.** Owner: *"deduplicating into a document
level table is preferred."* A stroke holds a small index, not a `Brush` by value.

**2.10 A brush edit does not change strokes already drawn, and there is an explicit verb that applies it
to them.** Editing mints a new table entry; existing strokes keep the entry they were drawn with. A
separate command re-points a selection, a layer, or the document at the edited brush, as one undo step.

**That verb is one arm of a tool the owner has asked for**, which also changes a selection's brush *kind*,
size and colour with the result visible live while it is being adjusted — [TODO.md](TODO.md) (42). Two
things follow for the stages before it. The table (§12 stage 6) is what makes re-pointing cheap, since it
is an index write rather than a per-stroke `Brush` rewrite. And **live adjustment is a middle-of-list edit
on every tick**, which is the case TODO (41) exists for: at the owner's measured density a whole-cel
re-walk is ~142 ms, so a slider driving one would be unusable long before the drawing is large.

**2.11 Opacity and Flow are separate controls, and the per-stroke buffer they require is accepted.**
Opacity caps what the whole stroke can reach however often it crosses itself; Flow is what one stamp
lays down. The stroke composites into its own buffer and merges at pen-up. BUILT, §12 stage 8.

**The two questions this left open were ruled on 2026-09-04, and both went the same way.**

- **Pressure drives flow, not a per-dab ceiling.** *"A light pass is faint; go over it again and it
  darkens, up to the stroke's opacity and no further."* The Photoshop-style per-dab ceiling — where a
  stamp may not take a pixel past some fraction however many stamps land on it — was offered and
  **declined**. So the `opacity` output is deleted outright rather than kept as a ceiling beside flow,
  and every preset's `opacity ← pressure` row became `flow ← pressure` with its numbers untouched.
- **The eraser obeys the same rule.** *"A 50% eraser removes exactly 50% wherever the stroke goes,
  however often it crosses back over itself."* That is not what punching each dab produces — N punches
  at `aᵢ` leave `∏(1 - aᵢ)`, which no cap can be applied to after the fact — so an eraser stroke
  accumulates *coverage* and one `.destinationOut` merge takes it away at the stroke's opacity.
  MEASURED on the owner's own gesture shape in the simulator: an eraser at 43% dragged over ink and
  then retraced back along itself removed a median **0.436** of it, where punching per dab would have
  removed `1 - 0.57² = 0.675`.

**2.12 The lag-brush stabilization slider stays as it is, and the refit is always on.** The refit is a
fixed low geometric tolerance, not a per-brush parameter.

**2.13 Per-dab randomness is a hash of the stroke's seed and the dab's distance along the stroke, never
a sequential stream.** §4 in full. This is the ruling that answers the brief's split-stroke constraint,
and it answers three more the brief did not raise.

**2.14 Nothing of the old engine survives beside the new one.** Owner: *"keep architecture clean with no
legacy code. Everything currently on the ipad is expendable, so we don't need backwards compatibility, and
no traces should remain from the previous version of the brush engine. If by any chance future
modifications to the brush engine are to be added, the architecture should be easily flexible as it is
clean."* §10 is what this means concretely, and it governs every stage of §12.

**2.15 Rotation and scale are never stored per point or per dab.** They are derived. Storing them would
freeze the brush into the stroke, which contradicts §2.10's apply-to-existing verb and the whole reason
a vector layer is worth having.

**2.16 The shipped brushes are replaced wholesale, organised into groups, and the artist can make their
own.** Owner: *"all the current brushes should be removed and replaced with these as current brushes are a
legacy feature. Ideally it contains: round brush (soft and hard), square brush, some pencil and pen
brushes, and some other brushes. I also like the idea of having a brush which is like an ink pen and is
rough, almost giving it a sort of slightly rough blotchy sketchy feel to the lineart. A lot of brushes
would be nice, organized into groups, with the option to make my own."* §8.

**2.17 Every `random` modulation carries a wavelength, and the rough ink's dropout ships at three to four
brush widths.** BUILT, §12 stage 7. §2.13 rules that a per-dab random is `hash(strokeSeed, arcLength)`; the wavelength makes that
value band-limited rather than white — it interpolates between hashed lattice points λ of arc length apart,
and λ = 0 is a fresh draw per dab. Nothing about §4 changes: there is still no sequence and no phase, so a
value survives a split, a refit, a spacing edit and an eraser punch for the same reason. **λ is what
separates a stipple from a segmented line.** At λ = 0 ten overlapping dabs cover every point, so dropping
half of them only roughens the edge; at λ ≈ 3–4 widths a contiguous run drops and the line breaks into the
long arcs the owner picked out of the comparison sheet. One output may carry several `random` rows at
different λ, which is how a rough nib gets slow thick/thin variation and fine edge fuzz out of one input
with no spectral-slope parameter.

**2.18 `density` is an output — the probability that a dab is stamped at all.** BUILT, §12 stage 7 —
`BrushDabSettings.density` and `.densityWavelength`, drawn on `DabRandom.Channel.density`. The dab is skipped when its
random draw exceeds it. Nothing special-cases pressure: the owner's *"at very low pressure, segments of the
brush aren't painted (its noisy), creating a sort of segmented lineart filled with gaps"* is `density ←
pressure`, one row of §6's matrix like any other. **The coherence lives in the draw, not in the value
compared against** — modulating `density` by a coherent random while drawing white noise gives a thinned
speckle rather than gaps — so λ sits on the `density` row itself.

**2.19 A taper is low pressure, so `density ← pressure` is a threshold curve rather than a ramp.** BUILT —
`ResponseCurve.threshold(knee:low:high:)` and `BrushModulation.densityFromPressure(knee:floor:)`. Density
holds flat at 1 above about a third of full pressure and falls below it. Without that the dropout eats the
point of every tapered stroke and a hair spike ends in gaps; with it a taper keeps its point while a stroke
drawn genuinely light breaks up along its whole length. That is the shape of the curve §6 already gives
every modulation, not a mechanism of its own.

**2.20 A brush parameter is changed in the brush editor and nowhere else.** The side toolbar carries
**size and opacity only** — the artist's own two numbers — and gains nothing, ever. Everything that
belongs to a *brush* lives behind the editor. Owner: *"The side menu sliders stays as is: opacity and
size. None should be added to that menu. The edit brush menu is where you put all the brush adjustment
things."*

The navigation is ruled with it. **Tapping the brush icon while it is already selected opens the
brushes menu** — the whole library, arranged into the folders §8.2 gives it, with an **Add brush**
button that is where §12 stage 12's importers land. **One tap selects a brush; a second tap on the
selected brush opens the editor.** So selection and editing are the same gesture repeated, which is
the grammar the tool icon already uses one level up.

`StrokeSettingsPanel`'s two `Pressure → X` rows and its stabilization and spacing sliders are what the
editor **absorbs** when it lands; they are not a second home for brush parameters, and stage 8 adding a
Flow slider beside them was a mistake reversed rather than a precedent. §7 is the design.

**2.21 An imported brush arrives with its dynamics mapped, not merely its tip.** Owner: *"ABR brushes
(or procreate or other types) should automatically get assigned these settings based on the information
they have, if available."* So §12 stage 12 is an **adapter** onto §6's matrix rather than a bitmap
reader: whatever the source format states about pressure, tilt, spacing, jitter and scatter becomes
rows, and what it does not state is left at the neutral rather than guessed. The owner's *"if
available"* is the whole licence for that asymmetry — a brush that lands with three rows and an honest
tip is right, and one that lands with eleven invented ones is not.

**2.22 A modulation row carries a second input, and its reading multiplies the first.** **BUILT, and
its `second` field became §2.28's scale module on 2026-09-05 — the ruling below survives inside it
except for one clause, which §2.29 reversed the same day: the module *is* curved now, and what it
curves is its own sensor's reading. A scale still attenuates and `amount` is still the only signed,
unclamped term.** §6 became `output = base + Σ amount · curve(input) ·
reading(second)`, where the second input is optional and its absence reads 1. That is the smallest thing that says *"how much random wobble there is depends on
pressure"* — §7.0's fourth worked example, which the additive form could not state at all.

Owner: *"i really don't know, your call. Get something working that i can interact with on the ipad and
ill tell you if i want changes. Thus clean architecture is critical so it could be replaced easily."*
**The last sentence is what chose between the three candidates**, not expressiveness. A nested `amount`
— one row opening into its own rows, which is CSP's model — is strictly more expressive and is the
wrong first answer here: it makes `Brush.dabValues` recursive, and that is the hot per-dab loop, one
pass over a flat array. A second slot is a **flat** field, one multiply in the loop that already exists,
one picker per row in the editor. And it is replaceable in the exact sense the owner asked for: a second
slot **is** a one-row nested matrix, so if nesting is wanted later the slot becomes its degenerate case
and nothing is un-built.

**The second input is not a second row, and the difference is the whole point.** Two rows *add*, so they
give a pressure shift **plus** a fixed-amplitude wobble; a second input *scales*, so the wobble's
amplitude is what pressure moves. `density` reaches the same place by a different road — §2.18's
coherence-lives-in-the-draw — and that road is not general, which is why segmentation works today and
spacing jitter does not.

**A second input attenuates; `amount` is how a row is made bigger.** The gain is clamped to `0…1`,
which the ruling did not originally say and which building it made necessary: without it one sensor
could be flattened as an *input* by its curve and then *amplify* as a gain, so the same reading would
mean two opposite things depending on which slot it sat in. `amount` is the signed, unclamped term and
stays the only one.

**Two traps it carries.** A row whose *both* inputs are `random` must draw two independent values, so
the second slot needs a channel of its own — §4's channel is derived from (output, row), and reusing it
would square one draw rather than multiply two. **An offset inside the output's own 4096-row block is
the wrong shape and that same doc says why** — at any stride `s`, row `s` of one output collides with
row 0 of the next, so halving the stride reintroduces the collision at half the distance. The gain is a
whole second **plane**, `1 << 20`, past the matrix's entire span, so no row count can make the slots
meet. And the second input is **not** curved: a curve on it
would be a second `ResponseCurve` per row for a gain term, which is expressiveness the ask does not need
and a second thing to keep in step.

**What the build settled, beyond the two traps.**

- **The gain slot is a whole second *plane* of channels, not a second half of the row block.**
  `DabRandom.Channel.modulation` takes a `slot` and offsets by `1 << 20`, which is past the matrix's
  whole 49,167-value span, so **no row count whatever can make slot 0 meet slot 1**. Halving the 4096
  stride would have worked and is the wrong shape: it reintroduces, at half the distance, exactly the
  collision that function's own doc reasons about. Slot 0's arithmetic is unchanged to the bit and is
  pinned against the literals it produced before the parameter existed, because a change there re-rolls
  every stroke ever drawn with a randomised brush.
- **Two scanners over the rows had to widen, and both guard something real.**
  `BrushModulations.isPressureOnly` asks the gain slot because `dabValues(atPressure:)` answers every
  other sensor with its neutral: a `size ← pressure × velocity` row contributes *nothing* there and
  plenty along a real stroke, so §6.3's capsule chain would bound the ink at the wrong width and
  `VectorEraser` would cut away faded ink it never saw. `readsTaper` asks it for the mirror reason —
  `StrokeSensors` answers `taper`'s neutral, **1**, where the stroke's length was not measured, so a
  gain of `taper` would sit at full gain for the whole stroke and a brush that does not taper would
  render green.
- **The gain is clamped to `0…1` and the first reading's clamp is its curve's.** Every `BrushInput` is
  defined to answer inside that range, so leaving the second slot alone would treat one sensor
  differently in the two slots: a stray reading above 1 is flattened as an *input* and would *amplify*
  as a *gain*. A second input attenuates; raising `amount` is how a row is made bigger.

**2.23 Not every brush is a dab walk, and the architecture must survive the first one that is not.**
Owner: *"There are also some special brush types I want to add which may follow custom brush logic, so
again, design the architecture cleanly and well thought out. These include stuff like the fill brush
(you draw and then it applies a fill inside of its contour when you lift the pen), and other special
brushes."* **Not scheduled** — the owner put it well after the shipped set — but it constrains what may
be assumed before then.

What it forbids is one assumption: *"a `Brush` is a description of how to stamp dabs"*. It is that
today, and the first fill brush makes it *one case of* something larger. The seam that has to stay
clean is therefore **where a stored stroke becomes ink**, and the good news is that it is already one
place per tier — `VectorLayer.stamp(stroke:into:isEraser:)` on the replay side and
`StrokeCanvasView.stampPath` on the live one — with `VectorStroke` storing samples and a `BrushRef` and
nothing about dabs. A fill brush stores the identical stroke and resolves differently at those two
sites; it needs no new storage and no format change.

So the rule for every stage before it: **a brush's *behaviour* is discriminated at those two call sites
and nowhere else.** Anything that spreads "walk the path and stamp" into a third place — a cache keyed
on dab counts, a bounds computed by assuming dabs, an editor that cannot render a brush with no spacing
— is what would have to be undone. §9.2 is the general form of this and this is its first named
consumer.

**BUILT.** `BrushTextureSettings` is three fields — the `BrushTextureRef` mask, `tileSize` (the side of
one repeat, **in canvas points**, so the anchoring is expressed in the units it is a claim about) and
`depth`, whose 0 is exactly no texture. It hangs off `Brush` as an **optional**, so a brush without one
takes no branch anywhere and hashes to what it hashed before; §9.2's *"nothing beyond what the stage
needs"* is why there is no offset, rotation, contrast or invert.

It rides `DabTarget.beginStrokeGroup`, because the group *is* the moment §2.4 said did not exist.
`BrushTextureMerge.apply` multiplies it in with `.destinationIn` **inside** the transparency layer,
after the dabs and before the merge's own `setAlpha` — which is the owner's sentence in the order the
owner said it: the accumulated untextured walk is the transparency mask, and the stroke's opacity then
scales the textured result.

**Canvas-anchored costs exactly one number, and it is `RasterLayerTexture.canvasOrigin`.** A live stroke
accumulates in a `StrokeScratch` window positioned at the pen and *reallocated* as the stroke grows;
without the phase the paper would be anchored to wherever the pen started and would slide at every
reallocation — which is the sprite behaviour §2.4 deleted, reached by accident. Every other target's
origin is `.zero`, and the two previews are the deliberate exception: a swatch sits in no canvas, so
`BrushPreview` and `SizePreview` anchor to their own origin.

**Every tier, and there are four rather than three.** The cel (`RasterLayerTexture`), the render-local
context (`CGContextDabTarget`, which is `VectorCanvas.renderLocalContent`), the **ungrouped** live walk
— `StrokeCanvasView.stampPath` stamps dabs with no group open, so the scratch carries the texture
itself and applies it where the window merges — and a **grouped walk inside a scratch window**, which is
`VectorCanvas.applyPreview`'s restamps and the only reader of `canvasOrigin`. Nothing was added to
`DabImageCache` or `DabGradientCache`: a texture in a dab-level key would be a texture in the wrong
place. Nothing was added to `PixelOps.RasterizeKey` or `LayerContentVersion` either, and that is a
finding rather than an omission — the texture is a field of `Brush`, `Brush` is `Hashable`, a stroke
stores a `BrushRef` into the pool addressed by that hash, so a textured brush is a different stored
value and every key already downstream of `vectorVersion` moves on its own.

**The eraser textures its removal**, because §11's *"the eraser is a stroke"* is the whole architecture
and an exception would be the thing to justify. One consequence had to be written down:
`VectorEraser.supportsCleanCut` now refuses a textured brush outright, since it removes
`depth·(1 - texel)` less than its footprint claims and a clean cut would delete ink the punch would
have left behind — the asymmetric direction that gate is built around.

**A brush's texture travels with the document by the tip's own route.** `Brush.importedTextureFileNames`
is now the single statement of *"which files does this brush need"*, and both `BrushTable` and
`ProjectStore`'s save-and-restore filter read it rather than re-deriving it — BUGS.md's
*"copied by the palette, not by what is drawn"* is one missed union away from being true again, one
field along.

**What it is not, yet: reachable.** There is no editor control for any of the three fields, so today a
textured brush can only be built in code. That is §12 stage 10's job and is the honest state to record
rather than a defect — but it does mean nothing in the shipped app draws with paper, which is why the
byte-identity pin below is the one that matters most.

**It was still driven by hand before being called done**, per CLAUDE.md's *"a feature is not finished
because its model is correct"*: a sixth preset carrying a sheet was added to `BrushLibrary.defaults` in
a working tree that was never committed, built, installed on the simulator and drawn with. Three things
came out of that which no logic test would have said. The brushes menu's own **preview swatch is
textured**, because `BrushPreview` goes through `stampStroke` and inherited the feature with no change —
so the artist will see which brushes carry paper before picking one. Two strokes drawn a canvas inch
apart carry **visibly different** paper, which is the anchoring at the scale a person judges it. And
`tileSize` **96 against a 128-pixel sheet** — a downscale, chosen deliberately because that is where the
per-tile edge clamp above would show — has **no visible seam**, which is the observation that comment's
INFERRED is standing next to.

**What it cost, MEASURED.** Nothing per dab: the merge does one `.destinationIn` tiling pass over the
stroke's own clip, and `BrushTextureMaskCache` holds the depth-adjusted, pre-flipped sheet per
*(mask, depth)* for the life of the process — so a stroke pays one tiled blit and a brush pays one
bitmap build, ever. The key deliberately has **no size term**, which is how it avoids being the fourth
of RENDER.md §3.8's three size-keyed memos rather than merely hoping not to be. An untextured brush
renders **byte-identical** to `b4dffeb`: `BrushTextureLogicTests` carries FNV-1a digests of a round-tip
stroke on the cel and render-local tiers and a stamp-tip stroke on the cel tier, all three measured on
that commit before any of this existed.

**2.24 The editor is a screen, not a panel, and its shape is a chain per output.** Owner: *"The brush
edit menu right now is a little menu, whereas in Procreate it is like a separate screen. For this menu,
I think we need to have it cover the entire screen due to the complex interactions it can have."* The
brushes menu stays a dropdown and **wants to be taller** — the owner asked for more brushes visible at
once — but the editor is full-screen.

Its shape is the owner's own, and it is **not** the flat row list §6 stores:

> *"there should be a dropdown list of all the outputs of the brush ... These can be organized into
> groups. Clicking on one of these outputs will expand it down into the controller. You select the input
> option of the brush (pressure, tilt, etc). Then you can add modifiers onto it, like it passes through
> an input/output curve ramp module, then a randomizer module. This means that for each output there can
> only be one input for now, but I think thats alright, though in the future it may change."*

So: **outputs are the index**, each expands to *one* input followed by an **ordered chain of modules** —
a curve ramp, a randomiser, and whatever else earns a place. §13 carries where this and §6 disagree and
what it costs to close the gap; it is a real difference in both directions, not a skin.

**BUILT 2026-09-05 — §7.2 and §12 stage 10.** The chain and the row turned out to agree on the ordinary
case rather than merely being mappable onto one another: `amount · curve(input) · reading(second)` read
left to right *is* input → curve ramp → randomiser. §13's entry is the four places they part, and the
editor shows the relevant sentence rather than offering a control the engine cannot honour.

**Three outputs the owner named that do not exist yet.** `flow` does and is *"alpha of dab, not to be
confused with opacity"*, which is exactly what §2.11 built. **Vertical/horizontal stretch** is the
`roundness` §6 deferred, and it is the expensive one — a second extent through both `DabTarget`
primitives, `BakedDab`, `DabPose.applied(to:)`, `dabBounds`, `StrokeScratch`'s window and every dirty
rect. **Vertical/horizontal offset** is a *directed* displacement, which §8.4 has a negative result
about: coherent `scatter` and a pure perpendicular offset were indistinguishable, so no `offset` output
was built. An offset the artist aims is a different thing from that and does not inherit the refutation.

**2.25 Texture returns, canvas-anchored, and this reverses §2.4.** Owner, having ruled *"Delete all of
grain"* at the start of this overhaul: *"a lot of paint programs have something called texture ... its a
texture that gets applied over your brush ... Texture is applied relative to canvas, and uses the
untextured brush as a transparency mask, then is scaled with opacity."*

**Say plainly what changed and why it is cheap now.** §2.4 deleted grain *including* canvas-anchored
paper, and gave a reason: *"a sprite travels with the stroke, paper does not"* — with the ink composited
dab by dab straight onto the layer, there was no moment at which the whole stroke existed as a mask, so
paper could only have been faked per dab. **§12 stage 8 built that moment.** A stroke now paints into
its own buffer and merges once, so the texture multiplies in **at the merge**, against canvas
coordinates, with the buffer serving as exactly the transparency mask the owner describes and the
stroke's opacity scaling the result. The feature that was structurally awkward is now a few lines in one
place.

**Canvas-anchored only.** The owner was offered stroke-anchored as well and did not take it, and the
reason to be glad is §2.5's: ink that travels — a lasso move, a pose, an interpolation — would have to
re-sample or bake a stroke-anchored texture, which is the whole argument that deleted grain the first
time. Paper does not move, so nothing has to be baked.

**It is what makes §2.21's importers honest**, since most `.abr` and Procreate brushes carry a texture
and a brush imported without one is not that brush.

**2.26 Tips and textures are libraries, not per-brush files.** Owner: *"their dab sprites should have
the ability to be changed, as well as texture. For these two, it may be worth having a library of
textures and sprites to which new sprites can be added into."* So the editor picks a tip and a texture
from browsable collections, and importing adds to a collection rather than to whichever brush happens to
be open. Two collections, because a tip is a shape and a texture is paper and an artist reaches for them
at different moments — but **one storage mechanism**, since both are a named bitmap under §2.27's root
and `BrushTextureRef` already resolves exactly that.

**2.30 Scatter is two amounts oriented to the stroke, not one isotropic disc.** Owner: *"is offset an
output? like horizontal or vertical offset of the sprite from the center of the stroke oriented relative
to direction of the stroke. This being randomized is a well known feature of many paint apps, so the
sprites arent just rotated randomly, but also randomly translated to an extent."*

`scatter` today is **isotropic and unaware of the path**: `BrushStamper.applyScatter` draws a free angle
and a distance, so a dab lands anywhere on a disc. The two axes are therefore coupled at equal weight and
neither is reachable alone. They do different things:

- **Across** (along the normal) widens and frays the stroke — the silhouette goes hairy while the ink
  stays evenly spaced.
- **Along** (along the tangent) widens nothing; it bunches and gaps the dabs, so density goes irregular
  without the line getting thicker.

So `scatter` is replaced by **`scatterAcross` and `scatterAlong`**, two outputs modulatable
independently, with the old isotropic behaviour expressible as both set equal. §2.14 governs: the old
single output is deleted rather than kept beside them.

**§8.4's negative result stands and does not cover this.** It measured that *coherent* `scatter` and a
pure perpendicular offset are indistinguishable, so a separate `offset` output bought nothing **for the
rough ink nib**. That is a statement about one brush under coherent noise, not about independent per-axis
amounts, and §7.2 already carries the qualification that an offset the artist *aims* does not inherit the
refutation.

**It costs nothing measurable**: the same two draws, resolved onto the tangent and normal instead of a
free angle, and `StrokeGeometry.tangent(atParameter:)` is already computed because `angle`'s
direction-follow reads it. **The one thing it does touch is the merge bound** — §12 stage 8's stroke
group clips to a rectangle derived from the brush's own maximum reach, and that derivation must take the
larger of the two axes rather than one `scatter`, or a heavily across-scattered stroke loses ink at the
clip. That is the failure direction the bound was written to avoid.

**2.29 Every module that reads a sensor carries its own input *and its own curve*. This supersedes
§2.22's "the second input is not curved".** **BUILT 2026-09-05, in the same pass as §2.28** —
`BrushModule.scale(BrushInput, ResponseCurve)`, with `.linear` left off the wire so a scale written
before this and one written after are the same two keys. Owner, with the case that forces it:

> *"lets picture a scenario where the spacing is randomized but also driven by brush pressure, where the
> lighter the pressure is, the more frequent you get segmented lines, but over lets say 30% pressure, it
> appears as a solid line. Thus It requires two inputs assuming randomizer is an input ... So two inputs:
> pressure and random, with a curves module to make strokes over 30% pressure as solid lines."*

§2.22 ruled a gain uncurved because *"a second `ResponseCurve` per row for a gain term is expressiveness
the ask does not need"*. **The ask needs it now**, and this is the whole change: a `scale` module becomes
*(input, curve)* rather than *(input)*. The owner's scenario is then one flat chain —
`spacing ← random(λ) → scale by pressure through a threshold curve` — where the curve returns 0 above a
third pressure, so the wobble vanishes and the line is solid, and returns towards 1 below it.

**This is what keeps a chain a list rather than a graph**, which is the property worth protecting. Two
sensors meeting inside one mapping is the case that would otherwise force branching nodes and wiring;
carrying the second sensor *inside the module that consumes it* expresses the same thing in a flat
ordered list. Three sensors is two `scale` modules. §2.22's other clause survives unchanged: **a scale
attenuates** — the shaped reading is clamped `0…1` — and `amount` remains the only signed, unclamped
term.

**What the build settled.** `.linear` is not a special case: `ResponseCurve.value(at:)` on an empty
curve **is** the `0…1` clamp §2.22 asks for, so an uncurved scale is the plain multiply it was, to the
bit, and the clamp is applied once rather than twice. The editor draws the curve **inside** the module,
because a curve outside it is a `.curveRamp` and means something else — the two would be
indistinguishable side by side, and `BrushModulationLogicTests` pins that they *are* different by
rendering the owner's own chain against the same curve worn as a ramp after the scale. That second brush
is the operand: without it the test would pass against an implementation that shaped the wrong value.

**The owner's example is also achievable today by a different route, and both should exist.** §2.18's
`density` with §2.19's threshold curve is exactly *"segments below a third pressure, solid above"*, and
it is the **broken** line — ink, gap, ink, survivors left where they were. Randomising *spacing* spreads
the dabs instead, which is a **dotted** line. They are different marks and the difference is §8.4's:
dropping dabs moves nothing that stays.

**2.28 A modulation is an input followed by an ordered list of modules, and this supersedes §2.22's
fixed shape.** Owner, on seeing the editor present a chain over storage that is not one: *"does it
contain the modular approach? right now there seems to be a hardcoded order for everything. For example
we may sometimes need the randomizer first, then use curves to remap the range."*

`output = base + Σ chain(input)`, where a chain is the sensor's reading passed through modules **in the
order the artist put them**: a **curve ramp**, a **randomiser**, a **scale-by-sensor**. §2.22's `second`
slot becomes the third of those rather than a field, and its ruling survives inside it — a scale
attenuates, `amount` is still the only signed unclamped term.

**This is the boundary §13 recorded rather than a new idea**, and the owner hit it twice: the shipped row
evaluates `amount · curve(input) · reading(second)`, which is *one* order and cannot state
"randomiser, then a curve to remap the result". The editor was honest about that in words on the screen,
which is what made the limit visible enough to be asked about — that is the argument for a screen that
states what the engine cannot do rather than hiding it.

**The randomiser carries octaves.** §2.17 rules that every `random` modulation has a wavelength λ, and
§8.4 found that *"several `random` rows at different λ give multi-scale roughness, so there is no octave
or spectral-slope parameter"*. That refutation was about not adding a *spectral slope*; it assumed the
several-rows spelling, which §2.24's one-input-per-output makes unavailable and which in any case asks
the artist to add three rows and halve each amount by hand. One randomiser with a count and a falloff is
the same arithmetic, fewer objects, and one control — and it is **cheaper** than three rows, since each
octave is one hash and one lerp inside a module that is already resolved.

**What must not change**: §4's positional hash. There is still no sequence and no phase, so every octave
survives a split, a refit, a spacing edit and an eraser punch for the reason §2.13 gives, and each octave
needs its own channel or two of them are the same number twice.

**BUILT 2026-09-05.** `BrushModulation` is *(output, input, [BrushModule], amount)*; `BrushModule` is
`.curveRamp(ResponseCurve)` and `.scale(BrushInput, ResponseCurve)` — the second curve is §2.29, ruled
the same evening and built in the same pass; `BrushRandomiser` is *(λ, octaves, falloff)* and
`BrushInput.random` carries one. The editor's chain is **add / remove / reorder** over the stored list,
with no mapping layer between what is drawn and what is evaluated.

**Three modules were asked for and two cases shipped, which is a refutation rather than a shortfall.**
`.random` is a `BrushInput` — §13's own *"a pure randomiser is an input, not a module"* — so
`.scale(.random(…))` **is** the randomiser, and a third case would be two spellings of one behaviour
with two codecs and two channel derivations to keep in step, which is §10's two-ways-to-compute trap.
The *editor* offers three things to add, because that is the artist's vocabulary; the storage has two,
because that is how many behaviours there are. It also means one randomiser description serves both
positions, so §8.4's rough nib — a pure `random` input — gets octaves for free rather than being the one
place that cannot have them.

**Order is the artist's, and it is the whole feature**: a chain of *curve then randomiser* and the same
two modules reversed render different ink, MEASURED, and the difference is not subtle — with a threshold
curve whose floor is 0.35, randomising first and shaping after contributes **29×** what shaping first and
randomising after does at a low reading, because the scaled-down value lands where the curve's floor
lifts it back.

**What did not move**: §4's positional hash, and every shipped preset's pixels. A chain position is a
whole *plane* of channels (`slotStride`, `1 << 20`) and an octave a whole plane above that
(`octaveStride`, `1 << 40`), so the three coordinates read as digits of one base-2²⁰ number and no chain
an artist can build makes two of them meet. **Position 0 is the input and position *m + 1* is module
*m*, which is why §2.22's second slot and a chain's first randomiser draw the identical channel**;
**octave 0 is the channel itself**, so a one-octave randomiser is the single draw it replaces to the
bit. The five presets were pinned by rendering them in a **separate worktree at the commit before this**
and comparing digests, not by comparing two brushes in one process.

**The cost, MEASURED** — two pairs, `4791204` and then `860a4a0` against `tmp/chain`, each taken on one
device back to back on an idle machine; PERFORMANCE.md §11.2b carries the tables and the provenance. An
empty chain costs **nothing** (0.30 → 0.31 µs/dab, and the module loop is not entered); a module costs
about **0.06 µs**; the whole re-walk of a shipped preset went **5.65 → 5.89 and 5.62 → 5.80 µs a dab,
+3.3 to +4.3%**. **An octave costs 0.24–0.26 µs** and is the steepest thing on the path — eight of them
is +1.7 µs, about a third of a dab — which is why the count is capped at 8 and sits behind a slider the
artist moves deliberately. A deliberately extreme brush, six chains carrying eleven modules, measures
**10.99 µs a dab** against a shipped preset's 2.38. §2.29's second curve added nothing measurable: the
second pair was taken after it landed and reads the same as the first.

**2.27 The library must be relocatable, and the architecture owes that before the feature exists.**
Owner: *"Right now all the files are stored internally on the app, which means that if the app gets
deleted, then all the files get deleted too. I'd like it to be able to have an external folder, so build
the architecture so that in the future when this feature gets added, moving the library from internal
app storage to this external folder is easy."*

**The external folder is still not built and is still not scheduled. The architecture is — BUILT,
`Engine/BrushStorage.swift`**, which owns the root and is the only thing that turns a stored file
*name* into a location. What each of the three requirements turned out to be is worth writing down,
because this section was right about two of them and understated the third.

1. **Every stored reference is a *name*, never a path — verified rather than assumed, and it held.**
   Audited across every persisted surface instead of taken on trust: `BrushTip.stamp(.imported(fileName:))`,
   `BrushTextureSettings.mask`, `library.json`, `brushtable.json`, and `manifest.json`'s `selectedBrush`
   and `customBrushes`. No brush path is in `UserDefaults` — the library is a file precisely because
   `BrushLibraryStore`'s own note says a defaults key is invisible and outlives its writer. The only
   `URL` any document-shaped type in the repo holds is `VectorVideoElement.assetURL`, and it is
   documented runtime-only with `assetFileName` as the persisted half — the same split, reached
   independently, for the same reason. **It is the expensive one to retrofit and nothing had to be
   retrofitted.** What keeps it paying is requirement 3: there is now exactly one place a name becomes
   a location, so there is nowhere else for a path to be minted and stored.
2. **Every file lives under one root — this was the work, and it is done.**
   `BrushLibrary.customBrushesDirectory` is deleted, along with its side effect of creating the
   directory on every read. `BrushStorage` holds the root; `BrushStorage.shared` is the app's and is
   still `Documents/Brushes`, pinned by a test because a refactor that quietly moved it to Application
   Support would read as *"the artist's brushes are gone"* with nothing in a diff to point at.
   `relocate(to:)` is the verb an external folder arrives through, and
   `BrushLibraryStore.init(directory:)` became `init(storage:)`, which is the injection this section
   named.
3. **Every access goes through that one type.** `read`, `write`, `contains`, `remove` and `fileNames`
   are between them the whole of what the app does to a library file; `url(for:)` is **private**, so no
   URL escapes to be read somewhere a bookmark's bracket would not cover. The security-scoped external
   folder is five one-line brackets rather than an audit.

**Two things this section did not anticipate, and the first is a correctness requirement rather than
tidiness.**

**A relocation has to drop two caches.** `BrushTextureStore` memoizes a mask against a
`BrushTextureRef` — which is a *name* — and `BrushTextureMaskCache` holds a depth-adjusted copy of
that. Neither key names the root, which is exactly right while a process has one root and is
RENDER.md §3.8's family of bug the moment it does not: the same name under a new root would be served
the old root's pixels, and a file that was missing before the move would stay missing forever off a
negative entry. `relocate(to:)` drops both, which is cheaper than keying a root into two caches to
hold entries a relocation invalidates anyway. **It is also what makes the test discriminating**: with
the drops removed, *"the ink is identical after the folder moved"* is green against an implementation
that resolves no file at all.

**The injection is on the instance, not on every call, and the asymmetry is deliberate.**
`BrushTextureStore` and `BrushTipImport` take no storage parameter. Their cache and their writes are
process-wide, so a per-call storage would let an import land in a root the renderer never reads from —
an incoherence the single global being replaced could not express, and inventing a new one for the sake
of symmetry is what §9.2 forbids. `BrushLibraryStore` takes one because *two libraries over two roots*
is a state a test has to be able to build, and a test that pointed both stores at one directory would
be green against an implementation with no root at all.

---

## 3. The pipeline — four stages, one of them stored

| stage | what it is | stored? |
|---|---|---|
| **Path** | a stabilized, refitted centreline carrying per-point sensor readings | **yes — this is the document** |
| **Walk** | march the path by arc length at the brush's spacing | no |
| **Dab** | evaluate every brush parameter from its sensors at that arc length | no |
| **Stamp** | blit the tip with that size, angle, roundness, alpha | no |

Only the path persists. Everything from the walk down is a pure function of *(path, brush, seed)* and is
recomputed on every render. That is what makes §2.10's apply-to-existing possible at all, and it is
already how the app's vector tier behaves — this specification makes it explicit rather than changing it.

### 3.1 Capture

`StrokeGestureRecognizer` → `StrokeInput` is unchanged, including its `coalescedTouches` fan-out.
`predictedTouches` stays unused; it trades latency for a wrong line at pen-up and the lag brush already
owns the latency question.

`StrokeInput.altitude` and `.azimuth` continue to be captured and continue to reach only the action
recorder — §2.7. **They are not dead code and must not be deleted as unused**; §5.5. `timestamp` starts
being consumed, for §2.8's velocity.

### 3.2 Stabilize

`StrokeStabilizer` is unchanged — an exponential follow whose strength is the brush's `stabilization`.
§2.12.

### 3.3 Refit — BUILT, and not the way this section first described it

**`StrokePathFit` replaces `StrokeSampleGate` entirely, and the gate is deleted.** The stored record
stays a list of **on-curve points** — position and pressure at the time, and §5.5's channel set since
stage 4 — and what changed is *which* samples become points. A sample is kept when dropping it would move the stored
polyline further than a fixed tolerance from the path the pen drew, plus a cap on how far apart two
stored points may be. Nothing consults the brush. §5.3 is why the gate could not survive.

**This section used to say the fit produced cubic *control points* and that `PackedSampleRun` encoded
those. That was wrong on three counts and building it settled all three.**

1. **Blast radius, for no gain.** `[VectorSample]` is read by `StrokeGeometry.capsuleChain`, the vector
   eraser's parametric cut, `DabLattice`, lasso membership, the spatial index, the packer and
   interpolation's registration — every one of them a polyline consumer. Changing the *stored type* to
   cubics rewrites all of them in stage 0; changing the *density* of a point list touches none.
2. **It would create two representations that can disagree.** The renderer walks a curve either way, so
   what matters is that the fit's error bound and the walk's geometry are the same geometry. Fitting the
   chord bounds both: MEASURED, the stored polyline stays within **0.250 pt** of the drawn path by
   construction and the curve through it within **0.391 pt**. Fitting the *curve* instead would let the
   chord — which is what every polyline consumer above sees — drift by the whole sagitta, several points
   on a tight arc.
3. **A cubic fit inherits the exact objection that killed Douglas-Peucker here.** Interpolation deforms a
   stroke by warping its stored points, so a straight run collapsed to two knots bends as a straight line
   under a warp that should curve it. Cubics collapse a straight run the same way. **The answer is a
   maximum knot spacing alongside the tolerance**, and it is load-bearing rather than belt-and-braces:
   MEASURED, a finger-drawn 400 pt line at constant pressure stores **2 points uncapped and 36 at a 12 pt
   cap**, and the warped path falls **1.14 pt** from the truth uncapped against **0.08 pt** capped.

The record is therefore unchanged by this stage — §5.1 still describes it — and the tolerance is one
`PackedSampleRun.quantum`, so the fit is exactly as true as the format can store.

### 3.4 Walk — BUILT

Arc-length march along the fitted curve at `spacing`, which is itself a sensor-driven parameter (§6) and
so may vary along the stroke. The interpolant is a **centripetal Catmull-Rom** chain through the stored
points, evaluated as a cubic Hermite per segment (`StrokePath`), and it creases rather than smooths at a
knot the path turns through more than 60° — without which a traced right angle loses a MEASURED 0.868 pt
across the corner.

The tangent at each step comes from **the fitted curve**, never from a difference of consecutive stored
points: at the fit's knot spacing the chord direction is a *step function* of the parameter, so
direction-follow built on it would rotate in visible jumps. `StrokeGeometry.tangent(atParameter:in:)` is
the one consumer that exists today — it gives the eraser its cross-section normal — and it reads the
curve now.

**Positionally the curve buys nothing at this tolerance and costs a little**, which is worth stating
plainly because the obvious reading of §2.3 is that it buys fidelity. It does not: the chord is *more*
faithful to the drawn path (0.250 pt against 0.391 pt), because the fit is defined against the chord. The
curve is for the tangent, and for not polygonising a stroke walked at a spacing wider than it was drawn
at. The first dab sits on the first stored point and takes the outgoing tangent.

### 3.5 Stamp — built, §12 stage 3

`DabTarget` has an image primitive beside `stampCircle`:

```swift
func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode)
```

`stampApproximateSquare` — sixteen gradient-filled circles faking one square dab — is gone, and
`.square` is a committed 256² alpha PNG loaded by the same route a user's import takes — one route, since
stage 5, with the artist's own tip at the other end of it. There is no `hardness` on this arm: a picture's
edge is in its pixels.

**A tip's mask is square, by ruling.** One scalar for the dab's size keeps `DabPose` at one multiply,
`BakedDab` at one number and the dirty-rect bound at one `abs`; a non-square import is letterboxed into
a square mask at import time, which is also what Procreate's square Shape Sources do. Nothing downstream
of the primitive ever asks a tip how wide it is.

**The cache is keyed on the tip and the colour, and this section's original "rotation-bucketed" was
wrong.** Bucketing the angle is worse on both counts, MEASURED:

- *Accuracy.* A bucket's worst error is `π/N`, and the corner of the largest dab the app allows sits
  `141.4` px from its centre (the size slider tops out at 200 pt and the raster tier is 1 px per canvas
  point). Holding that corner inside half a pixel needs **889 buckets**.
- *Cost, at any N.* A rotated-CTM draw of one cached entry beats a pre-rotated bucket blitted
  axis-aligned at every size and every interpolation quality — 5.35 vs 122 µs at a 16 pt dab and 485 vs
  1082 at 200 pt on `.high`. A pre-rotated bucket must be `√2` larger to hold the turned square, so it
  covers twice the pixels, and N entries per colour also defeat CoreGraphics' own per-image downsample
  cache.

So the angle is applied exactly by the CTM, and §7's direction-follow inherits a primitive with no
quantisation in it to remove.

**The dab's size *octave* is in the key, and the measurement that settled it is the one taken in the
app.** A microbenchmark on macOS CoreGraphics said a power-of-two ladder of pre-scaled entries was worth
nothing against one native-resolution entry per tip — 5.89 vs 5.93 µs at 16 pt, 624 vs 623 at 200 — and
that was **misleading**, because macOS CG absorbs a large downscale far more cheaply than the simulator's
does. MEASURED in the app over a 500-sample stroke, per dab: **76.3 µs** with one native 256² entry at
`.high`, **6.9 µs** with the same entry at `.none` (which throws the antialiasing away), and **14.2 µs**
with the ladder at `.high`. So the ladder buys 5.4× and keeps the edge. The expensive resample of the
mask then happens once per entry — once per stroke — rather than once per dab, and an image dab settles
at about **2.1× a round one** (14.2 against 6.7).

That still leaves one entry per stroke, which the hit-rate test in `PerfBaselineTests` pins at one miss
and the rest hits; a stroke whose pressure ramp crossed an octave would legitimately miss twice. And the
key names the **tip** rather than only its dimensions, which is the assertion RENDER.md §3.8 says nobody
wrote for the three size-keyed memos already in this repo.

The cache is what makes the primitive affordable at all: building a tinted stamp is a bitmap build at
the entry's resolution, MEASURED at **162 µs** per 16 pt dab against **5.5 µs** when it is cached, and
814 vs 508 at 200 pt.

**`BakedDab` carries a tip rather than a flat `hardness`**, because `hardness` is meaningless on a
picture and `angle` is meaningless on a disc:

```swift
enum Tip: Equatable {
    case round(hardness: CGFloat)
    case image(BrushTextureRef, angle: CGFloat)
}
```

**`DabPose` turns an image dab by its Jacobian's polar rotation**, `atan2(b - c, a + d)` — the rotation
closest to the Jacobian, so the square the primitive can draw is the closest one to the parallelogram
the pose really makes of the dab. The obvious alternative, the angle of the mapped x-axis, agrees on
every rotation and fails on every shear. `DabPose.constantRotation` is nil exactly when
`constantScale` is: an affine's Jacobian is one matrix everywhere so both are one number, and **under a
projective pose the turn genuinely differs from dab to dab**, which is why the whole stroke cannot share
one. Without any of this, a sprite brush under a rotating keyframe keeps its stamps upright while the
stroke turns.

**A `.high`-interpolated image dab paints past its own quad**, MEASURED in the app at up to **0.99 px**
across six sizes × five angles — the resample kernel plus whole-pixel coverage. So the bound
`StrokeScratch` grows its window to and the one `strokeDirtyRect` accumulates both carry a spill
allowance, set at three times the measured worst because the two ways to be wrong are not symmetric: a
bound too large costs a slightly bigger undo patch, and a bound one pixel short does not look soft — it
deletes that edge of the stroke and then leaves it behind on undo.

---

## 4. Randomness — hashed by arc length, never a stream — BUILT

The brief's constraint is that splitting a stroke must not restart its randomness. The engine this
replaced was a sequential `splitmix64` seeded per stroke, kept in phase by `DiscardedDabTarget`, which
computed dabs outside a piece's visible range and threw them away so the sequence did not shift. That
worked, and it carried two implicit rules: every draw came from the passed-in RNG, and a dab drew the
same *number* of values whether or not it was drawn. A single conditional draw desynchronised everything
after it, and the symptom was not a crash — it was half a split stroke's ink moving.

**Splitting is one of four ways that stream goes out of phase, and this overhaul adds the other three.**

| | why the stream shifts |
|---|---|
| a stroke is split | the surviving piece starts at a different dab index |
| **the path is refitted** (§3.3) | dab positions and dab *count* change |
| **a brush's spacing is edited** (§7) | every dab index shifts |
| the eraser punches, or an in-between re-derives the walk | the walk is rebuilt from different geometry |

No seed-inheritance rule survives all four. So:

> **Every per-dab random value is `hash(strokeSeed, channel, arcLength)`.** There is no sequence and no
> phase.

A dab 43.2 brush widths along the stroke draws the same scatter and angle jitter forever — whichever half
of a split it lands in, whatever the refit did to the point count, whether it is dab #200 or #150.
`Engine/DabRandom.swift` is the whole of it.

**A `channel` is what replaces "the next draw off the stream", and it is not optional.** Scatter angle and
scatter distance are two values at one arc length; a stream told them apart by *order*, and with no order
the channel has to be in the hash or they would be the same number. §6's matrix adds a row per modulation
on top of the three that exist (`scatterAngle`, `scatterDistance`, `rotation`). Raw values are hash input,
so they are stable: add cases, never renumber.

**The hash is splitmix64 addressed rather than stepped.** That generator is `state += golden;
avalanche(state)`, so its n-th output from a base state is `avalanche(base + n · golden)` — which is
exactly what a lattice point costs here. The statistical quality of a dab's jitter is therefore not merely
comparable to what the stream gave, it is the same generator's same output, indexed by *where the dab is*
instead of by how many dabs came before it.

### 4.1 The coordinate is arc length in **brush widths**, and that is a ruling

§2.17 already states λ in brush widths, and measuring the whole field in that unit buys the one invariance
canvas points do not have: **a uniform scale of a stroke changes nothing at all.** A dab sits at
`n · spacing / brushSize` widths, and a lasso resize, a canvas resize and a layer transform all scale
`spacing` and `brushSize` by one factor. MEASURED: `(k·size·fraction)/(k·size)` and `(size·fraction)/size`
are the *same* `Double` across every scale, size and fraction tried, so 60,000 accumulated dabs disagree
by exactly zero. In points, every scattering stroke an artist picked up with the lasso would re-roll, and
the Mode 2 cut preview — which walks canvas space while the render walks the layer's own — would sit on
different dabs from the thing it previews.

**The lattice quantum is 1/4096 of a brush width**, and both bounds on it are measured.

- *Fine enough that two dabs never share a cell.* The Spacing slider's range is `0.02...0.5` of a width and
  `stampSpacing`'s 1 pt floor only ever widens the gap, so the tightest walk the app can produce steps
  **82 quanta** at a time — four doublings of headroom below anything an artist can dial in.
- *Coarse enough that two routes to one arc length land in the same cell.* Arc length is accumulated one
  step per dab, so a dab that survives a spacing edit is reached by a different sum. MEASURED over every
  such coincidence inside a 5,000-width stroke (a 20,000 pt line drawn with a 4 pt brush) across eight
  spacings: the worst disagreement is **6.6e-8 widths, 2.7e-4 of one quantum**, and that is the extreme.

**λ is not a second arm.** A wavelength of zero quantises to a lattice step of *one quantum*, at which
every dab has its own cell, the interpolation fraction is zero, and the answer is that cell's hash — a
fresh draw per dab. So §2.17's two behaviours are one code path and cannot drift apart.

### 4.2 The two fields, and what carries them

**Two fields on the stroke, both per-stroke rather than per-sample**: a `seed` that is **inherited on split
rather than regenerated**, and the `arcOffset` of this piece from the original stroke's origin. Every
cutter here derives a piece by *copying* the stroke and replacing what the cut changed, so both travel by
default and losing one takes a deliberate act — the lasso split, the eraser's three modes, an
interpolation in-between and every `VectorCanvas.mapping` copy are all the same `var piece = stroke`.

**`arcOffset` is zero except where a piece re-anchors its own walk.** A `DabLattice` carrier replays the
parent's whole walk, so it already starts at the field's origin; the eraser's Modes 2 and 3 remove
geometry and cannot, so they record how far along the parent the survivor begins.
`VectorCanvas.detachedArcOffset` is the one function that answers it, shared by the cut and by its
preview.

**`DabLattice.seedID` is gone with it.** It carried the parent's id so the RNG could be re-seeded off it;
that is what "becomes a two-field copy" means. The lattice is now about dab *geometry* only — where a
piece's dabs land — and the stroke's own seed is about their randomness. Separating the two is what lets a
piece that *had* to re-anchor its walk keep its randomness anyway.

**`DiscardedDabTarget` is deleted**, along with `BrushStamper.DabRNG` and its non-deterministic
initialiser. A dab outside a piece's range is skipped outright and the walk's arc length advances over it,
because arc length is a property of the walk rather than of what came out of it.

**The seed is minted at pen-down, not at commit**, which is a strengthening the old engine could not have.
Live drawing used an unseeded generator on the reasoning that raster dabs are baked as they land and never
replayed — true of the raster tier, and beside the point on the vector one, where the scratch showed a
scattering stroke under the pen and the stored stroke re-rolled it at lift. The two now address the same
field; what is left between them is the refit's 0.25 pt of geometry, not the randomness.

**What is not preserved, correctly**: editing a brush's spacing changes which arc lengths carry a dab, so
different randoms land. Those are different dabs. What is preserved is that no *existing* dab's randomness
moves.

**Arc length is measured in rest space**, so this composes with KEYFRAMES §4.2's rest-space dab bake
rather than fighting it: a posed or keyframed stroke's randomness is frozen by construction, which is the
property the grain boil needed and never had.

**One consequence for documents written before this**: a stroke with no stored seed decodes to
`DabRandom.seed(for: id)`, which is the value its dabs were actually drawn with, so its ink does not move.
A *cut piece* saved by the old engine kept its parent's seed on its lattice, and that key is gone — such a
piece re-rolls once, on the first load. §2.14's expendable documents make that the right price for not
keeping a second definition of the seed alive.

---

## 5. What a point stores

### 5.1 The record

| channel | bytes | |
|---|---|---|
| x, y | 4 | unchanged — `Int16` quarter-pixel, offset from the run's origin |
| pressure | 1 | unchanged |
| Δt from the previous point | 1 | **new** — the only cost of §2.8's velocity, and it buys retiming later |
| tilt altitude | 1 | **new** — §2.7. 0…π/2 in a byte is 0.35° a step, far finer than a shading ramp resolves |
| tilt azimuth | 1 | **new** — §2.7. 1.4° a step over a full turn, ruled sufficient |

**Eight bytes a point against five — BUILT, and MEASURED at exactly that**: 8000 payload bytes for a
thousand-point run carrying every channel against 5000 for the same run carrying only pressure, and
12 with `preciseCoordinates`, which widens the coordinates the same way. On the wire, where base64 and
JSON escaping are what the file pays, MEASURED over a thousand samples: **10.785 B a sample against
6.743**, a ratio of **1.599** — the payload ratio almost exactly, because the run's two fixed costs are
~30 bytes against ~10,000. Against the MEASURED 0.9 MB a thousand strokes
([PERFORMANCE.md](PERFORMANCE.md) §11) that is ~1.3 MB, which is why §2.7 was reversed on seeing the number.

**And the common case is cheaper than eight**, at no cost in behaviour: a channel whose every value
quantises to the neutral's byte is **dropped at commit** (`StrokeSamples.compacted()`), because the funnel
answers the same value for an absent channel as for an all-neutral one. No decision, no per-brush capture
rule, no flag.

**MEASURED on the device rather than predicted**: a stroke drawn with a finger in the simulator, saved,
and its blob read back out of the project package, carries the channel-set byte **`0x04` — `deltaTime`
and nothing else, five bytes a point.** A finger reports π/2 and 0 for tilt *and exactly 1 for pressure*,
so all three drop and the common case comes out at the record's old width rather than at the six this
section first predicted. Its eight stored points carry Δt of 0, 33.5, 33.5, 37.0, 40.5, 40.5, 39.5 and
0.5 ms — 225 ms of gesture, with the first point's interval zero by definition and the last the lift.

**Δt is an *interval*, not a reading, and that is a ruling rather than a detail.** It is one half-millisecond
a step, saturating at 127.5 ms — the error that matters is relative, because Δt is a divisor, and it is 6%
of a raw 240 Hz gap and ~1% of the 40-50 ms gap the refit actually stores. Being an interval changes what
every derived sample does with it: `StrokePathFit` **absorbs** the intervals of the samples it drops into
the knot it keeps (or a refitted stroke's velocity would read as the digitiser's rate whatever the hand was
doing), and a cut boundary inserted part-way through a segment **takes its share and leaves the rest** to
the sample after it (or a cut piece would read as slower than the stroke ever was, through ink the eraser
never touched). Both are `SampleChannel.isCumulative`, one flag, no per-site special case.

**Azimuth is a byte, and that is settled rather than assumed.** It works out at 1.4° a step over a full
turn. The case against it was that azimuth drives a nib angle *directly* rather than through a ramp, so a
chisel turned slowly might show the steps as faceting; the owner ruled that *"1.4 degrees is more than
enough, the hypothetical chisel turning slowly is not a concern."* Two bytes would buy 0.0055° and is not
being spent.

**The refit (§3.3) does not change this record, and that is a decision rather than an omission.** The
stored thing stays a list of on-curve points; only their placement moved. §3.3 carries the three reasons
the cubic-control-point alternative was refused.

**The record is not fixed — it is a channel set.** §5.5.

### 5.2 Nothing else is stored

Not rotation, not scale, not dab positions, not jitter values, not alpha — §2.14. Three reasons, and the
middle one is the load-bearing one:

1. Each is a pure function of *(path, brush, seed)*.
2. Storing them freezes the brush into the stroke, so §2.10's apply-to-existing verb could not work.
3. They are per-*dab*, and dabs outnumber points several-fold. A 1000-point stroke at 10% spacing is
   ~5000 dabs; two floats each is 40 KB for one stroke.

### 5.3 The refit is a correctness requirement, not a saving

`StrokeSampleGate` admitted a sample once it had travelled **half the current dab spacing**. So *the
stored path's density was a function of the brush it was drawn with.* That is tolerable while brushes are
fixed presets. It is not tolerable once a brush editor exists: retune a wide-spaced brush to a tight
spacing and there is no longer enough path to walk, and the samples are gone.

**The stored path must be a fit of the drawn curve at a fixed geometric tolerance, independent of any
brush.** That is what §3.3 is, and the memory win is a side effect of it rather than its justification.

**BUILT.** `StrokePathFit`: a fixed 0.25 pt deviation tolerance, a 12 pt cap on the gap between two stored
points, and the gate's own pressure escape kept unchanged at 0.02 — the one threshold that never was a
function of the brush. MEASURED at 120 Hz over a 400 pt line and circles of radius 60 and 15, at 900 /
400 / 120 / 40 pt/s, hand tremor 0.4 pt:

| | raw | gate, 5 pt brush | gate, 20 pt brush | fit |
|---|---|---|---|---|
| line at 40 pt/s | 1201 | 603 | 419 | **204** |
| circle r=60 at 40 pt/s | 1131 | 561 | 393 | **189** |
| line at 120 pt/s | 401 | 401 | 361 | **73** |
| circle r=60 at 120 pt/s | 377 | 377 | 347 | **64** |
| circle r=15 at 120 pt/s | 95 | 95 | 87 | **23** |
| anything at 900 pt/s | 54 | 54 | 54 | 54 |

The saving is 2–5.5× against the gate and 3–5.9× against the input, and it **vanishes at 900 pt/s in every
row** — the pen already outruns both rules, which is the honest shape of this and was true of the gate too.

**The number that is not a saving is the one that matters**: the *fidelity* column is now a constant.
Every row's stored path sits within 0.250 pt of the drawing whatever brush was selected, where the gate's
was half a dab spacing and so 0.5 pt on a 5 pt brush and 3 pt on a 60 pt one.

### 5.4 The brush table — BUILT, §12 stage 6

`VectorStroke` stored a whole `Brush` by value. It now stores a `BrushRef`, four bytes, and §2.9's index.
The old figure was MEASURED against `Brush`'s synthesized `Codable` compact-encoded the way `ProjectStore`
writes it: **333 bytes for a stock preset and 386 for a custom-shaped one** carrying a `custom-<UUID>.png`
filename, against ~150-160 resident. What replaces it is MEASURED too — **`"brush":N`, 9 to 13 bytes on the
wire** including the key, and 4 resident. §6 makes `Brush` larger, so the gap grows rather than shrinks.

**There are two tables, and the split is the whole design.** `BrushPool` is the *process's*, addressed by
the brush's **value**: interning gives §2.9's deduplication for free and makes §2.10 fall out with no rule
to enforce, because an edited brush is a different value and therefore a different ref, so ink already
drawn cannot move. `BrushTable` is the *document's*, written to **`brushtable.json` in the package root
beside `brushes/`** — §13's first open item, settled there rather than in `manifest.json` for the reason
`CelManifest` already pulls per-cel vector data out of it: the manifest is decoded in full for every
gallery tile, and §2.10 makes the table the least bounded thing that could go back in.

**The sweep is the table's definition, not a pass over it, and that is what makes it unable to
half-apply.** A save collects the refs its own snapshot references — every cel's display list *and* every
derived cel's `InterpolationRecipe` local edits, which are reachable from no display list — and writes each
beside the brush it names. An entry nothing references is not deleted; it is never collected. **Nothing is
ever renumbered**, because the number a stroke holds is a pool ref rather than a position in the file, so
there is no stored numbering for a sweep to shift under a stroke that a later save has to keep in step.

**The save does walk every element, and BUGS.md's entry said the table was there to remove that walk.**
That was wrong, and it is worth writing down rather than quietly dropping: collecting the referenced refs
is one `UInt32` read per stroke over the snapshot the save already holds, against a save that PNG-encodes
and writes every cel — INFERRED from the shapes rather than measured, because it is not separable from the
save at the resolution `SaveProfile` reports. What the table actually removes is the *per-brush* work the
old shape would have needed: the walk answers "which files does this document need" with a set lookup
instead of decoding a `Brush` out of every stroke.

**A ref is meaningless without saying which table**, and the one crossing between the two is
`BrushPool.resolve(_:in:)`. A decode given a `BrushTable.Remap` in `userInfo` redeems the stored number
against the file and **throws** on one the table does not carry — a corrupt payload, not an old one
(§2.14), counted as a malformed element and reported. A decode given none takes the number as this
process's own, which is right for an undo snapshot or a defensive copy and would be silently wrong for a
file. `ProjectStore` therefore sets the key on **every** decoder it points at a package, even when the
table is empty; that is what makes the ambient path unreachable for anything read off disk.

**The defect the table was the honest fix for is fixed.** `ProjectStore`'s brush-texture copy walked the
palette while claiming to make a package self-contained. It now walks the **union** of the document's table
and the palette, from one function used by both the save and the load, because neither population subsumes
the other: a brush the ink is made of may be in no picker (§2.10 mints those in bulk), and a brush the
artist imported but has not drawn with is in no stroke's table and still has to travel or the picker comes
back pointing at a missing file.

### 5.5 The channel set, the funnel, and the neutral

§2.7 puts tilt in stage 4 alongside the record, so these are the shape of a feature being built rather than
room left for one. Three of them are what make *any* later channel additive; the fourth has been discharged.

**BUILT — §12 stage 4.** What follows is what shipped, not what was planned.

**A channel set in the run header, not a fixed record.** `PackedSampleRun` carries a `SampleChannelSet`
bitmask naming which per-point channels are present and derives `bytesPerSample` from it. A channel is one
case in `SampleChannel` and two arms in `StrokeSamples`' storage subscript — **no format version, no
migration, no decode default**, because a run written without one simply has those bits clear. The mask
costs one byte per *run*, written as the **first byte of the blob** rather than as a JSON key of its own:
that makes "one byte a run" literally true (a key costs six characters before its value), makes a run
self-describing, and takes the wire down to two keys always. It subsumes the `.quarterPixel` / `.float32`
mode flag as `preciseCoordinates`, bit 0 — a channel-width choice wearing a different hat, and now one
derivation of the record width rather than two hand-written arms. `VectorStroke.precise` is still off the
wire and still derived from the header.

**Struct-of-arrays in memory.** `StrokeSamples` holds parallel arrays — positions, pressures, and one per
optional channel. An absent channel is an empty array and costs nothing; adding one adds an array rather
than widening the stored record. It is also the shape the packer already wants.

**The sweep that made it worth having is the one over the sites that rebuilt a stroke by naming its
fields**, each of which would have dropped tilt on the day it arrived. There are none left: a positional
transform is `transformed(by:)`, a warp is `replacingPositions(_:angleRotation:)` — whose `angleRotation`
has no default, so a caller claiming "this map does not turn the ink" has to write it down — and a cut
piece is `replacingSamples`, which takes the *set* from the parent it was cut out of. `StrokeSamples`
conforms to `RandomAccessCollection` of `VectorSample`, so every polyline consumer in the engine reads a
stroke's own storage with no conversion and no allocation, through one `SampleRun` protocol that a bare
`[VectorSample]` also satisfies. `VectorSample` keeps a field per channel — it is the *view*, and being
lossless is what lets `StrokeGeometry`'s slicing, interpolating and bisecting carry every channel without
knowing any channel exists — and `VectorSample.lerp` walks the channel set rather than naming fields, so
one function serves a cut boundary, a densified point and a lasso crossing.

**`StrokeSamples(_:channels:)` has no default for `channels`**, and that is the guard rail: every site
that mints a run says out loud which channels it holds, so a new channel cannot be lost by a site that
predates it. `BrushStamper.Sample` — the stamper's own two-field copy of a sample — is deleted, and
`stampStroke` takes the stroke's storage directly.

**One evaluation funnel, with a defined neutral.** Every sensor resolves through
`StrokeSensors.value(of: BrushInput, at: DabSite)`, so a new sensor is one case in one switch — **provided
that funnel answers a defined neutral when the stroke carries no data for the channel asked for.** The
neutral is not a legacy concern that tilt's arrival retires: a **finger** reports no tilt and never will,
and §2.10's apply-to-existing verb can point any stroke at a brush reading anything. Neutral is the Pencil
held upright — full altitude, azimuth zero, no modulation effect.

**And the neutral is *derived*, not restated.** Three of the four channel-backed inputs reach it by
reading the channel — `StrokeSamples.value(_:at:)` answers `SampleChannel.neutral` for a run that does
not carry one — and then running the same normalisation a stored reading gets, so an upright Pencil and
no Pencil at all come out of one arithmetic. `BrushInput.neutral` is what the tests compare against,
not what the funnel consults. The first draft short-circuited on `BrushInput.neutral` instead, and a
mutation test caught what that costs: with two constants for one fact, changing the channel's neutral
left the render unaffected, and the pin below would have been green against a broken funnel. `velocity`
is the one exception and has to be, because it reads the channel's **presence** — a Δt of zero is not a
speed.

**This section spelled it `atArcLength:` and one coordinate turned out not to be enough.** The per-point
channels are attached to *points* and interpolate by parameter, while §4.1 rules that the random field is
addressed by arc length in brush widths. The walk produces both in the same loop, so `DabSite` carries
both; inverting one into the other would cost an arc-length table and would have to be bit-exact to keep
`RasterVectorParityLogicTests` at zero tolerance. Two coordinates of one march, not two arms.

**The pin is a rendering one, and it is real rather than definitional**: a run with no pressure channel —
which `compacted()` produces from any stroke drawn at a constant full press, and `StrokeSamples(points:)`
from the intersection eraser's probe — drawn with `BrushDynamics(sizePressure: 1, opacityPressure: 1)`
produces byte-identical pixels to the same brush at `.fixed`. A funnel answering `0` makes the first a
tapered hairline against the second's full-width line. Beside it sits the claim that makes the neutral a
fact about the world rather than a definition: **a stroke that stores what `StrokeInput` reports for a
finger resolves exactly as one that stores nothing at all**, through the packer as well as in memory.

**The capture was already there, and that is the whole return on this section.** `StrokeInput` takes
`altitude` and `azimuth` from the hardware and already answers `π/2` and `0` for a non-Pencil touch — the
neutral above, written before anything consumed it. It was kept as a named exception to the
delete-what-is-unused rule on the grounds that a hardware reading cannot be reconstructed from a decision
later. Stage 4 connects it; nothing has to be re-derived, and no stroke drawn before it is missing anything
a decision could have preserved.

---

## 6. The brush model — a modulation matrix — BUILT, §12 stage 7

Every parameter is `base value + [modulation]`, where a modulation is **(input, an ordered list of
modules, amount)** — §2.28. That is the brief's *"every parameter should be able to be sensor driven"*,
and it is the CSP model.

**The list is §2.28 and it replaced a fixed `curve` and `second` field on 2026-09-05.** A chain is
`amount · chain(input)` where the sensor's reading passes through the modules **in the order the artist
put them**: `.curveRamp` shapes it, `.scale` multiplies it by another sensor's reading **shaped by that
sensor's own curve** (§2.29). The row that
came before — `amount · curve(input) · reading(second)` — is exactly the chain
`[.curveRamp, .scale]`, so nothing an existing brush said became unsayable and the presets' pixels did
not move; what became sayable is the other order.

**A scale attenuates.** Its reading is clamped to `0…1` and `amount` is still the only signed,
unclamped term (§2.22, unchanged by the move). Two chains on one output *add*, so `spacing ← random`
beside `spacing ← pressure` gives a pressure shift **plus** a fixed-amplitude wobble, where a scale
*multiplies* and the wobble's amplitude is what pressure moves. A `.random` in any position has its
channel derived from that position (§6.2).

**What shipped**: `BrushOutput`, `BrushModulation`, `BrushModule`, `BrushModulations` and
`ResponseCurve` in `Engine/BrushModulation.swift` and `Engine/ResponseCurve.swift`, and
`BrushRandomiser` in `Engine/DabRandom.swift`; `Brush` regrouped into `dab`, `stroke` and
`modulations`; `BrushDynamics` **deleted in full**. `Brush.dabValues(_:)` is the evaluator and
`BrushStamper.stampDab` turns its answer into a stamp. Every sentence below that is not marked
otherwise describes what is there.

**Inputs** (§2.8): `pressure` · `tiltAngle` · `tiltDirection` · `direction` · `taper` (distance along the
stroke, from either end) · `velocity` · `random`.

`tiltAngle` is how far the Pencil is leaned over and `tiltDirection` which way it is leaned, in canvas
space (§2.7). Both answer §5.5's neutral — upright, pointing nowhere — for a finger, and for any stroke
whose run does not carry the channel.

**Every `random` modulation carries a wavelength λ, expressed in brush widths so a brush looks the same at
any size** — §2.17. Its value interpolates between hashed lattice points λ of arc length apart, which is
still exactly §4's `hash(strokeSeed, arcLength)`; λ = 0 is a fresh draw per dab.

**Outputs**: `size` · `opacity` · `flow` · `angle` · ~~`roundness`~~ · `spacing` · `scatter` ·
`density` · `hue` / `saturation` / `brightness` shift · `hardness` (procedural tips only).

**`roundness` is the one output stage 7 did not ship, and it is a decision rather than an omission —
now scheduled, for §12 stage 9.** The owner asked for it by another name (§2.24's *"vertical/horizontal
stretch"*) and asked whether it is a real feature elsewhere. It is: Photoshop's Shape Dynamics has
**Roundness Jitter** whose *default* control is pen pressure, and Clip Studio has a **Thickness** slider
with a **Horizontal/Vertical** toggle driven from its Dynamics popup — which is the owner's phrasing
almost exactly. **It lands with the brush set rather than before it**, and the reason is authoring
rather than taste: whether a chisel is a rectangular *sprite* or a squashed *round* tip changes how
§8.4's generator draws it, so settling it after the tips exist means re-drawing them. A
non-circular dab contradicts §3.5's ruling that *"a tip's mask is square, by ruling. One scalar for the
dab's size keeps `DabPose` at one multiply, `BakedDab` at one number and the dirty-rect bound at one
`abs`."* Shipping it means a second extent through both `DabTarget` primitives, `BakedDab`,
`DabPose.applied(to:)`, `dabBounds`, `StrokeScratch`'s window and the dirty rect every compositor
accumulates — i.e. reversing a stage-3 ruling and touching the zero-tolerance parity net and
KEYFRAMES' pose path in the same change. Nothing before §12 stage 9's **chisel** and **flat** brushes
needs it, and those are what should carry it: it belongs with the tips that are anisotropic, not with
the matrix. Declaring the output and leaving the renderer not reading it would have been worse than its
absence — this document's own §12 stage 5 note and CLAUDE.md's *"a feature is not finished because its
model is correct"* are both about exactly that.

**The bases are grouped, `size` and `opacity` are not, and that pair is not an exception.** `Brush.size`
and `Brush.opacity` are the *stroke's* diameter and opacity: `BrushStamper` takes both as arguments
because the toolbar drives them and a lasso resize scales the first, and what the preset holds is the
value copied into `CanvasManager.brushSize` when it is picked. `BrushDabSettings.size` and `.opacity`
are the matrix's own outputs — the fractions those are multiplied by — and live with the rest.

`density` (§2.18) is the probability that a dab is stamped at all, and it is the one output whose λ belongs
to the **row** rather than to a modulation entry, because what has to be coherent is the draw.

Angle has three contributions that sum: a base angle, direction-follow as a 0–100% amount, and jitter.
Measured in **turns**, so `direction` — which the funnel answers as a fraction of a turn — reaches it
with no conversion. The jitter is a *draw* rather than a value, so `BrushDabValues` carries the first
two and `stampDab` adds the third, which is the same line that keeps the scatter offset and §2.18's
dropout out of the evaluator.

**Direction-follow *is* also expressible as a row** — `angle ← direction` at amount 1, since the output
is in turns and the funnel answers direction in turns — and that would ordinarily be §10's
two-ways-to-compute trap. It is not, because the two forms are **pinned equal**:
`BrushModulationLogicTests` renders a turning stroke both ways and asserts the dabs match, and asserts
that neither matches a brush with no follow at all. A redundancy that is asserted is a tested identity;
the one §10 warns about is the unasserted kind. The named field survives because §6 names it and
because an artist sets a follow as a percentage rather than by drawing a curve.

**Jitter is not a row wearing a different hat, and that is worth being exact about.** It draws from
`DabRandom.Channel.rotation` — one of the four intrinsic draws, not a matrix channel — and it is
*signed*, `±j/2` of a turn about the base rather than `0…j` above it. An `angle ← random` row is a
different value from a different cell, so the two coexist rather than duplicate; a brush can carry both
and they do not cancel.

`BrushShape` + `customTextureFileName` — a case and a parallel optional field that could disagree —
are **one payload-carrying enum since §12 stage 5**, so the illegal states are not representable and
`stampDab`'s switch is exhaustive with no `default:`:

```swift
enum BrushTip: Codable, Hashable {
    case round                    // procedural, hardness gradient
    case stamp(BrushTextureRef)   // a committed tip, or the artist's own PNG
}
```

**Five shapes became two cases and no ink moved.** `.softRound`, `.hardRound`, `.pen` and `.pencil` all
called `stampCircle` and differed only in the hardness, spacing and pressure response their presets
carried — `dab.hardness`, `dab.spacing` and two rows of the matrix since stage 7, and every one of them
still a `Brush` field. `.square` and `.custom` are both `stampImage` of a
`BrushTextureRef`, so the difference between a shipped tip and the artist's own is a case of *that* type
rather than a case of the brush's shape — which is what makes an imported PNG reach the renderer by the
route the committed square already took.

**Two readers of the old pair were not about the tip at all, and both had to be re-homed rather than
translated.** `BrushShape.displayName` and `StrokeSettingsPanel.icon(for:)` were UI text with a case per
*preset*: the icon gave the pencil a pencil and the pen a nib for four brushes that were one dab. The
icon is derived from the tip now — a disc, filled or hollow by the falloff the artist will see, or the
picture itself — and the preset's **name**, already rendered beneath it, is what tells Pencil from Pen;
`displayName` is deleted. `CanvasManager.selectBrush` asked `shape == .pencil` to retarget `selectedTool`,
which no tip can answer, so it asks `BrushLibrary.isPencilPreset` instead: **the affinity is to the
preset, and that is a fact the library owns rather than a field on `Brush`** — a field would be the pair
just removed wearing a tool's name. That in turn needed `BrushLibrary`'s five presets to carry written-down
ids rather than `UUID()` in a `static let`, which is one value per *process*: a preset saved into a
manifest came back matching no running copy of itself, so the picker's highlight found nothing after a
reload. §12 stage 9 replaces the presets and the group tree answers both questions then.

**What a tip file is, is `BrushTipImport`'s rule and nothing else's.** Everything below
`BrushTextureRef` reads a mask's **alpha** as the dab's coverage, so an import is normalised on the way in
rather than interpreted on the way out: letterboxed into a square (§3.5's ruling — a dab's size is one
scalar everywhere below `stampImage`), 256² at a 2 px transparent border like the committed square, and —
the one inference — **an opaque picture is read as `1 - luminance` rather than as alpha**. Without that
the feature is unusable for the format artists' stamps arrive in: a scan, a `.abr` brush's pixels and
anything picked out of Photos carry no alpha channel at all, so read as alpha every one of them is a
filled square. The test is on the drawn pixels inside the letterbox rather than on the file's metadata, so
a PNG that is already a mask keeps its alpha and cannot be inverted. A picture that normalises to nothing
at all is refused by name (`Failure.blankMask`) rather than becoming a brush that paints air, which is the
failure a renderer bug looks exactly like.

`Brush`'s flat scalars group into sub-structs the way `dynamics` and `blendMode` already did, each with a
`static let default` and defaulted decode. `Brush`'s `Codable` was compiler-synthesized, so every new
flat key was a decode-compatibility question; a nested field with a default is not. **Three groups
shipped**: `dab` (`BrushDabSettings` — every output's base, plus `densityWavelength` and the angle's
three contributions), `stroke` (`BrushStrokeSettings` — `stabilization` and `blendMode`, the two
settings that are not dab outputs and could not be), and `modulations` (`BrushModulations` — the rows).

### 6.1 The curve is `AnimationCurve`, over a different axis

§7 asks that reusing TODO (38)'s bezier control *"keeps this from being a second curve
implementation"*, and `ResponseCurve` is that taken literally: it **stores an `AnimationCurve`** and
does one thing to it — maps the sensor's `0…1` onto that curve's integer-frame axis. No bezier
arithmetic, no second tangent grammar, no second answer to what `.autoClamped` means. `ResponseCurve
.curve` is the binding stage 10's editor drives.

**The scale is 1024 and that is load-bearing, not tidy.** `value(at:)` multiplies by it and
`AnimationCurve`'s linear segment divides by it, so the round trip must be the identity or a straight
ramp is not straight. MEASURED over 200,000 random inputs: **0** disagreements at 1024 and **6,909** at
1000. One disagreement is one ulp of dab diameter, which is exactly what the preset pin and
`RasterVectorParityLogicTests` are unwilling to spend.

`AnimationCurve` gained `Hashable` (and `Key`, `Handle`, `Interpolation`, `TangentMode` with it),
because `Brush` is `Hashable` and `BrushPool` addresses an entry by its whole value.

**The identity is the *empty* curve**, which is what almost every row carries and what all five presets
use — a `guard`, not a binary search and a Newton solve per dab per row. It is also why this cannot
simply forward to `AnimationCurve.evaluate`, which answers **0** for an empty curve: correct for a
channel, and here it would silently delete the row.

### 6.2 A `random` row's channel is derived, never authored

§4 rules that a channel has to be in the hash or two draws at one arc length would be the same number,
and §8.4's rough nib is *built* from several `random` rows at different λ. So `DabRandom.Channel` is a
struct now rather than an enum — the three intrinsic draws keep their raw values 1–3, §2.18's dropout
takes 4, and `DabRandom.Channel.modulation(_:row:)` mints one per *(output, position)* from 16 up.

**Every position in a chain is minted the same way, one plane up each.** `modulation(_:row:slot:)`
offsets by `1 << 20` per position — past the whole matrix's span, so the planes cannot meet at any row
count — and `BrushModulations` rewrites *every* position's channel on construction and on decode, not
just the input's. **Position 0 is the input and position *m + 1* is module *m***, which is why §2.22's
second slot and a chain's first randomiser are the same channel and no randomised brush re-rolled when
the chain replaced the row. Without the rewrite a chain randomised twice could square a single draw
rather than multiply two, which is the trap §2.22 named and §2.28 inherits at every position.

**§2.28's octaves are a third digit.** `DabRandom.Channel.octave(_:)` offsets by `1 << 40`, so an
address is (matrix span, position, octave) in base 2²⁰ and is unique as long as each is under 2²⁰ —
which no brush approaches. **Octave 0 is the channel unchanged**, so a one-octave randomiser draws
exactly what the single draw it replaces drew, and the reordering cost is the one already stated: moving
a randomiser along a chain moves the plane it draws from, so both it and whatever it passed re-roll.

**Derived rather than stored** is what makes "no two rows share a channel" a fact instead of an
invariant somebody maintains, and `BrushInput`'s codec leaves the channel off the wire entirely so a
stale one cannot contradict the matrix — the same defect as the `BrushShape` + `customTextureFileName`
pair stage 5 deleted. The stated cost: inserting a row *before* another on the same output re-rolls
that one's draws, which is the same class of change as editing a brush's spacing (§4: *"those are
different dabs"*) and is confined to one output's rows.

### 6.3 The consumers that have a pressure and no walk

Three places resolve a brush with no stroke around them — `StrokeGeometry.stampRadius` (the eraser's
capsule chain), `VectorEraser.supportsCleanCut`, and `VectorCanvas.strokePolyline` (the `.preview`
tier, which already approximates the pressure ramp by its mean). `Brush.dabValues(atPressure:)` is what
they call: the matrix with every other sensor at its §5.5 neutral.

**That answer is only *true* for a brush whose rows are all pressure-driven**, so the eraser's two
gates ask. `supportsSplitting` and `supportsCleanCut` now refuse a brush with any non-pressure row, and
refuse any `density < 1` outright — a dropout brush stamps *gaps*, so "the eraser covered this
cross-section" is a claim about paper. Both fall back to the exact alpha punch, which is right whatever
the dabs did. That is §11's *"gate on brush properties, not on a list of known brushes"* reached
through §6's door.

---

## 7. The editor

A Procreate-shaped panel: parameter groups, each row a base slider, each row able to gain a modulation —
pick an input, draw a curve, set an amount. **§2.20 rules where it sits and how it is reached**, and
rules that it is the *only* place a brush parameter is changed. Its shape is otherwise delegated:
owner, *"You decide how this menu is going to look like, but it should ideally contain a modularity or
a lot of parameters."* Procreate's Brush Studio is the named reference.

### 7.0 Four worked examples, which are the acceptance test for the design

The owner gave four. Three are already expressible and the fourth is not, and knowing which is which is
what stops the editor being designed around a mechanism that does not exist.

1. **Edge softness / antialiasing as an option.** One field on `BrushDabSettings`, built here.
   [BUGS.md](BUGS.md) carries the measurement, the mechanism, and why hardness 1.00 is a legitimate
   deterministic aliased look while 0.93–0.99 wanders with the size slider.
2. **Spacing that grows with the brush.** **Already the behaviour, with nothing to build**:
   `BrushDabSettings.spacing` is a *fraction of the stroke's diameter* (§6), so a brush at size 4 and
   the same brush at size 80 lay dabs at the same relative gaps. The editor's job is to say so in its
   units rather than to add a control.
3. **A line that breaks into segments at low pressure, and the same behaviour driven by tilt.**
   **Built, and not by moving spacing** — §2.18's `density` with §2.17's λ and §2.19's threshold curve.
   Widening spacing stretches the whole line uniformly and gives a dotted one; dropping dabs leaves the
   survivors on the same lattice, which is what reads as broken ink. Tilt-driven is `density ←
   tiltAngle`: one row, no new mechanism. **The curve is already per row**, so *"the pressure curve to
   trigger it may be adjustable"* is something the editor exposes rather than something to add.
4. **Randomness whose *amount* is driven by a sensor** — *"pressure maps to both brush thickness and
   spacing, with spacing using the randomizer engine"*, and *"pressure to taper"*. **Not expressible,
   and §13 holds the decision open.** §6 is `base + Σ amount · curve(input)`, a **sum**: two rows give
   a pressure-driven shift *plus* a fixed-amplitude wobble, never a wobble whose amplitude grows as
   pressure falls. `density` escapes this by construction — §2.18's *"the coherence lives in the draw,
   not in the value compared against"* means moving the compared-against value **is** moving the
   amplitude — which is exactly why (3) works today and (4) does not. *"Pressure to taper"* is the same
   shape from the other end: `taper` is an *input* (distance along the stroke), so "taper harder when
   pressed lightly" wants pressure to scale taper's effect rather than add to it.

**The curve editor already exists.** TODO (38) built bezier tangent handles with a tap grammar for the
timeline's graph band; a pressure curve is the same control over a different domain, and reusing it is
what keeps this from being a second curve implementation.

**§12 stage 7 built the model half of that and left the editor exactly one job.** `ResponseCurve` holds
an `AnimationCurve` (§6.1) — the same type `TimelineGraphBand` already draws and drags — so the editor
does **not** need a new curve type, new handle modes, new tangent maths or a new codec. What it has to
do:

1. **Bind to `modulation.curve.curve`**, an `AnimationCurve`, and re-plot the band's axes: x is the
   sensor's `0…1` mapped through `ResponseCurve.scale` (0…1024 in the curve's own units), y is the
   output's own range. `TimelineGraphBand`'s x axis is frames off `TimelineLayoutKey` and its y axis
   auto-ranges to the channel's live key values, so both are substitutions rather than rewrites — and
   the auto-range is the one to be careful with, because it is the defect the owner found on the device
   in TODO (38) (a node that wrote the right number and did not move, because with two keys both are
   extremes). A response curve's y axis should be **fixed**, not auto-ranged.
2. **Offer the row grammar**: pick an output, pick an input, set an amount, optionally draw a curve.
   `BrushModulations.setAmount(_:for:from:)` is there for the amount; adding and removing rows wants
   one more accessor of the same shape.
3. **Show λ on a `random` row and on the `density` row**, which are two different places by ruling
   (§2.18) and should not look like one control.
4. **Not offer the channel.** It is derived from where the row sits (§6.2) and is off the wire.

Parameters with no UI at all today — `scatter`, the angle's three contributions, `hardness`, `density`
and its λ, `blendMode` and the three HSB shifts — get one here.
Edits currently apply to a live copy and are lost when the preset changes; §2.9's table plus §2.10's
minting is what makes an edit persist.

**All four are built, and the first of them is wrong as written — §7.2 carries the correction.** The y
axis is the *shaped reading's* fixed `0…1`, not the output's own range: a `ResponseCurve` answers before
the row's `amount` scales it, so labelling the axis with the output's range would be a picture of a
different number. The fixed half of that instruction is exactly right and is what
`ResponseCurveEditing.axis` is.

### 7.1 The brushes menu — the shape, taken from the owner's own reference

**BUILT 2026-09-04** — `StrokeSettingsPanel` *is* this menu now, §2.20's second tap opens the editor,
and the six sliders the panel used to show inline moved into it. Four notes from
building it are folded into the bullets below and marked; everything else is as it was designed.

The owner supplied Procreate's brush menu as the reference and §2.20 rules the navigation. What the
reference actually shows, and which of it is a decision rather than decoration:

- **A card anchored under the brush icon**, with a notch pointing at it. It is the same dropdown
  geometry `BrushSettingsPanel` already uses; what changes is what is inside it.
- **Two columns.** The left is the **group list**, scrolling vertically, one row per group with a small
  glyph and a name, the open group highlighted. The right is **the brushes in that group**, one row
  each. Both scroll independently, which is what lets thirty groups and thirty brushes coexist in a
  panel the width of a dropdown.
- **A brush's row is its name over a rendered stroke of itself.** That preview is the row's whole point
  — a name tells an artist nothing about a brush and a swatch of its tip tells them little more. It is
  a real `BrushStamper` walk over a fixed S-curve with a pressure ramp, which makes it the same
  contact-sheet render §12 stage 9 chooses the set with, at row size. **Cache it by `BrushRef`**: it is
  the brush's value-addressed identity, so an edited brush re-renders and an unedited one never does.
  **BUILT, keyed one step earlier — on the `Brush` value itself.** A `BrushRef` *is* `BrushPool`'s index
  for a brush value, so the two are the same cache; the difference is that minting a ref costs an entry
  in an **append-only, process-wide** pool that never releases anything, and a preview is rendered for
  a brush the artist is merely *looking at*. Stage 10's editor will re-render on every tick of a slider
  drag, and interning each of those would grow the pool by hundreds of brushes nobody drew with.
  `Brush` is `Hashable` over its whole value — the same hash the pool addresses by — so `BrushPreviewKey`
  keeps the identity and drops the pool entry.
  **Two build notes.** The preview stroke's own width is the brush's `size` *clamped into the row*, not
  taken literally: at row size the Pen's 4 pt is a hairline and a 200 pt import is one dab covering the
  row, and a constant would be honest about neither. And the rendered image must **not** be
  `.accessibilityHidden(true)` — MEASURED, that made every brush row report no hit point at all while
  the group rows beside them were fine, because a row's centre lands on the image. It is a VoiceOver
  hole as much as an XCUITest one.
- **The selected brush's row is highlighted**, and a second tap on *that* row opens the editor. So the
  library's own selection state is what makes §2.20's second tap unambiguous — the gesture is "tap the
  thing that is already chosen", one level down from the tool icon's own version of it.
- **The `+` offers two things, and only one of them existed before.** Owner: *"the create brush right
  now makes you import a brush, but this library feature opens up the possibility of just taking you
  straight to the edit menu of a default brush, and you being able to fully customize it, so new brush
  should be two options: create manually, and import brush."* **Create manually** mints a brush from
  `BrushDabSettings.default` — every output at §6's neutral, a round tip, no rows — adds it to the open
  group, and opens §7.2's editor on it. **Import brush** is §2.21's adapter. The first is the one the
  library makes possible: before there was a library there was nowhere for a made-up brush to live, so
  importing was the only way to get a new one and the `+` could only mean that.

- **The set name sits top-left with a chevron**, the **`+` top-right**. §8.1 already rules that the
  shipped collection and the artist's own are two different things; the chevron is where that shows
  up, and the `+` is §2.21's importer. **BUILT**: the chevron opens the *open group's* own menu —
  Rename, Move Up, Move Down, Delete — which is where §8.2's ordering and rename became reachable, and
  the `+` offers Import Custom Brush and New Group. The importer's identifier is unchanged
  (`brushPanel.importCustomBrush`); what moved is that it is no longer a row under six sliders, which
  is the below-the-fold placement the owner reported having to scroll to find.
- **Not copied**: Procreate's per-brush cloud-download glyph. Every brush here is local.
- **BUILT, and the presentation is a deviation worth recording: the editor is a layer of
  `DrawingView`'s own tree, not a sheet.** It was a push *inside* this panel for one day and is a full
  screen since §2.24; the constraint is the same either way. The Size slider raises a **real-size stamp
  preview** that `DrawingView` draws in its own `overlayPreferenceValue`, positioned against the
  slider's frame in the drawing view's coordinate space (`SizePreviewRequest`, `SizePreviewWindow`). A
  sheet or a `.fullScreenCover` presents *above* that overlay, so holding the Size slider inside one
  would raise a window nobody can see — the control would look inert. A layer keeps one view tree, one
  coordinate space, one preference chain, and `activePanel` on `.brush`, which is also what
  `CanvasTouchOwner` and the draw-to-dismiss path already read. §7.2 records where in the tree that
  layer has to sit.
- **BUILT: the marker for "the menu is on screen" is on the group column's `ScrollView`, not on the
  enclosing `VStack`.** An `accessibilityIdentifier` on a SwiftUI container is *inherited by its
  descendants* rather than making an element of its own — it produced no queryable node at all, and it
  silently overwrote both `Menu`s' identifiers, so the `+` and the chevron were unreachable while
  looking perfectly correct in the source.

### 7.2 The editor — BUILT, §12 stage 10

**BUILT 2026-09-05.** `Views/BrushEditorScreen.swift` is the editor, `Views/ResponseCurveEditorView.swift`
the curve ramp's control, `Views/BrushScratchPadView.swift` the pad, and `Models/BrushEditorModel.swift`
everything a `View` cannot be asked about — the catalog, `BrushModuleKind`, `BrushChainLimit` and
`ResponseCurveEditing`. `BrushEditorView`, the six-slider shell of the day before, is **deleted**.

**And the chain became real the same day.** The screen first shipped drawing a *fixed* curve-then-gain
shape with sentences explaining why the order could not change; the owner read those sentences and asked
for the modular approach, which is §2.28. What is there now is **add / remove / reorder** over
`BrushModulation.modules` — `BrushModulationChain`, the type that mapped a row onto a chain, is
**deleted**, because the storage *is* the chain and a mapping layer is what hid the limit in the first
place. Reordering is two arrow buttons rather than a drag: the module list sits inside a `ScrollView`
inside a column that also scrolls, a long-press-to-reorder there fights both, and two taps are reachable
from the accessibility tree where a drag inside two scroll views is not.

**It covers the screen** (§2.24) and it is a layer of `DrawingView`'s own tree rather than a
`.fullScreenCover`. The reason the shell was a push holds for the screen: the Size slider raises a
real-size stamp preview drawn by an `overlayPreferenceValue` applied on `DrawingView`'s outer `HStack`,
and a modal presentation is a separate window *above* that overlay, so the preview would be drawn
behind it and the control would look inert. An `.overlay` on that same `HStack` keeps one preference
chain and one coordinate space — and it has to be the `HStack`'s rather than the canvas `ZStack`'s,
because the 64-point side toolbar is the stack's *first child* and a layer inside the second one leaves
it showing. MEASURED both ways on the simulator. `ToolsAndSelectionUITests`'
`testPressingTheBrushSizeSliderRaisesTheRealSizeStampPreview` drives this screen's Size slider and is
unchanged, which is the pin that the window still comes up.

**It needs no entry in `CanvasPresentation`, and being a layer is the reason.**
[MENU_PRESENTATION_CENSUS.md](MENU_PRESENTATION_CENSUS.md)'s registry exists for *system*
presentations, whose teardown can interrupt a stroke drawn underneath them. This one covers the canvas
completely and opaquely, so no touch reaches a stroke while it is up and there is nothing for
`dismissPresentationsOverLiveCanvas()` to close. `activePanel` is left on `.brush` throughout, so
`CanvasTouchOwner` is fed the value it always was.

Three columns, and the middle one is §2.24's own shape rather than a category list:

- **Left — what the brush *is*.** A live `BrushPreviewRow` of the brush's own stroke at 196×56, and a
  sentence naming the tip. Cached by the brush's whole value, so a slider moved in the middle column
  re-renders it and an untouched brush never re-renders.
- **Middle — every output, grouped, each expanding in place** into its base slider, its input, and the
  modules on that input. This is §2.24 read literally: *"a dropdown list of all the outputs … Clicking
  on one of these outputs will expand it down into the controller."* The groups are **Shape** (size,
  hardness, angle), **Ink** (flow, blend mode, stabilization), **Placement** (spacing, scatter,
  density), **Colour** (the three HSB shifts). `BrushEditorCatalog` owns the list and
  `BrushEditorLogicTests` pins that **every** `BrushOutput` case reaches it, so a new output with a
  renderer and no control is a red test rather than a discovery.
- **Right — the pad, and the artist's own two numbers.** Size and opacity live here (§2.20 — the side
  toolbar keeps them and gains nothing) beside the `BrushScratchPadView` they are being tried on. They
  are on this side rather than the left column because `SizePreviewSide.leading` puts the real-size
  window past the slider's leading edge, and from the leftmost column that clamps flush to the screen
  edge and lands on the side toolbar.

**Every parameter §7 listed as having no UI now has one** — `scatter`, the angle's three contributions,
`hardness`, `density` and its λ, `blendMode` and the three HSB shifts. §2.18's dropout λ is on the
`density` output itself and a `random` row's λ is on the row, which is §7's third point: two different
places by ruling, drawn as two different controls.

**Three of this section's own instructions did not survive contact.**

- **The pad is not a `StrokeCanvasView`, and could not be.** That view holds a `weak var canvasManager`,
  resolves a `layerID` and a cel through it, records undo through `CanvasManager.recordUndo` and writes
  into the document's `RasterLayerTexture`; with a nil manager it swallows every touch and draws
  nothing, and with a real one it puts the artist's doodles into their drawing. What actually had to be
  shared is the **stamper**, and it is: every dab goes through `BrushStamper.stampStroke` over a
  `CGContextDabTarget`, which is what `BrushPreview.render` already does for a menu row.
- **§7's first numbered point asks for the wrong y axis.** It says *"y is the output's own range"*. A
  `ResponseCurve` does not answer in the output's range — it shapes the sensor's reading, and the row's
  **amount** is what scales the result to the output afterwards. A `size` curve whose key sits at the
  top does not mean size 2, it means *"this row contributes its whole amount here"*. The axis is a
  fixed `0…1`, which is both honest and the fixed axis §7's own next sentence asks for.
- **The curve control could be neither of the two that exist, and that is a fact about both of them.**
  `TimelineGraphBand` is the right *model* — it is `AnimationCurve`, which is what `ResponseCurve`
  stores — and its drawing lives in `Views/TimelineTrackView.swift` as a `UIView.draw(_:)` inside the
  timeline's scroll view, with a `Content` that needs a layer index, an effect, a track table and a
  descriptor offset. `CurveEditor` (`Views/EffectSection.swift`) is the right *shape* — a square over a
  normalised `0…1` with the tap grammar — and the wrong model, editing `[CurvePoint]` through
  `MonotoneCubic`. §7's *"reusing it is what keeps this from being a second curve implementation"* is
  satisfied where it matters and by construction: one curve **type**, one `evaluate`, one tangent
  grammar, one codec; `ResponseCurveEditing.y`/`.value` *call* `TimelineGraphBand`'s so the two surfaces
  cannot drift; and `hitRadius`, `tapSlop`, `isTap`, `lineWidth` and `keyRadius` are that type's
  constants, which it took from `CurveEditor` in turn. Only the `Path`s are new.

**A third defect was found by driving §2.28's module list, and it is this file's own trap for the
fourth time.** The module card's `VStack` carried an `accessibilityIdentifier`, so **every control
inside a module inherited it** — the module's own label and its curve graph both vanished from the
accessibility tree while the card was plainly on screen and worked perfectly by hand. CLAUDE.md records
this, `StrokeSettingsPanel` was bitten by it, the screen's root `Rectangle` exists because it was bitten
by it, and it happened again one file down. The card carries no identifier now; its label does.

**Two defects were found by driving it, and neither could have been found by a model assertion.**

- **The screen's `accessibilityIdentifier` was on its root `VStack`**, so it was inherited by every
  descendant and `brushPanel.sizeSlider` existed nowhere — while the editor was plainly on screen and
  worked perfectly when driven by hand, because a hand uses coordinates. It is on a `Rectangle` now,
  which is `CurveEditor.curveGraph`'s spelling. CLAUDE.md and §7.1 both already record this trap; this
  is its third appearance.
- **An edit survived the editor and did not survive a relaunch.** `CanvasManager.selectedBrush` is
  initialised from the *literal* `BrushLibrary.softRound`, so after a relaunch the editor showed the
  shipped preset while the menu row beside it drew the edited stroke — the library file had the edit
  the whole time. `CanvasManager.adoptLibrarySelections`, called from `DrawingView.onAppear`, is the
  fix, and it re-baselines size and opacity **only when the value actually moved** so a fresh library
  cannot change the eraser's default width.

  **Four behaviours the pad still owes, and they are the owner's** — asked for after the brief that
  built it, so their absence is scheduling rather than refusal. It should **open showing a sample stroke
  with a pressure taper**, so the pad is never blank and a brush's character is visible before the
  artist touches it; be **zoomed in by default**, because the details that distinguish two brushes are
  granular; carry a **toggle to real size**, because zoom lies about what a brush looks like in use; and
  it already **clears**. The default stroke must be the same fixed S-curve `BrushPreview` walks for
  §7.1's rows — one sample stroke in the codebase, not two, or a brush's row and its pad will disagree
  about what it looks like.

**One thing in the reference is a trap worth naming.** Procreate's Apple Pencil tab organises by
*sensor* — "Pressure" heading, then Size / Opacity / Flow / Bleed underneath — while its other tabs
organise by *parameter*. Our model is a flat list of *(output, input, curve, amount, second)* rows, so
either presentation is a view over the same data and **both must not be built**, or an edit made in one
has to be found in the other. The parameter-first form is what shipped: it matches the model, it scales
to seven sensors, and a sensor-first form would need a row's absence to be renderable in six places at
once.

**And the brushes menu is taller** — 640 points against 420, for the brush and the eraser only
(`DrawingView.panelMaxHeight`). The owner asked for it and allowed it to be dropped if costly; what it
is *not* is "fill the space", because the card sits in a `ZStack` with a 60-point top inset and the
timeline claims the bottom of the same stack, and the stack's height is not available at that branch —
making it exact would mean moving the panel inside the `GeometryReader` that wraps the toolbar and
timeline column, which relays every other dropdown.

---

## 8. The library, the groups, and the default set

§2.16.

### 8.1 Two collections, and they are not the same thing

The **library** is app-level: the brushes the artist can pick, their groups, and the ones they make. It
persists across documents. The **document table** (§5.4) is per-document: the brushes the strokes in *this*
file were actually drawn with.

**BUILT 2026-09-04, and it took a third population with it.** Before this, the picker was
`BrushLibrary.defaults + CanvasManager.customBrushes`, and `customBrushes` is persisted **in the
project manifest** — so the artist's own brushes lived in whichever document happened to be open, and a
brush imported in one file was unpickable in the next. That is the defect this section names, and the
library is the fix. `customBrushes` stays, unchanged, because `ProjectStore.importedTextureFileNames`
reads it to decide which tip PNGs a saved package must carry; what it *means* narrowed from "the
palette" to "the imported brushes this document needs files for". The one crossing is
`CanvasManager.adoptRestoredBrushesIntoLibrary`, called once on project load: a file made on another
device restores brushes this library has never seen, and without it they would be drawable and
unpickable. It is id-keyed, so reopening the same project adds nothing the second time.

Both are needed, and the pair buys something neither does alone. Because a stroke is frozen to the brush it
was drawn with (§2.10), **a document that carries its own table is self-contained** — it opens correctly on
a device whose library has never held that brush. That falls out of §2.9 and §2.10 rather than costing
anything.

**Neither population subsumes the other, and `ProjectStore`'s texture copy takes the union** — §5.4. The
table holds brushes no picker lists, because §2.10 mints one per edit; the palette holds brushes no stroke
uses, because an artist can import a tip and not draw with it yet. A copy that walked either alone loses
something: the first case loses the ink's own tip, which is the defect BUGS.md carried, and the second
loses the picker's.

### 8.2 Groups are a flat `[BrushGroup]` — the layer-tree reuse was tried and is refuted

**This section used to say the opposite**, and it is worth keeping the claim it made because it is the
kind that sounds unanswerable: *"the layer tree is already a complete, tested, persisted, ordered
hierarchy with folders, and it is the third feature to want that shape — reuse it rather than
hand-rolling a third tree."* Built against the code (`BrushGroup.swift`, `BrushLibraryStore.swift`,
2026-09-04), three facts say no, and each is on its own decisive:

1. **There is no node type to reuse.** `Layer` and `LayerFolder` are two concrete structs, ~700 lines
   between them, and every field on them is about layers: cel content, `alphaMask`, `compositorRole`,
   `effect` plus its per-parameter keyframe tracks, `isFillReference`, blend mode, isolation, and the
   `hasCustomName` provenance flag. Nothing there is generic over a payload. "Reuse" therefore means
   either making `Layer` generic — a refactor of the single most load-bearing type in the app, to gain a
   brush picker — or instantiating layers *as* brushes and carrying twenty inert fields per brush.
2. **A folder has no ordering field at all, and an empty one cannot be placed.**
   `CanvasManager.containerEntries` derives a folder's position from the *topmost `layers` index its
   contents occupy*, on the invariant that a folder's layers are a contiguous span. That is elegant for
   layers, where an empty folder is a transient state; here it is fatal. `layerStackRows`' own comment
   says it: *"A folder holding no layers yet has no span, so it renders at the top of whatever contains
   it."* An artist who makes a brush group and then fills it would watch it jump. Brush groups need an
   order of their own, which is an array index — and `BrushLibraryLogicTests`'
   `testAnEmptyGroupKeepsThePositionItWasMovedTo` is the pin.
3. **The owner's own reference shows one level of grouping.** Nesting is the only thing the layer tree
   would have contributed, and nothing has asked for it. §7.1's two columns cannot render a second level
   anyway.

So the model is `[BrushGroup]`, each holding `[Brush]`, ~40 lines, with the store
(`BrushLibraryStore`) owning add / rename / reorder / delete and the one invariant worth having: **a
brush id lives in at most one group**, so adding a brush to a second group moves it rather than
duplicating it. TODO (30)'s document-organising observation is untouched by this — it may still want the
layer tree, and it should be checked against the code the same way.

**And the library is persisted as JSON, not in `UserDefaults`** — `Documents/Brushes/library.json`,
beside the imported tip PNGs a group's `.stamp(.imported(fileName:))` entries name. It is
`PaletteStore`'s shape with a file instead of a defaults key, and `-resetBrushLibrary` is
`-resetPalettes`' twin.

### 8.3 What may be shipped, and it rules out most of what is on the internet

**Artist brush packs cannot be redistributed inside this app** — Procreate `.brushset` packs, free `.abr`
packs, anything from Gumroad, Patreon, DeviantArt or ArtStation. They are near-universally licensed to make
*artwork* with, not to embed in software. Two representative EULAs say so in as many words: *"You do not
have the right to redistribute, resell, loan, rent, or lease my resources, modified versions or parts
thereof"*, and a second permitting use only where the brush is *"part of a finished, flattened original
artwork"*. "Free to download" is not a licence to ship. **This is what the artist's own import path exists
for** (§12 stage 10): a pack the artist buys is theirs to use, it simply does not travel inside the binary.

**Sources that are genuinely clear:**
- **GIMP's `data/brushes`.** GIMP's own `LICENSE` states that data used in artworks — brushes, patterns —
  *"should be under a CC0 license"*, separately from the GPLv3 covering the program. Its own caveat is that
  this is the policy for contributions and older files predate it, so it is strong but not airtight
  file-by-file.
- **David Revoy's Krita brush bundles**, released by their author as explicit CC0.
- **OpenGameArt's ~100-piece grunge brushstroke and splatter set**, explicitly CC0 — scanned real
  brushstrokes and splatters, genuinely tip-shaped rather than tileable material.

**Not clear, and not to be assumed:** **Krita's own bundled default presets.** Krita is GPLv3 and its
licence page does not carve out the resource bundle, which is a multi-contributor patchwork with no
top-level statement. "It ships with Krita" is not evidence.

**Every licence claim above is verified before an asset is committed, not once here.** Third-party hosting
gets relicensed and pulled; a dedication true when this was written is not a dedication at ship time.

### 8.4 Generate the core, source only the organics

Most of what §2.16 asks for is procedural and therefore has clean provenance by construction: a hard round is
a disc, a soft round a falloff, a square a square, a technical pen a small hard shape, a chisel an
anisotropic mask, a pencil a mid-frequency noise threshold.

**Including the one the owner singled out — and it is a dynamics effect, not a tip effect.** MEASURED by an
offline prototype running `BrushStamper`'s own walk arithmetic: a disc whose boundary is eroded by
high-frequency noise measures 1.08% of a brush width of edge roughness as a lone dab, and **the stroke made
of it at a 10% spacing measures 0.41%**. The walk unions about ten overlapping dabs, so the edge is a running
maximum of the notch profile and a neighbour fills most of each notch. **Cranking the erosion does not rescue
it and is not even monotonic**: a deeper tip renders a *smoother* line (0.262%) than a shallower one, and a
tip with interior pits — 7.93% rough on its own — reaches the line at 0.304%. At the size a lineart nib is
actually used, a 5 pt brush at 2× retina, the entire surviving effect is **0.06 px**. What does survive is a
*periodic sawtooth* at the dab spacing, because every dab presents the same profile at an even interval; it
reads as a rendering artifact rather than as ink.

**The mechanisms that work are coherent along arc length**, because those move the envelope the union takes:
`random → size` at ±30% measures 3.6% of a brush width — nine times the eroded tip — and coherent
`random → scatter` 2.3%. So **the rough ink nib is generated from modulation on a clean round tip and needs
no tip texture at all**, which is why §2.17 and §2.18 are where it lives. Two negative results from the same
measurement, both worth not re-deriving: coherent `scatter` and a pure perpendicular offset are
indistinguishable, so there is no `offset` output; and several `random` rows at different λ give multi-scale
roughness, so there is no **spectral-slope** parameter.

**The octave half of that second result was reversed on 2026-09-05, and saying why matters.** The
measurement refuted a *spectral slope* — a knob that tilts the mix — and it was right to. What it
quietly assumed was the **several-rows spelling**, and §2.24's one-input-per-output makes that spelling
unavailable: it asks an artist to add three chains and halve each amount by hand. §2.28's randomiser
carries a **count** and a **falloff** instead, which is the same arithmetic in one object and one
control, and MEASURED **cheaper** than the rows it replaces — an octave is 0.24 µs (one more hash and
one lerp inside a module already resolved) against a whole chain's sensor read and hash for a row. Its
own band-limiting is MEASURED rather than asserted: three octaves at a falloff of 0.5 tilt the field's
structure function by **1.48×** against a predicted 1.51, and stay a sixteenth of the way to a fresh
draw per dab.

**§8.4's union argument has a boundary, and the owner found it by eye where two rounds of measurement
had not.** On the second contact sheet the owner noticed that Pencil Blunt's mask has a **sharp cutoff
along one edge**, making the shape uneven, and that *this* is what produces the blotchy roughness once
the dab is randomised. That reads as a contradiction of §8.4 and is not one — it is the missing half of
the same rule:

> **Roughness survives when what a dab presents to the silhouette changes from dab to dab.**

An eroded *round* nib fails that, which is what §8.4 measured: every dab offers the same profile, ten of
them overlap, and the running maximum is the profile itself. A **direction-locked** nib fails it for the
same reason, which is why the square slab's ragged edge washed out. But an **asymmetric** nib under
`angle.jitter` passes it, because rotating an uneven shape changes its outline while rotating a disc
changes nothing at all. **The tip's asymmetry is what makes rotation jitter visible**, and rotation
jitter is what makes the asymmetry survive; neither does anything alone. Pencil Blunt carries
`angle.jitter` at 1, so it had both by accident.

So the generator's rule is not "no tip textures". It is: **a tip contributes roughness only through a
dynamic that varies its presentation** — rotation jitter for an asymmetric silhouette, size jitter for a
scale-dependent one — and **interior grain is exempt**, because a pit mid-dab is not filled by a
neighbour's boundary, which is why the pencils' tooth reads. *(The exemption is narrower than this
sentence: the second sheet found that interior structure survives only when it is a **hole** rather
than a dimming, and only when it does not vary **along the travel**. See below.)*

So: **generate Basics, Sketching, Inking and Painting; source CC0 only for Texture**, where scanned grunge
and splatter are genuinely hard to fake.

**The generator and the first contact sheet are built — §12 stage 9's first half — and four things came
back from rendering it.** `PaintSoftwareUITests/BrushTipGenerator.swift` draws twenty-three masks and
`BrushContactSheetBench` renders every candidate through `BrushStamper.stampStroke` itself, so what
follows is MEASURED against the shipped walk rather than against a prototype.

- **The refutation above is not about round nibs. It is about a picture being the same picture at
  every dab, and it reaches the square slab too.** The nib's *ends* trace a slab stroke's two edges;
  they present one fixed profile, ten overlapping dabs take its running maximum, and what an artist
  sees is a slightly wobbly straight line. The sheet carries the A/B: the same PNG in two rows, one
  roughened by the drawing and one by `size ← random(λ = 0.6)` plus three degrees of `angle.jitter`.
  **The second reads torn along its whole length and the first only at the caps and where a stroke
  crosses itself.** So a ragged tip edge is worth what it adds at a cap, and the tear is §6's.
- **Interior grain is a different mechanism and it does survive.** The four pencils are mid-frequency
  noise thresholds *inside* the nib with `angle.jitter` at 1, and the tooth reads plainly in the
  stroke. A pit in the middle of a dab is not filled by a neighbour's boundary the way a notch in one
  is, and rotating per dab moves the pits' phase — which is §8.5's variant argument arriving as the
  reason a generated pencil works at all.
- **A textured tip carries a minimum spacing, and it is far wider than the presets otherwise use.**
  The blender was authored at `spacing 0.02` and rendered as a plain soft round: its mottle was
  unioned away completely. At `0.10` the mottle reads. Anything whose character is in its pixels
  needs the dabs far enough apart to be seen one at a time.
- **Which of a tip's edges is visible is decided by the brush's `angle`, not by the tip.** On the slab
  (`base 0.25`, `directionFollow 1`) the long edges sweep *along* the travel and only the ends are on
  the silhouette, so an authoring pass that roughens the long edges roughens nothing an artist will
  see. Author the roughness against the angle the brush will carry.

**And the count of what needs no artwork went up.** Soft round, hard round, the technical pen and the
opaque round are `BrushTip.round` plus a hardness and a spacing, and Rough Ink Blotchy is this
section's own refutation. **That is five of §8.6's sixteen answered by arithmetic**, which is worth
knowing before anyone sources a pack to fill them.

**Both halves are authored rather than only assembled, and the owner asked for that explicitly**: a
sourced pack is the starting stock, and the shipped brushes are designed on top of it — tips drawn,
settings tuned, and each judged by eye against the contact sheet before it enters §8.6's table. Owner:
*"im guessing you are going to use the free krita brush pack, but then have an agent also design some
brushes too? As in making the sprites, customizing settings to what it thinks looks good, etc. That
would be appreciated."* So a group is not "whatever the pack had under that name"; §12 stage 9 owes a
*designed* set, and the sourced assets are raw material for it. **§8.3's licensing rule is unchanged and
now has a third source to check** — Krita's bundles, per file, before anything is committed.

**The second sheet rendered the boundary paragraph as a 2×2, and it holds.** Five Rough Ink rows
carry *identical* brush settings — same size, dab fraction, flow, spacing, one pressure row, and no
`density` dropout at all — and differ only in their picture and their `angle.jitter`:

| | jitter 1 (±180°) | jitter 0.03 (±5°) |
|---|---|---|
| **asymmetric** (a rough triangle) | **rough along the whole line** | a clean line |
| **symmetric** (an eroded round) | a clean line | (Technical Pen Fine) |

So both terms are necessary and the sheet says so in pictures rather than in prose. The eroded-round
control is the striking one: its *mask* is a wildly spiked disc and its *stroke* is smooth, which is
§8.4's original 0.41% measurement seen rather than computed.

**Five further things came back from that sheet, and three of them are the union argument reaching
somewhere nobody had pointed it.**

- **A union fills in a dimming; it cannot fill in a hole.** The painterly nib's bristle streaks were
  authored at 30% depth — visibly beautiful on the mask — and every one of the five painterly rows
  rendered as an identical solid slab. At these spacings a stroke lays twenty-odd overlapping dabs
  over every point, so a band dimmed to 0.2 of coverage accumulates to **0.92** and is gone. Streaks
  that reach *zero* survive; shading does not. `streakDepth` therefore sits near 1 on every nib whose
  streaks are meant to be seen, and the width of the closed band is what separates a comb from a
  blotch.
- **Anything that varies along the direction of travel is filled in by its neighbour, including
  inside the dab.** The same streaks were a band in `v` times a break-up in `u`; since consecutive
  dabs slide along `u`, one dab's gap sits over the next one's ink. Interior structure is exempt from
  the union argument only when it is **constant along the travel** — which is why the pencils (whose
  pits move because the tip turns) and the bristle (whose channels are perpendicular to the slide)
  both work, and why a `u`-varying streak does not. The surviving `u` term is a slow lateral wobble
  of the whole comb, a tenth of a band period across the nib.
- **`flow` is the other half of that, and 0.9 is too much for a nib with structure in it.** Twenty
  overlapping dabs at flow 0.9 saturate whatever the mask says. §2.11's pair is the fix: drop the
  *flow* and leave the stroke's opacity at 1, and the tonal range survives while the stroke still
  covers.
- **A soft, dirty end falloff survives the walk better than a displaced hard boundary does.** Messy
  Flat's sprite *alone*, direction-locked, already carries a fine hairy edge — not the clean wobble
  §8.4 predicts for a displaced boundary. Dilating a hard edge gives a hard edge; dilating a **ramp**
  gives a ramp whose position still wanders, so the mottle survives as softness even though the
  boundary noise does not. The full attributable set on that nib (one picture, terms added one at a
  time) ranks them: the envelope wobble does most, the picture next, ±2° of jitter least.
- **The two mechanisms make *different* roughness, not more and less of one.** A tipped nib under
  full jitter draws a **fine, even tooth** along the edge; Rough Ink Blotchy — all dynamics, no
  picture — draws **coarse lumps and outright breaks**. Neither is the other's weaker version, and
  the sheet carries a sixth row that is both at once.

**And one thing a slab nib does not do.** Three "Square" rows bracket the owner's *"only falls off in
the very edges"* from crisper than Opaque Round to softer than it, and at slab widths **the three
strokes are within about a point of each other**: the falloff is a ~1 pt ramp on a 24 pt band and the
chamfer shows only at the caps. Pick that nib on its cap and its aspect; the edge softness is not
where its character is.

**The Bristle defect was in the mask and nowhere else.** *"Right now you can see it fit within a clear
oval shape"* was literal — every filament was multiplied by one shared elliptical envelope, so the
silhouette **was** that ellipse however the filaments fell inside it. Giving each filament its own two
ends and its own taper, and multiplying by nothing shared, fixes it with no dynamics at all.

**Edge softness may be part of the nib rather than a fault in the dab.** The owner, on seeing rough ink
references: *"some versions of it are heavily aliased thus adding to the rough look... I may settle down on
there being multiple versions of this brush."* [BUGS.md](BUGS.md) records that a hard round dab is fully
aliased at hardness 0.95 and reads that as a defect; against a nib whose edge is *meant* to be seen it is at
least as likely to be an ingredient. §6 already carries `hardness` as an output, so the mechanism exists —
what is unsettled is whether the rough ink family ships as one brush or several, and that is a contact-sheet
question rather than an argument. **It is answered, and the answer is a control**: the owner ruled that edge
softness belongs in the brush editor as a slider or a toggle, so it is one field on `BrushDabSettings`
built with §12 stage 10 — not a repair taken beforehand. [BUGS.md](BUGS.md) carries the measurement, the
mechanism (CoreGraphics spends its band budget in proportion to the gradient's extent, so hardness 1.00 is
a *deterministic* two-alpha edge while 0.93-0.99 wanders with the size slider) and the field's cost.
**Do not antialias the dab globally**, and do not take the repair on its own: softness 0 is today's hard
edge, and the repair is only what makes the values between it and a clean ramp mean anything.

### 8.5 One texture per tip, and what that costs

Procreate builds a brush from two textures — a Shape Source and a Grain Source stamped through it. **This
engine takes one**, because §2.4 deleted grain and a second per-brush texture reintroduces it under a new
name.

The honest cost is **stamp repetition**: one tip means every dab of a stroke is the same shape, and a long
line can read as a pattern. The answer stays inside one concept — **a tip is a small set of variants, and
§4's hash picks one per dab.** Order-independent by construction, so it survives a split, a refit and a
spacing edit like every other random draw, and it needs no second texture kind.

**And the repetition is finer than "a long line can read as a pattern".** MEASURED: at a 10% spacing, one
tip stamped every 0.1 widths puts a *regular sawtooth* on the stroke's edge — a comb at the dab period,
rather than a texture. Rotating per dab breaks it, so the variant set is load-bearing rather than a nicety.
But note what rotation does at that spacing: it presents a different boundary radius per dab, which **is** a
per-dab size jitter. A clean disc with `random(λ = 0) → size` at ±6% measures the same character — 1.27% of a
width against 1.25% for the rotated eroded tip — and needs no tip. **The variant set earns its keep for
shaped tips (bristle, chalk, splatter) and not for a rough round, where §6's own modulation is the cheaper
answer.**

### 8.6 The set — chosen by the owner from the contact sheet

Five groups; **24–30 brushes**, which is the scale Photoshop now ships by default and well inside Clip
Studio's 42. Not Procreate's 200+, which is a decade of accretion.

**Sixteen are chosen and named below. The owner picked them off the first contact sheet and expects to
add more later** — *"I probably will choose to add more brushes in a future session, so no need to go
too far"* — so the groups are deliberately short of the band rather than padded to it.

Erasers are not a group: the eraser *is* a brush (§11), so every one of these erases already.

**Basics — 5.** Round Soft, **Opaque Round** (moved here from Painting at the owner's instruction —
*"I feel it better belongs here"*), Round Hard, and two square nibs:

- **Square** — a slab with **no noisy edges**, **bevelled corners**, and a falloff *"sort of like opaque
  round in that it only falls off in the very edges"*. The clean one, and the first sheet's finding is
  why it is clean: a ragged tip edge does not survive the walk on a direction-locked nib.
- **Messy Flat** — *"like the flat brush, except with messier ends. Still square, but the sprite gives
  it a unique non monolithic look for the ends, more of a slightly dirty falloff."* The ends, not the
  long sides: §8.4 records that a nib's long sides sweep *along* travel and never reach the silhouette.

**Sketching — 4.** Pencil Hard, Pencil Soft, **Pencil Blunt**, Pencil Textured. The owner's note on
Blunt is what §8.4's boundary paragraph is built from: it is *"much closer to the messy edge look I
wanted for the rough ink brush"*.

**Inking — 4.** Technical Pen Fine, Brush Pen, Rough Ink Blotchy, and **Rough Ink**, which is the one
piece of open design in the set:

> *"Look at the pencil blunt sprite. Right now, there is a sharp cutoff in the bottom. Whether
> intentional or not, that sharp cutoff makes the sprite uneven, and thats what creates the rough
> blotchy look when its randomized. I want you to take that concept with this pen and experiment with
> it."*

Named candidates: a **triangular** blob, a **rough squareish** shape, or **half-round-half-flat like
Pencil Blunt** if the rotation is fully isotropic. This is the brush §2.16 asked for by name and the one
§8.4 twice tried to build from dynamics alone; the answer is now known to be **both** — an uneven
silhouette *and* the jitter that turns it.

**Painting — 3**, and the group with the most left open.

- **A painterly nib**, to be explored broadly. The owner's reference: real paint-stroke sprites are
  *"a lot more squarish than slab shaped, though the shape is alot more blotchy than square, with a
  clear bristle direction noticeable in them."*
- **Bristle**, with **noisier edges** — *"Right now you can see it fit within a clear oval shape"*, and
  a silhouette that betrays its bounding shape is the defect.
- **Streaky** — *"Imagine the sprite being just a bunch of little dots, like 6 or 8 of them placed
  randomly. The brush makes many streaks."* A handful of separated points, so one drag lays parallel
  ribbons rather than a band.

**Texture — deferred to §12 stage 11**, the CC0 group, gated on §8.3's per-file licensing.

**The owner's own sprite reference**, supplied as a folder of thirty-three masks and described here
because the file did not travel: tall roughly-rectangular alpha masks, black on white, in four families
— **jagged/eroded outlines** (`JaggedSquare`, `MoreJaggedSquare`, `WobblySquare`, `TestSquare3/5`),
**horizontal bristle streaks** (`SquareBristles`, `SquareBristles2`, `chisel_streaks`, `ZigZag`,
`ThickStrokes`, `TestSquare7`), **soft or blurred slabs** (`SqareBlurred`, `SpongeSoft`, `CheeseBlurred2`,
`MoreJaggedSquareBlur`, `TestSquare4/8/10`), and **dotted or speckled fills** (`SpongeDotted`,
`WobblySquare2`, `TestSquare6`). `SpongeBlob3` — an irregular organic triangle — is named as a Rough Ink
candidate.

**The slab was drawn and it confirms both consequences.** `roundness` was not needed and never came up:
the nib is a 4:1 rectangle inside a square mask, the perpendicularity is `base 0.25` with
`directionFollow 1`, and one drag lays a band as wide as the nib's long side — which is the reference.
§6's deferral survives its first real test. What the *sheet* added is above, in §8.4: the tear has to
come from §6 rather than from the picture, because the picture is the same picture at every dab.

**The second contact sheet, which is what the sixteen are picked *into*.** Thirty-four rows over the
sixteen slots — 11 Basics, 4 Sketching, 9 Inking, 10 Painting — twenty-three generated tips, six PNGs. `BrushContactSheetBench` groups by **slot**
rather than by group and marks every row `CHOSEN` (settled — nothing competes with it), `VARIANT`
(competing for an open slot) or `CONTROL` (**on the sheet in order to fail**, isolating one operand
of §8.4's pair). It also carries a **third stroke that turns 340°**, because the first sheet's report
recorded the chisel as *"correct but subtle; the thick/thin needs a stroke that turns more than a
contact-sheet row allows"* and every square, flat and bristle nib has the same problem: a wave reaches
±18° and a nib's angle only shows across a wide sweep.

| slot | rows |
|---|---|
| **Round Soft · Opaque Round · Round Hard** | one each, procedural, unchanged and chosen |
| **Square** | Crisp · Soft Edge · Wide 2.5:1 — clean bevelled slabs, no jitter, bracketing the falloff |
| **Messy Flat** | Sprite Only *(control)* · + 4° Jitter · + Envelope · + Both · Milder Sprite — one picture, terms added one at a time |
| **Pencil Hard / Soft / Blunt / Textured** | one each, unchanged and chosen |
| **Technical Pen Fine · Brush Pen · Rough Ink Blotchy** | one each, unchanged and chosen |
| **Rough Ink** | Triangle · Triangle No Turn *(control)* · Rough Square · Half-Flat · Eroded Round *(control)* — the 2×2 above — plus Triangle + Blotchy Dynamics, outside it |
| **Painterly** | Blotchy · Streaky · Jagged · Soft Slab · Dry Load |
| **Bristle** | Open · Open + Envelope · Dense |
| **Streaky** | Six Dots *(stratified)* · Eight Dots *(uniform)* |
| **Texture** | empty — §12 stage 11's CC0 sourcing |

The chisel, the two ragged square slabs, the painting flat and the blender are **gone** rather than
carried: none is among the sixteen, and the first sheet's finding is why the ragged slabs are — a
direction-locked nib's ragged edge does not survive the walk.

**Nothing here is in `BrushLibrary` and that is still the point** — §12 stage 9 is driven by contact
sheet at the owner's instruction, so the presets are authored after the picking, not before it.

## 9. Grain — the deletion

§2.4. Delete, do not disable.

**Render**: `BrushGrain` and `noiseValue` (`Engine/Brush.swift`), the `grainMultiplier` fold into dab alpha
and `grainAlphaMultiplier` (`Engine/BrushStamper.swift`), the alpha-formula comment in
`Engine/RasterLayerTexture.swift`, the absolute-position doc comments in `Engine/VectorLayer.swift`.

**Model and persistence**: `Brush.grain`, its initialiser parameter and default, and the `pencil` preset's
grain in `Engine/BrushLibrary.swift`. No sidecar codec — grain rides `Brush`'s synthesized `Codable`.

**UI**: the Grain Depth slider and its binding in `Views/StrokeSettingsPanel.swift`.

**Tests**: the two `BrushEngineLogicTests` noise pins; the §2.16 grain-under-pose tests in
`RestSpaceDabBakeLogicTests` and `TransformChannelLogicTests` — **deleted with the feature, per §2.5, not
rewritten**; `grain: .disabled` in fixture constructors across four suites; parity-test doc comments.

**One behaviour change rides along, and it is an improvement.** `VectorEraser.supportsCleanCut` vetoes any
grain-enabled brush, so the pencil has never been cleanly cuttable by the vector eraser. Deleting the veto
makes it so. Intended, and pinned by a test that names it.

**Do not touch** `Effect.Noise` and the "Grain" control in `Views/EffectSection.swift`. That is the image
effect, a different feature that shares a word. Four test suites reference it.

**Texture came back on 2026-09-04 and this ledger stands unamended, which is the point.** §2.25 reverses
§2.4, and nothing above was resurrected to do it: `BrushGrain`, `noiseValue`, `grainAlphaMultiplier`, the
Grain Depth slider and the `supportsCleanCut` grain veto are all still gone, the deleted tests are still
deleted, and no vestigial field came back to life. What returned is a different mechanism in a different
place — a sheet multiplied into the *stroke's* buffer at the merge, in canvas coordinates, rather than a
noise function folded into each *dab's* alpha — and it is a new type, `BrushTextureSettings`, sitting
beside `BrushTip` rather than where `BrushGrain` sat.

The distinction is not bookkeeping. `grainAlphaMultiplier` was a function of the dab's absolute position
evaluated per dab, so posed ink boiled and a lassoed move re-sampled; a canvas-anchored sheet applied
once at the merge has neither property, and §2.5's KEYFRAMES §2.16 stays discharged rather than reopened.
The one thing §2.4 was right about is still true and is why this shape was chosen: **a sprite travels
with the stroke and paper does not.**

---

## 10. The deletion ledger, and what makes the result flexible

§2.14. **Every stage of §12 deletes its predecessor in the same change that replaces it.** A removal
deferred to a cleanup pass is exactly how legacy accumulates, and there is no cleanup pass scheduled.

### 9.1 What must not exist afterwards

| gone | replaced by | stage |
|---|---|---|
| ~~`StrokeSampleGate`~~ **gone** | `StrokePathFit` + `StrokePath` — §3.3, §5.3 | 0 |
| ~~`DiscardedDabTarget`~~ **gone** | hashed randomness has no stream to keep in phase — §4 | 1 |
| ~~`BrushStamper.DabRNG`~~ **gone**, both initialisers | `DabRandom` — §4 | 1 |
| ~~`BrushStamper.seed(for:)`~~ **moved** to `DabRandom`, and no longer how a stroke gets its seed | `VectorStroke.seed`, minted and inherited — §4.2 | 1 |
| ~~`DabLattice.seedID`~~ **gone** | the stroke's own `seed`, which a piece inherits by being a copy — §4.2 | 1 |
| `BrushGrain`, `noiseValue`, `grainAlphaMultiplier`, the Grain Depth slider, the `supportsCleanCut` grain veto | nothing — §9 | 2 |
| ~~`stampApproximateSquare`~~ **gone**, and with it `Brush.hardness` reaching a square dab at all | `stampImage`; `.square` is a committed alpha mask — §3.5 | 3 |
| ~~`PackedSampleRun`'s fixed record and its `.quarterPixel` / `.float32` mode flag~~ **gone** | `SampleChannelSet`, one header byte, `preciseCoordinates` as bit 0 — §5.5 | 4 |
| ~~`BrushStamper.Sample`~~ **gone** | `StrokeSamples`; the stamper walks the stroke's own storage — §5.5 | 4 |
| ~~`VectorSample`'s `Codable`, and `decodeRun`'s `[VectorSample]` fallback~~ **gone** | one way to write a sample, and it is `PackedSampleRun` — §2.14 | 4 |
| ~~`BrushShape` + `customTextureFileName` as a separable pair~~ **gone**, and with it `BrushShape.displayName` | `BrushTip`, one payload-carrying enum — §6 | 5 |
| ~~`VectorStroke`'s by-value `Brush`~~ **gone** | `BrushRef` into `BrushPool`, redeemed against the document's `BrushTable` — §5.4 | 6 |
| ~~`BrushDynamics`~~ **gone in full**, both blends and the type | §6's matrix: two rows per preset — §12 stage 7 | 7 |
| ~~`Brush`'s flat scalars~~ **gone** | `dab` / `stroke` / `modulations`, each with a defaulted decode — §6 | 7 |
| `BrushLibrary.defaults` — softRound, hardRound, pencil, pen, square | the generated and sourced set, in groups — §8 | 9 |

**No decode defaults for fields that stopped existing, no format version, no migration, no compatibility
shim, and no "this used to be" comments.** Documents on the device are expendable, so the format simply
changes. The one place history is kept is this document and `git log`.

**`BrushDynamics`' two blends were the trap on that list**, because they are correct and cheap and there
would have been a reason to keep them as a fast path beside the general one. Two ways to compute a dab's
size is two ways for it to be wrong, and the parity test compares tiers rather than paths, so it would
not catch the divergence.

**They are gone, and the assertion that says the deletion cost nothing is the one to keep.**
`BrushModulationLogicTests.testTheFivePresetsRenderIdenticallyToTheDynamicsTheyReplaced` renders all
five presets both ways at **zero tolerance** — once through the matrix, once through the deleted
arithmetic *transcribed into the test* rather than called, since calling a surviving copy would be the
second path this paragraph forbids. Mutation-tested: moving one preset's row amount by 0.02 reds it.

The exactness is not luck. Each preset's `dab.size` is `1 - k` and its row is a `ResponseCurve.ramp`
from `m` to 1 at amount `k`, so the expression evaluated is `(1 - k) + k · (m + (1 - m) · p)` — the same
association, in the same order, as `sizeFraction`'s `(1 - k) * 1 + k * pressureDriven`, and `x * 1` is
exact. §6.1's power-of-two scale is what makes the curve half exact; `1 - k == ` the literal base was
checked for all five, and `m + (1 - m) == 1` for all five values of `m`.

### 9.2 What makes it flexible, which is a property of the same decisions

Flexibility here is not an extra layer. It is what falls out of §2.14 being obeyed:

- **One evaluation funnel** (§5.5) means a new sensor is one case in one switch with a defined neutral,
  not a thread through every parameter.
- **The modulation matrix** (§6) means a new *parameter* is data rather than code — a row in a table, not
  a branch in the stamper.
- **The channel set** (§5.5) means a new per-point channel is two bits and no format version.
- **Payload-carrying enums** (`BrushTip`) make illegal states unrepresentable and keep `stampDab`'s switch
  exhaustive, so adding a tip kind is a compile-error-guided change rather than a search.
- **Nested settings with defaulted decode** (§6) mean a new setting is one field, not a
  decode-compatibility question — which is what `Brush`'s synthesized `Codable` makes every flat key today.

Each of those is a deletion doing double duty. None of them is speculative generality, and none should be
built beyond what §12's stages need.

## 11. What the current engine already gives this for free

Not to be lost — [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) argues each at length.

- **One stamper serves every tier.** Live raster, vector replay, the eraser and the shape tool all funnel
  through `stampStroke` → `stampDab` → `DabTarget`, so a new tip kind reaches all of them at once.
- **The eraser is a stroke**, so an imported brush erases with no eraser work.
- **`RasterVectorParityLogicTests` compares the two tiers at zero tolerance** and is the regression net for
  this whole item. It already exists.
- **Imported-asset lifetime is half solved** — `ProjectStore` copies an imported tip's PNG into the
  project and restores it on load, and since stage 5 the *filter* is exact (`BrushTip.importedTextureFileName`,
  which cannot disagree with itself the way `shape == .custom` plus a nil-able name could). What it walks
  is still the palette rather than the drawing; §5.4 and [BUGS.md](BUGS.md) carry that, and stage 6 owns it.
- **`supportsCleanCut` / `supportsSplitting` gate on brush *properties*, not on a list of known brushes**,
  so a scattered, jittered imported brush falls back to the exact alpha punch automatically. Do not relax
  `supportsSplitting`: its coverage test measures against a capsule chain, and scattered ink is not bounded
  by one.

---

## 12. Build order

Stages 1–4 are worth doing on their own merits with no file format involved, which is the test of whether
the ordering is honest.

**This order stands, and that is a decision rather than an oversight.** §8.4's refutation means the rough
ink nib needs no tip texture, so it could be pulled in front of the library and the editor and drawn with
early. It is not. Owner: *"The brush will get done once the brush engine which allows it to exist is done,
along with the other brushes. Focus on the engine for now. I want a clean and well designed architecture
first, which cleanly replaces the old one."*

0. **DONE — the path: refit, and `StrokeSampleGate` deleted.** §3.3 and §5.3. `StrokePathFit` decides what
   is stored and `StrokePath` is the curve every tier walks; the arc-length march and the curve tangent
   came with it, and `StrokeGeometry.tangent(atParameter:)` reads the curve rather than a chord. Pinned by
   `StrokePathWalkLogicTests` (a stored stroke is true to the drawing under brushes whose spacings differ
   forty-fold — the thing the gate made impossible) and `StrokePathFitLogicTests` (the tolerance, the cap
   against a warp, the pressure escape, the lift point, and the ink unchanged).
   **The live preview stopped being gated with it.** The fit commits a knot only once the sample after it
   proves it was needed, so driving the preview from its output would hang the ink a whole cap behind the
   pen; it is driven from the samples instead, as the raster tier and Mode 3's resolve already were, and
   the two agree to within the fit's 0.25 pt.
1. **DONE — randomness by hash.** §4. `DabRandom` is the field; `DiscardedDabTarget`, `DabRNG` and
   `DabLattice.seedID` are gone. Pinned by `DabRandomLogicTests`: a lassoed split of a **scattering**
   stroke moves no pixel; the live walk and the refitted replay draw the same values; halving the spacing
   leaves the dabs that still land on the same arc length alone; a Mode 2 punch leaves the ink in front of
   it bit-identical and the tail does not repeat the head's pattern; a uniform scale draws the identical
   values. **Five tests in the whole repo touched the random path before this stage and none of them could
   have caught what §4 is about** — two hand one walk to two rasterizers, three assert a scattering stroke
   is *refused* the split path, and every other fixture is `scatter: 0`. So the mechanism
   `DiscardedDabTarget` existed to protect was green against fixtures that could not have moved.
2. **Delete grain.** §9. Independent of everything else, and it shrinks the surface every later stage
   touches.
3. **DONE — `stampImage` on `DabTarget`**, the tinted cache and its hit-rate test. `.square` is a
   committed alpha mask and `stampApproximateSquare` is gone; `BakedDab` carries a tip with an angle
   and `DabPose` turns it by its Jacobian's polar rotation. Two of this section's instructions were
   **refuted by measurement and §3.5 records both**: the cache is keyed on tip, colour and size octave
   rather than rotation-bucketed, and the size term was in turn added only after an in-app measurement
   contradicted the microbenchmark that had said it was worthless.
4. **DONE — the sample record.** §5.1 and §5.5. `SampleChannelSet` is one header byte and absorbs the old
   precision flag; `StrokeSamples` is the struct-of-arrays every transform, cut and warp now carries
   channels through generically; Δt, altitude and azimuth are three new byte channels; `StrokeSensors` is
   the funnel and `BrushInput.neutral` its defined answer. Pinned by `SampleRecordLogicTests`: a run that
   carries some channels and not others round-trips both ways, every neutral survives its own quantisation
   exactly, an affine turns the nib and a translation does not, the fit's dropped intervals are absorbed
   and a cut piece reads the uncut stroke's speed, and — the guarantee the whole section exists for — a
   brush reading a channel the stroke does not carry paints byte-identical pixels to the same brush with
   that modulation removed. **Two of this section's instructions were refuted and §2.7 and §5.5 record
   both**: the capture was already in canvas space (the conversion that was missing is the layer
   transform's), and the funnel needs two coordinates rather than an arc length.
5. **DONE — `BrushTip`, and the renderer reads the artist's own PNG.** §6. The pair is deleted, the
   stamper resolves the tip's `BrushTextureRef`, and `BrushTipImport` is what an imported file has to
   be. `CanvasManager.importCustomBrush` is the whole import, so `BrushSettingsPanel` holds none of the
   rule and the path is drivable from a cold start. Pinned by `BrushTipLogicTests`: two brushes
   differing *only* in which imported tip they name stamp different pixels (the narrow test tip is the
   discriminating one — a tip that fills its mask is indistinguishable from the committed square, so an
   assertion built on that arm alone would be green against a stamper that ignored the tip); the round
   and stamp arms disagree at the corner; a fresh document imports, selects and draws in one call; and
   an import is letterboxed, bordered, right way up, read by luminance only when it is opaque, and
   refused when it is blank. **The one instruction this section gave that did not survive contact is
   "the renderer finally reads `customTextureFileName`"** — reading it is not enough, because the file
   an artist picks is an opaque photo and its alpha is all 255, so the stamp is a filled square however
   faithfully the renderer resolves it. §6 carries the normalisation that makes the feature usable and
   the reason it belongs at import time.
   **And one of this stage's own assertions was measuring `JSONDecoder`.** "A preset's id survives a
   round trip" passed with the id mutated back to `UUID()`, because a `static let` is one value for the
   life of a process and encode-then-decode inside it preserves whatever that was. The id has to come
   from *outside* the process to mean anything; the test decodes a manifest written down in the source
   instead. CLAUDE.md's assertion-true-of-mathematics, in this document's own back yard.
6. **DONE — the brush table.** §5.4, §2.9, the sweep, and §2.10's apply-to-existing verb at selection
   scope. `VectorStroke.brushRef` is four bytes; `BrushPool` is the process's value-addressed table and
   `BrushTable` the document's, written to `brushtable.json` beside `brushes/` and named by the manifest so
   `validateProject` refuses a package whose ink has lost the only thing that says what it was drawn with.
   `ProjectStore`'s texture copy walks the union of the table and the palette, which closes BUGS.md's
   *"copied by the palette, not by what is drawn"*. Pinned by `BrushTableLogicTests`: **one set of bytes and
   two tables mapping the same stored number to two different brushes give two different answers** — the one
   assertion an in-process round trip cannot make, and the direct answer to stage 5's *"and one of this
   stage's own assertions was measuring `JSONDecoder`"*; a stored number with no table refuses rather than
   guessing; a reopened document renders identically **after its stored numbers have been shifted out from
   under it**, which is what a launch with a differently-populated pool sees and what a test without the
   shift cannot distinguish from an implementation that ignores the table; the sweep drops an interned brush
   nothing references and keeps one only a recipe's local edit does; an imported tip **no palette entry
   names** still travels; a brush edit moves no pixel of ink already drawn; and the verb is one undo step
   across every stroke it touched.
   **Two of this section's instructions did not survive contact.** *"A stroke holds a small index"* is right
   about the size and wrong about the kind — a *position* in the document's table is what would have forced
   the sweep to renumber every stroke in every cel in one operation, which is precisely what §5.4 said must
   not half-apply; a pool ref is not a position and there is nothing to renumber. And *"a sweep on save
   drops entries"* describes a pass that deletes; what shipped never collects them, which is the same
   outcome reached by having no intermediate state at all.
   **What is deliberately not built**: layer and document scope for the verb, and the reason is filed rather
   than hidden — nothing in the repo batches per-cel content restores across *several* cels into one undo
   `Action`, and a selection lives in one cel. [BUGS.md](BUGS.md) carries it.
7. **DONE — the modulation matrix.** §6. Every dab parameter is `base + Σ amount · curve(input)`,
   resolved once per dab through §5.5's funnel by `Brush.dabValues(_:)`; `BrushDynamics` is deleted
   whole and the five presets carry two rows each instead. `density` (§2.18) skips a dab whose draw
   exceeds it, with λ on the row; `spacing` is read at **every** dab, drawn or skipped, which is what
   `StrokePath.advance`'s `WalkCarry` is for. Pinned by `BrushModulationLogicTests` — the five presets
   byte-identical to the arithmetic they replaced, every output reaching a dab and every input reaching
   an output, density at 1 bit-identical to no density row, a lower density removing dabs and moving
   none of the survivors, λ turning isolated skips into runs (measured as **mean run length over eight
   seeds**, not as "a noise field differs at two positions", which is true of any implementation), and
   the eraser refusing a brush whose ink the capsule chain cannot bound.
   **Four of this section's instructions did not survive contact.**
   - **`roundness` is not shipped** and §6 carries the reason: it contradicts §3.5's square-mask ruling
     and belongs to stage 9's chisel and flat brushes, which are the tips that need it.
   - **The live tier had to be taught the matrix**, which this stage did not anticipate. On a raster
     layer the dabs the pen lays down *are* the cel's pixels — nothing is re-stamped at lift — so a
     walk that could not read §6 would have left half the app without the feature.
     `StrokeCanvasView.stampPath` builds a two-sample `StrokeSensors` over the segment it is bridging.
     One behaviour change rides along and it removes a divergence: **live pressure now ramps across a
     walk** instead of being flat at the destination sample. A finger reports a constant 1, so nothing
     an XCUITest can draw is affected.
   - **§13's taper question is answered, and the answer is asymmetric.** A *replay* can measure the
     stroke, so `stampStroke` does — once, and **only when a row asks for taper**, because it is a
     second flattening pass. The live walk genuinely cannot and answers the neutral.
   - **`BrushDabValues` had to be answerable without a walk.** Three consumers have a pressure and no
     stroke; §6.3 is what they call and what the eraser's widened gates protect.
8. **DONE — Opacity and Flow, and the per-stroke buffer.** §2.11 and the two rulings under it. The
   `opacity` *output* is deleted whole — `BrushOutput`, `BrushDabValues`, `BrushDabSettings` and the
   `opacityFromPressure` factory — leaving `channelBase`'s number 2 unused, because that field's own
   instruction is *add cases, never renumber* and a renumber re-rolls every randomised stroke.
   `DabTarget` gains `beginStrokeGroup(opacity:blendMode:)` / `endStrokeGroup()`; `stampStroke`
   brackets its whole walk in one, a dab inside lays down its `flow` at `.normal`, and the merge is a
   CoreGraphics transparency layer composited under the stroke's own alpha and blend mode. The live
   tier gets a third `StrokeScratch` role, `.subtractive`, whose window holds an eraser's **removal
   coverage** rather than a punched picture; `.replacing` keeps its meaning and is the cut preview's
   alone. `StrokeSettingsPanel`'s *"Pressure → Opacity"* becomes *"Pressure → Flow"* — a label
   corrected rather than a control added, since that row always drove the dab's coverage and coverage
   is what `flow` is now called.
   Pinned by `BrushEngineLogicTests`' six new tests — the crossing reads the cap and not `1 - (1-o)²`;
   flow builds up where a stroke crosses itself while **every pixel** of a capped render is that
   fraction of an uncapped one (which folding the cap into a stamp cannot do); a 50% eraser takes away
   50% on the replay tier *and* on the live one; a scattering, size-modulated stroke loses no ink to
   the merge; the clean-cut gate refuses a brush whose merged alpha is short of 1; and a `.multiply`
   stroke blends once where it crosses itself. All six were mutation-tested against four separate
   mutations before being trusted.
   **Four of this section's instructions did not survive contact.**
   - **The merge is given no bounds, and could not safely have been.** The design was to derive a
     conservative box from the samples and the brush (`Brush.maximumDabExtent`). `ResponseCurve`
     deliberately does not clamp its output — §6's own doc says so — so an overshooting handle on a
     `size` row exceeds `Σ|amount|` and the box is not a bound at all; and a box that is too small does
     not cost memory, it **clips ink**. What shipped collects the dabs and takes the union of the
     rectangles they actually painted, which is exact by construction, needs no arithmetic in
     `PosedDabTarget`, and costs ~100 bytes and one array append against ~5.5 µs of drawing per dab.
   - **A fractional clip is not free, and that is where the whole change nearly went wrong.** Clipping
     the layer to the dabs' exact union antialiases the group's outermost row of pixels — MEASURED at
     alpha 193 where 255 was drawn, which four existing zero-tolerance parity tests caught as *ink lost
     at a seam*. `.integral` on the clip fixes it, and with it a buffered stroke is **byte-identical**
     to a directly stamped one at opacity 1 under `.normal`, which the design had expected to differ by
     one or two LSB.
   - **`VectorEraser.supportsCleanCut` needed a line deleted, not rewritten.** It already guarded on
     `opacity · values.flow`, which *is* the merged alpha; the second guard, on the deleted output,
     would have read a base that is now always 1 and passed unconditionally. `supportsSplitting` needed
     nothing at all — it never read opacity.
   - **No XCUITest named `pressureOpacitySlider`.** The identifier appeared once, in the panel that
     defines it.
   **The panel gains no slider, and that is §7's ruling reaching back into this stage.** A base
   slider for flow was built and removed: every brush parameter belongs to the brush editor, so the
   panel's `base + amount == 1` convention holds for `flow` exactly as it does for `size`, and flow's
   base is reachable when §12 stage 10 lands and not before. The side toolbar is untouched — size and
   opacity, set by the artist, and nothing else.
   **Two divergences the `.preview` tier had are closed by the same change**: `strokePolyline`
   multiplied in the per-dab `opacity` output that no longer exists, and its eraser arm punched at full
   coverage whatever the eraser's opacity was. Both now read the stroke's own opacity, so the tier that
   was *accidentally* already §2.11 — one `strokePath` call cannot double-darken — and the `.full` tier
   agree.
9. **The library: groups, and the tip generator.** §8. The group tree reusing the layer tree's; the
   procedural tips for Basics, Sketching, Inking and Painting; the variant set §8.5 needs. **`BrushLibrary`'s
   five presets are deleted here, not deprecated.** The generator is a build-time tool whose output is
   committed, not a runtime cost — a tip is a small alpha bitmap and generating it per launch buys nothing.
10. **DONE — the editor.** §2.24, §7 and §7.2. A full screen rather than a panel; the outputs are the
    index, grouped, each expanding in place into a base slider and however many chains drive it; a chain
    is an input and an ordered list of modules the artist adds to, reorders and removes (§2.28, which
    landed the day after and replaced the fixed curve-then-gain shape this stage first shipped); and a
    drawing pad the artist can try the result on. Taken **out of order** — §12 put it after the library
    and the library is stage 9 — because §2.24 arrived from the owner and the shell it replaced was one
    day old. Nothing here depends on the group tree: a brush the artist makes still lands in a group
    when stage 9 gives them one.
    Pinned by `BrushEditorLogicTests` (15) — every `BrushOutput` reaches a control, every base keypath
    moves what `dabValues` resolves, the curve's axis is fixed and a dragged key moves while its
    neighbour does not, a key cannot be dragged onto its neighbour, an empty curve materialises to the
    identity **bit-exactly**, a curve taken below two keys is emptied rather than left a constant, the
    row accessors re-mint §6.2's channels, every module kind the menu offers reads back as itself, a
    reorder re-mints the randomisers' planes, and `BrushChainLimit` is down to the one place a chain
    still cannot reach — and by `BrushEditorUITests` (5), every one of them from a cold launch with the
    library file deleted: an edit reaches the ink on the canvas, a curve node moves on screen while the
    other node does not, **a module can be added, reordered and removed and each changes the ink**, an
    edit survives a **relaunch**, and the pad draws with the brush as edited rather than as it was when
    the screen opened.
    **Three of §7.2's instructions did not survive contact and §7.2 records all three** — the pad cannot
    be a `StrokeCanvasView`, the curve's y axis is the *shaped reading's* `0…1` rather than the output's
    range, and neither existing curve control could be pointed at a `ResponseCurve`. **Two defects were
    found only by driving it**: an identifier on the screen's root container that made every control
    below it unreachable, and an edit that survived the editor and not the process.
11. **The Texture group's CC0 assets.** §8.3 and §8.4 — last of the shipped set, because it is the only part
    with a licensing step, and §8.3's verification happens at this point rather than earlier.
12. **Three formats, and it stays last.** Owner: *"support of clip studio paint, abr, procreate brushes
    are good enough for now i think"*, and on timing, *"Your choice"*. **Last**, and the reason is
    sharper than the original one: the model moved twice on the day this was scheduled — §2.28's module
    chains and §2.29's curved scale modules — and **an adapter aimed at a moving target is written
    twice**. The original reason stands too: a parser with no image primitive behind it shapes its model
    around the wrong renderer. Reached from the brushes menu's **Add brush** (§2.20), which §7.1 gives
    two arms — create manually, or import.

    **§2.21 makes this an adapter rather than a parser, and the adapter is the hard half.** Each
    format's parameter set only partly overlaps §6's, in both directions: Procreate has Wet Mix and
    Bleed and this engine has neither; this engine has `density`, noise octaves and orderable chains and
    none of them do. Every non-overlapping setting is a decision, and §2.21 already rules which way it
    goes — **what the file states becomes modules, what it does not state stays at the neutral and is
    never invented**.

    **All three are undocumented and reverse-engineered, so the stage opens with a survey against real
    files, not with a parser.** What is known going in, to be verified rather than trusted:
    - **`.abr`** — proprietary binary in several incompatible versions; the modern ones carry
      Photoshop's serialised descriptor structure (diameter, angle, roundness, spacing, hardness and the
      dynamics blocks) alongside compressed sampled bitmaps. GIMP and Krita both read it.
    - **Procreate `.brush` / `.brushset`** — a zip holding a binary-plist archive of the Brush Studio
      settings plus shape and grain PNGs. **The closest fit to this engine**, because §7.2's editor was
      designed against Brush Studio.
    - **Clip Studio `.sut`** — a SQLite database, parameters in tables and materials as blobs. The
      strangest container and the most *readable*, being a real database rather than a serialisation.

    **Test files are a real dependency and are not urgent.** A reverse-engineered parser can only be
    trusted against files somebody actually uses, and free packs are simple enough that an adapter can
    pass on them and still fail on an elaborate commercial brush. The owner can supply Procreate packs
    but it costs them time, so the instruction is to source freely-licensed samples first and ask only
    if those prove too thin. **§8.3 is why importing matters at all**: an artist's bought pack is theirs
    to use and simply cannot travel inside the binary, so the import path is the only lawful route for
    most of what exists.

---

## 13. Open

- ~~**Whether a modulation's `amount` may itself be modulated.**~~ **Answered and built — a row carries a
  second input, and its reading multiplies the first.** §2.22.

- **What a brush that is not a dab walk needs — §2.23's fill brush and its siblings.** Unscheduled by
  the owner and deliberately not designed here, because a mechanism nobody has measured a need for is
  what §9.2 says not to add. What is written down is only the seam it must arrive through: the two
  sites where a stored stroke becomes ink. The question left open is whether the discriminator is a
  case on `BrushTip` (which already makes illegal states unrepresentable and would make a third
  behaviour a compile error at both sites) or a field beside it — and that is answerable only against a
  real second behaviour, not before.

- ~~**Where §2.24's chain and §6's rows disagree, and what closing the gap would cost.**~~ **Closed by
  §2.28, built 2026-09-05, and three of its four entries are gone rather than reworded.** A modulation is
  an input and an ordered `[BrushModule]`, so the module order is the artist's, a chain may carry as many
  curve ramps as it likes and as many randomisers as it likes. `BrushChainLimit` is one case now —
  **several chains on one output are summed, not chained** — which is a fact about how the *matrix* adds
  outputs rather than about how one chain evaluates, and closing it would be a change to the former.
  Two things the build settled that the entry did not predict. **The third module is the second with a
  random input**: `.random` is a `BrushInput`, so `.scale(.random(…))` *is* the randomiser and a separate
  case would be two spellings of one behaviour — the editor offers three kinds and the storage has two.
  And **`amount` multiplies last now**, `amount · (chain)` where the row was `(amount · curve) · second`;
  floating-point multiplication is not associative, so the two differ by an ulp of the *contribution* for
  a chain carrying a scale, and identically for every chain that does not — which is every shipped preset,
  pinned digest-for-digest against a worktree at the commit before.
  **What it cost is MEASURED, not assumed** — PERFORMANCE.md §11.2b. An empty chain is free, a module is
  ~0.06 µs, a shipped preset's whole re-walk went **5.65 → 5.89 µs a dab (+3.3 to +4.3% over two
  independently taken pairs)**, and an **octave is 0.24–0.26 µs**, the steepest purchase on the path,
  which is why the count caps at 8.

- **Whether the octave cap of 8 is the right number, and whether a falloff above 1 should ever be
  reachable.** Both are INFERRED from arithmetic rather than from a drawing. The cap is where λ/2ᵏ falls
  below the tightest spacing the app can walk (0.027 widths against 0.02 at §2.17's shipped λ of 3.5), so
  every octave past it is per-dab hash noise wearing a wavelength's name — but nobody has drawn with
  eight, and the honest test is a contact sheet rather than an inequality. The falloff is clamped to
  `0…1` because above 1 the *finest* octave is the loudest, which is a high-pass and a different feature;
  §8.4's refuted spectral slope is the neighbouring idea and the reason to be careful about reopening it.

- **A brush imported into one document and used in another.** §12 stage 6 settled where the table lives
  (`brushtable.json` in the package root) and made a document self-contained for the tips its own ink names,
  but the *shared* library is still a flat directory: two documents that import the same PNG under different
  generated file names carry two copies, and a document opened on a second device restores its tips into
  that shared directory by file name with no check that the name means the same picture. Nobody has hit it,
  and §12 stage 9's group tree is where the library stops being flat.
- ~~**What the per-stroke buffer costs at the owner's canvas size.**~~ **MEASURED, §12 stage 8.**
  `DabCostBench.testWhatTheStrokeGroupCosts` stamps 200 strokes of 2,301 dabs each into a fresh
  2048² `RasterLayerTexture` two ways — through `stampStroke`'s group, and by replaying the very same
  dabs straight in with no group — and reports **852 µs a stroke, 6%** (2,643 ms against 2,813 ms) in
  the simulator. That is 0.37 µs a dab on a stroke far longer than an artist draws, and it buys the
  ruling; §2.11 accepted a cost and this is the number. The one term it does *not* bound is a stroke
  whose painted box is the whole canvas — a corner-to-corner diagonal at 16383² makes the transparency
  layer canvas-sized — which is inherent to a per-stroke buffer rather than to this implementation of
  one, and nobody has drawn that stroke.
- **Every CC0 claim in §8.3 needs re-checking against its source before an asset is committed**, and
  nobody has done that yet. The two that matter are GIMP's `data/brushes` — whose own licence file admits
  older files predate its CC0 policy, so it is a per-file question — and the OpenGameArt set, hosted by a
  third party that can relicense or pull it.
- **Whether the Texture group is worth its licensing step at all.** If §8.4's generator turns out to make
  credible grunge, the CC0 dependency disappears and §12 stage 11 with it. Nobody has tried.
- ~~**What the live tier does about `taper`.**~~ **Answered by §12 stage 7, and the answer is
  asymmetric.** A replay measures the stroke's own length and `stampStroke` passes it, so a taper row
  works there; it is measured **only when a row asks for it**, because it is a second flattening pass
  over the curve and no other brush should pay. The live walk stamps as the pen moves and genuinely
  cannot know, so `taper` answers its neutral — which is 1, *mid-stroke*, so a tapering brush draws its
  live preview un-tapered and the committed vector stroke tapers. `RasterVectorParityLogicTests`
  compares two replays, so it does not see this; the divergence is between the pen and the ink, it is
  confined to brushes that taper, and on a **raster** layer it is permanent because the live dabs are
  the cel. Nothing in the shipped set tapers yet. The fix, when one does, is not to guess a length
  live: it is to re-stamp a raster stroke from its fitted samples at lift, which is a change to the
  raster commit path rather than to the funnel.
- **How an angle channel travels through a map that is not an affine.** `StrokeSamples.transformed(by:)`
  turns azimuth by an affine's polar rotation, but an interpolation lattice warp has no single rotation
  and would need the *local* Jacobian per sample. It carries the angle unchanged today, which is stated at
  both call sites rather than defaulted. **Stage 7 shipped the reader** — a `tiltDirection` row on the
  `angle` output — so the cost of being wrong is no longer zero for a brush that uses one. It is still
  zero for every brush in the shipped set, and the cost of guessing is still a second definition to keep
  in step, so this stays open rather than being answered on no evidence.
- **What §6's colour outputs cost the dab caches, unmeasured.** `DabGradientCache` is keyed on the
  dab's RGB and holds 32 entries; `DabImageCache` on the tip, the colour and the size octave, and a miss
  there is a MEASURED 162 µs bitmap build against 5.5 µs for a hit (§3.5). A hue/saturation/brightness
  row changes the colour per dab, which is precisely the *"rainbow brush stamping a new colour per dab"*
  `DabGradientCache`'s own doc names as its pathological case. `BrushStamper` guards the shift on a
  comparison, so a brush that does not ask pays nothing — but nobody has taken the number for one that
  does, and PERFORMANCE.md's rule is that a figure carries MEASURED or INFERRED. The obvious mitigation
  if it bites is to quantise the shifted colour so consecutive dabs share cache entries; it is not built,
  because a mechanism nobody has measured a need for is the thing §9.2 says not to add.
- **Whether the refit tolerance is one constant or scales with zoom.** Still open, and stage 0 sharpened
  it rather than answering it. The tolerance is in canvas points, so zooming *out* is the dangerous
  direction, not in: at 16383² the artist works at `fitScale` 0.047, one screen point is 21 canvas points,
  and input jitter of a tenth of a screen point is 2 canvas points — eight times the tolerance, so the fit
  stops compressing anything at all. PERFORMANCE.md item 3 is the same finding wearing the gate's clothes.
  INFERRED from the fit's rule and `fitScale`; nobody has drawn on a 16k canvas and counted.
- **What per-sample noise the digitiser actually delivers.** Stage 0 turned out to depend on it and
  nothing in the repo measures it. A deviation fit compresses *correlated* tremor (a hand) and cannot
  compress white noise (a bad digitiser), where the sample gate — a distance rule — could not tell the
  two apart. MEASURED on the test fixture: the same 0.4 pt amplitude stores 193 of 1201 samples when it is
  spread over ten samples and **877** when it is drawn independently per sample. Physiological tremor is
  8–12 Hz against a 120 Hz sampler, so the first is the right model, but that is a physics argument rather
  than a measurement of this hardware.
