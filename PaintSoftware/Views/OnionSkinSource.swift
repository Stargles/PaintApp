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
///  1. The composite is capped at `maxCompositeEdge` on its longest side.
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

    /// The longest edge, in pixels, of the composite **and of the reduced sources drawn into it**.
    static let maxCompositeEdge: CGFloat = 1024

    /// How many reduced sources are held.
    ///
    /// **The window plus two, not the window exactly, and the two are the whole point.** The most
    /// skins that can be on screen at once is `maxSkinsPerSide` a side; a cache of exactly that size
    /// is full at all times, so stepping the playhead one frame brings one new cel in and evicts one
    /// — every move pays a miss, forever, even after the artist has been all the way round the cycle.
    /// Slack is what turns that into hits, and two is enough because a playhead moves one step at a
    /// time.
    static var sourceCacheLimit: Int { OnionSkinSettings.maxSkinsPerSide * 2 + 2 }

    /// Everything the onion skin can hold at once, in bytes, at `maxCompositeEdge`: one composite
    /// plus a full source cache.
    ///
    /// **This is a ceiling, not a cost.** The cache only ever fills to the number of skins actually
    /// asked for, so the shipped default of one skin either side holds two sources and one composite
    /// — about 12 MiB at 1024. The ~54 MiB ceiling is reachable only by dialling both sliders to
    /// five, which is the artist buying ten ghosts and paying for them.
    static var residentCeilingBytes: Int {
        let one = Int(maxCompositeEdge * maxCompositeEdge) * 4
        return one * (sourceCacheLimit + 1)
    }

    /// The size the composite is rendered at. Returns `canvasSize` unchanged when it is already
    /// within the cap, so this is inert on every canvas that never had a problem — and it never
    /// scales *up*, because a skin larger than the drawing it ghosts is pure cost.
    static func compositeSize(for canvasSize: CGSize) -> CGSize {
        compositeSize(for: canvasSize, maxEdge: maxCompositeEdge)
    }

    /// The rule against a stated cap — the half a test pins, so the number in the table above is
    /// checked rather than remembered.
    static func compositeSize(for canvasSize: CGSize, maxEdge: CGFloat) -> CGSize {
        let longest = max(canvasSize.width, canvasSize.height)
        guard maxEdge > 0, longest > maxEdge else { return canvasSize }
        let scale = maxEdge / longest
        // Floored to whole pixels for `RenderResolution.renderSize`'s reason: the app's several
        // rounding sites do not agree, and a source one pixel wider than the buffer reading it is a
        // garbage edge rather than a soft one.
        return CGSize(width: max(1, (canvasSize.width * scale).rounded(.down)),
                      height: max(1, (canvasSize.height * scale).rounded(.down)))
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

        init(cel: Cel, size: CGSize) {
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
    private static var memoryObserver: NSObjectProtocol?

    /// `cel`'s content at `size`, from the cache when it can be.
    ///
    /// Returns the canvas-size image untouched when no reduction is called for, so a small document
    /// pays nothing at all for this — no extra entry, no extra copy, the same object the compositor
    /// is already holding.
    static func image(for cel: Cel, canvasSize: CGSize, at size: CGSize) -> UIImage {
        guard size.width < canvasSize.width || size.height < canvasSize.height else {
            // No reduction called for, so there is nothing for this cache to add: hand back the
            // shared memo the compositor is already holding rather than a second copy of it.
            return PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        }

        let key = Key(cel: cel, size: size)
        lock.lock()
        if let hit = entries[key] { lock.unlock(); return hit }
        lock.unlock()

        let reduced = PixelOps.rasterize(cel: cel, canvasSize: size, memoize: false)

        lock.lock()
        installMemoryObserverIfNeeded()
        if entries.updateValue(reduced, forKey: key) == nil { order.append(key) }
        while order.count > OnionSkinBudget.sourceCacheLimit, let evicted = order.first {
            order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
        lock.unlock()
        return reduced
    }

    /// Called on a memory warning and by tests that need to measure an uncached cost.
    static func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(); order.removeAll()
    }

    /// What this is holding, for `PerfBaselineTests`. Nothing in the render path reads it.
    static var residentBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.values.reduce(0) { $0 + ($1.cgImage?.bytesPerRow ?? 0) * ($1.cgImage?.height ?? 0) }
    }

    /// Registered lazily rather than in a static initialiser so a process that never turns onion skin
    /// on never registers at all. Called under `lock`.
    private static func installMemoryObserverIfNeeded() {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in removeAll() }
    }
}

// MARK: - The source

/// The onion skin the panel configures: up to `previousCount` drawings/frames behind and
/// `nextCount` ahead, on the current layer, each at its slot's opacity and its side's tint.
///
/// Stateless — every decision comes from `manager.onionSkin` — so the view layer can hold one of
/// these forever and the panel changing anything is picked up on the next pass.
///
/// **A derived in-between skins as its stored content, not as its evaluated content**, and that is a
/// deliberate limit rather than an oversight. `CanvasManager.interpolatedImage` runs the ARAP
/// evaluator, which the live canvas memoizes behind `InterpolationPreviewKey` precisely because it is
/// too expensive to run per pass — running it for up to ten skins on every playhead move would be
/// worse than anything else in this file. So a `.generate` in-between is skipped (it stores nothing;
/// `Cel.isCertainlyBlank` sees that) and a `.reproject` in-between skins as the artist's own drawing
/// rather than the reposed one. Fixing it properly means a second memo keyed like the preview's, and
/// wants its own change.
struct OnionSkinSettingsSource: OnionSkinSource {

    func frames(for manager: CanvasManager) -> [OnionSkinFrame] {
        guard let canvasSize = manager.canvasSize,
              manager.layers.indices.contains(manager.currentLayerIndex) else { return [] }
        let settings = manager.onionSkin
        // **Frames come out at onion-skin resolution, not canvas resolution**, so the composite draws
        // them 1:1 instead of resampling a 4096² image once per skin per rebuild. That resample was
        // 73% of the cost of a rebuild — see `OnionSkinBudget` for the measurement that found it.
        let skinSize = OnionSkinBudget.compositeSize(for: canvasSize)
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
                guard !cels[celIndex].isCertainlyBlank else { continue }
                let image = OnionSkinRasterCache.image(for: cels[celIndex],
                                                       canvasSize: canvasSize, at: skinSize)
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
            let skinSize = OnionSkinBudget.compositeSize(for: canvasSize)
            let bounds = CGRect(origin: .zero, size: skinSize)
            // One reference can span layers (requirement 5), so its cels flatten into one frame —
            // otherwise lineart and flats would tint as two separate onion skins.
            let image = UIGraphicsImageRenderer(size: skinSize, format: PixelOps.transparentFormat()).image { _ in
                for cel in cels {
                    PixelOps.rasterize(cel: cel, canvasSize: canvasSize).draw(in: bounds)
                }
            }
            let isPast = startFrame <= manager.currentFrame
            return OnionSkinFrame(image: image,
                                  opacity: CGFloat(manager.onionSkin.linkedLevel),
                                  tint: isPast ? Self.pastTint : Self.futureTint)
        }
    }
}
