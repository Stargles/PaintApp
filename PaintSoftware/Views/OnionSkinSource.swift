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
