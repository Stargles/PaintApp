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
/// **Three kinds of candidate, and the sheet marks which is which**, because the most useful thing
/// on it is that some of these need no artwork at all:
///
/// - `.generatedTip` — a `BrushTipGenerator` PNG, stamped through `BrushTip.stamp`.
/// - `.dynamicsOnly` — a **clean round tip** whose whole character is §6's matrix. §8.4's
///   refutation: the rough ink nib the owner singled out is one of these, and a tip texture for it
///   measured *nine times weaker* than `random → size` at the same nominal roughness.
/// - `.procedural` — `BrushTip.round` with a hardness and a spacing and nothing else. Soft round,
///   hard round, the technical pens and the opaque round are all this, which is four of §8.6's
///   twenty-odd already answered by arithmetic.
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

    struct Candidate {
        let group: String
        let name: String
        let kind: Kind
        let brush: Brush
        /// One line of prose about what this candidate is *for*. The settings line under it is
        /// derived from the brush rather than written, so it cannot go stale.
        let note: String
    }

    /// §8.6's five groups, in its own order. `Texture` holds nothing: it is §12 stage 11's CC0
    /// sourcing, and showing it empty is more honest than leaving it off the sheet.
    static let groups: [String] = ["Basics", "Sketching", "Inking", "Painting", "Texture"]

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
            group: "Basics", name: "Round Soft", kind: .procedural,
            brush: Brush(name: "Round Soft", tip: .round, size: 22,
                         dab: BrushDabSettings(size: 0.5, flow: 0.35, spacing: 0.06, hardness: 0.12),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.5, atZero: 0.2),
                             .flowFromPressure(amount: 0.65)
                         ])),
            note: "The falloff arm of §8.4. No picture: hardness is a number on the round tip."))

        out.append(Candidate(
            group: "Basics", name: "Round Hard", kind: .procedural,
            brush: Brush(name: "Round Hard", tip: .round, size: 16,
                         dab: BrushDabSettings(size: 0.6, flow: 0.9, spacing: 0.045, hardness: 0.95),
                         stroke: BrushStrokeSettings(stabilization: 0.1),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.4, atZero: 0.4),
                             .flowFromPressure(amount: 0.1)
                         ])),
            note: "A disc. BUGS.md records that hardness 0.95 is already a fully aliased edge."))

        out.append(Candidate(
            group: "Basics", name: "Square Slab 4:1", kind: kind("square-slab-4to1"),
            brush: Brush(name: "Square Slab 4:1", tip: stamp("square-slab-4to1"), size: 26,
                         dab: BrushDabSettings(size: 0.72, flow: 0.85, spacing: 0.06,
                                               angle: BrushAngleSettings(base: 0.25,
                                                                         directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.28, atZero: 0.55),
                             .flowFromPressure(amount: 0.15)
                         ])),
            note: "§8.6's SAI nib: long side across the travel, one drag lays one slab."))

        out.append(Candidate(
            group: "Basics", name: "Square Slab 2.5:1 (torn)", kind: kind("square-slab-2p5to1"),
            brush: Brush(name: "Square Slab 2.5:1", tip: stamp("square-slab-2p5to1"), size: 30,
                         dab: BrushDabSettings(size: 0.75, flow: 0.9, spacing: 0.075,
                                               angle: BrushAngleSettings(base: 0.25,
                                                                         directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.6),
                             .flowFromPressure(amount: 0.1)
                         ])),
            note: "The same nib with the edge roughness cranked, to see how much survives the walk."))

        // **The A/B §8.4 asks for, on the one nib that has a ragged edge by construction.** The two
        // rows above get their tear from the *picture*, and a picture is the same picture at every
        // dab: the ends that trace the stroke's edges present one fixed profile, ten overlapping
        // dabs take its running maximum, and what survives is a wobbly straight line rather than a
        // torn one. §8.4 MEASURED exactly that for a round nib (1.08% as a lone dab, 0.41% in a
        // stroke) and there is no reason the slab escapes it.
        //
        // So this is the same tip with the roughness moved into §6 instead: a short-λ `size ←
        // random` and a few degrees of per-dab `angle.jitter`, both of which vary *along the arc*
        // and therefore move the envelope the union takes. If it reads as more torn than the two
        // above, that is §8.4's refutation reaching the square nib, and the tip's own raggedness is
        // worth only what it adds at the caps and at a crossing.
        out.append(Candidate(
            group: "Basics", name: "Square Slab 4:1 + dynamics", kind: kind("square-slab-4to1"),
            brush: Brush(name: "Square Slab 4:1 + dynamics", tip: stamp("square-slab-4to1"), size: 26,
                         dab: BrushDabSettings(size: 0.62, flow: 0.85, spacing: 0.06,
                                               angle: BrushAngleSettings(base: 0.25,
                                                                         directionFollow: 1,
                                                                         jitter: 0.03)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.24, atZero: 0.55),
                             BrushModulation(.size, .random(.scatterAngle, .plain(0.6)),
                                             amount: 0.14),
                             .flowFromPressure(amount: 0.15)
                         ])),
            note: "The same PNG, roughened by §6 instead of by the picture. The A/B for whether a "
                + "ragged tip edge survives the walk at all."))

        out.append(Candidate(
            group: "Basics", name: "Chisel 5:1", kind: kind("chisel-5to1"),
            brush: Brush(name: "Chisel 5:1", tip: stamp("chisel-5to1"), size: 28,
                         dab: BrushDabSettings(size: 0.8, flow: 0.95, spacing: 0.035,
                                               angle: BrushAngleSettings(base: 0.125,
                                                                         directionFollow: 0)),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.2, atZero: 0.7)
                         ])),
            note: "Fixed 45° hold, no direction-follow — the thick/thin is the stroke turning."))

        // MARK: - Sketching

        out.append(Candidate(
            group: "Sketching", name: "Pencil Hard", kind: kind("pencil-hard"),
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
            group: "Sketching", name: "Pencil Soft", kind: kind("pencil-soft"),
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
            group: "Sketching", name: "Pencil Blunt", kind: kind("pencil-blunt"),
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
            note: "A worn nib with a ground flat, partly following the travel so the flat reads."))

        out.append(Candidate(
            group: "Sketching", name: "Pencil Textured", kind: kind("pencil-textured"),
            brush: Brush(name: "Pencil Textured", tip: stamp("pencil-textured"), size: 20,
                         opacity: 0.9,
                         dab: BrushDabSettings(size: 0.7, flow: 0.5, spacing: 0.085,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.15),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.3, atZero: 0.45),
                             .flowFromPressure(amount: 0.5)
                         ])),
            note: "Coarse pits, wide spacing. The test of whether interior holes survive the union."))

        // MARK: - Inking

        out.append(Candidate(
            group: "Inking", name: "Technical Pen — Fine", kind: .procedural,
            brush: Brush(name: "Technical Pen — Fine", tip: .round, size: 4,
                         dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.03, hardness: 1),
                         stroke: BrushStrokeSettings(stabilization: 0.45)),
            note: "Constant width, no pressure response at all — a Rotring, not a nib."))

        out.append(Candidate(
            group: "Inking", name: "Technical Pen — Tapered", kind: .procedural,
            brush: Brush(name: "Technical Pen — Tapered", tip: .round, size: 6,
                         dab: BrushDabSettings(size: 0.8, flow: 0.95, spacing: 0.03, hardness: 1),
                         stroke: BrushStrokeSettings(stabilization: 0.4),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.2, atZero: 0.8),
                             .flowFromPressure(amount: 0.05)
                         ])),
            note: "The same pen with a light size response, for lineart that needs weight."))

        out.append(Candidate(
            group: "Inking", name: "Brush Pen", kind: kind("pen-brush"),
            brush: Brush(name: "Brush Pen", tip: stamp("pen-brush"), size: 26,
                         dab: BrushDabSettings(size: 0.35, flow: 0.9, spacing: 0.035,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.35),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.65, atZero: 0.12),
                             .flowFromPressure(amount: 0.1)
                         ])),
            note: "A teardrop lying along the travel; the taper is mostly size ← pressure."))

        // **§8.4's refutation, made visible.** These three carry no tip. What makes them rough is
        // §2.18's `density` at §2.17's λ, and several `random → size` rows at different λ — which
        // §8.4 MEASURED at 3.6% of a brush width against 0.41% for an eroded disc.
        out.append(Candidate(
            group: "Inking", name: "Rough Ink — Dry", kind: .dynamicsOnly,
            brush: Brush(name: "Rough Ink — Dry", tip: .round, size: 9,
                         dab: BrushDabSettings(size: 0.6, flow: 0.95, spacing: 0.05, hardness: 0.9,
                                               density: 0, densityWavelength: 3.5),
                         stroke: BrushStrokeSettings(stabilization: 0.3),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.22, atZero: 0.5),
                             BrushModulation(.size, .random(.scatterAngle, .plain(1.2)),
                                             amount: 0.16),
                             BrushModulation(.size, .random(.scatterAngle, .plain(0.25)),
                                             amount: 0.07),
                             BrushModulation(.scatter, .random(.scatterAngle, .plain(2.0)),
                                             amount: 0.10),
                             .densityFromPressure(knee: 1.0 / 3, floor: 0),
                             .flowFromPressure(amount: 0.05)
                         ])),
            note: "λ 3.5 widths and a floor of 0: a light stroke breaks into long arcs."))

        out.append(Candidate(
            group: "Inking", name: "Rough Ink — Blotchy", kind: .dynamicsOnly,
            brush: Brush(name: "Rough Ink — Blotchy", tip: .round, size: 11,
                         dab: BrushDabSettings(size: 0.5, flow: 0.9, spacing: 0.045, hardness: 0.85,
                                               density: 0, densityWavelength: 4.0),
                         stroke: BrushStrokeSettings(stabilization: 0.3),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.16, atZero: 0.55),
                             BrushModulation(.size, .random(.scatterAngle, .plain(2.5)),
                                             amount: 0.30),
                             BrushModulation(.size, .random(.scatterAngle, .plain(0.3)),
                                             amount: 0.10),
                             BrushModulation(.scatter, .random(.scatterAngle, .plain(1.5)),
                                             amount: 0.14),
                             .densityFromPressure(knee: 0.4, floor: 0.45),
                             .flowFromPressure(amount: 0.1)
                         ])),
            note: "Half the dropout, twice the width wobble — blotchy rather than segmented."))

        out.append(Candidate(
            group: "Inking", name: "Rough Ink — Aliased", kind: .dynamicsOnly,
            brush: Brush(name: "Rough Ink — Aliased", tip: .round, size: 8,
                         dab: BrushDabSettings(size: 0.65, flow: 1, spacing: 0.055, hardness: 1,
                                               density: 0, densityWavelength: 3.0),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.2, atZero: 0.6),
                             BrushModulation(.size, .random(.scatterAngle, .plain(1.5)),
                                             amount: 0.22),
                             BrushModulation(.scatter, .random(.scatterAngle, .plain(2.5)),
                                             amount: 0.08),
                             .densityFromPressure(knee: 0.3, floor: 0.15)
                         ])),
            note: "§8.4's open question: hardness 1.00 is a deterministic two-alpha edge. "
                + "Is the aliasing an ingredient?"))

        // MARK: - Painting

        out.append(Candidate(
            group: "Painting", name: "Opaque Round", kind: .procedural,
            brush: Brush(name: "Opaque Round", tip: .round, size: 34,
                         dab: BrushDabSettings(size: 0.85, flow: 1, spacing: 0.05, hardness: 0.8),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.15, atZero: 0.75)
                         ])),
            note: "Flow 1 and a near-hard edge: covers in one pass, which is what painting wants."))

        out.append(Candidate(
            group: "Painting", name: "Flat", kind: kind("paint-flat"),
            brush: Brush(name: "Flat", tip: stamp("paint-flat"), size: 36,
                         dab: BrushDabSettings(size: 0.85, flow: 0.8, spacing: 0.03,
                                               angle: BrushAngleSettings(base: 0.125,
                                                                         directionFollow: 0)),
                         stroke: BrushStrokeSettings(stabilization: 0.25),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.15, atZero: 0.7),
                             .flowFromPressure(amount: 0.2)
                         ])),
            note: "A loaded flat: feathered long edges, rounded ends, held at a fixed angle."))

        out.append(Candidate(
            group: "Painting", name: "Bristle", kind: kind("paint-bristle-0"),
            brush: Brush(name: "Bristle", tip: stamp("paint-bristle-0"), size: 34, opacity: 0.95,
                         dab: BrushDabSettings(size: 0.75, flow: 0.55, spacing: 0.025,
                                               angle: BrushAngleSettings(directionFollow: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.2),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.25, atZero: 0.55),
                             .flowFromPressure(amount: 0.45)
                         ])),
            note: "Eleven filaments along the travel. Two more variants exist; §8.5's per-dab "
                + "pick is not built, so only this one is reachable."))

        out.append(Candidate(
            group: "Painting", name: "Blender", kind: kind("paint-blender"),
            brush: Brush(name: "Blender", tip: stamp("paint-blender"), size: 40, opacity: 0.45,
                         dab: BrushDabSettings(size: 0.9, flow: 0.25, spacing: 0.10,
                                               angle: BrushAngleSettings(jitter: 1)),
                         stroke: BrushStrokeSettings(stabilization: 0.35),
                         modulations: BrushModulations([
                             .sizeFromPressure(amount: 0.1, atZero: 0.8),
                             .flowFromPressure(amount: 0.15)
                         ])),
            note: "Soft and mottled. Spacing is 0.10 rather than 0.02 on purpose: at 2% the mottle "
                + "was unioned away entirely and this was a plain soft round with extra steps."))

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
        if angle.jitter != 0 { parts.append("jitter \(f(angle.jitter, 2))") }
        return parts.joined(separator: "  ")
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
        case .scatter: return "scat"
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
