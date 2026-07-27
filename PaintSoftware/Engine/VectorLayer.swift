import UIKit
import CoreGraphics

/// One input sample of a vector stroke, in the stroke's own canvas-point space at draw time.
struct VectorSample: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var pressure: CGFloat
    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// A brush stroke stored as *geometry* (its input samples + the brush/color/size used), not baked
/// pixels. Because the pixels are produced on demand by re-stamping the brush along these samples
/// (see `VectorCanvas.render` → `BrushStamper`), a vector stroke can be moved/rotated/scaled and
/// re-rasterized at canvas-native resolution with no quality loss — the whole point of a vector
/// layer. Fully `Codable` so it persists as JSON rather than a flattened PNG.
struct VectorStroke: Identifiable, Codable {
    var id: UUID = UUID()
    var brush: Brush
    var color: CodableColor
    var size: CGFloat
    var opacity: Double
    var samples: [VectorSample]

    var uiColor: UIColor { UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha) }
}

/// A filled region stored as a vector path on a vector layer: the flood-fill tool's output when
/// used on a `.vector` layer, instead of rasterizing into `Cel.bakedImage`. The path is a closed
/// (possibly multi-loop, with holes) contour extracted from the GPU fill mask, stored as archived
/// `UIBezierPath` data for `Codable` conformance.
struct VectorFillElement: Identifiable, Codable {
    var id: UUID = UUID()
    /// Archiver data for the fill path (supports multi-subpath via UIBezierPath's NSSecureCoding).
    var pathData: Data
    var color: CodableColor
    /// Additional opacity multiplier on top of the color's own alpha (matches `VectorStroke.opacity`).
    var opacity: Double

    init(path: CGPath, color: CodableColor, opacity: Double = 1.0) {
        let bezier = UIBezierPath(cgPath: path)
        self.pathData = (try? NSKeyedArchiver.archivedData(withRootObject: bezier, requiringSecureCoding: true)) ?? Data()
        self.color = color
        self.opacity = opacity
    }

    var cgPath: CGPath? {
        guard let bezier = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIBezierPath.self, from: pathData) else { return nil }
        return bezier.cgPath
    }

    var uiColor: UIColor {
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

/// An imported image placed on a vector layer, movable/scalable/rotatable via its own transform
/// (position/scale/rotation in canvas space) — the same idea as the existing object layer, but as
/// one of possibly many elements on a vector layer rather than a whole dedicated layer. `image` is
/// runtime-only; persistence stores a file name + the transform (see `ProjectStore`). Shapes and
/// (eventually) video are further element kinds that slot in here the same way.
struct VectorImageElement: Identifiable {
    var id: UUID = UUID()
    var image: UIImage
    var transform: LayerTransform
    /// Set once the element has been persisted, so save can reuse the same file.
    var fileName: String?
}

/// The vector content of one cel on a `.vector` layer: strokes + placed images, plus one overall
/// affine transform applied to the whole set. A class (like `RasterLayerTexture`) because it's a
/// persistent mutable buffer the drawing surface stamps into; renders on demand to a canvas-native
/// `UIImage` that is displayed with nearest-neighbor magnification, so it still looks pixelated when
/// zoomed in (matching raster layers) even though the source is resolution-independent.
final class VectorCanvas {
    let size: CGSize
    var strokes: [VectorStroke]
    var fills: [VectorFillElement]
    var images: [VectorImageElement]
    /// Move/rotate/scale of the entire layer's content, applied at render time so it stays crisp at
    /// any transform (no resolution loss). Identity until the layer is transformed.
    var transform: CGAffineTransform

    private(set) var version: Int = 0
    private var cachedImage: UIImage?

    init(size: CGSize, strokes: [VectorStroke] = [], fills: [VectorFillElement] = [], images: [VectorImageElement] = [], transform: CGAffineTransform = .identity) {
        self.size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        self.strokes = strokes
        self.fills = fills
        self.images = images
        self.transform = transform
    }

    static func empty(size: CGSize) -> VectorCanvas { VectorCanvas(size: size) }

    var isEmpty: Bool { strokes.isEmpty && fills.isEmpty && images.isEmpty }

    func makeCopy() -> VectorCanvas {
        VectorCanvas(size: size, strokes: strokes, fills: fills, images: images, transform: transform)
    }

    /// A new canvas sized to `newSize` with all content shifted by `offset` (canvas point space),
    /// used by the canvas-padding resize (see `CanvasManager.setCanvasPadding`). Lossless: because
    /// `render()` applies the overall `transform` *after* drawing local content, appending a
    /// translation to `transform` shifts the whole rendered result by `offset` with no resampling —
    /// the stored strokes/images (in local space) are untouched. `size` is immutable, so this returns
    /// a fresh instance.
    func resized(to newSize: CGSize, offset: CGPoint) -> VectorCanvas {
        let shifted = transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        return VectorCanvas(size: newSize, strokes: strokes, fills: fills, images: images, transform: shifted)
    }

    private func invalidate() {
        version += 1
        cachedImage = nil
    }

    /// Invalidates the render cache after a direct mutation of `strokes`/`images` (e.g. undo/redo
    /// restoring a snapshot, which assigns the array wholesale rather than going through `addStroke`).
    func bumpVersion() { invalidate() }

    // MARK: - Mutation

    func addStroke(_ stroke: VectorStroke) {
        strokes.append(stroke)
        invalidate()
    }

    func addImage(_ element: VectorImageElement) {
        images.append(element)
        invalidate()
    }

    func addFill(_ element: VectorFillElement) {
        fills.append(element)
        invalidate()
    }

    func setTransform(_ t: CGAffineTransform) {
        transform = t
        invalidate()
    }

    /// The overall transform expressed as a `LayerTransform` (position/uniform-scale/rotation) about
    /// the canvas center, for driving the on-canvas transform overlay (which speaks `LayerTransform`,
    /// same as object layers). Assumes `transform` is a translate·rotate·uniform-scale (which is all
    /// the overlay can produce), so it decomposes cleanly.
    func layerTransform(canvasCenter: CGPoint) -> LayerTransform {
        let scale = hypot(transform.a, transform.b)
        return LayerTransform(position: canvasCenter.applying(transform),
                              scale: scale == 0 ? 1 : scale,
                              rotation: atan2(transform.b, transform.a))
    }

    /// Inverse of `layerTransform(canvasCenter:)`: builds the affine that maps content drawn at the
    /// canvas origin so its center lands at `t.position`, rotated/scaled about that center.
    static func affine(from t: LayerTransform, canvasCenter: CGPoint) -> CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: t.position.x, y: t.position.y)
            .rotated(by: t.rotation)
            .scaledBy(x: t.scale, y: t.scale)
            .translatedBy(x: -canvasCenter.x, y: -canvasCenter.y)
    }

    /// Splits/erases vector strokes along an eraser path: any stroke sample within `radius` of any
    /// eraser point is cut, and each surviving contiguous run of samples becomes its own stroke — so
    /// erasing through the middle of a stroke leaves two strokes, exactly like a vector eraser (not a
    /// raster hole). Returns true if anything changed. Eraser input is in canvas space, so points are
    /// mapped back through the layer transform first to compare against stored (untransformed) samples.
    @discardableResult
    func erase(alongPath eraserPoints: [CGPoint], radius: CGFloat) -> Bool {
        guard !eraserPoints.isEmpty, !strokes.isEmpty else { return false }
        let inverse = transform.inverted()
        let localEraser = eraserPoints.map { $0.applying(inverse) }
        let r2 = radius * radius
        func isErased(_ s: VectorSample) -> Bool {
            let p = s.point
            for e in localEraser {
                let dx = p.x - e.x, dy = p.y - e.y
                if dx * dx + dy * dy <= r2 { return true }
            }
            return false
        }

        var changed = false
        var result: [VectorStroke] = []
        for stroke in strokes {
            var runs: [[VectorSample]] = []
            var current: [VectorSample] = []
            for sample in stroke.samples {
                if isErased(sample) {
                    if !current.isEmpty { runs.append(current); current = [] }
                    changed = true
                } else {
                    current.append(sample)
                }
            }
            if !current.isEmpty { runs.append(current) }
            if runs.count == 1 && runs[0].count == stroke.samples.count {
                result.append(stroke) // untouched
            } else {
                for run in runs where run.count >= 1 {
                    var piece = stroke
                    piece.id = UUID()
                    piece.samples = run
                    result.append(piece)
                }
            }
        }
        if changed {
            strokes = result
            invalidate()
        }
        return changed
    }

    // MARK: - Rendering

    /// Rasterizes all content to a canvas-native `UIImage` (cached by `version`). Strokes are stamped
    /// via `BrushStamper` (identical to how they'd draw live); images are drawn with their transforms;
    /// then the whole thing is drawn through the overall `transform`. Always native resolution — the
    /// displaying image view magnifies it nearest-neighbor, so it stays pixelated when zoomed.
    func render() -> UIImage {
        if let cachedImage { return cachedImage }
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1

        // 1. Content in local (untransformed) space.
        let content = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            // Fills (flat color regions) — drawn first, underneath images and strokes.
            for fill in fills {
                guard let path = fill.cgPath else { continue }
                ctx.cgContext.setFillColor(fill.uiColor.cgColor)
                ctx.cgContext.setAlpha(fill.opacity)
                ctx.cgContext.addPath(path)
                ctx.cgContext.fillPath()
            }
            ctx.cgContext.setAlpha(1.0)
            for element in images {
                ctx.cgContext.saveGState()
                let t = element.transform
                ctx.cgContext.translateBy(x: t.position.x, y: t.position.y)
                ctx.cgContext.rotate(by: t.rotation)
                ctx.cgContext.scaleBy(x: t.scale, y: t.scale)
                let imgSize = element.image.size
                element.image.draw(in: CGRect(x: -imgSize.width / 2, y: -imgSize.height / 2, width: imgSize.width, height: imgSize.height))
                ctx.cgContext.restoreGState()
            }
            if !strokes.isEmpty {
                let raster = RasterLayerTexture.empty(size: size)
                for stroke in strokes {
                    let samples = stroke.samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
                    BrushStamper.stampStroke(into: raster, samples: samples, brush: stroke.brush,
                                             color: stroke.uiColor, brushSize: stroke.size, brushOpacity: stroke.opacity)
                }
                raster.renderToUIImage().draw(in: bounds)
            }
        }

        // 2. Apply the overall transform (identity → skip the extra pass).
        let final: UIImage
        if transform.isIdentity {
            final = content
        } else {
            final = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                ctx.cgContext.concatenate(transform)
                content.draw(in: bounds)
            }
        }
        cachedImage = final
        return final
    }
}

// MARK: - Persistence payload

/// Codable snapshot of a `VectorCanvas` for saving as JSON alongside the project. Images are stored
/// by file name (their PNGs are written separately by `ProjectStore`); strokes are stored inline.
struct VectorCanvasData: Codable {
    struct ImageRef: Codable {
        var fileName: String
        var x: Double
        var y: Double
        var scale: Double
        var rotation: Double
    }
    var strokes: [VectorStroke]
    var fills: [VectorFillElement]
    var images: [ImageRef]
    /// Overall transform as [a, b, c, d, tx, ty]; missing/short → identity.
    var transform: [Double]

    init(from canvas: VectorCanvas, imageFileNames: [UUID: String]) {
        strokes = canvas.strokes
        fills = canvas.fills
        images = canvas.images.compactMap { el in
            guard let name = el.fileName ?? imageFileNames[el.id] else { return nil }
            return ImageRef(fileName: name, x: el.transform.position.x, y: el.transform.position.y,
                            scale: el.transform.scale, rotation: el.transform.rotation)
        }
        let t = canvas.transform
        transform = [Double(t.a), Double(t.b), Double(t.c), Double(t.d), Double(t.tx), Double(t.ty)]
    }

    var affineTransform: CGAffineTransform {
        guard transform.count == 6 else { return .identity }
        return CGAffineTransform(a: CGFloat(transform[0]), b: CGFloat(transform[1]), c: CGFloat(transform[2]),
                                 d: CGFloat(transform[3]), tx: CGFloat(transform[4]), ty: CGFloat(transform[5]))
    }
}
