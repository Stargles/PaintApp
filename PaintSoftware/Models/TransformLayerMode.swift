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
/// **Three cases, not five.** Shake and Repeat are §8's stages 4 and 5; a case here before its stage
/// lands would be a row the mode picker offers and nothing honours, which is CLAUDE.md's *"refusal
/// with no notice"* wearing a menu. Each arrives with its own render arm and its own test.
///
/// **The mode lives on `LayerPose`** (`LayerPose.mode`), which is what makes a folder's pose take it
/// for free — `Layer.transform` and `LayerFolder.transform` are one type — and what keeps "a mode
/// never outlives the pose it qualifies" structural, `LayerPose.track`'s own argument for nesting.
/// The scalars each mode reads (`rotateSpeed`, `parallaxShare`) are `TargetChannel` rows on the two
/// homes, §3.3, and are *not* here: a key path into a nested optional is not writable.
enum TransformLayerMode: String, Codable, CaseIterable, Identifiable {

    /// §5.1 — the authored pose, applied to everything beneath. Every document before 2026-09-11.
    case move

    /// §5.2 — each item directly beneath takes its own *share* of the authored pose: 100/75/50/25 for
    /// four by default, keyable per item, a typed number staying with its layer.
    case parallax

    /// §5.3 — the authored pose, pre-composed with a turn about the box's own centre whose angle is
    /// the integral of `rotateSpeed` (degrees per frame) from the block's first frame.
    case rotate

    var id: String { rawValue }

    /// The artist-facing label — the picker's caption and the row's title.
    var displayName: String {
        switch self {
        case .move: return "Move"
        case .parallax: return "Parallax"
        case .rotate: return "Rotate"
        }
    }

    /// One line under the picker saying what the mode does with the box, so the artist is not sent
    /// to the source to learn it (CLAUDE.md's *"what does the artist do next"*).
    var caption: String {
        switch self {
        case .move: return "Pose everything beneath by the box"
        case .parallax: return "Each item beneath takes a share of the box's move"
        case .rotate: return "Spin everything beneath about the box's centre"
        }
    }
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
}
