<!-- Written 2026-08-18 from a four-sweep research workflow the owner asked for, after they
reported "when i circle something the entire canvas gets filled". This is the specification for the
rebuild; the diagnosis of what shipped is in BUGS.md, and the owner's asks are in TODO.md. -->

# Lasso Fill — Specification

## 1. The algorithm, in standard terms

**Name:** *morphological hole filling* — formally, **reconstruction by erosion of the complement, marked from the boundary** (Vincent, "Morphological Grayscale Reconstruction in Image Analysis," IEEE TIP 2(2):176–201, 1993; Soille, *Morphological Image Analysis*, §6.3). It is the same operation as MATLAB's `imfill(...,'holes')` (https://www.mathworks.com/help/images/ref/imfill.html) and the OpenCV "flood from the border, then invert" recipe (https://learnopencv.com/filling-holes-in-an-image-using-opencv-python-c/), with one substitution: **the marker set is the artist's loop instead of the image border.**

Equivalently and more usefully for a Metal implementation: **connected-component labelling of the passable pixels inside the loop, keeping every component that does not touch the loop.** These two produce bit-identical results — both answer "which pixels inside the loop are *unreachable* from the loop without crossing ink" — but CC labelling has exact parallel formulations (iterate-to-fixed-point label propagation) where flood fill is a serial wavefront.

The gap-sealing half of the problem is **trapped-ball segmentation** (Zhang, Tian, Wong, Tang & Barsky, "Vectorizing Cartoon Animations," IEEE TVCG 2009, https://cg.cs.tsinghua.edu.cn/papers/TVCG_2009_cartoon.pdf): erode the passable set by a disk of radius *g*, label, dilate back. A channel narrower than 2*g* cannot survive an opening, so gaps seal while genuine sharp corners — which are corners, not narrow channels, and do not disconnect under erosion — survive. This app already has a gap-closing radius, so the erosion/dilation is a fallback, not the primary path (see §6, step 2c).

**This is not an invented scheme.** Krita ships exactly this algorithm as **Enclose and Fill**, and its design document is explicitly an analysis and recreation of Clip Studio Paint's tool. I verified the design doc directly; it states the algorithm in three steps (https://phabricator.kde.org/T14993):

> "Perform several flood fills using the boundary points as seeds… The flood fills should not extend outside the enclosing region."
> "Now we have a mask that represents all the regions inside the enclosing mask that should not be filled, so we have to invert it and intersect it with the enclosing mask."
> "The last step is to subtract from that mask all the regions that are not similar to the chosen color."

## 2. Is the owner's proposal right?

**Yes. Adopt it essentially as stated.** "Run a fill on the outside, where the lasso walls are the seed points. Then you invert the fill so that everything inside gets filled" is, word for word, steps 1–2 of Krita's shipped algorithm, which was itself derived from studying Clip Studio Paint. The owner independently arrived at the convention of the two applications built specifically to solve this problem. It is also structurally the correct fix for the shipped bug: because the loop is the flood's *wall* rather than a thing the flood is trying to reach, the flood is hard-bounded by the loop's own bounding box and **cannot escape to the canvas**, by construction.

Three corrections, all small:

1. **"Invert" must include the ink pixels, not just the enclosed paper.** Krita inverts to get *regions* and leaves the line art alone; the owner's separate requirement is that inner lines are filled over. Taking the complement of the reached set — walls included — satisfies that for free and is why nested holes need no special code (§4, case 5).
2. **The seeds are not "the lasso wall" but "the passable pixels just inside the lasso wall."** A stretch of loop lying on ink contributes no seed. This is not an error condition (§4, case 1).
3. **Reject the fallback.** The obvious objection — "circling blank paper fills nothing, so fall back to filling the loop's own shape" — should be refused, and the owner has already ruled that way. Reasons in §4, case 6/11.

## 2a. What "filled over" means, and what the owner ruled on 2026-08-21

The original requirement was the owner's own: *"all inner lines are filled over."* Asked directly
whether it should hold when the line art sits on the **same layer** being filled — where a raster
fill composites beneath that cel's own strokes, and a vector fill renders beneath strokes by kind
order — they ruled:

> *"if the line art is on the same layer I am filling, its okay that the lineart is not filled over,
> in fact I'd rather keep it that way."*

**So the shipped behaviour is correct and the two BUGS.md entries that tracked it are closed as
not-a-defect, not deferred.** Do not "fix" this later; it is the intended result.

The distinction that still matters, and which this ruling does **not** touch: **the filled *region*
must still extend underneath the ink.** `fill = loopMask ∧ ¬reached` includes wall pixels, and that
is what stops a halo of unfilled paper appearing along every antialiased edge. Lines staying
*visible* is a compositing outcome; the region stopping short of them would be a defect. Keep the
region as it is.

The practical consequence for the artist: a lasso spanning several compartments on one layer fills
all of them, and the dividers stay drawn on top — which is what they want. On the ordinary workflow
(line art on its own layer above the colour) the outcome is the same, for a different reason.

## 3. The rule, for an artist

> **The loop is a fence, and ink is a wall. Anything inside your fence that the fence can walk to — the paper around your drawing, and anywhere it can slip into through a gap — is left untouched. Everything else inside the fence is filled solid, lines and all. So the colour lands inside your shapes and nowhere else: not on the paper between the fence and the drawing, and never on the fence itself.**

That paragraph has no branch and it is the complete rule. Every case in §4 is a consequence of it, including the ones that fill nothing.

## 4. Edge cases, decided

| # | Case | Decision | Why |
|---|---|---|---|
| 1 | **Loop crosses line art** | Not an error. Seed only from loop-adjacent pixels that are themselves passable; a stretch of loop lying on ink contributes no seed and needs no code. | Falls out of the rule. Zero-width collar there. |
| 2 | **Loop drawn entirely inside a solid/dark area** | **Fills nothing** + the signal from §7 — genuinely nothing here, unlike case 4, because there is no ink inside the loop for the complement to keep. | The ring's reference colour becomes that solid colour, the flood consumes the whole interior, nothing is held out. Same code path as case 6. |
| 3 | **Self-intersecting loop** | **Non-zero winding.** Auto-close the path (straight segment, last point → first). | CSP's *Lasso fill* deliberately uses even-odd and documents the figure-eight subtraction as a hair-drawing feature (https://tips.clip-studio.com/en-us/articles/2154) — but that tool's loop *is* the fill shape. Ours is a search region and a wall; a wall must be one closed curve. Even-odd would silently punch a hole in the search region at an accidental stylus overshoot, excluding artwork the artist meant to include. |
| 4 | **Gap wider than the gap-closing radius** — the common real-world failure | **Paints the outline the collar could not enter, and nothing else** — *not* "fills nothing", which is what this cell said until 2026-08-21 and what the shipped code does not do. `fill = loopMask ∧ ¬reached` includes ink, so a leak leaves the line art painted (927 px on the test fixture) and **the §7 empty-result signal therefore never fires on a leak**. Pinned by `testALeakThroughAWideGapPaintsOnlyTheOutlineTheCollarCouldNotEnter`. Do not attempt to out-engineer the leak itself. | The collar escapes through the gap, reaches the far side, and consumes the interior. No shipped application solves this automatically: CSP's own answer to leaks is a manual patch line (https://ask.clip-studio.com/en-us/detail?id=95993), and GIMP's purpose-built endpoint-matching closure concedes that truly open regions "remain unfillable without manual intervention" (https://developer.gimp.org/core/algorithm/line-art-bucket-fill/). What *is* new and cheap here: the reached set is the leak path, so we can draw it. |
| 5 | **Nested shapes — do a face's eyes fill?** | **Yes. The eyes fill the same colour as the face, with no extra code.** | The eyes' interiors are walled off by their own ink and are therefore not reachable from the loop, so they are in the complement. This is the direct consequence of the owner's "all inner lines are filled over": the eye outlines are painted over, so their interiors necessarily are too. **This diverges from every shipped app** — Illustrator Live Paint and CSP both treat nested regions as independently addressable — and the divergence is correct because their fill goes *under or between* line art while ours is explicitly a paint-over. Do not add connected-component target selection; it would contradict the owner's ruling and reintroduce a branch. |
| 6 | **Loop on blank paper, no artwork inside** | **Fills nothing** + the signal. **No fallback to filling the loop's shape.** | The owner ruled on this. It is also the right engineering call: cases 4 and 6 are *indistinguishable* from the algorithm's point of view (both are "the flood reached everything"), so a fallback would turn a leaked fill into a flat colour slab dumped over the artist's line art — a far worse, harder-to-undo outcome than an empty result. If a flat-polygon lasso fill is wanted, it belongs in a **separate tool**, exactly as CSP separates *Lasso fill* from *Enclose and fill* (https://help.clip-studio.com/en-us/manual_en/420_fill/Fill_Tool.htm) and FireAlpaca separates its base mode from the "Closed Area" option (https://firealpaca.net/manual/tool/tool-usage/). |
| 7 | **Antialiased edges / tolerance** | Two thresholds, both already in the shipped vocabulary: **Threshold** (wall test) and **Spread** (how far full opacity extends inside the region). Fill alpha at a boundary pixel = the artwork's own ink coverage there, so the silhouette keeps its original antialiasing. Edge-bleed/grow defaults to **0**. | The classic halo exists because the fill stops short of a *preserved* line. Here the fill consumes the line, so there is no seam to hide and growing outward would only make the shape fatter than the artist drew it. Krita's exact wording: Spread "will make opaque only the pixels that are exactly equal to the selected pixel… 100% will make opaque all the pixels in the region up to its boundary" (https://docs.krita.org/en/reference_manual/tools/fill.html). |
| 8 | **Cost** | Bounded by the loop's bounding box, never by canvas connectivity. A full-canvas loop costs a full-canvas flood; that is the honest ceiling. | This is the actual fix for the shipped bug — the old design's cost and correctness both depended on connectivity the artist does not control. |
| 9 | **Two disjoint doodles inside one loop** | **Both fill**, in one gesture. No target selection, no "pick the largest." | This is the documented headline behaviour of the tool class: CSP's Enclose and fill "can fill complex shapes and shapes with a lot of closed areas in one go" (https://help.clip-studio.com/en-us/manual_en/420_fill/Fill_Tool.htm). |
| 10 | **Loop runs off the canvas edge** | Clip the interior mask to the canvas and treat the clipped edge **as part of the fence** — ring pixels are seeded along it. | Keeps the fence closed. Without this the flood would be seeded from nothing along that stretch and the off-canvas side would wrongly fill. |
| 11 | **Leak vs. blank are the same symptom** | One code path, one outcome (fill nothing), one message that names both possibilities, plus the collar visualisation that lets the artist tell them apart by eye. | Making the tool guess between them is how you get a fallback that destroys artwork. |
| 12 | **Shape pokes out of the loop** | **Not filled.** Falls out: the loop passes through that shape's interior, so the ring seeds inside it and the flood consumes it. | Matches the documented default of both reference apps — Krita: "If a closed region is partially outside of the enclosing region it is not taken into account when filling" (https://phabricator.kde.org/T14993); CSP: "Lines and shapes (figures) that extend beyond the selection will not be filled." Krita's opt-in override is **Include Contour Regions**; do not implement it in v1. |
| 13 | **Degenerate gesture** (tap, < 3 distinct points, enclosed area < 4 px²) | Silent no-op, no message, no undo entry. | A tap is a cancelled gesture, not a failed fill. |

## 5. What shipped applications do, and where this diverges

**Krita — Enclose and Fill** (https://docs.krita.org/en/reference_manual/tools/enclose_and_fill.html) is the direct match and the vocabulary to reuse. This spec is Krita's **"Regions surrounded by transparent"** ("Fill regions that are surrounded by transparent"), extended to **"Regions surrounded by a specific color or transparent"** when the loop's ring sits on an existing flat, with **Include Contour Regions OFF** and **Close Gap** ON. Use those names in code and in any settings UI.

Two deliberate divergences from Krita:

- **We do not ship "All Regions."** That is Krita's "most basic option" and it is precisely the seed-inside-and-grow behaviour that produced this bug report. Offering it as a mode would re-expose the defect under a friendly name.
- **We paint over inner lines.** Krita fills regions and leaves the line art standing. The owner's requirement is a solid paint-over, which we get by including wall pixels in the complement. This is the single biggest behavioural difference from all prior art and it is deliberate.

**Clip Studio Paint** ships the tool Krita reverse-engineered. Its target-colour options are "Area surrounded by black" / "Area surrounded by transparent," and its **Close gap** setting "fills by closing gaps of up to a specified number of pixels" — an independent, orthogonal knob, exactly as here (https://help.clip-studio.com/en-us/manual_en/420_fill/Advanced_Fill.htm, https://www.clip-studio.com/site/gd_en/csp/toolguide/csp_toolguide/100_reference/Closedareafill.htm). CSP's *interior algorithm is not documented anywhere*, official or third-party — that is a real dead end, not a search failure, and Krita's design doc is the best available proxy precisely because its author derived it from testing CSP.

**FireAlpaca** is the closest touch-UI analogue by name — "Lasso Fill" with a "Closed Area" toggle and a "Close the gap" checkbox (https://firealpaca.net/manual/tool/tool-usage/). Its "All" sub-option is the leaky mode; we reject the equivalent.

**Photoshop** (select, then bucket — https://helpx.adobe.com/photoshop/using/tool-techniques/paint-bucket-tool.html), **Procreate** (Selections → Color Fill — https://help.procreate.com/articles/4rymuZ-fill-an-area), **Sketchbook** and **Infinite Painter** all do a flat or seed-clipped fill of the lasso polygon. None solves the ring-of-blank-paper case. They are not evidence against this design; they are the paradigm the owner is explicitly asking us not to build. Procreate users have an open request for exactly this tool (https://folio.procreate.com/discussions/3/1/53226).

**Toon Boom Harmony** reaches a similar *outcome* — one lasso paints every already-closed shape it contains — by a different mechanism (multi-select over vector regions), and its **Close Gap** is a separate four-preset setting plus a manual tool (https://docs.toonboom.com/help/harmony-22/premium/reference/tool-properties/paint-tool-properties.html). Worth knowing; not a model to copy, since we have no pre-closed vector regions.

## 6. Pixel-level specification

Buffers, all at canvas resolution and all passes restricted to the loop's bounding box:

- `R` — the reference composite the tool reads (honour the existing reference-layer setting: all layers vs. current). **The loop's live preview stroke must not appear in `R`;** it is UI, not artwork.
- `loopMask` (1 bit), `reached` (1 bit), `fillAlpha` (8 bit).

**Step 0 — close the gesture.** On lift, append the first path point to the end. If fewer than 3 distinct points or the enclosed area is under 4 px², cancel silently (case 13).

**Step 1 — derive the interior mask.** Rasterise the closed polyline's interior into `loopMask` using the **non-zero winding rule**, clipped to canvas bounds. The fence is the *thin path* (the 1-px rasterised polyline), not the fat visible stroke; path pixels are excluded from `loopMask`. Compute the bbox. The fat stroke is discarded on lift and is never painted — this is the mechanical guarantee behind "the fill shouldn't touch the loop."

**Step 2 — build the passability field.**

- **2a. Ring and reference colours.** `ring` = `loopMask` pixels 8-adjacent to a non-`loopMask` pixel, *including* pixels along a canvas-clipped edge (case 10). Cluster the ring pixels' colours in `R` under the tolerance metric. The reference set `C` = { paper } ∪ { the modal ring cluster, if it is not paper }, where *paper* is alpha < ε on a transparent layer, or the canvas ground colour on an opaque one. Cap `|C|` at 2 — this is Krita's "surrounded by a specific color **or transparent**." Using the *modal* cluster rather than every ring pixel's own colour is what makes a loop traced along a line still behave correctly: the majority of the ring is paper, so ink never becomes a flood reference and therefore always ends up filled over.
- **2b. Distance and passability.** For each `c ∈ C`: `d_c(p)` = colour distance from `R(p)` to `c`; `passable_c(p) = d_c(p) ≤ T` (`T` = the existing Threshold/tolerance).
- **2c. Gap closing — applied here, once, to the artwork only.** Run the app's existing gap-closing pass against the ink (`¬passable_c`) so gaps up to radius `g` are sealed. **Never apply gap closing to the loop** — the loop is already a solid, continuous wall, and dilating it would eat the collar. If the existing mechanism is a seed-time trick rather than a standalone mask operation, substitute a morphological opening, `passable_c ← δ_g(ε_g(passable_c))` with a disk of radius `g`; that is trapped-ball's sealing step and it provably cannot reconnect across a channel narrower than 2*g*. Known cost of the opening variant: a genuinely narrow paper collar (thinner than 2*g*) is dropped from the collar and therefore gets filled — a small over-fill. Keep `g` at the existing few-pixel value.

**Step 3 — the collar flood.** `reached` = the union over `c ∈ C` of all pixels in `loopMask ∧ passable_c` that are 8-connected to a `ring` pixel which is itself in `passable_c`. **The flood must never leave `loopMask`** — that single constraint is the whole leak fix. Implement either as a bbox-bounded scanline flood on the CPU (fast; the region is small) or as an iterate-to-fixed-point label-propagation compute kernel. **Do not use jump flooding** — it is an approximate algorithm (https://en.wikipedia.org/wiki/Jump_flooding_algorithm) and a fill boundary must be exact. The reached set is a fixed point, so it is iteration-order independent and deterministic regardless of which you choose.

**Step 4 — invert.** `fill = loopMask ∧ ¬reached`. Note that this *includes ink pixels*: that is "all inner lines are filled over," and it is the same line of code that makes a face's eyes fill (case 5).

**Step 5 — the empty check.** Count `fill` with an atomic in the step-4 kernel. If the count is 0 (or under 4 px²) → **commit nothing, create no undo entry**, and go to §7.

**Step 6 — antialiasing.** Let `d_min(p) = min_c d_c(p)` and let `s ∈ [0,1]` be Spread. Define coverage `k(p) = clamp((d_min(p) − sT) / (T − sT), 0, 1)`. Then:

```
fillAlpha(p) = 1        if p ∈ fill        (unreached: interior, and ink)
fillAlpha(p) = k(p)     if p ∈ reached     (collar: 0 on clean paper, partial on the line's outer fringe)
fillAlpha(p) = 0        otherwise
```

The filled shape therefore inherits the artwork's own edge softness: the outer fringe of the silhouette fades from fill colour to paper exactly as the original line faded.

**Step 7 — grow/bleed.** Optional dilation by `G` px (Krita's *Grow Selection*, CSP's *Area scaling*). **Default `G = 0`**, and say so in the settings: because the fill covers the line rather than stopping at it, there is no seam to hide, and a positive `G` only makes the shape fatter than drawn.

**Step 8 — composite.** `fillAlpha × fillColor` onto the active layer with the tool's blend mode. One undo entry per fill.

## 7. When there is nothing to fill

Silently doing nothing is a broken-tool experience, and there is direct evidence for that: Krita users hit exactly this and report only that "it just won't fill anything" (https://krita-artists.org/t/enclose-and-fill-not-working/55071, https://krita-artists.org/t/please-help-me-understand-the-enclose-and-fill-tool/75576). **I could not find any documentation of Krita or CSP giving a diagnostic when the enclosure yields nothing** — the absence is itself the finding, and it is where we can be better than both.

On an empty result:

1. **Commit nothing and push no undo entry.** The artist must not have to undo a no-op.
2. **Show the collar.** Render `reached` as a translucent tint (a warning hue, ~40% alpha) held for ~0.8 s and fading. This is the single most valuable thing the architecture gives us for free: the collar *is the leak path*, so on a gap the artist sees the colour visibly pour out through the gap and knows exactly which pixel to patch. The nearest shipped analogue is OpenToonz's Gap Check, which highlights closeable gaps in magenta (https://opentoonz.readthedocs.io/en/latest/painting_animation_levels.html); CSP has nothing equivalent and its forums have been asking for it for years.
3. **One line of text**, naming both causes because they are genuinely indistinguishable (case 11): *"Nothing enclosed — the fill leaked through a gap in the line, or there was no shape inside the loop."* If a flat lasso-fill tool exists, add *"To fill a plain area, use Lasso Fill."*
4. Redraw the loop path itself for the same 0.8 s so the artist sees the fence they actually drew (stylus loops often close somewhere other than where the artist believed).

Do **not** add a partial-result warning for small-but-nonempty fills. A small fill is usually intentional and a false warning is worse than none.

### What §7.2 turned out to be, once it was built (2026-08-19)

**The collar tint cannot show a leak, because a leak is not an empty result.** Item 2 above was written on the reasoning that the reached set is the escape route, so the artist would watch the colour pour out through the gap. Two things in this same document make that unreachable:

- §6 step 4's `fill = loopMask ∧ ¬reached` includes ink, because ink is never passable. A leaked fill therefore still paints the outline's own pixels — measured at 927 px on the test box — so `lastFilledPixelCount` is nowhere near the step-5 empty threshold and **the signal does not fire**.
- Conversely, an empty result *means* the collar reached everything inside the fence. So on the one path where the tint is displayed, it is congruent to the loop's interior, every time.

The tint is still worth shipping and is shipped: an orange wash filling the fence states *"every pixel in here counted as background"* far more directly than an outline does, and paired with §7.4's redrawn fence it separates the two causes the sentence names — a loop around blank paper looks nothing like one that closed early somewhere its owner did not intend. But it is a picture of **why nothing was enclosed**, not a picture of a leak, and the code says so where it used to claim otherwise.

A leak still announces itself, just differently: only the line gets coloured. Whether that deserves its own signal is an open question for the owner. Detecting it properly means asking whether any ink component inside the loop encloses a region the collar walked into, which is the connected-component analysis §4 case 5 rules out of the fill path — it would be diagnostic-only, so the ruling does not forbid it, but it is new work rather than a correction.

## 8. Open risks

**Needs the owner's eye on the device, not a test:**

- **Paint-over destroys the outline on a single-layer sketch.** Since the complement includes the silhouette's ink, filling on the *same* layer as the line art consumes the outline and the shape becomes a solid blob. That is the literal reading of "all inner lines are filled over," but the owner should see it happen on real artwork before we call it settled. The likely resolution is that this tool defaults to filling on a layer *beneath* the line art — that is a product decision, not an algorithm change, and it should not be guessed.
- **The collar tint on failure** — whether it reads as a helpful diagnostic or as a rendering glitch is a judgement only the owner can make, on the device, with the tint colour and duration in front of them.
- **Tolerance and Spread against the owner's actual brushes.** GIMP documents that textured brushes wreck this class of algorithm — "creates excessive keypoints… potentially slowing processing and generating spurious closed zones" (https://developer.gimp.org/core/algorithm/line-art-bucket-fill/). A clean simulator test with a hard round brush proves nothing about a textured pencil. This must be exercised with the owner's real line art.
- **Non-zero winding on a self-crossing loop** is correct by construction but "does it feel right when I overshoot" is not unit-testable.

**Engineering risks:**

- **A gap wider than `g` silently produces nothing.** This is unsolved industry-wide and we are not going to solve it; the mitigation is entirely the §7 signal. Expect it to be the top support question. **Measured once built (2026-08-18): it does not produce *nothing*, it produces the outline.** A leaked collar reaches the interior but cannot walk through ink, so the ink is in the complement and is painted — 927 px of recoloured outline on the test fixture rather than 6,561 px of filled shape. That follows from step 4 as written, and the only way to suppress it is the connected-component filter §4 case 5 forbids (it would also un-fill a face's eyes). Consequence: the §7 message does not fire on a leak, because the result is not empty. `LassoFillLogicTests.testALeakThroughAWideGapPaintsOnlyTheOutlineTheCollarCouldNotEnter` pins it.
- **Ring straddling paper and an existing flat.** With `|C|` capped at 2 and the reference chosen by mode, a minority-colour collar gets filled rather than held out. Documented limitation; the escape hatch is exposing Krita's "or a specific color" reference explicitly.
- **Large-loop cost.** A loop spanning most of the canvas costs a near-full-canvas flood. Bounded by something the artist controls, which the old design was not, but it still wants a measurement rather than an assumption — profile a worst-case loop before shipping.
- **Undo granularity and the empty case.** Verify by test that an empty result pushes no undo entry; a no-op that eats an undo slot is a bug artists will notice immediately.
