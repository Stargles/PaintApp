# Vector Interpolation — Design Brainstorm

**Status: design only. No code written.** The four highest-leverage questions are answered and
recorded as decisions in §10; three secondary ones remain open but do not block prototyping.

This is the pre-implementation brainstorm for interpolated in-between frame generation on vector
layers. It surveys what the codebase already gives us, weighs three candidate engines against the
requirement that keyframes are *independently drawn*, and proposes an architecture.

Companion docs: [VECTOR_INTERPOLATION_IMPLEMENTATION.md](VECTOR_INTERPOLATION_IMPLEMENTATION.md)
(the phased build plan), [VECTOR_INTERPOLATION_HANDOFF.md](VECTOR_INTERPOLATION_HANDOFF.md) (live
session state — **read this first if you are resuming work**),
[VECTOR_ERASER_PLAN.md](VECTOR_ERASER_PLAN.md) (whose §2.1, §2.2, §3 and §11 decisions this builds
directly on), [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md).

---

## 0. The brief

*The product owner's original specification, recorded verbatim in substance and lightly edited for
clarity. **The rest of this document references these numbers** ("requirement 5", "note 1", "edge
case 3"), so this section is the key to reading it. Nothing here may be dropped without the product
owner's say-so.*

### Goal

Allow animators to take two or more keyframes and automatically generate in-between frames, or
modify frames to be earlier or later in the interpolated timeline.

### The workflow, as specified

1. There is an **interpolate mode** the user can switch into.
2. In this mode, holding down an animation block offers **"set as reference"**, which highlights the
   reference block(s) **yellow**.
3. The user then selects any animation block and taps an **"interpolate"** option that pops up. The
   frame is interpolated from the frames around it.
4. While in this **temporal interpolate edit stage**, the user can drag a **slider** left or right
   between the neighbouring reference frames — Keyframe 1 (*t*=0.0) and Keyframe 2 (*t*=1.0) — to
   dynamically preview and adjust how close the in-between frame is to either keyframe. **Onion skin
   is displayed** during this stage.
5. Also in this stage, the user can use a **liquify / mesh-distort tool** (yet to be added), and add
   new paint or eraser strokes to make manual adjustments. They can also **lasso select and resize**.
   They can then adjust the slider again, or do anything else interpolate mode offers — **it must be
   seamless**.
6. The user can select a special **"guide stroke" tool** that draws a path connecting points in space
   between keyframes. The stroke captures **stylus speed and timing** to dictate both the geometric
   arc and the physical velocity (easing) of secondary motion — hair, clothing — between the two
   frames. The guide stroke is physically a vector object that is **normally invisible but visible
   whenever interpolate mode is on**.

### Notes (referenced elsewhere as "requirement N" / "note N")

1. In-between frames can be applied to **any** frame, even one that already has a drawing. Example:
   interpolate A and C as references to create B; then modify A or C; then interpolate B again to
   slide it left or right in time, and it adjusts accordingly. The same must work if the user draws
   A, B and C by hand and then interpolates B to nudge its timing.
2. The slider must give **real-time feedback**. This may imply a GPU implementation, though the cost
   of interpolation is not yet clear.
3. **Multi-keyframe support:** reference multiple keyframes (e.g. frames 1, 2, 3, 4) and insert
   intermediate points (like frame 2.5) to maintain non-linear motion, acceleration, and
   ease-in/ease-out.
4. **Colour & colour-coding integration:** full support for colour transitions and colour-coded
   stroke tagging, letting the artist manually assign matching colours to strokes to tell the
   algorithm which part morphs into where.
5. **Multi-layer references.** Selecting reference frames across layers may be valuable. If a fill
   layer is being interpolated, it should be interpolated using both the fill layer and the lineart
   layer. Another case: an arm on one layer and clothing around it on another.
6. The guide stroke must be **modifiable during interpolate mode**, with live feedback on the
   interpolated frame: geometric adjustment of the curve (Bézier-like), and timing adjustment —
   possibly dragging the interpolated frame's node along the curve.
7. There must be a way to use a **single guide stroke across multiple interpolated frames** — some
   way to fetch another frame's guideline into your frame before interpolating.
8. **Full undo.**
9. This is a **vector-layer-exclusive** feature.

### Key technical & UX edge cases (referenced as "edge case N")

1. **Eraser & masking strokes.** Vector eraser strokes lower the alpha of underlying paint. Needs a
   clean answer for when an eraser exists on Keyframe 1 but disappears entirely by Keyframe 2.
2. **Topological mismatches.** Keyframe stroke counts and point densities will not match (e.g. 1
   stroke morphing into 3). The program will be interpolating between **two independently drawn
   drawings**.
3. **Vector fills & layering.** Interpolating closed fill-bucket regions and layer blend modes
   cleanly, without muddy colour transitions or artifacts. Compositing layers (After Effects-style
   post-production) are a future addition and should be interpolatable too.
4. **Range interpolation** — interpolating a range of frames at once — is a possible future version.
   Not in this run, but the architecture should not need a major refactor to add it.
5. **Blank vs. non-blank target.** Interpolating onto a blank frame must generate the frame.
   Interpolating onto a non-blank frame must keep it and modify it as the slider moves. There may be
   cases where the interpolated frame is too ambiguous not to partially generate parts of it.

---

## 1. The central problem

Every published inbetweening system that works well assumes **one-to-one stroke correspondence**:
each stroke in keyframe A maps to exactly one stroke in keyframe C, and the inbetween is that stroke
somewhere along the way. CACANi is built on this; so is most of the stroke-matching literature.

The requirement here breaks that assumption on purpose:

> "In fact the program will be interpolating between two independently drawn drawings."

Two drawings made independently by a human have *no* stroke correspondence. A forearm drawn with one
confident stroke in A is three overlapping searching strokes in C. A hatching pass has 40 strokes in
A and 31 in C, in a different order, at different angles. Any engine whose first step is "match
stroke i to stroke j" has already lost, and it loses in the most visible way possible — a bad match
does not degrade gracefully, it produces a stroke that flies across the canvas.

**So the engine's primary motion model cannot be per-stroke correspondence.** Correspondence can be
a refinement layered on top where it is confident, but it cannot be the substrate.

This one constraint drives essentially every decision below.

---

## 2. What the codebase already gives us

Surveyed at `72ac6a9`. This is unusually good ground to build on — several decisions taken for the
eraser turn out to be exactly what interpolation needs.

| Asset | Where | Why it matters here |
|---|---|---|
| Strokes are geometry, not pixels | [VectorStroke](PaintSoftware/Engine/VectorLayer.swift:26) | Warping is a transform on `samples`. Nothing to re-rasterize losslessly — it already re-rasterizes on every change. |
| **The eraser *is* a stroke** | [StrokeComposite](PaintSoftware/Engine/VectorLayer.swift:16) | Erasers get interpolated, warped and faded by the same code path as paint. Edge case 1 in the brief is *free* — see §7.1. This is the single biggest gift from the eraser work. |
| One z-ordered display list | [VectorElement](PaintSoftware/Engine/VectorLayer.swift:217) | An interpolated frame is just another display list. No new render path. |
| Pure geometry layer | [StrokeGeometry](PaintSoftware/Engine/StrokeGeometry.swift:30) | Already has `interpolatedSample(in:at:)`, `subdivided(_:maxSpacing:)`, `lerp`, `splitStroke`, `intersections`, arc-length reparameterisation. Resampling two strokes to a common parameterisation is mostly written. |
| Spatial index | [StrokeSpatialIndex](PaintSoftware/Engine/StrokeSpatialIndex.swift) | "What strokes are in this rect" is the query lattice binning needs. |
| `DabLattice` precedent | [DabLattice](PaintSoftware/Engine/VectorLayer.swift:99) | A stroke that renders on *another* stroke's dab lattice already exists. The idea of "geometry here, rendering authority there" is established in this codebase. |
| Structure undo | [withStructureUndo](PaintSoftware/Models/CanvasManager+Undo.swift:69) | Snapshot/restore of `[Layer]` is cheap (value types, shared class refs). An interpolation spec that lives in the layer/cel tree inherits undo for free. |
| Onion skin | [CanvasManager:294](PaintSoftware/Models/CanvasManager.swift:294) | Already exists as a toggle + opacity + a dedicated `UIImageView`. |

### Gaps found

1. **Onion skin does not handle vector cels.** [CanvasView.swift:739](PaintSoftware/Views/CanvasView.swift:739)
   renders `cels[celIdx].raster.renderToUIImage()` unconditionally — a vector cel onion-skins as
   blank. This is a prerequisite bug for step 4 of the workflow, and it is small.
2. **No timestamps anywhere in the input pipeline.** [StrokeInput](PaintSoftware/Engine/StrokeInput.swift:8)
   carries position/pressure/altitude/azimuth and no time; `VectorSample` carries x/y/pressure only.
   The guide stroke's whole premise is capturing stylus *velocity*, so this needs a new capture path
   — see §6.3.
3. **Rasterisation is CPU and it is the binding constraint.** See §8. The interpolation *math* is
   cheap; drawing the result is not.
4. **`VectorFillElement` stores its path as archived `Data`.** Warping a fill means unarchiving,
   transforming control points, re-archiving. Fine, but there is no accessor for the points today.

---

## 3. Three candidate engines

### A. Stroke correspondence + per-stroke interpolation

Match stroke *i* in A to stroke *j* in C (Hungarian assignment over a shape/context descriptor),
resample both to a common parameterisation, lerp positions, pressure and colour. This is the CACANi
model and most of the literature.

**Pros.** Conceptually simple. Exact at both endpoints. Output is a clean single stroke per input
pair — no ghosting, publishable lineart. Colour interpolation is trivial. Tiny data. Correspondence
is a natural place to hang the colour-coded tagging from the brief.

**Cons.** It is the approach §1 rules out as a substrate. Unmatched strokes have no defined
behaviour. Cardinality mismatch (1→3) has no good answer — split one stroke into three? into which
three? A confident wrong match is catastrophic rather than merely poor. Systems that ship this
successfully (CACANi) do so by controlling how the keyframes are drawn in the first place.

### B. Raster morph (dense warp + cross-dissolve)

Rasterise A and C, estimate a dense correspondence field, warp both toward *t*, dissolve.

**Pros.** Completely topology-agnostic. Handles fills, erasers, images, blend modes, *everything*,
because it works after compositing. Well-understood, and mature implementations exist.

**Cons.** The output is pixels. The brief says vector-layer-exclusive, and requires the in-between to
be editable, re-timeable and re-interpolatable — none of which survives a bake to raster. Also
produces blur/ghosting under large motion. **Rejected as the engine**, but genuinely useful as an
*automatic correspondence hint* (§5.3): a coarse optical-flow field over rasterised A and C is a
cheap way to guess the initial lattice registration so the artist starts from something close.

### C. Lattice embedding + ARAP warp — *recommended*

Group strokes into **motion groups** (a limb, a hair clump, a prop). Embed each group's stroke
vertices in a 2D quad lattice. Register group-A's lattice to group-C's. At time *t*, interpolate the
lattice (as-rigid-as-possible, so it rotates rather than shears), push A's strokes forward through it
and C's strokes backward through it, and cross-fade the two sets.

This is the architecture of Even, Bénard & Barla's *transient embeddings* system
([CGF 2023](https://doi.org/10.1111/cgf.14771), extended in
[Inria RR-9559](https://inria.hal.science/hal-04797216/file/RR-9559.pdf)), whose reference
implementation "Frite" is public. **It matches this brief unusually closely** — trajectory
constraints as Bézier curves, per-group spacing charts, real-time preview, non-linear editing in any
order, and drawing at intermediate frames are all things that system already does, which is strong
evidence the workflow in the brief is coherent rather than merely appealing.

**Pros.**
- **No stroke correspondence required.** 1 stroke → 3 strokes needs no special case: A's one stroke
  warps forward and fades out while C's three warp backward and fade in, all riding the same motion.
- Motion is *coherent*. ARAP keeps the group locally rigid, which is why the result reads as an arm
  moving rather than as one drawing dissolving into another. This is the difference between
  inbetweening and a cross-dissolve, and it is entirely down to the warp.
- **Deformation and timing are separable.** The lattice at *t* is a pure function of
  (latticeA, latticeC, t). The slider is a parameter, not a re-solve. This is what makes real-time
  scrubbing tractable and what makes "slide frame B earlier/later" trivially correct.
- **The inverse map is what makes mid-interpolation editing work.** A stroke drawn at *t* can be
  carried *back* to keyframe A through the inverse lattice transform and stored there. That is the
  clean answer to requirement 5 ("add strokes, then move the slider again, seamlessly") — see §5.4.
- Per-vertex temporal visibility handles appearance/disappearance mid-interval, covering both the
  vanishing eraser and "partial drawings".
- Guide strokes map directly onto trajectory constraints, which the system already needs.

**Cons.**
- **Cross-fading means the middle of the interval shows both drawings.** Near *t*=0.5 you see A's
  ghost and C's ghost simultaneously. For rough/blocking animation this is correct and even
  desirable. For clean lineart it is not shippable output. **This is the most important trade-off in
  the document and it is question 1 in §10.**
- Requires the drawing to be decomposed into groups. The paper does this manually. Fully automatic
  grouping is fragile.
- ARAP is a sparse linear solve. Real work, though the factorisation is computed once per registered
  pair and reused for every *t*.

### D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*

Always use the lattice for global motion. Then, for strokes that *do* confidently correspond after
the warp (same colour tag, similar shape, similar arc length, low residual once the lattice motion is
removed), interpolate them as a single stroke instead of cross-fading the pair. Everything unmatched
falls back to cross-fade.

This is the best answer to the clean-lineart problem without giving up robustness: matched strokes
produce one clean line, unmatched strokes degrade to a ghost that the artist can fix with the tools
in step 5. And it makes the colour-coded tagging from the brief do real, visible work — a tag is
what promotes a pair from "cross-fade" to "interpolate cleanly".

The lattice is what makes correspondence *tractable* here, incidentally: matching A's strokes against
C's is hard, but matching A's **lattice-warped** strokes against C's is easy, because the gross motion
has already been removed and the two are nearly on top of each other.

### The decision: C as substrate, D per group, artist-overridable

Answered in §10: **both, chosen per motion group.** Each group carries an interpolation mode:

```
enum GroupInterpolation {
    case auto        // try correspondence; fall back to cross-fade if confidence is low
    case clean       // force correspondence — one line in, one line out
    case crossFade   // force cross-fade — never attempt matching
}
```

`.auto` is the default and does the obvious thing: run the matcher, and if it produces a confident
one-to-one pairing over most of the group's strokes, interpolate them cleanly; otherwise cross-fade.
The two explicit modes exist because the artist knows things the matcher does not — a clean-lineart
arm should be forced `.clean` and reported as a failure if it can't be, while a hatching pass or a
splash of effects should be forced `.crossFade` so no effort is wasted trying to match it.

This is more work than either engine alone, but the work is additive rather than forked: **the
cross-fade path is the fallback for every group**, so it has to be correct regardless, and the
correspondence path is a per-group refinement layered on the same lattice. There is one motion model,
one lattice, one warp, and two ways to draw the result.

Phase 1 should still make cross-fade work end-to-end before the matcher exists — `.clean` simply
degrades to `.crossFade` until it lands.

---

## 4. The load-bearing decision: an inbetween is *derived*, never *stored*

Requirement note 1 and edge case 5 in the brief are the same question, and this is the answer.

**An interpolated cel does not store a display list. It stores a recipe, and the display list is
computed from it on demand.**

```
InterpolatedCel
  ├─ references: [KeyframeRef]        // which cels, on which layers, are the sources
  ├─ t: CGFloat                       // where between them (the slider)
  ├─ groups: [MotionGroupBinding]     // lattice per group, registered A↔C
  ├─ guides: [GuideStrokeRef]         // trajectory + timing constraints
  ├─ localEdits: [LocalEdit]          // artist edits, expressed in KEYFRAME space
  └─ spacing: SpacingCurve            // easing, per-group override allowed
```

Everything the brief asks for falls out of this:

- **"Slide B left or right in time"** → change `t`. Re-evaluate. That is the whole operation.
- **"Modify A or C, then re-interpolate B"** → the recipe references A and C by identity, so
  re-evaluating picks up their new content. Nothing to invalidate by hand.
- **"Edit B, then move the slider, seamlessly"** → `localEdits` are stored in *keyframe* space (via
  the inverse lattice map), so they ride the warp along with everything else. Moving the slider
  re-warps them correctly instead of stranding them where they were drawn. §5.4.
- **"Interpolate a frame that already has a drawing"** → §5.5. Two distinct modes; the existing
  drawing is never destroyed.
- **Undo** → the recipe is a value type in the layer tree, so
  [`withStructureUndo`](PaintSoftware/Models/CanvasManager+Undo.swift:69) covers slider moves, guide
  edits and group changes with no new undo machinery. Only stroke-level edits inside the interval
  need the existing `registerVectorUndo` path. §9.
- **Future: interpolate a whole range at once** → a range is N cels sharing one set of references and
  differing only in `t`. The recipe already expresses that; nothing to refactor.

The counterpart: at some point the artist wants to stop maintaining a link and just have a drawing.
That is a **Commit** action — evaluate at the current `t`, write the resulting display list into the
cel as ordinary content, drop the recipe. One-way, undoable, explicit. Never automatic.

### Why "derived" and not "generate once, then it's a normal frame"

Because generate-once makes note 1 impossible. If B is baked, then editing A cannot update B, and
re-interpolating B to slide it in time has to re-derive from scratch and *throw away every edit the
artist made*. The derived model is more work up front and it is the only one that satisfies the
brief.

---

## 5. Workflow and architecture

### 5.0 The loop in practice

The brief's six steps hold up well. Walking them with the architecture attached, plus where I'd
change or add something:

1. **Enter interpolate mode.** Mode entry is also when registration runs, so this is the moment that
   costs hundreds of milliseconds (§8). Show the grouping it inferred immediately — tinted stroke
   overlays per motion group — because the artist's first question is always "what did it decide?"
2. **Hold a block → Set as reference (highlights yellow).** Good. Two additions: references should be
   settable across *layers* at once (requirement 5 — lineart + fill together), and the highlight
   should distinguish "reference" from "reference on another layer feeding this one", since those
   read differently on the timeline.
3. **Select a block → Interpolate.** This is where **Generate vs. Reproject** (§5.5) must be two
   commands, not one. The menu can pick the likely one by whether the block is empty and offer the
   other, but they should never be silently conflated.
4. **Slider between t=0 and t=1, onion skin on.** The slider is the recipe's `t` (§4), so this is a
   parameter change, not a regeneration. Two UX notes: onion skin here wants to show *the two
   references specifically* rather than ±1 frame, and the slider should show where neighbouring
   in-betweens already sit so the artist can judge spacing — the same information the spacing chart
   on the guide stroke shows (§6.2), in a second place.
5. **Liquify / draw / erase / lasso at the in-between, then keep sliding.** Works because edits are
   stored in keyframe space via the inverse lattice map (§5.4). The thing to get right: **liquify is a
   lattice edit, not a stroke edit.** If liquify deforms stroke geometry directly it fights the
   interpolation; if it displaces lattice vertices it *is* the interpolation, and the two compose for
   free. Worth deciding before the liquify tool is designed, since it constrains that tool.
6. **Guide stroke — invisible except in interpolate mode.** Agreed, with the refinement that it is a
   document-level object rather than cel content (§6.1), which is what makes requirement 7 (reuse
   across frames) a reference instead of a copy.

**Additions I'd argue for:**

- **A "what did it decide?" pass before anything else.** Grouping overlay, per-group mode badge
  (`.auto`/`.clean`/`.crossFade`), and correspondence lines where the matcher found pairs. This
  feature will be judged on whether its automatic choices are legible; an artist who cannot see why a
  limb warped wrongly cannot fix it.
- **Scrub the whole interval, not just one frame.** A play/scrub control over the A→C span, so the
  artist judges *motion* rather than one static pose. Spacing problems are invisible in a still.
- **Per-group solo/mute while adjusting.** Isolating one motion group to fix its arc without the rest
  of the drawing in the way — the standard rigging affordance, and cheap here since groups already
  exist.
- **Show the failure honestly.** When a `.clean` group cannot be matched confidently, say so on the
  group badge rather than silently cross-fading. Silent fallback is how the artist loses trust in
  `.auto`.

### 5.1 Motion groups are document-level, not layer-level

This is the answer to requirement 5 (multi-layer references — lineart + fill, arm + clothing).

A **motion group** is not owned by a layer or a cel. It lives in a document-level registry, and
strokes *reference* it by ID:

```
MotionGroup            // document-level
  ├─ id: UUID
  ├─ displayName: String
  ├─ tagColor: CodableColor        // display swatch for the colour-coding (requirement 4)
  ├─ mode: GroupInterpolation      // .auto / .clean / .crossFade — see §3
  └─ (no geometry — the geometry is per-keyframe)

MotionGroupBinding     // per keyframe-pair, lives in the recipe
  ├─ groupID: UUID
  ├─ latticeA / latticeC: Lattice
  ├─ spacing: SpacingCurve?     // per-group easing override
  └─ constraints: [GuideStrokeRef]
```

Consequences, all of them good:

- A lineart stroke on layer 3 and a fill on layer 4 can carry the same `groupID`, so they are warped
  by **one** lattice and *cannot* drift apart. That is a structural guarantee, not a heuristic — much
  stronger than interpolating the two layers separately and hoping.
- An arm (layer A) and its sleeve (layer B) likewise.
- Compositing layers later slot in the same way: an effect layer references the group and inherits
  its motion. Requirement/edge case 3's "future compositing layers should be interpolatable" is a
  reference, not a rewrite.
- Group membership is authored by tagging strokes — which is exactly the colour-coding UX the brief
  already asks for, arriving as a side effect rather than as separate machinery.

### 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action

Decided in §10: a stroke carries a `groupID` **independent of its paint colour**, shown as a colour
overlay only while interpolate mode is on. That keeps artwork and metadata separate, so colour-coding
still works on fully-coloured art where two red things need to move differently.

Because assigning tags by hand is tedious for art that *already* encodes structure in its colours,
there is a one-shot **"Tag by stroke colour"** action: cluster the layer's strokes by paint colour and
write one motion group per cluster into the `groupID` field. It runs once, produces ordinary editable
tags, and is undoable like any other structural edit.

The important property is that this is a *populate* action, not a live binding. After it runs, the
tags are just tags — recolouring a stroke afterwards does not silently move it to a different motion
group, and the artist can merge, split or reassign the generated groups freely. A live binding would
be simpler to implement and much worse to use: it would make every colour change a hidden motion
change.

### 5.2 The lattice

Following the transient-embeddings model: an axis-aligned quad lattice built over the group's
bounding region at keyframe A, each cell recording which stroke vertices it contains. Vertices are
stored in barycentric/bilinear coordinates within their cell, so warping a stroke is: look up the
cell, apply the cell's current corner positions, done — O(vertices), branch-free, parallelisable.

Registration A→C is where the work is. Three tiers, escalating only as needed:

1. **Similarity fit.** Least-squares rigid+scale between the two groups' point clouds. Free, instant,
   and correct for a huge fraction of real motion (a prop sliding, a head bobbing).
2. **ARAP registration.** The full deformable fit, initialised from tier 1. This is the one that makes
   a bending arm work.
3. **Artist constraints.** Guide strokes and pinned points added on top, re-solving locally.

The interpolated lattice at *t* is ARAP *interpolation* between the two configurations — rotations
are interpolated as rotations, not as matrix lerps, which is the difference between an arm swinging
and an arm collapsing to a line and re-expanding. (Baxter/Barla/Anjyo's normal-equations formulation
is the standard cheap version.)

**Cost note:** the system matrix depends only on the lattice topology, so it is factorised once at
registration and every subsequent *t* is a back-substitution. That is what makes the slider real-time
*on the math side* — see §8 for the side that is not free.

### 5.3 Grouping and registration: one hierarchical algorithm serving both workflows

§10 asks for **both** fully-automatic grouping and one-tap-per-body-part. Rather than two systems,
these are the same algorithm with a different seed — which is the single most useful structural
consequence of the answers.

**Coarse-to-fine split by motion residual:**

1. **Seed.** Start with one group covering the whole layer (fully automatic), *or* with the groups
   the artist tagged (one tap per part). Same code path; only the initial partition differs.
2. **Fit** each group: similarity fit first, then ARAP registration initialised from it.
3. **Measure residual** per stroke — how far that stroke sits from where its group's motion says it
   should be.
4. **Split** where residuals cluster. Strokes with high, *spatially coherent* residual are a part
   moving differently from its parent group; that cluster becomes a new group.
5. **Recurse** until residuals fall below threshold, or a group cap is hit.

Why this shape is right:

- **It degrades gracefully.** Worst case is one group — a single global warp of the layer. That is
  still a usable result (the whole drawing eases from A to C along an arc), not a broken one. Nothing
  about the failure mode is catastrophic, which is the property per-stroke correspondence lacks.
- **Every intermediate state is a valid grouping.** So the artist can stop the process, accept it,
  and edit — the automatic result and the hand-authored result are the same kind of object.
- **It dissolves the chicken-and-egg.** Segmenting by motion needs a motion estimate; estimating
  motion needs a segmentation. Starting global and splitting on residual breaks the cycle without
  needing either one first.
- **Segmenting by motion coherence rather than appearance is the correct criterion.** Two strokes
  belong together because they *move* together, not because they look alike or are near each other.
  An arm and the sleeve on top of it are one motion group despite being different colours on
  different layers; two adjacent strokes on either side of a joint are not, despite touching.

**Bootstrap hints** feed step 2 so the ARAP solve lands in the right local minimum rather than a
folded one:

- Bounding-box / centroid alignment of matching tags.
- A coarse optical-flow field between rasterised A and C — approach B (§3) demoted to a *hint
  generator*. It does not need to be accurate, only roughly right.
- Existing `StrokeSpatialIndex` queries for local density matching.

Then the artist corrects it. **Automatic-with-correction is the target, and "fully automatic" means
"the automatic result is good enough to accept unedited most of the time" — not "there is no way to
intervene".** Every system promising fully automatic inbetweening from independent drawings either
constrains how the drawings are made or is unreliable; what makes unreliability acceptable here is
that the artist can always see the grouping and fix it in one tap.

**This is the highest-risk part of the project** and the reason §11 recommends prototyping
registration before building anything around it.

### 5.4 Editing at an intermediate frame — the inverse map

Requirement 5 says the artist can liquify, draw, erase and lasso-transform *at* the in-between, then
keep moving the slider and have it all still work. The mechanism:

1. Artist draws a stroke at *t*.
2. It is embedded in the **deformed** lattice at *t* (expanding the lattice by a ring of quads if the
   stroke falls outside it — the paper's lattice-expansion routine, RR-9559 Appendix A).
3. The **inverse** lattice transform carries it back to keyframe A's undeformed space, and it is
   stored there as a `localEdit`.
4. It is given a visibility threshold τ = *t*, so it does not appear before the frame it was drawn at.

Now moving the slider re-warps that stroke exactly like every other stroke — it follows the motion
instead of sitting still. That is what "seamless" in the brief actually requires, and it is not
achievable if edits are stored at the inbetween.

Liquify and lasso-transform are the same story one level up: they are edits to the **lattice**, not to
the strokes. Liquify at *t* becomes "displace these lattice vertices at *t*", which is stored as a
deformation offset the interpolation blends in. This is a much better fit than deforming stroke
geometry directly, and it means liquify and interpolation share one representation.

### 5.5 Interpolating a non-blank frame — two modes

Edge case 5 and note 1 need disentangling, because they are two different operations:

**Generate** — B is empty. B is derived entirely from its neighbours. The recipe *is* the frame.

**Reproject** — B already has a drawing the artist made. The drawing must be preserved; what moves is
*when* it sits in the motion. B's own strokes get their own lattice, registered against A's and C's,
and sliding *t* slides **B's lattice along the A→C motion path** while B's strokes ride it. The
artist's linework is never replaced — only reposed.

These deserve distinct entry points in the UI, because they answer different artistic intents
("make me an inbetween" vs. "nudge this drawing's timing"). Conflating them behind one "interpolate"
button is how this feature gets confusing. Note that Generate-then-Commit produces a frame that
Reproject then works on, so the two compose.

The brief's worry — "instances where the interpolated frame is too ambiguous to not partially
generate parts of it" — mostly dissolves under this split. In Reproject nothing is generated at all.
In Generate everything is. The genuinely mixed case is "B exists but is incomplete" (a rough with the
head drawn and the body missing), which is handled by tagging: groups B has get Reproject, groups it
lacks get Generate. That falls out of the group model without a special case.

### 5.6 Rendering an interpolated cel

Evaluating the recipe at *t* produces a `[VectorElement]` — the same display list any other vector cel
holds — so it goes straight into the existing renderer. One correctness point:

**The forward set and the backward set must be composited as isolated groups, then blended.** They
cannot be concatenated into one list. An `.erase` stroke lowers the alpha of *everything beneath it in
the list* ([renderLocalContent rule 3](PaintSoftware/Engine/VectorLayer.swift:1307)) — so A's eraser,
naively appended alongside C's backward-warped strokes, would punch holes in geometry it has no
business touching. Two isolated composites blended at (1−t)/t is the correct structure and it fits
the existing transparency-layer machinery.

---

## 6. Guide strokes

### 6.1 What they are

A guide stroke is a document-level object, not cel content:

```
GuideStroke
  ├─ id: UUID
  ├─ samples: [TimedSample]     // x, y, pressure, AND timestamp
  ├─ interval: KeyframeInterval // which A→C span it governs
  ├─ boundGroups: [UUID]        // which motion groups it drives
  └─ role: .trajectory | .timing | .both
```

Two independent signals come out of one gesture, which is the elegant part of the brief's idea:

- **Geometry → trajectory constraint.** The bound group's anchor point follows this path instead of
  travelling in a straight line between its A and C positions. This is what produces arcs, and arcs
  are most of what makes hand-drawn motion look alive.
- **Stylus velocity → spacing function.** Arc length travelled per unit stylus time *is* the easing
  curve. Drawing the guide fast at the start and slow at the end gives ease-out for free, with no
  graph editor. This is a genuinely good idea and I have not seen it done exactly this way — the
  literature uses separate spacing charts.

### 6.2 The controls from requirement 6

- Geometric adjustment → the guide renders as an editable path with handles in interpolate mode.
- Timing adjustment → the spacing curve is editable, both as a curve and *directly on the path*:
  dragging the current frame's node along the guide re-times that frame. Dots along the guide showing
  where each in-between frame lands is the classic animator's spacing chart, drawn in place. Strongly
  recommend that as the primary timing UI — it is legible without explanation.
- Live feedback → guide edits change the trajectory constraint, which re-solves the lattice.
  Constraint re-solve is local, so this is cheap.

### 6.3 The data gap

**Nothing in the input pipeline captures time.**
[`StrokeInput`](PaintSoftware/Engine/StrokeInput.swift:8) has position, pressure, altitude, azimuth
and no timestamp; `VectorSample` has x/y/pressure.

Recommend **a separate timestamped sample type for guides** rather than adding `t` to `VectorSample`:

- No `Codable` migration on the type every existing project file is full of.
- No 8 bytes per sample on every ordinary stroke, of which there are millions in a real project, for
  a field only guides read.
- Guides are not stamped by `BrushStamper` at all — they render as a thin overlay path — so they
  share none of the stroke hot path and gain nothing from sharing its type.

`UITouch.timestamp` is already available at the recogniser; it is simply discarded today.

### 6.4 Reuse across frames (requirement 7)

Because guides are document-level with IDs, "fetch the guide from another frame" is a reference, not
a copy. Recommend both: **link** (edits propagate — right for a repeating cycle) and **duplicate**
(independent copy — right for a one-off). The registry makes a guide library ("show all guides in this
scene, drop one onto this interval") a natural later addition.

---

## 7. Edge cases from the brief

### 7.1 Erasers — mostly already solved

The brief's edge case 1 is the one this codebase is best positioned for, because
[VECTOR_ERASER_PLAN §2.1](VECTOR_ERASER_PLAN.md) already decided **the eraser is a stroke**:

> "an eraser is structurally a polyline with pressure and width, so interpolation, liquify and point
> decimation all get it for free from the one implementation they already have for paint strokes."

That prediction holds. An eraser warps through the lattice like any stroke, fades by thickness like
any stroke, and carries a visibility threshold like any stroke. "Eraser exists on KF1, gone by KF2"
is τ = its disappearance time and progressive vanishing — no eraser-specific code.

Two things that *are* eraser-specific:

1. **Isolation** — §5.6. Non-negotiable for correctness.
2. **Fade semantics.** Fading a *paint* stroke out by lowering thickness is right. Doing the same to
   an eraser means the hole shrinks, which is usually right, but "the hole gets more transparent" is
   sometimes what's wanted. Probably a per-stroke option, defaulting to shrink. Low priority.

### 7.2 Topological mismatch

Handled by construction — this is the entire reason for choosing engine C (§3). Worth restating the
mechanism plainly: **the system never claims stroke 1 becomes stroke 2.** It claims *this region of
the drawing* moves this way, and it carries both drawings' strokes through that motion, fading
between them. Cardinality never enters the model.

### 7.3 Fills

Warp the fill path's control points through the lattice, same as stroke vertices. Cross-fade with the
same rule. Two specifics:

- The "muddy colour" worry is real when cross-fading two differently-coloured fills through a
  half-transparent middle. Mitigation: **fills are easy to correspond** — there are few of them and
  colour is highly discriminative — so match fills 1:1 by colour+overlap first and interpolate them
  cleanly (engine D's path), falling back to cross-fade only for unmatched fills. Fills are the case
  where correspondence is *reliable*, so use it there even in phase 1.
- Needs a control-point accessor on `VectorFillElement`, which currently exposes only archived
  `Data` and a reconstructed `CGPath`.

### 7.4 Range interpolation (future)

Nothing in §4's recipe assumes a single cel. A range is N recipes sharing references and differing in
`t`. The thing that would force a refactor is storing interpolation state *outside* the cel in a
singleton "current interpolation session" — so don't. Keep the recipe on the cel from day one and the
future feature is a loop.

---

## 8. Performance — the real constraint

**The interpolation math is cheap. The rasterisation is not. This is the whole performance story and
it is worth being precise about, because it points at a different piece of work than expected.**

Per slider tick:

| Stage | Cost |
|---|---|
| ARAP lattice interpolation at *t* | Back-substitution on a pre-factorised system. Sub-millisecond for hundreds of quads; independent of stroke count. |
| Warping stroke vertices through the lattice | O(vertices), a bilinear map each. Microseconds. |
| **Rasterising the result** | **~3.2 ms per stroke.** |

That last number is measured, not guessed —
[REFACTOR_BASELINE.md](REFACTOR_BASELINE.md) records 63.6 ms for a 20-stroke vector layer and 146 ms
for a 426-element one, essentially all of it Core Graphics radial-gradient fills, one per dab.

A 60 fps slider has a 16 ms budget. **That is five strokes.** A 50-stroke drawing scrubs at ~6 fps, and
interpolation is *worse* than ordinary editing because every stroke moves — the dirty-rect and
prefix/suffix caches from [VECTOR_ERASER_PLAN §11](VECTOR_ERASER_PLAN.md) save nothing when the whole
frame is in motion.

### The answer for v1: a preview fidelity tier

**During the drag, don't stamp dabs — stroke the warped polylines as `CGPath`s with a width.** One
path fill per stroke instead of hundreds of radial gradients; roughly two orders of magnitude cheaper.
Stamp at full fidelity on slider release.

This is not a compromise so much as the right thing:

- While scrubbing, the artist is judging *motion and spacing*, not brush texture.
- It degrades to exactly what a rough animation preview should look like.
- It is a small, well-contained addition — a `renderPreview(quality:)` seam alongside `render()`,
  reusing all the existing geometry.
- It buys the entire feature without blocking on the GPU rasteriser.

### The answer eventually: the GPU rasteriser

§11 of the eraser plan already identifies a GPU dab rasteriser as necessary at scale and explains why
it was deferred (it must move raster and vector together, and the raster/vector pixel-parity test is
the regression net that makes the port safe). **Interpolation does not change that reasoning and
should not be the thing that forces it.** But it is the second major feature to want it, which is
worth recording as evidence for prioritising it.

Note the useful shape of this: the interpolation engine is pure geometry, so it neither helps nor
hinders that port. Same discipline §11 credits for the eraser — keep `StrokeGeometry`-style purity in
the new code and a renderer swap costs nothing here.

### Secondary costs

- **Registration** (the ARAP fit + factorisation) is the expensive step, but it happens on
  entering interpolate mode / editing a group — not per tick. Hundreds of milliseconds is acceptable
  there; it needs a progress affordance, not a budget.
- **Onion skin** in interpolate mode means rendering two extra frames. They are *static* while the
  slider moves, so render once and cache.
- **Memory:** `cachedImage` on `VectorCanvas` has no eviction (noted in §11 of the eraser plan), and
  interpolation multiplies live cels. Worth an eviction policy before this ships.

---

## 9. Undo

Requirement 8 wants full undo, and the good news is that most of it already exists.

Three tiers of edit, each mapping to machinery already in the repo:

1. **Recipe edits** — slider, guide geometry/timing, group membership, spacing. These mutate value
   types in the layer/cel tree, so
   [`withStructureUndo`](PaintSoftware/Models/CanvasManager+Undo.swift:69) handles them with no new
   code. The `beginStructureGesture`/`commitStructureGesture` bracket is already the right shape for
   a slider drag (one undo step per drag, not per tick) — the timeline's cel-resize drag uses exactly
   that pattern today.
2. **Stroke edits inside the interval** — new strokes, erases, lasso transforms. These go through the
   existing `registerVectorUndo` path, with the one twist that the recorded change is against
   *keyframe* space (§5.4), which is where the edit was stored anyway.
3. **Commit** — one structure step; the recipe and the resulting display list are both in the
   snapshot.

The trap to avoid: recording an undo step per slider tick. `beginStructureGesture` on touch-down,
`commitStructureGesture` on touch-up, matching
[`resizeCelLeftEdge`](PaintSoftware/Models/CanvasManager+Timeline.swift:171)'s comment on exactly this
issue.

---

## 10. Decisions and remaining questions

### Decided

**1. Rough *and* clean — chosen per motion group.** Each group carries `.auto` / `.clean` /
`.crossFade` (§3). Cross-fade is the universal fallback and must be correct on its own; the
correspondence path is a per-group refinement on the same lattice. Phase 1 ships cross-fade only,
with `.clean` degrading to it until the matcher lands.

**2. Automatic grouping *and* manual tagging — one algorithm, two seeds.** Coarse-to-fine splitting by
motion residual (§5.3), seeded either with one global group (automatic) or with the artist's tags
(one tap per part). Worst case degrades to a single global warp, which is still usable.

**3. Generate and Reproject ship as separate commands** (§5.5). Generate derives a blank frame from
its neighbours; Reproject keeps the artist's existing strokes and slides only their pose along the
A→C motion. They compose — Generate → Commit produces a frame Reproject then works on.

**4. A separate tag attribute, plus a "Tag by stroke colour" bake action** (§5.1.1). The tag is
independent of paint colour; the bake action populates tags from colour clusters once, producing
ordinary editable tags rather than a live binding.

A pattern worth naming, since all four answers share it: **every one of these is an automatic default
with an artist override, not a mode switch.** The design should hold that line everywhere — produce a
result immediately, show what it decided, and make every decision one tap from being changed. It is
also why these four answers cost much less than four times one answer: the override is the same
mechanism each time (a per-group attribute in the recipe), and the automatic path is what the
override falls back to.

**5. Interpolated frames stay linked indefinitely.** No bake-on-exit. A "break link" action is a
nice-to-have for later, explicitly *not* phase-1 work — do not over-engineer it. The one thing that
could force a rethink is file size or memory blowing up, so §8's cache-eviction work is the thing to
watch; if the recipe turns out to be cheap (it should be — it is a few hundred bytes plus lattices),
this decision needs no revisiting.

**6. Guide strokes bind per motion group.** A whole-frame binding option should also be exposed
*if it is genuinely cheap* — the product owner wants to feel out the ergonomics of both. Treat
whole-frame as "bind this guide to every group at once", which if the binding is a set of group IDs
costs almost nothing. If it turns out to need real work, drop it and say so.

**7. Multi-keyframe: pairwise chains first, spline later.** The product owner's *ultimate* intent is
a true spline across 4+ keyframes — the whole point of referencing more than two frames is to derive
non-linear paths from them. We are deferring that, not abandoning it, because a spline through
noisy hand-drawn keyframes may be both unergonomic and unstable, and pairwise is the honest way to
find out. **The data model must therefore make the spline addable without a refactor** (§4), and
that constraint is load-bearing rather than aspirational.

### Standing constraints from the product owner

These are not phase-1 features; they are constraints on *how* phase-1 code is written.

**A. ARAP must be modular and reusable.** It is intended for future vector-layer features (liquify,
mesh distort, warp tools), so the solver and lattice must know nothing about keyframes, cels or
interpolation. Follow the purity discipline `StrokeGeometry`/`StrokeSpatialIndex`/`VectorEraser`
already keep — CoreGraphics types only, no UIKit, no drawing — which is also what lets it be
unit-tested without a simulator.

**B. The onion-skin integration must be swappable.** The current onion skin is provisional and will
be replaced wholesale. Interpolate mode's use of it must go through a seam that survives that
rewrite without significant refactoring. (It also has a live bug: vector cels onion-skin blank — §2.)

**C. Rasterisation cost is a growing strategic concern.** The polyline preview tier (§8) is the
answer *for now*. The product owner explicitly flags that vector layers with >1000 objects make this
critical, and wants optimisation there increasingly prioritised — GPU rasteriser or otherwise. Do not
solve it in this project, but do not make it harder: keep the geometry pure and the renderer behind a
seam.

---

## 11. How clear is the vision

Honest assessment, since it was asked for.

**Very clear (high confidence):**
- Derived-not-stored recipe (§4). Every awkward requirement in the brief resolves the moment this is
  fixed, and it is the decision that would be most expensive to change later.
- Lattice + ARAP as the substrate (§3C). The independently-drawn-keyframes constraint rules out the
  alternatives, and the transient-embeddings work is a strong existence proof for essentially this
  workflow.
- Document-level motion groups (§5.1). Cleanly answers multi-layer references, and buys future
  compositing layers.
- Erasers being nearly free (§7.1), and the isolation requirement that comes with them (§5.6).
- The performance story (§8). Numbers are measured; the preview tier is a concrete unblock.
- Undo (§9). Existing machinery fits.

- The automatic-default-with-override principle (§10). It came out of the answers rather than going
  in, and it is what keeps four "both please" decisions from multiplying the work.

**Clear in shape, fuzzy in detail (medium confidence):**
- **Registration and auto-grouping quality. This is the technical risk of the project.** Everything
  rests on the lattice landing in the right place, and how well the residual-split algorithm (§5.3)
  works on *this app's* real drawings is unknown until tried. Prototype before building around it.
- The correspondence matcher for `.clean` groups. Doing it *after* the lattice warp makes it far more
  tractable than matching raw strokes, but "confident enough to use" needs a real threshold found
  empirically, and `.auto` silently picking wrong is the failure mode to watch.
- Guide-stroke velocity → easing. Conceptually clean, but the mapping from stylus speed to spacing
  needs tuning against real strokes to feel right rather than twitchy.
- Liquify-as-lattice-edit (§5.4). Right idea, but it entangles a tool that does not exist yet with
  this feature's core representation. Worth designing the liquify tool with this in mind.

**Genuinely unresolved:**
- Fill interpolation beyond simple cases — overlapping fills whose *topology* changes (a region
  splitting in two) are a research problem, not an engineering one. Recommend scoping fills to
  warp-and-fade plus colour-matched clean interpolation (§7.3) and accepting imperfection.
- Whether `.auto` mode can pick between clean and cross-fade reliably enough that artists trust it,
  or whether it ends up being a setting everyone sets by hand. Only usage answers this.

**What I would do next:** a throwaway prototype of registration + ARAP interpolation on two real
hand-drawn keyframes, rendered as bare polylines, with a slider. No UI, no persistence, no
integration. It answers the one question that everything else depends on — *does the motion look
right on real drawings from this app* — and it is cheap to throw away if the answer is no.

---

## 12. Sources

- Even, Bénard, Barla. **Non-linear Rough 2D Animation using Transient Embeddings.** *Computer
  Graphics Forum* 42(2), 2023. [DOI](https://doi.org/10.1111/cgf.14771) ·
  [HAL](https://inria.hal.science/hal-04006992)
- Even, Bénard, Barla. **Inbetweening with Occlusions for Non-Linear Rough 2D Animation.** Inria
  Research Report RR-9559, 2024. [PDF](https://inria.hal.science/hal-04797216/file/RR-9559.pdf) —
  the most detailed public description of the animation structure, including the lattice-expansion
  routine and temporal visibility thresholds.
- Sýkora, Dingliana, Collins. **As-rigid-as-possible image registration for hand-drawn cartoon
  animations.** NPAR 2009. — the registration half.
- Baxter, Barla, Anjyo. **Rigid shape interpolation using normal equations.** NPAR 2008. — the
  interpolation half; the cheap formulation.
- Alexa, Cohen-Or, Levin. **As-rigid-as-possible shape interpolation.** SIGGRAPH 2000.
  [DOI](https://doi.org/10.1145/344779.344859)
- Mo et al. **Joint Stroke Tracing and Correspondence for 2D Animation.** *ACM TOG*, 2024.
  [Project](https://markmohr.github.io/JoSTC/) · [Code](https://github.com/MarkMoHR/JoSTC) — the
  correspondence-first camp, and a source of ideas for engine D's matcher.
- **LayerInbetween: Occlusion-Aware Stroke Correspondence and Inbetweening with Automatic Layering.**
  *ACM TOG*, 2025. [DOI](https://dl.acm.org/doi/10.1145/3811364)
- **Sketch Animation: State-of-the-art Report**, 2025. [arXiv](https://arxiv.org/pdf/2510.10218)
- [CACANi](https://cacani.sg/) — the commercial correspondence-based system; context-coherent stroke
  matching with artist-assigned feature points.
