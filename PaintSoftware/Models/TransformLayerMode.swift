import CoreGraphics
import Foundation

/// **What a container pose *does* with the pose the artist authored** — TRANSFORM_LAYER.md §5, the
/// modes of the transform layer, and the same three on a posed folder (§3.3: a folder's pose takes
/// the pose modes as well, or its keyable rows would key nothing).
///
/// **Named `TransformLayerMode` and not `TransformMode`**, because that name is taken: `TransformMode`
/// is the Move bar's Uniform / Freeform / Distort picker (`SelectionModels.swift`), which is about
/// *how a box is dragged*, and this is about *what a layer does with the box once it is set*. The
/// two meet in §5.3 — a Rotate layer's box under Distort is what gives the perspective ellipse — so
/// they must not share a spelling.
///
/// **Five cases, one per §8 stage.** Each arrived with its own render arm and its own test — a case
/// here before its stage landed would have been a row the mode picker offers and nothing honours,
/// CLAUDE.md's *"refusal with no notice"* wearing a menu.
///
/// **Repeat is the one that is not a pose** (§3.1's second shape): it produces a *frame* per entry
/// beneath it rather than a map, and it is here rather than in a home of its own because it is the
/// same kind of leaf with the same scope rule — spent in `renderNodes`' carry on the entries
/// beneath, in its own container — and the owner listed it with the others. It is also the one mode
/// a **folder cannot take** (`folderCases`): the loop's extent is the block, and a folder has none.
///
/// **The mode lives on `LayerPose`** (`LayerPose.mode`), which is what makes a folder's pose take it
/// for free — `Layer.transform` and `LayerFolder.transform` are one type — and what keeps "a mode
/// never outlives the pose it qualifies" structural, `LayerPose.track`'s own argument for nesting.
/// The scalars each mode reads (`rotateSpeed`, `parallaxShare`, the three shake amplitudes) are
/// `TargetChannel` rows on the two homes, §3.3, and are *not* here: a key path into a nested optional
/// is not writable. What is **not** keyable — shake's seed and period — lives on `LayerPose` beside
/// the mode, for the same "never outlives the pose it qualifies" reason.
enum TransformLayerMode: String, Codable, CaseIterable, Identifiable {

    /// §5.1 — the authored pose, applied to everything beneath. Every document before 2026-09-11.
    case move

    /// §5.2 — each item directly beneath takes its own *share* of the authored pose: 100/75/50/25 for
    /// four by default, keyable per item, a typed number staying with its layer.
    case parallax

    /// §5.3 — the authored pose, pre-composed with a turn about the box's own centre whose angle is
    /// the integral of `rotateSpeed` (degrees per frame) from the block's first frame.
    case rotate

    /// §5.4 — the authored pose, pre-composed with a jolt in box space about the box's centre: a
    /// slide of `shakeX`/`shakeY` and a turn of `shakeRotation`, each scaled by value noise that is a
    /// pure function of `(seed, channel, beat)` (§2 ruling 9: the same every play; Re-roll changes
    /// the seed). `shakePeriod` is how many frames one beat lasts (ruling 10).
    case shake

    /// §5.5 — everything beneath is shown at the **source** frame `s + ((f − s) mod p)` for a block
    /// starting at `s` and a typed period `p` (`LayerPose.repeatPeriod`, ruling 11: typed, pre-filled
    /// from where the drawings beneath end). Everything repeats — cels, their cel-local keys, the
    /// entries' opacity and effect curves, a transform layer beneath (ruling 12) — and drawing on a
    /// repeated frame lands on the frame it repeats (ruling 13).
    case `repeat`

    var id: String { rawValue }

    /// The artist-facing label — the picker's caption and the row's title.
    var displayName: String {
        switch self {
        case .move: return "Move"
        case .parallax: return "Parallax"
        case .rotate: return "Rotate"
        case .shake: return "Shake"
        case .repeat: return "Repeat"
        }
    }

    /// One line under the picker saying what the mode does with the box, so the artist is not sent
    /// to the source to learn it (CLAUDE.md's *"what does the artist do next"*).
    var caption: String {
        switch self {
        case .move: return "Pose everything beneath by the box"
        case .parallax: return "Each item beneath takes a share of the box's move"
        case .rotate: return "Spin everything beneath about the box's centre"
        case .shake: return "Jolt everything beneath about the box's centre"
        case .repeat: return "Play the frames beneath again from the bar's start, until it ends"
        }
    }

    /// **The modes a posed folder may take** — every pose mode and not Repeat (§3.3: *"not repeat: a
    /// folder has no block"*). The folder panel's picker lists these; the layer's lists `allCases`.
    static let folderCases: [TransformLayerMode] = [.move, .parallax, .rotate, .shake]
}

// MARK: - The arithmetic, stated once

/// The pure functions the three modes are made of — on the enum so `RenderTree.renderNodes`,
/// `LayerPose.movesItsContents`'s callers and the tests read one spelling. Nothing here touches a
/// `CanvasManager`; every input is a value.
extension TransformLayerMode {

    /// **Item `rank` of `count` — the positional default share**, §5.2: `(n − k + 1) / n` for item
    /// *k* of *n* counted from the top, or with a zero-based rank `(n − rank) / n`. Four items are
    /// 1.0, 0.75, 0.5, 0.25 — the owner's own example — and the item nearest the parallax layer
    /// moves most.
    static func positionalParallaxShare(rank: Int, of count: Int) -> Double {
        guard count > 0, rank >= 0, rank < count else { return 1 }
        return Double(count - rank) / Double(count)
    }

    /// **A share of a pose** — `PoseInterpolation.blend(rest, authored, t: share)`, which is §5.2's
    /// whole definition and the one interpolation §2.15 allows: for a pure translation exactly
    /// `share × P`, for a scale or a turn the factored blend, beyond 0…1 the extrapolation the owner
    /// asked for (*"negative values or higher"*), and the nearer end only where the result goes
    /// singular (KEYFRAMES §9.1).
    ///
    /// Nil where the authored pose is at rest or the share leaves the item where it is, for
    /// `LayerPose.mapping(atFrame:)`'s reason: nil is what decides whether the leaf beneath has a
    /// derivation at all, so an untouched parallax layer must cost the document nothing.
    static func parallaxMap(authored: PoseQuad, share: Double) -> PoseMap? {
        guard !authored.isIdentity else { return nil }
        let rest = PoseQuad(restingIn: authored.box)
        guard let blended = PoseInterpolation.blend(rest, authored, t: CGFloat(share)),
              !blended.isIdentity, let map = blended.map, !map.isIdentity else { return nil }
        return map
    }

    /// **θ(f) = Σ speed(k) for k from `start` to `frame − 1`** — §5.3, in degrees. Integrated rather
    /// than `speed(f) × (f − f0)`, so a speed keyed 0 → 15 is a wheel spinning up and a speed keyed to
    /// 0 is a wheel that stops where it is; under the product a keyed speed would snap the wheel
    /// backwards. Zero at the block's first frame and at every frame before it.
    ///
    /// **`hasCurve` chooses the closed form.** With no curve every term is the same number and the
    /// sum is `speed × (frame − start)` exactly for the values an artist types (15 × 6 and 15 + 15 +
    /// 15 + 15 + 15 + 15 are both 90, bit for bit); with a curve the terms differ and the sum is the
    /// only honest reading. Either way the answer is a pure function of `(track, start, frame)`,
    /// which is what RENDER's *"the same frame renders the same bytes"* needs of it (§7).
    static func integratedRotationDegrees(from start: Int, to frame: Int, hasCurve: Bool,
                                          speedAt speed: (Int) -> Double) -> Double {
        guard frame > start else { return 0 }
        guard hasCurve else { return speed(start) * Double(frame - start) }
        var total = 0.0
        for k in start..<frame { total += speed(k) }
        return total
    }

    /// **The rotate mode's map at one frame**: a turn of `degrees` about the centre of the authored
    /// pose's own box, *then* the authored map — `R` pre-composed in box space, §5.3. That order is
    /// the owner's perspective trick (§2 ruling 8): a circle in box space through a keystoned quad is
    /// an ellipse on screen, so Distort on the box gives *"rotating in ellipses"* with nothing else
    /// built. The box's own rotation, made with Move, is the start angle for free.
    ///
    /// Positive degrees turn clockwise as drawn — `CGAffineTransform(rotationAngle:)`'s own sense on
    /// a y-down canvas, and the sense the Move box's rotation handle reports.
    ///
    /// Nil where nothing turns and nothing is posed, for `parallaxMap`'s reason. A whole number of
    /// turns is treated as no turn rather than trusted to the trigonometry, because `PoseMap.isIdentity`
    /// is exact and `cos(4π)` is not.
    static func rotationMap(authored: PoseQuad, degrees: Double) -> PoseMap? {
        let turn = degrees.truncatingRemainder(dividingBy: 360)
        let authoredMap: PoseMap? = authored.isIdentity ? nil : authored.map
        guard turn != 0 else {
            guard let authoredMap, !authoredMap.isIdentity else { return nil }
            return authoredMap
        }
        let centre = CGPoint(x: authored.box.midX, y: authored.box.midY)
        let rotation = CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: CGFloat(turn * .pi / 180))
            .translatedBy(x: -centre.x, y: -centre.y)
        let spun = PoseMap.affine(rotation)
        guard let authoredMap else { return spun }
        return spun.concatenating(authoredMap)
    }

    /// How many frames one full turn takes at `degreesPerFrame` — the panel's second reading of the
    /// speed (§2 ruling 6: *"the panel can also show frames per turn"*). Nil at a speed of zero,
    /// where the wheel never completes a turn.
    static func framesPerTurn(degreesPerFrame: Double) -> Double? {
        guard degreesPerFrame != 0 else { return nil }
        return 360 / abs(degreesPerFrame)
    }

    // MARK: Shake (§5.4)

    /// **Value noise at one integer beat, −1…1** — a hash of `(seed, channel, beat)` through
    /// `DabRandom.avalanche`, splitmix64's finalizer addressed rather than stepped (that type's own
    /// argument). Channel 0 is the slide's x, 1 its y, 2 the turn, each an independently seeded
    /// stream so that x and y do not jolt in lockstep. The top 53 bits become a `Double` in 0…1
    /// exactly, then span −1…1.
    ///
    /// **A pure function of its three arguments and nothing else** — RENDER §2.16, *"the same frame
    /// renders the same bytes"*, and §2 ruling 9's *"the same every time you play"*. Changing this
    /// hash changes every saved shake on open, so `TransformLayerModesLogicTests` pins one raw value.
    static func shakeNoise(seed: UInt64, channel: UInt64, beat: Int) -> Double {
        let golden: UInt64 = 0x9E37_79B9_7F4A_7C15
        let base = DabRandom.avalanche(seed &+ (channel &+ 1) &* golden)
        let raw = DabRandom.avalanche(base &+ UInt64(bitPattern: Int64(beat)) &* golden)
        return Double(raw >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1
    }

    /// **The noise at a frame of the block, smoothstepped between beats** — `localFrame` is frames
    /// since the block's first frame (§4: the block is the function's origin, so a bar slid along the
    /// timeline shakes the same way), `period` is frames per beat: 1 is a new position every frame
    /// and the sample is the beat's own value; larger is a wobble that eases from one beat's value
    /// to the next's over `period` frames.
    static func shakeSample(seed: UInt64, channel: UInt64, localFrame: Int, period: Int) -> Double {
        let p = max(period, 1)
        // Floor division, so a frame before the block's start (a folder's, which has none and
        // integrates from 0) still lands on a beat rather than on Swift's truncation toward zero.
        let beat = localFrame >= 0 ? localFrame / p : -((-localFrame + p - 1) / p)
        let phase = localFrame - beat * p
        let a = shakeNoise(seed: seed, channel: channel, beat: beat)
        guard phase != 0 else { return a }
        let b = shakeNoise(seed: seed, channel: channel, beat: beat + 1)
        let t = Double(phase) / Double(p)
        return a + (b - a) * (t * t * (3 - 2 * t))
    }

    /// **The shake mode's map at one frame**: a jolt of `(x·n₁, y·n₂)` points and `rotation·n₃`
    /// degrees about the centre of the authored pose's own box, *then* the authored map — §5.4, one
    /// rule with `rotationMap`, and with the same consequence (§2 ruling 9): the jolt is in box
    /// space, so a box scaled 2× by Move shakes twice the pixels for the same amplitude. With the
    /// default canvas-sized box the whole picture shakes about its centre, which is a screen shake.
    ///
    /// Nil where nothing jolts and nothing is posed, for `parallaxMap`'s reason; an amplitude of
    /// zero contributes exactly nothing rather than `0 × noise`, so a layer with all three at zero is
    /// the authored pose bit for bit.
    static func shakeMap(authored: PoseQuad, localFrame: Int, period: Int, seed: UInt64,
                         x: Double, y: Double, rotation: Double) -> PoseMap? {
        let dx = x == 0 ? 0 : x * shakeSample(seed: seed, channel: 0, localFrame: localFrame, period: period)
        let dy = y == 0 ? 0 : y * shakeSample(seed: seed, channel: 1, localFrame: localFrame, period: period)
        let dr = rotation == 0 ? 0 : rotation * shakeSample(seed: seed, channel: 2, localFrame: localFrame, period: period)
        let authoredMap: PoseMap? = authored.isIdentity ? nil : authored.map
        guard dx != 0 || dy != 0 || dr != 0 else {
            guard let authoredMap, !authoredMap.isIdentity else { return nil }
            return authoredMap
        }
        let centre = CGPoint(x: authored.box.midX, y: authored.box.midY)
        let jolt = CGAffineTransform(translationX: centre.x + CGFloat(dx), y: centre.y + CGFloat(dy))
            .rotated(by: CGFloat(dr * .pi / 180))
            .translatedBy(x: -centre.x, y: -centre.y)
        let shaken = PoseMap.affine(jolt)
        guard let authoredMap else { return shaken }
        return shaken.concatenating(authoredMap)
    }

    /// The range the panel's period control offers — one beat a frame up to one every twelve.
    static let shakePeriodRange = 1...12

    // MARK: Repeat (§5.5)

    /// **The source frame a repeat shows at `frame`**: `s + ((f − s) mod p)` inside a block starting
    /// at `blockStart` with period `period`, so the first cycle is the identity and every later one
    /// reads the first. A period under 1 loops nothing — the frame is its own source — which is what
    /// a Repeat layer whose period was never set does. Frames before the block are never asked:
    /// the accumulator only reaches this where the block is in force.
    static func repeatSourceFrame(_ frame: Int, blockStart: Int, period: Int) -> Int {
        guard period >= 1, frame > blockStart else { return frame }
        return blockStart + (frame - blockStart) % period
    }
}
