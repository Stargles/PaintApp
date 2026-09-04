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

**2.6 No barrel roll.** Owner: *"For memory, no barrel roll."* Apple Pencil Pro rotation is not a sensor.

**2.7 No tilt now, and the architecture accommodates it without a refactor.** Owner: *"i may eventually
add pen tilt in the future, so design the architecture so that if it eventually does get added, it already
accommodates it smoothly without needing intensive refactors."* Neither tilt angle nor tilt direction ships
as a sensor, and until one does the app has no brush that shades broadly when the Pencil is leaned over —
no charcoal, no soft graphite edge. **§5.5 is the seam, and it is a build requirement of this item rather
than a note for a later one.**

**2.8 The sensors are pressure, stroke direction, taper distance, random, and velocity.** Direction is
the brief's *"rotation of your brush follows your brush's painting direction"*. Taper distance is
position along the stroke. Velocity is the only one of the five that costs storage.

**2.9 Brushes are deduplicated into a document-level table.** Owner: *"deduplicating into a document
level table is preferred."* A stroke holds a small index, not a `Brush` by value.

**2.10 A brush edit does not change strokes already drawn, and there is an explicit verb that applies it
to them.** Editing mints a new table entry; existing strokes keep the entry they were drawn with. A
separate command re-points a selection, a layer, or the document at the edited brush, as one undo step.

**2.11 Opacity and Flow are separate controls, and the per-stroke buffer they require is accepted.**
Opacity caps what the whole stroke can reach however often it crosses itself; Flow is what one stamp
lays down. The stroke composites into its own buffer and merges at pen-up.

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
brush widths.** §2.13 rules that a per-dab random is `hash(strokeSeed, arcLength)`; the wavelength makes that
value band-limited rather than white — it interpolates between hashed lattice points λ of arc length apart,
and λ = 0 is a fresh draw per dab. Nothing about §4 changes: there is still no sequence and no phase, so a
value survives a split, a refit, a spacing edit and an eraser punch for the same reason. **λ is what
separates a stipple from a segmented line.** At λ = 0 ten overlapping dabs cover every point, so dropping
half of them only roughens the edge; at λ ≈ 3–4 widths a contiguous run drops and the line breaks into the
long arcs the owner picked out of the comparison sheet. One output may carry several `random` rows at
different λ, which is how a rough nib gets slow thick/thin variation and fine edge fuzz out of one input
with no spectral-slope parameter.

**2.18 `density` is an output — the probability that a dab is stamped at all.** The dab is skipped when its
random draw exceeds it. Nothing special-cases pressure: the owner's *"at very low pressure, segments of the
brush aren't painted (its noisy), creating a sort of segmented lineart filled with gaps"* is `density ←
pressure`, one row of §6's matrix like any other. **The coherence lives in the draw, not in the value
compared against** — modulating `density` by a coherent random while drawing white noise gives a thinned
speckle rather than gaps — so λ sits on the `density` row itself.

**2.19 A taper is low pressure, so `density ← pressure` is a threshold curve rather than a ramp.** Density
holds flat at 1 above about a third of full pressure and falls below it. Without that the dropout eats the
point of every tapered stroke and a hair spike ends in gaps; with it a taper keeps its point while a stroke
drawn genuinely light breaks up along its whole length. That is the shape of the curve §6 already gives
every modulation, not a mechanism of its own.

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
stays a list of **on-curve points** — `VectorSample`, position and pressure, exactly as before — and
what changed is *which* samples become points. A sample is kept when dropping it would move the stored
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

### 3.5 Stamp

`DabTarget` gains an image primitive beside `stampCircle`. `stampApproximateSquare` — sixteen
gradient-filled circles faking one square dab — is deleted and `.square` becomes a built-in texture. The
primitive needs a tinted, rotation-bucketed image cache with a hit-rate test written in the same change,
the way `DabGradientCache` has one; per-dab `CGImage` construction otherwise dominates everything.

**`BakedDab` gains an angle**, and `DabPose` must rotate it. Without that, a sprite brush under a
rotating keyframe keeps its stamps upright while the stroke turns.

---

## 4. Randomness — hashed by arc length, never a stream

The brief's constraint is that splitting a stroke must not restart its randomness. Today's engine is a
sequential `splitmix64` seeded per stroke, kept in phase by `DiscardedDabTarget`, which **computes dabs
outside a piece's visible range and throws them away** so the sequence does not shift. That works, and it
carries two implicit rules: every draw comes from the passed-in RNG, and a dab draws the same *number* of
values whether or not it is drawn. A single conditional draw desynchronises everything after it, and the
symptom is not a crash — it is half a split stroke's ink moving.

**Splitting is one of four ways that stream goes out of phase, and this overhaul adds the other three.**

| | why the stream shifts |
|---|---|
| a stroke is split | the surviving piece starts at a different dab index |
| **the path is refitted** (§3.3) | dab positions and dab *count* change |
| **a brush's spacing is edited** (§7) | every dab index shifts |
| the eraser punches, or an in-between re-derives the walk | the walk is rebuilt from different geometry |

No seed-inheritance rule survives all four. So:

> **Every per-dab random value is `hash(strokeSeed, arcLength)`.** There is no sequence and no phase.

A dab 43.2 pt along the stroke draws the same scatter, angle jitter and flow jitter forever — whichever
half of a split it lands in, whatever the refit did to the point count, whether it is dab #200 or #150.

**Two fields on the stroke, both per-stroke rather than per-sample**: a `seed` that is **inherited on
split rather than regenerated**, and the `arcOffset` of this piece from the original stroke's origin.
`DabLattice`'s existing parent-seed propagation is the same idea and becomes a two-field copy.

**`DiscardedDabTarget` is deleted.** It exists only to keep a sequential RNG in phase; with no stream
there is nothing to keep. Dabs outside a piece's range are skipped outright. Confirm nothing else leans
on it before removing — its `DabTarget` conformance may be load-bearing for a test double.

**What is not preserved, correctly**: editing a brush's spacing changes which arc lengths carry a dab, so
different randoms land. Those are different dabs. What is preserved is that no *existing* dab's randomness
moves.

**Arc length is measured in rest space**, so this composes with KEYFRAMES §4.2's rest-space dab bake
rather than fighting it: a posed or keyframed stroke's randomness is frozen by construction, which is the
property the grain boil needed and never had.

---

## 5. What a point stores

### 5.1 The record

| channel | bytes | |
|---|---|---|
| x, y | 4 | unchanged — `Int16` quarter-pixel, offset from the run's origin |
| pressure | 1 | unchanged |
| Δt from the previous point | 1 | **new** — the only cost of §2.8's velocity, and it buys retiming later |

**Six bytes a point against five**, and `PackedSampleRun`'s `.float32` mode for `precise` strokes widens
the same way.

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

### 5.4 The brush table

`VectorStroke` stores a whole `Brush` by value today. §6's `Brush` is substantially larger, and a cel
shaped like real artwork holds ~190 strokes. A document-level table with strokes holding an index turns
~500 bytes a stroke into ~2 — §2.9.

**§2.10 makes the table grow**: an edit mints an entry rather than mutating one. A sweep on save drops
entries no stroke references, or a heavily tuned document accumulates dead brushes forever.

### 5.5 The tilt seam — §2.7, and a build requirement of this item

Adding tilt later must be additive at every layer. Four seams, and each is cheaper to build now than to
retrofit:

**A channel set in the run header, not a fixed record.** `PackedSampleRun` carries a small bitmask naming
which per-point channels are present and derives `bytesPerSample` from it. Adding tilt is then two bits
and two arms in the pack/unpack switch — **no format version, no migration, no decode default**, because a
run written without tilt simply has those bits clear. The mask costs one byte per *run*, not per point, so
§5.1's six-byte record is unaffected. This also subsumes the `.quarterPixel` / `.float32` mode flag, which
is a channel-width choice wearing a different hat.

**Struct-of-arrays in memory.** A stroke holds parallel arrays — positions, pressures, and one per optional
channel. An absent channel is an empty array and costs nothing; adding one adds an array rather than
widening every `VectorSample`. It is also the shape the packer already wants.

**One evaluation funnel, with a defined neutral.** Every sensor resolves through a single
`value(of: BrushInput, atArcLength:)`. Adding `.tiltAngle` / `.tiltDirection` is one case in one switch —
**provided that funnel answers a defined neutral when the stroke carries no data for the channel asked
for.** Without that, the day tilt ships every stroke drawn before it renders wrong or traps. Neutral is
the Pencil held upright: full altitude, azimuth zero, and no modulation effect. Build the neutral now,
with the funnel, and pin it: a brush reading a channel the stroke does not carry must render identically
to the same brush with that modulation removed.

**Do not delete the capture.** `StrokeInput` already carries `altitude` and `azimuth` from the hardware and
they currently reach only the action recorder. That is exactly the shape a cleanup pass removes as dead
code, and this repo has a standing instruction to delete replaced paths rather than leave them beside new
ones. **This is a named exception**: the capture stays, because it is the half of the seam that cannot be
rebuilt from a decision — every other part of tilt is code, and this part is a hardware reading that has to
be taken at the moment of the touch.

---

## 6. The brush model — a modulation matrix

Every parameter is `base value + [modulation]`, where a modulation is **(input, curve, amount)**. That is
the brief's *"every parameter should be able to be sensor driven"*, and it is the CSP model.

**Inputs** (§2.8): `pressure` · `direction` · `taper` (distance along the stroke, from either end) ·
`velocity` · `random`.

**Every `random` modulation carries a wavelength λ, expressed in brush widths so a brush looks the same at
any size** — §2.17. Its value interpolates between hashed lattice points λ of arc length apart, which is
still exactly §4's `hash(strokeSeed, arcLength)`; λ = 0 is a fresh draw per dab.

**Outputs**: `size` · `opacity` · `flow` · `angle` · `roundness` · `spacing` · `scatter` · `density` ·
`hue` / `saturation` / `brightness` shift · `hardness` (procedural tips only).

`density` (§2.18) is the probability that a dab is stamped at all, and it is the one output whose λ belongs
to the **row** rather than to a modulation entry, because what has to be coherent is the draw.

Angle has three contributions that sum: a base angle, direction-follow as a 0–100% amount, and jitter.

`BrushShape` + `customTextureFileName` — a case and a parallel optional field that can disagree — collapse
into one payload-carrying enum, so the illegal states stop being representable and `stampDab`'s switch
stays exhaustive:

```swift
enum BrushTip: Codable, Equatable {
    case round                    // procedural, hardness gradient
    case stamp(BrushTextureRef)   // imported, or a user PNG
}
```

`Brush`'s flat scalars group into sub-structs the way `dynamics` and `blendMode` already are, each with a
`static let default` and defaulted decode. `Brush`'s `Codable` is compiler-synthesized today, so every
new flat key is a decode-compatibility question; a nested field with a default is not.

---

## 7. The editor

A Procreate-shaped panel: parameter groups, each row a base slider, each row able to gain a modulation —
pick an input, draw a curve, set an amount.

**The curve editor already exists.** TODO (38) built bezier tangent handles with a tap grammar for the
timeline's graph band; a pressure curve is the same control over a different domain, and reusing it is
what keeps this from being a second curve implementation.

Parameters with no UI at all today — `scatter`, `rotationJitter`, `hardness`, `blendMode` — get one here.
Edits currently apply to a live copy and are lost when the preset changes; §2.9's table plus §2.10's
minting is what makes an edit persist.

---

## 8. The library, the groups, and the default set

§2.16.

### 8.1 Two collections, and they are not the same thing

The **library** is app-level: the brushes the artist can pick, their groups, and the ones they make. It
persists across documents. The **document table** (§5.4) is per-document: the brushes the strokes in *this*
file were actually drawn with.

Both are needed, and the pair buys something neither does alone. Because a stroke is frozen to the brush it
was drawn with (§2.10), **a document that carries its own table is self-contained** — it opens correctly on
a device whose library has never held that brush. That falls out of §2.9 and §2.10 rather than costing
anything.

### 8.2 Groups are the layer tree again

`BrushLibrary` is a flat array of presets plus a custom-brushes directory; there is no folder concept. The
layer tree is already a complete, tested, persisted, ordered hierarchy with folders, and it is the third
feature to want that shape — TODO (30) makes the same observation about organising documents. **Reuse it
rather than hand-rolling a third tree.**

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
roughness, so there is no octave or spectral-slope parameter.

So: **generate Basics, Sketching, Inking and Painting; source CC0 only for Texture**, where scanned grunge
and splatter are genuinely hard to fake.

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

### 8.6 The set

Five groups; **24–30 brushes**, which is the scale Photoshop now ships by default and well inside Clip
Studio's 42. Not Procreate's 200+, which is a decade of accretion.

| group | holds |
|---|---|
| **Basics** | round soft, round hard, square, chisel |
| **Sketching** | pencils — hard, soft, blunt, textured |
| **Inking** | technical pens, brush pen, and **the rough ink nib** §8.4 names |
| **Painting** | opaque round, flat, bristle, blender |
| **Texture** | grunge, splatter, stipple, chalk — the CC0 group |

Erasers are not a group: the eraser *is* a brush (§11), so every one of these erases already.

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

---

## 10. The deletion ledger, and what makes the result flexible

§2.14. **Every stage of §12 deletes its predecessor in the same change that replaces it.** A removal
deferred to a cleanup pass is exactly how legacy accumulates, and there is no cleanup pass scheduled.

### 9.1 What must not exist afterwards

| gone | replaced by | stage |
|---|---|---|
| ~~`StrokeSampleGate`~~ **gone** | `StrokePathFit` + `StrokePath` — §3.3, §5.3 | 0 |
| `DiscardedDabTarget` | hashed randomness has no stream to keep in phase — §4 | 1 |
| `BrushGrain`, `noiseValue`, `grainAlphaMultiplier`, the Grain Depth slider, the `supportsCleanCut` grain veto | nothing — §9 | 2 |
| `stampApproximateSquare` | `stampImage`; `.square` becomes a texture — §3.5 | 3 |
| `PackedSampleRun`'s fixed record and its `.quarterPixel` / `.float32` mode flag | the channel set, which absorbs the width choice — §5.5 | 4 |
| `BrushShape` + `customTextureFileName` as a separable pair | `BrushTip`, one payload-carrying enum — §6 | 5 |
| `VectorStroke`'s by-value `Brush` | a table index — §5.4 | 6 |
| `BrushDynamics.sizeFraction` / `.opacityFraction`, the two hardcoded linear pressure blends | the modulation matrix — §6 | 7 |
| `Brush`'s flat scalars | grouped sub-structs with defaulted decode — §6 | 7 |
| `BrushLibrary.defaults` — softRound, hardRound, pencil, pen, square | the generated and sourced set, in groups — §8 | 5 |

**No decode defaults for fields that stopped existing, no format version, no migration, no compatibility
shim, and no "this used to be" comments.** Documents on the device are expendable, so the format simply
changes. The one place history is kept is this document and `git log`.

**`BrushDynamics`' two blends are the trap on that list**, because they are correct and cheap and there
will be a reason to keep them as a fast path beside the general one. Two ways to compute a dab's size is
two ways for it to be wrong, and the parity test compares tiers rather than paths, so it would not catch
the divergence.

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
- **Imported-asset lifetime is solved** — `ProjectStore` copies a custom brush's texture into the project
  and restores it on load.
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
1. **Randomness by hash.** §4. Delete `DiscardedDabTarget`. Pin the split case the brief names — a stroke
   split in two stamps the same ink as the stroke it came from.
2. **Delete grain.** §9. Independent of everything else, and it shrinks the surface every later stage
   touches.
3. **`stampImage` on `DabTarget`** + the tinted rotation-bucketed cache + its hit-rate test. `.square`
   becomes a texture; `stampApproximateSquare` goes. `BakedDab` gains an angle and `DabPose` rotates it.
4. **The sample record** — the channel set, struct-of-arrays, Δt, and velocity as a sensor. §5.1 and
   **§5.5, which is not deferrable to the stage that adds tilt**: the funnel's neutral has to exist before
   any brush reads a sensor, or it is a retrofit through every modulation instead of one function.
5. **`BrushTip`**, and the renderer finally reads `customTextureFileName`. User PNG stamps work: the first
   artist-visible feature, and it exercises the whole path.
6. **The brush table** — §5.4, §2.9, the save-time sweep, and §2.10's apply-to-existing verb.
7. **The modulation matrix** — `Brush` regrouped, every parameter `base + [modulation]`. §6.
8. **Opacity and Flow**, and the per-stroke buffer. §2.11. Late, because it changes the live drawing path
   and wants the rest settled around it.
9. **The library: groups, and the tip generator.** §8. The group tree reusing the layer tree's; the
   procedural tips for Basics, Sketching, Inking and Painting; the variant set §8.5 needs. **`BrushLibrary`'s
   five presets are deleted here, not deprecated.** The generator is a build-time tool whose output is
   committed, not a runtime cost — a tip is a small alpha bitmap and generating it per launch buys nothing.
10. **The editor.** §7, reusing (38)'s curve control. After the library, because a brush the artist makes has
    to land in a group.
11. **The Texture group's CC0 assets.** §8.3 and §8.4 — last of the shipped set, because it is the only part
    with a licensing step, and §8.3's verification happens at this point rather than earlier.
12. **`.abr`, then Procreate `.brush`.** Last. A parser with no image primitive behind it shapes its model
    around the wrong renderer.

---

## 13. Open

- **Where the brush table lives** — the project package beside `brushes/`, or inside the document — is
  unsettled, and interacts with §2.10's minting and with a brush imported into one document and used in
  another.
- **What the per-stroke buffer costs at the owner's canvas size** is unmeasured. §2.11 accepts the cost;
  nobody has taken the number, and PERFORMANCE.md's rule is that a figure carries MEASURED or INFERRED.
- **Every CC0 claim in §8.3 needs re-checking against its source before an asset is committed**, and
  nobody has done that yet. The two that matter are GIMP's `data/brushes` — whose own licence file admits
  older files predate its CC0 policy, so it is a per-file question — and the OpenGameArt set, hosted by a
  third party that can relicense or pull it.
- **Whether the Texture group is worth its licensing step at all.** If §8.4's generator turns out to make
  credible grunge, the CC0 dependency disappears and §12 stage 11 with it. Nobody has tried.
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
