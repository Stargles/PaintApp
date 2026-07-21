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
}
