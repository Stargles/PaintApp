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

    /// Broad phase for every geometric query against this canvas's strokes, rebuilt lazily — see
    /// `strokeIndex()`. Version-keyed rather than cleared by `invalidate()`, because `version` only
    /// ever increases, so a stale index can never be mistaken for a current one.
    ///
    /// This is also the answer to the plan's §3.2 "cached `bounds: CGRect` per stroke". A stored
    /// per-stroke box would exist to reject strokes before testing their segments; the index rejects
    /// them *without visiting them at all*, which strictly dominates, and it does so without adding a
    /// derived stored property to a `Codable` struct whose `samples` are assigned from a dozen call
    /// sites with no mutator to hang the invalidation off. That mutator seam is worth building when
    /// Phase 5's decimation needs it anyway; until then this is the cache.
    private var cachedIndex: StrokeSpatialIndex?
    private var cachedIndexVersion: Int = -1

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

    // MARK: - Erasing
    //
    // The adapter layer between a gesture in canvas space and `VectorEraser`'s pure geometry: map
    // into local space, ask the spatial index which strokes are even candidates, delegate the actual
    // "which spans go away" decision, splice the survivors back at their parent's z-position.
    //
    // Nothing below decides geometry itself. That is the point of the split — every rule about what
    // an eraser covers lives in `VectorEraser`/`StrokeGeometry`, where it is compiled into the test
    // target and checked headlessly, rather than in here behind a lock and a render cache.

    /// Removes stroke geometry along an eraser gesture, according to `mode`. Returns true if anything
    /// changed.
    ///
    /// Eraser input is in **canvas** space (that is where touches are measured), so both the samples
    /// and the brush diameter are mapped through the inverse layer transform before they meet the
    /// stored, local-space geometry — otherwise erasing a scaled-up layer cuts a nib-sized hole where
    /// the user swept a wide one.
    ///
    /// Surviving pieces are spliced back **in place**, so they keep the z-position their parent held
    /// relative to fills, images and other strokes. Id semantics match the pre-Phase-2 behaviour and
    /// are load-bearing now that `BrushStamper`'s dab RNG is seeded from `stroke.id`: an untouched
    /// stroke keeps its id and therefore its exact scatter/jitter pattern, while a split mints fresh
    /// ids and re-rolls the pattern for both pieces (which is unavoidable — two strokes cannot share
    /// one seed without sharing one dab sequence).
    ///
    /// ## What this replaced
    ///
    /// The pre-Phase-2 implementation compared every stroke sample against every raw eraser *touch
    /// point* and dropped whole samples. All four of its defects (plan §4) are gone: a small nib no
    /// longer passes between two coarse touches without erasing (the eraser is a continuous capsule
    /// chain), cuts land at the footprint's edge instead of at the nearest stored sample, a coarse
    /// stroke is probed along its segments instead of judged at its vertices, and the traversal is
    /// bounded by the spatial index instead of being O(all samples × all touch points) over every
    /// stroke on the layer.
    ///
    /// ## `composite`
    ///
    /// `.erase` strokes are skipped — the carry-over the display-list phase deliberately left open.
    /// An eraser element is not ink; cutting a span out of one would *restore* the ink beneath it,
    /// which is not what any of the three modes mean by erasing. Phase 4, which starts producing
    /// `.erase` elements, garbage-collects them instead (plan §1).
    @discardableResult
    func erase(alongPath canvasSpaceSamples: [VectorSample], brush: Brush, size: CGFloat,
               opacity: Double = 1, mode: VectorEraserMode) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !canvasSpaceSamples.isEmpty else { return false }
        // Mode 1 can leave a punch over a fill or a placed image, so unlike Modes 2 and 3 it has work
        // to do on a layer with no strokes at all.
        guard mode == .erase || _elements.contains(where: { $0.stroke != nil }) else { return false }

        let localSamples = Self.localSamples(canvasSpaceSamples, through: _transform)
        let scale = Self.scale(of: _transform)
        let localSize = scale > 0 ? size / scale : size
        guard let sweep = VectorEraser.Sweep(samples: localSamples, brush: brush, size: localSize,
                                             mode: mode) else { return false }

        let changed: Bool
        switch mode {
        case .erase:
            changed = eraseHybrid(sweep: sweep, samples: localSamples, brush: brush, size: localSize,
                                  opacity: opacity)
        case .cutPoints:
            changed = cutAlongFootprint(sweep: sweep)
        case .cutToIntersection:
            // Whole-gesture form, resolved once against the first sample. The live gesture driver
            // uses `cutToIntersection(atCanvasPoint:…)` below instead, because Mode 3 cuts on
            // touch-down and re-resolves per crossing; this stays as the one-shot API that the
            // canvas offers for all three modes uniformly.
            changed = cutToIntersection(sweep: sweep, near: localSamples[0].point) == .cut
        }
        if changed { invalidate() }
        return changed
    }

    /// Mode 3 resolved against a **single** eraser position, which is what the plan means by cutting
    /// on touch-down and re-querying per crossing (§4, Mode 3): one drag across three lines cuts three
    /// spans, because the driver calls this once per touch sample rather than once per gesture.
    ///
    /// `cutting` is the driver's re-arming latch, not an optimisation. After a cut the eraser is still
    /// sitting on the stroke it just cut — right next to the surviving pieces if the crossing was
    /// nearby — so cutting again on the very next touch sample would walk down the line deleting span
    /// after span from one stationary finger. The driver therefore disarms after a cut and re-arms only
    /// once this reports `.missed`, i.e. once the tip has left ink entirely. Passing `cutting: false`
    /// runs the same target search and reports the same outcome **without mutating the display list**,
    /// so the driver learns it has left the ink from the query it was making anyway rather than from a
    /// second one.
    @discardableResult
    func cutToIntersection(atCanvasPoint canvasPoint: CGPoint, pressure: CGFloat, brush: Brush,
                           size: CGFloat, cutting: Bool = true) -> VectorEraser.CutOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard _elements.contains(where: { $0.stroke != nil }) else { return .missed }

        let localSamples = Self.localSamples([VectorSample(x: canvasPoint.x, y: canvasPoint.y, pressure: pressure)],
                                             through: _transform)
        let scale = Self.scale(of: _transform)
        let localSize = scale > 0 ? size / scale : size
        // A one-sample sweep is the single dab the eraser has stamped so far: `capsuleChain` yields one
        // zero-length capsule for it, so the footprint test below is the nib itself.
        guard let sweep = VectorEraser.Sweep(samples: localSamples, brush: brush, size: localSize,
                                             mode: .cutToIntersection) else { return .missed }

        let outcome = cutToIntersection(sweep: sweep, near: localSamples[0].point, cutting: cutting)
        if outcome == .cut { invalidate() }
        return outcome
    }

    // MARK: - Mode 1 — the hybrid
    //
    // The rules and the measurement that shaped them are documented on `VectorEraser`'s Mode 1
    // section; this is the adapter that applies them to a display list. Two steps, in this order:
    //
    // 1. **Separate** what the eraser provably severed, by splitting those strokes. Conservatively
    //    inset, so the ink it removes is a subset of the ink step 2 removes and it changes no pixels.
    // 2. **Punch**, always, so the result is byte-identical to erasing the same content on a raster
    //    layer — trimmed to the stretches of the gesture that still have something beneath them, then
    //    dropped entirely if none do.
    //
    // Step 2 is why Mode 1 is not just a better Mode 2, and step 1 is why it is not just a punch.

    /// Caller must hold `lock`.
    private func eraseHybrid(sweep: VectorEraser.Sweep, samples localSamples: [VectorSample],
                             brush: Brush, size: CGFloat, opacity: Double) -> Bool {
        var changed = false

        if VectorEraser.supportsCleanCut(brush: brush, opacity: opacity) {
            let erasers = VectorEraser.cleanCutCapsules(sweep.capsules, brush: brush, size: size)
            if !erasers.isEmpty, splitCleanlySeveredStrokes(sweep: sweep, erasers: erasers) {
                changed = true
                // Bumps `version`, so the residue query below rebuilds the index against the
                // *survivors*. Without this it would ask a stale index and retain punch over strokes
                // the split just removed.
                invalidate()
            }
        }

        let residue = VectorEraser.residueSpans(in: localSamples, sweep: sweep) { parameter in
            hasContentBeneath(atParameter: parameter, in: localSamples, brush: brush, size: size)
        }
        if !residue.isEmpty {
            let domain = 0...CGFloat(max(localSamples.count - 1, 0))
            let discarded = StrokeGeometry.complementOfSpans(residue, over: domain)
            for run in StrokeGeometry.splitStroke(localSamples, removing: discarded) {
                // The eraser *is* a stroke (plan §2.1): same brush, same size, same pressure-driven
                // dab chain, composited `.destinationOut` at render. Appended last, so it punches
                // everything already in the list and nothing drawn after it. The colour is arbitrary —
                // `.destinationOut` reads only the stamp's alpha coverage.
                let punch = VectorStroke(brush: brush,
                                         color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                         size: size, opacity: opacity, samples: run, composite: .erase)
                _elements.append(.stroke(punch))
                changed = true
            }
        }

        if collectResidueGarbage() { changed = true }
        return changed
    }

    /// Splits every candidate paint stroke the eraser severs across its whole width. Caller must hold
    /// `lock`.
    private func splitCleanlySeveredStrokes(sweep: VectorEraser.Sweep,
                                            erasers: [StrokeGeometry.Capsule]) -> Bool {
        // The index holds centrelines, so a stroke whose centreline sits outside the sweep's box can
        // still have ink inside it. Grow the query by the widest half-width on the layer or the
        // clean-cut test never gets asked about the strokes at the edge of the gesture.
        let reach = maxPaintReach()
        let candidates = Set(strokeIndex().segments(near: sweep.bounds.insetBy(dx: -reach, dy: -reach))
            .map(\.elementIndex))
        guard !candidates.isEmpty else { return false }

        var changed = false
        var result: [VectorElement] = []
        result.reserveCapacity(_elements.count)
        for (index, element) in _elements.enumerated() {
            guard candidates.contains(index), let stroke = element.stroke,
                  stroke.composite == .paint, VectorEraser.supportsSplitting(strokeBrush: stroke.brush) else {
                result.append(element)
                continue
            }
            let clean = VectorEraser.cleanCutRanges(in: stroke.samples, brush: stroke.brush,
                                                    size: stroke.size, by: erasers, sweep: sweep)
            let cuts = Self.effectiveCuts(VectorEraser.conservativeCuts(clean, in: stroke.samples,
                                                                        brush: stroke.brush, size: stroke.size),
                                          in: stroke.samples)
            guard !cuts.isEmpty else { result.append(element); continue }
            changed = true
            for run in StrokeGeometry.splitStroke(stroke.samples, removing: cuts) {
                var piece = stroke
                piece.id = UUID()
                piece.samples = run
                result.append(.stroke(piece))
            }
        }
        if changed { _elements = result }
        return changed
    }

    /// Whether the eraser's dab at a parametric position along the gesture still has anything under it
    /// — the predicate behind residue trimming. Caller must hold `lock`.
    private func hasContentBeneath(atParameter parameter: CGFloat, in samples: [VectorSample],
                                   brush: Brush, size: CGFloat) -> Bool {
        guard let dab = StrokeGeometry.interpolatedSample(in: samples, at: parameter) else { return false }
        let radius = StrokeGeometry.stampRadius(forPressure: dab.pressure, brush: brush, size: size)
        let box = CGRect(x: dab.x - radius, y: dab.y - radius, width: radius * 2, height: radius * 2)

        // Fills and images have no geometry the split could have removed, so any overlap at all means
        // the punch is still doing work. Bounding boxes rather than exact paths: conservative in the
        // safe direction (an unnecessary punch is a retained element, a missing one is a visible
        // artefact), and a fill's exact containment test per probe is not worth its cost here.
        for element in _elements {
            switch element {
            case .fill(let fill):
                if let path = fill.cgPath, path.boundingBoxOfPath.intersects(box) { return true }
            case .image(let image):
                if Self.bounds(of: image).intersects(box) { return true }
            case .stroke:
                continue
            }
        }

        let reach = maxPaintReach()
        guard reach > 0 else { return false }
        for ref in strokeIndex().segments(near: box.insetBy(dx: -reach, dy: -reach)) {
            guard let stroke = _elements[ref.elementIndex].stroke, stroke.composite == .paint,
                  stroke.samples.indices.contains(ref.sampleIndex) else { continue }
            let a = stroke.samples[ref.sampleIndex].point
            let b = stroke.samples[min(ref.sampleIndex + 1, stroke.samples.count - 1)].point
            let limit = radius + StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush,
                                                            size: stroke.size)
            if StrokeGeometry.distanceSquared(from: dab.point, toSegment: a, b) <= limit * limit {
                return true
            }
        }
        return false
    }

    /// Plan §1's garbage collection: a retained `.erase` element is dropped once nothing *beneath it*
    /// in the display list still reaches its bounding box. Caller must hold `lock`.
    ///
    /// Beneath, not anywhere — an element added after the punch is above it and was never affected by
    /// it, so its presence is no reason to keep one. Run on commit rather than per frame, which is why
    /// a punch whose backdrop was deleted survives until the next erase; it renders as a hole in
    /// nothing, so nothing is visibly wrong in the meantime.
    private func collectResidueGarbage() -> Bool {
        guard _elements.contains(where: { $0.stroke?.composite == .erase }) else { return false }
        let reach = maxPaintReach()
        var kept: [VectorElement] = []
        kept.reserveCapacity(_elements.count)
        var dropped = false
        for element in _elements {
            guard let stroke = element.stroke, stroke.composite == .erase else {
                kept.append(element)
                continue
            }
            let punchReach = StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush, size: stroke.size)
            guard let box = StrokeGeometry.bounds(of: stroke.samples, padding: punchReach + reach) else {
                dropped = true
                continue
            }
            if Self.anyContent(in: kept, reaching: box) {
                kept.append(element)
            } else {
                dropped = true
            }
        }
        if dropped { _elements = kept }
        return dropped
    }

    /// Whether any paint stroke, fill or image in `elements` reaches `box`. Static, so it cannot
    /// re-enter `lock`; `box` is already padded by the caller for stroke width.
    private static func anyContent(in elements: [VectorElement], reaching box: CGRect) -> Bool {
        for element in elements {
            switch element {
            case .stroke(let stroke):
                guard stroke.composite == .paint,
                      let strokeBox = StrokeGeometry.bounds(of: stroke.samples) else { continue }
                if strokeBox.intersects(box) { return true }
            case .fill(let fill):
                if let path = fill.cgPath, path.boundingBoxOfPath.intersects(box) { return true }
            case .image(let image):
                if bounds(of: image).intersects(box) { return true }
            }
        }
        return false
    }

    /// A placed image's local-space bounding box, taken as the circumscribing circle of its scaled
    /// size so the answer is rotation-independent — conservative, and rotation is stored as a free
    /// angle rather than a quadrant.
    private static func bounds(of element: VectorImageElement) -> CGRect {
        let size = element.image.size
        let radius = hypot(size.width, size.height) / 2 * abs(element.transform.scale)
        return CGRect(x: element.transform.position.x - radius, y: element.transform.position.y - radius,
                      width: radius * 2, height: radius * 2)
    }

    /// The widest half-width any paint stroke on the layer renders at, i.e. how far ink can extend
    /// beyond a centreline the spatial index stores. Caller must hold `lock`.
    private func maxPaintReach() -> CGFloat {
        var reach: CGFloat = 0
        for element in _elements {
            guard let stroke = element.stroke, stroke.composite == .paint else { continue }
            reach = max(reach, StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush,
                                                          size: stroke.size))
        }
        return reach
    }

    /// Mode 2: every paint stroke loses the spans its geometry shares with the eraser's footprint.
    /// Caller must hold `lock`.
    private func cutAlongFootprint(sweep: VectorEraser.Sweep) -> Bool {
        let candidates = Set(strokeIndex().segments(near: sweep.bounds).map(\.elementIndex))
        guard !candidates.isEmpty else { return false }

        var changed = false
        var result: [VectorElement] = []
        result.reserveCapacity(_elements.count)
        for (index, element) in _elements.enumerated() {
            guard candidates.contains(index), let stroke = element.stroke,
                  stroke.composite == .paint else {
                // Fills and images are untouched by a geometric eraser, and so is anything the
                // eraser's swept box never reached.
                result.append(element)
                continue
            }
            let cuts = Self.effectiveCuts(VectorEraser.cutRanges(in: stroke.samples, sweep: sweep),
                                          in: stroke.samples)
            guard !cuts.isEmpty else { result.append(element); continue }
            changed = true
            for run in StrokeGeometry.splitStroke(stroke.samples, removing: cuts) {
                var piece = stroke
                piece.id = UUID()
                piece.samples = run
                result.append(.stroke(piece))
            }
        }
        if changed { _elements = result }
        return changed
    }

    /// Mode 3: the one stroke the eraser came down on loses the span between its two neighbouring
    /// crossings. Caller must hold `lock`.
    ///
    /// `cutting: false` stops short of mutating anything and only reports whether a target was found —
    /// see `cutToIntersection(atCanvasPoint:…)` for why the gesture driver needs that distinction.
    private func cutToIntersection(sweep: VectorEraser.Sweep, near hitPoint: CGPoint,
                                   cutting: Bool = true) -> VectorEraser.CutOutcome {
        let index = strokeIndex()
        let candidates = Set(index.segments(near: sweep.bounds).map(\.elementIndex))
        guard !candidates.isEmpty else { return .missed }

        // The stroke the eraser came down on: nearest centreline among the candidates, and only if
        // the eraser's footprint actually reaches it (a near miss should cut nothing, not cut the
        // nearest thing on the layer).
        var target: (index: Int, stroke: VectorStroke, parameter: CGFloat)?
        var bestDistanceSquared = CGFloat.infinity
        for elementIndex in candidates.sorted() {
            guard let stroke = _elements[elementIndex].stroke, stroke.composite == .paint,
                  !stroke.samples.isEmpty else { continue }
            guard let hit = StrokeGeometry.closestPoint(onPolyline: stroke.samples, to: hitPoint),
                  hit.distanceSquared < bestDistanceSquared, sweep.contains(hit.point) else { continue }
            bestDistanceSquared = hit.distanceSquared
            target = (elementIndex, stroke, hit.parameter)
        }
        guard let target else { return .missed }
        // Past this point the tip *is* over ink, so every remaining exit says `.unchanged` rather than
        // `.missed` — the driver must stay disarmed until the finger actually leaves the stroke.
        guard cutting else { return .unchanged }

        // Everything that could cross it, with a width-aware tolerance per pair: two lines whose ink
        // visibly touches read as crossed even when the centrelines miss (plan §4, Mode 3).
        let targetReach = StrokeGeometry.stampRadius(forPressure: 1, brush: target.stroke.brush,
                                                     size: target.stroke.size)
        guard let targetBounds = StrokeGeometry.bounds(of: target.stroke.samples,
                                                       padding: targetReach) else { return .unchanged }
        var others: [(points: [CGPoint], tolerance: CGFloat)] = []
        for elementIndex in Set(index.segments(near: targetBounds).map(\.elementIndex)).sorted()
        where elementIndex != target.index {
            guard let other = _elements[elementIndex].stroke, other.composite == .paint,
                  other.samples.count > 1 else { continue }
            let reach = StrokeGeometry.stampRadius(forPressure: 1, brush: other.brush, size: other.size)
            others.append((other.samples.map(\.point), targetReach + reach))
        }

        let cuts = Self.effectiveCuts(VectorEraser.cutToIntersection(in: target.stroke.samples,
                                                                     at: target.parameter, others: others),
                                      in: target.stroke.samples)
        guard !cuts.isEmpty else { return .unchanged }

        var pieces: [VectorElement] = []
        for run in StrokeGeometry.splitStroke(target.stroke.samples, removing: cuts) {
            var piece = target.stroke
            piece.id = UUID()
            piece.samples = run
            pieces.append(.stroke(piece))
        }
        _elements.replaceSubrange(target.index...target.index, with: pieces)
        return .cut
    }

    /// `cuts` reduced to what actually removes something, so a graze that merely touches a stroke's
    /// geometry doesn't churn it.
    ///
    /// Two filters. Ranges are merged and clamped to the run's domain first, so cuts that fall
    /// entirely outside it disappear rather than being handed to `splitStroke` only to be dropped
    /// there — the caller needs to know "nothing happened" to keep the stroke's id and skip the
    /// invalidation. Then zero-width ranges go: on a multi-sample run they arise from a repeated
    /// sample or a boundary graze and would otherwise rebuild the stroke, with a fresh id and a
    /// re-rolled dab pattern, without deleting a thing. A single-sample run is exempt — its whole
    /// domain *is* the zero-width range `0...0`, and removing that is how a lone dab gets erased.
    private static func effectiveCuts(_ cuts: [ClosedRange<CGFloat>],
                                      in samples: [VectorSample]) -> [ClosedRange<CGFloat>] {
        guard !samples.isEmpty else { return [] }
        let domainEnd = CGFloat(samples.count - 1)
        let merged = StrokeGeometry.mergedCuts(cuts, clampedTo: 0...domainEnd)
        guard samples.count > 1 else { return merged }
        return merged.filter { $0.upperBound - $0.lowerBound > StrokeGeometry.epsilon }
    }

    /// A uniform grid over every stroke's segments, keyed by `version` so it survives as long as the
    /// display list does and is rebuilt the first time anything asks after a mutation.
    ///
    /// This is what takes the eraser off the "test everything against everything" path: a query
    /// returns only the segments in the eraser's swept box, so the cost scales with what the gesture
    /// touched rather than with how much is on the layer. Mode 3's intersection search and Phase 4's
    /// coverage test and residue GC all query the same structure.
    ///
    /// Caller must hold `lock` — and that is not just the usual convention here. `segments(near:)`
    /// stamps a per-query visit marker into the index to de-duplicate refs across cells, so it
    /// mutates during a *read*: two concurrent queries would interleave their markers and drop
    /// results. The lock is what makes that safe; a future off-main reader needs its own index.
    ///
    /// Segment boxes are inserted with **no padding**, i.e. the index answers questions about stroke
    /// *centrelines*. That is exactly what Modes 2 and 3 ask (does the footprint cover this point?).
    /// Phase 4's coverage test asks about a stroke's own *width*, so it must expand its query rect by
    /// the widest half-width on the layer rather than assume this rejects nothing it needed.
    private func strokeIndex() -> StrokeSpatialIndex {
        if let cachedIndex, cachedIndexVersion == version { return cachedIndex }
        let index = StrokeSpatialIndex()
        for (elementIndex, element) in _elements.enumerated() {
            guard let stroke = element.stroke else { continue }
            index.insert(samples: stroke.samples, elementIndex: elementIndex)
        }
        cachedIndex = index
        cachedIndexVersion = version
        return index
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

    /// Replays one stored stroke. `seed:` is what makes that a *replay* rather than a fresh roll:
    /// this method runs again for every stroke on the layer on every invalidation, so with unseeded
    /// randomness a brush carrying `scatter`/`rotationJitter` re-scattered its dabs each time and the
    /// user watched finished artwork crawl. Deriving the seed from the stroke's own id keeps it stable
    /// across save/load and gives two strokes different scatter patterns. See `BrushStamper.DabRNG`.
    private static func stamp(stroke: VectorStroke, into target: DabTarget, isEraser: Bool) {
        let samples = stroke.samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
        BrushStamper.stampStroke(into: target, samples: samples, brush: stroke.brush,
                                 color: stroke.uiColor, brushSize: stroke.size,
                                 brushOpacity: stroke.opacity, isEraser: isEraser,
                                 seed: BrushStamper.seed(for: stroke.id))
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
