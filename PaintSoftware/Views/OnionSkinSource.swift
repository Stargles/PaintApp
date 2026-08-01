import UIKit

/// What the onion-skin layer should display. The current implementation answers "the previous cel
/// on the current layer"; interpolate mode will later answer "the two reference keyframes". Kept as
/// a protocol because the whole onion-skin feature is provisional and will be replaced — see
/// VECTOR_INTERPOLATION_PLAN.md §10 constraint B.
protocol OnionSkinSource {
    func frames(for manager: CanvasManager) -> [OnionSkinFrame]
}

/// One image to composite into the onion-skin layer.
struct OnionSkinFrame {
    let image: UIImage
    let opacity: CGFloat
    /// nil = untinted; interpolate mode tints past/future references differently.
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
    static func composite(_ frames: [OnionSkinFrame], size: CGSize?) -> UIImage? {
        guard let size, size.width > 0, size.height > 0, !frames.isEmpty else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            for frame in frames {
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

/// Today's onion skin: the previous cel on the current layer, untinted, at the onion-skin opacity
/// setting. Multi-frame/tint is plumbing for later — this always returns at most one frame.
struct PreviousCelOnionSkinSource: OnionSkinSource {
    func frames(for manager: CanvasManager) -> [OnionSkinFrame] {
        guard let canvasSize = manager.canvasSize,
              manager.layers.indices.contains(manager.currentLayerIndex),
              let celIdx = manager.activeCelIndex(inLayer: manager.currentLayerIndex, atFrame: manager.currentFrame - 1) else {
            return []
        }
        let cel = manager.layers[manager.currentLayerIndex].cels[celIdx]
        // Route through the shared cel-rasterisation path rather than reading `cel.raster` directly —
        // that path ignores a `.vector` cel's live strokes entirely, which onion-skinned a vector
        // layer to blank.
        let image = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        return [OnionSkinFrame(image: image, opacity: CGFloat(manager.onionSkinOpacity), tint: nil)]
    }
}

/// Interpolate mode's onion skin: **the two reference keyframes**, tinted apart, rather than ±1
/// frame (PLAN §5.0 step 4).
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
            let bounds = CGRect(origin: .zero, size: canvasSize)
            // One reference can span layers (requirement 5), so its cels flatten into one frame —
            // otherwise lineart and flats would tint as two separate onion skins.
            let image = UIGraphicsImageRenderer(size: canvasSize, format: PixelOps.transparentFormat()).image { _ in
                for cel in cels {
                    PixelOps.rasterize(cel: cel, canvasSize: canvasSize).draw(in: bounds)
                }
            }
            let isPast = startFrame <= manager.currentFrame
            return OnionSkinFrame(image: image,
                                  opacity: CGFloat(manager.onionSkinOpacity),
                                  tint: isPast ? Self.pastTint : Self.futureTint)
        }
    }
}
