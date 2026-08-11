import UIKit
import SwiftUI

/// Pixel-level image processing that backs the Select & Move tool. "Select a region and
/// move/resize/rotate/fill/clear it" is inherently a raster operation (this is how Procreate works
/// — it's fully raster under the hood), which the whole engine now is end to end. These helpers
/// are the bridge: whenever a selection-based edit touches a cel, its current content (baked image
/// + live strokes) gets flattened into a plain `UIImage` — see `Cel.bakedImage`.
enum PixelOps {
    static func transparentFormat(scale: CGFloat = 1) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        return format
    }

    static let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()

    /// A genuinely independent copy of `rect` out of `image`, in UIKit top-left coordinates.
    ///
    /// **Not** `CGImage.cropping(to:)`: that returns an image which keeps a reference to the original
    /// image's pixel data, so the parent buffer stays alive and a "crop" retains just as much memory
    /// as the whole thing. This renders into a fresh buffer of exactly `rect.size`, which is the
    /// entire point when the caller is shrinking what an undo step holds on to.
    ///
    /// `preferredRange = .standard` matters for the same reason: left at `.automatic`, a wide-colour
    /// device backs the new buffer with 16 bits per component and the patch costs twice what the
    /// caller's byte accounting says it does.
    ///
    /// Returns nil for an empty or fully out-of-bounds rect.
    static func copiedSubimage(of image: UIImage, in rect: CGRect) -> UIImage? {
        let bounds = CGRect(origin: .zero, size: image.size)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        let format = transparentFormat()
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: clamped.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -clamped.origin.x, y: -clamped.origin.y))
        }
    }

    static func uiColor(from color: Color, opacity: Double = 1.0) -> UIColor {
        color.resolvedUIColor(opacity: opacity)
    }

    /// Flattens a cel's fill-tool wash, baked raster content, and live strokes into one
    /// canvas-sized image — the full stack a select/move/fill-selection/clear op should treat as
    /// "the cel's pixels".
    /// `quality` reaches only the vector tier, which is the only one with a cheaper mode to offer:
    /// `RasterLayerTexture` has a single rendering. Defaulted to `.full` so the ~10 existing callers
    /// are unchanged — it is threaded through for `RenderRequest`, whose §9.1 contract is to carry a
    /// quality, and a quality the snapshot then ignored would be a field that lies.
    static func rasterize(cel: Cel, canvasSize: CGSize, quality: RenderQuality = .full) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let strokesImage = cel.raster.renderToUIImage()
        // A vector cel's live strokes/images live in `vector` (rendered to a native-res image),
        // not in `raster` — include it so fill, select/move, and cross-layer fill references treat
        // a vector layer's content as pixels just like a raster layer's.
        let vectorImage = cel.vector?.render(quality: quality)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { _ in
            cel.fillImage?.draw(in: bounds)
            cel.bakedImage?.draw(in: bounds)
            strokesImage.draw(in: bounds)
            vectorImage?.draw(in: bounds)
        }
    }

    /// Flattens every *visible* layer's content, bottom-to-top with each layer's own opacity, into
    /// one canvas-sized image — used for the gallery/project thumbnail so a multi-layer drawing
    /// shows the whole composited stack instead of just its bottom-most visible layer.
    static func compositeCanvas(layers: [Layer], atFrame frame: Int, canvasSize: CGSize) -> UIImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { _ in
            for layer in layers where layer.isVisible {
                guard let cel = layer.cels.first(where: { frame >= $0.startFrame && frame < $0.startFrame + $0.frameCount }) else { continue }
                rasterize(cel: cel, canvasSize: canvasSize).draw(in: bounds, blendMode: .normal, alpha: CGFloat(layer.opacity))
            }
        }
    }

    /// Finds the bounding rect (in point space, assuming scale 1 — which everything here renders at)
    /// of all non-transparent pixels in the image. Returns nil if the image has no visible content.
    ///
    /// Scans through an unsafe pointer rather than subscripting the array: this runs synchronously on
    /// the main thread when the Move tool engages, and a canvas-sized image is several million
    /// pixels — enough for the bounds-checked version to be a visible hang in a debug build.
    static func opaqueContentBounds(_ image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width * 4, space: deviceRGBColorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        pixels.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for y in 0..<height {
                let row = base + y * width * 4
                // Narrow the horizontal search to what's still unknown: once a row's pixels all sit
                // inside the running [minX, maxX] span they can't widen it, so only the edges matter.
                var x = 0
                var rowHasContent = false
                while x < width {
                    if row[x * 4 + 3] > 0 {
                        rowHasContent = true
                        if x < minX { minX = x }
                        break
                    }
                    x += 1
                }
                guard rowHasContent else { continue }
                var right = width - 1
                while right > maxX {
                    if row[right * 4 + 3] > 0 { maxX = right; break }
                    right -= 1
                }
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                      width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }

    /// Splits a canvas-sized image into the pixels inside `path` ("piece") and the same image with
    /// that region cleared to transparent ("remainder"), both still canvas-sized.
    static func maskedPiece(image: UIImage, path: CGPath) -> (piece: UIImage, remainder: UIImage) {
        let bounds = CGRect(origin: .zero, size: image.size)
        let format = transparentFormat()

        let piece = UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
            ctx.cgContext.saveGState()
            ctx.cgContext.addPath(path)
            ctx.cgContext.clip()
            image.draw(in: bounds)
            ctx.cgContext.restoreGState()
        }
        let remainder = UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
            image.draw(in: bounds)
            ctx.cgContext.setBlendMode(.clear)
            ctx.cgContext.addPath(path)
            ctx.cgContext.fillPath()
        }
        return (piece, remainder)
    }

    /// Crops a canvas-sized (scale-1) image to `rect`, in the same point space it was rendered at.
    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let pixelRect = CGRect(x: rect.origin.x * image.scale, y: rect.origin.y * image.scale,
                                width: rect.width * image.scale, height: rect.height * image.scale).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Renders a floating piece (with its live transform applied) into a canvas-sized image, ready
    /// to be composited over a target cel's baked image at commit time.
    static func render(floatingPiece piece: FloatingPiece, into canvasSize: CGSize) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { ctx in
            ctx.cgContext.saveGState()
            ctx.cgContext.concatenate(piece.transform.affineTransform)
            let half = CGSize(width: piece.baseSize.width / 2, height: piece.baseSize.height / 2)
            let drawRect = CGRect(x: -half.width, y: -half.height, width: piece.baseSize.width, height: piece.baseSize.height)
            piece.pieceImage.draw(in: drawRect)
            ctx.cgContext.restoreGState()
        }
    }

    /// A `newSize` copy of a canvas-sized image with its pixels re-placed at `offset` (canvas point
    /// space), used by the canvas-padding resize (see `CanvasManager.setCanvasPadding`) for a cel's
    /// `fillImage`/`bakedImage`. A positive offset (growing padding) keeps content centred; a negative
    /// one (shrinking) crops whatever falls outside the new bounds.
    static func resizedCanvasImage(_ image: UIImage, to newSize: CGSize, offset: CGPoint) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: newSize), format: transparentFormat())
        return renderer.image { _ in
            image.draw(in: CGRect(origin: offset, size: image.size))
        }
    }

    /// Flattens two canvas-sized layer images into one, each drawn at its own layer opacity — the
    /// pixel side of merging two layers together (see `CanvasManager.mergeLayers`).
    static func flatten(bottom: UIImage, bottomOpacity: Double, top: UIImage, topOpacity: Double, canvasSize: CGSize) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { _ in
            bottom.draw(in: bounds, blendMode: .normal, alpha: CGFloat(bottomOpacity))
            top.draw(in: bounds, blendMode: .normal, alpha: CGFloat(topOpacity))
        }
    }

    /// Draws `overlay` on top of `base` (or on transparent if `base` is nil), both canvas-sized.
    static func compositeOver(base: UIImage?, overlay: UIImage) -> UIImage {
        let bounds = CGRect(origin: .zero, size: overlay.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { _ in
            base?.draw(in: bounds)
            overlay.draw(in: bounds)
        }
    }

    /// Flat color fill inside `path`, composited over `base` (canvas-sized).
    static func fill(base: UIImage, path: CGPath, color: UIColor) -> UIImage {
        let bounds = CGRect(origin: .zero, size: base.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { ctx in
            base.draw(in: bounds)
            ctx.cgContext.setFillColor(color.cgColor)
            ctx.cgContext.addPath(path)
            ctx.cgContext.fillPath()
        }
    }

    /// Composites `overlay` over `base` (or over transparent if `base` is nil), but only inside
    /// `path` — pixels outside stay exactly as `base` was. Used to keep a brush/eraser stroke or a
    /// flood-fill result from touching pixels outside the active selection when outside interaction
    /// is denied (see `CanvasManager.allowsPaintingOutsideSelection`): `overlay` is the tentative
    /// result, `base` the pre-edit content, so anything drawn outside `path` is discarded rather than
    /// applied.
    static func maskedComposite(base: UIImage?, overlay: UIImage, insidePath path: CGPath) -> UIImage {
        let bounds = CGRect(origin: .zero, size: overlay.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { ctx in
            base?.draw(in: bounds)
            ctx.cgContext.saveGState()
            ctx.cgContext.addPath(path)
            ctx.cgContext.clip()
            overlay.draw(in: bounds)
            ctx.cgContext.restoreGState()
        }
    }

    /// Clears the pixels inside `path` to transparent, over `base` (canvas-sized).
    static func clear(base: UIImage, path: CGPath) -> UIImage {
        let bounds = CGRect(origin: .zero, size: base.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { ctx in
            base.draw(in: bounds)
            ctx.cgContext.setBlendMode(.clear)
            ctx.cgContext.addPath(path)
            ctx.cgContext.fillPath()
        }
    }

    // MARK: - Automatic (magic wand) selection

    private struct IntPoint: Hashable { var x: Int; var y: Int }

    /// Flood-fills from `point` (canvas point space) across pixels within `tolerance` (0...1 fraction
    /// of the 0-255 channel range) of the starting pixel's color, 4-connected, then traces the
    /// boundary of the filled region into a `CGPath` usable both for the marching-ants overlay and
    /// for masking. Runs against `image` rendered at scale 1, so pixel coordinates equal point
    /// coordinates.
    static func floodFillMask(image: UIImage, point: CGPoint, tolerance: Double) -> CGPath? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width * 4, space: deviceRGBColorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // `image` is a canvas-point-sized image rendered at scale 1, but its cgImage's pixel
        // dimensions can still differ slightly from the CGPoint-space width/height passed in via
        // `image.size` if scale != 1; since every caller here renders at scale 1, size == pixel count.
        let px = Int(point.x.rounded(.down)), py = Int(point.y.rounded(.down))
        guard px >= 0, px < width, py >= 0, py < height else { return nil }

        func colorAt(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
        }
        let target = colorAt(px, py)
        let tol = tolerance * 255.0
        func matches(_ x: Int, _ y: Int) -> Bool {
            let c = colorAt(x, y)
            return abs(Double(c.0 - target.0)) <= tol && abs(Double(c.1 - target.1)) <= tol &&
                   abs(Double(c.2 - target.2)) <= tol && abs(Double(c.3 - target.3)) <= tol
        }

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(px, py)]
        visited[py * width + px] = true
        while let (x, y) = stack.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let idx = ny * width + nx
                if !visited[idx], matches(nx, ny) {
                    visited[idx] = true
                    stack.append((nx, ny))
                }
            }
        }

        return contourPath(selected: visited, width: width, height: height)
    }

    /// Traces the boundary of a boolean pixel mask into a (possibly multi-loop) `CGPath`, by
    /// collecting every unit edge between a selected pixel and a non-selected neighbor and
    /// stitching those edges into closed loops. Enclosed unselected regions ("holes") fall out of
    /// this naturally as their own loop with opposite winding, so a nonzero-winding fill/clip
    /// correctly punches a hole for them.
    static func contourPath(selected: [Bool], width: Int, height: Int) -> CGPath? {
        func isSelected(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return selected[y * width + x]
        }

        var edges: [IntPoint: IntPoint] = [:]
        for y in 0..<height {
            for x in 0..<width where isSelected(x, y) {
                if !isSelected(x, y - 1) { edges[IntPoint(x: x, y: y)] = IntPoint(x: x + 1, y: y) }
                if !isSelected(x + 1, y) { edges[IntPoint(x: x + 1, y: y)] = IntPoint(x: x + 1, y: y + 1) }
                if !isSelected(x, y + 1) { edges[IntPoint(x: x + 1, y: y + 1)] = IntPoint(x: x, y: y + 1) }
                if !isSelected(x - 1, y) { edges[IntPoint(x: x, y: y + 1)] = IntPoint(x: x, y: y) }
            }
        }
        guard !edges.isEmpty else { return nil }

        let path = CGMutablePath()
        var remaining = edges
        while let start = remaining.keys.first {
            var loop: [IntPoint] = [start]
            var current = start
            while let next = remaining.removeValue(forKey: current) {
                current = next
                if current == start { break }
                loop.append(current)
            }
            guard loop.count > 2 else { continue }
            let simplified = simplifyCollinear(loop)
            let points = simplified.map { CGPoint(x: $0.x, y: $0.y) }
            path.addLines(between: points)
            path.closeSubpath()
        }
        return path
    }

    /// Drops points that lie on a straight run between their neighbors, so long straight edges of
    /// the flood-filled region become one segment instead of one point per pixel.
    private static func simplifyCollinear(_ points: [IntPoint]) -> [IntPoint] {
        let n = points.count
        guard n > 2 else { return points }
        var result: [IntPoint] = []
        for i in 0..<n {
            let prev = points[(i - 1 + n) % n]
            let curr = points[i]
            let next = points[(i + 1) % n]
            let d1x = curr.x - prev.x, d1y = curr.y - prev.y
            let d2x = next.x - curr.x, d2y = next.y - curr.y
            if d1x * d2y - d1y * d2x != 0 {
                result.append(curr)
            }
        }
        return result.isEmpty ? points : result
    }

    // MARK: - Fill mask to vector path

    /// Converts a premultiplied-last RGBA byte buffer (e.g. the output of `MetalFillSession.fill`)
    /// into a closed `CGPath` by thresholding the alpha channel to produce a boolean mask and then
    /// tracing its contour. Used to create `VectorFillElement` geometry from the GPU flood fill.
    static func pathFromAlphaMask(bytes: [UInt8], width: Int, height: Int) -> CGPath? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        let mask = (0..<(width * height)).map { bytes[$0 * 4 + 3] > 0 }
        return contourPath(selected: mask, width: width, height: height)
    }
}
