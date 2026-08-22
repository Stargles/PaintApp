import UIKit

enum ThumbnailRenderer {
    static func render(_ raster: RasterLayerTexture, fillImage: UIImage? = nil, canvasSize: CGSize, thumbnailSize: CGSize) -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return UIImage()
        }
        let renderScale = max(min(thumbnailSize.width / canvasSize.width, thumbnailSize.height / canvasSize.height), 0.01)
        let size = CGSize(width: canvasSize.width * renderScale, height: canvasSize.height * renderScale)
        // `raster` is always at native resolution (unlike PKDrawing.image(from:scale:), which could
        // rasterize vector strokes directly at the target scale) — downscale via the same
        // UIGraphicsImageRenderer draw-and-shrink path the fillImage compositing below already uses.
        let strokesImage = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            raster.renderToUIImage().draw(in: CGRect(origin: .zero, size: size))
        }
        guard let fillImage else { return strokesImage }

        let renderer = UIGraphicsImageRenderer(size: strokesImage.size, format: PixelOps.transparentFormat(scale: strokesImage.scale))
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: strokesImage.size)
            // Strokes first, fill on top — the order `PixelOps.rasterizeUncached` draws in, and for
            // the reason given there: a fill covers what is already on the cel (LASSO_FILL.md §2a).
            // This overload only ever sees a *live* fill preview, since a committed fill is flattened
            // into `raster`, but a thumbnail that contradicted the canvas would still be a bug.
            strokesImage.draw(in: rect)
            fillImage.draw(in: rect)
        }
    }

    /// Same downscaling as the drawing-based overload, for a cel that's been rendered to a single
    /// flattened image (see `PixelOps.rasterize`) because a select/move/fill/clear operation baked
    /// raster content into it.
    static func render(_ image: UIImage, canvasSize: CGSize, thumbnailSize: CGSize) -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return UIImage()
        }
        let renderScale = max(min(thumbnailSize.width / canvasSize.width, thumbnailSize.height / canvasSize.height), 0.01)
        let size = CGSize(width: canvasSize.width * renderScale, height: canvasSize.height * renderScale)
        let renderer = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat())
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
