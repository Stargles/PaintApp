import UIKit
import CoreGraphics

extension CodableColor {
    /// The stored components as a `UIColor`. One definition rather than the same four-argument
    /// initialiser repeated at every call site.
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}

/// Whether a `VectorStroke` *adds* ink or *removes* it.
///
/// The eraser being a mode on `VectorStroke` rather than its own element type is deliberate: an
/// eraser is structurally a polyline with pressure and width, so interpolation, liquify and point
/// decimation all get it for free from the one implementation they already have for paint strokes.
/// See VECTOR_ERASER_PLAN.md §2.1.
enum StrokeComposite: String, Codable {
    case paint
    case erase
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
    /// `.erase` routes this stroke through `BrushStamper.stampStroke(..., isEraser: true)` at render
    /// time — the same shape/hardness/dynamics/grain pipeline as a paint stroke, composited
    /// `.destinationOut` — so it punches a hole in everything beneath it in the display list.
    ///
    /// The property default only covers *construction*. Decoding needs the explicit `init(from:)`
    /// below: Swift's synthesized `Decodable` deliberately ignores property defaults and throws
    /// `keyNotFound` on a missing key, which would make every project saved before this field
    /// existed fail to load.
    var composite: StrokeComposite = .paint

    var uiColor: UIColor { color.uiColor }

    /// Spelled out rather than left to synthesis so the hand-written `init(from:)` below can name the
    /// keys. A nested type in the body is fine — unlike an `init`, it does not suppress the
    /// synthesized memberwise initialiser that every construction site here uses.
    enum CodingKeys: String, CodingKey {
        case id, brush, color, size, opacity, samples, composite
    }
}

/// `init(from:)`/`encode(to:)` live in an extension for one specific reason: declaring *any*
/// initialiser inside the struct body would suppress the memberwise initialiser, and every call site
/// in the app builds a `VectorStroke` memberwise (`StrokeCanvasView.endVectorStroke`,
/// `CanvasManager+Shape.bakeShape`, the tests). A struct can satisfy `Decodable` from an extension —
/// the requirement is only `required` for classes — so this keeps both.
extension VectorStroke {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        brush = try c.decode(Brush.self, forKey: .brush)
        color = try c.decode(CodableColor.self, forKey: .color)
        size = try c.decode(CGFloat.self, forKey: .size)
        opacity = try c.decode(Double.self, forKey: .opacity)
        samples = try c.decode([VectorSample].self, forKey: .samples)
        // The whole point of the hand-written decoder: absent key → `.paint`, so legacy files load.
        composite = try c.decodeIfPresent(StrokeComposite.self, forKey: .composite) ?? .paint
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(brush, forKey: .brush)
        try c.encode(color, forKey: .color)
        try c.encode(size, forKey: .size)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(samples, forKey: .samples)
        try c.encode(composite, forKey: .composite)
    }
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

/// One entry in a `VectorCanvas`'s display list.
///
/// Replaces the three parallel `strokes`/`fills`/`images` arrays that were drawn in a fixed
/// fills→images→strokes order. That fixed order cannot express z-position, and z-position is exactly
/// what an eraser needs: an `.erase` stroke lowers the alpha of everything *beneath it in this list*,
/// so if erasers could only ever be appended last, a stroke drawn after an erase would be eaten by
/// it. See VECTOR_ERASER_PLAN.md §2.2.
///
/// Not `Codable`: `.image`'s payload holds a runtime `UIImage`. Persistence has its own ordered
/// representation that stores images by file name — see `VectorCanvasData.ElementData`.
enum VectorElement: Identifiable {
    case stroke(VectorStroke)
    case fill(VectorFillElement)
    case image(VectorImageElement)

    var id: UUID {
        switch self {
        case .stroke(let stroke): return stroke.id
        case .fill(let fill): return fill.id
        case .image(let image): return image.id
        }
    }

    var stroke: VectorStroke? {
        if case .stroke(let stroke) = self { return stroke }
        return nil
    }

    var fill: VectorFillElement? {
        if case .fill(let fill) = self { return fill }
        return nil
    }

    var image: VectorImageElement? {
        if case .image(let image) = self { return image }
        return nil
    }
}

/// The vector content of one cel on a `.vector` layer: strokes + placed images, plus one overall
/// affine transform applied to the whole set. A class (like `RasterLayerTexture`) because it's a
/// persistent mutable buffer the drawing surface stamps into; renders on demand to a canvas-native
/// `UIImage` that is displayed with nearest-neighbor magnification, so it still looks pixelated when
/// zoomed in (matching raster layers) even though the source is resolution-independent.
final class VectorCanvas {
    let size: CGSize

    /// Guards `_elements`/`_transform` and `cachedImage`. Live drawing mutates this
    /// canvas on the main thread, but `render()` is reached from a background queue — the interactive
    /// fill's reference composite goes through `PixelOps.rasterize(cel:)`, which renders a vector
    /// cel's content off-main exactly as it reads a raster cel's `RasterLayerTexture`. Without this,
    /// a stroke landing on a layer mid-fill mutates the element array's buffer while the background
    /// thread is concurrently iterating it — a real data race on a heap-allocated array, not a
    /// hypothetical one.
    ///
    /// This deliberately mirrors `RasterLayerTexture`'s lock rather than making `VectorCanvas` an
    /// actor: an actor turns every call site async, and the call sites are spread through
    /// `CanvasView`/`CanvasManager`. Same trade-off, same lock type, same placement — taken at method
    /// entry and released via `defer`.
    ///
    /// As there, the private helpers (`invalidate()`, `renderLocalContent()`, and every `static`
    /// helper below — the geometry mappers, the display-list splice/ordering helpers and the drawing
    /// helpers) are only ever called from a method that already holds this lock, so they don't lock
    /// themselves — otherwise this non-reentrant lock would deadlock. **Anything added here follows
    /// that rule: a private helper never takes the lock, and `static` is how the ones that only need
    /// data passed in are kept structurally incapable of re-entering it.** The stored-property
    /// accessors below are the public seam: they lock, so every existing call site
    /// (`canvas.strokes = snapshot`, `vector.images`, `cel.vector?.strokes.count`) stays unchanged
    /// and becomes safe, while code inside the class uses the `_`-prefixed backing storage directly.
    private let lock = NSLock()

    /// The one z-ordered display list, drawn back to front. Replaces the three parallel arrays; see
    /// `VectorElement` for why, and `renderLocalContent()` for how it is walked.
    private var _elements: [VectorElement]
    private var _transform: CGAffineTransform

    /// The display list itself. The seam later phases (eraser modes, liquify, decimation) work
    /// through; existing code keeps using the three kind-filtered accessors below.
    var elements: [VectorElement] {
        get { lock.lock(); defer { lock.unlock() }; return _elements }
        set { lock.lock(); defer { lock.unlock() }; _elements = newValue }
    }

    // MARK: - Kind-filtered compatibility accessors
    //
    // These keep ~30 call sites across the app and test suite compiling and behaving unchanged. The
    // getters filter the display list; the setters splice.
    //
    // **Setter contract.** Remove every element of that kind, then insert the new list at the index
    // the *first* removed element occupied. That is what makes a get→set round trip order-stable,
    // which the undo/redo path depends on — it snapshots `canvas.strokes`, then later assigns the
    // snapshot back wholesale (`StrokeCanvasView.registerVectorUndo`,
    // `CanvasManager+Shape.registerVectorStrokeUndo`, `CanvasManager+Fill.registerVectorFillUndo`).
    // Any other splice point would drift strokes above or below a fill on every undo.
    //
    // Round-tripping is exact while each kind occupies one contiguous run, which
    // `insertionIndex(forKind:in:)` guarantees for every list the app can currently build. A list that
    // deliberately *interleaves* kinds — nothing produces one yet — collapses each kind into one run at
    // its first position, so a later phase that starts interleaving must stop routing wholesale
    // assignment through these accessors and use `elements` instead.
    //
    // When the canvas holds *none* of that kind there is no removed index to reuse, and the fallback
    // is `Self.insertionIndex(forKind:in:)` rather than a plain append. That deviation is load-bearing:
    // `registerVectorFillUndo`'s redo does `canvas.fills = newFills` on a canvas whose fills were all
    // removed by the matching undo, so a plain append would put a redone flood fill *above* the
    // strokes it originally went under. Using the same ordering rule the `add…` methods use makes
    // set-after-empty agree with add.
    //
    // As with the previous stored-property accessors, the setters do **not** invalidate: every caller
    // that assigns wholesale follows it with `bumpVersion()` (checked — nine assignments across six
    // methods in `StrokeCanvasView`, `CanvasManager`, `CanvasManager+Shape`, `CanvasManager+Fill` and
    // `SelectionModels`), and keeping that split means the version counter ticks exactly as often as
    // it did before.

    var strokes: [VectorStroke] {
        get { lock.lock(); defer { lock.unlock() }; return _elements.compactMap(\.stroke) }
        set {
            lock.lock()
            defer { lock.unlock() }
            _elements = Self.splicing(_elements, kind: .stroke, with: newValue.map { .stroke($0) })
        }
    }

    var fills: [VectorFillElement] {
        get { lock.lock(); defer { lock.unlock() }; return _elements.compactMap(\.fill) }
        set {
            lock.lock()
            defer { lock.unlock() }
            _elements = Self.splicing(_elements, kind: .fill, with: newValue.map { .fill($0) })
        }
    }

    var images: [VectorImageElement] {
        get { lock.lock(); defer { lock.unlock() }; return _elements.compactMap(\.image) }
        set {
            lock.lock()
            defer { lock.unlock() }
            _elements = Self.splicing(_elements, kind: .image, with: newValue.map { .image($0) })
        }
    }

    /// Move/rotate/scale of the entire layer's content, applied at render time so it stays crisp at
    /// any transform (no resolution loss). Identity until the layer is transformed.
    var transform: CGAffineTransform {
        get { lock.lock(); defer { lock.unlock() }; return _transform }
        set { lock.lock(); defer { lock.unlock() }; _transform = newValue }
    }

    private(set) var version: Int = 0
    private var cachedImage: UIImage?

    init(size: CGSize, elements: [VectorElement], transform: CGAffineTransform = .identity) {
        self.size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        // Assigns the backing storage directly: `init` runs before the instance is shared with any
        // other thread, so there is nothing to lock against yet (as in `RasterLayerTexture.init`).
        self._elements = elements
        self._transform = transform
    }

    /// Three-array convenience, kept because it is what most construction sites (tests, and the
    /// display-list-free load path) already say. It builds the list in **fills, then images, then
    /// strokes** order — precisely the fixed order the pre-display-list renderer drew in, which is
    /// what makes content constructed this way render byte-identically.
    convenience init(size: CGSize, strokes: [VectorStroke] = [], fills: [VectorFillElement] = [],
                     images: [VectorImageElement] = [], transform: CGAffineTransform = .identity) {
        self.init(size: size,
                  elements: fills.map { .fill($0) } + images.map { .image($0) } + strokes.map { .stroke($0) },
                  transform: transform)
    }

    static func empty(size: CGSize) -> VectorCanvas { VectorCanvas(size: size) }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _elements.isEmpty
    }

    func makeCopy() -> VectorCanvas {
        lock.lock()
        defer { lock.unlock() }
        // The new instance has its own lock and isn't shared yet, so constructing it under this one
        // can't deadlock — and taking the lock is what makes the copy a coherent snapshot of the
        // display list and the transform rather than a mix of pre- and post-mutation state.
        return VectorCanvas(size: size, elements: _elements, transform: _transform)
    }

    /// A new canvas sized to `newSize` with all content shifted by `offset` (canvas point space),
    /// used by the canvas-padding resize (see `CanvasManager.setCanvasPadding`). Lossless: because
    /// `render()` applies the overall `transform` *after* drawing local content, appending a
    /// translation to `transform` shifts the whole rendered result by `offset` with no resampling —
    /// the stored elements (in local space) are untouched. `size` is immutable, so this returns
    /// a fresh instance.
    func resized(to newSize: CGSize, offset: CGPoint) -> VectorCanvas {
        lock.lock()
        defer { lock.unlock() }
        let shifted = _transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        return VectorCanvas(size: newSize, elements: _elements, transform: shifted)
    }

    // MARK: - Display-list ordering
    //
    // All `static`, so a method holding the non-reentrant `lock` can call them without any chance of
    // re-entering it — the same reason the geometry mappers below are static.

    /// The three element kinds, as a value the ordering/splice helpers can switch on.
    private enum Kind: Int {
        case fill = 0
        case image = 1
        case stroke = 2
    }

    private static func kind(of element: VectorElement) -> Kind {
        switch element {
        case .fill: return .fill
        case .image: return .image
        case .stroke: return .stroke
        }
    }

    /// Where a *newly added* element of `kind` belongs: after every element of the same or lower kind,
    /// before the first element of a higher one.
    ///
    /// This is the one place the legacy fills→images→strokes z-order still lives, and it is why Phase 1
    /// ships zero visible change. `addFill`/`addImage`/`addStroke` used to append into three separate
    /// arrays that were *always* drawn in that order, so "flood-fill after drawing a line" put the fill
    /// under the line. A naive append into one list would put it over the line — a real, visible
    /// regression. Routing every add through here reproduces the old order exactly while the list stays
    /// fully capable of arbitrary z-position, which is what the eraser needs (a stroke appended after an
    /// `.erase` stroke lands above it and is not eaten by it).
    ///
    /// Whether a *new* fill should keep going under existing strokes is a product question, not a
    /// mechanical one; Phase 2 owns it. Assumes the list is kind-sorted, which it is as long as every
    /// mutation goes through these helpers.
    private static func insertionIndex(forKind kind: Kind, in elements: [VectorElement]) -> Int {
        elements.firstIndex { Self.kind(of: $0).rawValue > kind.rawValue } ?? elements.count
    }

    /// The `strokes`/`fills`/`images` setter contract in one place — see the comment above those
    /// accessors for the full rationale.
    private static func splicing(_ elements: [VectorElement], kind: Kind,
                                 with replacements: [VectorElement]) -> [VectorElement] {
        var kept: [VectorElement] = []
        kept.reserveCapacity(elements.count)
        var firstRemoved: Int?
        for element in elements {
            if Self.kind(of: element) == kind {
                if firstRemoved == nil { firstRemoved = kept.count }
            } else {
                kept.append(element)
            }
        }
        kept.insert(contentsOf: replacements,
                    at: firstRemoved ?? Self.insertionIndex(forKind: kind, in: kept))
        return kept
    }

    /// Caller must hold `lock`.
    private func invalidate() {
        version += 1
        cachedImage = nil
    }

    /// Invalidates the render cache after a direct mutation of `strokes`/`fills`/`images`/`elements`
    /// (e.g. undo/redo restoring a snapshot, which assigns the array wholesale rather than going
    /// through `addStroke`).
    func bumpVersion() {
        lock.lock()
        defer { lock.unlock() }
        invalidate()
    }

    // MARK: - Mutation

    func addStroke(_ stroke: VectorStroke) {
        lock.lock()
        defer { lock.unlock() }
        _elements.insert(.stroke(stroke), at: Self.insertionIndex(forKind: .stroke, in: _elements))
        invalidate()
    }

    /// Adds a stroke whose samples were captured in **canvas** space — a live drag, or a smart
    /// shape's collapsed outline — mapping both its geometry and its width into this canvas's local
    /// space. See `addFill(canvasSpacePath:...)`: stored content is local-space and `render()`
    /// applies `transform` on top, so storing canvas-space samples verbatim puts the stroke through
    /// the transform twice and lands it away from where it was drawn, again with every later move.
    ///
    /// This used to open with `guard !_transform.isIdentity else { append(stroke); return invalidate() }`.
    /// That branch was *not* a behavioural difference — it was a duplicate of the general path:
    /// `localSamples(_:through:)` already returns its input unchanged for an identity transform, and
    /// `scale(of: .identity)` is `hypot(1, 0) == 1`, so `size / scale == size`. Two copies of one rule
    /// with no test able to tell them apart is how the identity and non-identity cases silently drift,
    /// so there is now one path; the no-op guards live in the mappers where they can't be forgotten.
    func addStroke(canvasSpaceStroke stroke: VectorStroke) {
        lock.lock()
        defer { lock.unlock() }
        var mapped = stroke
        mapped.samples = Self.localSamples(stroke.samples, through: _transform)
        // Width is a canvas-space measurement too: `render()` scales the stamped result by the
        // transform, so a stroke drawn at N points on a layer scaled by k must be stored at N/k to
        // come back out N points wide.
        let scale = Self.scale(of: _transform)
        if scale > 0 { mapped.size = stroke.size / scale }
        _elements.insert(.stroke(mapped), at: Self.insertionIndex(forKind: .stroke, in: _elements))
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
        _elements.insert(.image(element), at: Self.insertionIndex(forKind: .image, in: _elements))
        invalidate()
    }

    func addFill(_ element: VectorFillElement) {
        lock.lock()
        defer { lock.unlock() }
        _elements.insert(.fill(element), at: Self.insertionIndex(forKind: .fill, in: _elements))
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
        let fill = VectorFillElement(path: Self.localPath(path, through: _transform), color: color,
                                     opacity: opacity, evenOddFill: evenOddFill)
        _elements.insert(.fill(fill), at: Self.insertionIndex(forKind: .fill, in: _elements))
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
    ///
    /// Rebuilds each stroke **in place** in the display list rather than reassembling one flat stroke
    /// array, so the surviving pieces keep the z-position their parent held relative to fills, images
    /// and (later) other strokes.
    ///
    /// Applies to every stroke regardless of `composite`, which is what the pre-display-list code did
    /// and therefore what keeps this byte-identical. Nothing constructs an `.erase` stroke yet, so the
    /// two readings ("cut points out of an eraser too" vs. "leave erase elements alone") are
    /// indistinguishable today — Phase 2, which rewrites this whole method onto `StrokeGeometry`, is
    /// where that gets decided.
    @discardableResult
    func erase(alongPath eraserPoints: [CGPoint], radius: CGFloat) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !eraserPoints.isEmpty, _elements.contains(where: { $0.stroke != nil }) else { return false }
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
        var result: [VectorElement] = []
        result.reserveCapacity(_elements.count)
        for element in _elements {
            guard let stroke = element.stroke else {
                result.append(element) // fills and images are untouched by a vector eraser
                continue
            }
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
                result.append(element) // untouched
            } else {
                for run in runs where run.count >= 1 {
                    var piece = stroke
                    piece.id = UUID()
                    piece.samples = run
                    result.append(.stroke(piece))
                }
            }
        }
        if changed {
            _elements = result
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
    /// visibly change the render. So a group of strokes carrying a non-normal blend mode goes into a
    /// transparency layer, which restores exactly the isolation the scratch texture provided
    /// (composited once, source-over — the outer blend mode and alpha are `.normal`/1 at that point,
    /// matching the old `draw(in:)`). The common all-normal case pays nothing for it.
    ///
    /// **The isolation-group rule**, now that strokes can be interleaved with fills, images and
    /// erasers rather than always drawn last:
    ///
    /// 1. A *paint run* is a maximal stretch of consecutive `.paint` stroke elements. Any fill, any
    ///    image, or any `.erase` stroke ends the run.
    /// 2. If **any** stroke in a run has a non-`.normal` blend mode, the whole run is wrapped in one
    ///    transparency layer, so its strokes blend against each other but not against the fills,
    ///    images or earlier strokes beneath them. If every stroke in the run is `.normal`, no layer is
    ///    opened at all — associativity of source-over (above) makes that provably identical, and it
    ///    is the overwhelmingly common case.
    /// 3. An `.erase` stroke is never part of a run, so by construction no transparency layer is ever
    ///    open when one is stamped: it punches `.destinationOut` straight against the accumulated
    ///    context and therefore lowers the alpha of *everything* beneath it in the list — fills and
    ///    placed images included, which is the confirmed product behaviour (VECTOR_ERASER_PLAN.md §1).
    ///    Punching inside a transparency layer would only eat that group's own pixels, which is why
    ///    rule 1 makes an eraser close the run rather than join it.
    ///
    /// On any content the previous renderer could represent this is exactly the old behaviour: fills
    /// and images all sorted ahead of the strokes means there is precisely one paint run, spanning
    /// every stroke, and "any stroke non-normal → one layer around all of them" is what rule 2 reduces
    /// to. `insertionIndex(forKind:in:)` is what keeps that sorting true.
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
        let elements = _elements
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            // One target — and so one `DabGradientCache` — for the whole walk, exactly as before: the
            // cache's steady state is one miss per stroke and a hit for every dab after it, and a
            // per-run target would throw that away at every fill or eraser.
            let target = CGContextDabTarget(cg)
            var index = 0
            while index < elements.count {
                switch elements[index] {
                case .fill(let fill):
                    Self.draw(fill: fill, into: cg)
                    index += 1
                case .image(let element):
                    Self.draw(image: element, into: cg)
                    index += 1
                case .stroke(let stroke) where stroke.composite == .erase:
                    // Never inside a transparency layer — see rule 3 on `renderLocalContent`.
                    Self.stamp(stroke: stroke, into: target, isEraser: true)
                    index += 1
                case .stroke:
                    // Scan the maximal run of consecutive `.paint` strokes, deciding up front whether
                    // it needs isolating (rules 1 and 2).
                    var end = index
                    var needsIsolation = false
                    while let stroke = Self.paintStroke(at: end, in: elements) {
                        if stroke.brush.blendMode != .normal { needsIsolation = true }
                        end += 1
                    }
                    if needsIsolation { cg.beginTransparencyLayer(auxiliaryInfo: nil) }
                    for i in index..<end {
                        guard let stroke = Self.paintStroke(at: i, in: elements) else { continue }
                        Self.stamp(stroke: stroke, into: target, isEraser: false)
                    }
                    if needsIsolation { cg.endTransparencyLayer() }
                    index = end
                }
            }
        }
    }

    // The per-kind drawing helpers. `static` for the same reason everything else here is: the caller
    // holds the non-reentrant `lock`, so these must never take it, and taking only their inputs makes
    // that structural rather than a promise.

    /// The `.paint` stroke at `index`, or nil if that slot is out of range or holds anything else —
    /// i.e. the run terminator for `renderLocalContent`'s scan.
    private static func paintStroke(at index: Int, in elements: [VectorElement]) -> VectorStroke? {
        guard index < elements.count, let stroke = elements[index].stroke,
              stroke.composite == .paint else { return nil }
        return stroke
    }

    private static func draw(fill: VectorFillElement, into cg: CGContext) {
        guard let path = fill.cgPath else { return }
        cg.setFillColor(fill.uiColor.cgColor)
        cg.setAlpha(fill.opacity)
        cg.addPath(path)
        if fill.evenOddFill {
            cg.fillPath(using: .evenOdd)
        } else {
            cg.fillPath()
        }
        // Reset here rather than once after a whole block of fills. Those were equivalent only while
        // nothing but fills could precede an image; in an interleaved list a leftover global alpha
        // would dim whatever element came next.
        cg.setAlpha(1.0)
    }

    private static func draw(image element: VectorImageElement, into cg: CGContext) {
        cg.saveGState()
        let t = element.transform
        cg.translateBy(x: t.position.x, y: t.position.y)
        cg.rotate(by: t.rotation)
        cg.scaleBy(x: t.scale, y: t.scale)
        let imgSize = element.image.size
        element.image.draw(in: CGRect(x: -imgSize.width / 2, y: -imgSize.height / 2,
                                      width: imgSize.width, height: imgSize.height))
        cg.restoreGState()
    }

    private static func stamp(stroke: VectorStroke, into target: DabTarget, isEraser: Bool) {
        let samples = stroke.samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
        BrushStamper.stampStroke(into: target, samples: samples, brush: stroke.brush,
                                 color: stroke.uiColor, brushSize: stroke.size,
                                 brushOpacity: stroke.opacity, isEraser: isEraser)
    }
}

// MARK: - Persistence payload

/// Codable snapshot of a `VectorCanvas` for saving as JSON alongside the project.
///
/// Stores the **ordered display list**, so a saved project keeps the z-order it was drawn with rather
/// than being re-flattened into three kind-buckets on every save. Images are still stored by file name
/// only (their PNGs are written separately by `ProjectStore`, because `VectorImageElement.image` is a
/// runtime `UIImage` and deliberately not `Codable`); strokes and fills are stored inline. That split
/// is unchanged — it just travels per element instead of in a parallel array.
struct VectorCanvasData: Codable {
    struct ImageRef: Codable {
        var fileName: String
        var x: Double
        var y: Double
        var scale: Double
        var rotation: Double
    }

    /// The persisted form of one `VectorElement`. Written with an explicit `kind` discriminator rather
    /// than relying on Swift's synthesized enum encoding, so the on-disk shape is something a human can
    /// read and a future version can extend (shapes, video — VECTOR_ERASER_PLAN.md §2.2) without the
    /// layout being an implementation detail of the compiler.
    enum ElementData: Codable {
        case stroke(VectorStroke)
        case fill(VectorFillElement)
        case image(ImageRef)

        private enum Kind: String, Codable { case stroke, fill, image }
        private enum CodingKeys: String, CodingKey { case kind, stroke, fill, image }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(Kind.self, forKey: .kind) {
            case .stroke: self = .stroke(try c.decode(VectorStroke.self, forKey: .stroke))
            case .fill: self = .fill(try c.decode(VectorFillElement.self, forKey: .fill))
            case .image: self = .image(try c.decode(ImageRef.self, forKey: .image))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .stroke(let stroke):
                try c.encode(Kind.stroke, forKey: .kind)
                try c.encode(stroke, forKey: .stroke)
            case .fill(let fill):
                try c.encode(Kind.fill, forKey: .kind)
                try c.encode(fill, forKey: .fill)
            case .image(let ref):
                try c.encode(Kind.image, forKey: .kind)
                try c.encode(ref, forKey: .image)
            }
        }
    }

    var elements: [ElementData]
    /// Overall transform as [a, b, c, d, tx, ty]; missing/short → identity.
    var transform: [Double]

    /// Kind-filtered reads of the display list, mirroring `VectorCanvas`'s compatibility accessors so
    /// existing readers of `payload.strokes` / `.fills` / `.images` keep working. Read-only: a caller
    /// that needs the order (i.e. the load path) should use `elements(resolvingImages:)`.
    var strokes: [VectorStroke] {
        elements.compactMap { if case .stroke(let stroke) = $0 { return stroke } else { return nil } }
    }
    var fills: [VectorFillElement] {
        elements.compactMap { if case .fill(let fill) = $0 { return fill } else { return nil } }
    }
    var images: [ImageRef] {
        elements.compactMap { if case .image(let ref) = $0 { return ref } else { return nil } }
    }

    private enum CodingKeys: String, CodingKey {
        case elements, transform
        /// Legacy pre-display-list keys. Decoded when `elements` is absent, never written.
        case strokes, fills, images
    }

    init(elements: [ElementData], transform: [Double]) {
        self.elements = elements
        self.transform = transform
    }

    init(from canvas: VectorCanvas, imageFileNames: [UUID: String]) {
        elements = canvas.elements.compactMap { element in
            switch element {
            case .stroke(let stroke): return .stroke(stroke)
            case .fill(let fill): return .fill(fill)
            case .image(let el):
                // Unchanged contract: an image whose PNG was never written has no name to reference, so
                // it is dropped rather than persisted as a dangling ref.
                guard let name = el.fileName ?? imageFileNames[el.id] else { return nil }
                return .image(ImageRef(fileName: name, x: el.transform.position.x, y: el.transform.position.y,
                                       scale: el.transform.scale, rotation: el.transform.rotation))
            }
        }
        let t = canvas.transform
        transform = [Double(t.a), Double(t.b), Double(t.c), Double(t.d), Double(t.tx), Double(t.ty)]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transform = try c.decode([Double].self, forKey: .transform)
        if let ordered = try c.decodeIfPresent([ElementData].self, forKey: .elements) {
            elements = ordered
            return
        }
        // Legacy payload: three parallel arrays and no z-order at all. Rebuild the order the old
        // renderer drew in — all fills, then all images, then all strokes — which is what makes an
        // existing project open looking exactly as it did. It gains a real display list on first save.
        let strokes = try c.decode([VectorStroke].self, forKey: .strokes)
        let fills = try c.decode([VectorFillElement].self, forKey: .fills)
        let images = try c.decode([ImageRef].self, forKey: .images)
        elements = fills.map { .fill($0) } + images.map { .image($0) } + strokes.map { .stroke($0) }
    }

    /// Written explicitly so it is unmistakable that only the new ordered form goes to disk. The legacy
    /// arrays are deliberately *not* mirrored alongside it: a `.erase` stroke listed in a legacy
    /// `strokes` array would render as paint in an older build, which is worse than that build seeing
    /// no vector content at all.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elements, forKey: .elements)
        try c.encode(transform, forKey: .transform)
    }

    /// Rebuilds the ordered display list, turning each `ImageRef` back into a `VectorImageElement` via
    /// `resolveImage`. A ref whose PNG can't be loaded is dropped — the same `compactMap` behaviour the
    /// load path had before, just kept here so ordering logic lives in one place.
    func elements(resolvingImages resolveImage: (ImageRef) -> UIImage?) -> [VectorElement] {
        elements.compactMap { data in
            switch data {
            case .stroke(let stroke): return .stroke(stroke)
            case .fill(let fill): return .fill(fill)
            case .image(let ref):
                guard let image = resolveImage(ref) else { return nil }
                return .image(VectorImageElement(image: image,
                                                 transform: LayerTransform(position: CGPoint(x: ref.x, y: ref.y),
                                                                           scale: ref.scale, rotation: ref.rotation),
                                                 fileName: ref.fileName))
            }
        }
    }

    var affineTransform: CGAffineTransform {
        guard transform.count == 6 else { return .identity }
        return CGAffineTransform(a: CGFloat(transform[0]), b: CGFloat(transform[1]), c: CGFloat(transform[2]),
                                 d: CGFloat(transform[3]), tx: CGFloat(transform[4]), ty: CGFloat(transform[5]))
    }
}
