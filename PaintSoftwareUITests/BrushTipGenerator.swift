import UIKit
import CoreGraphics

/// **BRUSH.md §12 stage 9's tip generator** — the procedural half of §8.4's *"generate Basics,
/// Sketching, Inking and Painting; source CC0 only for Texture"*.
///
/// **It is a build-time tool whose output is committed, not a runtime cost.** §12 stage 9 rules
/// that explicitly — *"a tip is a small alpha bitmap and generating it per launch buys nothing"* —
/// which is why this lives in the test target beside `DabCostBench` rather than in `Engine`.
/// Nothing in the app links it; `BrushContactSheetBench` runs it, writes the PNGs, and the owner
/// picks from the sheet. Only once they have picked does a chosen PNG become a
/// `BuiltInBrushTexture` case with its bytes committed to `Resources/`.
///
/// **Deterministic by construction, and that is the property that makes committing safe.** Every
/// value here comes from `splitmix64` over integer lattice coordinates and a written-down seed —
/// there is no `Double.random`, no `arc4random`, no clock and no dictionary iteration order in the
/// output path. Regenerating gives the identical bytes, so a committed PNG can always be shown to
/// be the one this file draws. `BrushTipGeneratorLogicTests` is the assertion.
///
/// **§8.4's boundary paragraph is what this catalogue is now organised around, and it moved on the
/// second contact sheet.** The rule is not *"a tip contributes no roughness"* — it is:
///
/// > Roughness survives when what a dab presents to the silhouette changes from dab to dab.
///
/// So an **eroded round** nib buys nothing (every dab offers the same profile, and ten overlapping
/// dabs take its running maximum), a **direction-locked** nib buys nothing on its swept sides, and
/// an **asymmetric** nib under `angle.jitter` does: rotating an uneven shape changes its outline
/// where rotating a disc changes nothing at all. **Asymmetry and rotation multiply; neither works
/// alone**, and interior grain is exempt because a pit mid-dab is not filled by a neighbour's
/// boundary. Every rough shape below carries both halves, or is a deliberate control that carries
/// one — `rough-ink-eroded-round` is §8.4's own refuted nib, drawn so the owner can see the cell of
/// the 2×2 that is supposed to fail.
///
/// **What is still deliberately not generated:**
///
/// - **Soft and hard round, the technical pens, and the opaque round.** `BrushTip.round` already
///   *is* a disc with a falloff; §8.4's *"a hard round is a disc, a soft round a falloff"* is a
///   description of the procedural arm, not an instruction to draw one.
/// **The Texture group is generated too, and that was an open question until round four.** §8.4
/// ruled *"source CC0 only for Texture, where scanned grunge and splatter are genuinely hard to
/// fake"*; §13 asked whether eleven shipped tips had made that obsolete. They had. The four Texture
/// nibs turn on three things the earlier rounds had not put together — **holes at floor 0** rather
/// than a mottle, a **spacing of 0.09–0.46** where every other group walks at 0.03–0.095, and
/// §2.25's **canvas-anchored paper**, which merges once per stroke and is therefore the one texture
/// in this engine that §8.4's union argument cannot reach.
///
/// **A tip's silhouette has to be discriminating, and that is checked rather than assumed.** §12
/// stage 5 records the trap in this document's own back yard: *"a tip that fills its mask is
/// indistinguishable from the committed square, so an assertion built on that arm alone would be
/// green against a stamper that ignored the tip"*. Every shape below leaves a clear corner, a clear
/// gap, or both — and `BrushTipGeneratorLogicTests` stamps each one against `.builtIn(.square)` and
/// requires the pixels to differ.
enum BrushTipGenerator {

    /// The mask side and border every tip is drawn at — `BrushTipImport`'s, so a generated tip and
    /// an artist's imported one are the same kind of file. 256² at a 2 px transparent border is
    /// `BuiltInBrushTexture.square`'s own specification, and the border is what a rotated or
    /// downscaled draw antialiases into.
    static let side: Int = BrushTipImport.maskSide
    static let border: Int = BrushTipImport.border

    /// Half the usable span, in mask pixels: 128 - 2. Normalised tip coordinates run `-1…1` over
    /// exactly this, so `|u| > 1` is inside the transparent border by construction and no shape can
    /// reach the edge however it is authored.
    static let halfSpan: Float = Float(side / 2 - border)

    /// One mask pixel, in normalised tip units. The natural width for a "hard" edge: anything
    /// narrower is a step, anything wider is visibly soft at the sizes a nib is used.
    static let pixel: Float = 1 / halfSpan

    // MARK: - What a generated tip is

    struct Tip {
        /// The candidate's own name, e.g. `square-slab-4to1`. Stable — it is what the contact sheet
        /// prints and what a committed `BuiltInBrushTexture` case would be named after.
        let name: String
        /// The file it is written under in `BrushStorage`. Deterministic rather than a UUID, so a
        /// regeneration overwrites its own file instead of littering the library.
        let fileName: String
        /// Row-major coverage, `side * side` bytes, top row first. The generator's real output —
        /// `png` is this run through ImageIO, and the determinism assertion is on both.
        let alpha: [UInt8]
        let png: Data

        var textureRef: BrushTextureRef { .imported(fileName: fileName) }
        var tip: BrushTip { .stamp(textureRef) }
    }

    // MARK: - The catalogue

    /// Every generated tip, in a fixed order. An array rather than a dictionary for the reason
    /// `BrushModulations` is one: iteration order has to be a property of the source, not of a hash
    /// seed, or "generate twice and compare" is testing the wrong thing.
    static func generateAll() -> [Tip] {
        shapes.map { render($0) }
    }

    static let shapes: [Shape] = [

        // MARK: Basics — §8.6's two square nibs

        // **"Square" — the clean one.** The owner: *"slab with no noisy edges, and beveled corners,
        // softness sort of like opaque round in that it only falls off in the very edges."* Round
        // one's ragged square slabs are gone rather than kept beside these: §8.4's boundary
        // paragraph says a direction-locked nib's ragged edge cannot survive the walk, the first
        // sheet showed it washing out, and the owner picked a clean nib in its place.
        //
        // Three variants, and they differ in the two things the sentence above names: how much
        // corner is cut, and how wide the falloff band is.
        // **The falloff numbers are calibrated against Opaque Round rather than chosen**, because
        // that is what the owner's sentence asks for. Opaque Round is `hardness 0.8`, which is a
        // gradient over the outer fifth of the radius; a fifth of this nib's *short* half-axis is
        // about 0.05 in tip units. So 0.028 is crisper than Opaque Round, 0.110 is softer, and
        // 0.055 is the match — and the first render of this sheet is why they are spread that far:
        // at 0.028 against 0.075 the two strokes were indistinguishable at 26 pt.
        Shape(name: "square-bevel-tight", seed: 0x5148_0101,
              body: { u, v, _ in bevelSlab(u, v, aspect: 4.0, bevel: 0.10, falloff: 0.028) }),

        Shape(name: "square-bevel-soft", seed: 0x5148_0102,
              body: { u, v, _ in bevelSlab(u, v, aspect: 4.0, bevel: 0.10, falloff: 0.110) }),

        Shape(name: "square-bevel-wide", seed: 0x5148_0103,
              body: { u, v, _ in bevelSlab(u, v, aspect: 2.5, bevel: 0.20, falloff: 0.055) }),

        // **"Messy Flat" — the ends, and only the ends.** *"Like the flat brush, except with messier
        // ends. Still square, but the sprite gives it a unique non monolithic look for the ends,
        // more of a slightly dirty falloff."* §8.4's fourth finding is why the long sides are left
        // clean: with `base 0.25` and `directionFollow 1` they sweep *along* the travel and never
        // reach the silhouette, so roughening them roughens nothing an artist will see.
        //
        // **Round three turns the dirt through ninety degrees**, which is the owner's second tweak
        // off the second sheet and is `comb`'s whole note: this nib's mask `u` is the *across-stroke*
        // axis, so a comb in `u` traces ribbons along the drag and a comb in `v` — round two's —
        // rakes across it.
        Shape(name: "flat-messy-ends", seed: 0x5148_0111,
              body: { u, v, s in messyEndSlab(u, v, s, aspect: 4.0, endRough: 0.10,
                                              endFade: 0.26, dirt: 0.90, sideSoft: 0.035) }),

        Shape(name: "flat-messy-ends-dirty", seed: 0x5148_0112,
              body: { u, v, s in messyEndSlab(u, v, s, aspect: 3.2, endRough: 0.17,
                                              endFade: 0.42, dirt: 1.0, sideSoft: 0.055) }),

        // MARK: Sketching — four pencils, unchanged and accepted off the first sheet

        // **A pencil is a mid-frequency noise threshold** (§8.4) on an irregular nib. The four differ
        // in the grain's frequency and how hard it is thresholded, which is what separates a hard
        // pencil's tooth from a soft one's smear, plus the nib's own outline.
        Shape(name: "pencil-hard", seed: 0x5148_0011,
              grain: Grain(frequency: 26, octaves: 2, floor: 0.05, threshold: 0.44, softness: 0.16),
              body: { u, v, s in nib(u, v, s, radius: 0.74, wobble: 0.10, wobbleFrequency: 5.5,
                                     edge: 1.6 * pixel, falloff: 0.05) }),

        Shape(name: "pencil-soft", seed: 0x5148_0012,
              grain: Grain(frequency: 13, octaves: 2, floor: 0.34, threshold: 0.30, softness: 0.42),
              body: { u, v, s in nib(u, v, s, radius: 0.95, wobble: 0.07, wobbleFrequency: 4.0,
                                     edge: 1.6 * pixel, falloff: 0.34) }),

        // **Blunt** — a worn nib, flattened on one side and wider than it is tall. **The owner read
        // this mask off the first sheet and it is what §8.4's boundary paragraph is built from**:
        // the sharp cutoff along the bottom makes the shape uneven, and under `angle.jitter` an
        // uneven shape presents a different outline at every dab. It had both halves by accident;
        // the Rough Ink family below has them on purpose.
        Shape(name: "pencil-blunt", seed: 0x5148_0013,
              grain: Grain(frequency: 9, octaves: 2, floor: 0.22, threshold: 0.26, softness: 0.34),
              body: { u, v, s in
                  let body = nib(u, v * 1.30, s, radius: 0.94, wobble: 0.09, wobbleFrequency: 3.5,
                                 edge: 1.6 * pixel, falloff: 0.10)
                  // The worn flat: everything past v = 0.30 is ground away.
                  return body * step(0.30 - v, 3 * pixel)
              }),

        // **Textured** — coarse enough that the holes survive into the stroke. §8.4's warning is
        // about *edge* erosion on a round tip; interior pits at this frequency are a different
        // mechanism and do survive the union, because a neighbouring dab's pits are at a different
        // phase only when the tip is also rotated per dab.
        Shape(name: "pencil-textured", seed: 0x5148_0014,
              grain: Grain(frequency: 6.5, octaves: 3, floor: 0.0, threshold: 0.46, softness: 0.13),
              body: { u, v, s in nib(u, v, s, radius: 0.96, wobble: 0.06, wobbleFrequency: 3.0,
                                     edge: 1.6 * pixel, falloff: 0.12) }),

        // MARK: Inking — the brush pen's nib, and §8.6's one piece of open design

        // **A brush pen's nib is a teardrop that lies along the travel**, which is `directionFollow`
        // at 1 with no base turn. The taper an artist sees is mostly `size ← pressure`; what the
        // *shape* adds is the asymmetry — the trailing end is blunter than the leading one, so a
        // stroke that turns leaves a slightly different edge on the inside of the curve.
        Shape(name: "pen-brush", seed: 0x5148_0021,
              body: { u, v, _ in teardrop(u, v, halfHeight: 0.50, point: 0.72, lean: 0.22,
                                          soft: 0.20) }),

        // **Rough Ink — the three shapes the owner named, plus the control that is meant to fail.**
        // *"A potential candidate is a triangular sprite … Or maybe a rough squareish shape, or a
        // half round half flat shape like pencil blunt could just work if its totally isotropically
        // randomized."* All three are grossly asymmetric on purpose; `BrushCandidates` turns each
        // of them at `angle.jitter 1`, which is ±half a turn — isotropic.
        Shape(name: "rough-ink-triangle", seed: 0x5148_0031,
              grain: Grain(frequency: 7.0, octaves: 2, floor: 0.72, threshold: 0.0, softness: 1.0),
              body: { u, v, s in roughTriangle(u, v, s, radius: 0.46, rough: 0.15,
                                               cornerCap: 0.80) }),

        Shape(name: "rough-ink-square", seed: 0x5148_0032,
              grain: Grain(frequency: 8.0, octaves: 2, floor: 0.74, threshold: 0.0, softness: 1.0),
              body: { u, v, s in roughSquarish(u, v, s, rough: 0.17, lean: 0.22) }),

        Shape(name: "rough-ink-halfflat", seed: 0x5148_0033,
              grain: Grain(frequency: 7.5, octaves: 2, floor: 0.76, threshold: 0.0, softness: 1.0),
              body: { u, v, s in halfRoundFlat(u, v, s, radius: 0.86, cut: 0.30, rough: 0.09) }),

        // **The control, and it is a control rather than a candidate.** §8.4 MEASURED an eroded
        // round nib at 0.41% of a brush width of edge roughness in a stroke against 1.08% as a lone
        // dab: every dab presents the same profile and a neighbour fills each notch. Drawn here so
        // that the *sheet* carries the negative result beside the positive ones instead of the
        // document carrying it alone — if this row reads as rough as the triangle, the boundary
        // paragraph is wrong and the whole family collapses back to §8.4's first answer.
        Shape(name: "rough-ink-eroded-round", seed: 0x5148_0034,
              body: { u, v, s in nib(u, v, s, radius: 0.84, wobble: 0.11, wobbleFrequency: 15.0,
                                     edge: 1.4 * pixel, falloff: 0) }),

        // MARK: Painting — the painterly nib, five ways

        // **The owner's reference, verbatim**: real paint-stroke sprites are *"a lot more squarish
        // than slab shaped, though the shape is alot more blotchy than square, with a clear bristle
        // direction noticeable in them."* So every one of these is a **superellipse** (squarish, not
        // a slab, not an oval) at an aspect near 1, with a blotchy boundary and horizontal streaks
        // running along its long axis — which `directionFollow 1` lays along the travel.
        //
        // They span §8.6's four sprite families: jagged outlines, bristle streaks, soft slabs and
        // dry speckle.
        // **The streak depths are near 1 and the first render is why.** At 0.3 the bands are
        // *shading* rather than gaps, and a stroke lays twenty-odd overlapping dabs over every
        // point — so the accumulation fills every band in and all five rows rendered as identical
        // black slabs. §8.4's exemption for interior structure is real but it is not unconditional:
        // what survives a union is a **hole**, not a dimming. Streaks that reach zero survive;
        // streaks at 30% do not.
        Shape(name: "paint-blotchy", seed: 0x5148_0041,
              body: { u, v, s in painterly(u, v, s, aspect: 1.15, exponent: 4.0, blob: 0.16,
                                           streaks: 14, streakDepth: 0.97, streakCut: 0.30,
                                           edge: 0.045, dry: 0.30) }),

        Shape(name: "paint-streaky", seed: 0x5148_0042,
              body: { u, v, s in painterly(u, v, s, aspect: 1.35, exponent: 5.0, blob: 0.10,
                                           streaks: 20, streakDepth: 1.0, streakCut: 0.46,
                                           edge: 0.030, dry: 0.35) }),

        Shape(name: "paint-jagged", seed: 0x5148_0043,
              body: { u, v, s in painterly(u, v, s, aspect: 1.10, exponent: 3.5, blob: 0.28,
                                           streaks: 9, streakDepth: 0.94, streakCut: 0.24,
                                           edge: 0.025, dry: 0.55) }),

        Shape(name: "paint-soft-slab", seed: 0x5148_0044,
              body: { u, v, s in painterly(u, v, s, aspect: 1.55, exponent: 4.5, blob: 0.09,
                                           streaks: 7, streakDepth: 0.55, streakCut: 0.20,
                                           edge: 0.190, dry: 0.15) }),

        Shape(name: "paint-dry-load", seed: 0x5148_0045,
              grain: Grain(frequency: 11, octaves: 3, floor: 0.30, threshold: 0.30, softness: 0.45),
              body: { u, v, s in painterly(u, v, s, aspect: 1.25, exponent: 4.0, blob: 0.21,
                                           streaks: 12, streakDepth: 0.90, streakCut: 0.26,
                                           edge: 0.035, dry: 0.70) }),

        // **Bristle, with the oval taken out of it.** The owner on round one's: *"Right now you can
        // see it fit within a clear oval shape."* That was literal — every filament was multiplied
        // by one shared elliptical envelope, so the nib's silhouette **was** that ellipse however
        // the filaments fell inside it. `openBristle` gives each filament its own two ends and its
        // own taper and multiplies by nothing shared, so the outline is the filaments.
        Shape(name: "bristle-open", seed: 0x5148_0051,
              body: { u, v, s in openBristle(u, v, s, filaments: 11, spread: 0.46,
                                             breakUp: 0.55) }),

        Shape(name: "bristle-open-dense", seed: 0x5148_0052,
              body: { u, v, s in openBristle(u, v, s, filaments: 17, spread: 0.52,
                                             breakUp: 0.70) }),

        // **Streaky — *"the sprite being just a bunch of little dots, like 6 or 8 of them placed
        // randomly. The brush makes many streaks."*** Separated points, so one drag lays parallel
        // ribbons rather than a band. `BrushCandidates` gives these `directionFollow 1` and
        // **jitter 0**, which is the one place on this sheet where rotation jitter is wrong: turning
        // the dot pattern per dab smears the ribbons back into a band.
        //
        // The two differ in how the dots are placed, which is the question the ask leaves open.
        // Stratified across the nib guarantees six distinct ribbons; a uniform draw is what *"placed
        // randomly"* says literally and lets two dots share a ribbon.
        // **The radii are halved from round two at the owner's instruction** — *"make the dots a
        // bit smaller, at least half the radius. Ill go with the 6 dots option."* Round two drew
        // 0.10–0.17; these are 0.05–0.085, which at a 30 pt brush is a ribbon 1.5–2.5 pt wide.
        // The placement is unchanged: stratified, so six distinct ribbons are guaranteed.
        Shape(name: "streak-dots-6", seed: 0x5148_0061,
              body: { u, v, s in dots(u, v, s, count: 6, stratified: true,
                                      minRadius: 0.050, maxRadius: 0.085) }),

        Shape(name: "streak-dots-8", seed: 0x5148_0062,
              body: { u, v, s in dots(u, v, s, count: 8, stratified: false,
                                      minRadius: 0.045, maxRadius: 0.075) }),

        // MARK: Texture — §13's open question, asked of the generator
        //
        // **§8.4 rules *"source CC0 only for Texture, where scanned grunge and splatter are
        // genuinely hard to fake"*, and §13 asks whether that is still true now the generator has
        // made eleven shipped tips.** These are the attempt. Everything the first three rounds
        // learned governs them and none of it is optional:
        //
        // - Every one is **grossly asymmetric** and carried at `angle.jitter 1`, because §8.4's
        //   boundary paragraph is that asymmetry and rotation multiply and neither works alone.
        // - Interior structure reaches **zero**, never a dimming — twenty overlapping dabs turn 0.2
        //   of coverage into 0.92.
        // - And they are authored to be stamped **far apart**. §8.4: *"anything whose character is
        //   in its pixels needs the dabs far enough apart to be seen one at a time."* Every shipped
        //   brush before this walks at 0.03–0.095; these want 0.25–0.7, which is where a paint
        //   program's grunge and splatter brushes have always sat and is the one dial nobody on this
        //   sheet had turned.

        // **Grunge — a crust, not a blob.** The gross shape is a lobed disc whose radius swings by a
        // third, so a turn presents a genuinely different outline; on top of it a coarse tear, a dry
        // broken outer band, and a `Grain` whose floor is **0** so the interior is holes rather than
        // mottle. The two differ only in how coarse the holes are: `crust` is a sponge print, `soot`
        // a finer deposit that survives a smaller brush.
        Shape(name: "grunge-crust", seed: 0x5148_0071,
              grain: Grain(frequency: 5.0, octaves: 3, floor: 0.0, threshold: 0.47, softness: 0.09),
              body: { u, v, s in grungeBlob(u, v, s, radius: 0.80, lobes: 0.26, bite: 0.20,
                                            dry: 0.65) }),

        Shape(name: "grunge-soot", seed: 0x5148_0072,
              grain: Grain(frequency: 11.0, octaves: 3, floor: 0.0, threshold: 0.44, softness: 0.14),
              body: { u, v, s in grungeBlob(u, v, s, radius: 0.84, lobes: 0.22, bite: 0.26,
                                            dry: 0.50) }),

        // **Splatter — a cluster of drops whose radii come off a cube law.** That is the whole of
        // what separates a splatter from a field of dots: one or two drops carry most of the ink and
        // the rest are specks, so a stamp has a *shape* rather than a texture. Each drop's own
        // boundary is torn on the unit circle (`nib`'s wrap trick) so nothing here is a disc.
        // **Thirteen drops at a 0.44 maximum was the first render and it was wrong**: the cube law
        // gave two or three *large* blobs a stamp and almost no specks, so a drag laid a chain of
        // fat dots. What a splatter needs is the other end of the same law — one or two carriers
        // and a crowd of flecks, spread nearly to the mask's edge so the flecks land off the path.
        Shape(name: "splatter-drops", seed: 0x5148_0081,
              body: { u, v, s in splatterCluster(u, v, s, drops: 26, spread: 0.86,
                                                 minRadius: 0.014, maxRadius: 0.30, tear: 0.22) }),

        // **No carriers at all** — every drop small, spread nearly to the edge. Round two had this
        // at a 0.24 maximum and the elongation merged its drops into one blot; a mist is a mist
        // because nothing in it is large.
        Shape(name: "splatter-fine", seed: 0x5148_0082,
              body: { u, v, s in splatterCluster(u, v, s, drops: 20, spread: 0.90,
                                                 minRadius: 0.014, maxRadius: 0.14, tear: 0.25) }),

        // **Stipple — the tipped arm of the question.** §2.18's `density` on a plain round tip is
        // the other arm and needs no picture at all; this is what a picture adds, which is that a
        // single stamp is already several dots of different sizes. Hard-edged on purpose: a stipple
        // whose dots are feathered reads as spray.
        Shape(name: "stipple-specks", seed: 0x5148_0091,
              body: { u, v, s in speckle(u, v, s, count: 17, spread: 0.80,
                                         minRadius: 0.030, maxRadius: 0.105) }),

        // **Chalk — a worn stick, squarish and torn, with the pits doing the work.** The body is a
        // superellipse the way the painterly nibs are, but the boundary is torn at two scales
        // instead of combed and the `Grain` floor is 0, so the interior is holes. What this nib is
        // *for* is to be laid through §2.25's canvas-anchored paper, which is the route that did not
        // exist when §8.4 was written — see `BrushCandidates`' Chalk rows, which are the A/B.
        Shape(name: "chalk-block", seed: 0x5148_00A1,
              grain: Grain(frequency: 7.5, octaves: 3, floor: 0.0, threshold: 0.40, softness: 0.20),
              body: { u, v, s in chalkBlock(u, v, s, aspect: 1.45, exponent: 3.2, tear: 0.17,
                                            edge: 0.045) }),

        Shape(name: "chalk-worn", seed: 0x5148_00A2,
              grain: Grain(frequency: 4.5, octaves: 2, floor: 0.0, threshold: 0.34, softness: 0.30),
              body: { u, v, s in chalkBlock(u, v, s, aspect: 1.15, exponent: 2.6, tear: 0.24,
                                            edge: 0.090) })
    ]

    // MARK: - The shape vocabulary
    //
    // Every one takes normalised tip coordinates `u, v` in `-1…1` and answers coverage in `0…1`.
    // They are pure functions of their arguments and the seed, which is the whole of what "seeded,
    // deterministic" means here.

    /// **§8.6's "Square"** — a slab with **no noisy edges**, chamfered corners, and a falloff band
    /// narrow enough that it *"only falls off in the very edges"*.
    ///
    /// The three distances are all in **tip units**, not in each axis's own normalised units, which
    /// is what makes the falloff the same physical width on a long side, an end and a chamfer. A
    /// normalised-per-axis distance would feather a 4:1 nib's ends four times as wide as its sides
    /// and read as a lozenge.
    static func bevelSlab(_ u: Float, _ v: Float,
                          aspect: Float, bevel: Float, falloff: Float) -> Float {
        let hu: Float = 0.96
        let hv: Float = hu / aspect
        let du: Float = hu - abs(u)
        let dv: Float = hv - abs(v)
        // The chamfer is the line through (hu - bevel, hv) and (hu, hv - bevel); this is the
        // perpendicular distance inward from it, which is what keeps the cut a straight bevel
        // rather than the rounded corner a radial metric would give.
        let dc: Float = (hu + hv - bevel - abs(u) - abs(v)) * 0.70710678
        return smoothFalloff(min(min(du, dv), dc), max(falloff, 1.2 * pixel))
    }

    /// **§8.6's "Messy Flat"** — the same slab with the *ends* broken up and the long sides left
    /// alone, because §8.4's fourth finding is that a direction-locked nib's long sides sweep along
    /// the travel and never reach the silhouette.
    ///
    /// Three things happen at the end and they are separable on purpose: the boundary itself is
    /// displaced (`endRough`), it fades rather than cuts, and over the last `endFade` of the nib the
    /// coverage is multiplied by a **comb** (`dirt`) so the end is *"non monolithic"* rather than a
    /// softer straight line.
    ///
    /// **The comb runs across `u` and not across `v`, and round two had it the other way round.**
    /// The owner, on the second sheet: *"the bristle direction for those slab brushes is pointing
    /// the wrong way, perpendicular to the brush stroke direction."* They are right, and this nib is
    /// where mask space and stroke space part company — see `comb`'s own note. The dirt was an
    /// `fbm2` whose `v` coefficient was `aspect * 5.5` against `7.5` in `u`, so its structure was
    /// elongated **along `u`**; with `base 0.25` and `directionFollow 1` that lands it across the
    /// travel. It is a comb in `u` now, so each tooth keeps one fixed offset from the path and draws
    /// a ribbon along the drag.
    static func messyEndSlab(_ u: Float, _ v: Float, _ seed: UInt64,
                             aspect: Float, endRough: Float, endFade: Float,
                             dirt: Float, sideSoft: Float) -> Float {
        let hu: Float = 0.94
        let hv: Float = hu / aspect
        let dv: Float = hv - abs(v)
        guard dv > 0 else { return 0 }
        var coverage: Float = smoothFalloff(dv, max(sideSoft, 1.2 * pixel))

        let end: Float = hu * (1 + endRough * ragged(v * aspect * 2.1 + 4.7, seed &+ 3))
        let du: Float = end - abs(u)
        guard du > 0 else { return 0 }
        coverage *= smoothFalloff(du, max(endFade * 0.30, 1.2 * pixel))

        // The fringe is the outer `endFade` of the nib in `u`, which is where the stroke's two
        // *edges* live — so the teeth are ribbons at the edge of the band rather than a texture in
        // the middle of it, which is what *"a slightly dirty falloff"* asks for.
        //
        // **The comb carries its own envelope rather than riding the coverage falloff's, and the
        // first render of round three is why.** Blended as `t + (1 - t) · comb` the teeth reach
        // their full depth only in the outermost sliver, and eight overlapping dabs at flow 0.85
        // accumulate everything shallower straight back to opaque: the render came out as a row of
        // fine ticks rather than as ribbons. `reach` holds the teeth at full depth over the outer
        // 55% of the fringe and closes them by its inner edge, which is a real width for a hole to
        // live in. §8.4's *"what survives is a hole, not a dimming"* is unchanged by turning the
        // comb the right way round — orientation decides whether a tooth is a ribbon or a rake,
        // depth decides whether it is there at all.
        let reach: Float = min(max((endFade - du) / (0.45 * endFade), 0), 1)
        let bristles: Float = comb(across: u, along: v * aspect, seed &+ 9,
                                   teeth: 12, depth: dirt, cut: 0.40)
        return coverage * (1 - reach * (1 - bristles))
    }

    /// A pencil's outline: a disc whose radius wobbles with the angle, optionally fading over the
    /// last `falloff` of it. Also the **eroded round control** — at a high `wobbleFrequency` and no
    /// falloff this is exactly the nib §8.4 measured and refuted.
    ///
    /// The angular noise is sampled on the **unit circle** rather than on an angle, so it wraps: a
    /// 1-D noise indexed by `atan2` has a seam at `-π`, which shows up as one straight facet on
    /// every dab and is exactly the sort of artifact a repeated stamp turns into a stripe.
    static func nib(_ u: Float, _ v: Float, _ seed: UInt64,
                    radius: Float, wobble: Float, wobbleFrequency: Float,
                    edge: Float, falloff: Float) -> Float {
        let r: Float = sqrt(u * u + v * v)
        guard r > 1e-4 else { return 1 }
        let cx: Float = u / r, cy: Float = v / r
        let n: Float = value2(cx * wobbleFrequency + 7.3, cy * wobbleFrequency + 3.1, seed)
        let rr: Float = radius * (1 + wobble * (2 * n - 1))
        let hard: Float = step(rr - r, edge)
        guard falloff > 1e-4 else { return hard }
        return hard * smoothFalloff(rr - r, falloff)
    }

    /// **§8.6's triangular Rough Ink candidate.** Three half-planes whose offsets are independently
    /// displaced by seeded noise, capped by a disc so the three points are trimmed to a blob rather
    /// than left as spikes that survive a downscale only as flecks.
    ///
    /// It is grossly asymmetric under any rotation, which is the whole point: §8.4's boundary
    /// paragraph is that *rotating an uneven shape changes its outline while rotating a disc changes
    /// nothing*, so this is the shape half of the pair and `angle.jitter 1` is the other.
    static func roughTriangle(_ u: Float, _ v: Float, _ seed: UInt64,
                              radius: Float, rough: Float, cornerCap: Float) -> Float {
        var d: Float = 3
        for i in 0..<3 {
            let a: Float = Float(i) * 2.0943951 + 0.42
            let nx: Float = cos(a), ny: Float = sin(a)
            let across: Float = -u * ny + v * nx
            let offset: Float = radius
                * (1 + rough * ragged(across * 2.4 + Float(i) * 3.7, seed &+ UInt64(i) &+ 1))
            d = min(d, offset - (u * nx + v * ny))
        }
        d = min(d, cornerCap - sqrt(u * u + v * v))
        return step(d, 1.4 * pixel)
    }

    /// **§8.6's "rough squareish shape".** Four half-planes at four **different** distances, so the
    /// nib has no 4-fold symmetry left: a regular square's silhouette repeats every quarter turn,
    /// and a jitter that lands on a repeat presents the same outline twice.
    static func roughSquarish(_ u: Float, _ v: Float, _ seed: UInt64,
                              rough: Float, lean: Float) -> Float {
        let sides: [Float] = [0.78, 0.60, 0.86, 0.68]
        var d: Float = 3
        for i in 0..<4 {
            let a: Float = Float(i) * 1.5707963 + lean
            let nx: Float = cos(a), ny: Float = sin(a)
            let across: Float = -u * ny + v * nx
            let offset: Float = sides[i]
                * (1 + rough * ragged(across * 3.1 + Float(i) * 5.3, seed &+ UInt64(i) &+ 11))
            d = min(d, offset - (u * nx + v * ny))
        }
        return step(d, 1.4 * pixel)
    }

    /// **§8.6's *"half round half flat shape like pencil blunt"***, at ink weight: a disc with one
    /// side ground away. Pencil Blunt's cut is clean and the owner read *that* — the sharp cutoff —
    /// as what makes the shape uneven, so the cut is kept and only slightly torn.
    static func halfRoundFlat(_ u: Float, _ v: Float, _ seed: UInt64,
                              radius: Float, cut: Float, rough: Float) -> Float {
        let r: Float = sqrt(u * u + v * v)
        guard r > 1e-4 else { return 1 }
        let cx: Float = u / r, cy: Float = v / r
        let n: Float = value2(cx * 6.5 + 1.7, cy * 6.5 + 8.3, seed)
        let rr: Float = radius * (1 + rough * (2 * n - 1))
        let body: Float = step(rr - r, 1.4 * pixel)
        let lip: Float = cut * (1 + 0.18 * ragged(u * 3.4 + 2.1, seed &+ 21))
        return body * step(lip - v, 2 * pixel)
    }

    /// The brush pen's teardrop, long axis along `u`. `point` sharpens the leading end and `lean`
    /// biases the width toward the trailing one.
    static func teardrop(_ u: Float, _ v: Float,
                         halfHeight: Float, point: Float, lean: Float, soft: Float) -> Float {
        let along: Float = min(max(1 - u * u, 0), 1)
        let width: Float = halfHeight * pow(along, point) * (1 - lean * u)
        guard width > 1e-4 else { return 0 }
        return smoothFalloff(width - abs(v), soft * halfHeight) * step(width - abs(v), 1.2 * pixel)
    }

    /// **The painterly nib** — §8.6's *"a lot more squarish than slab shaped, though the shape is
    /// alot more blotchy than square, with a clear bristle direction noticeable in them."* Three
    /// separable terms, one per clause of that sentence:
    ///
    /// - **Squarish**: a superellipse at `exponent` 3.5–5, at an aspect near 1. Not a slab (which
    ///   would be 3:1 or 4:1) and not the ellipse round one's bristle turned out to be.
    /// - **Blotchy**: the boundary radius is displaced by three octaves of 2-D noise, so the outline
    ///   swells and bites rather than wobbling at one frequency.
    /// - **Bristle direction**: horizontal bands along `u`, broken along their own length, so the
    ///   streaks are visible *inside* the dab. §8.4 exempts interior structure from the union
    ///   argument — a pit mid-dab is not filled by a neighbour's boundary — which is why this is the
    ///   term that survives a stroke rather than the boundary noise.
    ///
    /// `streakCut` is the share of the comb that closes completely and therefore the width of the
    /// channels; `streakDepth` is how far a closed band goes, and it wants to be near 1 here for the
    /// reason `comb` records — these nibs' teeth vary across `v`, and a stroke lays twenty-odd
    /// overlapping dabs over every point, so a band dimmed to 0.2 accumulates to 0.92 and is gone.
    ///
    /// `dry` breaks the outer band of the nib, which is what makes a loaded flat read as loaded.
    static func painterly(_ u: Float, _ v: Float, _ seed: UInt64,
                          aspect: Float, exponent: Float, blob: Float,
                          streaks: Float, streakDepth: Float, streakCut: Float,
                          edge: Float, dry: Float) -> Float {
        let hu: Float = 0.94
        let hv: Float = hu / aspect
        let su: Float = abs(u) / hu, sv: Float = abs(v) / hv
        let sBox: Float = pow(pow(su, exponent) + pow(sv, exponent), 1 / exponent)
        let warp: Float = 2 * fbm2(u * 2.6 + 4.1, v * aspect * 2.6 + 7.9,
                                   octaves: 3, seed: seed &+ 31) - 1
        let d: Float = (1 + blob * warp) - sBox
        guard d > 0 else { return 0 }
        var coverage: Float = smoothFalloff(d, max(edge, 1.4 * pixel))

        // **The painterly nibs hold no base turn, so their across-travel axis is `v`** — which is why
        // this call passes `across: v` where `messyEndSlab` passes `across: u`. See `comb`.
        coverage *= comb(across: v, along: u, seed,
                         teeth: streaks, depth: streakDepth, cut: streakCut)

        guard dry > 1e-4 else { return coverage }
        let t: Float = min(max(d / 0.30, 0), 1)
        let pits: Float = fbm2(u * 9.0 + 3.3, v * aspect * 9.0 + 5.5, octaves: 2, seed: seed &+ 43)
        return coverage * (t + (1 - t) * (1 - dry + dry * pits))
    }

    /// **A comb of streaks that trace ribbons along the drag — and which mask axis that is is a
    /// property of the brush's `angle`, not of the tip.**
    ///
    /// The owner, on the second sheet: *"the bristle direction for those slab brushes is pointing
    /// the wrong way, perpendicular to the brush stroke direction."* It was, and the reason it is
    /// easy to get backwards is that **mask space and stroke space are not the same axes**:
    ///
    /// - `directionFollow 1`, **no base turn** — the painterly nibs, the bristle, the dots. Mask `u`
    ///   lies **along** the travel and `v` runs **across** the stroke, so the comb varies in `v`.
    /// - `directionFollow 1` **plus `base 0.25`** — every slab (Square, Messy Flat). The nib's long
    ///   side is perpendicular to the travel, so mask `u` is **across** the stroke and `v` is along
    ///   it. The comb varies in `u`.
    ///
    /// `across` is therefore whichever coordinate runs across the stroke's *width*, and `along` is
    /// the one that runs with the travel. Get them the wrong way round and the result is doubly
    /// wrong: the streaks read as a rake dragged sideways, **and** they are the orientation §8.4
    /// says the walk dilates away — consecutive dabs slide along the travel, so one dab's gap sits
    /// over its neighbour's ink and the union fills every channel in.
    ///
    /// Two consequences of getting it right, and the first one is a correction this file made to
    /// itself on the round-three render:
    ///
    /// - **Turning the comb the right way does not buy a shallow tooth.** It is tempting to think a
    ///   tooth at a fixed offset from the path survives at any depth, since every dab presents it
    ///   identically — but the walk **accumulates** rather than taking a maximum. Eight overlapping
    ///   dabs at flow 0.85, each laying 15% of a tooth's dimming, reach 0.66 and twelve reach 0.81.
    ///   §8.4's *"what survives is a hole, not a dimming"* is therefore orthogonal to this note:
    ///   orientation decides whether a tooth reads as a ribbon or as a rake, `depth` decides whether
    ///   it is visible at all, and a nib needs both.
    /// - **The `along` term may only wobble.** It moves the whole comb sideways by a tenth of a
    ///   tooth period over the nib — about 0.005 of a period between neighbouring dabs — which is
    ///   slow enough that it cannot fill a channel and fast enough that the comb is not a ruler.
    ///
    /// `cut` is the share of the comb that closes and therefore the width of the channels; `depth`
    /// is how far a closed tooth goes; `band` is the ramp either side of the cut. `amplitude` varies
    /// slowly **along `across` only**, so one channel is a clean gap, its neighbour a grey drag and
    /// the one after it barely there — a comb whose every channel is the same depth is a rake.
    static func comb(across: Float, along: Float, _ seed: UInt64,
                     teeth: Float, depth: Float, cut: Float, band: Float = 0.16) -> Float {
        let phase: Float = across * teeth + 0.37 + 0.10 * value1(along * 1.7 + 1.9, seed &+ 42)
        let n: Float = value1(phase, seed &+ 41)
        let closed: Float = min(max((cut - n) / band, 0), 1)
        let amplitude: Float = 0.35 + 0.65 * value1(across * teeth * 0.31 + 5.1, seed &+ 44)
        return 1 - depth * amplitude * closed
    }

    /// **Parallel filaments with no shared envelope** — §8.6's *"Right now you can see it fit within
    /// a clear oval shape"*, which was literal and is the whole of what this rewrites.
    ///
    /// The filaments run along `u` with their centres spread across `v`, which is `comb`'s
    /// no-base-turn case: these nibs carry `directionFollow 1` and no hold, so `u` is the travel.
    ///
    /// Round one multiplied every filament by one elliptical envelope, so whatever the filaments did
    /// the **silhouette** was that ellipse — the exact defect the owner named, and a nib that
    /// betrays its bounding shape. Here each filament carries its own two ends, its own taper and
    /// its own break-up, and nothing multiplies the sum. The outline is therefore the filaments and
    /// has no closed form to read off it.
    static func openBristle(_ u: Float, _ v: Float, _ seed: UInt64,
                            filaments: Int, spread: Float, breakUp: Float) -> Float {
        var coverage: Float = 0
        for i in 0..<filaments {
            let s: UInt64 = seed &+ UInt64(i) &* 0x9E37_79B9
            let slot: Float = (Float(i) + 0.5) / Float(filaments)
            let centre: Float = (slot * 2 - 1) * spread + (hash01(i, 1, s) - 0.5) * 0.07
            let halfWidth: Float = 0.012 + 0.026 * hash01(i, 2, s)
            guard abs(v - centre) < halfWidth + 0.01 else { continue }
            let u0: Float = -0.95 + 0.66 * hash01(i, 4, s)
            let u1: Float = 0.95 - 0.66 * hash01(i, 5, s)
            guard u > u0, u < u1 else { continue }
            var f: Float = smoothFalloff(halfWidth - abs(v - centre), 0.85 * halfWidth)
            guard f > 0 else { continue }
            f *= smoothFalloff(u - u0, 0.24) * smoothFalloff(u1 - u, 0.24)
            f *= (1 - breakUp) + breakUp * value1(u * 6.5 + Float(i) * 17.0, s &+ 0x51)
            coverage = max(coverage, f * (0.55 + 0.45 * hash01(i, 3, s)))
        }
        return coverage
    }

    /// **§8.6's "Streaky"** — *"the sprite being just a bunch of little dots, like 6 or 8 of them
    /// placed randomly. The brush makes many streaks."*
    ///
    /// `stratified` is the one design question the ask leaves open and the sheet asks it: spreading
    /// the dots one per band across the nib guarantees *n* distinct ribbons, where a uniform draw —
    /// which is what *"placed randomly"* says literally — lets two dots land on one ribbon and
    /// leaves a gap elsewhere.
    static func dots(_ u: Float, _ v: Float, _ seed: UInt64,
                     count: Int, stratified: Bool, minRadius: Float, maxRadius: Float) -> Float {
        var coverage: Float = 0
        for i in 0..<count {
            let s: UInt64 = seed &+ UInt64(i) &* 0xC2B2_AE35
            let cy: Float = stratified
                ? ((Float(i) + 0.5) / Float(count) * 2 - 1) * 0.72 + (hash01(i, 6, s) - 0.5) * 0.11
                : (hash01(i, 6, s) * 2 - 1) * 0.74
            let cx: Float = (hash01(i, 7, s) * 2 - 1) * 0.66
            let radius: Float = minRadius + (maxRadius - minRadius) * hash01(i, 8, s)
            let dx: Float = u - cx, dy: Float = v - cy
            coverage = max(coverage, smoothFalloff(radius - sqrt(dx * dx + dy * dy), 0.55 * radius))
        }
        return coverage
    }

    // MARK: - The Texture group's vocabulary — §13's open question

    /// **A grunge crust.** A disc whose radius carries two independent noise terms on the unit
    /// circle: a **low-frequency lobe field** that is the gross asymmetry §8.4's rotation has to have
    /// something to turn, and a coarser tear on top of it. Then a **dry band**, which is the outer
    /// third of the blob eaten into rather than feathered.
    ///
    /// Both noise terms are sampled on the unit circle rather than on an angle, for `nib`'s reason:
    /// a 1-D field indexed by `atan2` has a seam at `-π` and a repeated stamp turns one straight
    /// facet into a stripe.
    ///
    /// This draws only the **silhouette**. The holes are the `Grain` the catalogue pairs it with,
    /// whose floor is 0 — §8.4's *"a union fills in a dimming; it cannot fill in a hole"*, which for
    /// a stamp brush at a wide spacing is the whole design rather than a caveat.
    static func grungeBlob(_ u: Float, _ v: Float, _ seed: UInt64,
                           radius: Float, lobes: Float, bite: Float, dry: Float) -> Float {
        let r: Float = sqrt(u * u + v * v)
        guard r > 1e-4 else { return 1 }
        let cx: Float = u / r, cy: Float = v / r
        let low: Float = value2(cx * 1.7 + 2.9, cy * 1.7 + 6.1, seed &+ 5)
        let mid: Float = value2(cx * 5.5 + 9.3, cy * 5.5 + 1.7, seed &+ 6)
        let rr: Float = radius * (1 + lobes * (2 * low - 1) + bite * (2 * mid - 1))
        let body: Float = step(rr - r, 1.6 * pixel)
        guard body > 0 else { return 0 }
        guard dry > 1e-4 else { return body }
        // The dry band. `t` is 0 at the boundary and 1 a third of the radius inside it, so the
        // break-up is strongest exactly where the edge is and stops before it eats the core.
        let t: Float = min(max((rr - r) / (0.34 * radius), 0), 1)
        let pits: Float = fbm2(u * 7.5 + 4.4, v * 7.5 + 8.8, octaves: 2, seed: seed &+ 47)
        return body * (t + (1 - t) * (1 - dry + dry * pits))
    }

    /// **A splatter cluster** — drops whose radii come off a **cube law**, so one or two carry most
    /// of the ink and the rest are specks.
    ///
    /// That distribution is the design and a uniform one is the failure: a stamp of equal dots is a
    /// stipple, and what makes a splatter read is that it has a *main* and a spray around it. The
    /// placement is `sqrt`-warped so the drops are area-uniform on the disc rather than piling into
    /// the middle.
    ///
    /// **Each drop is stretched along its own random axis**, and the first render is why. A cluster
    /// of round blots came back reading as *hexagons* — a radial displacement at three cycles is a
    /// faceted circle and nothing else — where a flung drop is elongated in the direction it
    /// travelled. Every drop carries an axis and an aspect of 1–2.1, measured in a space squashed
    /// along that axis, so the shape is an ellipse before its boundary is torn.
    ///
    /// The tear is then at 5.5 cycles rather than 3, which is fine irregularity on a rounded outline
    /// instead of a polygon. The union is a `max`, which is what makes two overlapping drops one
    /// blot with a waist rather than a brighter disc.
    static func splatterCluster(_ u: Float, _ v: Float, _ seed: UInt64,
                                drops: Int, spread: Float,
                                minRadius: Float, maxRadius: Float, tear: Float) -> Float {
        var coverage: Float = 0
        for i in 0..<drops {
            let s: UInt64 = seed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15
            let radius: Float = minRadius
                + (maxRadius - minRadius) * pow(hash01(i, 1, s), 3.0)
            let angle: Float = hash01(i, 2, s) * 6.2831853
            let reach: Float = spread * sqrt(hash01(i, 3, s))
            let dx: Float = u - cos(angle) * reach, dy: Float = v - sin(angle) * reach
            guard abs(dx) < radius * 2.6 + 0.02, abs(dy) < radius * 2.6 + 0.02 else { continue }
            let axis: Float = hash01(i, 9, s) * 3.1415927
            let ca: Float = cos(axis), sa: Float = sin(axis)
            let stretch: Float = 1 + 1.1 * hash01(i, 10, s)
            let px: Float = (dx * ca + dy * sa) / stretch, py: Float = -dx * sa + dy * ca
            let d: Float = sqrt(px * px + py * py)
            guard d < radius * 1.6 + 0.02 else { continue }
            guard d > 1e-4 else { return 1 }
            let n: Float = value2(px / d * 5.5 + Float(i) * 2.7, py / d * 5.5 + 4.3, s &+ 0x71)
            let rr: Float = radius * (1 + tear * (2 * n - 1))
            coverage = max(coverage, step(rr - d, 1.3 * pixel))
            if coverage >= 1 { return 1 }
        }
        return coverage
    }

    /// **Stipple's tipped arm** — hard-edged dots of mixed size scattered over the nib.
    ///
    /// Deliberately *not* `dots`, which feathers each disc over 55% of its own radius because a
    /// Streaky ribbon wants soft sides. A stipple whose dots are feathered reads as spray, and the
    /// two masks would otherwise be one function with a parameter nobody could name.
    static func speckle(_ u: Float, _ v: Float, _ seed: UInt64,
                        count: Int, spread: Float, minRadius: Float, maxRadius: Float) -> Float {
        var coverage: Float = 0
        for i in 0..<count {
            let s: UInt64 = seed &+ UInt64(i) &* 0xC2B2_AE3D_27D4_EB4F
            let angle: Float = hash01(i, 4, s) * 6.2831853
            let reach: Float = spread * sqrt(hash01(i, 5, s))
            let radius: Float = minRadius + (maxRadius - minRadius) * pow(hash01(i, 6, s), 1.8)
            let dx: Float = u - cos(angle) * reach, dy: Float = v - sin(angle) * reach
            coverage = max(coverage, step(radius - sqrt(dx * dx + dy * dy), 1.2 * pixel))
            if coverage >= 1 { return 1 }
        }
        return coverage
    }

    /// **A worn stick of chalk** — a superellipse whose boundary is torn at two scales.
    ///
    /// The body is the painterly nibs' shape and the difference is what is done to it: they carry a
    /// `comb` because a paint brush has bristles, and this carries a two-scale tear because a stick
    /// of chalk has a broken edge. The interior is the `Grain` the catalogue pairs it with, at floor
    /// 0 — holes, not shading.
    ///
    /// The tear is a **sum of an isotropic 2-D term and a directional one**, and the second is what
    /// makes the nib asymmetric enough for `angle.jitter` to have something to turn: a purely radial
    /// displacement moves every direction alike, which is §8.4's refuted eroded round.
    static func chalkBlock(_ u: Float, _ v: Float, _ seed: UInt64,
                           aspect: Float, exponent: Float, tear: Float, edge: Float) -> Float {
        let hu: Float = 0.92
        let hv: Float = hu / aspect
        let su: Float = abs(u) / hu, sv: Float = abs(v) / hv
        let sBox: Float = pow(pow(su, exponent) + pow(sv, exponent), 1 / exponent)
        let broad: Float = 2 * value2(u * 1.5 + 3.7, v * 1.5 + 8.1, seed &+ 13) - 1
        let fine: Float = ragged(u * 2.2 + v * 1.4 + 5.9, seed &+ 17)
        let d: Float = (1 + tear * (0.6 * broad + 0.4 * fine)) - sBox
        guard d > 0 else { return 0 }
        return smoothFalloff(d, max(edge, 1.4 * pixel))
    }

    // MARK: - Edge and falloff helpers

    /// A hard-ish edge: 1 where `d` is comfortably positive, 0 where comfortably negative, one ramp
    /// of width `w` between. `d` is "how far inside", so callers pass `boundary - position`.
    @inline(__always)
    static func step(_ d: Float, _ w: Float) -> Float {
        guard w > 1e-6 else { return d > 0 ? 1 : 0 }
        return min(max(d / w + 0.5, 0), 1)
    }

    /// A smooth falloff over the last `w` of the inside: 1 well inside, 0 outside, smoothstepped.
    @inline(__always)
    static func smoothFalloff(_ d: Float, _ w: Float) -> Float {
        guard w > 1e-6 else { return d > 0 ? 1 : 0 }
        let t: Float = min(max(d / w, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Two octaves of signed 1-D noise in `-1…1` — a coarse tear at ~3 cycles across the nib and a
    /// fine fray at ~11. §8.4's *"several `random` rows at different λ give multi-scale
    /// roughness"*, one level down: the same argument applies to a tip's outline.
    @inline(__always)
    static func ragged(_ t: Float, _ seed: UInt64) -> Float {
        let coarse: Float = value1(t * 3.0, seed)
        let fine: Float = value1(t * 11.0, seed &+ 0x5BF0_3635)
        return (0.66 * coarse + 0.34 * fine) * 2 - 1
    }

    // MARK: - Deterministic noise

    /// `splitmix64`'s mixer — the same one `DabRandom` hashes with, for the same reason: it is a
    /// bijection with good avalanche and no state.
    @inline(__always)
    static func mix(_ x: UInt64) -> UInt64 {
        var z: UInt64 = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A lattice draw in `0..<1`. Integer coordinates only — a float coordinate would make the value
    /// depend on rounding and the field would not be reproducible across architectures.
    @inline(__always)
    static func hash01(_ a: Int, _ b: Int, _ seed: UInt64) -> Float {
        let ha: UInt64 = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
        let hb: UInt64 = UInt64(bitPattern: Int64(b)) &* 0xC2B2_AE3D_27D4_EB4F
        return Float(mix(ha ^ hb ^ seed) >> 40) / Float(1 << 24)
    }

    @inline(__always)
    static func floorInt(_ x: Float) -> Int {
        let i = Int(x)
        return x < 0 && Float(i) != x ? i - 1 : i
    }

    /// Smooth 1-D value noise in `0…1`.
    @inline(__always)
    static func value1(_ x: Float, _ seed: UInt64) -> Float {
        let xi: Int = floorInt(x)
        let fx: Float = x - Float(xi)
        let s: Float = fx * fx * (3 - 2 * fx)
        let a: Float = hash01(xi, 0, seed)
        let b: Float = hash01(xi + 1, 0, seed)
        return a + (b - a) * s
    }

    /// Smooth 2-D value noise in `0…1`.
    @inline(__always)
    static func value2(_ x: Float, _ y: Float, _ seed: UInt64) -> Float {
        let xi: Int = floorInt(x), yi: Int = floorInt(y)
        let fx: Float = x - Float(xi), fy: Float = y - Float(yi)
        let sx: Float = fx * fx * (3 - 2 * fx)
        let sy: Float = fy * fy * (3 - 2 * fy)
        let a: Float = hash01(xi, yi, seed)
        let b: Float = hash01(xi + 1, yi, seed)
        let c: Float = hash01(xi, yi + 1, seed)
        let d: Float = hash01(xi + 1, yi + 1, seed)
        let top: Float = a + (b - a) * sx
        let bottom: Float = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    static func fbm2(_ x: Float, _ y: Float, octaves: Int, seed: UInt64) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, norm: Float = 0
        var fx: Float = x, fy: Float = y
        for octave in 0..<octaves {
            sum += amplitude * value2(fx, fy, seed &+ UInt64(octave) &* 0x0100_0193)
            norm += amplitude
            amplitude *= 0.5
            fx *= 2
            fy *= 2
        }
        return norm > 0 ? sum / norm : 0
    }

    // MARK: - Grain

    /// A tip's interior texture. Multiplies the silhouette's coverage, so it can only ever take ink
    /// away — a grain that could add would paint outside the nib.
    struct Grain {
        /// Cycles across the whole tip.
        var frequency: Float
        var octaves: Int
        /// What the grain reads where the noise is at its lowest. `0` punches holes; `0.3` is a
        /// mottle.
        var floor: Float
        /// Noise below this is the floor. `0` with `softness: 1` is a plain mottle with no pits.
        var threshold: Float
        /// Width of the ramp above the threshold.
        var softness: Float
    }

    struct Shape {
        let name: String
        /// `var` so a test can re-seed one and prove the seed is read at all — a determinism
        /// assertion against a generator that ignored its seed would be green and vacuous.
        var seed: UInt64
        var grain: Grain?
        /// Coverage at normalised `(u, v)`, given the shape's seed.
        let body: (Float, Float, UInt64) -> Float

        init(name: String, seed: UInt64, grain: Grain? = nil,
             body: @escaping (Float, Float, UInt64) -> Float) {
            self.name = name
            self.seed = seed
            self.grain = grain
            self.body = body
        }
    }

    // MARK: - Rasterizing a shape

    /// **The silhouette is supersampled and the grain is not**, which is a cost decision with a
    /// correctness argument behind it. A silhouette's edge is where a jagged sample shows, so it is
    /// evaluated `samples²` times per pixel; the grain is a continuous field whose own frequency is
    /// far below the pixel grid, so sampling it once per pixel is exact enough to be
    /// indistinguishable and is 4× cheaper across the whole mask.
    static let samples: Int = 2

    static func render(_ shape: Shape) -> Tip {
        let n: Int = side
        var alpha = [UInt8](repeating: 0, count: n * n)
        let inv: Float = 1 / Float(samples)

        for y in border..<(n - border) {
            for x in border..<(n - border) {
                var accumulated: Float = 0
                for sy in 0..<samples {
                    let py: Float = Float(y) + (Float(sy) + 0.5) * inv
                    let v: Float = (py - Float(n / 2)) / halfSpan
                    for sx in 0..<samples {
                        let px: Float = Float(x) + (Float(sx) + 0.5) * inv
                        let u: Float = (px - Float(n / 2)) / halfSpan
                        accumulated += shape.body(u, v, shape.seed)
                    }
                }
                var coverage: Float = accumulated * inv * inv
                if coverage > 0, let grain = shape.grain {
                    let u: Float = (Float(x) + 0.5 - Float(n / 2)) / halfSpan
                    let v: Float = (Float(y) + 0.5 - Float(n / 2)) / halfSpan
                    coverage *= grainValue(u, v, grain, shape.seed &+ 0x6721)
                }
                alpha[y * n + x] = UInt8(min(max(coverage, 0), 1) * 255 + 0.5)
            }
        }

        return Tip(name: shape.name,
                   fileName: "gen-\(shape.name).png",
                   alpha: alpha,
                   png: png(from: alpha))
    }

    static func grainValue(_ u: Float, _ v: Float, _ grain: Grain, _ seed: UInt64) -> Float {
        let noise: Float = fbm2(u * grain.frequency, v * grain.frequency,
                                octaves: grain.octaves, seed: seed)
        let ramp: Float = grain.softness > 1e-6
            ? min(max((noise - grain.threshold) / grain.softness, 0), 1)
            : (noise > grain.threshold ? 1 : 0)
        return grain.floor + (1 - grain.floor) * ramp
    }

    // MARK: - Bytes

    /// The alpha buffer as a straight-alpha PNG in the shape `BrushTextureStore` reads.
    ///
    /// **RGB is black everywhere, which makes premultiplied and straight the same bytes**, so the
    /// premultiplied context below writes a file whose unpremultiplied alpha is exactly the buffer
    /// — `0 / a == 0` for every `a`. That is the same trick `BrushTipImport` relies on, and it is
    /// why the round trip in `BrushTipGeneratorLogicTests` can be exact rather than approximate.
    static func png(from alpha: [UInt8]) -> Data {
        let n: Int = side
        var rgba = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) { rgba[i * 4 + 3] = alpha[i] }
        let image: CGImage? = rgba.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n,
                                      bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
        guard let image, let data = UIImage(cgImage: image).pngData() else { return Data() }
        return data
    }

    /// Writes every generated tip into the brush library and hands back what was written.
    ///
    /// **`BrushTextureStore` is dropped first**, because it caches a *negative* answer for a ref
    /// whose file was missing — the hazard `860a4a0` records for the restored-texture path, reached
    /// here by a different door: a test that stamped a `gen-…` ref before this ran would otherwise
    /// hold a nil mask for the life of the process and every dab after it would draw nothing.
    @discardableResult
    static func writeAll() -> [Tip] {
        let tips = generateAll()
        for tip in tips {
            try? BrushStorage.shared.write(tip.png, to: tip.fileName)
        }
        BrushTextureStore.removeAll()
        return tips
    }
}
