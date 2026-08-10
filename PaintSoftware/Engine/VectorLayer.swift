import UIKit
import CoreGraphics

extension CodableColor {
    /// The stored components as a `UIColor`. One definition rather than the same four-argument
    /// initialiser repeated at every call site.
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}

/// Whether a `VectorStroke` *adds* ink or *removes* it. A mode on `VectorStroke` rather than its
/// own element type, so an eraser gets interpolation, liquify and point decimation for free.
enum StrokeComposite: String, Codable {
    case paint
    case erase
}

/// A brush stroke stored as geometry (input samples + brush/color/size), not baked pixels. Pixels
/// are produced on demand by re-stamping the brush along these samples (`VectorCanvas.render` →
/// `BrushStamper`), so a stroke can be moved/scaled and re-rasterized with no quality loss.
struct VectorStroke: Identifiable, Codable {
    var id: UUID = UUID()
    var brush: Brush
    var color: CodableColor
    var size: CGFloat
    var opacity: Double
    var samples: [VectorSample]
    /// `.erase` routes this stroke through `BrushStamper.stampStroke(..., isEraser: true)` — same
    /// pipeline as paint, composited `.destinationOut`, punching a hole in everything beneath it.
    ///
    /// Decoding uses the explicit `init(from:)` below: synthesized `Decodable` ignores property
    /// defaults and throws on a missing key, which would break projects saved before this field existed.
    var composite: StrokeComposite = .paint

    /// The lattice a piece's dabs belong to, if this stroke is a piece cut from another. Nil for a
    /// stroke drawn as itself. `samples` stays this stroke's geometric truth; the lattice answers
    /// only "where did the dabs go". See `DabLattice`.
    var lattice: DabLattice?

    /// The motion group this stroke belongs to during keyframe interpolation. Nil means untagged.
    /// A field, not a side table, so it survives copy/duplicate/split/undo automatically and a cut
    /// piece keeps its parent's tag. Independent of `color` — see `MotionGroup.tagColor`.
    var motionGroupID: UUID? = nil

    /// The interpolation parameter below which this stroke is not drawn — the τ threshold. Set on a
    /// stroke that appears at an in-between or exists at only one keyframe. Nil means always visible.
    var visibilityThreshold: CGFloat? = nil

    /// Per-sample overrides of `visibilityThreshold`, keyed by index into `samples`. Absent unless a
    /// stroke needs to vanish progressively along its length instead of all at once.
    var sampleVisibilityThresholds: [Int: CGFloat]? = nil

    var uiColor: UIColor { color.uiColor }

    /// Spelled out so `init(from:)` below can name the keys without suppressing the synthesized
    /// memberwise initialiser every construction site here uses.
    enum CodingKeys: String, CodingKey {
        case id, brush, color, size, opacity, samples, composite, lattice
        case motionGroupID, visibilityThreshold, sampleVisibilityThresholds
    }
}

/// How a stroke cut out of another one reproduces the original's dabs instead of starting a lattice of
/// its own. `BrushStamper.stampStroke` anchors its dab lattice at `samples[0]`, so re-stamping a
/// sub-run alone would re-phase every dab; instead a piece stores the **parent's** samples plus, per
/// own sample, the parameter it sits at in the parent's domain, and rendering walks the parent whole,
/// drawing only the dabs inside `range`. `parameters` maps into the parent's domain via linear
/// interpolation (`parentParameter(of:)`), which lets a piece be cut again. `seedID` is the parent's
/// id, so the dab RNG replays the parent's sequence.
struct DabLattice: Codable, Equatable {
    /// The parent stroke's samples, whole — the walk that defines the lattice.
    var samples: [VectorSample]
    /// Parameter in the parent's domain for each of the owning stroke's own samples, ascending.
    var parameters: [CGFloat]
    /// The parent's id, so `BrushStamper.seed(for:)` replays the parent's dab RNG.
    var seedID: UUID

    /// The parent parameters this piece shows. Nil-return keeps the renderer honest on a decoded
    /// file rather than crashing, even though empty `parameters` shouldn't occur for a real stroke.
    var range: ClosedRange<CGFloat>? {
        guard let low = parameters.first, let high = parameters.last, high >= low else { return nil }
        return low...high
    }

    /// `parameter`, in the owning stroke's own domain, mapped into the parent's. Linear between
    /// neighbouring entries — exact, since a piece's segment lies inside one parent segment.
    func parentParameter(of parameter: CGFloat) -> CGFloat {
        guard parameters.count > 1 else { return parameters.first ?? parameter }
        let clamped = min(max(parameter, 0), CGFloat(parameters.count - 1))
        let i = min(Int(clamped.rounded(.down)), parameters.count - 2)
        let f = clamped - CGFloat(i)
        return parameters[i] + (parameters[i + 1] - parameters[i]) * f
    }
}

/// `init(from:)`/`encode(to:)` live in an extension so declaring them doesn't suppress the
/// memberwise initialiser every call site here builds with.
extension VectorStroke {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        brush = try c.decode(Brush.self, forKey: .brush)
        color = try c.decode(CodableColor.self, forKey: .color)
        size = try c.decode(CGFloat.self, forKey: .size)
        opacity = try c.decode(Double.self, forKey: .opacity)
        samples = try c.decode([VectorSample].self, forKey: .samples)
        // Absent key → `.paint`, so legacy files load.
        composite = try c.decodeIfPresent(StrokeComposite.self, forKey: .composite) ?? .paint
        // Absent is the normal case; only a stroke cut out of another one carries a lattice.
        lattice = try c.decodeIfPresent(DabLattice.self, forKey: .lattice)
        motionGroupID = try c.decodeIfPresent(UUID.self, forKey: .motionGroupID)
        visibilityThreshold = try c.decodeIfPresent(CGFloat.self, forKey: .visibilityThreshold)
        sampleVisibilityThresholds = try c.decodeIfPresent([Int: CGFloat].self,
                                                           forKey: .sampleVisibilityThresholds)
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
        // Written only when present, so an ordinary stroke's payload stays byte-for-byte unchanged.
        try c.encodeIfPresent(lattice, forKey: .lattice)
        try c.encodeIfPresent(motionGroupID, forKey: .motionGroupID)
        try c.encodeIfPresent(visibilityThreshold, forKey: .visibilityThreshold)
        try c.encodeIfPresent(sampleVisibilityThresholds, forKey: .sampleVisibilityThresholds)
    }
}

/// A filled region stored as a vector path on a vector layer: the flood-fill tool's output when used
/// on a `.vector` layer, instead of rasterizing into `Cel.bakedImage`. A closed (possibly multi-loop,
/// with holes) contour extracted from the GPU fill mask, stored as archived `UIBezierPath` data.
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

/// An imported image placed on a vector layer, movable/scalable/rotatable via its own transform.
/// `image` is runtime-only; persistence stores a file name + the transform (see `ProjectStore`).
struct VectorImageElement: Identifiable {
    var id: UUID = UUID()
    var image: UIImage
    var transform: LayerTransform
    /// Set once the element has been persisted, so save can reuse the same file.
    var fileName: String?
}

/// One entry in a `VectorCanvas`'s display list, drawn back to front. Not three parallel arrays,
/// because z-position is what an eraser needs: an `.erase` stroke lowers the alpha of everything
/// beneath it in this list.
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

/// How much fidelity a render is asked for. `.preview` stamps one stroked `CGPath` per stroke instead
/// of hundreds of dabs — ~100x cheaper, which is what makes scrubbing usable — at the cost of per-dab
/// pressure ramping, grain, scatter, rotation jitter, and dab alpha build-up. Shape, position, colour,
/// blend mode and the eraser's punch are preserved.
enum RenderQuality {
    case full
    case preview
}

/// The vector content of one cel on a `.vector` layer: strokes + placed images, plus one overall
/// affine transform applied to the whole set. A class because it's a persistent mutable buffer the
/// drawing surface stamps into; renders on demand to a canvas-native `UIImage` displayed with
/// nearest-neighbor magnification, so it stays pixelated when zoomed even though the source is
/// resolution-independent.
final class VectorCanvas {
    let size: CGSize

    /// Guards `_elements`/`_transform` and `cachedImage`. Live drawing mutates this canvas on the main
    /// thread, but `render()` is also reached from a background queue (the interactive fill's
    /// reference composite), which would otherwise race the array read.
    ///
    /// Non-reentrant: every private/`static` helper below is only called from a method already
    /// holding this lock. The stored-property accessors are the public seam that locks.
    private let lock = NSLock()

    /// The one z-ordered display list, drawn back to front. See `VectorElement` for why not three
    /// parallel arrays, and `renderLocalContent()` for how it is walked.
    private var _elements: [VectorElement]
    private var _transform: CGAffineTransform

    /// The display list itself. Existing code keeps using the three kind-filtered accessors below.
    var elements: [VectorElement] {
        get { lock.lock(); defer { lock.unlock() }; return _elements }
        set { lock.lock(); defer { lock.unlock() }; _elements = newValue }
    }

    // MARK: - Kind-filtered compatibility accessors
    //
    // Getters filter the display list; setters splice: remove every element of that kind, then insert
    // the new list at the index the first removed element occupied, so a get→set round trip is
    // order-stable (undo/redo depends on this). Setters do not invalidate — callers follow with
    // `bumpVersion()`.

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

    /// Move/rotate/scale of the entire layer's content, applied at render time so it stays crisp.
    /// Identity until the layer is transformed.
    var transform: CGAffineTransform {
        get { lock.lock(); defer { lock.unlock() }; return _transform }
        set { lock.lock(); defer { lock.unlock() }; _transform = newValue }
    }

    private(set) var version: Int = 0
    private var cachedImage: UIImage?

    /// The `.preview` render, memoized separately from `cachedImage` — releasing the slider renders
    /// `.full` and must not discard `.preview`, and starting a drag must not discard `.full`.
    private var cachedPreviewImage: UIImage?

    /// Broad phase for every geometric query against this canvas's strokes, rebuilt lazily — see
    /// `strokeIndex()`. Version-keyed rather than cleared by `invalidate()`, since `version` only
    /// increases, so a stale index can never be mistaken for current.
    private var cachedIndex: StrokeSpatialIndex?
    private var cachedIndexVersion: Int = -1

    init(size: CGSize, elements: [VectorElement], transform: CGAffineTransform = .identity) {
        self.size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        self._elements = elements
        self._transform = transform
    }

    /// Three-array convenience, kept because most construction sites (tests, the display-list-free
    /// load path) already say it this way. Builds fills, then images, then strokes.
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
        return VectorCanvas(size: size, elements: _elements, transform: _transform)
    }

    /// A new canvas sized to `newSize` with all content shifted by `offset`, used by the
    /// canvas-padding resize. Lossless: `render()` applies `transform` after drawing local content,
    /// so appending a translation shifts the result with no resampling.
    func resized(to newSize: CGSize, offset: CGPoint) -> VectorCanvas {
        lock.lock()
        defer { lock.unlock() }
        let shifted = _transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        return VectorCanvas(size: newSize, elements: _elements, transform: shifted)
    }

    // MARK: - Display-list ordering
    //
    // All `static`, so a method holding the non-reentrant `lock` can call them without re-entering it.

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

    /// Where a newly added element of `kind` belongs: after every element of the same or lower kind,
    /// before the first of a higher one. Reproduces the legacy fills→images→strokes z-order while the
    /// list stays capable of arbitrary z-position, which the eraser needs. Assumes the list is kind-sorted.
    private static func insertionIndex(forKind kind: Kind, in elements: [VectorElement]) -> Int {
        elements.firstIndex { Self.kind(of: $0).rawValue > kind.rawValue } ?? elements.count
    }

    /// The `strokes`/`fills`/`images` setter contract — see the comment above those accessors.
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
        cachedPreviewImage = nil
    }

    /// Invalidates the render cache after a direct mutation of `strokes`/`fills`/`images`/`elements`
    /// (e.g. undo/redo restoring a snapshot, which assigns the array wholesale).
    func bumpVersion() {
        lock.lock()
        defer { lock.unlock() }
        invalidate()
    }

    /// True when a rendered image of either quality is memoized — what cache eviction counts. A cel
    /// holding only a `.preview` render is just as much of a claim on memory.
    var hasCachedImage: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedImage != nil || cachedPreviewImage != nil
    }

    /// Frees the memoized render without touching the content. Deliberately not `invalidate()`:
    /// `version` means "the content changed", and bumping it would make version-keyed consumers
    /// believe an edit happened when nothing did. See `CanvasManager.evictDistantVectorRenderCaches`.
    func dropCachedImage() {
        lock.lock()
        defer { lock.unlock() }
        cachedImage = nil
        cachedPreviewImage = nil
    }

    // MARK: - Mutation

    func addStroke(_ stroke: VectorStroke) {
        lock.lock()
        defer { lock.unlock() }
        _elements.insert(.stroke(stroke), at: Self.insertionIndex(forKind: .stroke, in: _elements))
        invalidate()
    }

    /// Adds a stroke whose samples were captured in canvas space — a live drag, or a smart shape's
    /// collapsed outline — mapping geometry and width into this canvas's local space (storage is
    /// local-space; `render()` applies `transform` on top).
    func addStroke(canvasSpaceStroke stroke: VectorStroke) {
        lock.lock()
        defer { lock.unlock() }
        var mapped = stroke
        mapped.samples = Self.localSamples(stroke.samples, through: _transform)
        // Width is canvas-space too: a stroke at N points on a layer scaled by k must store N/k to
        // come back out N points wide after render() rescales it.
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

    // Static functions of the transform they're given, rather than methods reading `_transform`, so
    // a locked method can call them without re-entering the lock.

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

    /// Adds a fill whose path was captured in **canvas** space — where the flood-fill mask, the lasso,
    /// and every other on-screen path are measured — mapping it into this canvas's local space first,
    /// or it would go through `transform` twice at render time.
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
    /// `pivot`, a fixed point in the content's own local space (typically its bounding box's center),
    /// so the Move tool's on-canvas box tracks the actual content. Assumes `transform` is
    /// translate·rotate·uniform-scale.
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
    // into local space, ask the spatial index which strokes are candidates, delegate the "which spans
    // go away" decision to `VectorEraser`/`StrokeGeometry`, splice survivors back at their z-position.

    /// Removes stroke geometry along an eraser gesture, according to `mode`. Returns true if anything
    /// changed.
    ///
    /// Eraser input is in **canvas** space; samples and brush diameter are mapped through the inverse
    /// layer transform before meeting the stored, local-space geometry, or erasing a scaled-up layer
    /// would cut a nib-sized hole where the user swept a wide one.
    ///
    /// Surviving pieces are spliced back in place, keeping their parent's z-position. An untouched
    /// stroke keeps its id (and so its scatter/jitter pattern, seeded from `stroke.id`); a split mints
    /// fresh ids and re-rolls the pattern for both pieces.
    ///
    /// `.erase` strokes are skipped: cutting a span out of one would *restore* the ink beneath it.
    @discardableResult
    func erase(alongPath canvasSpaceSamples: [VectorSample], brush: Brush, size: CGFloat,
               opacity: Double = 1, mode: VectorEraserMode) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !canvasSpaceSamples.isEmpty else { return false }
        // Mode 1 can leave a punch over a fill or placed image, so unlike Modes 2/3 it has work to
        // do on a layer with no strokes at all.
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
            // uses `cutToIntersection(atCanvasPoint:…)` instead, since Mode 3 cuts on touch-down and
            // re-resolves per crossing.
            changed = cutToIntersection(sweep: sweep, near: localSamples[0].point) == .cut
        }
        if changed { invalidate() }
        return changed
    }

    /// Mode 3 resolved against a **single** eraser position: the driver calls this once per touch
    /// sample, so a drag across three lines cuts three spans.
    ///
    /// `cutting` is the driver's re-arming latch: after a cut the eraser is still sitting on the
    /// stroke, so cutting again on the next sample would walk down the line deleting span after span
    /// from one stationary finger. The driver disarms after a cut and re-arms only once this reports
    /// `.missed`. `cutting: false` runs the same target search without mutating the display list.
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
        // A one-sample sweep is the single dab stamped so far: `capsuleChain` yields one zero-length
        // capsule for it, so the footprint test below is the nib itself.
        guard let sweep = VectorEraser.Sweep(samples: localSamples, brush: brush, size: localSize,
                                             mode: .cutToIntersection) else { return .missed }

        let outcome = cutToIntersection(sweep: sweep, near: localSamples[0].point, cutting: cutting)
        if outcome == .cut { invalidate() }
        return outcome
    }

    // MARK: - Mode 1 — the hybrid
    //
    // Rules documented on `VectorEraser`'s Mode 1 section; this is the adapter onto the display list.
    // Three steps, in order: (1) delete every stroke the eraser covers end to end; (2) split every
    // stroke it covers full-width over a stretch, inset by the stroke's own half-width, into pieces
    // that keep rendering on the parent's dab lattice; (3) punch, always, matching raster-layer erasing
    // exactly (soft edge, partial-width shave, opacity below 1 — none of which geometry alone can do).
    // Steps 1–2 only remove ink step 3 would remove anyway, so they're pixel-invisible; they exist to
    // keep the list from growing forever.

    /// Caller must hold `lock`.
    private func eraseHybrid(sweep: VectorEraser.Sweep, samples localSamples: [VectorSample],
                             brush: Brush, size: CGFloat, opacity: Double) -> Bool {
        var changed = false

        // The lightest dab in the gesture: pressure interpolates linearly between samples, so the
        // minimum over samples is the minimum over every dab stamped.
        let minPressure = localSamples.map(\.pressure).min() ?? 1
        if VectorEraser.supportsCleanCut(brush: brush, opacity: opacity, minPressure: minPressure) {
            let erasers = VectorEraser.cleanCutCapsules(sweep.capsules, brush: brush, size: size)
            if !erasers.isEmpty {
                if removeFullyErasedStrokes(sweep: sweep, erasers: erasers) {
                    changed = true
                    // Bumps `version` so downstream rebuilds its index against the *survivors* —
                    // otherwise the split and residue query below address stale element indices.
                    invalidate()
                }
                if splitCleanlyErasedStrokes(sweep: sweep, erasers: erasers) {
                    changed = true
                    invalidate()
                }
            }
        }

        let hasResidue = VectorEraser.hasResidue(in: localSamples, sweep: sweep) { parameter in
            hasContentBeneath(atParameter: parameter, in: localSamples, brush: brush, size: size)
        }
        if hasResidue {
            // The eraser *is* a stroke, composited `.destinationOut` at render. Appended last, so it
            // punches everything already in the list and nothing drawn after it. Colour is arbitrary —
            // `.destinationOut` reads only the stamp's alpha coverage.
            let punch = VectorStroke(brush: brush,
                                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                     size: size, opacity: opacity, samples: localSamples,
                                     composite: .erase)
            _elements.append(.stroke(punch))
            changed = true
        }

        if collectResidueGarbage() { changed = true }
        return changed
    }

    /// Drops every candidate paint stroke the eraser covers **completely**. Caller must hold `lock`.
    /// Whole strokes only, load-bearing: deleting a fully-covered stroke is pixel-neutral, but cutting
    /// a *piece* out of one re-stamps the remainder and re-anchors its dab lattice and pressure ramp at
    /// the cut.
    private func removeFullyErasedStrokes(sweep: VectorEraser.Sweep,
                                          erasers: [StrokeGeometry.Capsule]) -> Bool {
        // The index holds centrelines, so a stroke whose centreline sits outside the sweep's box can
        // still have ink inside it. Grow the query by the widest half-width on the layer.
        let reach = maxPaintReach()
        let candidates = Set(strokeIndex().segments(near: sweep.bounds.insetBy(dx: -reach, dy: -reach))
            .map(\.elementIndex))
        guard !candidates.isEmpty else { return false }

        var changed = false
        var result: [VectorElement] = []
        result.reserveCapacity(_elements.count)
        for (index, element) in _elements.enumerated() {
            guard candidates.contains(index), let stroke = element.stroke,
                  stroke.composite == .paint,
                  // A scattering stroke throws dabs off its centreline, so the capsule chain the
                  // coverage test uses does not bound its ink.
                  VectorEraser.supportsSplitting(strokeBrush: stroke.brush),
                  VectorEraser.isEntirelyCovered(stroke.samples, brush: stroke.brush, size: stroke.size,
                                                 by: erasers, sweep: sweep) else {
                result.append(element)
                continue
            }
            changed = true
        }
        if changed { _elements = result }
        return changed
    }

    /// Cuts every candidate paint stroke at the spans the eraser covers **full width at full alpha**,
    /// inset by the stroke's own half-width. Caller must hold `lock`.
    ///
    /// Exactness (zero tolerance in the parity tests) needs both: `splitPreservingLattice` renders
    /// pieces on the parent's dab lattice so a cut doesn't re-anchor/re-scatter the remaining ink, and
    /// `VectorEraser.conservativeCuts` insets the cut so the round-cap ink it loses stays a subset of
    /// the covered span. A span too short to survive its own two insets disappears — the punch handles
    /// it alone.
    private func splitCleanlyErasedStrokes(sweep: VectorEraser.Sweep,
                                           erasers: [StrokeGeometry.Capsule]) -> Bool {
        // Same widened query as the deletion pass: the index holds centrelines, and the coverage
        // test asks about a stroke's whole width.
        let reach = maxPaintReach()
        let candidates = Set(strokeIndex().segments(near: sweep.bounds.insetBy(dx: -reach, dy: -reach))
            .map(\.elementIndex))
        guard !candidates.isEmpty else { return false }

        var changed = false
        var result: [VectorElement] = []
        result.reserveCapacity(_elements.count)
        for (index, element) in _elements.enumerated() {
            guard candidates.contains(index), let stroke = element.stroke,
                  stroke.composite == .paint,
                  // A lone dab has no length to cut; `isEntirelyCovered` in the deletion pass above
                  // is the only way a single-sample stroke goes.
                  stroke.samples.count > 1,
                  // As in the deletion pass: a scattering stroke's ink isn't bounded by the capsule
                  // chain the coverage test measures.
                  VectorEraser.supportsSplitting(strokeBrush: stroke.brush) else {
                result.append(element)
                continue
            }
            let clean = VectorEraser.cleanCutRanges(in: stroke.samples, brush: stroke.brush,
                                                    size: stroke.size, by: erasers, sweep: sweep)
            let inset = VectorEraser.conservativeCuts(clean, in: stroke.samples, brush: stroke.brush,
                                                      size: stroke.size, by: erasers)
            let cuts = Self.effectiveCuts(inset, in: stroke.samples)
            guard !cuts.isEmpty else {
                result.append(element)
                continue
            }
            changed = true
            for piece in Self.splitPreservingLattice(stroke, removing: cuts) {
                result.append(.stroke(piece))
            }
        }
        if changed { _elements = result }
        return changed
    }

    /// `stroke` cut into pieces that keep rendering on the same dab lattice the original did. Static,
    /// so it cannot re-enter `lock`.
    ///
    /// A piece's `samples` are its own geometry (interpolated at the cut); its `lattice` says where in
    /// the parent's walk those samples came from. Cutting a piece again composes: the new run's
    /// parameters are mapped back through the piece's own lattice, so the grandchild points at the
    /// original ancestor's samples directly.
    private static func splitPreservingLattice(_ stroke: VectorStroke,
                                               removing cuts: [ClosedRange<CGFloat>]) -> [VectorStroke] {
        let parentSamples = stroke.lattice?.samples ?? stroke.samples
        let seedID = stroke.lattice?.seedID ?? stroke.id
        return StrokeGeometry.splitStrokeRuns(stroke.samples, removing: cuts).map { run in
            var piece = stroke
            // Fresh id: two pieces cannot share one. The dab seed travels via `DabLattice.seedID`
            // instead.
            piece.id = UUID()
            piece.samples = run.samples
            let parameters = stroke.lattice.map { run.parameters.map($0.parentParameter(of:)) }
                ?? run.parameters
            piece.lattice = DabLattice(samples: parentSamples, parameters: parameters, seedID: seedID)
            return piece
        }
    }

    /// Whether the eraser's dab at a parametric position along the gesture still has anything under it
    /// — the predicate behind residue trimming. Caller must hold `lock`.
    private func hasContentBeneath(atParameter parameter: CGFloat, in samples: [VectorSample],
                                   brush: Brush, size: CGFloat) -> Bool {
        guard let dab = StrokeGeometry.interpolatedSample(in: samples, at: parameter) else { return false }
        let radius = StrokeGeometry.stampRadius(forPressure: dab.pressure, brush: brush, size: size)
        let box = CGRect(x: dab.x - radius, y: dab.y - radius, width: radius * 2, height: radius * 2)

        // Fills and images have no geometry the split could have removed, so any overlap means the
        // punch is still doing work. Bounding boxes rather than exact paths: conservative in the safe
        // direction, and cheaper than a fill's exact containment test per probe.
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

    /// Garbage collection: a retained `.erase` element is dropped once nothing *beneath it* (not
    /// anywhere — elements added after the punch were never affected by it) in the display list still
    /// reaches its bounding box. Caller must hold `lock`. Run on commit rather than per frame, since a
    /// stale punch renders as an invisible hole in nothing in the meantime. Each element's box is
    /// derived once and tested against the accumulated list — `O(n)` rather than `O(p · n)` for `p`
    /// punches.
    private func collectResidueGarbage() -> Bool {
        guard _elements.contains(where: { $0.stroke?.composite == .erase }) else { return false }
        let reach = maxPaintReach()
        var kept: [VectorElement] = []
        kept.reserveCapacity(_elements.count)
        // Boxes of content already passed over, i.e. everything *beneath* the punch under
        // consideration. `.erase` elements contribute nothing — a punch is not content for another.
        var boxesBeneath: [CGRect] = []
        boxesBeneath.reserveCapacity(_elements.count)
        var dropped = false
        for element in _elements {
            guard let stroke = element.stroke, stroke.composite == .erase else {
                kept.append(element)
                if let box = Self.contentBounds(of: element) { boxesBeneath.append(box) }
                continue
            }
            let punchReach = StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush, size: stroke.size)
            guard let box = StrokeGeometry.bounds(of: stroke.samples, padding: punchReach + reach) else {
                dropped = true
                continue
            }
            if boxesBeneath.contains(where: { $0.intersects(box) }) {
                kept.append(element)
            } else {
                dropped = true
            }
        }
        if dropped { _elements = kept }
        return dropped
    }

    /// An element's local-space bounding box as a *backdrop* — what a punch above it can be keeping
    /// alive. Nil for anything that is not content (an `.erase` element punches ink, it never is any).
    private static func contentBounds(of element: VectorElement) -> CGRect? {
        switch element {
        case .stroke(let stroke):
            guard stroke.composite == .paint else { return nil }
            return StrokeGeometry.bounds(of: stroke.samples)
        case .fill(let fill):
            return fill.cgPath?.boundingBoxOfPath
        case .image(let image):
            return bounds(of: image)
        }
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
                // Fills and images are untouched by a geometric eraser.
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
                // Mode 2 removes geometry, so a piece re-stamps from its own first sample rather than
                // inheriting the parent's lattice, which would keep drawing dabs just cut away.
                piece.lattice = nil
                result.append(.stroke(piece))
            }
        }
        if changed { _elements = result }
        return changed
    }

    /// Mode 3: the one stroke the eraser came down on loses the span between its two neighbouring
    /// crossings. Caller must hold `lock`. `cutting: false` reports whether a target was found
    /// without mutating anything — see `cutToIntersection(atCanvasPoint:…)`.
    private func cutToIntersection(sweep: VectorEraser.Sweep, near hitPoint: CGPoint,
                                   cutting: Bool = true) -> VectorEraser.CutOutcome {
        let index = strokeIndex()
        let candidates = Set(index.segments(near: sweep.bounds).map(\.elementIndex))
        guard !candidates.isEmpty else { return .missed }

        // The stroke the eraser came down on: nearest centreline among the candidates, only if the
        // eraser's footprint actually reaches it (a near miss cuts nothing).
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
        // `.missed` — the driver must stay disarmed until the finger leaves the stroke.
        guard cutting else { return .unchanged }

        // Everything that could cross it, with a width-aware tolerance per pair: lines whose ink
        // visibly touches read as crossed even when the centrelines miss.
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
            // As in Mode 2: deletes geometry, so the piece is its own stroke from here on.
            piece.lattice = nil
            pieces.append(.stroke(piece))
        }
        _elements.replaceSubrange(target.index...target.index, with: pieces)
        return .cut
    }

    /// `cuts` reduced to what actually removes something, so a graze that merely touches a stroke's
    /// geometry doesn't churn it (rebuild with a fresh id and re-rolled dab pattern) without deleting
    /// anything. Ranges are merged/clamped to the run's domain first; then zero-width ranges are
    /// dropped, since on a multi-sample run they only arise from a repeated sample or boundary graze. A
    /// single-sample run is exempt — its whole domain *is* `0...0`, and removing that is how a lone dab
    /// gets erased.
    private static func effectiveCuts(_ cuts: [ClosedRange<CGFloat>],
                                      in samples: [VectorSample]) -> [ClosedRange<CGFloat>] {
        guard !samples.isEmpty else { return [] }
        let domainEnd = CGFloat(samples.count - 1)
        let merged = StrokeGeometry.mergedCuts(cuts, clampedTo: 0...domainEnd)
        guard samples.count > 1 else { return merged }
        return merged.filter { $0.upperBound - $0.lowerBound > StrokeGeometry.epsilon }
    }

    /// A uniform grid over every stroke's segments, keyed by `version` so it's rebuilt the first time
    /// anything asks after a mutation. Bounds query cost to what the gesture touched; used by Mode 3's
    /// intersection search, Mode 1's coverage test, and residue GC.
    ///
    /// Caller must hold `lock`: `segments(near:)` stamps a per-query visit marker to de-duplicate refs
    /// across cells, so it mutates during a *read*.
    ///
    /// Segment boxes are inserted with **no padding** — the index answers questions about stroke
    /// *centrelines*. Mode 1's coverage test asks about a stroke's own *width*, so it expands its query
    /// rect by the widest half-width on the layer.
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

    // MARK: - Hit testing

    /// The **topmost** paint stroke whose ink covers `point`, or nil for a tap on bare canvas. Used by
    /// the retagging gesture (`CanvasManager.assignArmedMotionGroup(atCanvasPoint:)`).
    ///
    /// Measured against the stroke's **ink**: the query rect is grown by the layer's widest half-width
    /// and each candidate tested against its own stamp radius. `slop` widens the target beyond the ink
    /// for a fingertip, added to the stroke's own radius so a hairline stays tappable.
    ///
    /// Erasers are skipped. Fills and placed images cannot carry a tag at all (see
    /// `VECTOR_INTERPOLATION.md` §4 item 11).
    func topmostStroke(atCanvasPoint point: CGPoint, slop: CGFloat = 6) -> VectorStroke? {
        lock.lock()
        defer { lock.unlock() }
        let reach = maxPaintReach() + slop
        guard reach > 0 else { return nil }
        let box = CGRect(x: point.x - reach, y: point.y - reach, width: reach * 2, height: reach * 2)

        var best: Int?
        for ref in strokeIndex().segments(near: box) {
            if let best, ref.elementIndex <= best { continue }
            guard let stroke = _elements[ref.elementIndex].stroke, stroke.composite == .paint,
                  stroke.samples.indices.contains(ref.sampleIndex) else { continue }
            let a = stroke.samples[ref.sampleIndex].point
            let b = stroke.samples[min(ref.sampleIndex + 1, stroke.samples.count - 1)].point
            let limit = slop + StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush,
                                                          size: stroke.size)
            if StrokeGeometry.distanceSquared(from: point, toSegment: a, b) <= limit * limit {
                best = ref.elementIndex
            }
        }
        return best.flatMap { _elements[$0].stroke }
    }

    // MARK: - Rendering

    /// Rasterizes all content to a canvas-native `UIImage` (cached by `version`, one slot per
    /// quality). Strokes are stamped via `BrushStamper`; images drawn with their transforms; then the
    /// whole thing is drawn through the overall `transform`.
    ///
    /// `quality` changes only how a *stroke* is put down — see `RenderQuality`. The isolation rules
    /// that make an eraser correct are identical for both.
    func render(quality: RenderQuality = .full) -> UIImage {
        lock.lock()
        defer { lock.unlock() }
        switch quality {
        case .full: if let cachedImage { return cachedImage }
        case .preview: if let cachedPreviewImage { return cachedPreviewImage }
        }
        let bounds = CGRect(origin: .zero, size: size)
        let format = PixelOps.transparentFormat()

        // 1. Content in local (untransformed) space.
        let content = renderLocalContent(quality: quality)

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
        switch quality {
        case .full: cachedImage = final
        case .preview: cachedPreviewImage = final
        }
        return final
    }

    /// Step 1 of `render()`: the layer's own content stamped at native resolution, before the overall
    /// `transform` is applied. Not cached — only called from `render()` and `localContentBounds()`.
    /// Caller must hold `lock` for the whole rasterization. Strokes stamp straight into this
    /// renderer's own context via `CGContextDabTarget` rather than a throwaway `RasterLayerTexture`,
    /// avoiding an extra canvas-sized `CGContext`+`CGImage` per invalidation.
    ///
    /// **The isolation-group rule.** Strokes can be interleaved with fills, images and erasers, so
    /// blend-mode isolation is scoped explicitly:
    ///
    /// 1. A *paint run* is a maximal stretch of consecutive `.paint` stroke elements; any fill, image,
    ///    or `.erase` stroke ends it.
    /// 2. If any stroke in a run has a non-`.normal` blend mode, the whole run is wrapped in one
    ///    transparency layer so its strokes blend against each other but not what's beneath them. An
    ///    all-`.normal` run opens no layer — source-over is associative, so drawing straight into the
    ///    context is identical, and it's the common case.
    /// 3. An `.erase` stroke is never inside a transparency layer: it punches `.destinationOut` against
    ///    the accumulated context, lowering the alpha of everything beneath it — punching inside a
    ///    layer would only eat that group's own pixels.
    ///
    /// `insertionIndex(forKind:in:)` keeps fills/images ahead of strokes, so ordinary content has
    /// exactly one paint run. `quality` doesn't reach this logic — only `Self.draw(stroke:…)` branches
    /// on it — since the isolation rules must hold for a preview too.
    private func renderLocalContent(quality: RenderQuality = .full) -> UIImage {
        // `.standard` is load-bearing: `.preferredRange` defaults to `.automatic`, which on a
        // wide-colour iPad backs the context with an extended-range 16-bit bitmap, and stamping
        // thousands of radial gradients into that is drastically slower than into 8-bit. No fidelity
        // is lost — every raster tier already renders and persists as 8-bit deviceRGB.
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard
        let elements = _elements
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            // One target — and so one `DabGradientCache` — for the whole walk: a per-run target would
            // throw away the cache's hit rate at every fill or eraser.
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
                    Self.draw(stroke: stroke, into: cg, target: target, isEraser: true, quality: quality)
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
                        Self.draw(stroke: stroke, into: cg, target: target, isEraser: false, quality: quality)
                    }
                    if needsIsolation { cg.endTransparencyLayer() }
                    index = end
                }
            }
        }
    }

    // The per-kind drawing helpers are `static`, taking only their inputs, so they cannot re-enter
    // the caller's non-reentrant `lock`.

    /// The `.paint` stroke at `index`, or nil if out of range or another kind — the run terminator
    /// for `renderLocalContent`'s scan.
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
        // Reset here rather than after a whole block of fills: in an interleaved list a leftover
        // global alpha would dim whatever element came next.
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

    /// Replays one stored stroke. The seed is derived from the stroke's id so a `scatter`/
    /// `rotationJitter` brush's dabs stay stable across invalidations and save/load — see
    /// `BrushStamper.DabRNG`.
    ///
    /// The one place a stroke's `lattice` is read: a piece is stamped by replaying its **parent's**
    /// walk under the parent's seed, drawing only the dabs in the piece's range — see `DabLattice`.
    /// `target` is the dab sink for `.full`; `cg` is the context `.preview` strokes into — the same
    /// context `target` wraps, so both qualities land under the same transparency layer.
    private static func draw(stroke: VectorStroke, into cg: CGContext, target: DabTarget,
                             isEraser: Bool, quality: RenderQuality) {
        switch quality {
        case .full: stamp(stroke: stroke, into: target, isEraser: isEraser)
        case .preview: strokePolyline(stroke: stroke, into: cg, isEraser: isEraser)
        }
    }

    /// One stroked `CGPath` in place of the stroke's hundreds of dabs — the `.preview` tier.
    ///
    /// Uses the stroke's **own** samples even for a piece carrying a `DabLattice`: the lattice exists
    /// to reproduce the parent's dab *phase*, and there are no dabs here.
    ///
    /// Width and opacity are taken once, at the mean pressure, rather than ramped per dab — a varying
    /// width would need one stroked path per segment, giving back most of the cost this tier saves.
    private static func strokePolyline(stroke: VectorStroke, into cg: CGContext, isEraser: Bool) {
        guard let first = stroke.samples.first else { return }
        let meanPressure = Double(stroke.samples.reduce(0) { $0 + $1.pressure })
            / Double(stroke.samples.count)
        let width = max(stroke.size * CGFloat(stroke.brush.dynamics.sizeFraction(forPressure: meanPressure)), 0.5)

        let path = CGMutablePath()
        path.move(to: first.point)
        for sample in stroke.samples.dropFirst() {
            path.addLine(to: sample.point)
        }
        // A one-sample stroke is a dot: a zero-length path under a round cap draws the cap, which is
        // the same disc a single dab would have left.
        if stroke.samples.count == 1 {
            path.addLine(to: first.point)
        }

        cg.saveGState()
        cg.setLineWidth(width)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        if isEraser {
            // `.destinationOut` with an opaque stroke colour punches at full coverage, matching the
            // eraser dab path where `color` is ignored and only the stamp's alpha counts.
            cg.setBlendMode(.destinationOut)
            cg.setStrokeColor(UIColor.black.cgColor)
        } else {
            cg.setBlendMode(stroke.brush.blendMode.cgBlendMode)
            cg.setStrokeColor(stroke.uiColor.cgColor)
            cg.setAlpha(CGFloat(stroke.opacity
                                * stroke.brush.dynamics.opacityFraction(forPressure: meanPressure)))
        }
        cg.addPath(path)
        cg.strokePath()
        cg.restoreGState()
    }

    private static func stamp(stroke: VectorStroke, into target: DabTarget, isEraser: Bool) {
        // A lattice without a usable range would otherwise stamp the *parent* whole, which is worse
        // than either option — so an unreadable one falls back to the stroke's own geometry.
        let lattice = stroke.lattice.flatMap { $0.range == nil ? nil : $0 }
        let source = lattice?.samples ?? stroke.samples
        let samples = source.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
        BrushStamper.stampStroke(into: target, samples: samples, brush: stroke.brush,
                                 color: stroke.uiColor, brushSize: stroke.size,
                                 brushOpacity: stroke.opacity, isEraser: isEraser,
                                 seed: BrushStamper.seed(for: lattice?.seedID ?? stroke.id),
                                 visibleRange: lattice?.range)
    }
}

// MARK: - Persistence payload

/// Codable snapshot of a `VectorCanvas` for saving as JSON alongside the project. Stores the
/// **ordered display list** so a saved project keeps its z-order rather than being re-flattened into
/// three kind-buckets. Images are stored by file name only (PNGs written separately by
/// `ProjectStore`, since `UIImage` isn't `Codable`); strokes and fills are stored inline.
struct VectorCanvasData: Codable {
    struct ImageRef: Codable {
        var fileName: String
        var x: Double
        var y: Double
        var scale: Double
        var rotation: Double
    }

    /// The persisted form of one `VectorElement`. Written with an explicit `kind` discriminator rather
    /// than Swift's synthesized enum encoding, so the on-disk shape is human-readable and extensible.
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

    /// Kind-filtered reads of the display list, mirroring `VectorCanvas`'s compatibility accessors.
    /// Read-only: a caller that needs the order should use `elements(resolvingImages:)`.
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
                // An image whose PNG was never written has no name to reference, so it is dropped
                // rather than persisted as a dangling ref.
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
        // Legacy payload: three parallel arrays and no z-order. Rebuild the old draw order — fills,
        // images, then strokes — so an existing project opens looking as it did.
        let strokes = try c.decode([VectorStroke].self, forKey: .strokes)
        let fills = try c.decode([VectorFillElement].self, forKey: .fills)
        let images = try c.decode([ImageRef].self, forKey: .images)
        elements = fills.map { .fill($0) } + images.map { .image($0) } + strokes.map { .stroke($0) }
    }

    /// Legacy arrays are deliberately *not* mirrored alongside the ordered form: an `.erase` stroke
    /// listed in a legacy `strokes` array would render as paint in an older build.
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
