import PencilKit
import UIKit

enum ThumbnailRenderer {
    static func render(_ drawing: PKDrawing, fillImage: UIImage? = nil, canvasSize: CGSize, thumbnailSize: CGSize) -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return UIImage()
        }
        let renderScale = min(thumbnailSize.width / canvasSize.width, thumbnailSize.height / canvasSize.height)
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let strokesImage = drawing.image(from: bounds, scale: max(renderScale, 0.01))
        guard let fillImage else { return strokesImage }

        let format = UIGraphicsImageRendererFormat()
        format.scale = strokesImage.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: strokesImage.size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: strokesImage.size)
            fillImage.draw(in: rect)
            strokesImage.draw(in: rect)
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
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
