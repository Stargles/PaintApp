import PencilKit
import UIKit

enum ThumbnailRenderer {
    static func render(_ drawing: PKDrawing, canvasSize: CGSize, thumbnailSize: CGSize) -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return UIImage()
        }
        let renderScale = min(thumbnailSize.width / canvasSize.width, thumbnailSize.height / canvasSize.height)
        let bounds = CGRect(origin: .zero, size: canvasSize)
        return drawing.image(from: bounds, scale: max(renderScale, 0.01))
    }
}
