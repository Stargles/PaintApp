import UIKit

enum ThumbnailRenderer {
    static func render(_ raster: RasterLayerTexture, canvasSize: CGSize, thumbnailSize: CGSize) -> UIImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return UIImage()
        }
        let renderScale = max(min(thumbnailSize.width / canvasSize.width, thumbnailSize.height / canvasSize.height), 0.01)
        let size = CGSize(width: canvasSize.width * renderScale, height: canvasSize.height * renderScale)
        // `raster` is always at native resolution, so this is a downscale — made from the version's
        // own pixels or its file at thumbnail size (`RasterSource.thumbnailImage`), never by decoding
        // a canvas-sized picture and keeping it.
        guard let source = raster.snapshot() else {
            return UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in }
        }
        guard case .success(let image) = source.thumbnailImage(size: size, format: PixelOps.transparentFormat())
        else { return nil }
        return image
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
