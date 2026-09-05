import UIKit
import CoreGraphics

/// **BRUSH.md §12 stage 9's candidates — what the contact sheet shows and the owner picks from.**
///
/// **These are not the shipped set and must not become it by default.** §12 stage 9 is *driven by
/// contact sheet at the owner's instruction*: candidates are rendered through the real
/// `BrushStamper`, the owner picks and adjusts, and only then are presets authored. So nothing here
/// touches `BrushLibrary`, nothing here has a written-down `id` (a preset's id is a manifest
/// commitment — §12 stage 5's own note), and every brush below is free to be deleted whole.
///
/// **This is round four, and it is organised by §8.6's twenty slots rather than by candidate.** The
/// owner picked sixteen off rounds one to three; round four adds the **Texture** group, which §12
/// stage 11 had deferred to CC0 sourcing and which §13 asked the generator to try. Every row below
/// names the **slot** it belongs to and its **standing** in it, so a row that is already settled and
/// a row competing for an open slot cannot be confused for one another.
///
/// **Three kinds of candidate, and the sheet marks which is which**, because the most useful thing
/// on it is that some of these need no artwork at all:
///
/// - `.generatedTip` — a `BrushTipGenerator` PNG, stamped through `BrushTip.stamp`.
/// - `.dynamicsOnly` — a **clean round tip** whose whole character is §6's matrix. §8.4's first
///   answer for the rough ink nib, and the owner kept one of them (Rough Ink Blotchy).
/// - `.procedural` — `BrushTip.round` with a hardness and a spacing and nothing else. Soft round,
///   hard round, the technical pen and the opaque round are all this, which is four of §8.6's
///   sixteen answered by arithmetic.
///
/// **What governs every rough row here is §8.4's boundary paragraph**: roughness survives only when
/// what a dab presents to the silhouette *changes from dab to dab*, so an asymmetric nib and
/// `angle.jitter` multiply and neither works alone. The Rough Ink family is laid out as a factorial
/// on exactly those two terms, and the rows marked `.control` are the cells that are supposed to
/// fail.
enum BrushCandidates {

    enum Kind {
        case generatedTip(String)
        case dynamicsOnly
        case procedural

        var label: String {
            switch self {
            case .generatedTip: return "GENERATED TIP"
            case .dynamicsOnly: return "DYNAMICS ONLY — NO TIP"
            case .procedural: return "PROCEDURAL ROUND — NO TIP"
            }
        }

        var tipName: String? {
            if case .generatedTip(let name) = self { return name }
            return nil
        }
    }

    /// **Where a row stands against §8.6's sixteen.** The brief for this sheet: *"mark each row as
    /// one of the sixteen or as a variant competing for one of those slots"*.
    enum Standing: Equatable {
        /// The slot is settled — this row *is* the brush, kept from the first sheet or ruled by the
        /// owner. Nothing on this sheet competes with it.
        case chosen
        /// One of several rows competing for an open slot.
        case contender
        /// **On the sheet in order to fail.** A control isolates one operand of §8.4's pair — an
        /// asymmetric nib with the rotation taken away, or a symmetric one with the rotation left
        /// in. If a control reads as strong as the contenders beside it, the boundary paragraph is
        /// wrong and the family it belongs to has to be redesigned rather than picked from.
        case control

        var label: String {
            switch self {
            case .chosen: return "CHOSEN"
            case .contender: return "VARIANT"
            case .control: return "CONTROL — EXPECTED TO FAIL"
            }
        }
    }

    struct Candidate {
        let group: String
        /// Which of §8.6's sixteen this row is for. Rows are grouped by it on the sheet.
        let slot: String
        let standing: Standing
        let name: String
        let kind: Kind
        let brush: Brush
        /// One line of prose about what this candidate is *for*. The settings line under it is
        /// derived from the brush rather than written, so it cannot go stale.
        let note: String
    }

    /// §8.6's five groups, in its own order.
    static let groups: [String] = ["Basics", "Sketching", "Inking", "Painting", "Texture"]

    /// **§8.6's sixteen, per group, in the owner's own order.** The sheet's slot headers are driven
    /// from this rather than from whatever the candidate list happens to contain, so a slot nobody
    /// drew a candidate for shows up as an empty header instead of silently vanishing.
    static let slots: [String: [String]] = [
        "Basics": ["Round Soft", "Opaque Round", "Round Hard", "Square", "Messy Flat"],
        "Sketching": ["Pencil Hard", "Pencil Soft", "Pencil Blunt", "Pencil Textured"],
        "Inking": ["Technical Pen Fine", "Brush Pen", "Rough Ink Blotchy", "Rough Ink"],
        "Painting": ["Painterly", "Bristle", "Streaky"],
        // **§8.6 names four and §13 asks whether the generator can draw them** — *"grunge, splatter,
        // stipple and chalk"*, deferred to §12 stage 11 because §8.4 ruled scanned organics genuinely
        // hard to fake. Round four is that question asked rather than answered from the armchair.
        "Texture": ["Grunge", "Splatter", "Stipple", "Chalk"]
    ]

    /// **The five rows that make up §8.4's factorial on asymmetry × rotation.** Named here rather
    /// than inferred from the slot, because the Rough Ink slot also carries a **sixth** row that
    /// deliberately breaks the *"only the tip and the jitter differ"* invariant — it is the two
    /// mechanisms combined. `BrushTipGeneratorLogicTests` pins the invariant against this list, so
    /// adding a row to the slot cannot silently weaken the pin.
    static let roughInkFactorial: [String] = [
        "Rough Ink — Triangle", "Rough Ink — Triangle, No Turn", "Rough Ink — Rough Square",
        "Rough Ink — Half-Flat", "Rough Ink — Eroded Round"
    ]

    /// Every candidate, given the tips `BrushTipGenerator` produced.
    ///
    /// Takes the tips rather than reaching for a global, so the sheet, the tests and any future
    /// caller all see the same files they just wrote — a generator whose output is looked up by name
    /// from somewhere else is how a stale PNG gets rendered under a new name.
    static func all(tips: [BrushTipGenerator.Tip]) -> [Candidate] {
        var byName: [String: BrushTipGenerator.Tip] = [:]
        for tip in tips { byName[tip.name] = tip }
        func stamp(_ name: String) -> BrushTip {
            byName[name].map { $0.tip } ?? .round
        }
        func kind(_ name: String) -> Kind { .generatedTip(name) }

        var out: [Candidate] = []

        // MARK: - Basics

        out.append(Candidate(
            group: "Basics", slot: "Round Soft", standing: .chosen,
            name: "Round Soft", kind: .procedural,
            brush: Brush(name: "Round Soft", tip: .round, size: 22,
                         dab: BrushDabSettings(size: 0.5, flow: 0.35, spacing: 0.06, hardness: 0.12),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.5, atZero: 0.2),
                             .flowFromPressure(amount: 0.65)
                         ])),
            note: "The falloff arm of §8.4. No picture: hardness is a number on the round tip."))

        // **Moved here from Painting at the owner's instruction** — *"I feel it better belongs
        // here"* (§8.6). The brush is unchanged from the first sheet; only its group is.
        out.append(Candidate(
            group: "Basics", slot: "Opaque Round", standing: .chosen,
            name: "Opaque Round", kind: .procedural,
            brush: Brush(name: "Opaque Round", tip: .round, size: 34,
                         dab: BrushDabSettings(size: 0.85, flow: 1, spacing: 0.05, hardness: 0.8),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.15, atZero: 0.75)
                         ])),
            note: "Flow 1 and a near-hard edge: covers in one pass. The falloff \"Square\" is "
                + "asked to match."))

        out.append(Candidate(
            group: "Basics", slot: "Round Hard", standing: .chosen,
            name: "Round Hard", kind: .procedural,
            brush: Brush(name: "Round Hard", tip: .round, size: 16,
                         dab: BrushDabSettings(size: 0.6, flow: 0.9, spacing: 0.045, hardness: 0.95),
                         stroke: BrushStrokeSettings(stabilization: 0.1),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.4, atZero: 0.4),
                             .flowFromPressure(amount: 0.1)
                         ])),
            note: "A disc. BUGS.md records that hardness 0.95 is already a fully aliased edge."))

        // **§8.6's "Square", three ways.** *"A slab with no noisy edges, and beveled corners, and
        // softness sort of like opaque round in that it only falls off in the very edges."* All
        // three carry the same hold — `base 0.25`, `directionFollow 1` — and **no jitter at all**,
        // because a clean nib is what was asked for and jitter is what would make it dirty.
        let squareVariants: [(String, String, CGFloat, String)] = [
            ("Square — Crisp", "square-bevel-tight", CGFloat(32),
             "4:1, a 0.10 chamfer, and a falloff band *crisper* than Opaque Round's. The hardest "
             + "reading of \"only falls off in the very edges\"."),
            ("Square — Soft Edge", "square-bevel-soft", CGFloat(32),
             "The same nib and chamfer with the falloff four times as wide — softer than Opaque "
             + "Round. The two bracket the owner's sentence; at slab widths the difference "
             + "between them is about a point."),
            ("Square — Wide 2.5:1", "square-bevel-wide", CGFloat(36),
             "Shorter and fatter, a heavier chamfer, and a falloff that matches Opaque Round's "
             + "own. A 2.5:1 nib turns more visibly, which the turning stroke is there to show.")
        ]
        for (name, tipName, size, note) in squareVariants {
            out.append(Candidate(
                group: "Basics", slot: "Square", standing: .contender,
                name: name, kind: kind(tipName),
                brush: Brush(name: name, tip: stamp(tipName), size: size,
                             dab: BrushDabSettings(size: 0.75, flow: 0.9, spacing: 0.05,
                                                   angle: BrushAngleSettings(base: 0.25,
                                                                             directionFollow: 1)),
                             stroke: BrushStrokeSettings(stabilization: 0.2),
                             modulations: BrushModulations([
                                 .sizeFromPressure(amount: 0.25, atZero: 0.6),
                                 .flowFromPressure(amount: 0.12)
                             ])),
                note: note))
        }

        // **§8.6's "Messy Flat", and it is the row that re-asks §8.4's boundary question.** *"Like
        // the flat brush, except with messier ends. Still square, but the sprite gives it a unique
        // non monolithic look for the ends, more of a slightly dirty falloff."*
        //
        // The sprite's messiness lives at the **ends**, which is right — the long sides sweep along
        // the travel and never reach the silhouette. But the ends trace the stroke's two *edges*,
        // and on a direction-locked nib they present the **same profile at every dab**: at spacing
        // 0.065 with a 4:1 nib, about eight dabs overlap along the travel and the edge is their
        // running maximum. That is §8.4's union argument exactly, and it predicts the sprite alone
        // washes out into a slightly wobbly straight line.
        //
        // **The first render of this sheet confirmed it, and the fix has to be attributable.** Three
        // rows that each changed the picture *and* the dynamics could show the owner a torn stroke
        // without saying which term tore it — CLAUDE.md's *"mutate one fixture cumulatively, so a
        // row's difference is attributable to the row"*. So four of the five rows below are one
        // picture with the dynamics added one at a time, and the fifth swaps only the picture.
        let messyFlatVariants: [(String, String, Double, Double, Standing, String)] = [
            ("Messy Flat — Sprite Only", "flat-messy-ends-dirty", 0.0, 0.0, Standing.control,
             "The picture doing the work alone, direction-locked. §8.4 predicts the messy end "
             + "dilates away into a wobble, and the first render of this sheet agreed."),
            ("Messy Flat — + 4° Jitter", "flat-messy-ends-dirty", 0.012, 0.0, Standing.contender,
             "The same PNG turned ±2° per dab, and nothing else. The rotation term on its own."),
            ("Messy Flat — + Envelope", "flat-messy-ends-dirty", 0.0, 0.10, Standing.contender,
             "The same PNG with a short-λ `size ← random` and no turn — the mechanism §8.4 "
             + "MEASURED at nine times an eroded edge. The envelope term on its own."),
            ("Messy Flat — + Both", "flat-messy-ends-dirty", 0.012, 0.10, Standing.contender,
             "Both terms on the same PNG. If this is no better than the row above, the jitter is "
             + "not paying for itself on a direction-locked nib."),
            ("Messy Flat — Milder Sprite", "flat-messy-ends", 0.012, 0.10, Standing.contender,
             "The same two dynamics against the *cleaner* of the two end sprites — the picture "
             + "term, isolated against the row above it.")
        ]
        for (name, tipName, jitter, envelope, standing, note) in messyFlatVariants {
            var rows: [BrushModulation] = [.sizeFromPressure(amount: 0.22, atZero: 0.6)]
            if envelope > 0 {
                rows.append(BrushModulation(.size, .random(.scatterAcross, .plain(0.5)),
                                            amount: envelope))
            }
            rows.append(.flowFromPressure(amount: 0.15))
            out.append(Candidate(
                group: "Basics", slot: "Messy Flat", standing: standing,
                name: name, kind: kind(tipName),
                brush: Brush(name: name, tip: stamp(tipName), size: 32,
                             dab: BrushDabSettings(size: 0.8, flow: 0.85, spacing: 0.065,
                                                   angle: BrushAngleSettings(base: 0.25,
                                                                             directionFollow: 1,
                                                                             jitter: jitter)),
                             stroke: BrushStrokeSettings(stabilization: 0.2),
                             modulations: BrushModulations(rows)),
                note: note))
        }

        // MARK: - Sketching — all four settled off the first sheet

        out.append(Candidate(
            group: "Sketching", slot: "Pencil Hard", standing: .chosen,
            name: "Pencil Hard", kind: kind("pencil-hard"),
            brush: Brush(name: "Pencil Hard", tip: stamp("pencil-hard"), size: 8, opacity: 0.95,
                         dab: BrushDabSettings(size: 0.7, flow: 0.45, spacing: 0.05,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.12),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.3, atZero: 0.5),
                             .flowFromPressure(amount: 0.55)
                         ])),
            note: "Mid-frequency threshold, hard-thresholded. Full angle jitter per §8.5."))

        out.append(Candidate(
            group: "Sketching", slot: "Pencil Soft", standing: .chosen,
            name: "Pencil Soft", kind: kind("pencil-soft"),
            brush: Brush(name: "Pencil Soft", tip: stamp("pencil-soft"), size: 14, opacity: 0.85,
                         dab: BrushDabSettings(size: 0.6, flow: 0.3, spacing: 0.04,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.4, atZero: 0.35),
                             .flowFromPressure(amount: 0.7)
                         ])),
            note: "A smear rather than a tooth: the grain modulates alpha instead of punching it."))

        out.append(Candidate(
            group: "Sketching", slot: "Pencil Blunt", standing: .chosen,
            name: "Pencil Blunt", kind: kind("pencil-blunt"),
            brush: Brush(name: "Pencil Blunt", tip: stamp("pencil-blunt"), size: 18, opacity: 0.9,
                         dab: BrushDabSettings(size: 0.72, flow: 0.4, spacing: 0.055,
                                               angle: BrushAngleSettings(base: 0.08,
                                                                         directionFollow: 0.35,
                                                                         jitter: 0.25)),
                         stroke: BrushStrokeSettings(stabilization: 0.18),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.28, atZero: 0.55),
                             .flowFromPressure(amount: 0.6)
                         ])),
            note: "The mask §8.4's boundary paragraph was written from: a ground flat makes the "
                + "shape uneven, and the jitter is what turns unevenness into roughness."))

        out.append(Candidate(
            group: "Sketching", slot: "Pencil Textured", standing: .chosen,
            name: "Pencil Textured", kind: kind("pencil-textured"),
            brush: Brush(name: "Pencil Textured", tip: stamp("pencil-textured"), size: 20,
                         opacity: 0.9,
                         dab: BrushDabSettings(size: 0.7, flow: 0.5, spacing: 0.085,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.15),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.3, atZero: 0.45),
                             .flowFromPressure(amount: 0.5)
                         ])),
            note: "Coarse pits, wide spacing. Interior grain is §8.4's exempt case and it reads."))

        // MARK: - Inking

        out.append(Candidate(
            group: "Inking", slot: "Technical Pen Fine", standing: .chosen,
            name: "Technical Pen — Fine", kind: .procedural,
            brush: Brush(name: "Technical Pen — Fine", tip: .round, size: 4,
                         dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.03, hardness: 1),
                         stroke: BrushStrokeSettings(stabilization: 0.45)),
            note: "Constant width, no pressure response at all — a Rotring, not a nib. Also the "
                + "empty cell of the Rough Ink factorial: no asymmetry and no turn."))

        out.append(Candidate(
            group: "Inking", slot: "Brush Pen", standing: .chosen,
            name: "Brush Pen", kind: kind("pen-brush"),
            brush: Brush(name: "Brush Pen", tip: stamp("pen-brush"), size: 26,
                         dab: BrushDabSettings(size: 0.35, flow: 0.9, spacing: 0.035,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.35),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.65, atZero: 0.12),
                             .flowFromPressure(amount: 0.1)
                         ])),
            note: "A teardrop lying along the travel; the taper is mostly size ← pressure."))

        out.append(Candidate(
            group: "Inking", slot: "Rough Ink Blotchy", standing: .chosen,
            name: "Rough Ink — Blotchy", kind: .dynamicsOnly,
            brush: Brush(name: "Rough Ink — Blotchy", tip: .round, size: 11,
                         dab: BrushDabSettings(size: 0.5, flow: 0.9, spacing: 0.045, hardness: 0.85,
                                               density: 0, densityWavelength: 4.0),
                         stroke: BrushStrokeSettings(stabilization: 0.3),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.16, atZero: 0.55),
                             BrushModulation(.size, .random(.scatterAcross, .plain(2.5)),
                                             amount: 0.30),
                             BrushModulation(.size, .random(.scatterAcross, .plain(0.3)),
                                             amount: 0.10),
                             BrushModulation(.scatterAcross, .random(.scatterAcross, .plain(1.5)),
                                             amount: 0.14),
                             .densityFromPressure(knee: 0.4, floor: 0.45),
                             .flowFromPressure(amount: 0.1)
                         ])),
            note: "Chosen off the first sheet and unchanged. All dynamics, no picture — the other "
                + "answer to the same ask, kept beside the tipped ones on purpose."))

        // **§8.6's one piece of open design, laid out as a factorial on §8.4's two terms.**
        //
        // The owner, on Pencil Blunt: *"there is a sharp cutoff in the bottom … that sharp cutoff
        // makes the sprite uneven, and thats what creates the rough blotchy look when its
        // randomized … a potential candidate is a triangular sprite … Or maybe a rough squareish
        // shape, or a half round half flat shape like pencil blunt could just work if its totally
        // isotropically randomized."*
        //
        // **Every one of these five carries identical brush settings except its tip and its
        // jitter.** Same size, same dab fraction, same flow, same spacing, same one pressure row,
        // and — deliberately — **no `density` dropout at all**, so nothing on these rows is doing
        // the roughening except the picture and the turn. That is what makes the sheet able to
        // answer which term does the work rather than only which row looks best.
        let roughInkDab = { (tipJitter: Double) in
            BrushDabSettings(size: 0.9, flow: 1, spacing: 0.055,
                             angle: BrushAngleSettings(jitter: tipJitter))
        }
        let roughInkRows = BrushModulations([.sizeFromPressure(amount: 0.25, atZero: 0.55)])

        let roughInkVariants: [(String, String, Double, Standing, String)] = [
            ("Rough Ink — Triangle", "rough-ink-triangle", 1.0, Standing.contender,
             "The owner's first named candidate. Grossly asymmetric, turned isotropically: both "
             + "halves of §8.4's pair at full strength."),
            ("Rough Ink — Triangle, No Turn", "rough-ink-triangle", 0.03, Standing.control,
             "The same picture with the turn taken away — ±5°. Asymmetry alone. If this reads as "
             + "rough as the row above, the jitter is not the term that matters."),
            ("Rough Ink — Rough Square", "rough-ink-square", 1.0, Standing.contender,
             "The second named candidate. Four sides at four different distances, so no quarter "
             + "turn returns the same outline."),
            ("Rough Ink — Half-Flat", "rough-ink-halfflat", 1.0, Standing.contender,
             "The third: Pencil Blunt's ground flat at ink weight, turned isotropically — which "
             + "is the owner's own \"could just work\" hypothesis, drawn."),
            ("Rough Ink — Eroded Round", "rough-ink-eroded-round", 1.0, Standing.control,
             "§8.4's refuted nib: a disc with a noisy edge and no gross asymmetry. Turn alone. "
             + "MEASURED at 0.41% of a width in a stroke — this row should look nearly clean.")
        ]
        for (name, tipName, jitter, standing, note) in roughInkVariants {
            out.append(Candidate(
                group: "Inking", slot: "Rough Ink", standing: standing,
                name: name, kind: kind(tipName),
                brush: Brush(name: name, tip: stamp(tipName), size: 10,
                             dab: roughInkDab(jitter),
                             stroke: BrushStrokeSettings(stabilization: 0.3),
                             modulations: roughInkRows),
                note: note))
        }

        // **The sixth row, and it is the one the first render of this sheet argued for.** Rendered
        // at 1:1 the two mechanisms turn out to make *different* roughness rather than more or less
        // of one: the tipped rows carry a fine even tooth along the edge, and Rough Ink Blotchy —
        // all dynamics, no picture — carries coarse lumps and an outright break. Neither is the
        // other's weaker version, so the obvious question the factorial cannot answer is what they
        // look like together. This row is that question: the triangle at full turn, carrying
        // Blotchy's own dropout, width wobble and scatter unchanged.
        // **And the seventh, which is the owner's own question off the second sheet.** They accepted
        // Triangle + Blotchy for the slot and then asked to see the square given the same
        // treatment before it is settled: *"i wonder what rough ink square with blotchy dynamics
        // will look like."* So this row is the one above with **only the picture swapped** — same
        // size, same dab, same spacing, same dropout, same four random rows, same jitter — which
        // makes the pair attributable even though neither is attributable on its own.
        let blotchyRoughInk: [(String, String, String)] = [
            ("Rough Ink — Triangle + Blotchy Dynamics", "rough-ink-triangle",
             "Outside the factorial on purpose: the picture's fine tooth *and* Blotchy's coarse "
             + "lumps and dropout at once. Not attributable, and not meant to be — it is the row "
             + "that asks whether the two mechanisms add up."),
            ("Rough Ink — Rough Square + Blotchy Dynamics", "rough-ink-square",
             "The owner's ask off the second sheet: the square nib given the triangle's treatment. "
             + "Only the tip differs from the row above, so the pair is the picture term isolated "
             + "against a fixed set of dynamics.")
        ]
        for (name, tipName, note) in blotchyRoughInk {
            out.append(Candidate(
                group: "Inking", slot: "Rough Ink", standing: .contender,
                name: name, kind: kind(tipName),
                brush: Brush(name: name, tip: stamp(tipName), size: 11,
                             dab: BrushDabSettings(size: 0.6, flow: 1, spacing: 0.045,
                                                   density: 0, densityWavelength: 4.0,
                                                   angle: BrushAngleSettings(jitter: 1)),
                             stroke: BrushStrokeSettings(stabilization: 0.3),
                             modulations: BrushModulations([
                                 .sizeFromPressure(amount: 0.16, atZero: 0.55),
                                 BrushModulation(.size, .random(.scatterAcross, .plain(2.5)),
                                                 amount: 0.30),
                                 BrushModulation(.size, .random(.scatterAcross, .plain(0.3)),
                                                 amount: 0.10),
                                 BrushModulation(.scatterAcross, .random(.scatterAcross, .plain(1.5)),
                                                 amount: 0.14),
                                 .densityFromPressure(knee: 0.4, floor: 0.45),
                                 .flowFromPressure(amount: 0.1)
                             ])),
                note: note))
        }

        // MARK: - Painting

        // **The painterly nib, five ways.** The owner's reference: *"most appear to be a lot more
        // squarish than slab shaped, though the shape is alot more blotchy than square, with a
        // clear bristle direction noticeable in them."*
        //
        // All five hold `directionFollow 1` with **no base turn**, so the nib's long axis and its
        // streaks lie *along* the travel — which is what makes the bristle direction read as a
        // bristle direction rather than as a rake dragged sideways. The streaks are interior
        // structure and §8.4 exempts those from the union argument; the blotchy *outline* is on the
        // swept sides and mostly is not, which is what the five spacings and the one jittered row
        // are there to bracket.
        let painterlyVariants: [(String, String, CGFloat, Double, Double, Double, String)] = [
            ("Painterly — Blotchy", "paint-blotchy", CGFloat(34), 0.055, 0.0, 0.0,
             "The middle of the reference: squarish at 1.15:1, a blotchy outline, fourteen narrow "
             + "streaks at mixed depths — one a gap, the next a grey drag. The baseline."),
            ("Painterly — Streaky", "paint-streaky", CGFloat(34), 0.05, 0.0, 0.0,
             "Twenty streaks that go all the way to zero — the \"clear bristle direction\" clause "
             + "taken as far as it goes before it becomes the Bristle nib."),
            ("Painterly — Jagged", "paint-jagged", CGFloat(36), 0.06, 0.008, 0.09,
             "§8.6's jagged-outline family, plus 3° of turn and an envelope wobble — the only one "
             + "of the five whose *silhouette* is asked to be rough rather than its interior."),
            ("Painterly — Soft Slab", "paint-soft-slab", CGFloat(38), 0.035, 0.0, 0.0,
             "§8.6's soft/blurred-slab family: 1.55:1, a wide falloff, six faint streaks. The one "
             + "that looks like a loaded brush rather than a dry one, and the deliberate smooth "
             + "member of the five."),
            ("Painterly — Dry Load", "paint-dry-load", CGFloat(36), 0.095, 0.0, 0.0,
             "Speckled interior and broken edges at spacing 0.095 — §8.4's \"anything whose "
             + "character is in its pixels needs the dabs far enough apart to be seen one at a "
             + "time\", which is what killed the first sheet's blender.")
        ]
        for (name, tipName, size, spacing, jitter, extraSizeRandom, note) in painterlyVariants {
            var rows: [BrushModulation] = [
                .sizeFromPressure(amount: 0.2, atZero: 0.7),
                .flowFromPressure(amount: 0.25)
            ]
            if extraSizeRandom > 0 {
                rows.append(BrushModulation(.size, .random(.scatterAcross, .plain(0.5)),
                                            amount: extraSizeRandom))
            }
            out.append(Candidate(
                group: "Painting", slot: "Painterly", standing: .contender,
                name: name, kind: kind(tipName),
                brush: Brush(name: name, tip: stamp(tipName), size: size,
                             // **Flow is 0.6, not 0.9, and the first render is why.** At these
                             // spacings twenty-odd dabs overlap every point, so at flow 0.9 the
                             // accumulation saturates and every streak the nib carries is filled
                             // in by its neighbours — the five rows rendered as five identical
                             // black bands. §2.11's pair is half of what fixes it: a lower *flow*
                             // with the stroke's opacity still at 1 keeps the tonal range and
                             // still covers. The other half is in the nib, where the streaks had
                             // to become holes rather than shading.
                             dab: BrushDabSettings(size: 0.85, flow: 0.45, spacing: spacing,
                                                   angle: BrushAngleSettings(directionFollow: 1,
                                                                             jitter: jitter)),
                             stroke: BrushStrokeSettings(stabilization: 0.25),
                             modulations: BrushModulations(rows)),
                note: note))
        }

        // **Bristle, and the defect the owner named is in the mask rather than in the settings.**
        // *"Right now you can see it fit within a clear oval shape."* Round one multiplied every
        // filament by one shared elliptical envelope, so the silhouette **was** that ellipse.
        // `openBristle` removes the shared term entirely.
        //
        // Rows one and two are the same PNG with and without an envelope wobble, which is the honest
        // A/B: a mask with no bounding shape still gets its *outer* boundary dilated by the walk
        // (about thirty dabs overlap at this spacing), so the question is whether fixing the picture
        // is enough on its own.
        out.append(Candidate(
            group: "Painting", slot: "Bristle", standing: .contender,
            name: "Bristle — Open", kind: kind("bristle-open"),
            brush: Brush(name: "Bristle — Open", tip: stamp("bristle-open"), size: 34,
                         opacity: 0.95,
                         dab: BrushDabSettings(size: 0.8, flow: 0.55, spacing: 0.03,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.55),
                             .flowFromPressure(amount: 0.45)
                         ])),
            note: "Eleven filaments with independent ends and no shared envelope. The mask fix "
                + "alone — no dynamics — so the row says whether that was the whole of it."))

        out.append(Candidate(
            group: "Painting", slot: "Bristle", standing: .contender,
            name: "Bristle — Open + Envelope", kind: kind("bristle-open"),
            brush: Brush(name: "Bristle — Open + Envelope", tip: stamp("bristle-open"), size: 34,
                         opacity: 0.95,
                         dab: BrushDabSettings(size: 0.8, flow: 0.55, spacing: 0.04,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.55),
                             BrushModulation(.size, .random(.scatterAcross, .plain(0.6)),
                                             amount: 0.16),
                             BrushModulation(.scatterAcross, .random(.scatterAcross, .plain(1.0)),
                                             amount: 0.07),
                             .flowFromPressure(amount: 0.45)
                         ])),
            note: "The same PNG with §8.4's two working mechanisms on it — a short-λ size wobble "
                + "and a coherent scatter. The A/B against the row above."))

        out.append(Candidate(
            group: "Painting", slot: "Bristle", standing: .contender,
            name: "Bristle — Dense", kind: kind("bristle-open-dense"),
            brush: Brush(name: "Bristle — Dense", tip: stamp("bristle-open-dense"), size: 38,
                         opacity: 0.95,
                         dab: BrushDabSettings(size: 0.8, flow: 0.5, spacing: 0.04,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.55),
                             BrushModulation(.size, .random(.scatterAcross, .plain(0.6)),
                                             amount: 0.16),
                             .flowFromPressure(amount: 0.45)
                         ])),
            note: "Seventeen filaments, broken harder along their length — closer to a worn brush "
                + "than to a new one."))

        // **Streaky** — *"Imagine the sprite being just a bunch of little dots, like 6 or 8 of them
        // placed randomly. The brush makes many streaks."*
        //
        // **`jitter` is 0 on both and that is the design, not an omission.** Every other rough row
        // on this sheet wants rotation; this one is the exception §8.4's rule predicts, because what
        // makes a ribbon a ribbon is that a dot keeps the *same* perpendicular offset from the path
        // dab after dab. Turn the pattern and the ribbons smear back into a band.
        out.append(Candidate(
            group: "Painting", slot: "Streaky", standing: .contender,
            name: "Streaky — Six Dots", kind: kind("streak-dots-6"),
            brush: Brush(name: "Streaky — Six Dots", tip: stamp("streak-dots-6"), size: 30,
                         dab: BrushDabSettings(size: 0.9, flow: 0.9, spacing: 0.04,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.55),
                             .flowFromPressure(amount: 0.3)
                         ])),
            note: "Six dots, one per band across the nib, so six distinct ribbons are guaranteed."))

        out.append(Candidate(
            group: "Painting", slot: "Streaky", standing: .contender,
            name: "Streaky — Eight Dots", kind: kind("streak-dots-8"),
            brush: Brush(name: "Streaky — Eight Dots", tip: stamp("streak-dots-8"), size: 30,
                         dab: BrushDabSettings(size: 0.9, flow: 0.9, spacing: 0.04,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.55),
                             .flowFromPressure(amount: 0.3)
                         ])),
            note: "Eight dots placed by a uniform draw, which is what \"placed randomly\" says "
                + "literally — two can share a ribbon and leave a gap elsewhere."))

        out.append(contentsOf: texture(stamp: stamp, kind: kind))
        return out
    }

    // MARK: - Texture — §13's open question

    /// **Round four, and it is a question rather than a set.** §8.4 ruled *"generate Basics,
    /// Sketching, Inking and Painting; source CC0 only for Texture, where scanned grunge and
    /// splatter are genuinely hard to fake"*, and §12 stage 11 is the one stage that therefore
    /// carries a licensing step. §13: *"if §8.4's generator turns out to make credible grunge, the
    /// CC0 dependency disappears and §12 stage 11 with it. Nobody has tried."*
    ///
    /// **Three levers separate these rows from every earlier sheet, and only the third is new
    /// information.**
    ///
    /// 1. **Spacing.** Every shipped brush walks at 0.03–0.095; these walk at 0.25–0.7. §8.4 already
    ///    knew why — *"anything whose character is in its pixels needs the dabs far enough apart to
    ///    be seen one at a time"* — and the blender died of it, but nobody had then turned the dial
    ///    the other way. A grunge brush is a **stamp** brush, and a paint program has always spaced
    ///    one that way.
    /// 2. **Holes at floor 0 and a grossly asymmetric outline under `angle.jitter 1`**, which is
    ///    §8.4's boundary paragraph applied rather than rediscovered. Every slot carries a **no-turn
    ///    control** so the sheet says which term did the work.
    /// 3. **§2.25's canvas-anchored paper**, which did not exist when §8.4 was written and changes
    ///    the argument rather than adding to it: the sheet multiplies in at the **merge**, once per
    ///    stroke, so a hole in it is not filled by the next dab at any spacing or flow. §8.4's union
    ///    argument does not reach it at all. The Chalk rows are that A/B — one picture, the texture
    ///    added a term at a time — and Grunge carries the same pair.
    private static func texture(stamp: @escaping (String) -> BrushTip,
                                kind: (String) -> Kind) -> [Candidate] {
        var out: [Candidate] = []

        // MARK: Grunge

        // The A leg. A lobed, torn crust whose interior is holes rather than mottle, stamped every
        // 0.30 of a width so about three dabs overlap a point instead of twenty.
        let grungeDab = { (spacing: Double, jitter: Double) in
            BrushDabSettings(size: 0.9, flow: 0.55, spacing: spacing,
                             angle: BrushAngleSettings(jitter: jitter))
        }
        let grungeRows = BrushModulations([
            .sizeFromPressure(amount: 0.2, atZero: 0.7),
            BrushModulation(.size, .random(.scatterAngle, .plain(0.9)), amount: 0.18),
            .flowFromPressure(amount: 0.35)
        ])

        out.append(Candidate(
            group: "Texture", slot: "Grunge", standing: .contender,
            name: "Grunge — Crust", kind: kind("grunge-crust"),
            brush: Brush(name: "Grunge — Crust", tip: stamp("grunge-crust"), size: 46,
                         dab: grungeDab(0.30, 1), stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: grungeRows),
            note: "The picture alone, at a stamp brush's spacing. Lobed outline, torn boundary, "
                + "interior holes at floor 0 — and 0.30 spacing, which is 3× anything shipped."))

        out.append(Candidate(
            group: "Texture", slot: "Grunge", standing: .control,
            name: "Grunge — Crust, No Turn", kind: kind("grunge-crust"),
            brush: Brush(name: "Grunge — Crust, No Turn", tip: stamp("grunge-crust"), size: 46,
                         dab: grungeDab(0.30, 0.03),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: grungeRows),
            note: "The same picture with the turn taken away — §8.4's asymmetry-alone cell. It "
                + "should read as one blot repeated at a regular interval, not as grunge."))

        out.append(Candidate(
            group: "Texture", slot: "Grunge", standing: .control,
            name: "Grunge — Crust, Tight", kind: kind("grunge-crust"),
            brush: Brush(name: "Grunge — Crust, Tight", tip: stamp("grunge-crust"), size: 46,
                         dab: grungeDab(0.05, 1), stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: grungeRows),
            note: "The same picture and the same turn at a *shipped* brush's spacing. §8.4's "
                + "minimum-spacing finding, which killed the first sheet's blender — the holes "
                + "should union away into a plain band."))

        // The §2.25 leg: **only `texture` differs** from Crust, so the pair is attributable.
        out.append(Candidate(
            group: "Texture", slot: "Grunge", standing: .contender,
            name: "Grunge — Crust + Paper", kind: kind("grunge-crust"),
            brush: Brush(name: "Grunge — Crust + Paper", tip: stamp("grunge-crust"), size: 46,
                         dab: grungeDab(0.30, 1), stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: grungeRows,
                         texture: BrushTextureSettings(mask: .builtIn(.paperTooth),
                                                       tileSize: 160, depth: 0.6)),
            note: "Crust with §2.25's canvas-anchored Rough Tooth over it and nothing else "
                + "changed. The sheet merges once per stroke, so its holes cannot be unioned away "
                + "— which is the mechanism §8.4 did not have. Laid at 160pt and 0.6 depth: round "
                + "one had 44pt and 0.85 and the paper *competed* with the nib instead of "
                + "staining it."))

        out.append(Candidate(
            group: "Texture", slot: "Grunge", standing: .contender,
            name: "Grunge — Soot", kind: kind("grunge-soot"),
            brush: Brush(name: "Grunge — Soot", tip: stamp("grunge-soot"), size: 40,
                         dab: BrushDabSettings(size: 0.9, flow: 0.8, spacing: 0.34,
                                               density: 0.9, densityWavelength: 0.6,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.6),
                             BrushModulation(.size, .random(.scatterAngle, .plain(1.4)), amount: 0.26)
                         ])),
            note: "A finer hole field than Crust's, denser and blacker. **Round one had this at "
                + "spacing 0.62 with a 0.55 dropout and it fell apart into islands** — past about "
                + "0.4 a stamp brush stops being a stroke, which is the far end of §8.4's "
                + "minimum-spacing finding and is on this sheet because nobody had found it."))

        // MARK: Splatter

        let splatterRows = BrushModulations([
            .sizeFromPressure(amount: 0.25, atZero: 0.55),
            BrushModulation(.size, .random(.scatterAngle, .plain(0.4)), amount: 0.35),
            .flowFromPressure(amount: 0.15)
        ])

        out.append(Candidate(
            group: "Texture", slot: "Splatter", standing: .contender,
            name: "Splatter — Spray", kind: kind("splatter-drops"),
            brush: Brush(name: "Splatter — Spray", tip: stamp("splatter-drops"), size: 48,
                         dab: BrushDabSettings(size: 0.95, flow: 0.95, spacing: 0.46,
                                               density: 0.7, densityWavelength: 1.0,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: splatterRows),
            note: "Twenty-six drops off a cube law — one or two carriers, the rest flecks — turned "
                + "and resized per stamp. The drops' own spread nearly to the mask's edge is what "
                + "puts ink off the path, since a stamp lands on it."))

        out.append(Candidate(
            group: "Texture", slot: "Splatter", standing: .control,
            name: "Splatter — Spray, No Turn", kind: kind("splatter-drops"),
            brush: Brush(name: "Splatter — Spray, No Turn", tip: stamp("splatter-drops"), size: 48,
                         dab: BrushDabSettings(size: 0.95, flow: 0.95, spacing: 0.46,
                                               density: 0.7, densityWavelength: 1.0,
                                               angle: BrushAngleSettings(jitter: 0.03)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: splatterRows),
            note: "The same cluster stamped at the same angle every time. §8.5's sawtooth in its "
                + "purest form — this should read as a repeating pattern rather than as a spray."))

        out.append(Candidate(
            group: "Texture", slot: "Splatter", standing: .contender,
            name: "Splatter — Fine", kind: kind("splatter-fine"),
            brush: Brush(name: "Splatter — Fine", tip: stamp("splatter-fine"), size: 34,
                         dab: BrushDabSettings(size: 0.95, flow: 0.9, spacing: 0.34,
                                               density: 0.7, densityWavelength: 0.6,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: splatterRows),
            note: "Twenty smaller drops with no carrier among them, at a tighter spacing — an "
                + "airbrush mist rather than a flicked loaded brush."))

        // MARK: Stipple

        // §2.18's own sentence is that λ is what makes a stipple: *"at λ = 0 ten overlapping dabs
        // cover every point … at λ ≈ 3–4 a contiguous run drops and the line breaks."* So the
        // dynamics arm is a small hard disc walked far apart with a **short**-λ dropout, and the
        // long-λ row beside it is on the sheet in order to be a broken line instead.
        let stippleDynamics = { (lambda: CGFloat) in
            Brush(name: "Stipple", tip: .round, size: 10,
                  dab: BrushDabSettings(size: 0.55, flow: 1, spacing: 0.70, hardness: 0.92,
                                        density: 0.42, densityWavelength: lambda),
                  stroke: BrushStrokeSettings(stabilization: 0.25),
                  modulations: BrushModulations([
                      .sizeFromPressure(amount: 0.3, atZero: 0.45),
                      BrushModulation(.size, .random(.scatterAngle, .plain(0.25)), amount: 0.45)
                  ]))
        }

        out.append(Candidate(
            group: "Texture", slot: "Stipple", standing: .contender,
            name: "Stipple — Dynamics", kind: .dynamicsOnly,
            brush: stippleDynamics(0.2),
            note: "No picture at all: a small hard disc, spacing 0.70, and §2.18's dropout at "
                + "λ 0.2 so skips are isolated. The size draw is what stops it being a ruler."))

        out.append(Candidate(
            group: "Texture", slot: "Stipple", standing: .control,
            name: "Stipple — Dynamics, Long λ", kind: .dynamicsOnly,
            brush: stippleDynamics(3.5),
            note: "The same brush with λ at §2.17's shipped 3.5. §2.18 says this is a *segmented "
                + "line* rather than a stipple — the dropout drops runs. On the sheet to fail as a "
                + "stipple and to show what λ is doing."))

        out.append(Candidate(
            group: "Texture", slot: "Stipple", standing: .contender,
            name: "Stipple — Specks", kind: kind("stipple-specks"),
            brush: Brush(name: "Stipple — Specks", tip: stamp("stipple-specks"), size: 30,
                         dab: BrushDabSettings(size: 0.9, flow: 0.95, spacing: 0.34,
                                               density: 0.85, densityWavelength: 0.4,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.3, atZero: 0.5),
                             BrushModulation(.size, .random(.scatterAngle, .plain(0.3)), amount: 0.25)
                         ])),
            note: "What a picture adds over the row above: one stamp is already seventeen "
                + "hard-edged dots of mixed size, so a drag lays a field rather than a line."))

        // MARK: Chalk
        //
        // **The cleanest A/B on this sheet.** Four rows, one nib, and the only thing that changes
        // between the first three is `Brush.texture` — no paper, `paperGrain`, `paperTooth`. If §2.25
        // is what makes a generated chalk credible, these three rows say so and nothing else on the
        // sheet has to.
        let chalkBrush = { (name: String, texture: BrushTextureSettings?) in
            Brush(name: name, tip: stamp("chalk-block"), size: 30, opacity: 0.95,
                  dab: BrushDabSettings(size: 0.85, flow: 0.5, spacing: 0.09,
                                        angle: BrushAngleSettings(jitter: 1)),
                  stroke: BrushStrokeSettings(stabilization: 0.18),
                  modulations: BrushModulations([
                      .sizeFromPressure(amount: 0.3, atZero: 0.5),
                      .flowFromPressure(amount: 0.5)
                  ]),
                  texture: texture)
        }

        out.append(Candidate(
            group: "Texture", slot: "Chalk", standing: .contender,
            name: "Chalk — Block", kind: kind("chalk-block"),
            brush: chalkBrush("Chalk — Block", nil),
            note: "The nib on its own — a torn squarish stick whose interior is holes. The A leg "
                + "of the texture A/B: everything below is this row plus a sheet."))

        out.append(Candidate(
            group: "Texture", slot: "Chalk", standing: .contender,
            name: "Chalk — Block + Paper Grain", kind: kind("chalk-block"),
            brush: chalkBrush("Chalk — Block + Paper Grain",
                              BrushTextureSettings(mask: .builtIn(.paperGrain),
                                                   tileSize: 80, depth: 1)),
            note: "The same row plus §2.25's shipped Paper Grain at full depth. That sheet floors "
                + "at 0.35, so it can only dim — the question this row asks is whether dimming is "
                + "enough when it is applied at the merge instead of per dab."))

        out.append(Candidate(
            group: "Texture", slot: "Chalk", standing: .contender,
            name: "Chalk — Block + Tooth", kind: kind("chalk-block"),
            brush: chalkBrush("Chalk — Block + Tooth",
                              BrushTextureSettings(mask: .builtIn(.paperTooth),
                                                   tileSize: 80, depth: 0.9)),
            note: "And the same row again with Rough Tooth, whose valleys reach 0.04. The four "
                + "Chalk rows differ in exactly one field."))

        out.append(Candidate(
            group: "Texture", slot: "Chalk", standing: .contender,
            name: "Chalk — Block + Tooth, Coarse", kind: kind("chalk-block"),
            brush: chalkBrush("Chalk — Block + Tooth, Coarse",
                              BrushTextureSettings(mask: .builtIn(.paperTooth),
                                                   tileSize: 150, depth: 0.9)),
            note: "The same sheet laid at 150pt instead of 80. `tileSize` is in canvas points, so "
                + "this row is the *scale* question on its own: at 150 the tooth is coarser than "
                + "the 30pt nib and reads as blotches, at 80 it reads as paper."))

        out.append(Candidate(
            group: "Texture", slot: "Chalk", standing: .contender,
            name: "Chalk — Worn Broad", kind: kind("chalk-worn"),
            brush: Brush(name: "Chalk — Worn Broad", tip: stamp("chalk-worn"), size: 44,
                         opacity: 0.95,
                         dab: BrushDabSettings(size: 0.9, flow: 0.4, spacing: 0.13,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.18),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.28, atZero: 0.55),
                             .flowFromPressure(amount: 0.55)
                         ]),
                         texture: BrushTextureSettings(mask: .builtIn(.paperTooth),
                                                       tileSize: 110, depth: 0.8)),
            note: "A broader, blunter stick at a wider spacing and a lower flow, on a coarser "
                + "sheet — the side-of-the-chalk mark rather than the edge."))

        return out
    }

    // MARK: - The settings line, derived rather than written

    /// The brush's dab bases, as one line. **Derived from the value**, so a candidate whose numbers
    /// are edited cannot show the owner the old ones — the failure mode of a hand-written caption.
    static func basesLine(_ brush: Brush) -> String {
        var parts: [String] = ["size \(f(brush.size, 0))pt",
                               "dab ×\(f(brush.dab.size, 2))",
                               "flow \(f(brush.dab.flow, 2))",
                               "sp \(f(brush.dab.spacing, 3))"]
        if case .round = brush.tip { parts.append("hard \(f(brush.dab.hardness, 2))") }
        if brush.opacity < 1 { parts.append("op \(f(brush.opacity, 2))") }
        if brush.dab.density < 1 {
            parts.append("dens \(f(brush.dab.density, 2)) λ\(f(Double(brush.dab.densityWavelength), 1))")
        }
        let angle = brush.dab.angle
        if angle.base != 0 { parts.append("∠\(f(angle.base, 3))t") }
        if angle.directionFollow != 0 { parts.append("follow \(f(angle.directionFollow, 2))") }
        if angle.jitter != 0 {
            parts.append("jitter \(f(angle.jitter, 3)) (±\(f(angle.jitter * 180, 0))°)")
        }
        // **§2.25's paper, printed because round four's whole question turns on it.** A row that
        // lays ink through a sheet and a row that does not are otherwise identical in every number
        // on this line, and the Chalk slot is three of exactly that pair.
        if let texture = brush.texture {
            parts.append("tex \(name(texture.mask)) @\(f(texture.tileSize, 0))pt "
                         + "d\(f(texture.depth, 2))")
        }
        return parts.joined(separator: "  ")
    }

    private static func name(_ ref: BrushTextureRef) -> String {
        switch ref {
        case .builtIn(let built): return built.displayName
        case .imported(let fileName): return fileName
        }
    }

    /// The matrix's rows, as one line.
    static func rowsLine(_ brush: Brush) -> String {
        let rows = brush.modulations.rows
        guard !rows.isEmpty else { return "no modulation rows" }
        return rows.map { row -> String in
            let curve = row.modules.contains { if case .curveRamp(let c) = $0 { return !c.isLinear }; return false } ? "↗" : ""
            return "\(short(row.output))←\(short(row.input))\(curve) \(f(row.amount, 2))"
        }.joined(separator: "  ")
    }

    private static func short(_ output: BrushOutput) -> String {
        switch output {
        case .size: return "size"
        case .flow: return "flow"
        case .angle: return "ang"
        case .spacing: return "sp"
        case .scatterAcross: return "scX"
        case .scatterAlong: return "scY"
        case .density: return "dens"
        case .hardness: return "hard"
        case .hue: return "hue"
        case .saturation: return "sat"
        case .brightness: return "bri"
        }
    }

    private static func short(_ input: BrushInput) -> String {
        switch input {
        case .pressure: return "press"
        case .tiltAngle: return "tilt"
        case .tiltDirection: return "tiltdir"
        case .direction: return "dir"
        case .taper: return "taper"
        case .velocity: return "vel"
        case .random(_, let r): return "rnd(λ\(f(Double(r.wavelength), 2)))"
        }
    }

    private static func f(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    private static func f(_ value: CGFloat, _ places: Int) -> String {
        String(format: "%.\(places)f", Double(value))
    }
}
