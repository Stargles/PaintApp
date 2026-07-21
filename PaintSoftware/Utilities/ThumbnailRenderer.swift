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
        let strokesImage = UIGraphicsImageRenderer(size: size, format: Self.format(scale: 1)).image { _ in
            raster.renderToUIImage().draw(in: CGRect(origin: .zero, size: size))
        }
        guard let fillImage else { return strokesImage }

        let renderer = UIGraphicsImageRenderer(size: strokesImage.size, format: Self.format(scale: strokesImage.scale))
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: strokesImage.size)
            fillImage.draw(in: rect)
            strokesImage.draw(in: rect)
        }
    }

    private static func format(scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return format
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
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
