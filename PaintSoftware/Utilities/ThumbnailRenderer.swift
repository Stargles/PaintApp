import UIKit

enum ThumbnailRenderer {
    static func render(_ raster: RasterLayerTexture, canvasSize: CGSize, thumbnailSize: CGSize) -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return UIImage()
        }
        let renderScale = max(min(thumbnailSize.width / canvasSize.width, thumbnailSize.height / canvasSize.height), 0.01)
        let size = CGSize(width: canvasSize.width * renderScale, height: canvasSize.height * renderScale)
        // `raster` is always at native resolution (unlike PKDrawing.image(from:scale:), which could
        // rasterize vector strokes directly at the target scale) — downscale via a
        // UIGraphicsImageRenderer draw-and-shrink.
        return UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            raster.renderToUIImage().draw(in: CGRect(origin: .zero, size: size))
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
