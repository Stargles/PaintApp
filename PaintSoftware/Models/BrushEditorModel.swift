import CoreGraphics
import Foundation

/// **What the brush editor shows, and the arithmetic behind the two controls that are not sliders** —
/// BRUSH.md §2.24, §7 and §7.2, `§12` stage 10.
///
/// **Everything here is outside a `View` file on purpose**, exactly as `SizePreview` is and for the
/// identical reason: `PaintSoftwareUITests` compiles a hand-picked list of app sources and no
/// `Views/Brush*.swift` is on it, so a rule written inside `BrushEditorScreen` is a rule no fast-tier
/// test can reach. The screen owns layout and touches; this owns what the outputs are, what a chain
/// is, and where a finger lands on a response curve.

// MARK: - The index: every output, grouped

/// One thing the editor lets an artist change.
///
/// **Two kinds, and the split is the model's rather than the screen's.** `output` is a
/// `BrushOutput` — a base value plus however many of §6's rows drive it. `stabilization` and
/// `blendMode` are `BrushStrokeSettings` fields: they belong to the *gesture* rather than to a dab,
/// no row can drive them, and there is no sensor reading that would mean anything if one could. A
/// screen that offered them an input picker would be implying a mechanism the engine does not have.
enum BrushEditorControl: Hashable {
    case output(BrushOutput)
    case stabilization
    case blendMode
}

/// A row of the editor's index — BRUSH.md §2.24's *"a dropdown list of all the outputs of the
/// brush"*, one entry per line.
struct BrushEditorEntry: Hashable, Identifiable {
    let control: BrushEditorControl
    /// Stable, and it is what an accessibility identifier is built from — so a UI test names an
    /// output the way the model does.
    let id: String
    let name: String
    /// The units sentence shown under the base slider.
    ///
    /// **§7.0's second worked example is answered by one of these and by no code at all.** The owner
    /// asked for *"spacing that grows with the brush"*; `spacing` is already a fraction of the
    /// stroke's diameter, so the editor's job there is to *say so in its units* rather than to add a
    /// control. Putting that sentence in the model rather than in the view is what makes it
    /// assertable.
    let detail: String
}

/// A heading in that list — §2.24's *"These can be organized into groups."*
struct BrushEditorGroup: Hashable, Identifiable {
    let name: String
    let entries: [BrushEditorEntry]
    var id: String { name }
}

/// **Every parameter the editor exposes, in the order it shows them.**
///
/// The grouping is by *what the artist is changing*, which is §7.2's ruling and not Procreate's
/// tabs: our model has `density`, λ and §2.22's second input and Procreate has none of those, and it
/// has Wet Mix and Bleed and we have neither.
///
/// **This list is the answer to §7's *"parameters with no UI at all today"***: `scatter`, the angle's
/// three contributions, `hardness`, `density` and its λ, `blendMode` and the three HSB shifts were
/// all unreachable from any screen before stage 10, and every one of them is here.
enum BrushEditorCatalog {

    static let groups: [BrushEditorGroup] = [
        BrushEditorGroup(name: "Shape", entries: [
            entry(.size, "Size",
                  "A multiplier on the stroke's own diameter. 1 is full width."),
            entry(.hardness, "Hardness",
                  "How sharp a round tip's edge is. Reaches a picture tip not at all — its edge is in its own pixels."),
            entry(.angle, "Angle",
                  "The tip's rotation, in turns. A round tip turned is the same disc, so this reaches a stamp tip only.")
        ]),
        BrushEditorGroup(name: "Ink", entries: [
            entry(.flow, "Flow",
                  "What one dab lays down. The stroke's own opacity is the cap on what all of them together reach."),
            BrushEditorEntry(control: .blendMode, id: "blendMode", name: "Blend Mode",
                             detail: "How the finished stroke merges with what is under it — once, at the merge, not per dab."),
            BrushEditorEntry(control: .stabilization, id: "stabilization", name: "Stabilization",
                             detail: "How much the gesture is smoothed before it becomes a stroke. Not a dab parameter.")
        ]),
        BrushEditorGroup(name: "Placement", entries: [
            entry(.spacing, "Spacing",
                  "The gap between dabs as a fraction of the stroke's diameter — so a brush lays the same relative gaps at size 4 and at size 80."),
            entry(.scatter, "Scatter",
                  "How far off the path a dab may land, in brush widths."),
            entry(.density, "Density",
                  "The chance a dab is stamped at all. Below 1 the line breaks up; the survivors stay on the same lattice.")
        ]),
        BrushEditorGroup(name: "Colour", entries: [
            entry(.hue, "Hue Shift", "Turns each dab's colour around the wheel, in turns."),
            entry(.saturation, "Saturation Shift", "Adds to each dab's saturation."),
            entry(.brightness, "Brightness Shift", "Adds to each dab's brightness.")
        ])
    ]

    private static func entry(_ output: BrushOutput, _ name: String, _ detail: String) -> BrushEditorEntry {
        BrushEditorEntry(control: .output(output), id: output.rawValue, name: name, detail: detail)
    }

    static var entries: [BrushEditorEntry] { groups.flatMap(\.entries) }

    static func entry(id: String) -> BrushEditorEntry? { entries.first { $0.id == id } }

    /// **Every `BrushOutput` reaches the screen.** Asserted rather than assumed: `BrushOutput` is
    /// `CaseIterable` and a case added later would otherwise be a parameter with a renderer and no
    /// control, which is the exact half-built state CLAUDE.md's "a feature is not finished because
    /// its model is correct" section is about.
    static var coveredOutputs: Set<BrushOutput> {
        Set(entries.compactMap { if case .output(let output) = $0.control { return output } else { return nil } })
    }
}

// MARK: - Where a base value lives, and what its slider spans

extension BrushOutput {

    /// The `Brush` field this output's **base** is stored in — §6's *base value + [modulation]*.
    ///
    /// `angle`'s is `dab.angle.base`, which is the first of its three contributions; the other two
    /// (direction-follow and jitter) are not outputs at all and the screen shows them beside it.
    var baseKeyPath: WritableKeyPath<Brush, Double> {
        switch self {
        case .size: return \Brush.dab.size
        case .flow: return \Brush.dab.flow
        case .spacing: return \Brush.dab.spacing
        case .scatter: return \Brush.dab.scatter
        case .density: return \Brush.dab.density
        case .hardness: return \Brush.dab.hardness
        case .angle: return \Brush.dab.angle.base
        case .hue: return \Brush.dab.hueShift
        case .saturation: return \Brush.dab.saturationShift
        case .brightness: return \Brush.dab.brightnessShift
        }
    }

    /// What the base slider spans.
    ///
    /// **Wider than the shipped presets use, and narrower than the model allows.** `ResponseCurve`
    /// deliberately does not clamp, and §12 stage 8 records what that cost when a bound was inferred
    /// from `Σ|amount|` — so these are a *slider's* travel and nothing downstream reads them as a
    /// guarantee. The three colour shifts are signed because a hue shift of −0.1 is as ordinary as
    /// +0.1; `spacing` starts above zero because a spacing of 0 is an infinite dab count.
    var editorRange: ClosedRange<Double> {
        switch self {
        case .size: return 0...2
        case .flow: return 0...1
        case .spacing: return 0.01...1
        case .scatter: return 0...2
        case .density: return 0...1
        case .hardness: return 0...1
        case .angle: return 0...1
        case .hue: return -0.5...0.5
        case .saturation, .brightness: return -1...1
        }
    }

    /// How the base and a row's amount are written out. Percent for the `0…1` fractions, turns for
    /// the two angular ones, plain for the rest.
    func format(_ value: Double) -> String {
        switch self {
        case .size, .flow, .density, .hardness, .spacing, .saturation, .brightness:
            return "\(Int((value * 100).rounded()))%"
        case .angle, .hue:
            return String(format: "%.3f turns", value)
        case .scatter:
            return String(format: "%.2f widths", value)
        }
    }
}

// MARK: - The inputs, as a picker can offer them

/// **`BrushInput` without its payload** — what a picker can list.
///
/// `BrushInput.random` carries a `DabRandom.Channel` and a wavelength, and the channel is **derived,
/// never authored** (§6.2). So the thing an artist picks is the *kind*; the channel is minted by
/// `BrushModulations` from where the row sits, and λ is the one half of `.random` that is authored.
enum BrushInputKind: String, CaseIterable, Hashable, Identifiable {
    case pressure
    case tiltAngle
    case tiltDirection
    case direction
    case taper
    case velocity
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pressure: return "Pressure"
        case .tiltAngle: return "Tilt Angle"
        case .tiltDirection: return "Tilt Direction"
        case .direction: return "Direction"
        case .taper: return "Taper"
        case .velocity: return "Velocity"
        case .random: return "Random"
        }
    }

    /// **The channel is deliberately garbage here.** `BrushModulations` rewrites it from the row's
    /// position on construction and on decode, in both slots, so anything minted outside that type is
    /// overwritten before it can be read — which is §6.2's *"derived rather than stored"* doing its
    /// job rather than a shortcut. A hand-picked channel would be the stale-field defect §6.2 exists
    /// to make unrepresentable.
    func input(wavelength: CGFloat = BrushEditorDefaults.wavelength) -> BrushInput {
        switch self {
        case .pressure: return .pressure
        case .tiltAngle: return .tiltAngle
        case .tiltDirection: return .tiltDirection
        case .direction: return .direction
        case .taper: return .taper
        case .velocity: return .velocity
        case .random: return .random(.modulation(.size, row: 0), wavelength: wavelength)
        }
    }
}

extension BrushInput {
    var kind: BrushInputKind {
        switch self {
        case .pressure: return .pressure
        case .tiltAngle: return .tiltAngle
        case .tiltDirection: return .tiltDirection
        case .direction: return .direction
        case .taper: return .taper
        case .velocity: return .velocity
        case .random: return .random
        }
    }

    /// The authored half of a `.random` input — nil for every sensor, which is what makes "show λ
    /// only where it means something" a property of the value rather than a rule in the view.
    var wavelength: CGFloat? {
        guard case .random(_, let wavelength) = self else { return nil }
        return wavelength
    }
}

enum BrushEditorDefaults {
    /// What a fresh `random` row's λ is, in brush widths (§2.17). Roughly the `density` row's own
    /// default, so a first randomiser reads as a wobble rather than as per-dab hash noise.
    static let wavelength: CGFloat = 3.5
    /// What a fresh row's amount is. Non-zero, because a row added at 0 does nothing and reads as a
    /// control that did not work — CLAUDE.md's "a refusal with no notice", reached through a default.
    static let amount: Double = 0.5
}

// MARK: - The owner's chain, over the rows that are actually stored

/// **BRUSH.md §2.24's chain, read off one stored row** — *"You select the input option of the brush …
/// Then you can add modifiers onto it, like it passes through an input/output curve ramp module,
/// then a randomizer module."*
///
/// One row of §6's matrix contributes `amount · curve(input) · reading(second)`. Read left to right
/// that **is** the owner's chain: an input, then a curve ramp, then a gain — and when the gain is
/// `.random`, a randomiser. So the shapes agree on the ordinary case rather than merely being
/// mappable onto each other.
///
/// Where they disagree is `BrushChainLimit`, which is written down rather than papered over, because
/// BRUSH.md §13 is where a difference between the owner's design and the storage belongs and because
/// the screen shows the artist the relevant sentence instead of a module list the engine cannot
/// honour.
struct BrushModulationChain: Equatable {
    enum Module: Equatable {
        /// The row's `ResponseCurve` — §2.24's *"input/output curve ramp module"*.
        case curveRamp(ResponseCurve)
        /// §2.22's second slot at `.random` — *"a randomizer module"*, and its reading **multiplies**
        /// what the curve produced rather than adding to it. That is the whole difference between
        /// this and a second row, and it is why §7.0's fourth worked example is expressible at all.
        case randomiser(wavelength: CGFloat)
        /// §2.22's second slot at a sensor. Not a module the owner named — it is the same slot the
        /// randomiser occupies, so the two are alternatives and the screen offers one picker.
        case gain(BrushInputKind)
    }

    var input: BrushInput
    var amount: Double
    var modules: [Module]

    /// **In the order the engine applies them**, which is the order they are read out here and the
    /// order the screen draws them. It is not the artist's to change — see
    /// `BrushChainLimit.moduleOrderIsFixed`.
    init(_ row: BrushModulation) {
        input = row.input
        amount = row.amount
        var modules: [Module] = []
        if !row.curve.isLinear { modules.append(.curveRamp(row.curve)) }
        switch row.second {
        case .none: break
        case .some(let second):
            if let wavelength = second.wavelength {
                modules.append(.randomiser(wavelength: wavelength))
            } else {
                modules.append(.gain(second.kind))
            }
        }
        self.modules = modules
    }

    /// The row this chain is of, for the output it drives.
    ///
    /// A chain carrying two curve ramps or two randomisers cannot round-trip — the storage has one
    /// slot for each — so the **last** of each kind wins and `BrushChainLimit` says so. Silently
    /// keeping the first would be the same lie told the other way round.
    func row(driving output: BrushOutput) -> BrushModulation {
        var curve = ResponseCurve.linear
        var second: BrushInput?
        for module in modules {
            switch module {
            case .curveRamp(let ramp): curve = ramp
            case .randomiser(let wavelength):
                second = .random(.modulation(output, row: 0, slot: 1), wavelength: wavelength)
            case .gain(let kind): second = kind.input()
            }
        }
        return BrushModulation(output, input, second: second, amount: amount, curve: curve)
    }
}

/// **Where §2.24's chain and §6's rows genuinely differ.** BRUSH.md §13 carries the same list in
/// prose; this is the copy the screen reads, so the sentence an artist is shown and the sentence the
/// document records cannot drift.
///
/// Every one of these is a limit of the *storage*, and none of them is fixed by changing the editor.
/// Closing any of them is a change to `BrushModulation`, which §2.22 already ruled on once and which
/// is not a decision to take inside a build of the screen that revealed it.
enum BrushChainLimit: String, CaseIterable, Identifiable {
    /// A row is `amount · curve(input) · second`, evaluated in that order and no other. So the curve
    /// ramp is always before the randomiser, and *"a randomizer, then a curve ramp"* — randomise
    /// first and shape the result — cannot be stated. §2.22 rules the second slot uncurved.
    case moduleOrderIsFixed
    /// One `curve` field, so one curve ramp. Two in series would need a second `ResponseCurve` per
    /// row, which is a second thing to keep in step for expressiveness nothing has asked for.
    case oneCurveRampPerChain
    /// One `second` field, so one randomiser. Two independent wobbles on one output are two *rows*,
    /// which sum rather than compose — §8.4's rough nib is built exactly that way.
    case oneRandomiserPerChain
    /// **Several chains on one output are summed, not chained.** The owner's *"for each output there
    /// can only be one input for now"* is true of everything the shipped set carries, and the storage
    /// does not enforce it: §8.4's nib is several `random` rows at different λ on one output. So the
    /// screen lists however many rows there are rather than hiding the extras behind a picker that
    /// can name one.
    case severalChainsPerOutputAreSummed

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .moduleOrderIsFixed:
            return "Modules run in one order: the curve ramp shapes the input, then the randomiser scales the result. That order is the engine's and cannot be swapped."
        case .oneCurveRampPerChain:
            return "One curve ramp per input. Two in series is not something the brush can store."
        case .oneRandomiserPerChain:
            return "One randomiser per input. A second independent wobble is a second input on the same output, which adds rather than chains."
        case .severalChainsPerOutputAreSummed:
            return "An output can carry more than one input. They add together — they do not feed into each other."
        }
    }
}

// MARK: - The response curve editor's arithmetic

/// **Where a finger lands on a response curve, and what it does when it lands there** — BRUSH.md §7's
/// four numbered points, the half a `View` cannot be asked about.
///
/// ## It reuses the timeline's control rather than being a second one
///
/// §7: *"reusing it is what keeps this from being a second curve implementation"*. What is reused,
/// exactly:
///
/// - **The type.** `ResponseCurve` stores an `AnimationCurve` (§6.1), so there is one curve model,
///   one tangent grammar, one `evaluate`, one codec. Nothing here does bezier arithmetic.
/// - **The mapping.** `y(ofValue:)` and `value(atY:)` *call* `TimelineGraphBand`'s, so the two
///   surfaces cannot drift about what a value's height is.
/// - **The constants and the tap predicate.** `hitRadius`, `tapSlop`, `isTap`, `lineWidth` and
///   `keyRadius` are `TimelineGraphBand`'s, which took them from `CurveEditor` in turn.
///
/// **What could not be reused is the drawing, and that is a fact about both existing controls rather
/// than a preference.** `TimelineGraphBand`'s own doc records the first half — *"The band is not
/// `CurveEditor` moved … none of its drawing is portable to a `UIView.draw(_:)` inside a scroll view
/// whose x axis belongs to the timeline"* — and the second half is its mirror image: the band's
/// drawing lives in `Views/TimelineTrackView.swift`, is a `UIView.draw(_:)` inside the timeline's
/// scroll view, and its `Content` needs a layer index, an effect, a track table and a descriptor
/// offset. `CurveEditor`, meanwhile, is the right *shape* — a square over a normalised `0…1` with the
/// tap grammar — and the wrong *model*: it edits `[CurvePoint]` through `MonotoneCubic`, not an
/// `AnimationCurve`. Neither could be pointed at a `ResponseCurve` without becoming the second
/// implementation §7 is trying to avoid.
///
/// ## The axis is fixed, and that is the whole of §7's first point
///
/// `TimelineGraphBand.Channel.axis` auto-ranges to a channel's live key values, and TODO (38)'s
/// device report is what that costs: with **two** keys both are extremes, so the axis rescales by
/// exactly what the drag changed and the dot lands back under the finger. `axis` here is a
/// **constant**. A key dragged up moves up.
enum ResponseCurveEditing {

    /// The square's side, in points. A square rather than a `GeometryReader`, `CurveEditor`'s reason
    /// verbatim: this sits inside a `ScrollView`, where a `GeometryReader` reports the *proposed*
    /// height and collapses the graph to nothing.
    static let side: CGFloat = 210

    /// **Fixed, never fitted to the keys.** See the type's note.
    ///
    /// `0…1` because that is what a curve *outputs*: `ResponseCurve.value(at:)` shapes the sensor's
    /// reading and the row's `amount` is what scales it to the output's range afterwards. Labelling
    /// this axis with the output's own range — which §7's first point proposed — would be a picture
    /// of a different number: a key at the top of a `size` curve does not mean size 2, it means the
    /// row contributes its whole amount there.
    static let axis: ClosedRange<Double> = 0...1

    static var hitRadius: CGFloat { TimelineGraphBand.hitRadius }
    static var tapSlop: CGFloat { TimelineGraphBand.tapSlop }
    static var lineWidth: CGFloat { TimelineGraphBand.lineWidth }
    /// Bigger than the band's 2.5 pt dot, because this graph is a fifth of the width and the dot is
    /// the only thing on it — the finger target is `hitRadius` either way.
    static let keyRadius: CGFloat = 4.5

    /// **Keys may not touch.** `AnimationCurve.setKey` replaces on collision, so a key allowed to
    /// travel onto its neighbour's frame would silently delete it — the destructive-continuous-
    /// gesture defect `TimelineGraphBand.moves` and `CurveEditor.moving` each guard against, one
    /// frame and one epsilon apart respectively.
    static let minimumFrameGap = 1

    // MARK: Geometry

    /// The sensor reading `0…1` a curve frame stands for. `ResponseCurve.scale` is the only unit
    /// conversion in the feature and it is named once, in that type.
    static func reading(ofFrame frame: Int) -> Double { Double(frame) / ResponseCurve.scale }

    static func x(ofFrame frame: Int, side: CGFloat = side) -> CGFloat {
        CGFloat(reading(ofFrame: frame)) * side
    }

    /// The frame an x means, rounded rather than floored: a key sits *on* the point the finger is
    /// over, and flooring would put every drag half a step behind the touch.
    static func frame(atX x: CGFloat, side: CGFloat = side) -> Int {
        let clamped = min(max(x / max(side, 1), 0), 1)
        return Int((Double(clamped) * ResponseCurve.scale).rounded())
    }

    static func y(ofValue value: Double, side: CGFloat = side) -> CGFloat {
        TimelineGraphBand.y(ofValue: value, in: axis, bandHeight: side)
    }

    static func value(atY y: CGFloat, side: CGFloat = side) -> Double {
        TimelineGraphBand.value(atY: y, in: axis, bandHeight: side)
    }

    static func point(ofKey key: AnimationCurve.Key, side: CGFloat = side) -> CGPoint {
        CGPoint(x: x(ofFrame: key.frame, side: side), y: y(ofValue: key.value, side: side))
    }

    // MARK: Hit testing

    /// The frame of the nearest key within `hitRadius`, or nil. `CurveEditor.nearestHandle`'s
    /// nearest-rather-than-first rule, which matters here because two keys a few frames apart share
    /// a pixel column at this scale.
    static func nearestKey(to location: CGPoint, in curve: AnimationCurve,
                           side: CGFloat = side) -> Int? {
        var best: (frame: Int, distance: CGFloat)?
        for key in curve.keys {
            let at = point(ofKey: key, side: side)
            let distance = hypot(at.x - location.x, at.y - location.y)
            guard distance <= hitRadius else { continue }
            if best == nil || distance < best!.distance { best = (key.frame, distance) }
        }
        return best?.frame
    }

    // MARK: Edits

    /// **What an empty curve becomes the moment it is touched, and it is free.**
    ///
    /// `ResponseCurve`'s identity is the *empty* curve — `value(at: x) == x` by a `guard` rather than
    /// by keys. But `AnimationCurve` with one key is a **constant**, so the first key an artist adds
    /// to an empty curve would flatten the row to that value: a control whose first use destroys what
    /// it was showing. Materialising the ramp first makes the first edit mean what it looks like, and
    /// it costs nothing at all — `ResponseCurve.ramp(from: 0, to: 1)` is documented and tested
    /// **bit-exact** with the pass-through it replaces.
    static func materialised(_ curve: AnimationCurve) -> AnimationCurve {
        guard curve.isEmpty else { return curve }
        return ResponseCurve.ramp(from: 0, to: 1).curve
    }

    /// A key moved to where the finger is.
    ///
    /// Its frame is clamped between its neighbours and its value into `axis`. The value clamp is
    /// this control's own — `ResponseCurve` deliberately does not clamp its *output* (§6.1) and an
    /// overshooting handle is legitimate, but a **key** the artist cannot see is a key they cannot
    /// get back, which is the unreachable state `TimelineGraphBand.reachableY` exists to undo one
    /// surface over. Here the graph is a fixed square and clamping the key is the simpler answer.
    static func moving(frame: Int, to location: CGPoint, in curve: AnimationCurve,
                       side: CGFloat = side) -> AnimationCurve {
        guard let key = curve.key(atFrame: frame) else { return curve }
        let ordered = curve.keys.map(\.frame).sorted()
        guard let index = ordered.firstIndex(of: frame) else { return curve }
        let lower = index == 0 ? 0 : ordered[index - 1] + minimumFrameGap
        let upper = index == ordered.count - 1 ? Int(ResponseCurve.scale)
                                              : ordered[index + 1] - minimumFrameGap
        let target = Self.frame(atX: location.x, side: side)
        let destination = min(max(target, lower), max(lower, upper))
        let value = min(max(Self.value(atY: location.y, side: side), axis.lowerBound), axis.upperBound)

        var updated = curve
        updated.removeKey(atFrame: frame)
        var moved = key
        moved.frame = destination
        moved.value = value
        updated.setKey(moved)
        return updated
    }

    /// A key added where the finger tapped. Refused where one already sits within the gap, which is
    /// `moving`'s collision rule reached by the other door.
    static func adding(at location: CGPoint, to curve: AnimationCurve,
                       side: CGFloat = side) -> AnimationCurve {
        var updated = materialised(curve)
        let frame = Self.frame(atX: location.x, side: side)
        guard !updated.keys.contains(where: { abs($0.frame - frame) < minimumFrameGap }) else { return updated }
        let value = min(max(Self.value(atY: location.y, side: side), axis.lowerBound), axis.upperBound)
        updated.setKey(AnimationCurve.Key(frame: frame, value: value, tangentMode: .autoClamped))
        return updated
    }

    /// A key removed — and a curve left with fewer than two keys is **emptied**, not left holding
    /// one.
    ///
    /// One key is a constant, so a row whose curve had been reduced to it would contribute a flat
    /// value at every reading with nothing on screen to say why. Empty is the identity (§6.1), which
    /// is the state the artist plainly means by taking the curve apart.
    static func removing(frame: Int, from curve: AnimationCurve) -> AnimationCurve {
        var updated = curve
        updated.removeKey(atFrame: frame)
        if updated.keys.count < 2 { updated = AnimationCurve(step: curve.step) }
        return updated
    }

    /// The polyline, one sample per point of width — `CurveEditor.curvePath`'s density, so the
    /// preview can never be smoother than what the row actually evaluates.
    static func samples(of curve: ResponseCurve, side: CGFloat = side) -> [CGPoint] {
        let steps = max(Int(side), 2)
        return (0...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: t * side, y: y(ofValue: Double(curve.value(at: t)), side: side))
        }
    }
}
