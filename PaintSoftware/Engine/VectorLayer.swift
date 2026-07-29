import UIKit
import CoreGraphics

extension CodableColor {
    /// The stored components as a `UIColor`. One definition rather than the same four-argument
    /// initialiser repeated at every call site.
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
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

    var uiColor: UIColor { color.uiColor }
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
    /// When true the path is rendered with the even-odd fill rule (used for clear-selection holes).
    var evenOddFill: Bool = false

    init(path: CGPath, color: CodableColor, opacity: Double = 1.0, evenOddFill: Bool = false) {
        let bezier = UIBezierPath(cgPath: path)
        self.pathData = (try? NSKeyedArchiver.archivedData(withRootObject: bezier, requiringSecureCoding: true)) ?? Data()
        self.color = color
        self.opacity = opacity
        self.evenOddFill = evenOddFill
    }

    var cgPath: CGPath? {
        guard let bezier = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIBezierPath.self, from: pathData) else { return nil }
        return bezier.cgPath
    }

    var uiColor: UIColor { color.uiColor }
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

    /// Guards `_strokes`/`_fills`/`_images`/`_transform` and `cachedImage`. Live drawing mutates this
    /// canvas on the main thread, but `render()` is reached from a background queue — the interactive
    /// fill's reference composite goes through `PixelOps.rasterize(cel:)`, which renders a vector
    /// cel's content off-main exactly as it reads a raster cel's `RasterLayerTexture`. Without this,
    /// a stroke landing on a layer mid-fill mutates the `strokes` array's buffer while the background
    /// thread is concurrently iterating it — a real data race on a heap-allocated array, not a
    /// hypothetical one.
    ///
    /// This deliberately mirrors `RasterLayerTexture`'s lock rather than making `VectorCanvas` an
    /// actor: an actor turns every call site async, and the call sites are spread through
    /// `CanvasView`/`CanvasManager`. Same trade-off, same lock type, same placement — taken at method
    /// entry and released via `defer`.
    ///
    /// As there, the private helpers (`invalidate()`, `renderLocalContent()`, and the three static
    /// geometry mappers) are only ever called from a method that already holds this lock, so they
    /// don't lock themselves — otherwise this non-reentrant lock would deadlock. The stored-property
    /// accessors below are the public seam: they lock, so every existing call site
    /// (`canvas.strokes = snapshot`, `vector.images`, `cel.vector?.strokes.count`) stays unchanged
    /// and becomes safe, while code inside the class uses the `_`-prefixed backing storage directly.
    private let lock = NSLock()

    private var _strokes: [VectorStroke]
    private var _fills: [VectorFillElement]
    private var _images: [VectorImageElement]
    private var _transform: CGAffineTransform

    var strokes: [VectorStroke] {
        get { lock.lock(); defer { lock.unlock() }; return _strokes }
        set { lock.lock(); defer { lock.unlock() }; _strokes = newValue }
    }

    var fills: [VectorFillElement] {
        get { lock.lock(); defer { lock.unlock() }; return _fills }
        set { lock.lock(); defer { lock.unlock() }; _fills = newValue }
    }

    var images: [VectorImageElement] {
        get { lock.lock(); defer { lock.unlock() }; return _images }
        set { lock.lock(); defer { lock.unlock() }; _images = newValue }
    }

    /// Move/rotate/scale of the entire layer's content, applied at render time so it stays crisp at
    /// any transform (no resolution loss). Identity until the layer is transformed.
    var transform: CGAffineTransform {
        get { lock.lock(); defer { lock.unlock() }; return _transform }
        set { lock.lock(); defer { lock.unlock() }; _transform = newValue }
    }

    private(set) var version: Int = 0
    private var cachedImage: UIImage?

    init(size: CGSize, strokes: [VectorStroke] = [], fills: [VectorFillElement] = [], images: [VectorImageElement] = [], transform: CGAffineTransform = .identity) {
        self.size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        // Assigns the backing storage directly: `init` runs before the instance is shared with any
        // other thread, so there is nothing to lock against yet (as in `RasterLayerTexture.init`).
        self._strokes = strokes
        self._fills = fills
        self._images = images
        self._transform = transform
    }

    static func empty(size: CGSize) -> VectorCanvas { VectorCanvas(size: size) }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _strokes.isEmpty && _fills.isEmpty && _images.isEmpty
    }

    func makeCopy() -> VectorCanvas {
        lock.lock()
        defer { lock.unlock() }
        // The new instance has its own lock and isn't shared yet, so constructing it under this one
        // can't deadlock — and taking the lock is what makes the copy a coherent snapshot of all
        // four properties rather than a mix of pre- and post-mutation state.
        return VectorCanvas(size: size, strokes: _strokes, fills: _fills, images: _images, transform: _transform)
    }

    /// A new canvas sized to `newSize` with all content shifted by `offset` (canvas point space),
    /// used by the canvas-padding resize (see `CanvasManager.setCanvasPadding`). Lossless: because
    /// `render()` applies the overall `transform` *after* drawing local content, appending a
    /// translation to `transform` shifts the whole rendered result by `offset` with no resampling —
    /// the stored strokes/images (in local space) are untouched. `size` is immutable, so this returns
    /// a fresh instance.
    func resized(to newSize: CGSize, offset: CGPoint) -> VectorCanvas {
        lock.lock()
        defer { lock.unlock() }
        let shifted = _transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        return VectorCanvas(size: newSize, strokes: _strokes, fills: _fills, images: _images, transform: shifted)
    }

    /// Caller must hold `lock`.
    private func invalidate() {
        version += 1
        cachedImage = nil
    }

    /// Invalidates the render cache after a direct mutation of `strokes`/`images` (e.g. undo/redo
    /// restoring a snapshot, which assigns the array wholesale rather than going through `addStroke`).
    func bumpVersion() {
        lock.lock()
        defer { lock.unlock() }
        invalidate()
    }

    // MARK: - Mutation

    func addStroke(_ stroke: VectorStroke) {
        lock.lock()
        defer { lock.unlock() }
        _strokes.append(stroke)
        invalidate()
    }

    /// Adds a stroke whose samples were captured in **canvas** space — a live drag, or a smart
    /// shape's collapsed outline — mapping both its geometry and its width into this canvas's local
    /// space. See `addFill(canvasSpacePath:...)`: stored content is local-space and `render()`
    /// applies `transform` on top, so storing canvas-space samples verbatim puts the stroke through
    /// the transform twice and lands it away from where it was drawn, again with every later move.
    func addStroke(canvasSpaceStroke stroke: VectorStroke) {
        lock.lock()
        defer { lock.unlock() }
        guard !_transform.isIdentity else {
            _strokes.append(stroke)
            return invalidate()
        }
        var mapped = stroke
        mapped.samples = Self.localSamples(stroke.samples, through: _transform)
        // Width is a canvas-space measurement too: `render()` scales the stamped result by the
        // transform, so a stroke drawn at N points on a layer scaled by k must be stored at N/k to
        // come back out N points wide.
        let scale = Self.scale(of: _transform)
        if scale > 0 { mapped.size = stroke.size / scale }
        _strokes.append(mapped)
        invalidate()
    }

    /// Uniform scale factor of the overall `transform` (the overlay only ever produces
    /// translate·rotate·uniform-scale, so one number describes it).
    var transformScale: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return Self.scale(of: _transform)
    }

    /// Maps canvas-space stroke samples into this canvas's local (pre-`transform`) space, preserving
    /// pressure. The point-wise counterpart of `localPath(fromCanvas:)`.
    func localSamples(fromCanvas samples: [VectorSample]) -> [VectorSample] {
        lock.lock()
        defer { lock.unlock() }
        return Self.localSamples(samples, through: _transform)
    }

    // The geometry mappers are static functions of the transform they're given rather than methods
    // reading `_transform`, so a locked method can call them while holding the lock without any
    // chance of re-entering it — the reason the public wrappers above are thin.

    private static func scale(of t: CGAffineTransform) -> CGFloat { hypot(t.a, t.b) }

    private static func localSamples(_ samples: [VectorSample], through t: CGAffineTransform) -> [VectorSample] {
        guard !t.isIdentity else { return samples }
        let inverse = t.inverted()
        return samples.map {
            let p = $0.point.applying(inverse)
            return VectorSample(x: p.x, y: p.y, pressure: $0.pressure)
        }
    }

    private static func localPath(_ path: CGPath, through t: CGAffineTransform) -> CGPath {
        guard !t.isIdentity else { return path }
        var inverse = t.inverted()
        return path.copy(using: &inverse) ?? path
    }

    func addImage(_ element: VectorImageElement) {
        lock.lock()
        defer { lock.unlock() }
        _images.append(element)
        invalidate()
    }

    func addFill(_ element: VectorFillElement) {
        lock.lock()
        defer { lock.unlock() }
        _fills.append(element)
        invalidate()
    }

    /// Adds a fill whose path was captured in **canvas** space — where the flood-fill mask, the
    /// lasso, and every other on-screen path are measured — mapping it into this canvas's own local
    /// space first.
    ///
    /// `renderLocalContent` draws `fills` untransformed and `render()` then applies `transform` on
    /// top, so storing a canvas-space path verbatim puts the fill through `transform` a second time:
    /// on any layer that has ever been moved, the filled region lands detached from the contour it
    /// was poured into, and shifts again with every subsequent move. `erase(alongPath:)` already
    /// maps its input the same way; this exists so the fill paths can't drift back out of step.
    func addFill(canvasSpacePath path: CGPath, color: CodableColor, opacity: Double = 1.0, evenOddFill: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        _fills.append(VectorFillElement(path: Self.localPath(path, through: _transform), color: color,
                                        opacity: opacity, evenOddFill: evenOddFill))
        invalidate()
    }

    /// Maps a canvas-space path into this canvas's local (pre-`transform`) space — see
    /// `addFill(canvasSpacePath:...)` for why every stored path must be in local space.
    func localPath(fromCanvas path: CGPath) -> CGPath {
        lock.lock()
        defer { lock.unlock() }
        return Self.localPath(path, through: _transform)
    }

    func setTransform(_ t: CGAffineTransform) {
        lock.lock()
        defer { lock.unlock() }
        _transform = t
        invalidate()
    }

    /// The overall transform expressed as a `LayerTransform` (position/uniform-scale/rotation) about
    /// `pivot` — a fixed point in the content's own local (untransformed) space, typically its
    /// content bounding box's center rather than the canvas center, so the Move tool's on-canvas box
    /// tracks the actual content instead of the whole canvas. Assumes `transform` is a
    /// translate·rotate·uniform-scale (which is all the overlay can produce), so it decomposes cleanly.
    func layerTransform(pivot: CGPoint) -> LayerTransform {
        lock.lock()
        defer { lock.unlock() }
        let scale = Self.scale(of: _transform)
        return LayerTransform(position: pivot.applying(_transform),
                              scale: scale == 0 ? 1 : scale,
                              rotation: atan2(_transform.b, _transform.a))
    }

    /// Inverse of `layerTransform(pivot:)`: builds the affine that maps content drawn at `pivot` so
    /// its center lands at `t.position`, rotated/scaled about that center. `pivot` must be the same
    /// fixed point used to derive `t` via `layerTransform(pivot:)`.
    static func affine(from t: LayerTransform, pivot: CGPoint) -> CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: t.position.x, y: t.position.y)
            .rotated(by: t.rotation)
            .scaledBy(x: t.scale, y: t.scale)
            .translatedBy(x: -pivot.x, y: -pivot.y)
    }

    /// Bounding box of the layer's own content (strokes/fills/images) in its local, untransformed
    /// coordinate space — i.e. where it sits before `transform` is applied. Nil if there's no
    /// visible content. Used to size/pivot the Move tool's on-canvas box to the actual content
    /// rather than the whole canvas.
    func localContentBounds() -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return PixelOps.opaqueContentBounds(renderLocalContent())
    }

    /// Splits/erases vector strokes along an eraser path: any stroke sample within `radius` of any
    /// eraser point is cut, and each surviving contiguous run of samples becomes its own stroke — so
    /// erasing through the middle of a stroke leaves two strokes, exactly like a vector eraser (not a
    /// raster hole). Returns true if anything changed. Eraser input is in canvas space, so points are
    /// mapped back through the layer transform first to compare against stored (untransformed) samples.
    @discardableResult
    func erase(alongPath eraserPoints: [CGPoint], radius: CGFloat) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !eraserPoints.isEmpty, !_strokes.isEmpty else { return false }
        let inverse = _transform.inverted()
        let localEraser = eraserPoints.map { $0.applying(inverse) }
        // The radius is a canvas-space measurement like the points, so it has to be brought into
        // local space alongside them — otherwise erasing a scaled-up layer cuts a nib-sized hole
        // where the user swept a wide one (or vice versa).
        let scale = Self.scale(of: _transform)
        let localRadius = scale > 0 ? radius / scale : radius
        let r2 = localRadius * localRadius
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
        for stroke in _strokes {
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
            _strokes = result
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
        lock.lock()
        defer { lock.unlock() }
        if let cachedImage { return cachedImage }
        let bounds = CGRect(origin: .zero, size: size)
        let format = PixelOps.transparentFormat()

        // 1. Content in local (untransformed) space.
        let content = renderLocalContent()

        // 2. Apply the overall transform (identity → skip the extra pass).
        let final: UIImage
        if _transform.isIdentity {
            final = content
        } else {
            final = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                ctx.cgContext.concatenate(_transform)
                content.draw(in: bounds)
            }
        }
        cachedImage = final
        return final
    }

    /// Just step 1 of `render()`: the layer's own content stamped at native resolution, before the
    /// overall `transform` is applied. Not cached — only called from `render()` (once per
    /// invalidation) and `localContentBounds()` (once per Move-tool overlay refresh).
    ///
    /// Caller must hold `lock`. Note this means a rasterization holds the lock for its whole
    /// duration, so a main-thread stroke can briefly block behind a background render — the same
    /// trade-off `RasterLayerTexture.renderToUIImage()` already makes, and the cache means it happens
    /// at most once per change. Strokes are stamped straight into this renderer's own context via
    /// `CGContextDabTarget`, which holds no lock of its own and cannot re-enter this one.
    ///
    /// It used to allocate a throwaway `RasterLayerTexture` here, stamp into that, `makeImage()` a
    /// second canvas-sized copy out of it, and blit that in — a canvas-sized CGContext plus a
    /// canvas-sized CGImage (~16 MB each at 2048², ~64 MB at 4000²) per visible vector layer per
    /// invalidation, both immediately discarded, plus a lock acquisition per dab on the scratch
    /// texture. Stamping direct removes all of it.
    ///
    /// **Why the transparency layer.** Dropping the intermediate is not unconditionally
    /// behaviour-preserving. The scratch texture isolated the strokes: they blended against each
    /// other on transparent, and only the finished result was composited over the fills and images.
    /// Stamping into this context instead exposes each dab to whatever is already underneath. For
    /// `.normal` that is provably identical — source-over is associative, so
    /// `(dab₂ over dab₁) over backdrop` equals `dab₂ over (dab₁ over backdrop)` — but a brush set to
    /// multiply/screen/darken/lighten would start blending with the fills and images beneath it and
    /// visibly change the render. So when any stroke carries a non-normal blend mode the strokes go
    /// into a transparency layer, which restores exactly the isolation the scratch texture provided
    /// (one group for all strokes, composited once, source-over — the outer blend mode and alpha are
    /// `.normal`/1 at that point, matching the old `draw(in:)`). The common all-normal case pays
    /// nothing for it.
    private func renderLocalContent() -> UIImage {
        // `.standard` is not a detail — it is load-bearing, and measuring 5.3 is what found it.
        // `UIGraphicsImageRendererFormat.preferredRange` defaults to `.automatic`, which on a
        // wide-colour iPad backs the context with an extended-range 16-bit-per-component bitmap.
        // That was invisible while the dabs went into a scratch `RasterLayerTexture` (an explicit
        // 8-bit deviceRGB context) and only the finished image was drawn in. Stamping thousands of
        // radial gradients directly into an extended-range context instead measured **155 ms
        // against the old 70 ms** — the memory win would have shipped with a 2.2x wall-clock
        // regression behind it. Pinning standard range puts dab rasterization back on the same 8-bit
        // path `RasterLayerTexture` uses and brings it to 62 ms, i.e. faster than before as well as
        // lighter.
        //
        // No fidelity is lost relative to what this app actually delivers: every raster tier already
        // renders and persists as 8-bit deviceRGB (`RasterLayerTexture.ensureContext`,
        // `PixelOps.deviceRGBColorSpace`, the cel PNGs), and the strokes here were being stamped
        // into an 8-bit texture before this change regardless. A wide-gamut imported image is the
        // one thing that previously kept extended range through this pass, and it was clipped
        // downstream anyway the moment it was composited or saved.
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            // Fills (flat color regions) — drawn first, underneath images and strokes.
            for fill in _fills {
                guard let path = fill.cgPath else { continue }
                ctx.cgContext.setFillColor(fill.uiColor.cgColor)
                ctx.cgContext.setAlpha(fill.opacity)
                ctx.cgContext.addPath(path)
                if fill.evenOddFill {
                    ctx.cgContext.fillPath(using: .evenOdd)
                } else {
                    ctx.cgContext.fillPath()
                }
            }
            ctx.cgContext.setAlpha(1.0)
            for element in _images {
                ctx.cgContext.saveGState()
                let t = element.transform
                ctx.cgContext.translateBy(x: t.position.x, y: t.position.y)
                ctx.cgContext.rotate(by: t.rotation)
                ctx.cgContext.scaleBy(x: t.scale, y: t.scale)
                let imgSize = element.image.size
                element.image.draw(in: CGRect(x: -imgSize.width / 2, y: -imgSize.height / 2, width: imgSize.width, height: imgSize.height))
                ctx.cgContext.restoreGState()
            }
            if !_strokes.isEmpty {
                let needsIsolation = _strokes.contains { $0.brush.blendMode != .normal }
                if needsIsolation { ctx.cgContext.beginTransparencyLayer(auxiliaryInfo: nil) }
                let target = CGContextDabTarget(ctx.cgContext)
                for stroke in _strokes {
                    let samples = stroke.samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
                    BrushStamper.stampStroke(into: target, samples: samples, brush: stroke.brush,
                                             color: stroke.uiColor, brushSize: stroke.size, brushOpacity: stroke.opacity)
                }
                if needsIsolation { ctx.cgContext.endTransparencyLayer() }
            }
        }
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strokes = try c.decode([VectorStroke].self, forKey: .strokes)
        fills = try c.decode([VectorFillElement].self, forKey: .fills)
        images = try c.decode([ImageRef].self, forKey: .images)
        transform = try c.decode([Double].self, forKey: .transform)
    }

    var affineTransform: CGAffineTransform {
        guard transform.count == 6 else { return .identity }
        return CGAffineTransform(a: CGFloat(transform[0]), b: CGFloat(transform[1]), c: CGFloat(transform[2]),
                                 d: CGFloat(transform[3]), tx: CGFloat(transform[4]), ty: CGFloat(transform[5]))
    }
}
