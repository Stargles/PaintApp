import UIKit

/// What the onion-skin layer should display. `OnionSkinSettingsSource` answers "the neighbouring
/// drawings/frames on the current layer, as the onion-skin panel is configured"; interpolate mode
/// answers "the two reference keyframes". Kept as a protocol because the two answer the same
/// question from completely different inputs.
protocol OnionSkinSource {
    func frames(for manager: CanvasManager) -> [OnionSkinFrame]
}

/// One image to composite into the onion-skin layer.
struct OnionSkinFrame {
    let image: UIImage
    let opacity: CGFloat
    /// nil = untinted; `.tinted` colouring and interpolate mode both supply one.
    let tint: UIColor?

    /// Flattens several frames into the one image the onion-skin view displays, each at its own
    /// opacity and tint. Nil for an empty list or an unknown canvas size.
    ///
    /// Opacity is baked in here rather than left to the view's `alpha`, because a view has one alpha
    /// and these frames do not: two references at 0.3 shown through a 0.3 view would come out at
    /// 0.09 each.
    ///
    /// A tint is applied with `.sourceIn` over the frame's own silhouette, so it recolours the ink
    /// and leaves the transparent surround alone — which is the difference between "the past keyframe,
    /// in blue" and "a blue rectangle".
    ///
    /// **`size` is the size of the composite, not necessarily of the canvas.** Every frame is drawn
    /// into `bounds`, so handing this a smaller size downsamples the whole stack in one blit per
    /// frame rather than rendering at native resolution and scaling afterwards — see
    /// `OnionSkinBudget`, which is what decides that size, and why an onion skin is allowed to be
    /// softer than the artwork.
    static func composite(_ frames: [OnionSkinFrame], size: CGSize?) -> UIImage? {
        guard let size, size.width > 0, size.height > 0, !frames.isEmpty else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            for frame in frames {
                // A skin at zero opacity is not merely invisible, it is a full canvas-sized draw
                // that produces nothing. Dropped here rather than at every call site so no caller
                // can forget: the per-slot sliders make "one of the ten is at zero" ordinary.
                guard frame.opacity > 0 else { continue }
                guard let tint = frame.tint else {
                    frame.image.draw(in: bounds, blendMode: .normal, alpha: frame.opacity)
                    continue
                }
                ctx.cgContext.saveGState()
                ctx.cgContext.setAlpha(frame.opacity)
                ctx.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
                frame.image.draw(in: bounds)
                tint.setFill()
                ctx.cgContext.setBlendMode(.sourceIn)
                ctx.cgContext.fill(bounds)
                ctx.cgContext.endTransparencyLayer()
                ctx.cgContext.restoreGState()
            }
        }
    }
}

// MARK: - The clip

/// What clips the onion-skin view, and the whole of the owner's 2026-09-06 ruling on placement.
///
/// **Both placements draw on top of the composite; Behind differs only by a mask.** The owner:
/// *"the onion skin always renders on top of the compositor… For the 'Behind' option, it is still
/// rendered on top of the compositor, but then uses the inverse of the current drawing layer as an
/// alpha mask."* So there is no z-order for "behind" to express and none is expressed — the view is
/// fronted over every layer host either way, and the ghost never picks up a blend mode or an
/// adjustment layer's grade meant for artwork.
///
/// **The paper is untouched by this and that is the point** (EFFECT_BACKDROP.md §2.1): the paper is a
/// `UIView` painted *behind* the composite, so a skin drawn above the composite sits above the paper
/// too, and a `.value` layer grading the paper cannot reach it.
///
/// **A mask rather than a cut baked into `OnionSkinFrame.composite`.** Both would put the same pixels
/// on screen, and the composite already has a render to add one `.destinationOut` draw to — but the
/// current layer's ink moves on every stroke, so folding it into the composite would rebuild the
/// ghost stack each time the artist drew. That is the expensive product: MEASURED on the owner's iPad
/// at 237 ms for ten skins at 2048x1024 Full (`OnionSkinBudget`), against the two draws this costs
/// whatever the skin count. The composite's cache stays keyed on the neighbours, which is what it is
/// about.
enum OnionSkinClip {

    /// The image `CALayer.mask` gets on the onion-skin view — nil for no clip at all.
    ///
    /// - `layerMask` is §6.4's coverage, the clip the compositor applies to the current layer. It
    ///   applies to the ghost under both placements, unchanged: a ghost outside the current layer's
    ///   mask is the BUGS.md entry "The onion skin renders unmasked".
    /// - `ink` is what Behind takes back out. Nil is In Front and is also "Behind over a drawing with
    ///   nothing on it", which are the same picture and rightly the same code path.
    ///
    /// **The placement setting is not read here**, deliberately: `CanvasManager.onionSkinInkToSubtract`
    /// is the one place in the app that consults it, so there is a single answer to "does this pass
    /// subtract anything" and a test can hold it. This function combines whatever it is handed.
    ///
    /// **An empty current layer means a fully visible skin**, which is the correct answer and the one
    /// worth stating: with no ink there is nothing for the ghost to be behind, so Behind and In Front
    /// look identical on a blank drawing.
    ///
    /// The combined image is built at `size` — the *skin's* resolution, not the canvas's. The thing
    /// being masked is already soft at that size (`OnionSkinBudget` argues why a ghost may be), so a
    /// cut edge sharper than the ghost it cuts would buy nothing and cost the square of the ratio.
    static func mask(layerMask: CGImage?, subtracting ink: UIImage?, size: CGSize) -> CGImage? {
        guard let ink, size.width > 0, size.height > 0 else { return layerMask }

        let bounds = CGRect(origin: .zero, size: size)
        let combined = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat())
            .image { ctx in
                // Everything is shown to begin with — either §6.4's coverage, or a fully opaque
                // field when nothing clips this layer. White because `makeMaskImage` is white
                // premultiplied by coverage and a mask that reads correctly by luminance as well as
                // by alpha is cheaper to look at in a debugger than one that does not.
                if let layerMask {
                    UIImage(cgImage: layerMask).draw(in: bounds)
                } else {
                    UIColor.white.setFill()
                    ctx.cgContext.fill(bounds)
                }
                // …and then the artist's own ink is taken back out of it. `.destinationOut` is
                // dst x (1 - src alpha), which *is* "the inverse of the current drawing layer as an
                // alpha mask" — no separate inversion pass, and it composes with the coverage above
                // by construction rather than by a second multiply.
                ink.draw(in: bounds, blendMode: .destinationOut, alpha: 1)
            }
        return combined.cgImage
    }
}

extension CanvasManager {

    /// The current drawing layer's own content at the playhead, at `size` — what Behind subtracts
    /// from the ghost. Nil when there is nothing to subtract, which is the common case on a fresh
    /// frame and is why this answers before rasterizing anything.
    ///
    /// **The only reader of `onionSkin.placement` outside the panel that sets it.** In Front leaves
    /// here immediately, so `updateOnionSkin` makes no decision of its own and there is one place to
    /// hold to the ruling rather than a condition in a view coordinate no headless test can reach.
    ///
    /// **`OnionSkinRasterCache` rather than a render of the layer host**, which is the cheapest
    /// source that forces no extra work: the ghost's own sources go through that cache at this exact
    /// size, so a Behind clip is one more entry in a store that is already sized, budgeted and
    /// evicted for canvas-reduced flattens — and at Full it hands straight to the compositor's shared
    /// memo, which the composite the artist is looking at has already filled. Snapshotting
    /// `LayerHostView` would be a genuinely extra canvas-sized render, off a view whose contents are
    /// mid-flight during a stroke.
    ///
    /// **Effective visibility, not `isVisible`** — a layer hidden by an enclosing folder draws no ink,
    /// and a ghost cut out by ink nobody can see is the surprise this guard exists to prevent.
    ///
    /// **A `.value` layer subtracts nothing.** It has no cel to rasterize (`hasNoDrawingSurface`), so
    /// an adjustment layer or a flat colour selected as the current layer leaves the skin whole
    /// rather than erasing all of it — which is what a canvas-filling flat colour would otherwise do.
    /// It falls out of the cel lookup below; the guard is here so it is a decision rather than an
    /// accident.
    ///
    /// **Layer opacity is deliberately not folded in.** The ruling's stated purpose is *"giving the
    /// animator a clear view at their art"*, and a proportional cut puts the ghost back under
    /// half-opacity ink, which is the muddle Behind exists to remove. Full cut wherever there is ink.
    ///
    /// Not `@MainActor`, matching `OnionSkinSettingsSource.frames(for:)` next to it: everything it
    /// reads is ordinary document state and the only caller is a SwiftUI pass.
    func onionSkinInkToSubtract(at size: CGSize) -> UIImage? {
        guard onionSkin.placement == .behind else { return nil }
        guard let canvasSize, layers.indices.contains(currentLayerIndex) else { return nil }
        let layer = layers[currentLayerIndex]
        guard layer.kind != .value, isLayerEffectivelyVisible(currentLayerIndex) else { return nil }
        guard let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layer.cels.indices.contains(celIndex) else { return nil }
        let cel = layer.cels[celIndex]
        // Asked in `OnionSkinSettingsSource.frames`'s order and for its reason: `isCertainlyBlank`
        // answers about *stored* tiers, so a derived in-between reports blank while showing a whole
        // drawing and would be skipped by a check made first.
        //
        // No `inheriting:` pose, which is `OnionSkinSettingsSource`'s convention rather than a
        // decision taken here: nothing in this subsystem poses a skin by an enclosing transformation
        // layer, and `OnionSkinRasterCache` has no `pose` argument to hand a raster cel through. So a
        // current layer moved by a container pose is cut where its ink rests, not where it is drawn.
        // Fixing it is one field on that cache plus one on this call, and it belongs to whichever
        // pass gives the *ghosts* their poses — cutting by a rule the skins themselves do not follow
        // would be worse than the gap.
        let derived = derivedCelContent(for: cel, atFrame: currentFrame)
        guard derived != nil || !cel.isCertainlyBlank else { return nil }
        return OnionSkinRasterCache.image(for: cel, canvasSize: canvasSize, at: size, derived: derived)
    }
}

// MARK: - Settings

/// Everything the onion-skin panel configures, as one value.
///
/// A value type rather than a dozen `@Published` properties on `CanvasManager` for two reasons that
/// both matter: the render path needs to compare "the settings that produced the picture on screen"
/// against "the settings now" in one `==` (see `Coordinator.OnionSkinKey`), and every decision this
/// carries is then testable without a view or a manager.
///
/// **Not persisted.** `isOnionSkinEnabled`/`onionSkinOpacity` were not in the project manifest
/// either, and onion skin is a way of looking at a drawing rather than part of it. Adding it to
/// `ProjectManifest` later is additive and needs nothing here to change.
struct OnionSkinSettings: Equatable {

    /// What "one step away" counts, and the distinction is real in this model rather than cosmetic —
    /// see `OnionSkinPlanner.resolvedCelIndices` for the arithmetic.
    ///
    /// - `drawings`: step by *cel*. One cel is one drawing however many frames it is exposed for, so
    ///   the previous drawing is the previous block on the track no matter how long the current one
    ///   is held. This is what you drew.
    /// - `frames`: step by *timeline frame*, then resolve whichever cel covers that frame. A drawing
    ///   held for five frames is therefore five steps away from the one after it, and an empty frame
    ///   is an empty skin. This is what plays back.
    enum Neighbourhood: String, CaseIterable, Identifiable {
        case drawings, frames
        var id: String { rawValue }
        var title: String { self == .drawings ? "Drawings" : "Frames" }
    }

    /// Where the skins composite relative to the drawing being worked on.
    enum Placement: String, CaseIterable, Identifiable {
        case behind, inFront
        var id: String { rawValue }
        var title: String { self == .behind ? "Behind" : "In Front" }
    }

    /// Whether a skin keeps its own colours or is recoloured to the side's tint.
    enum Colouring: String, CaseIterable, Identifiable {
        case tinted, originalColors
        var id: String { rawValue }
        var title: String { self == .tinted ? "Tinted" : "Original Colors" }
    }

    /// How sharp the skins are, as a fraction of the canvas — the owner's own vocabulary
    /// (2026-08-17: "default half resolution, option to make it full or quarter").
    ///
    /// **A fraction alone would be wrong on a small canvas, and `OnionSkinBudget` is where that is
    /// fixed** rather than here: the readability cliff measured at 512 px is an *absolute* size and
    /// does not scale with the document, so Half on a 1024² canvas would land at 512² and hand the
    /// artist a ghost they cannot read, at the default setting, with nothing to explain why. The
    /// fraction is applied and then floored.
    ///
    /// **Eighth was considered and left out.** With the floor in place it collapses onto Quarter for
    /// every canvas at or below 3072², and on a 4096² one it buys 768² against Quarter's 1024² —
    /// 1.8x the speed for the edge of legibility. A fourth segment on an already-dense panel did not
    /// look worth that; it is three lines to add if the owner wants it.
    enum Resolution: String, CaseIterable, Identifiable {
        case full, half, quarter
        var id: String { rawValue }
        var fraction: CGFloat {
            switch self {
            case .full:    return 1
            case .half:    return 0.5
            case .quarter: return 0.25
            }
        }
        var title: String {
            switch self {
            case .full:    return "Full"
            case .half:    return "Half"
            case .quarter: return "Quarter"
            }
        }
    }

    /// Which side of the playhead a slot is on.
    enum Side: String, CaseIterable, Identifiable {
        case previous, next
        var id: String { rawValue }
        /// -1 for previous, +1 for next — the only place the direction is written down.
        var step: Int { self == .previous ? -1 : 1 }
    }

    /// **The cap, and it stayed at five on the strength of a measurement rather than by default.**
    ///
    /// Each skin is one more draw into the composite, so this is what the cost is linear in. At the
    /// resolution `OnionSkinBudget` now sets, and with its sources cached, ten skins rebuild in about
    /// 100 ms and the shipped default of one a side in under 10 — against 1302 ms and 190 ms
    /// respectively on the owner's iPad 9 before that work. A rebuild happens when the playhead moves
    /// to a different drawing, not while the artist is drawing (see `Coordinator.OnionSkinKey`), so
    /// ten skins is a visible hitch on a playhead move and nothing at all on a stroke.
    ///
    /// That is a cost worth *offering*: it is opt-in, it is the setting the reference app offers, and
    /// the artist who dials it to five is buying ten ghosts knowingly. Lowering this would take the
    /// feature away to fix a cost that is now proportionate. If the owner disagrees after feeling it
    /// on the device, this is the one constant to move.
    static let maxSkinsPerSide = 5

    var neighbourhood: Neighbourhood = .drawings
    /// **Behind by default**, on the owner's instruction (2026-08-17).
    var placement: Placement = .behind
    var previousCount: Int = 1
    var nextCount: Int = 1
    /// Wrap the skins around the layer's first and last drawing/frame, so a cycle can be judged
    /// against itself without copying the first drawings onto the end by hand.
    var loops: Bool = false
    var colouring: Colouring = .tinted
    /// **Half by default**, the owner's call (2026-08-17). A quality/speed dial: see `OnionSkinBudget`
    /// for what each option costs and for the floor that keeps the cheap ones readable.
    var resolution: Resolution = .half
    /// Red for what came before, green for what comes after — the panel's gradient bar draws these
    /// two, and both are configurable.
    var previousTint = CodableColor(red: 0.95, green: 0.26, blue: 0.21, alpha: 1)
    var nextTint = CodableColor(red: 0.30, green: 0.78, blue: 0.31, alpha: 1)

    /// **On by default**, the owner's emphasis. See `OnionSkinOpacityRamp` for exactly what it does.
    var isOpacityLinked: Bool = true

    /// The one number the linked ramp is scaled by: the opacity of the *nearest* skin on a side.
    ///
    /// 0.35 rather than 1 because an onion skin at full opacity is not a ghost, and because it keeps
    /// the shipped default — one previous skin at 0.3 — roughly where it was.
    var linkedLevel: Double = 0.35

    /// Per-slot opacities used **only while unlinked**, indexed by distance-1 (element 0 is the skin
    /// nearest the current drawing). Always `maxSkinsPerSide` long, so lowering the count and raising
    /// it again gives the artist their values back rather than a reset ramp.
    var freePreviousOpacities: [Double] = OnionSkinOpacityRamp
        .opacities(level: 0.35, count: OnionSkinSettings.maxSkinsPerSide)
    var freeNextOpacities: [Double] = OnionSkinOpacityRamp
        .opacities(level: 0.35, count: OnionSkinSettings.maxSkinsPerSide)

    func count(on side: Side) -> Int {
        side == .previous ? previousCount : nextCount
    }

    func tint(on side: Side) -> CodableColor {
        side == .previous ? previousTint : nextTint
    }

    /// The opacities actually shown on one side, nearest first — the ramp when linked, the artist's
    /// own values when not. `count(on:)` long.
    func opacities(on side: Side) -> [Double] {
        let n = max(0, min(count(on: side), Self.maxSkinsPerSide))
        guard n > 0 else { return [] }
        guard !isOpacityLinked else { return OnionSkinOpacityRamp.opacities(level: linkedLevel, count: n) }
        let free = side == .previous ? freePreviousOpacities : freeNextOpacities
        return (0..<n).map { $0 < free.count ? free[$0] : 0 }
    }

    /// What the artist just did to one slider, applied.
    ///
    /// **Linked**: `slot` (1-based, 1 = nearest) is put at `value` by rescaling the whole ramp, which
    /// moves every other slider on *both* sides — "all the opacity sliders behave linearly to each
    /// other", the owner's words, read as strongly as it can be read. **Unlinked**: only that slot on
    /// that side moves.
    mutating func setOpacity(_ value: Double, slot: Int, on side: Side) {
        let n = max(0, min(count(on: side), Self.maxSkinsPerSide))
        guard slot >= 1, slot <= n else { return }
        guard isOpacityLinked else {
            let clamped = min(max(value, 0), 1)
            if side == .previous {
                guard slot - 1 < freePreviousOpacities.count else { return }
                freePreviousOpacities[slot - 1] = clamped
            } else {
                guard slot - 1 < freeNextOpacities.count else { return }
                freeNextOpacities[slot - 1] = clamped
            }
            return
        }
        linkedLevel = OnionSkinOpacityRamp.level(settingSlot: slot, to: value, count: n)
    }

    /// Turning the link off freezes the ramp into the free values, so the sliders do not jump the
    /// instant they become independent. Turning it on takes the nearest previous slider as the new
    /// level, so the one the artist is most likely looking at is the one that stays put.
    mutating func setOpacityLinked(_ linked: Bool) {
        guard linked != isOpacityLinked else { return }
        if linked {
            let anchor = freePreviousOpacities.first ?? linkedLevel
            linkedLevel = min(max(anchor, 0), 1)
            isOpacityLinked = true
        } else {
            let previous = opacities(on: .previous)
            let next = opacities(on: .next)
            for i in previous.indices where i < freePreviousOpacities.count {
                freePreviousOpacities[i] = previous[i]
            }
            for i in next.indices where i < freeNextOpacities.count {
                freeNextOpacities[i] = next[i]
            }
            isOpacityLinked = false
        }
    }
}

// MARK: - Linked opacity

/// The maths behind "linked opacity", stated precisely because the owner singled it out.
///
/// Slots are numbered by **distance**: slot 1 is the skin nearest the current drawing, slot `n` the
/// furthest. A side showing `n` skins has a fixed *shape*
///
///     s(d) = (n + 1 - d) / n            d = 1 ... n
///
/// — a straight line from 1 at the nearest slot down to 1/n at the furthest, in equal steps. That is
/// "a linear ramp from the nearest skin to the furthest".
///
/// What is actually stored is one scalar, the **level** λ in 0...1, and the opacities are
///
///     o(d) = λ · s(d)
///
/// so the whole vector is one point on a ray through the origin. Dragging *any* slider rescales that
/// ray: putting slot k at v means λ = v / s(k), and every other slot moves to keep its ratio to the
/// dragged one exactly as it was. That is "moving one moves the others, linearly to each other".
///
/// Two consequences worth stating rather than discovering:
///
///  * **A drag to zero zeroes every slot**, on both sides. λ = 0 is a point on the ray like any
///    other, and this is what "linear" costs — there is no offset to preserve.
///  * **A far slider cannot be dragged above its own share of a full ramp.** λ is clamped at 1, so
///    slot k tops out at s(k): with five skins, slot 3 stops at 0.6, because going higher would need
///    the nearer slots above 1 and they are already full. It is the ramp being straight that says so.
///    Unlinking is the escape hatch, and that is what unlinking is *for*.
///
/// The shape is strictly positive at every slot on purpose — a ramp that reached 0 at the furthest
/// slot would make that slider unable to move the level at all (v / 0), so the furthest visible skin
/// sits at 1/n of the nearest rather than at nothing.
enum OnionSkinOpacityRamp {

    /// The normalised ramp for a side showing `count` skins, nearest first. Empty for `count <= 0`.
    static func shape(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return (1...count).map { Double(count + 1 - $0) / Double(count) }
    }

    /// The opacities a side shows at link level `level`, nearest first.
    static func opacities(level: Double, count: Int) -> [Double] {
        let clamped = min(max(level, 0), 1)
        return shape(count: count).map { clamped * $0 }
    }

    /// The level that puts slot `slot` (1-based) at `value`, clamped into 0...1.
    ///
    /// Out-of-range slots return the level unchanged in effect (clamped `value`), which only happens
    /// if a caller ignores `count`; `OnionSkinSettings.setOpacity` guards ahead of this.
    static func level(settingSlot slot: Int, to value: Double, count: Int) -> Double {
        let shape = shape(count: count)
        guard slot >= 1, slot <= shape.count, shape[slot - 1] > 0 else { return min(max(value, 0), 1) }
        return min(max(value / shape[slot - 1], 0), 1)
    }
}

// MARK: - Which cel goes in which slot

/// One cel's extent on the timeline — the only thing slot resolution needs to know about a cel, so
/// the arithmetic below can be tested against a stated timeline rather than against a document.
struct CelSpan: Equatable {
    var start: Int
    var length: Int
    var end: Int { start + length }
    func covers(_ frame: Int) -> Bool { frame >= start && frame < end }
}

/// Which cel each onion-skin slot shows, as pure index arithmetic.
///
/// **Nothing here is allowed to return the cel the playhead is in**, and that is the one hard rule
/// rather than an optimisation. Drawing the current cel underneath itself is invisible while the
/// layer's own pixels cover it and becomes visible the moment the layer is masked — the leak the
/// product owner found, recorded in BUGS.md, and the reason the old source stepped back from the
/// current cel's `startFrame` instead of from the playhead. Looping makes it easy to hit again: a
/// two-drawing cycle asked for three previous skins wraps straight back onto the current drawing.
enum OnionSkinPlanner {

    /// Cel indices for one side, nearest first, `count` long. `nil` where a slot has nothing to show.
    ///
    /// - `spans` must be in timeline order (`CanvasManager` keeps `Layer.cels` sorted by start frame).
    /// - `currentCelIndex` is nil when the playhead sits in a gap; the walk then starts from the
    ///   nearest cel on the relevant side rather than refusing, because "there is no drawing here
    ///   yet" is an ordinary place to stand and the neighbours are still worth seeing.
    ///
    /// Duplicates are permitted and deliberate: a cycle with two drawings, asked for three previous
    /// skins, shows the other drawing twice at two different opacities. That is a faint double
    /// exposure rather than an error, and suppressing it would make a slider that silently does
    /// nothing — which is the worse of the two.
    static func resolvedCelIndices(spans: [CelSpan],
                                   currentCelIndex: Int?,
                                   currentFrame: Int,
                                   neighbourhood: OnionSkinSettings.Neighbourhood,
                                   loops: Bool,
                                   side: OnionSkinSettings.Side,
                                   count: Int) -> [Int?] {
        guard count > 0 else { return [] }
        guard !spans.isEmpty else { return Array(repeating: nil, count: count) }
        let step = side.step

        switch neighbourhood {
        case .drawings:
            // Where the walk starts, and the offset is the whole of the off-by-one.
            //
            // Standing *on* a drawing, the anchor is that drawing and distance 1 is one step off it,
            // so `baseOffset` is 1. Standing in a *gap* there is no current drawing, so the anchor is
            // already the nearest drawing on this side and distance 1 *is* the anchor — `baseOffset`
            // 0. Both then read `anchor + step * (d - 1 + baseOffset)`.
            let anchor: Int
            let baseOffset: Int
            if let currentCelIndex {
                anchor = currentCelIndex
                baseOffset = 1
            } else if side == .previous {
                guard let last = spans.lastIndex(where: { $0.end <= currentFrame }) else {
                    return Array(repeating: nil, count: count)
                }
                anchor = last
                baseOffset = 0
            } else {
                guard let first = spans.firstIndex(where: { $0.start > currentFrame }) else {
                    return Array(repeating: nil, count: count)
                }
                anchor = first
                baseOffset = 0
            }
            return (1...count).map { d in
                let raw = anchor + step * (d - 1 + baseOffset)
                let index: Int?
                if loops {
                    index = positiveModulo(raw, spans.count)
                } else {
                    index = spans.indices.contains(raw) ? raw : nil
                }
                return index == currentCelIndex ? nil : index
            }

        case .frames:
            // The layer's own extent, which is what "wraps around the layer's first and last frame"
            // names. Empty leading/trailing gaps are not part of the cycle: a cycle that spent its
            // first three frames blank because the artist started drawing at frame 3 would otherwise
            // wrap through them.
            let low = spans.map(\.start).min() ?? 0
            let high = spans.map(\.end).max() ?? 0
            let span = high - low
            return (1...count).map { d in
                var frame = currentFrame + step * d
                if loops {
                    guard span > 0 else { return nil }
                    frame = low + positiveModulo(frame - low, span)
                }
                guard let index = spans.firstIndex(where: { $0.covers(frame) }) else { return nil }
                return index == currentCelIndex ? nil : index
            }
        }
    }

    /// `a mod n` with a non-negative result. Swift's `%` follows the sign of the dividend, so
    /// `-1 % 3` is -1 and a wrap written with it walks off the front of the array on the very first
    /// previous slot at index 0 — the exact off-by-one this whole feature invites.
    static func positiveModulo(_ a: Int, _ n: Int) -> Int {
        guard n > 0 else { return 0 }
        let r = a % n
        return r < 0 ? r + n : r
    }
}

// MARK: - Resolution and memory

/// **How big an onion skin is allowed to be, and it is a picture-quality decision rather than a
/// memory one.** That is why this is its own number and no longer a fraction of
/// `CompositorBudget.textureBudgetBytes`: how soft a ghost may be does not depend on how much RAM
/// the device has, and deriving it from the compositor's budget made it depend on exactly that.
///
/// ### What the measurements said, because the first design was wrong about it
///
/// The composite was sized to 2508² on a 4096² canvas, and on the owner's iPad 9 in Release ten
/// tinted skins cost **1302 ms**, one skin 190 ms. The obvious lever was to shrink the composite.
/// It is not enough, and `PerfBaselineTests.testOnionSkinCompositeCostIsBoundByDestinationOrBySourcePixels`
/// is what says so — ten skins, one 4096² source, four destinations:
///
/// | destination | cost | share of cost | share of pixels |
/// |---|---|---|---|
/// | 2508² | 1159 ms | 1.00 | 1.00 |
/// | 1254² | 494 ms | 0.43 | 0.25 |
/// | 1024² | 409 ms | 0.35 | 0.17 |
/// | 627² | 236 ms | 0.20 | 0.06 |
///
/// Cost falls far more slowly than pixels: at 627² the composite writes 6% of the pixels and still
/// pays 20% of the cost. **`CGContext.draw(in:)` samples the whole source however small the
/// destination is**, so shrinking the composite alone runs into a floor made of source reads. The
/// second half of that test isolates it — the same 1024² destination costs 338 ms from a 4096²
/// source and **92 ms from a 1024² one, 3.7x**.
///
/// So the fix is in two halves, and the second is the load-bearing one:
///
///  1. The composite is capped by `compositeSize(for:resolution:)` — the artist's chosen
///     fraction of the canvas, floored at a readable size.
///  2. **Its sources are reduced to that same size once per cel version** and held by
///     `OnionSkinRasterCache`, so a skin is drawn 1:1 instead of resampled from the full canvas on
///     every rebuild. Rebuilds after the first are the 92 ms column, not the 338 ms one.
///
/// ### Why 1024, in terms the owner can rule on
///
/// A skin is a *registration reference* — "where did the line go" — drawn under the artist's own
/// work at a third of full opacity, and it is the one thing in this app that does not have to be
/// sharp. 1024 is chosen against what the screen can show rather than against a byte count: a 4096²
/// canvas fitted to the iPad 9's 2160x1620 display is already resampled to about 1500 px by the
/// display itself, so a 1024 skin is upscaled 1.5x at fit zoom — softer than the artwork, in the
/// same ballpark. Zoomed to 1:1 it is 4x soft, which reads as a blurred band a few pixels wide
/// rather than a line: still enough to place the previous drawing, not enough to trace.
///
/// **The trade-off, stated plainly, and it was looked at rather than argued.** Lineart at 4096²
/// (strokes of 2 to 12 px, plus hatching at a 16 px pitch) was skinned at 4096, 2048, 1024, 768 and
/// 512 and the results compared:
///
///  * **1024 — chosen.** Every stroke width still reads, the hatching resolves into separate lines,
///    the curve is clean. Barely distinguishable from native at fit zoom.
///  * **768 — the edge.** Still legible; the hatching survives but its ends begin to alias.
///  * **512 — fails, visibly.** The hatching stops being lines at all and collapses into a stippled
///    moiré wash, and the 2 px stroke nearly vanishes. This is exactly "a skin so soft the artist
///    cannot see where the previous drawing's line went".
///
/// So 1024 sits one full step above the cliff rather than on it. Going lower buys draw time at the
/// rate of the square and spends the margin that keeps hatching and thin lineart readable; going
/// back up toward 2048 costs 4x the draw time for detail the display cannot show at fit zoom. It is
/// one constant, and the comparison above is reproducible by re-running the resolution sweep in
/// `PerfBaselineTests`.
enum OnionSkinBudget {

    /// **The floor, and it is the load-bearing number in this type.** The readability cliff found by
    /// the sweep is an *absolute* pixel size — 512 px is where hatching stopped being lines and
    /// became a moiré wash — and it does not scale with the document. So a fraction of the canvas is
    /// applied and then floored here: Half means "half, but never so small you cannot see the line".
    ///
    /// 768 rather than 1024 because 768 is what the sweep actually showed still legible (hatching
    /// survives, its ends begin to alias), and a floor should sit at the edge of acceptable rather
    /// than at the edge of comfortable — it exists to prevent the unreadable case, not to overrule
    /// an artist who asked for speed.
    ///
    /// The floor never scales a skin *up*: on a canvas smaller than this the skin is the canvas.
    static let readableFloorEdge: CGFloat = 768

    /// The size the composite is rendered at, and the size its sources are reduced to.
    ///
    /// | canvas | Full | Half | Quarter |
    /// |---|---|---|---|
    /// | 4096² | 4096² | 2048² | 1024² |
    /// | 2048² | 2048² | 1024² | 768² (floored) |
    /// | 1024² | 1024² | 768² (floored) | 768² (floored) |
    /// | 512² | 512² | 512² | 512² (never upscaled) |
    static func compositeSize(for canvasSize: CGSize,
                              resolution: OnionSkinSettings.Resolution) -> CGSize {
        compositeSize(for: canvasSize, fraction: resolution.fraction, floorEdge: readableFloorEdge)
    }

    /// The rule against a stated fraction and floor — the half a test pins, so the table above is
    /// checked rather than remembered.
    static func compositeSize(for canvasSize: CGSize, fraction: CGFloat, floorEdge: CGFloat) -> CGSize {
        let longest = max(canvasSize.width, canvasSize.height)
        guard longest > 0, fraction > 0 else { return canvasSize }
        // Apply the fraction, raise it to the floor, then refuse to exceed the canvas. The last clamp
        // is what stops the floor from magnifying a small document's skin above its own artwork,
        // which would be pure cost for no pixels.
        let wanted = min(longest, max(longest * fraction, floorEdge))
        guard wanted < longest else { return canvasSize }
        let scale = wanted / longest
        // Floored to whole pixels for `RenderResolution.renderSize`'s reason: the app's several
        // rounding sites do not agree, and a source one pixel wider than the buffer reading it is a
        // garbage edge rather than a soft one.
        return CGSize(width: max(1, (canvasSize.width * scale).rounded(.down)),
                      height: max(1, (canvasSize.height * scale).rounded(.down)))
    }

    /// **Bytes, not entries, and the resolution setting is what made that necessary.** At a fixed
    /// 1024 skin an entry was 4 MiB and counting them was a fine proxy; with Full on a 4096² document
    /// an entry is 64 MiB, and a count-based limit would happily hold 768 MiB on a 3 GB iPad. The
    /// ceiling is now a number of bytes and the entry count falls out of the size the artist chose.
    ///
    /// **64 MiB is the whole subsystem, composite included**, not just the sources. Budgeting the
    /// sources alone was the first version and it reported a *higher* ceiling at Half (80 MiB) than
    /// at Full (64 MiB), which is nonsense on its face — the composite has to come out of the same
    /// allowance as the things feeding it, or the total is whatever the arithmetic happens to give.
    ///
    /// 64 MiB is a third of the compositor's own budget on the owner's 3 GB iPad, and the onion skin
    /// is a reference the artist looks *through* — it should not be able to outweigh a third of the
    /// thing it is a reference to. Full resolution spends the whole of it on the composite and caches
    /// nothing, which is correct rather than a shortfall: at Full there is no reduction, so
    /// `OnionSkinRasterCache` hands back the compositor's own shared memo instead of a second copy.
    static let residentBudgetBytes = 64 * 1024 * 1024

    /// Never fewer than two sources, whatever the budget arithmetic says, so the shipped default of
    /// one skin either side always caches. A cache that holds nothing is worse than no cache: it pays
    /// the bookkeeping and delivers none of the hits.
    static let minimumSourceCacheEntries = 2

    /// How many reduced sources are held at `size`.
    ///
    /// **The window plus two, bounded by bytes.** The most skins that can be on screen at once is
    /// `maxSkinsPerSide` a side; a cache of exactly that size is full at all times, so stepping the
    /// playhead one frame brings one new cel in and evicts one — every move pays a miss, forever,
    /// even after the artist has been all the way round the cycle. Slack is what turns that into
    /// hits, and two is enough because a playhead moves one step at a time.
    static func sourceCacheLimit(entryBytes: Int) -> Int {
        let window = OnionSkinSettings.maxSkinsPerSide * 2 + 2
        guard entryBytes > 0 else { return window }
        // The composite is one entry's worth of the same budget, so it is subtracted before the
        // sources get their share — see `residentBudgetBytes`.
        let forSources = max(0, residentBudgetBytes - entryBytes)
        return max(minimumSourceCacheEntries, min(window, forSources / entryBytes))
    }

    /// Everything the onion skin can hold at once, in bytes: one composite plus a source cache
    /// bounded by `sourceCacheBudgetBytes`.
    ///
    /// **This is a ceiling, not a cost.** The cache only ever fills to the number of skins actually
    /// asked for, so the shipped default of one skin either side holds two sources and one composite.
    ///
    /// **At Full this cache holds nothing, and that is an accounting fact rather than a saving.** The
    /// sources are canvas-sized, so `OnionSkinRasterCache.image(for:canvasSize:at:)` hands the call
    /// straight to `PixelOps.rasterize` and the bytes land in the *compositor's* cache instead of
    /// this one. The work does not go away with them — see `cachedSourceCount` — so a Full setting
    /// costs no onion-skin memory and every bit of the source production.
    static func residentCeilingBytes(for canvasSize: CGSize,
                                     resolution: OnionSkinSettings.Resolution) -> Int {
        let size = compositeSize(for: canvasSize, resolution: resolution)
        let entry = Int(size.width.rounded()) * Int(size.height.rounded()) * 4
        let cached = size == canvasSize ? 0 : entry * sourceCacheLimit(entryBytes: entry)
        return entry + cached
    }

    // MARK: - What a rebuild will cost, for the panel to say out loud

    /// **Milliseconds per megapixel of composite, per skin.** Measured on the owner's iPad 9 (A13,
    /// 3 GB) in Release on 2026-08-18, by
    /// `PerfBaselineTests.testOnionSkinCostOfEachResolutionOption`.
    ///
    /// It is one constant rather than a table because the measurement says it can be: dividing each
    /// of the six reported figures by (composite megapixels x skins) gives 11.5 at ten skins and 9.2
    /// at two, and that holds across *both* canvases and all three options to within 3% —
    ///
    /// | canvas | option | 10 skins | ms / MP / skin |
    /// |---|---|---|---|
    /// | 2048x1024 | Full | 237.1 ms | 11.3 |
    /// | 2048x1024 | Half | 59.8 ms | 11.4 |
    /// | 2048x1024 | Quarter | 33.9 ms | 11.5 |
    /// | 4096x4096 | Full | 1953.8 ms | 11.6 |
    /// | 4096x4096 | Half | 486.2 ms | 11.6 |
    /// | 4096x4096 | Quarter | 120.6 ms | 11.5 |
    ///
    /// — so an estimate here is arithmetic on a measured slope, not a guess. The ten-skin figure is
    /// the one taken because a caution is about the expensive end; using 9.2 would under-report every
    /// case the caution exists to catch, and the two figures differ by fixed per-composite overhead
    /// (one context allocation) that matters less the more skins there are.
    ///
    /// **Calibrated to the slowest device the owner draws on, deliberately.** A faster iPad pays less
    /// than this says, so the caution errs toward speaking on a machine where it need not — which is
    /// the safe direction for a line that only ever suggests a cheaper setting.
    static let compositeMillisecondsPerMegapixelPerSkin: Double = 11.5

    /// **What producing one skin's source costs when the source has to be resampled** — the read of
    /// the cel at canvas resolution, per megapixel of *canvas*. Same device, same day, same test.
    ///
    /// A miss flattens the cel at canvas resolution before anything is reduced, so the dominant term
    /// scales with the document and not with the resolution the artist picked. **That is why Quarter
    /// does not make a miss cheap**, and it is the single most surprising thing in this arithmetic.
    static let sourceReadMillisecondsPerCanvasMegapixel: Double = 6.8

    /// The resample's own cost, per megapixel of the buffer it writes. Only paid when the composite
    /// is smaller than the canvas — a filtered downscale, as against the straight blit below.
    static let sourceResampleMillisecondsPerMegapixel: Double = 13.2

    /// **What producing one skin's source costs at Full, per megapixel of canvas — and it is the
    /// *cheapest* of the three options, which is the opposite of what the rest of this file would
    /// lead you to expect.** At Full there is no reduction, so the flatten is a 1:1 copy with no
    /// interpolation filter in it at all; Half and Quarter pay a filtered downscale that Full does
    /// not.
    ///
    /// So Full's problem is never the price of a miss. It is **how many misses there are**, which
    /// `cachedSourceCount` answers, and it is much the worse of the two.
    ///
    /// The three constants above and this one reproduce every one of the six measured misses within
    /// 4% — measured on the simulator by the same test and scaled by the 1.26x device factor that
    /// the composite rows of the same run establish:
    ///
    /// | canvas | option | measured (device-scaled) | predicted |
    /// |---|---|---|---|
    /// | 2048x1024 | Full | 13.0 ms | 13.0 ms |
    /// | 2048x1024 | Half | 20.4 ms | 20.2 ms |
    /// | 2048x1024 | Quarter | 17.9 ms | 17.3 ms |
    /// | 4096x4096 | Full | 103.8 ms | 104.0 ms |
    /// | 4096x4096 | Half | 161.8 ms | 161.6 ms |
    /// | 4096x4096 | Quarter | 122.3 ms (measured on device directly) | 122.0 ms |
    static let sourceCopyMillisecondsPerCanvasMegapixel: Double = 6.5

    /// How many of a document's cels can actually be held as onion-skin sources at once.
    ///
    /// **Two completely different caches answer this, and which one applies is decided by whether
    /// the resolution reduces anything.**
    ///
    ///  * **Reduced (Half, Quarter, or Full on a canvas the floor has raised):** `OnionSkinRasterCache`
    ///    holds them, bounded by `sourceCacheLimit`.
    ///  * **Full:** the reduction is a no-op, so `OnionSkinRasterCache.image(for:canvasSize:at:)`
    ///    falls through to `PixelOps.rasterize` and the sources live in the *compositor's* flatten
    ///    cache — canvas-sized entries, `PixelOps.sharedRasterizeEntryLimit` of them, bounded by
    ///    `CompositorBudget.textureBudgetBytes`. On a 3 GB iPad that budget is 192 MiB, so a
    ///    4096x4096 document holds **three** and a 2048x1024 one holds twenty-four.
    ///
    /// The Full figure is an *upper* bound and the real one is lower, because those three slots are
    /// shared with the artwork: the compositor is holding the current frame's own layers in the same
    /// cache. Nothing here subtracts for that — the cel count is not knowable from a canvas size —
    /// so read this as "at best".
    static func cachedSourceCount(for canvasSize: CGSize,
                                  resolution: OnionSkinSettings.Resolution,
                                  sharedBudgetBytes: Int = CompositorBudget.textureBudgetBytes) -> Int {
        let size = compositeSize(for: canvasSize, resolution: resolution)
        let entry = Int(size.width.rounded()) * Int(size.height.rounded()) * 4
        guard entry > 0 else { return PixelOps.sharedRasterizeEntryLimit }
        guard size == canvasSize else { return sourceCacheLimit(entryBytes: entry) }
        return max(1, min(PixelOps.sharedRasterizeEntryLimit, sharedBudgetBytes / entry))
    }

    /// How many of a rebuild's `skins` sources will be misses in the steady state.
    ///
    /// **One, or all of them — there is nothing in between, and the cliff is what makes this worth
    /// computing rather than ignoring.** A rebuild happens when the playhead moves to a different
    /// drawing, which shifts the window by one, so exactly one cel is new. If the cache can hold the
    /// window *and* the newcomer, that one arrival is the only miss. If it cannot, eviction is FIFO
    /// over a window scanned in the same order every rebuild, which is the textbook worst case for
    /// FIFO: every entry is evicted a moment before it is wanted again, so **every skin misses, every
    /// time, forever** — no amount of revisiting the same drawings warms it.
    ///
    /// `skins + 1` rather than `skins` is the same slack argument `sourceCacheLimit` already makes
    /// for its "+2": a cache exactly the size of the window is full at all times and the arrival
    /// evicts something still wanted.
    ///
    /// This is the second, independent reason a combination is expensive, and on a large document it
    /// is the larger one — a miss is tens or hundreds of milliseconds each, and this decides whether
    /// there is one of them or ten.
    static func sourceMissesPerRebuild(for canvasSize: CGSize,
                                       resolution: OnionSkinSettings.Resolution,
                                       skins: Int,
                                       sharedBudgetBytes: Int = CompositorBudget.textureBudgetBytes) -> Int {
        guard skins > 0 else { return 0 }
        let cached = cachedSourceCount(for: canvasSize, resolution: resolution,
                                       sharedBudgetBytes: sharedBudgetBytes)
        return cached >= skins + 1 ? 1 : skins
    }

    /// **What one onion-skin rebuild will cost, in milliseconds, on the owner's iPad.**
    ///
    /// A rebuild is two things and the panel has only ever been able to see one of them:
    ///
    ///     composite  = 11.5 ms x composite megapixels x skins
    ///     one miss   = 6.8 ms x canvas MP + 13.2 ms x composite MP   (reduced: a filtered downscale)
    ///                = 6.5 ms x canvas MP                            (Full: a 1:1 copy)
    ///     rebuild    = composite + misses x one miss
    ///
    /// The miss term is the half that the per-option table in `PerfBaselineTests` leaves out, and
    /// leaving it out is what made Full look merely linear. **At Full the source production does not
    /// vanish, it relocates**: `OnionSkinRasterCache` stores nothing because there is no reduction to
    /// store, so the flatten is paid through `PixelOps.rasterize` at canvas size and cached in the
    /// compositor's own store — which on a 4096x4096 document holds three canvas-sized entries in
    /// total, shared with the artwork. So Full on a large canvas is not "the table's number"; it is
    /// the table's number plus ten full-canvas flattens, and it also evicts the compositor's working
    /// set on the way past.
    ///
    /// `skins` is the total across both sides — `previousCount + nextCount`, capped at
    /// `maxSkinsPerSide` each — not per side.
    static func estimatedRebuildMilliseconds(for canvasSize: CGSize,
                                             resolution: OnionSkinSettings.Resolution,
                                             skins: Int,
                                             sharedBudgetBytes: Int = CompositorBudget.textureBudgetBytes) -> Double {
        guard skins > 0, canvasSize.width > 0, canvasSize.height > 0 else { return 0 }
        let size = compositeSize(for: canvasSize, resolution: resolution)
        let megapixel = 1024.0 * 1024.0
        let compositeMP = Double(size.width * size.height) / megapixel
        let canvasMP = Double(canvasSize.width * canvasSize.height) / megapixel
        let composite = compositeMillisecondsPerMegapixelPerSkin * compositeMP * Double(skins)
        let miss = sourceMissMilliseconds(canvasSize: canvasSize, compositeSize: size)
        let misses = sourceMissesPerRebuild(for: canvasSize, resolution: resolution, skins: skins,
                                            sharedBudgetBytes: sharedBudgetBytes)
        return composite + Double(misses) * miss
    }

    /// What one source miss costs — the two regimes of `sourceCopyMillisecondsPerCanvasMegapixel`.
    /// Split on whether anything is actually reduced rather than on the enum case, because the
    /// readability floor can make Half or Quarter a no-op on a small document and then they are 1:1
    /// blits too.
    static func sourceMissMilliseconds(canvasSize: CGSize, compositeSize: CGSize) -> Double {
        let megapixel = 1024.0 * 1024.0
        let canvasMP = Double(canvasSize.width * canvasSize.height) / megapixel
        let compositeMP = Double(compositeSize.width * compositeSize.height) / megapixel
        guard compositeSize != canvasSize else {
            return sourceCopyMillisecondsPerCanvasMegapixel * canvasMP
        }
        return sourceReadMillisecondsPerCanvasMegapixel * canvasMP
            + sourceResampleMillisecondsPerMegapixel * compositeMP
    }

    /// **Where a rebuild stops reading as instant, and the number is about *when* the cost lands
    /// rather than about how big it is.**
    ///
    /// A rebuild happens when the playhead moves to a different drawing — never while the artist is
    /// drawing (`Coordinator.OnionSkinKey` is what guarantees that), so this is a hitch on a frame
    /// change, not a per-frame cost. That is a much more forgiving budget than 16 ms: the artist has
    /// just asked to look at a different drawing and is waiting to see it. Under about a tenth of a
    /// second the new frame appears to arrive with the tap; by a third of a second it is a stutter
    /// the artist notices but works through; past half a second scrubbing stops being usable.
    ///
    /// **250 ms**, and it survived having the source-miss term added to the estimate under it, which
    /// is the only reason it is still 250. Adding a term that raises every figure is exactly the kind
    /// of change that should move a threshold, so it was re-derived rather than kept: with the misses
    /// in, the owner's 2048x1024 canvas tops out at **243 ms** — Full at the maximum ten skins, the
    /// most expensive thing that document can be asked to do — so the whole of it stays silent, and
    /// the 4096x4096 stress case speaks at Full even at the shipped default of two skins (472 ms).
    /// Those are the two verdicts the measurements support, and 250 delivers both.
    ///
    /// **The margin at the top of the owner's canvas is 7 ms and that is worth knowing rather than
    /// discovering.** It is small because the estimate is accurate, not because it is lucky: 243 is a
    /// measured figure to within a few percent. A slightly taller document, or a fourth skin's worth
    /// of anything, and Full will start to speak there — correctly, since a quarter-second hitch on
    /// every drawing change is the thing this line exists to name.
    ///
    /// Pinned in both directions by `OnionSkinLogicTests`, so moving it is a decision rather than a
    /// drift.
    static let cautionThresholdMilliseconds: Double = 250

    /// The caution the panel shows, or nil when the combination is fine.
    ///
    /// **Factual and short by construction**: what the current settings cost, and the sharpest
    /// cheaper option that comes in under the threshold, with its cost. No adjectives, no severity
    /// word — the numbers are the argument. When no option is under the threshold the line says so
    /// and names the other lever, the skin count, because at that point resolution alone cannot fix
    /// it.
    ///
    /// Returns nil for zero skins, which is not a cheap onion skin but no onion skin at all.
    static func caution(for canvasSize: CGSize,
                        settings: OnionSkinSettings,
                        sharedBudgetBytes: Int = CompositorBudget.textureBudgetBytes) -> String? {
        // Clamped both ways, as `opacities(on:)` does — the panel's sliders cannot produce anything
        // outside 0...maxSkinsPerSide, but this is arithmetic on settings and not on a slider.
        func clamp(_ count: Int) -> Int { max(0, min(count, OnionSkinSettings.maxSkinsPerSide)) }
        let skins = clamp(settings.previousCount) + clamp(settings.nextCount)
        guard skins > 0 else { return nil }
        let cost = estimatedRebuildMilliseconds(for: canvasSize, resolution: settings.resolution,
                                                skins: skins, sharedBudgetBytes: sharedBudgetBytes)
        guard cost >= cautionThresholdMilliseconds else { return nil }

        // Sharpest first, so the suggestion gives up as little picture as it has to.
        let cheaper = OnionSkinSettings.Resolution.allCases
            .filter { $0.fraction < settings.resolution.fraction }
            .map { ($0, estimatedRebuildMilliseconds(for: canvasSize, resolution: $0, skins: skins,
                                                     sharedBudgetBytes: sharedBudgetBytes)) }
            .first { $0.1 < cautionThresholdMilliseconds }

        let here = "About \(duration(cost)) each time the drawing changes."
        guard let cheaper else { return here + " Fewer skins is the other lever." }
        return here + " \(cheaper.0.title): about \(duration(cheaper.1))."
    }

    /// Milliseconds as the artist reads them: whole milliseconds below a second, one decimal above.
    /// Rounded to 10 ms so a slider drag does not animate a digit that means nothing.
    static func duration(_ milliseconds: Double) -> String {
        // Rounded *before* the unit is chosen, so 999 ms reads as "1.0 s" rather than "1000 ms".
        let rounded = (milliseconds / 10).rounded() * 10
        guard rounded >= 1000 else { return "\(Int(rounded)) ms" }
        return String(format: "%.1f s", rounded / 1000)
    }
}

/// One cel's pixels at onion-skin resolution, memoized per cel version.
///
/// **This exists because of the source-read floor documented on `OnionSkinBudget`**, and it is the
/// half of that fix that actually moves the number: without it every rebuild resamples a 4096²
/// image per skin, and with it that resample is paid once per cel version and then reused by every
/// rebuild the cel appears in — which, with a playhead moving through a cycle, is most of them.
///
/// **Deliberately not `PixelOps.rasterizeCache`, and the reason is that cache's eviction policy.**
/// It evicts in insertion order under a shared byte budget, and its other entries are *canvas-sized*
/// — 64 MiB each at 4096². Pushing ten small onion entries through it would walk the compositor's
/// current-frame working set out of it in FIFO order, trading a stall on the onion skin for a stall
/// on the artwork. A separate, smaller store cannot do that.
///
/// **A miss renders the cel straight into the small buffer rather than through a canvas-sized
/// intermediate**, and that is measured rather than assumed. Reading through
/// `PixelOps.rasterize(cel:canvasSize:)` was the first version of this and cost 175 ms a cel at
/// 4096², because a cel the onion skin wants sits at *another* frame and so is precisely the cel the
/// compositor has not just rasterized — every miss allocated a 64 MiB canvas-sized context and
/// filled it only to shrink it away. `memoize: false` skips both that intermediate and the shared
/// cache, and reuses `PixelOps`' own draw order rather than copying it.
enum OnionSkinRasterCache {

    private struct Key: Hashable {
        let celID: UUID
        let raster: ObjectIdentifier
        let rasterVersion: Int
        let vector: ObjectIdentifier?
        let vectorVersion: Int
        let fillImage: ObjectIdentifier?
        let bakedImage: ObjectIdentifier?
        let width: Int
        let height: Int
        /// The `ContentProvider` seam's half of this key — see `PixelOps.RasterizeKey.derived`. This
        /// store is the "second memo keyed like the preview's" that `OnionSkinSettingsSource`'s own
        /// note said a derived skin would need.
        let derived: AnyHashable?

        init(cel: Cel, size: CGSize, derived: AnyHashable? = nil) {
            self.derived = derived
            // Identity *and* version for both tiers, exactly as `PixelOps.RasterizeKey` argues: a
            // version alone is monotonic only within one object's lifetime, and reopening a project
            // rebuilds every texture with its counter back at 0 under the same cel id.
            celID = cel.id
            raster = ObjectIdentifier(cel.raster)
            rasterVersion = cel.raster.version
            vector = cel.vector.map(ObjectIdentifier.init)
            vectorVersion = cel.vector?.version ?? -1
            fillImage = cel.fillImage.map(ObjectIdentifier.init)
            bakedImage = cel.bakedImage.map(ObjectIdentifier.init)
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
        }
    }

    private static let lock = NSLock()
    private static var entries: [Key: UIImage] = [:]
    private static var order: [Key] = []
    private static var pressureToken: MemoryPressure.Token?

    /// `cel`'s content at `size`, from the cache when it can be.
    ///
    /// Returns the canvas-size image untouched when no reduction is called for, so a small document
    /// pays nothing at all for this — no extra entry, no extra copy, the same object the compositor
    /// is already holding.
    ///
    /// `derived` is the `ContentProvider` seam, resolved by the caller. **The evaluation it wraps is
    /// paid at canvas size and then reduced**, because derived geometry is in canvas coordinates and
    /// a smaller render would clip rather than scale — so a derived skin costs one full evaluation
    /// per (cel, identity) and is then served from here for every rebuild after.
    static func image(for cel: Cel, canvasSize: CGSize, at size: CGSize,
                      derived: DerivedCelContent? = nil) -> UIImage {
        guard size.width < canvasSize.width || size.height < canvasSize.height else {
            // No reduction called for, so there is nothing for this cache to add: hand back the
            // shared memo the compositor is already holding rather than a second copy of it.
            return PixelOps.rasterize(cel: cel, canvasSize: canvasSize, derived: derived)
        }

        let key = Key(cel: cel, size: size, derived: derived?.identity)
        lock.lock()
        if let hit = entries[key] { lock.unlock(); return hit }
        lock.unlock()

        let reduced = PixelOps.rasterize(cel: cel, canvasSize: size, memoize: false, derived: derived)

        lock.lock()
        installMemoryObserverIfNeeded()
        if entries.updateValue(reduced, forKey: key) == nil { order.append(key) }
        // The limit is derived from *this* entry's size rather than fixed, because the artist can now
        // change the resolution and with it what one entry costs — see `OnionSkinBudget`. Entries at
        // an older resolution are a different key and simply age out through the same eviction.
        let limit = OnionSkinBudget.sourceCacheLimit(entryBytes: bytes(of: reduced))
        while order.count > limit, let evicted = order.first {
            order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
        lock.unlock()
        return reduced
    }

    /// Called on a memory warning, on backgrounding, and by tests that need to measure an uncached cost.
    static func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(); order.removeAll()
    }

    /// What this is holding, for `PerfBaselineTests`. Nothing in the render path reads it.
    static var residentBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.values.reduce(0) { $0 + bytes(of: $1) }
    }

    private static func bytes(of image: UIImage) -> Int {
        (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
    }

    /// Registered lazily rather than in a static initialiser so a process that never turns onion skin
    /// on never registers at all. Called under `lock`.
    ///
    /// **Through `MemoryPressure`, on either level.** RENDER.md §2.6 and BUGS.md's census item 6: six
    /// caches each named `UIApplication.didReceiveMemoryWarningNotification` and
    /// `didEnterBackgroundNotification` in their own initialisers, and a host that is not iOS had
    /// nothing to signal and no list of who to signal. The subscription lives in one place now.
    ///
    /// **Purges on a warning rather than halving, unlike the two byte-budgeted CPU caches.** This one
    /// is bounded by `OnionSkinBudget` rather than by `CompositorBudget`, and its entries are the
    /// *whole* onion window — halving it leaves an onion skin with holes in it, which reads as a bug
    /// rather than as a saving. All or nothing is the honest response for a cache whose entries are
    /// only useful as a set. Correctness-neutral either way: an entry is derived from its key and
    /// costs one re-rasterize to rebuild.
    private static func installMemoryObserverIfNeeded() {
        guard pressureToken == nil else { return }
        MemoryPressure.startObservingSystemEvents()
        pressureToken = MemoryPressure.register("OnionSkinRasterCache") { _ in removeAll() }
    }
}

// MARK: - The source

/// The onion skin the panel configures: up to `previousCount` drawings/frames behind and
/// `nextCount` ahead, on the current layer, each at its slot's opacity and its side's tint.
///
/// Stateless — every decision comes from `manager.onionSkin` — so the view layer can hold one of
/// these forever and the panel changing anything is picked up on the next pass.
///
/// **A derived in-between skins as its evaluated content** — VECTOR_INTERPOLATION item 18, fixed by
/// the `ContentProvider` seam. This used to read stored content only, so a `.generate` in-between was
/// skipped outright (it stores nothing; `Cel.isCertainlyBlank` sees that) and a `.reproject` one
/// skinned as the artist's own drawing rather than the reposed one. The note here said fixing it
/// "means a second memo keyed like the preview's, and wants its own change" — that memo is
/// `OnionSkinRasterCache`'s `derived` key field, and this is that change.
///
/// **The cost is real and bounded by the memo rather than by a limit.** An evaluation is two lattice
/// embeddings, an ARAP solve and two canvas-sized renders; with ten slots open on a span of
/// in-betweens the *first* rebuild after any change pays one per distinct cel. Every rebuild after it
/// — which, with a playhead moving through a cycle, is nearly all of them — is a cache hit, on the
/// same key the live preview would compute. If that first pass proves too slow on a real span, the
/// lever is capping how many derived skins evaluate per rebuild, not going back to blank ghosts.
struct OnionSkinSettingsSource: OnionSkinSource {

    func frames(for manager: CanvasManager) -> [OnionSkinFrame] {
        guard let canvasSize = manager.canvasSize,
              manager.layers.indices.contains(manager.currentLayerIndex) else { return [] }
        let settings = manager.onionSkin
        // **Frames come out at onion-skin resolution, not canvas resolution**, so the composite draws
        // them 1:1 instead of resampling a 4096² image once per skin per rebuild. That resample was
        // 73% of the cost of a rebuild — see `OnionSkinBudget` for the measurement that found it.
        let skinSize = OnionSkinBudget.compositeSize(for: canvasSize, resolution: settings.resolution)
        let cels = manager.layers[manager.currentLayerIndex].cels
        guard !cels.isEmpty else { return [] }
        let spans = cels.map { CelSpan(start: $0.startFrame, length: $0.frameCount) }
        let currentCelIndex = manager.activeCelIndex(inLayer: manager.currentLayerIndex,
                                                     atFrame: manager.currentFrame)

        // Gathered with the distance kept, then sorted furthest-first across *both* sides, so the
        // composite lays the faintest skins down and the nearest ones last. With `.normal` blending
        // that ordering is what makes the nearest neighbour read as the nearest neighbour where two
        // skins overlap — and doing it across both sides rather than within each one means the skin
        // one step back is not buried under the one three steps forward.
        var gathered: [(distance: Int, frame: OnionSkinFrame)] = []
        for side in [OnionSkinSettings.Side.previous, .next] {
            let opacities = settings.opacities(on: side)
            let indices = OnionSkinPlanner.resolvedCelIndices(
                spans: spans,
                currentCelIndex: currentCelIndex,
                currentFrame: manager.currentFrame,
                neighbourhood: settings.neighbourhood,
                loops: settings.loops,
                side: side,
                count: settings.count(on: side))
            let tint: UIColor? = settings.colouring == .tinted ? settings.tint(on: side).uiColor : nil

            for slot in indices.indices {
                guard let celIndex = indices[slot], cels.indices.contains(celIndex) else { continue }
                let opacity = slot < opacities.count ? opacities[slot] : 0
                guard opacity > 0 else { continue }
                // A cel with certainly nothing in it is skipped before it can cost a rasterize and a
                // canvas-sized draw. Held and blank frames are ordinary in animation, and with ten
                // slots open they are the common case rather than the corner.
                //
                // **`isCertainlyBlank` is asked second, and only of a cel that derives nothing.** It
                // answers about *stored* tiers and says so in its own doc comment — a `.generate`
                // in-between reports blank while displaying a whole drawing, so consulting it first
                // would skip precisely the cels this seam exists to render.
                let derived = manager.derivedCelContent(for: cels[celIndex],
                                                        atFrame: cels[celIndex].startFrame)
                guard derived != nil || !cels[celIndex].isCertainlyBlank else { continue }
                let image = OnionSkinRasterCache.image(for: cels[celIndex],
                                                       canvasSize: canvasSize, at: skinSize,
                                                       derived: derived)
                gathered.append((distance: slot + 1,
                                 frame: OnionSkinFrame(image: image,
                                                       opacity: CGFloat(opacity),
                                                       tint: tint)))
            }
        }
        // `sorted(by:)` is not stable, so ties (the same distance on either side) would swap order
        // between calls and make a cached composite differ from an identical one. Broken by side —
        // previous under next — via the gather order, which the index is a proxy for.
        return gathered.enumerated()
            .sorted { lhs, rhs in
                lhs.element.distance == rhs.element.distance
                    ? lhs.offset < rhs.offset
                    : lhs.element.distance > rhs.element.distance
            }
            .map(\.element.frame)
    }
}

/// Interpolate mode's onion skin: **the two reference keyframes**, tinted apart, rather than ±1
/// frame.
///
/// The references are what the in-between is being judged against, and they are frequently nowhere
/// near the previous frame — a two-keyframe span can be twelve frames wide, which is exactly when
/// "the previous cel" shows nothing useful.
///
/// Reads `interpolationReferences` (the artist's current selection) rather than the recipe on the
/// current cel, so the references are visible while they are being *picked* — before any recipe
/// exists — which is the moment the artist most wants to see them together.
struct InterpolationReferenceOnionSkinSource: OnionSkinSource {

    /// Blue for the keyframe behind, warm red for the one ahead. Two hues far enough apart to read
    /// as "before" and "after" at 30% opacity over a drawing; a single tint would make a
    /// twelve-frame span unreadable, since both references would look the same.
    ///
    /// Deliberately **not** the panel's configurable tints. These name a different thing — "the two
    /// references this in-between is derived from" — and the panel's red/green name "before" and
    /// "after". Sharing the colours would make the mode indistinguishable from ordinary onion skin
    /// at exactly the moment the artist needs to know which one they are looking at.
    static let pastTint = UIColor.systemBlue
    static let futureTint = UIColor.systemRed

    func frames(for manager: CanvasManager) -> [OnionSkinFrame] {
        guard let canvasSize = manager.canvasSize else { return [] }
        let keyframes = manager.interpolationKeyframes
        guard keyframes.count >= 2 else { return [] }

        // Which references count as "behind" is decided by frame rather than by list position, so a
        // reference set while the playhead sits between them tints correctly either way.
        return keyframes.enumerated().compactMap { index, reference in
            let cels = reference.cels.compactMap { ref -> Cel? in
                guard let at = manager.celIndices(forCel: ref.celID, inLayer: ref.layerID) else {
                    return nil
                }
                return manager.layers[at.layer].cels[at.cel]
            }
            guard let startFrame = cels.map(\.startFrame).min() else { return nil }
            // Onion-skin resolution here too. This source mints a fresh image every call — its
            // references have no cel-version identity to memoize on the way the settings source does —
            // so it is the one path that pays a full render per pass, and rendering it at 4096² was
            // paying that at sixteen times the necessary size.
            let skinSize = OnionSkinBudget.compositeSize(for: canvasSize,
                                                          resolution: manager.onionSkin.resolution)
            let bounds = CGRect(origin: .zero, size: skinSize)
            // One reference can span layers (requirement 5), so its cels flatten into one frame —
            // otherwise lineart and flats would tint as two separate onion skins.
            let image = UIGraphicsImageRenderer(size: skinSize, format: PixelOps.transparentFormat()).image { _ in
                for cel in cels {
                    // Through the seam like every other flatten. A reference keyframe normally
                    // stores its own ink — `interpolate` refuses `.alreadyInterpolated` for the
                    // *target* but nothing forbids flagging a derived cel as a keyframe — so this
                    // costs one optional test on the ordinary path and is right on the other.
                    PixelOps.rasterize(cel: cel, canvasSize: canvasSize,
                                       derived: manager.derivedCelContent(for: cel, atFrame: cel.startFrame))
                        .draw(in: bounds)
                }
            }
            let isPast = startFrame <= manager.currentFrame
            return OnionSkinFrame(image: image,
                                  opacity: CGFloat(manager.onionSkin.linkedLevel),
                                  tint: isPast ? Self.pastTint : Self.futureTint)
        }
    }
}
