import CoreGraphics
import Foundation
import UIKit

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
/// tabs: our model has `density`, a chain of modules and a gain per input and Procreate has none of
/// those, and it has Wet Mix and Bleed and we have neither.
///
/// **This list is the answer to §7's *"parameters with no UI at all today"***: scatter, the angle's
/// three contributions, `hardness`, `density`, `blendMode` and the three HSB shifts were all
/// unreachable from any screen before stage 10, and every one of them is here. §2.30 made `scatter`
/// two rows here as it made it two outputs: the artist reaches the frayed edge and the uneven
/// spacing separately, which is the whole of that ruling. **`density`'s own λ was on this list until
/// §2.32** and is not a property of the output any more — it belongs to whichever randomiser the
/// artist puts on the chain, beside that randomiser's octaves and falloff.
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
            entry(.scatterAcross, "Scatter Across",
                  "How far a dab may land to either side of the path, in brush widths. Frays the edge of the stroke; the gaps between dabs stay even."),
            entry(.scatterAlong, "Scatter Along",
                  "How far a dab may land forward or back along the path, in brush widths. Widens nothing — it bunches and gaps the dabs instead."),
            // **§2.32 rewrote this sentence and it had to be rewritten.** It said *"the chance a dab
            // is stamped at all. Below 1 the line breaks up"*, which was §2.18's meaning and is now
            // false in the direction that matters: below the gate **nothing** is stamped. Left
            // alone it sat two lines above the gate sentence and contradicted it — the state §7.2
            // calls worse than never having said anything.
            entry(.density, "Density",
                  "The level a dab's gate is decided by, not a probability. It is stamped when this reaches 50%; a dropout is a base near that with a Randomiser input swinging across it.")
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
        case .scatterAcross: return \Brush.dab.scatterAcross
        case .scatterAlong: return \Brush.dab.scatterAlong
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
        case .scatterAcross, .scatterAlong: return 0...2
        case .density: return 0...1
        case .hardness: return 0...1
        case .angle: return 0...1
        case .hue: return -0.5...0.5
        case .saturation, .brightness: return -1...1
        }
    }

    /// How the base and a row's gain are written out. Percent for the `0…1` fractions, turns for
    /// the two angular ones, plain for the rest.
    func format(_ value: Double) -> String {
        switch self {
        case .size, .flow, .density, .hardness, .spacing, .saturation, .brightness:
            return "\(Int((value * 100).rounded()))%"
        case .angle, .hue:
            return String(format: "%.3f turns", value)
        case .scatterAcross, .scatterAlong:
            return String(format: "%.2f widths", value)
        }
    }

    /// **`format` read backwards** — BRUSH.md §2.33's typed field, which is what lets a gain go past
    /// the end of its slider.
    ///
    /// The owner: *"making gain a slider means having it bounded, which I think may limit freedom, so
    /// make it a slider, but also a place where you can type out the percent past 100%."* So this
    /// **must not clamp**, and it deliberately does not: §6 rules a row's amount signed and
    /// unclamped, and a slider that silently pinned a typed 150% would be the control the ask exists
    /// to remove. A negative is ordinary rather than an edge case — it is how a sensor is made to
    /// *reduce* a parameter.
    ///
    /// The unit suffix is accepted and ignored, so the pill round-trips its own text; anything that
    /// is not a number at all answers nil and the field puts back what was there.
    func parse(_ text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        for suffix in ["%", "turns", "turn", "widths", "width"] where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard let value = Double(trimmed), value.isFinite else { return nil }
        switch self {
        case .size, .flow, .density, .hardness, .spacing, .saturation, .brightness:
            return value / 100
        case .angle, .hue, .scatterAcross, .scatterAlong:
            return value
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

    /// **The channel is deliberately garbage here.** `BrushModulations` rewrites it from the chain's
    /// position on construction and on decode, in every position, so anything minted outside that
    /// type is overwritten before it can be read — which is §6.2's *"derived rather than stored"*
    /// doing its job rather than a shortcut. A hand-picked channel would be the stale-field defect
    /// §6.2 exists to make unrepresentable.
    func input(_ randomiser: BrushRandomiser = BrushEditorDefaults.randomiser) -> BrushInput {
        switch self {
        case .pressure: return .pressure
        case .tiltAngle: return .tiltAngle
        case .tiltDirection: return .tiltDirection
        case .direction: return .direction
        case .taper: return .taper
        case .velocity: return .velocity
        case .random: return .random(.modulation(.size, row: 0), randomiser)
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

    /// The authored half of a `.random` input — λ, §2.28's octave count and its falloff — and nil for
    /// every sensor, which is what makes "show the randomiser's controls only where they mean
    /// something" a property of the value rather than a rule in the view.
    var randomiser: BrushRandomiser? {
        guard case .random(_, let randomiser) = self else { return nil }
        return randomiser
    }
}

// MARK: - The modules, as a menu can offer them

/// **What the *Add module* menu lists** — BRUSH.md §2.28's three modules, over `BrushModule`'s two
/// cases.
///
/// The third is the second with a random input: `.scale(.random(…))` **is** the randomiser, because
/// `.random` is a `BrushInput` (§13's *"a pure randomiser is an input, not a module"*). Storing a
/// third case would be two spellings of one behaviour and two channel derivations to keep in step;
/// offering two menu entries would hide the randomiser behind a sensor picker an artist has no reason
/// to look in. So the vocabulary is three and the storage is two, and this type is the join.
enum BrushModuleKind: String, CaseIterable, Identifiable {
    case curveRamp
    case randomiser
    case scale

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curveRamp: return "Curve Ramp"
        case .randomiser: return "Randomiser"
        case .scale: return "Scale by Sensor"
        }
    }

    /// What the module does to the value reaching it, in the artist's terms — shown under the module
    /// so a chain reads as a sentence rather than as three boxes.
    var detail: String {
        switch self {
        case .curveRamp:
            return "Remaps the value running through the chain. Put one after a randomiser to reshape the wobble's range."
        case .randomiser:
            return "Multiplies by a random value that varies along the stroke. Octaves add finer detail on top. It can only take away — the input's Gain is what makes a chain bigger."
        case .scale:
            return "Multiplies by another sensor's reading, shaped by its own curve. It can only take away — the input's Gain is what makes a chain bigger."
        }
    }

    /// A fresh module of this kind, at the defaults a first use should have.
    var module: BrushModule {
        switch self {
        case .curveRamp: return .curveRamp(ResponseCurve.ramp(from: 0, to: 1))
        case .randomiser: return .scale(.random(.modulation(.size, row: 0),
                                                BrushEditorDefaults.randomiser),
                                        .linear, BrushModule.fullScale)
        case .scale: return .scale(.pressure, .linear, BrushModule.fullScale)
        }
    }
}

extension BrushModule {
    /// Which menu entry this module came from. A `.scale` carrying a `.random` reads back as the
    /// randomiser, which is the one place the two-cases-three-kinds join has to be exact.
    var kind: BrushModuleKind {
        switch self {
        case .curveRamp: return .curveRamp
        case .scale(let input, _, _): return input.randomiser == nil ? .scale : .randomiser
        }
    }

    /// The randomiser this module draws through, or nil — nil for a curve ramp and for a scale by an
    /// ordinary sensor.
    var randomiser: BrushRandomiser? {
        guard case .scale(let input, _, _) = self else { return nil }
        return input.randomiser
    }

    /// **§2.29's own curve** — the one a `.scale` shapes *its own sensor's reading* with, which is a
    /// different thing from a `.curveRamp`'s shaping of the value running through the chain. Nil for
    /// a ramp, because a ramp *is* its curve and the editor binds to it by position instead.
    /// **§2.33's amount on a scale** — how much of this module's attenuation applies, `0…1`. Nil for
    /// a ramp, which reads no sensor and so has nothing to mix towards.
    var scaleAmount: Double? {
        guard case .scale(_, _, let amount) = self else { return nil }
        return amount
    }

    var sensorCurve: ResponseCurve? {
        guard case .scale(_, let curve, _) = self else { return nil }
        return curve
    }
}

// MARK: - BRUSH.md §2.26 — the two browsable collections, as a picker can list them

/// One thing a tip or texture picker offers: the bitmap, and what to call it.
///
/// `id` is what an accessibility identifier is built from, so a UI test names an asset the way the
/// model does — and it is the **file name** for an import rather than the display name, because the
/// display name is a position in a sorted list and the file name is the identity.
struct BrushAssetItem: Identifiable, Hashable {
    let ref: BrushTextureRef
    let name: String
    let id: String
}

/// **What is in each of §2.26's two collections, right now** — BRUSH.md §2.26, the owner: *"their dab
/// sprites should have the ability to be changed, as well as texture. For these two, it may be worth
/// having a library of textures and sprites to which new sprites can be added into."*
///
/// **It is a listing, not a store.** `BrushStorage` owns the root and its five verbs are the whole
/// file surface (§2.27); this asks `fileNames()` — the one of the five that had no caller until now —
/// and sorts the answer into the two collections `BrushAssetKind` names. There is no index file, no
/// second directory and no cache: the files *are* the collection, so a tip written by an import is in
/// the picker the next time it is opened with nothing to keep in step.
///
/// **The names are positional and the ids are not.** An imported bitmap is `custom-<uuid>.png`, which
/// is not a thing to show an artist, and nothing in the model carries a nicer one — a name would need
/// a text field at import time, which is a decision the owner has not made. So the display name is
/// "Imported *n*" over the sorted file names, which is stable while the file is there and shifts when
/// one is deleted; the **identifier** is the file name, which does not.
enum BrushAssetLibrary {

    static func items(in kind: BrushAssetKind, storage: BrushStorage = .shared) -> [BrushAssetItem] {
        let builtIns = BuiltInBrushTexture.all(in: kind == .tip ? .tip : .texture).map {
            BrushAssetItem(ref: .builtIn($0), name: $0.displayName, id: $0.rawValue)
        }
        let imported = storage.fileNames().filter(kind.owns).sorted()
        return builtIns + imported.enumerated().map { index, fileName in
            BrushAssetItem(ref: .imported(fileName: fileName),
                           name: "Imported \(index + 1)",
                           id: fileName)
        }
    }

    /// What a ref is called wherever one is shown outside a picker — the editor's own "Tip:" line.
    /// Falls back to the file name for an import the listing no longer holds, which is a brush whose
    /// picture the artist deleted: saying its name is more use than saying "unknown".
    static func name(of ref: BrushTextureRef, in kind: BrushAssetKind,
                     storage: BrushStorage = .shared) -> String {
        if let match = items(in: kind, storage: storage).first(where: { $0.ref == ref }) { return match.name }
        switch ref {
        case .builtIn(let builtIn): return builtIn.displayName
        case .imported(let fileName): return fileName
        }
    }

    /// **Adds a picture to a collection and answers the ref that resolves it** — §2.26's *"importing
    /// adds to a collection rather than to whichever brush happens to be open"*.
    ///
    /// Two normalisations, one per collection, and `BrushTextureImport` carries why they cannot be
    /// the same one: a tip is letterboxed with a transparent border and a tiled sheet cannot be.
    static func importImage(_ image: UIImage, into kind: BrushAssetKind) throws -> BrushTextureRef {
        switch kind {
        case .tip:
            guard case .stamp(let ref) = try BrushTipImport.importTip(from: image) else {
                throw BrushTipImport.Failure.unreadableImage
            }
            return ref
        case .texture:
            return try BrushTextureImport.importTexture(from: image)
        }
    }
}

// MARK: - BRUSH.md §7.2 — the pad's magnification

/// **How much of the canvas the editor's pad shows, and what that does and does not scale** —
/// BRUSH.md §7.2's second and third owner asks: *"zoomed in by default, because the details that
/// distinguish two brushes are granular"*, and *"a toggle to real size, because zoom lies about what
/// a brush looks like in use."*
///
/// **The one thing this must not do is scale the brush.** A brush drawn at 3× size is a *different
/// brush*, not a magnified one, and the pad exists to tell the truth about what a brush looks like.
/// So every function here moves the *view*: the pad's context keeps its pixel dimensions and takes a
/// larger scale factor, which shrinks the canvas extent it covers. The size handed to
/// `BrushStamper.stampStroke` is the artist's own number in canvas points at every zoom, and there is
/// deliberately no function here that takes one.
///
/// It lives outside `BrushScratchPadView` for this file's stated reason — a rule written in a `View`
/// is a rule no fast-tier test can reach — and `makeContext` is here rather than in the pad so the
/// test builds the *same* context the app draws into rather than a lookalike.
enum BrushPadZoom {

    /// **Zoomed in by default.** 3 rather than something larger because the pad is also where an
    /// artist judges *spacing* and *scatter*, which are read from a length of stroke rather than from
    /// one dab: at 3× a 330-point pad still shows about 110 canvas points of stroke, and past that a
    /// brush's line stops being a line.
    static let standard: CGFloat = 3
    /// 1 canvas point to 1 view point — the same claim the Size slider's real-size stamp preview
    /// makes, which is why it is named rather than written as a literal.
    static let realSize: CGFloat = 1

    static func isRealSize(_ zoom: CGFloat) -> Bool { zoom == realSize }

    /// **How many finished strokes the pad keeps** — BRUSH.md §2.31's *"if a pad full of strokes
    /// cannot keep up, the honest answer is a cap on how many it keeps, not a quietly stale
    /// preview."*
    ///
    /// Since §2.31 every stroke on the pad is re-walked from the draft on every edit, so this number
    /// times one stroke's walk is what one serviced frame of a slider drag costs.
    ///
    /// **MEASURED by `DabCostBench`' `testWhatThePadsRewalkCostsAtItsStrokeCap`, on the simulator** —
    /// one pad-crossing stroke costs **19 ms** (Grunge, spacing 0.30), **27 ms** (Round Hard),
    /// **34 ms** (Painterly) and **44 ms** (Chalk, the dearest shipped walk).
    /// The cost tracks the dab count and **not** §2.25's paper, which was the expected culprit and is
    /// not: Grunge lays a canvas-anchored sheet and is the cheapest of the four.
    ///
    /// **That is also the number the artist pays, which this comment used to deny.** It read Debug at
    /// 62× Release — CLAUDE.md's figure for the alpha-mask path — and called the measurement a worst
    /// case pending a Release run that could not then be built. The Release run was taken 2026-09-05
    /// and **this path is 1.01× Debug**: MEASURED, three samples each way alternated on a warm
    /// device, `PADREWALK` 44.05 / 44.08 / 43.05 ms in Debug against 42.20 / 42.48 / 44.63 ms in
    /// Release. The dab *walk* alone is ~25× faster in Release, but a pad stroke is dominated by the
    /// CoreGraphics compositing underneath it, and framework code does not notice the configuration.
    /// PERFORMANCE.md §12 has the table and the reason.
    ///
    /// **Eight, and the arithmetic is the reason.** At the measured Debug cost a full pad is
    /// 0.14–0.34 s of main-thread work on one serviced frame, and a realistic pad — the two or three
    /// strokes an artist draws before reaching for a slider — is 0.04–0.13 s. Twelve would put the
    /// worst case past half a second even in Debug, and eight is still more strokes than the pad has
    /// room to show at 3× before the newest one lands in a mess of older ones. The **oldest** goes,
    /// because the newest is the one being judged.
    ///
    /// It lives here rather than on the pad for this file's own stated reason: a rule written inside
    /// a `View` is a rule no fast-tier test can reach, and the measurement above is a fast-tier test.
    static let maximumStrokes = 8

    /// The toggle. Two positions rather than a slider: §7.2 asks for *"a toggle to real size"*, and a
    /// continuous zoom would leave the artist unable to say whether what they are looking at is life
    /// size — which is the whole of what the control is for.
    static func toggled(_ zoom: CGFloat) -> CGFloat { isRealSize(zoom) ? standard : realSize }

    /// What the button says. The current state rather than what tapping does: a control whose label
    /// names its *destination* reads as a claim about what is on screen, and this one is beside the
    /// thing it describes.
    static func label(_ zoom: CGFloat) -> String {
        isRealSize(zoom) ? "Real size" : "Zoomed \(Int(zoom.rounded()))×"
    }

    /// The canvas extent a pad of `viewSize` shows, in canvas points.
    static func canvasSize(of viewSize: CGSize, at zoom: CGFloat) -> CGSize {
        CGSize(width: viewSize.width / max(zoom, 0.01), height: viewSize.height / max(zoom, 0.01))
    }

    /// A touch, in canvas points. Getting this backwards draws the stroke a third of the way to the
    /// finger, which looks like a broken hit test rather than like a wrong transform.
    static func canvasPoint(_ viewPoint: CGPoint, at zoom: CGFloat) -> CGPoint {
        CGPoint(x: viewPoint.x / max(zoom, 0.01), y: viewPoint.y / max(zoom, 0.01))
    }

    /// **The pad's bitmap: `viewSize · screenScale` pixels, whose user space is canvas points.**
    ///
    /// Flipped to UIKit's orientation, because the samples come from `touch.location(in:)` and a bare
    /// `CGBitmapContext` is y-up from the bottom left. `BrushPreview` needs no such flip — a
    /// `UIGraphicsImageRenderer` hands out a context that already has one — and getting it wrong here
    /// would draw every stroke as its own vertical mirror.
    static func makeContext(viewSize: CGSize, screenScale: CGFloat, zoom: CGFloat) -> CGContext? {
        let pixelWidth = Int((viewSize.width * screenScale).rounded())
        let pixelHeight = Int((viewSize.height * screenScale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let scale = screenScale * max(zoom, 0.01)
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        return context
    }
}

// MARK: - BRUSH.md §7.1 — what "create manually" makes

extension Brush {
    /// **A brush minted from the engine's neutral defaults** — §7.1's first arm of the `+`.
    ///
    /// The owner: *"the create brush right now makes you import a brush, but this library feature
    /// opens up the possibility of just taking you straight to the edit menu of a default brush, and
    /// you being able to fully customize it, so new brush should be two options: create manually, and
    /// import brush."*
    ///
    /// So it is deliberately **not** a copy of a shipped preset. `BrushDabSettings.default` is every
    /// output at §6's neutral, `BrushStrokeSettings.default` is the gesture untouched, the tip is
    /// `.round`, and `modulations` is **empty** — no `size ← pressure`, no `flow ← pressure`. What the
    /// artist gets is the engine with nothing said about it, which is the only starting point the
    /// editor can honestly claim to be "fully customizable" from: every row on the screen then reads
    /// as something they added.
    ///
    /// **`size` is the one number with no neutral to take.** It is the stroke's own diameter rather
    /// than a dab parameter (see `Brush`), so `BrushDabSettings` has nothing to say about it and a
    /// number has to be picked. 12 points is legible on the canvas at the default zoom and small
    /// enough that a first stroke shows the tip rather than a band.
    static func manuallyCreated(named name: String) -> Brush {
        Brush(name: name, tip: .round, size: manualStartingSize, opacity: 1,
              dab: .default, stroke: .default, modulations: BrushModulations())
    }

    static let manualStartingSize: CGFloat = 12
    /// What the first manually made brush is called; later ones take a numeric suffix from
    /// `BrushLibraryStore`, which is the only thing that knows what is taken.
    static let manualBaseName = "New Brush"
}

enum BrushEditorDefaults {
    /// What a fresh randomiser is, in brush widths (§2.17) at one octave (§2.28). Roughly the
    /// `density` row's own default λ, so a first randomiser reads as a wobble rather than as per-dab
    /// hash noise — and one octave, so adding one changes the amplitude and nothing else until the
    /// artist asks for scales.
    static let randomiser = BrushRandomiser(wavelength: 3.5)
    /// What a fresh chain's amount is. Non-zero, because a chain added at 0 does nothing and reads as
    /// a control that did not work — CLAUDE.md's "a refusal with no notice", reached through a
    /// default.
    static let amount: Double = 0.5
}

// MARK: - What the chain still cannot say

/// **Where §2.24's chain and §6's storage still differ.** BRUSH.md §13 carries the same list in
/// prose; this is the copy the screen reads, so the sentence an artist is shown and the sentence the
/// document records cannot drift.
///
/// **It was four entries and it is one.** §2.28 closed the other three by making a modulation an
/// input and an ordered list of modules: the order is the artist's, a chain may carry as many curve
/// ramps as it likes, and it may carry as many randomisers as it likes. Those three sentences were on
/// the screen until 2026-09-05 and are **deleted rather than reworded** — a limit the engine no
/// longer has, still printed beside the control that disproves it, is worse than never having said
/// it.
///
/// The survivor is a fact about the *matrix* rather than about a chain, and closing it is a change to
/// how outputs are summed rather than to how one chain is evaluated.
enum BrushChainLimit: String, CaseIterable, Identifiable {
    /// **Several chains on one output are summed, not chained.** The owner's *"for each output there
    /// can only be one input for now"* is true of everything the shipped set carries, and the storage
    /// does not enforce it: §8.4's rough nib is several `random` rows at different λ on one output —
    /// which §2.28's octaves now express inside a single chain, so this is the shape an artist
    /// reaches for less often than they did.
    case severalChainsPerOutputAreSummed

    var id: String { rawValue }

    var explanation: String {
        switch self {
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
