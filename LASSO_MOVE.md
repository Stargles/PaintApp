<!-- Written 2026-08-21 as a scoping-and-specification pass over TODO.md's queued item (a), after the
owner reported that "the lasso and move tool ... on the vector layer the behaviour isn't inline".
Nothing here is built. The owner's asks live in TODO.md; what we find lives in BUGS.md; this is the
design, in the idiom of ADD_TEXT.md and LASSO_FILL.md. -->

# Lasso Move — Specification

Lasso a region on a vector layer, then Move, and **only what is inside the loop moves**. A brush
stroke that crosses the loop is cut at the boundary into two strokes: the piece inside travels, the
piece outside stays, and from then on either can be moved, erased or re-cut on its own. A filled
region loses the chunk that was inside and that chunk travels as its own fill. Text moves whole or
not at all.

---

## 0. How much of this already exists

**Most of it, and the honest headline is that this is a small feature wearing a large feature's
clothes.** The three hard problems — cutting a polyline at a boundary with the cut landing where the
artist drew it, cutting a region out of a filled area, and keeping a cut piece's ink bit-identical to
what it was before the cut — are all solved, shipped, and pinned by tests. What is missing is a
*caller*.

| the feature needs | it already exists as | status |
|---|---|---|
| a closed lasso polygon in canvas space | `SelectionOverlayView.handleLassoPan` → `CGMutablePath` + `closeSubpath()`, `Selection{path,bounds,layerID,celID}` | shipped; `SelectionOverlayView.swift:281-305`, `SelectionModels.swift:54-59` |
| "cut a stroke where it crosses a closed path" | `StrokeGeometry.splitRuns(_:inside:)` — maximal runs where a membership predicate holds, each crossing bisected 40× | shipped and **already used for selections**; `StrokeGeometry.swift:898-923` |
| "cut a stroke into pieces and splice them into the display list" | `VectorCanvas.cutAlongFootprint` (eraser Mode 2), `cutToIntersection` (Mode 3) | shipped; `VectorLayer.swift:1126-1155`, `:1243-1248` |
| "a cut piece's dabs land exactly where the parent's did" | `DabLattice` + `BrushStamper.stampStroke(visibleRange:)` | shipped; `VectorLayer.swift:62-91`, `BrushStamper.swift:144-165` |
| "cut a chunk out of a fill" | `CGPath.intersection` / `.subtracting` — Core Graphics, iOS 16+, deployment target here is **26.5** | shipped by Apple; measured in §1 |
| one undo step for a whole display-list edit | `registerVectorFillUndo`'s whole-array before/after swap | shipped; `CanvasManager+Fill.swift:557-570` |
| a lasso that clips vector drawing | `StrokeCanvasView.selectionClipPath` → `splitRuns` | shipped; `StrokeCanvasView.swift:51, 810-820` |

**The gap is fourteen lines of `TopToolbar`.** `toggleMove()` checks the layer kind *before* it
looks at anything else, and on a vector layer it never reads `canvasManager.selection` at all
(`TopToolbar.swift:136-145`):

```swift
if canvasManager.activeLayerIsVector {
    guard !canvasManager.activeCelIsInBetween else { return }
    canvasManager.isVectorTransforming.toggle()
    return
}
```

`isVectorTransforming` drives `setVectorTransform`, which writes **the cel's whole
`VectorCanvas.transform`** (`CanvasManager.swift:329-356`) — every stroke, fill, image and text
object together. So the lasso the artist drew is still live, the marching ants are still on screen,
and the Move drag moves everything. That is exactly the report.

Nothing gates the lasso itself: `finishSelection(path:)` has no layer-kind check
(`SelectionModels.swift:182-193`), and `SelectPanel` shows the same controls on both kinds. Two of
its four buttons already branch correctly for vector — `fillSelection` at `SelectionModels.swift:363`
and `clearSelectionPixels` at `:393`. Move and Duplicate are the two that do not.

**A second, separate defect found while scoping, worth its own fix and not part of this plan.**
`SelectPanel`'s Duplicate button calls `beginDuplicate()` directly (`SelectPanel.swift:38`), which
has no vector branch and always runs `PixelOps.rasterize` (`SelectionModels.swift:261-295`) onto a
brand-new **raster** layer. Lasso a region on a vector layer, tap Duplicate, and the copy is pixels.
That is reachable today and is not what this document is about.

---

## 1. The decisions

### The cutter is a closed polygon, and the clip is Sutherland–Hodgman's problem, not its algorithm

A lasso is a closed polygon in canvas space (`SelectionOverlayView.swift:296-298`; the points are
captured in the transformed `container`'s own space, so they are canvas points already). Cutting a
polyline against it is **polyline-vs-polygon clipping**, the *line*-clipping half of the family whose
polygon-vs-polygon member is Sutherland–Hodgman and whose general member is Greiner–Hormann. This
project does not need either, and should not import either, because both compute an *intersection
polygon* and what is wanted here is a **partition of one polyline's parameter domain**, which is a
strictly easier problem: walk the samples, ask "inside?" at each, and bisect where the answer flips.

`StrokeGeometry.splitRuns(_:inside:)` is that walk, it is already written, and its doc comment says
what it is for (`StrokeGeometry.swift:885-897`):

> "used to stop a **selection clip** from bridging a stroke that exits the selection and re-enters it"

It returns the maximal runs where `inside` holds, in order, with each crossing landed by 40
bisections rather than at sample granularity (`StrokeGeometry.swift:934-943`). Its complement — the
runs *outside* — is the same call with the predicate negated. Six tests already pin it
(`StrokeGeometryLogicTests.swift:588-657`), including the multi-crossing case.

The four cases the owner will hit, and what falls out with no branch:

- **Enters and leaves several times → n pieces, alternating.** `splitRuns` with `inside` gives the
  moving pieces; `splitRuns` with `!inside` gives the stationary ones. Their union is the parent and
  they abut exactly, because both walks bisect the same crossings.
- **Entirely inside** → one run in, zero out. The stroke is *not split at all*: recognise this
  before splitting and move the element as it stands, so a whole-stroke move mints no new geometry
  and no new ids. This is `isEntirelyCovered`'s role in the eraser (`VectorEraser.swift:344-355`),
  done far more cheaply here because a polygon membership test needs no coverage integral.
- **Entirely outside** → zero runs in. The element is untouched, and the spatial-index prefilter
  (§4 rule 5) means most of the layer never reaches the test at all.
- **Grazing the boundary.** `splitRuns` keeps runs of a single sample ("a lone dab inside the
  selection is legitimate ink", `StrokeGeometry.swift:896`), so a graze produces a one-dab stroke
  rather than nothing. That is right — a dab the artist circled is a dab they meant to move — but it
  means a nearly-tangent loop can mint several one-dab strokes along a line. Cheap, and undo removes
  the whole thing in one step, so it is accepted rather than filtered.

**`splitRuns`' one known limit is inherited, and it is written down where it lives**
(`StrokeGeometry.swift:891-895`): a segment that crosses the boundary *twice* between two stored
samples — a thin concave spur of the loop clipping a coarsely-sampled stroke — is missed, because
one bisection assumes one sign change. The raster path is pixel-exact via
`PixelOps.maskedComposite`; vector geometry has no per-pixel mask to composite against. This is
already the accepted trade-off for drawing inside a selection on a vector layer, and adopting the
same primitive means the two agree rather than disagreeing in a new way.

### Selection is by **centreline**, not by ink — and the alternative is a real feature, not a constant

A thick stroke half inside the loop gives two visibly different answers. This spec chooses the
centreline. Four reasons, in descending order of weight:

1. **The eraser already answers it that way and the owner accepted it.** `cutToIntersection`'s own
   doc says so in as many words (`VectorLayer.swift:1168-1171`): *"a stroke is taken when its
   centreline passes under the footprint, not merely when its ink does. That makes the circle the
   user sees exactly the rule, at the cost of a thick line being left alone when the eraser clips
   only its edge."* Two tools with two membership rules is worse than one imperfect rule, and the
   imperfect rule is the one the artist has already been trained on.
2. **Illustrator's Lasso selects anchor points and path segments, not painted width** — the closest
   shipped analogue to this feature does the centreline thing, and every vector editor that offers a
   lasso does, because a vector object's *identity* is its path.
3. **Ink membership has no primitive.** Centreline membership is `CGPath.contains(_:)` — one call,
   **MEASURED 3.6 µs per probe** against a 400-point loop (Mac, Swift 6, `-O`, 2026-08-21; the
   iPad 9 is slower and the ratio is not measured). Ink membership is *"is the disc of radius
   `r(p)` at `p` inside or touching the loop"*, i.e. a **signed distance to the polygon**, which
   `CGPath` does not expose at all. It means writing a point-to-polyline distance query and indexing
   the loop's own segments to keep it off `O(lasso segments)` per probe.
4. **The cut boundary stops being one curve.** Under ink membership the boundary is the loop
   *offset inward by that stroke's own pressure-varying half-width* — a different curve per stroke,
   and per point along it. `splitRuns`' one-bisection-per-sign-change assumption models a fixed
   boundary well and a moving one badly.

**What ink would cost, honestly.** The reusable half exists: `StrokeSpatialIndex` is keyed on an
*opaque caller-supplied element index* precisely so it does not know what kinds exist
(`StrokeSpatialIndex.swift:12-16`), so the loop's own segments can be inserted as one pseudo-element
and queried per probe. The new half is a `signedDistance(to:)` on the loop plus a per-probe radius
lookup — `StrokeGeometry.stampRadius(forPressure:brush:size:)` already gives the radius. Call it a
day's work plus its own test file, and put it behind a settings toggle only if the owner says the
centreline rule feels wrong on their thick lines. **Do not build it speculatively.**

### The cut is exact, and `conservativeCuts` must *not* be used

The eraser insets every clean cut by the stroke's own half-width (`VectorEraser.conservativeCuts`,
`VectorEraser.swift:381-402`). That inset exists for one reason and the reason does not apply here:
a cut end renders as a **round cap** while the eraser removed ink along a **straight band edge**, so
a naive cut loses ink up to half a width past the covered span — ink the eraser never touched. The
inset pushes the cut inward so the lost ink lands back under the **retained alpha punch**, and the
punch is what makes Mode 1 pixel-exact.

**A lasso move has no punch.** Nothing covers the cut. The two round caps *are* the visible result —
they are what "break the brushstroke in two" means, and they are what Illustrator's Knife and
Scissors produce. Insetting here would open a visible gap of half a stroke-width on *each* side of
the cut that neither piece covers, on top of the caps. So: `StrokeGeometry.splitRuns`, exact, at the
boundary the artist drew.

Two consequences follow and both are decisions, not bugs:

- **A thick stroke cut by the lasso gets visibly rounder at the cut than the lasso's own edge was.**
  This is the ≈0.43·w² lens the eraser's Mode 1 notes quantify (`VectorEraser.swift:178-181`). It is
  correct: a stroke has round caps, and a piece of a stroke is a stroke.
- **The cut is exact rather than pixel-neutral**, which is the opposite of the eraser's requirement
  and is why none of Mode 1's exactness machinery is inherited. `supportsCleanCut` and
  `supportsSplitting` (`VectorEraser.swift:243-254`, `:269-271`) are gates on whether a split can be
  made *invisible*; here the split is supposed to be visible, so **neither gate applies** and a
  scattering, textured or soft brush splits exactly like a hard round one.

### A moved piece carries a **translated** dab lattice; a stationary piece keeps the parent's

This is the one non-obvious mechanical decision in the whole feature, and getting it wrong produces
a bug that reads as a rendering glitch.

`VectorCanvas.stamp` reads the lattice, not the stroke (`VectorLayer.swift:1668-1681`):

```swift
let lattice = stroke.lattice.flatMap { $0.range == nil ? nil : $0 }
let source = lattice?.samples ?? stroke.samples
```

So a piece carrying a `DabLattice` renders at the **parent's** sample positions, filtered to its own
range. Translate a piece's `samples` and leave its lattice alone and it **renders where it used to
be**. That is why both eraser modes that remove geometry set `piece.lattice = nil`
(`VectorLayer.swift:1150` and `:1237`).

Nil-ing it is the wrong fix here, because it throws away the thing the lattice exists for: a piece
that re-anchors its own lattice re-phases every dab along its whole length, and for a scattering or
grainy brush re-rolls the pattern. The artist would move one half of a stroke and watch the *other*
half's texture change — the exact defect `DabLattice` was built to prevent.

**The rule:**

- The piece **left behind** keeps the parent's lattice verbatim. Its dabs are bit-identical to what
  they were, because nothing about its walk changed.
- The piece that **moves** keeps the parent's lattice with `lattice.samples` translated by the same
  delta as its own `samples`. `parameters` and `seedID` are untouched — a parameter is an index into
  the parent's domain and a rigid translation does not change it, and the seed must stay the
  parent's so `BrushStamper` replays the same RNG sequence (`BrushStamper.swift:161-162`,
  `DiscardedDabTarget` at `:297-309`).

Under a **pure translation** that makes the moved half's ink a rigid translate of what it was, dab
for dab, at zero tolerance. That is a stronger guarantee than the feature needs and it is free.

**It holds only for translation, and that is one of the reasons stage 1 is translation-only.** Under
a scale, `BrushStamper.stampSpacing` changes with brush size, so the dab phase shifts whatever the
lattice says; under a rotation it survives, but the piece and the parent walk must rotate about the
same pivot or the range means something different. Stage 3 either recomputes honestly or drops the
lattice and accepts the re-phase — decided there, with a measurement, not here.

**One artefact this creates, named because it is deterministic and nobody would look for it.**
`BrushStamper`'s doc says the boundary is inclusive (`BrushStamper.swift:157-159`): *"a dab exactly
on a boundary is drawn, so two pieces cut at `low`/`high` render, between them, every dab of the
original except those strictly inside `(low, high)`."* The eraser always removes a span, so its two
ranges never abut. A **move** split produces ranges `[0, c]` and `[c, end]` that abut at `c`, so a
dab landing exactly on `c` is drawn by both pieces. Once the pieces are apart this is correct — each
end wants its cap. At **zero delta**, in the instant between the split and the first drag, it is one
dab of doubled alpha, visible only for a brush with opacity below 1. Stage 1 accepts it and pins it
with a test rather than tuning it away; if the owner sees it, the fix is a half-open range on the
moved piece.

### A fill is a `CGPath`, and cutting a chunk out of it is two Core Graphics calls

`VectorFillElement` stores an archived `UIBezierPath` — *"A closed (possibly multi-loop, with holes)
contour extracted from the GPU fill mask"* (`VectorLayer.swift:133-160`). Not a bitmap, not a
re-evaluated seed-and-tolerance recipe. It is drawn by `cg.addPath(path); cg.fillPath()`
(`VectorLayer.swift:1542-1555`). The GPU flood runs once at commit and `PixelOps.pathFromAlphaMask`
traces its result into a path (`PixelOps.swift:586-599`, called at `CanvasManager+Fill.swift:404`).

The deployment target is **iOS 26.5** (`project.pbxproj:1001`), and `CGPath.intersection(_:using:)`
/ `.subtracting(_:using:)` have been available since iOS 16. So:

```
inside  = fill.cgPath.intersection(loop, using: rule)
outside = fill.cgPath.subtracting(loop,   using: rule)
```

**MEASURED standalone with `swiftc -O`, macOS 26, 2026-08-21** (no simulator, no test run):

| claim | result |
|---|---|
| an **open** lasso subpath is auto-closed | identical result to the explicitly closed one, bbox for bbox |
| the result is **fill-rule normalised** | a split donut's two halves each render **identically under winding and even-odd** (2200 px both ways; 6200 px both ways) |
| **area is conserved exactly** | 2200 + 6200 = 8400 = the source donut's own even-odd area |
| holes survive | a donut clipped even-odd keeps its hole in both halves |
| **grazing → empty** | `intersection` returns `isEmpty == true`; a free "nothing selected" test |
| **wholly contained → the other side is empty** | `subtracting` returns `isEmpty`; a free "move it whole" test |
| a disjoint component comes back as a subpath | `bar - notch` → **one `CGPath`, two subpaths** |
| the result transforms | `copy(using:&t)` moves it; bbox lands where expected |
| cost, big fill vs big loop | **0.86 ms** ∩ and **1.27 ms** − for an 8000-point fill against a 1500-point loop; 0.20/0.29 ms at 2000 vs 400 |

Three decisions fall out:

- **Fill-rule normalisation settles `evenOddFill`.** The field exists for `clearSelectionPixels`'
  hole trick and it is *load-bearing* for a path built that way. A boolean result needs no such
  trick: set `evenOddFill = true` on both halves and the rendering is identical either way. That is
  measured above, not assumed.
- **This replaces `clearSelectionPixels`' `clipPath(_:excluding:)`, and should.** That helper
  (`SelectionModels.swift:422-427`) concatenates the two paths and relies on even-odd to make the
  overlap a hole. It is not a boolean: it produces a path whose *shape* depends on the fill rule
  every downstream reader must remember to pass, its doc comment claims a nil return it does not
  have, and it cannot answer "is the result empty". Do not extend it. (Migrating Clear onto the
  boolean is a separate, welcome cleanup and is **not** in this plan.)
- **The moved chunk is one element, not n.** `bar - notch` came back as one path with two subpaths,
  and that is the right granularity: the artist made one gesture, so the outside remnant is one fill
  and the inside chunk is one fill, however many components each has. Splitting components into
  separate elements is a different feature (it is Illustrator's *Release Compound Path*), it
  multiplies the display list, and nothing in the owner's ask asks for it.

**A fill has no transform field.** `VectorFillElement` is `{id, pathData, color, opacity,
evenOddFill}` (`VectorLayer.swift:136-144`); unlike `VectorImageElement` it carries no
`LayerTransform`. So moving a fill means re-archiving a translated `CGPath`. That is fine — it is
one `copy(using:)` and one `NSKeyedArchiver` round trip, done once at commit, not per frame — and it
is the same thing `addFill(canvasSpacePath:)` already does when it maps a canvas-space path into
local space (`VectorLayer.swift:687-694`).

**Fills are therefore the *easy* half of this feature, not the hard half.** The brief guessed the
opposite. Strokes need a parametric walk, a bisection, a dab lattice and an id policy; a fill needs
two Apple calls and an archive.

### Text moves whole, if the lasso contains its centre

The owner allowed it: *"Being able to do this to text probably is hard to impossible, so it's okay
if it moves text whole."* `ADD_TEXT.md` §5.4 already settled the same question for the eraser —
*"Text stays whole under the eraser… Slicing letters directly was rejected because it forces an
outline conversion on first cut, after which the text is no longer text"* — so this is that ruling
applied to a second tool, not a new one.

**The rule: a text element moves whole iff its frame's bounding-box centre is inside the loop.**
`TextFrame.boundingBox` exists (`TextObject.swift:293`) and moving the element is translating
`frame.corners` by the delta — four points, no re-layout, no re-measure, and correct for a rotated
or scaled frame because the corners *are* the frame (`TextObject.swift:252-256`).

Why the centre and not the two obvious alternatives:

- **"Intersects the loop" over-selects.** A loop drawn around one word of a paragraph drags the
  whole paragraph out of the page. The artist's gesture said *this much*, and the answer moved
  something an order of magnitude larger.
- **"Wholly contained" under-selects.** The common gesture is a loop *around the thing*, drawn
  close; a wide title needs a generous, deliberate loop before it qualifies, and until then Move
  silently leaves it behind. Silent non-selection is the worse failure of the two, because there is
  nothing on screen to explain it.
- **The centre is the stroke rule rounded to the nearest whole object.** Strokes move the part
  inside; an object that cannot be parted moves if *more than half of it* is inside, and the
  bounding-box centre is the cheap, stable proxy for that. One `path.contains(box.center)` call, one
  sentence an artist can hold in their head — *"if you circled its middle, it comes with you"* —
  and it degrades in the direction the artist can see and correct.

`editingElementID` is not involved: a text element with a live editor open cannot be lassoed,
because opening a lasso runs `beginCanvasEdit()` (`SelectionModels.swift:187`), which calls
`commitInteractiveText()` (`CanvasManager.swift:773-784`) and closes the session first. The chokepoint
`ADD_TEXT.md` §1 built for exactly this purpose covers this feature with no retrofit.

Placed images (`VectorImageElement`) get the same centre-inside rule for the same reason, and there
they are *cheaper* — the element already has a `LayerTransform` to add the delta to
(`VectorLayer.swift:164-170`).

### An erase punch is a stroke and moves like one

There is **no `.erase` element kind**. An eraser is a `VectorStroke` with `composite == .erase`, and
the reason is on the type (`VectorLayer.swift:9-11`): *"A mode on `VectorStroke` rather than its own
element type, so an eraser gets interpolation, liquify and point decimation for free."* This feature
is the fourth operation to inherit it for free, and it should.

**The rule: `.erase` strokes are split and moved by exactly the same centreline rule as paint
strokes, and `collectResidueGarbage()` runs after the commit.** No branch.

The alternative — leave punches where they are — is rejected concretely, not by preference. A punch
masks only what is *beneath it* in the list (`collectResidueGarbage`, `VectorLayer.swift:1046-1048`),
so ink moved out from under a punch **heals**: the hole the artist deliberately erased closes up,
and a new hole opens in whatever the punch is now sitting on. Worse, the stranded punch then has
nothing beneath it, so the next erase's garbage collector deletes it outright — and the healing
becomes permanent rather than something one undo press reverses.

Moving the punch has its own cost and it is named rather than argued away: **a punch that lands on a
new backdrop punches a hole the artist did not draw.** That is real. It is bounded by three things —
the punch travels with the ink it was punching, so its intended victim is still under it; a punch
that lands on nothing is collected; and `supportsCleanCut` (`VectorEraser.swift:243-254`) means the
common hard-round, full-opacity eraser mostly *splits* rather than retaining a punch at all, so most
drawings have few punches to move. Stage 1 accepts it and pins the behaviour with a test.

This is an artefact of *this* codebase's retained-punch decision, not of the feature. Illustrator
and CSP both cut vector geometry outright and have no punch object to strand.

### Identity: fresh ids, in-place splice, tags inherited

**Both pieces mint fresh `UUID`s.** That is what Modes 2 and 3 already do (`piece.id = UUID()`,
`VectorLayer.swift:1146` and `:1234`). The tempting alternative — the stationary piece keeps the
parent's id — buys nothing: dab phase and the RNG sequence come from `lattice?.seedID ?? stroke.id`
(`VectorLayer.swift:1679`) and both pieces carry the parent's `seedID` in their lattice, so renders
are unaffected; and it makes "which one is the original" a coin flip the moment a lasso cuts one
stroke into three.

**The pieces replace the parent in place.** `_elements.replaceSubrange(index...index, with: pieces)`
— `cutToIntersection`'s own splice, applied in descending index so an earlier one cannot invalidate
a later one (`VectorLayer.swift:1243-1248`). Two things are forbidden:

- **Do not append the moved piece to the end of the list.** Appending puts it above every `.erase`
  punch, so a hole punched in that stroke silently stops applying — a punch masks only what is
  beneath it.
- **Do not route through the `strokes` kind-filtered setter.** It gathers the whole bucket back at
  the first stroke's index (`splicing`, `VectorLayer.swift:438-453`), which is order-stable only for
  a *contiguous* bucket, and strokes are interleaved with `.erase` punches and text by construction.
  `ADD_TEXT.md` §3 stage 3 records the identical caveat for text and reaches the identical
  conclusion: **the whole `elements` array is what undo swaps.**

**`Kind`'s rawValues are untouched and stay untouched.** `fill = 0, image = 1, text = 2, stroke = 3`
(`VectorLayer.swift:414-419`) governs `insertionIndex` only — where a *newly added* element belongs
(`:433-435`). An in-place replacement never calls it. So `ADD_TEXT.md` §3 stage 3's load-bearing
rule — *"keeping `.stroke` highest is what makes a brush stroke drawn after an erase still land at
the end of the list"* — is not merely preserved by this feature, it is not touched by it.

**`motionGroupID` is inherited by both pieces, and this needs no code.** A piece is built by copying
the parent (`var piece = stroke`), and the field's own doc already claims this outcome
(`VectorLayer.swift:38-41`): *"A field, not a side table, so it survives copy/duplicate/split/undo
automatically and a cut piece keeps its parent's tag."* Splitting a tagged stroke gives two strokes
in the same motion group, which is right — they are still the same limb. The known wart is unchanged
and not worsened: a fill has no `motionGroupID` at all (`VECTOR_INTERPOLATION.md` items 11/41), so a
fill chunk cut out by the lasso cannot carry a tag either, exactly as it could not before.

### Undo: the split and the move are one atomic step, and it is a session

**One step per move gesture, and the step contains the split.** Undo must never leave the artist
with a stroke cut in half and nothing moved. The mechanism is a whole-array before/after swap of
`VectorCanvas.elements`, which is `registerVectorFillUndo`'s shape (`CanvasManager+Fill.swift:557-570`)
and what every other display-list edit in this app already does.

**It is a *session*, in the shape of a text session, not a bracket in the shape of
`setVectorTransform`'s.** The distinction matters and it is not stylistic. `b100d65`'s bracket
(landed today, `CanvasManager.swift:206-213`, `:373-397`) captures **two `CGAffineTransform`s** and
nothing else, because — its own words — *"Nothing else in the cel is touched by a transform, so
nothing else needs capturing."* A lasso move changes the display list. A pair of affines cannot
describe it.

What *is* inherited from that bracket is its lesson, and it is the whole of the lifecycle design:
**a session must close however it ends.** The two paths that end one with no gesture ending are the
same two — `handleActiveContextChanged()` on a layer or frame switch (`SelectionModels.swift:148-173`)
and `rasterizeLayer` — plus save, backgrounding, and `finalizePendingGesturesForHistoryAction()`
(`CanvasManager.swift:2278`). All of them already funnel through `beginCanvasEdit()` /
`commitAllInteractiveState()` (`CanvasManager.swift:773-792`), so a `commitLassoMove()` added to
`beginCanvasEdit()`'s list — beside `commitInteractiveFill`, `commitInteractiveShape` and
`commitInteractiveText` — inherits every one of them with no per-caller retrofit. That is
`ADD_TEXT.md` §1's "the bake trigger is one line", used a second time.

**Never a step per delta.** Two documented failures say so from opposite directions:
`setVectorTransform` before `b100d65` pushed a step per gesture-`.changed` event (hundreds per drag),
and `ADD_TEXT.md` §3 stage 4 found that a per-drag `recordUndo` *underneath* an enclosing session is
a **dead** entry — undo commits the session and reverts it, leaving a step whose next press restores
state into a session that no longer exists.

**The split is applied at session open, and abandoning the session un-applies it.** The alternative
— keep the parent whole and split only at commit — requires the live preview to draw a stroke that
does not exist yet, in two halves, one of them moving. Applying the split up front lets the preview
be *exactly* the existing render minus a suppressed set, which is cheap and is the shape
`editingElementID` already established. The price is a rule: a session that ends with no movement
must restore the snapshot verbatim, so no invisible split is left behind. That is
`closeVectorTransformBracket`'s no-op guard generalised (`vectorTransformsAreIndistinguishable`,
`CanvasManager.swift:399-407`), and it wants the same tolerance rather than `==`.

**The suppression set is the one new field on `VectorCanvas`.** `editingElementID: UUID?` freezes one
element out of the flatten and invalidates on assignment (`VectorLayer.swift:317-326`); this needs a
`Set<UUID>`. Widen the existing field to a set rather than adding a second one — one concept, one
check in `renderLocalContent`, and `ADD_TEXT.md`'s "the committed element is never lifted out of
`_elements`" argument applies here word for word and for the same reason (a display list that
momentarily does not contain what the artist committed is a data-loss window on a device whose
`Compositor` header documents jetsam killing the process).

### Interpolation: out of scope, and the guard already exists

`toggleMove()` already refuses on a derived cel (`TopToolbar.swift:139-142`), and it must keep doing
so: an in-between stores an `InterpolationRecipe`, not ink, so there is no display list to split.
Reuse the guard verbatim.

On a **keyframe**, splitting a stroke changes the stroke count, which changes correspondence. What
that costs is bounded and is already written down (`VECTOR_INTERPOLATION.md` §3.4): tier 0 is a
*1:1* arc-length match, and *"`N:M` falls back to the point-cloud path, which also refuses any frame
holding a fill or a placed image."* So the honest statement is:

- **Splitting a stroke on a keyframe can demote that pair from the 1:1 tier to the point-cloud
  tier**, which is a quality change in an existing feature, not a correctness failure — and it is
  the same demotion the *eraser* already causes every time it splits a stroke on a keyframe. This
  feature adds no new hazard.
- **Splitting a fill costs nothing at all**, because the point-cloud path already refuses any frame
  holding a fill.
- **Recipes are derived, not stored.** Nothing needs migrating; the next evaluate re-registers
  against whatever the display list now holds.

Out of scope, and safe. One test asserts a split cel still evaluates rather than trapping, and that
is the whole obligation.

---

## 2. Why the rejected alternatives were rejected

**Reuse `beginMove()` — rasterize the vector cel, lift pixels, move them.** It is the shortest
diff and it would work on the first try. It also destroys the layer: `beginMove` flattens through
`PixelOps.rasterize` and `commitFloatingPieceIfNeeded` lands the result in `Cel.raster`
(`SelectionModels.swift:225-254`, `:333-345`), so the artist's vector strokes become pixels on a
layer still labelled `.vector`. The owner's whole complaint is that a vector layer is not behaving
like one. This is also not hypothetical — it is what `beginDuplicate()` does today (§0).

**Build the whole thing on `CGPath` booleans, strokes included.** Attractive: one algorithm for
both kinds. It fails because a `VectorStroke` is not a region — it is a centreline plus a brush, and
its ink is produced by re-stamping (`VectorLayer.swift:16-19`). Converting a stroke to an outline
path to intersect it discards pressure, dynamics, grain, scatter, the dab lattice and the brush
itself; the piece that came back could never be re-cut, re-warped by interpolation, or re-rendered
at another resolution. That is "convert to outlines", which `ADD_TEXT.md` §3 stage 6 correctly files
as a *deliberate, one-way, opt-in* operation.

**Use `VectorEraser`'s probe-and-bisect walk (`coveredSpans`) instead of `splitRuns`.** It is the
more powerful machine and it is the wrong one. `coveredSpans` steps probes at the eraser's smallest
radius because a *footprint* can enter and leave a single segment several times
(`VectorEraser.swift:116-171`); a polygon membership test is one boolean per point, and
`splitRuns`' doc says exactly why one bisection per sign change suffices
(`StrokeGeometry.swift:891-895`). Using `coveredSpans` would multiply the probe count by the ratio
of segment length to eraser radius for no additional correctness, and would need a `probeStep` that
a lasso does not have.

**Inset the cuts with `conservativeCuts`, for consistency with the eraser.** The inset exists to
hide a cut *under a retained alpha punch*. There is no punch here, so the inset would open a visible
gap of half a stroke-width on each side of the cut — the artist would lasso a line, move it, and
find both halves shorter than the line was. Consistency with a mechanism whose precondition is
absent is not consistency.

**Nil the lattice on both pieces, as Modes 2 and 3 do.** Those modes *remove* geometry, so a piece
"re-stamps from its own first sample rather than inheriting the parent's lattice, which would keep
drawing dabs just cut away" (`VectorLayer.swift:1148-1150`). A move removes nothing. Nil-ing the
stationary piece's lattice re-phases every one of its dabs and re-rolls a scattering brush's
pattern, so the half the artist did **not** touch visibly changes — the precise defect `DabLattice`
was built to prevent.

**Extend `clearSelectionPixels`' `clipPath(_:excluding:)` to do the fill split.** That helper
concatenates two paths and leans on the even-odd rule to make the overlap read as a hole
(`SelectionModels.swift:422-427`). It is not a boolean and cannot be made into one: it produces no
"inside" half, cannot answer whether the result is empty (its doc comment claims a nil return the
code does not have), and its output's *shape* depends on every downstream reader remembering to pass
`.evenOdd`. Core Graphics' own boolean returns a fill-rule-normalised path — **measured** in §1, both
rules agreeing to the pixel — which removes that whole class of coupling.

**Split a fill's disjoint components into separate elements.** `bar - notch` returns one path with
two subpaths, and keeping it that way matches the gesture: one lasso, one chunk. Splitting into n
elements is Illustrator's *Release Compound Path*, it multiplies the display list on every move, and
it changes what a subsequent undo swap has to reconcile. Nothing in the ask asks for it.

**Select by ink rather than centreline, in stage 1.** Rejected for stage 1 only, with §1's four
reasons — the deciding one being that the eraser already answers the same question by centreline and
the owner accepted it, so shipping the opposite answer in a second tool creates a disagreement the
artist has to learn. It is listed in §3 stage 4 as a real follow-up, not as a closed door.

**Text: move it if the loop touches it at all.** A loop around one word drags the paragraph. The
artist's gesture named a region and the answer moved something far larger, with nothing on screen to
explain why.

**Text: move it only if the loop wholly contains it.** Silently leaves a title behind because the
loop clipped one corner. Of the two failure directions, silent non-selection is the worse: the
over-selection at least shows the artist what happened.

**Leave `.erase` punches where they are.** Moving ink out from under a punch heals a hole the artist
deliberately made — and then `collectResidueGarbage()` deletes the now-orphaned punch
(`VectorLayer.swift:1046-1082`), making the healing permanent rather than one undo press away.

**Hang the undo off `isVectorTransforming`'s `didSet`, copying `b100d65`.** That bracket stores two
affines and its own doc says that is sufficient *because a transform touches nothing else in the cel*
(`CanvasManager.swift:361-366`). A lasso move rewrites the display list. Copying the mechanism would
mean storing a display-list snapshot in a structure named and documented as a transform pair.

**A `recordUndo` per drag delta, or per drag.** Per delta is `setVectorTransform`'s pre-`b100d65`
defect — hundreds of steps for one gesture. Per drag, underneath an enclosing session, is
`ADD_TEXT.md` §3 stage 4's finding: a *dead* entry that undo commits past, leaving a step whose next
press restores a frame into a session that no longer exists.

**Apply the split at commit rather than at session open.** It sounds safer — nothing is written
until the artist means it — but it forces the live preview to render a stroke that does not exist
yet, split into halves, one moving. Applying at open makes the preview "the normal render, minus a
suppressed set", which is machinery that already exists. The safety is bought back by the rule that
an abandoned session restores the snapshot.

**A `formatVersion`, or any persistence change at all.** There is none: a split produces
`VectorStroke`s and `VectorFillElement`s, which are exactly what the display list and
`VectorCanvasData.ElementData` already hold (`VectorLayer.swift:1708-1745`). **This feature adds no
new persisted type, no new discriminator, and no new file.** An older build opening a project
containing split strokes sees strokes.

---

## 3. Staged delivery

Each stage merges to `main` on its own and is usable on the owner's iPad. Follow the multi-session
protocol in [CLAUDE.md](CLAUDE.md): one worktree per stage, and a new *test* file needs a hand-written
`project.pbxproj` entry with an id derived from the file's own name — plus the duplicate-id check
after any rebase that touches that file.

The spine is: **strokes first** (the owner's core ask, and the part with existing machinery), **fills
second** (small, and independently useful), **the whole objects third**, **polish fourth**.

**Stage 1 — a lasso move splits and moves strokes, by translation.**
`Engine/LassoSelectionGeometry.swift`: `CoreGraphics`/`Foundation` only, like `StrokeGeometry` and
`VectorEraser`, so it compiles a second time into `PaintSoftwareUITests` and every decision above is
testable headlessly. It holds the membership predicate, the inside/outside partition built on
`StrokeGeometry.splitRuns`, the whole-in / whole-out fast paths, the piece constructor (fresh id,
inherited `motionGroupID`, the lattice rule), and the centre-inside test for whole objects. It holds
no `VectorCanvas` and takes no lock, so `VectorCanvas.splitForLassoMove(...)` is a thin adapter that
queries the spatial index, calls in here, and splices — the arrangement `VectorEraser`'s own header
argues for (`VectorEraser.swift:4-17`).
`Models/CanvasManager+LassoMove.swift`: the session — open (snapshot `elements`, split, populate the
suppression set), `updateLassoMoveTranslation`, `commitLassoMove()` (one whole-array undo step),
and the abandon path. `commitLassoMove()` joins `beginCanvasEdit()`'s list.
`VectorCanvas.editingElementID` widens to `editingElementIDs: Set<UUID>`.
`TopToolbar.toggleMove()`'s vector branch gains one condition: **with a selection on this cel, start
a lasso-move session; without one, the existing whole-layer transform, unchanged** — which is the
owner's *"This is currently correct, nothing needs to change"*, honoured literally.
`.erase` strokes move with paint strokes; `collectResidueGarbage()` runs after commit.
**Explicitly not yet:** fills, images and text are left where they are; rotate and scale; ink
selection.
**Tests** (headless, asserting identities and invariants — never screenshots):
`LassoSplitLogicTests` — a stroke crossing once yields exactly two strokes with the parent's tag and
two fresh ids; crossing three times yields four, alternating, and their sample counts sum to the
parent's plus the crossings; a stroke wholly inside is moved with **the same id and no split**; a
stroke wholly outside is untouched **by identity**; a graze yields a one-sample run; the cut point
lies on the loop to within `StrokeGeometry.epsilon`; the stationary piece's `lattice` is the
parent's **by value** and the moved piece's `lattice.samples` are the parent's plus the delta, with
`parameters` and `seedID` equal; sixty small deltas and one large one leave identical geometry and
**identical history depth**; a session abandoned at zero delta leaves `elements` equal to the
snapshot **element for element, id for id**; an `.erase` punch inside the loop moves and one outside
does not; a `motionGroupID` survives to both pieces.
`LassoMoveUndoLogicTests` — one step per gesture; undo restores the pre-split array (so no
half-cut stroke can survive an undo); redo re-applies both halves; a layer switch mid-session
commits rather than strands; `finalizePendingGesturesForHistoryAction` closes the session.
**Needs the device before merge**, and the reason is specific: whether the marching ants and the
moving pieces read as one gesture, and whether the split lands where the artist's finger thought it
did at 0.3× zoom. Neither is reachable headlessly. Use `ActionRecorder` if it does not.

**Stage 2 — fills split too.**
The two `CGPath` boolean calls, plus the archive round trip, plus the empty-side fast paths. Small
enough to be its own branch and worth being one, because it is the stage most likely to surprise on
real artwork (a traced fill contour has thousands of points).
**Explicitly not yet:** migrating `clearSelectionPixels` off `clipPath(_:excluding:)`. Welcome, and
separate.
**Tests:** `LassoFillSplitLogicTests` — the two halves' rendered coverage **sums to the source's**
(the area-conservation identity §1 measures); each half renders identically under winding and
even-odd (the normalisation identity); a hole in the source survives into whichever half contains
it; a grazing loop leaves the fill **by identity**; a containing loop moves it whole with no boolean
call made; a translated chunk's bbox is the source chunk's bbox plus the delta; a fill with two
disjoint components stays one element with two subpaths.
**No device check owed** beyond stage 1's, unless the owner's own drawings show a fill contour large
enough to make §4 rule 1's budget bite — which stage 1's device pass is the moment to look for.

**Stage 3 — whole objects: text and placed images.**
Centre-inside, translate `frame.corners` / add to `LayerTransform.position`. Genuinely small; it is
last only because it is the least of the ask.
**Tests:** `LassoWholeObjectLogicTests` — a box whose centre is inside moves and one whose centre is
outside does not, *with a fixture assertion that the second box really does overlap the loop*, so the
test fails loudly if the rule is ever quietly swapped for "intersects"; a rotated frame's four
corners each move by exactly the delta and the frame's `size` and `pointSize` are unchanged; a text
element is never split under any loop.

**Stage 4 — the follow-ups, independent small branches.** Rotate and scale a lasso selection, which
means deciding the lattice question §1 defers and probably means accepting a re-phase under scale.
Ink-based membership behind a setting, if the owner says the centreline rule feels wrong on thick
lines. Migrating `clearSelectionPixels` onto the boolean. Fixing `beginDuplicate()`'s
rasterize-on-a-vector-layer (§0) — which is a bug, not a stage of this, and should be filed as one.

---

## 4. Performance rules

The measured trap ([BUGS.md](BUGS.md):382-392, `StrokeCanvasView.refreshDisplay`'s `.overlay`
branch) has three ingredients: a **canvas-sized** allocation, **per input event**, plus two
canvas-sized `draw(in:)` calls — MEASURED on the owner's iPad 9 in Release at **53.8 ms a dab** on a
vector layer at 4096², against 4.0 ms on raster. This feature must break all three, and the second
measured figure is even more to the point: [PERFORMANCE.md](PERFORMANCE.md) item 10 measured the
Mode 3 eraser's live drag at
**94.6 ms per cutting sample**, because a cut invalidates the cache and re-stamps a ~150-element
layer. **That is the number that says cutting must never enter a drag loop**, and it is why the
split here happens exactly once.

1. **The split runs once, at session open.** Not per input event, not per drag delta, not on lasso
   lift (the artist may never press Move). One split, one invalidate.
2. **The live drag writes one `CGAffineTransform` and rasterizes nothing.** The moved pieces are
   drawn into an overlay whose backing store is **the pieces' own bounding box**, never the canvas —
   the position `ADD_TEXT.md` §4 rule 2 reaches for text, for the same reason. A 60 Hz drag assigns
   a transform.
3. **Never call `VectorCanvas.render()` during the drag.** That is item 10's 94.6 ms, and it is a
   whole-layer re-stamp on a path with no Metal variant.
4. **Exactly two `invalidate()` calls per session** — one when the suppression set is populated at
   open, one at commit. Every bump cascades into `RasterizeKey`, `LayerContentVersion`, `SandwichKey`
   and both upload caches, each costing a canvas-sized flatten and an LRU eviction.
5. **Membership testing is prefiltered by the spatial index.** `strokeIndex().segments(near:)`
   against the **loop's bounding box** — the query is the size of the loop, not the size of the layer
   (`StrokeSpatialIndex.swift:4-11`). A small loop on a dense drawing must not touch every element.
   Only elements the index returns get the per-sample walk.
6. **The lasso path is mapped into layer-local space once**, via `VectorCanvas.localPath(fromCanvas:)`
   (`VectorLayer.swift:698-703`), and the *local* path is what every probe tests against. Mapping per
   probe would put a matrix multiply inside the 40-iteration bisection.
7. **Budget the boolean, and know when it is skipped.** MEASURED (Mac, `swiftc -O`, 2026-08-21):
   0.86 ms + 1.27 ms for an 8000-point fill against a 1500-point loop; 0.20 + 0.29 ms at 2000 vs 400.
   INFERRED for the iPad 9: several times that, so a layer with a dozen large fills could reach tens
   of milliseconds — **once, at session open, where a one-frame hitch is acceptable and a per-frame
   one is not**. The `isEmpty` fast paths (§1) skip both calls entirely for a fill the loop misses or
   wholly contains, which is the common case.
8. **`CGPath.contains` is the cost model for strokes.** MEASURED 3.6 µs per probe against a
   400-point loop (Mac). One probe per stored sample plus 40 per crossing, over the elements the
   spatial index returned. A 200-sample stroke with two crossings is ≈1.0 ms. This is the figure to
   re-measure on device if session open ever feels slow, and the reason a *finer* loop costs more
   than a coarse one.
9. **No new cache entries, no new persisted type.** The pieces are `VectorStroke`s and
   `VectorFillElement`s; nothing new is minted, cached or written. `CompositorBudget` and
   `PixelOps.RasterizeCache` see one invalidation at open and one at commit and nothing else.
10. **Measure in Release on the device.** Debug measured 62× slower on the alpha-mask path;
    `CompositorBudget.hasHeadroom` returns true whenever `os_proc_available_memory()` is 0, which is
    the simulator, so the memory valve never closes there. Stage 1's device check is not optional.

---

## 5. Behaviour, decided

Settled by the owner on **2026-08-21**. Do not re-litigate.

1. **A lasso selection moves only what is inside it.** *"When you lasso and then move, only the parts
   inside the selection should be moved. This means breaking up brushstrokes and taking chunks out of
   fill sections."* The Move tool with **no** selection still moves the whole cel, and the owner said
   so explicitly: *"This is currently correct, nothing needs to change."*
2. **One stroke becomes two independent strokes.** Asked directly whether the piece left behind and
   the piece that moved should become two strokes from then on, so either could later be moved or
   erased separately, the owner answered **"yes, they should be two strokes."** This matches
   Illustrator and it matches this codebase's own vector eraser, which has minted independent pieces
   at every cut since Mode 2 shipped.
3. **Text moves whole.** *"Being able to do this to text probably is hard to impossible, so it's okay
   if it moves text whole."* Consistent with `ADD_TEXT.md` §5.4, which settled the same question for
   the eraser.

### Still needs a ruling, and stage 1 can start without it

- **Does the artist expect the lasso to survive the move?** After committing, should the loop still
  be on screen around the moved pieces (so a second Move nudges the same set), or be cleared? Raster
  `beginMove` clears it (`SelectionModels.swift:255`). Keeping it is more useful and is a one-line
  difference. **Stage 1 should clear it, matching raster, and ask.**
- **Should a fill chunk that lands on nothing still be a fill?** Moving a chunk of flat colour out
  from between two lines and dropping it on blank paper leaves a floating coloured shape. That is
  literally what was asked for, and it may still read as a mistake on real artwork. Device question,
  not a code question.
- **Is one undo step per Move gesture the right granularity?** Session 56 asked the same question of
  the whole-layer transform and it is still open. The answer should be the same for both.

---

## 6. Open risks

**Needs the owner's eye on the device, not a test:**

- **The centreline rule on their actual line weights.** §1 argues it from consistency and cost, but
  "a 40-point brush stroke whose ink is half inside the loop does not move" is a sentence the owner
  should see happen before it is called settled. This is the single most likely thing to come back.
- **The visible round caps at the cut.** Correct by construction, and possibly not what the artist
  pictured when they said "breaking up brushstrokes".
- **A moved punch biting a new backdrop.** §1 accepts it; whether it reads as a bug depends on how
  many retained punches the owner's drawings actually carry, which only their files can say.
- **Whether the split lands where the finger thought it did**, at low zoom, with the marching ants
  and the moving pieces on screen together.

**Engineering risks:**

- **`splitRuns`' double-crossing limit** (`StrokeGeometry.swift:891-895`) is inherited, not
  introduced. A thin concave spur of the loop clipping a coarse stroke between two samples is
  missed. It is already the accepted behaviour for drawing inside a selection; adopting the same
  primitive keeps the two consistent rather than adding a second, different approximation.
- **The abutting boundary dab** (§1) is deterministic, visible only for a translucent brush at zero
  delta, and unfixed in stage 1 by choice.
- **A traced fill contour is not a tidy polygon.** `pathFromAlphaMask` walks an alpha threshold
  (`PixelOps.swift:586-599`), so a real fill can carry thousands of near-collinear points. The
  boolean cost measured in §4 rule 7 used 8000 points precisely to bound this, but the owner's own
  fills are the only honest test, and there is no simplification pass anywhere in the pipeline
  today.
- **Widening `editingElementID` to a set touches text.** It is one field, one comparison, and
  `ADD_TEXT.md` §4 rule 5's `isTextEditLive` reads it — so the text suite is part of stage 1's
  regression surface, not a bystander.
- **`beginDuplicate()` rasterizes a vector layer** (§0). Not caused by this work and not fixed by
  it, but the same lasso reaches it, so an artist exercising stage 1 is one button away from it.
