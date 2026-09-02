import UIKit
import CoreGraphics
import os

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
    /// Whether `samples` is **stored** at full precision rather than on the quarter-pixel grid —
    /// TODO item (14), and the owner's *"when the option is turned on, it gets stored as doubles"*.
    ///
    /// **Not its own persisted key.** It is *derived* from the wire form on decode (a run declared
    /// float32 → precise) and *drives* the wire form on encode; `VectorSample.decodeRun` and
    /// `VectorSample.packed(_:for:precise:)` are the two ends of that. A key of its own would be a
    /// second copy of a fact the run already states, and the two could disagree — the argument
    /// `Lattice`'s persistence extension makes about derivable data.
    ///
    /// In memory this changes nothing: `samples` was three `CGFloat` before item (8), still is, and a
    /// Move has always been exact within one sitting. What the flag buys is the *round trip* — a
    /// stroke shrunk to 2% and stored comes back **8.57 pt** out on the quarter-pixel grid and
    /// **5.0e-5 pt** out on this one (MEASURED; `PackedSampleRun.Precision.float32` carries the table).
    /// It costs **1.72x** the bytes a sample until the artist bakes it
    /// (`CanvasManager.bakePreciseStrokes`).
    var precise: Bool = false
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

    /// Saturating a coordinate at the storage boundary is ink the artist drew and will not get back,
    /// so it is said out loud exactly once, on the save that loses it. `encode(to:)` is the only user.
    static let log = Logger(subsystem: "Starg.PaintSoftware", category: "SampleCoding")

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
    /// `VectorStroke.precise` for *this* walk — same field, same derivation, same reason. A piece's
    /// lattice is its parent's whole walk and is mapped by the very transform the piece's own samples
    /// are, so a precise piece whose lattice stayed quantised would come back with its dabs on a
    /// coarser grid than its own centre line. The invariant that keeps the two in step is stated and
    /// enforced at the one site that sets either — `VectorStroke.markedPrecise()`.
    var precise: Bool = false

    /// The parent parameters this piece shows. Nil-return keeps the renderer honest on a decoded
    /// file rather than crashing, even though empty `parameters` shouldn't occur for a real stroke.
    var range: ClosedRange<CGFloat>? {
        guard let low = parameters.first, let high = parameters.last, high >= low else { return nil }
        return low...high
    }

    /// Hand-written for one reason: `samples` is persisted as a packed quarter-pixel run like every
    /// other run of samples (TODO item (8)), and a synthesized coder would write the parent's whole
    /// walk back out as `{"x":…,"y":…,"pressure":…}` objects — the larger half of a cut-heavy cel.
    /// Declared in an extension below so this stays a memberwise-initialisable struct.
    enum CodingKeys: String, CodingKey { case samples, parameters, seedID }

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

extension DabLattice {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let run = try VectorSample.decodeRun(from: c, forKey: .samples)
        samples = run.samples
        // Derived from the run's own shape, exactly as a stroke's is — see `precise`.
        precise = run.precise
        parameters = try c.decode([CGFloat].self, forKey: .parameters)
        seedID = try c.decode(UUID.self, forKey: .seedID)
    }

    /// A lattice's clamp count is deliberately not logged: it is the *parent's* walk, so a piece that
    /// saturates has already said so through the stroke it was cut from.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(VectorSample.packed(samples, for: encoder, precise: precise), forKey: .samples)
        try c.encode(parameters, forKey: .parameters)
        try c.encode(seedID, forKey: .seedID)
    }
}

extension VectorStroke {

    /// This stroke marked as stored at full precision — **and the lattice it walks with it**.
    ///
    /// **The one site that sets either flag, so the invariant is stated once and cannot be half-kept.**
    /// A piece's `lattice.samples` is the parent's whole walk, and `VectorCanvas.mapping` maps it by
    /// the very transform it maps `samples` by (see `drawn(_:through:widthScale:)`), so the two are
    /// one geometry with one provenance. Marking the stroke and leaving the lattice quantised would
    /// store a centre line the artist can regrow exactly and a dab walk they cannot — the piece would
    /// come back with its dabs re-phased against its own spine, which is precisely the failure
    /// `DabLattice` exists to prevent.
    ///
    /// Idempotent, and cheap on a stroke that is already precise: nothing here touches `samples`.
    func markedPrecise() -> VectorStroke {
        var copy = self
        copy.precise = true
        copy.lattice?.precise = true
        return copy
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
        let run = try VectorSample.decodeRun(from: c, forKey: .samples)
        samples = run.samples
        // Derived, never read from a key of its own — see `precise`.
        precise = run.precise
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
        // TODO item (8): quarter-pixel fixed point, five bytes a sample — or item (14)'s float32
        // layout when this stroke is marked precise, at nine. `packed` reads the quantisation origin
        // off the encoder and writes it into the payload, so a decoder needs no context; see
        // `PackedSampleRun`.
        let packed = VectorSample.packed(samples, for: encoder, precise: precise)
        if packed.clampedCount > 0 {
            VectorStroke.log.error("""
                \(packed.clampedCount, privacy: .public) of \(samples.count, privacy: .public) samples on \
                stroke \(id.uuidString, privacy: .public) are outside the storable range about \
                (\(packed.origin.x, privacy: .public), \(packed.origin.y, privacy: .public)) and saturate — \
                that ink is flattened onto the boundary. See BUGS.md's unclamped zoom.
                """)
        }
        if packed.nonFiniteCount > 0 {
            VectorStroke.log.error("""
                \(packed.nonFiniteCount, privacy: .public) of \(samples.count, privacy: .public) samples on \
                stroke \(id.uuidString, privacy: .public) have a coordinate that is not a number and are \
                stored at the origin — a defect upstream of storage, and it is reported in both layouts \
                because a precise stroke has no clamp to notice it instead.
                """)
        }
        try c.encode(packed, forKey: .samples)
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
    /// A live text object — `ADD_TEXT.md` stage 3. **The only case whose payload is already its own
    /// persisted form**: it holds no runtime resource, so unlike `.image` it needs none of the
    /// `ImageRef` / `<project>/images/` machinery, and `VectorCanvasData.ElementData.text` stores the
    /// very same value inline.
    case text(VectorTextElement)

    var id: UUID {
        switch self {
        case .stroke(let stroke): return stroke.id
        case .fill(let fill): return fill.id
        case .image(let image): return image.id
        case .text(let text): return text.id
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

    var text: VectorTextElement? {
        if case .text(let text) = self { return text }
        return nil
    }
}

/// **Which of three rules decides what a lasso move carries** — how much of a drawing travels when
/// the loop covers only part of it.
///
/// The owner, 2026-08-28: *"There should be an option of three where instead of cutting the lines
/// outside the selection, it moves all the lines including the ones partially inside the selection,
/// or only the ones fully inside. The third option is the current behaviour."* (TODO item (20).)
///
/// **Ordered by how much travels, with the default in the middle**, which is what lets the picker
/// read as a dial rather than as three unrelated buttons: `enclosed` takes the least, `cutting`
/// takes exactly what is inside, `touching` takes the most. `.cutting` is the default and is
/// bit-for-bit the behaviour that shipped, so nothing changes until the artist touches the picker.
///
/// **The two new modes are cheaper and safer than the one that ships**, which inverts the usual
/// expectation: neither cuts anything, so there is no bisection, no boundary dab, no fresh ids, no
/// lattice re-keying and — the one that matters — no interpolation-tier demotion, since the stroke
/// count is unchanged. `VectorCanvas.liftWholeCel` is the working proof that a float which splits
/// nothing shares every nudge, bake and teardown path with one that does.
///
/// **Not persisted, deliberately** (owner's ask, 2026-08-28): this is per-drawing intent, the line
/// `CanvasManager.preserveMovePrecision` already draws. Storing it would make *last used* the
/// default, which is not what was asked for. It lives on `CanvasManager.lassoMoveMembership` for the
/// length of a session and nowhere else — there is no `@AppStorage` anywhere in this project.
enum LassoMembership: String, CaseIterable, Identifiable {
    /// **Enclosed** — only what lies *entirely* inside the loop travels, whole and uncut. A stroke
    /// that pokes out anywhere is left where it is.
    ///
    /// This is the one mode that can catch nothing on a loop full of ink, which is why
    /// `CanvasManager.beginVectorLassoMove` says so rather than failing silently: LASSO_MOVE.md
    /// §5.9's silent empty lasso was over blank paper, where the artist can see the reason.
    case enclosed
    /// **Cut** — the shipped rule, and the default. A stroke crossing the loop is cut in two at the
    /// boundary and the inside piece travels (LASSO_MOVE.md §5.1–5.2); a fill loses the chunk that
    /// was inside; and text and a placed image, which cannot be cut, keep the **centre** rule that
    /// has always been the cut rule rounded to the nearest whole object.
    case cutting
    /// **Touching** — anything the loop touches at all travels, whole and uncut, ink outside the
    /// loop included. This is `VectorCanvas.elementIDs(insideLocalPath:)`'s existing predicate, the
    /// one item (19)'s Change Colour already uses, with images and text answered by their own quad
    /// rather than their centre.
    case touching

    var id: String { rawValue }

    /// The segment's label. Three words the artist can hold in their head, not the internal names.
    var displayName: String {
        switch self {
        case .enclosed: return "Enclosed"
        case .cutting:  return "Cut"
        case .touching: return "Touching"
        }
    }

    /// One line under the picker saying what the selected segment does — the same job
    /// `MoveTransformBottomBar`'s "Coming soon — acts like Uniform for now" caption does, and needed
    /// for the same reason: the difference between the three is invisible until the artist has
    /// already moved something.
    var explanation: String {
        switch self {
        case .enclosed: return "Moves only what lies completely inside the loop."
        case .cutting:  return "Cuts at the loop and moves what is inside."
        case .touching: return "Moves anything the loop touches, whole."
        }
    }

    /// Whether this mode cuts geometry at the boundary. Only `.cutting` does, and that is the whole
    /// difference in the engine: the other two classify and lift, and change no element at all.
    var cutsAtTheBoundary: Bool { self == .cutting }
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
    /// Backing store for `suppressedElementIDs`/`editingElementID`; see there.
    private var _suppressedElementIDs: Set<UUID> = []

    /// The display list itself. Existing code keeps using the three kind-filtered accessors below.
    var elements: [VectorElement] {
        get { lock.lock(); defer { lock.unlock() }; return _elements }
        set { lock.lock(); defer { lock.unlock() }; _elements = newValue }
    }

    // MARK: - Kind-filtered compatibility accessors
    //
    // Getters filter the display list; setters splice **positionally** — the i-th element of that kind
    // is replaced where it already sits — so a get→set round trip is the identity even for a kind that
    // is interleaved with others, which fills and text both are (`addFill`, `upsertText`). See
    // `splicing` for the two ragged cases. Setters do not invalidate — callers follow with
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

    /// The layer's text objects, back to front.
    ///
    /// The setter obeys the same splice contract as the three above. `commitInteractiveText` does
    /// **not** use it: it upserts through `upsertText(_:)` and undoes by swapping the whole `elements`
    /// array (`registerVectorElementsUndo`), which is what a *shorter* or *longer* list needs — the
    /// positional splice can only preserve the z-positions of elements that already exist. Every fill
    /// mutation goes the same way, for the same reason.
    var texts: [VectorTextElement] {
        get { lock.lock(); defer { lock.unlock() }; return _elements.compactMap(\.text) }
        set {
            lock.lock()
            defer { lock.unlock() }
            _elements = Self.splicing(_elements, kind: .text, with: newValue.map { .text($0) })
        }
    }

    /// The elements skipped by the flatten while something else is drawing them: the one text object
    /// whose editor is open, or the set a lasso move has lifted into a floating piece.
    ///
    /// **The committed elements are never lifted out of `_elements`** — `ADD_TEXT.md` §1 and §2 both
    /// argue that at length. Lifting makes the persisted source of truth momentarily not contain an
    /// object the artist already committed, on the one device whose `Compositor` header documents
    /// jetsam killing the process rather than `makeTexture` failing gracefully, and it also removes
    /// the object from thumbnails, the layer panel and other cels mid-edit. It buys nothing either,
    /// because the `strokes`/`fills`/`images` setters splice without invalidating and callers follow
    /// with `bumpVersion()`, so a lift costs a version bump exactly like this flag does.
    ///
    /// Transient: not persisted, and not carried by `makeCopy()`/`resized(to:offset:)`. Assigning it
    /// invalidates, which is precisely the **two `invalidate()` calls per session** §4 rule 4 allows —
    /// one as the session opens, one as it commits — and no more, because nothing else during a
    /// session touches this canvas at all.
    ///
    /// **A set rather than one id, because the lasso move suppresses many at once.** A float holds a
    /// whole region's worth of split pieces, and the alternative — the raster path's canvas-sized
    /// `remainderPreview` (`SelectionModels.swift`) — is a full bitmap per lift where this is a
    /// `Set<UUID>`. A leaked entry is artwork that is in the saved document, counts toward every
    /// bound, and renders nowhere, so every teardown path clears it and
    /// `LassoMoveLogicTests.testEveryTeardownPathLeavesNothingSuppressedAndNothingDropped` enumerates
    /// them.
    var suppressedElementIDs: Set<UUID> {
        get { lock.lock(); defer { lock.unlock() }; return _suppressedElementIDs }
        set {
            lock.lock()
            defer { lock.unlock() }
            guard _suppressedElementIDs != newValue else { return }
            _suppressedElementIDs = newValue
            invalidate()
        }
    }

    /// The text editor's half of `suppressedElementIDs`, kept as a one-element view over it so
    /// `CanvasManager+Text`'s assignments read as they always did. Setting it replaces the whole set,
    /// which is correct because a text edit session and a lasso move cannot be open at once —
    /// `beginVectorLassoMove` calls `commitAllInteractiveState()` first, and the text overlay's own
    /// session commits there.
    var editingElementID: UUID? {
        get { suppressedElementIDs.first }
        set { suppressedElementIDs = newValue.map { [$0] } ?? [] }
    }

    /// Move/rotate/scale of the entire layer's content, applied at render time so it stays crisp.
    /// Identity until the layer is transformed.
    var transform: CGAffineTransform {
        get { lock.lock(); defer { lock.unlock() }; return _transform }
        set { lock.lock(); defer { lock.unlock() }; _transform = newValue }
    }

    private(set) var version: Int = 0

    /// Bumped by every change to `_elements` (and to `editingElementID`, which filters them), and
    /// **deliberately not by `setTransform`**: an overall transform moves the layer's content in
    /// canvas space and leaves it exactly where it was in the layer's own local space. Anything
    /// derived from the *local* content can therefore be memoized across a transform, which is what
    /// `localContentBounds()` does and what takes the two canvas-sized rasterizations out of a Move
    /// drag's per-touch-move cost. `version` still moves on a transform, because the display really
    /// is stale.
    private(set) var contentVersion: Int = 0

    private var cachedImage: UIImage?

    /// The `.preview` render, memoized separately from `cachedImage` — releasing the slider renders
    /// `.full` and must not discard `.preview`, and starting a drag must not discard `.full`.
    private var cachedPreviewImage: UIImage?

    /// Dabs stamped by the most recent `render(quality:)` call that actually rasterized (i.e. missed
    /// both caches) — 0 whenever that call resolved from `cachedImage`/`cachedPreviewImage`. `.full`
    /// stamps one dab per `stampSpacing` interval via `BrushStamper`; `.preview` never touches
    /// `DabTarget` at all, since `strokePolyline` draws one stroked `CGPath` per stroke instead — see
    /// `draw(stroke:into:target:isEraser:quality:)`. Test seam for
    /// `testPreviewIsSubstantiallyCheaperThanFull`, which asserts on this countable difference instead
    /// of wall-clock time.
    private(set) var lastRenderDabCount: Int = 0

    /// How many canvas-sized rasterizations this canvas has actually performed — `render()` calls that
    /// missed both memos, plus every `renderIsolated(ids:)`, which is never memoized.
    ///
    /// A test seam, in `localContentBoundsRasterizations`' idiom and for its reason: **the lasso
    /// move's cost model is a claim about the design, not about the machine.** "Three renders for the
    /// whole move, however many times the artist nudges it" is countable; the milliseconds it takes
    /// are the laptop's business and would assert nothing about whether the latch is working.
    private(set) var rasterizations: Int = 0

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

    /// A new canvas sized to `newSize` with this canvas's whole extent re-placed into `content` (a
    /// rectangle in the *new* canvas's point space), used by every canvas resize.
    ///
    /// **A rectangle rather than the `offset: CGPoint` this took until CANVAS_RESIZE.md stage 1.** The
    /// rect is required to be a *uniform* placement — `content.size` is `k` times this canvas's size
    /// on both axes — because the map it builds is handed to `mapping(_:throughSimilarity:)`, whose
    /// whole contract is that one scalar `k` stands for both axis widths (a per-axis stretch has no
    /// correct `stroke.size`; CANVAS_RESIZE.md §3). Stage 1 only ever passes `k == 1`.
    ///
    /// **The scale lands in the elements, never in `_transform`** — CANVAS_RESIZE.md §2's one-line
    /// trap. `render()` rasterizes the display list at canvas size *first* and applies `_transform` to
    /// that bitmap, so folding a scale into the transform is a bitmap magnify of the vector render
    /// wearing a vector operation's name. Baking through `mapping` re-stamps the brush at the new
    /// size on the next render, which is the entire reason the tier exists.
    ///
    /// **The shift is baked into the geometry and the new canvas is identity** — TODO item (12)
    /// stage 3. It used to *append* the translation to `_transform` and hand back the same local
    /// display list, which is where every non-identity transform in the owner's documents came from:
    /// `setCanvasPadding` walks every cel of every layer, so one use of the slider left one on every
    /// cel in the file, and each of those then clipped later canvas-space ink in local space (the
    /// defect stage 1 closed for the Move box). Nothing writes `_transform` any more, so with this
    /// line the app has no producer of a non-identity cel transform at all, which is what makes a
    /// stored sample a canvas coordinate — the precondition TODO item (8) was blocked on.
    ///
    /// Still lossless, and for a stronger reason than before: a translation moves no sample onto a
    /// different sub-pixel and re-stamps nothing, so `mapping`'s three floors cannot bind. The
    /// composition with `_transform` is kept rather than assumed away — a canvas handed in with one
    /// (a test, or a document decoded by a build older than stage 3) bakes both at once.
    func resized(to newSize: CGSize, placing content: CGRect) -> VectorCanvas {
        lock.lock()
        defer { lock.unlock() }
        let k = size.width > 0 ? content.width / size.width : 1
        assert(size.height <= 0 || abs(content.height / size.height - k) < 1e-9,
               "resized(to:placing:) takes a uniform placement — `mapping(_:throughSimilarity:)` asserts a similarity, and a per-axis stretch has no correct stroke size (CANVAS_RESIZE.md §3)")
        // `.scaledBy` after `translationX:` means *scale first, then translate* — the order §2 pins,
        // and the other one reads identically and is wrong.
        let placement = CGAffineTransform(translationX: content.minX, y: content.minY).scaledBy(x: k, y: k)
        let baked = _transform.concatenating(placement)
        let moved = baked.isIdentity ? _elements : _elements.map { Self.mapping($0, throughSimilarity: baked) }
        return VectorCanvas(size: newSize, elements: moved)
    }

    // MARK: - Display-list ordering
    //
    // All `static`, so a method holding the non-reentrant `lock` can call them without re-entering it.

    /// **`.text` sits below `.stroke` here, and that ordering is load-bearing rather than
    /// alphabetical.** `insertionIndex` puts a new element after every element of the same or lower
    /// kind, so keeping `.stroke` the highest is what makes a new brush stroke land at the very end
    /// of the list — above any `.erase` punch, which `eraseHybrid` *appends* rather than inserting.
    /// Number text above strokes and a stroke drawn after an erase would be inserted *underneath*
    /// that punch and get eaten by an erase that happened before it existed.
    ///
    /// It does not mean text draws under strokes: `upsertText` appends a brand-new text object to the
    /// end of the list (see there), so text and strokes stack in the order the artist made them. The
    /// rawValue governs *insertion arithmetic*, not z-order.
    ///
    /// **`.fill` is in the same position as `.text`: numbered low, but appended.** `addFill` appends
    /// too, since LASSO_FILL.md §2a — a fill covers everything already on the layer. The rawValue
    /// still decides where a fill goes when something *reconstructs* the list without knowing the
    /// original z-position (the `fills` setter on an empty bucket, `init(size:strokes:fills:images:)`
    /// on a legacy project), and "under the strokes" is the right answer there because that is where
    /// those documents' fills were.
    private enum Kind: Int {
        case fill = 0
        case image = 1
        case text = 2
        case stroke = 3
    }

    private static func kind(of element: VectorElement) -> Kind {
        switch element {
        case .fill: return .fill
        case .image: return .image
        case .text: return .text
        case .stroke: return .stroke
        }
    }

    /// Where a newly added element of `kind` belongs: before the first element of a higher kind.
    /// Reproduces the legacy images→strokes z-order while the list stays capable of arbitrary
    /// z-position, which the eraser needs.
    ///
    /// **It no longer assumes the list is kind-sorted, because it is not** — `upsertText` and (since
    /// LASSO_FILL.md §2a) `addFill` both append past this. Its two remaining callers are unaffected by
    /// that: `.stroke` is the highest kind, so a stroke appends whatever else is in the list, and an
    /// image goes below the first stroke, which is where an image has always gone. Read it as "below
    /// the first higher-kind element", not as an index into a sorted list.
    private static func insertionIndex(forKind kind: Kind, in elements: [VectorElement]) -> Int {
        elements.firstIndex { Self.kind(of: $0).rawValue > kind.rawValue } ?? elements.count
    }

    /// The `strokes`/`fills`/`images` setter contract — see the comment above those accessors.
    ///
    /// **Positional, not bucketed, and that is what makes it safe now that fills are appended.** The
    /// old version gathered every element of `kind` back at the index the *first* one occupied, which
    /// round-tripped exactly only while each kind sat in one contiguous run. `addFill` appends
    /// (LASSO_FILL.md §2a), so fills are interleaved with strokes by construction and that assumption
    /// is gone: a get→set through `fills` would have dragged a fill the artist put on top back under
    /// the line art. Replacing the i-th element of the kind with the i-th replacement, where it
    /// already sits, is the identity for *any* arrangement.
    ///
    /// The two ragged cases keep the old behaviour, because there is no position to preserve: extra
    /// replacements go after the last one written, or — when the bucket was empty — at
    /// `insertionIndex`, which is what puts a restored fill back under the strokes on a legacy
    /// document. A shorter list drops the trailing slots.
    private static func splicing(_ elements: [VectorElement], kind: Kind,
                                 with replacements: [VectorElement]) -> [VectorElement] {
        var result: [VectorElement] = []
        result.reserveCapacity(max(elements.count, replacements.count))
        var next = 0
        var afterLastReplaced: Int?
        for element in elements {
            guard Self.kind(of: element) == kind else { result.append(element); continue }
            guard next < replacements.count else { continue }   // the new list is shorter
            result.append(replacements[next])
            next += 1
            afterLastReplaced = result.count
        }
        if next < replacements.count {
            result.insert(contentsOf: replacements[next...],
                          at: afterLastReplaced ?? Self.insertionIndex(forKind: kind, in: result))
        }
        return result
    }

    /// Caller must hold `lock`.
    private func invalidate() {
        contentVersion += 1
        invalidateRenderOnly()
    }

    /// Drops the memoized renders and moves the display's staleness key, **without** claiming the
    /// layer's own content changed. `setTransform` is the only caller and the only mutation for
    /// which that distinction is true. Caller must hold `lock`.
    private func invalidateRenderOnly() {
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

    /// The inverse of `localSamples`: stored, local-space geometry expressed back in canvas space, so
    /// it can be re-stamped into `StrokeCanvasView`'s scratch raster — which is a copy of `render()`
    /// and therefore already carries `transform`. Only `cutPreviewPieces` needs this; every other
    /// caller is going the other way.
    private static func canvasSamples(_ samples: [VectorSample], through t: CGAffineTransform) -> [VectorSample] {
        guard !t.isIdentity else { return samples }
        return samples.map {
            let p = $0.point.applying(t)
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

    /// Canvas-point spacing between a freshly-imported image and the one before it — see
    /// `addImage(canvasSpaceElement:canvasPosition:canvasFit:)`.
    private static let importCascadeStep: CGFloat = 24

    /// Imports an image whose position/scale were measured in **canvas** space — the import path
    /// always centers a new image on the canvas the artist is looking at, exactly as a live stroke or
    /// fill is measured where the finger is — mapping into this canvas's local space before storing,
    /// for the reason `addStroke(canvasSpaceStroke:)` and `addFill(canvasSpacePath:)` both give:
    /// storage is local, `render()` applies `transform` on top, and a canvas-space value stored
    /// unmapped would go through the transform twice. `scale` gets the same correction `size` does in
    /// `addStroke(canvasSpaceStroke:)`: divided by the transform's own scale so it renders back out at
    /// the canvas-space size it was given.
    ///
    /// **Also cascades**, offsetting by `importCascadeStep` canvas points per image already on this
    /// canvas — converted to local units the same way `size` is, so the offset is the right number of
    /// *screen* points regardless of the layer's own zoom/scale — so a second import does not land
    /// exactly on top of the first. Without this, two images centered on the same canvas at the same
    /// `fit` (same aspect ratio) are bit-identical `CGPoint`s: `splitForLassoMove` selects by an
    /// element's stored centre alone, so no lasso loop could ever contain one without the other, and
    /// Move only carries the whole cel — there is no way to separate them after the fact. Counting
    /// this canvas's own images (not a running counter kept elsewhere) is what makes undo → redo
    /// re-place the same element at the same offset instead of drifting on a later import.
    ///
    /// Returns the element as actually stored (local space, cascaded, inserted), so the caller can
    /// bind it once outside its undo/redo closures — recomputing the offset inside redo would replay a
    /// different value than undo captured whenever another image was imported in between.
    @discardableResult
    func addImage(canvasSpaceElement image: UIImage, canvasPosition: CGPoint, canvasFit: CGFloat) -> VectorImageElement {
        lock.lock()
        defer { lock.unlock() }
        let scale = Self.scale(of: _transform)
        let localScale = scale > 0 ? canvasFit / scale : canvasFit
        let cascade = CGFloat(_elements.compactMap(\.image).count) * Self.importCascadeStep / (scale > 0 ? scale : 1)
        var localPosition = canvasPosition.applying(_transform.inverted())
        localPosition.x += cascade
        localPosition.y += cascade
        let element = VectorImageElement(image: image,
                                         transform: LayerTransform(position: localPosition, scale: localScale, rotation: 0))
        _elements.insert(.image(element), at: Self.insertionIndex(forKind: .image, in: _elements))
        invalidate()
        return element
    }

    /// Puts a fill **on top of everything already on this canvas** — appended to the end of the
    /// display list, not inserted at `Kind.fill`'s index.
    ///
    /// **This is LASSO_FILL.md §2a, and it is the owner's ruling of 2026-08-21: *"Cover
    /// everything."*** Inserting by kind put every fill below every stroke, so a second fill could
    /// not cover the first (the reported bug) and no fill could ever cover the layer's own line art
    /// (which the owner had provisionally accepted, then overruled after testing). `upsertText`
    /// already appends past the kind order for the same reason — a new object goes above what is
    /// there — so this is that precedent, not a new one.
    ///
    /// **What appending costs, and why it is paid.** The display list is no longer sorted by kind, so
    /// the kind-filtered `fills` setter can no longer reconstruct z-positions from a bucket. Two
    /// things answer that: `splicing` is positional (see there), and every fill mutation registers
    /// undo through `CanvasManager.registerVectorElementsUndo`, which swaps the whole array and has
    /// nothing to reconstruct. Do not reintroduce a fills-bucket undo on top of this.
    func addFill(_ element: VectorFillElement) {
        lock.lock()
        defer { lock.unlock() }
        _elements.append(.fill(element))
        invalidate()
    }

    /// Puts a text object into the display list: **replaced at its own index when one with that id is
    /// already there, appended to the end when it is new.**
    ///
    /// The replace-in-place half is what makes re-editing safe. A text object that has been retyped,
    /// restyled or moved is the same object at the same z-position; removing and re-adding it would
    /// bring it to the front, so an edit to the label *behind* a drawing would silently pull it in
    /// front of it. `VectorTextPersistenceLogicTests` pins that.
    ///
    /// The append half is why `Kind.text` is numbered below `.stroke` rather than above it — see
    /// `Kind`. A brand-new object goes on top of what is already there, which is what every editor
    /// does and what the artist just placed; text and strokes therefore stack chronologically.
    ///
    /// Frames are in **local** space, like every other stored geometry on this canvas. A caller
    /// holding canvas-space corners maps them with `localPoints(fromCanvas:)` first.
    func upsertText(_ element: VectorTextElement) {
        lock.lock()
        defer { lock.unlock() }
        upsertTextLocked(element)
        invalidate()
    }

    /// Drops a text object by id. What an edit session that ends with an empty string does to the
    /// element it re-opened — deleting every character is how an artist removes a label, and leaving
    /// an empty box behind would leave an invisible object they cannot select to get rid of.
    @discardableResult
    func removeText(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard removeTextLocked(id: id) else { return false }
        invalidate()
        return true
    }

    /// **The commit half of an edit session, and the session's second and last `invalidate()`.**
    ///
    /// Un-suppressing the element being edited and applying what the artist typed are one event, not
    /// two, so they are one mutation here — `ADD_TEXT.md` §4 rule 4 allows exactly two invalidations
    /// per session (open and commit) and doing this in two calls would spend three. Every bump
    /// cascades into `RasterizeKey`, `LayerContentVersion`, `SandwichKey` and both upload caches,
    /// each costing a fresh canvas-sized flatten and an LRU eviction.
    ///
    /// `element == nil` deletes the object the session opened — the artist emptied the box. Returns
    /// whether the display list actually changed, so a session that placed a box and typed nothing
    /// registers no undo step.
    @discardableResult
    func commitTextEdit(editingID: UUID?, element: VectorTextElement?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var listChanged = false
        if let element {
            upsertTextLocked(element)
            listChanged = true
        } else if let editingID, removeTextLocked(id: editingID) {
            listChanged = true
        }
        let wasSuppressing = !_suppressedElementIDs.isEmpty
        _suppressedElementIDs = []
        if listChanged || wasSuppressing { invalidate() }
        return listChanged
    }

    /// Caller must hold `lock`. See `upsertText(_:)` for the replace-in-place / append rule.
    private func upsertTextLocked(_ element: VectorTextElement) {
        if let index = _elements.firstIndex(where: { $0.id == element.id }) {
            _elements[index] = .text(element)
        } else {
            _elements.append(.text(element))
        }
    }

    /// Caller must hold `lock`.
    private func removeTextLocked(id: UUID) -> Bool {
        guard let index = _elements.firstIndex(where: { $0.id == id && $0.text != nil }) else { return false }
        _elements.remove(at: index)
        return true
    }

    /// A text object captured in **canvas** space expressed in this canvas's local space, and back.
    ///
    /// Needed for the reason `addStroke(canvasSpaceStroke:)` and `addFill(canvasSpacePath:)` are: the
    /// draft is measured where the finger is, storage is local, and `render()` applies `transform`
    /// afterwards — so a frame stored unmapped would go through the layer's transform twice. Both
    /// directions are `mappingText` with the transform or its inverse, so a round trip is exact.
    ///
    /// **The point size and the box travel with the corners.** A layer scaled by *k* stores a stroke
    /// at `size / k` so it comes back out the width it was drawn; type is the same statement about a
    /// different scalar, and leaving `pointSize` in canvas points would re-lay the glyphs out at the
    /// wrong size inside a box that had been scaled.
    ///
    /// **Rotation used to be the one part this did not carry, and stage 4 closed it.** A rotated
    /// layer transform gives the mapped frame a rotated quad, which stage 3's
    /// `VectorCanvas.draw(text:…)` then drew through its bounding box; it now draws through the
    /// frame's own affine map, so the mapped quad renders turned. What remains for stage 5 is the
    /// case no affine map covers — a layer transform that is not a similarity, or a frame the artist
    /// has warped into a non-parallelogram.
    func localText(fromCanvas element: VectorTextElement) -> VectorTextElement {
        lock.lock()
        defer { lock.unlock() }
        return Self.mappingText(element, through: _transform.isIdentity ? _transform : _transform.inverted())
    }

    func canvasText(fromLocal element: VectorTextElement) -> VectorTextElement {
        lock.lock()
        defer { lock.unlock() }
        return Self.mappingText(element, through: _transform)
    }

    private static func mappingText(_ element: VectorTextElement,
                                    through t: CGAffineTransform) -> VectorTextElement {
        guard !t.isIdentity else { return element }
        var mapped = element
        mapped.frame.corners = element.frame.corners.map { $0.applying(t) }
        let s = scale(of: t)
        if s > 0, abs(s - 1) > 1e-9 {
            mapped.frame.size = CGSize(width: element.frame.size.width * s,
                                       height: element.frame.size.height * s)
            mapped.recipe.typography.pointSize = element.recipe.typography.pointSize * s
        }
        return mapped
    }

    /// Adds a fill whose path was captured in **canvas** space — where the flood-fill mask, the lasso,
    /// and every other on-screen path are measured — mapping it into this canvas's local space first,
    /// or it would go through `transform` twice at render time.
    ///
    /// On top of everything already here, for the reasons `addFill(_:)` gives.
    func addFill(canvasSpacePath path: CGPath, color: CodableColor, opacity: Double = 1.0, evenOddFill: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        let fill = VectorFillElement(path: Self.localPath(path, through: _transform), color: color,
                                     opacity: opacity, evenOddFill: evenOddFill)
        _elements.append(.fill(fill))
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
        // `invalidateRenderOnly`, not `invalidate`: the display is stale, the local content is not.
        // See `contentVersion`.
        invalidateRenderOnly()
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
        affine(from: t, aspect: 1, stretchAxis: 0, pivot: pivot)
    }

    /// The same, for a box the Move bar's **Freeform** has stretched: `aspect` is how much wider than
    /// tall the box is, and the two axis scales it implies come from
    /// `ObjectTransformFrame.axisScales(scale:aspect:)` rather than being spelled again here — the box
    /// and the geometry it maps must not be able to disagree about which axis is which.
    /// `aspect == 1` returns `affine(from:pivot:)` bit for bit, so no existing caller changes by
    /// going through here.
    ///
    /// **This is the only affine in the lasso move that is not a similarity**, and every consumer of
    /// it has to know: `mapping(_:throughSimilarity:)` asserts against exactly that shape, and the
    /// stretched arm is `mapping(_:throughStretch:)`.
    ///
    /// **`stretchAxis` is the axis the stretch was made about** — LASSO_MOVE.md §5.20, Move stage 3b
    /// phase 2 — and it puts a rotation on the **other** side of the scale: `R(ρ+φ)·S·R(−φ)`. That is
    /// the singular value decomposition of a general 2×2, so with the position this expression is
    /// exactly a general affine and has nothing left to be extended by.
    ///
    /// **Two poses reduce to the shorter expression, and both reductions are written out rather than
    /// computed.** `φ == 0` is the pose of every document nobody has stretched off-axis; `aspect == 1`
    /// is every pose that has not been stretched at all, where `S` is a scalar and commutes with the
    /// rotation, so `R(ρ+φ)·s·R(−φ)` *is* `s·R(ρ)`. Computing either would round-trip two more
    /// `sin`/`cos` pairs and leave a similarity that is only nearly one — and "nearly" is not good
    /// enough twice over: `CanvasManager.applyToVectorFloat` dispatches on `aspect != 1` **exactly**,
    /// and `mapping(_:throughSimilarity:)` asserts the shape it is handed. So the branch is
    /// correctness, not speed.
    static func affine(from t: LayerTransform, aspect: CGFloat, stretchAxis: CGFloat,
                       pivot: CGPoint) -> CGAffineTransform {
        let s = ObjectTransformFrame.axisScales(scale: t.scale, aspect: aspect)
        let placed = CGAffineTransform.identity
            .translatedBy(x: t.position.x, y: t.position.y)
        let linear: CGAffineTransform
        if stretchAxis == 0 || aspect == 1 {
            linear = placed.rotated(by: t.rotation).scaledBy(x: s.x, y: s.y)
        } else {
            linear = placed.rotated(by: t.rotation + stretchAxis)
                .scaledBy(x: s.x, y: s.y)
                .rotated(by: -stretchAxis)
        }
        return linear.translatedBy(x: -pivot.x, y: -pivot.y)
    }

    /// Bounding box of the layer's own content (strokes/fills/images) in its local, untransformed
    /// coordinate space — i.e. where it sits before `transform` is applied. Nil if there's no
    /// visible content. Used to size/pivot the Move tool's on-canvas box to the actual content
    /// rather than the whole canvas.
    ///
    /// **Memoized on `contentVersion`, which is what makes it usable on a per-touch-move path.** The
    /// answer costs a canvas-sized rasterize of every element plus a several-million-pixel alpha
    /// scan, and the Move tool asked for it on every delta of a drag — once in
    /// `CanvasView.Coordinator.objectTransformChanged` and again in `updateTransformOverlay` — to
    /// recompute a value that a transform cannot change. Unlike the render memo this costs no
    /// pixels to hold (one `CGRect?`), so it is invisible to `hasCachedImage` and to eviction, which
    /// is correct rather than an oversight: there is nothing here to evict.
    func localContentBounds() -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        if cachedLocalContentBoundsVersion == contentVersion, let cached = cachedLocalContentBounds {
            return cached
        }
        localContentBoundsRasterizations += 1
        let bounds = PixelOps.opaqueContentBounds(
            renderLocalContent(elements: Self.visible(_elements, suppressing: _suppressedElementIDs)))
        cachedLocalContentBounds = .some(bounds)
        cachedLocalContentBoundsVersion = contentVersion
        return bounds
    }

    /// The memo behind `localContentBounds()`. Doubly optional on purpose: the outer level is "has an
    /// answer been computed", the inner is the answer itself, and an empty layer's legitimate `nil`
    /// must not read as a cache miss and re-rasterize on every call.
    private var cachedLocalContentBounds: CGRect??
    private var cachedLocalContentBoundsVersion: Int = -1

    /// How many times `localContentBounds()` has actually rasterized, as against resolving from the
    /// memo above. The test seam `ObjectTransformLogicTests` reads, in `lastRenderDabCount`'s
    /// idiom: whether the memo is live is a **countable** property, and asserting it in milliseconds
    /// on this machine would be asserting on the machine. A counter of its own rather than
    /// `lastRenderDabCount` because `render()` leaves that value standing on a cache hit rather than
    /// zeroing it, so it cannot distinguish "rasterized again" from "did not".
    private(set) var localContentBoundsRasterizations: Int = 0

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
        guard let sweep = VectorEraser.Sweep(samples: localSamples, brush: brush,
                                             size: localSize) else { return false }

        let changed: Bool
        switch mode {
        case .erase:
            changed = eraseHybrid(sweep: sweep, samples: localSamples, brush: brush, size: localSize,
                                  opacity: opacity)
        case .cutPoints:
            changed = cutAlongFootprint(sweep: sweep)
        case .cutToIntersection:
            // Whole-gesture form, resolved once against the first sample, against the gesture's whole
            // swept footprint. It is not what ships: `StrokeCanvasView.endVectorStroke` skips Mode 3
            // here because the live gesture driver has already committed per sample through
            // `cutToIntersection(atCanvasPoint:…)`, since Mode 3 cuts on touch-down and re-resolves
            // per crossing. Kept — and routed through the *same* private resolve as the live path, so
            // it cannot drift into a second, differently-behaving Mode 3.
            changed = cutToIntersection(sweep: sweep, near: localSamples[0].point,
                                        suppressing: []).outcome == .cut
        }
        if changed { invalidate() }
        return changed
    }

    /// Mode 3 resolved against a **single** eraser position: the driver calls this once per touch
    /// sample, so a drag across three lines cuts three spans.
    ///
    /// `suppressing` is the driver's per-stroke latch: after a cut the eraser is still sitting on the
    /// pieces it just made, so cutting again on the next sample would walk down the line deleting span
    /// after span from one stationary finger. `VectorEraser.IntersectionDriver` holds the ids and this
    /// returns the set now under the tip — the cut's own fresh pieces included — for it to hold next.
    /// Passing every id on the layer therefore runs the same search as a pure, non-mutating query.
    ///
    /// Only this layer knows the ids, which is why the driver takes them back as a value rather than
    /// asking a question it cannot phrase.
    ///
    /// **Takes no pressure, deliberately.** Modes 1 and 2 lay down a hole and that hole *is* ink, so
    /// it should breathe with the pencil like any other stroke. Mode 3's footprint is not ink — it is
    /// a *selection*, and the owner asked for it in so many words: *"the eraser brush size should be
    /// the radius around which everything is erased"* (2026-08-18). A radius that shrank with a light
    /// touch would erase a different amount each pass with nothing on screen to explain why, and would
    /// make `StrokeCanvasView.updateEraserFootprint(at:)`'s ring — drawn at full size — a promise the
    /// cut does not keep. `StrokeInput` reports pressure 1 for a finger but `force /
    /// maximumPossibleForce` for a pencil (StrokeInput.swift:36), so this was invisible in the
    /// simulator and would have shown up only on the owner's own iPad. Pinning at 1 also matches the
    /// `forPressure: 1` the width-aware tolerances below already use.
    @discardableResult
    func cutToIntersection(atCanvasPoint canvasPoint: CGPoint, brush: Brush,
                           size: CGFloat, suppressing: Set<UUID> = [])
        -> (outcome: VectorEraser.CutOutcome, underTip: Set<UUID>) {
        lock.lock()
        defer { lock.unlock() }
        guard _elements.contains(where: { $0.stroke != nil }) else { return (.missed, []) }

        let localSamples = Self.localSamples([VectorSample(x: canvasPoint.x, y: canvasPoint.y, pressure: 1)],
                                             through: _transform)
        let scale = Self.scale(of: _transform)
        let localSize = scale > 0 ? size / scale : size
        // A one-sample sweep is the single dab stamped so far: `capsuleChain` yields one zero-length
        // capsule for it, so the footprint test below is the nib itself.
        guard let sweep = VectorEraser.Sweep(samples: localSamples, brush: brush,
                                             size: localSize) else { return (.missed, []) }

        let resolved = cutToIntersection(sweep: sweep, near: localSamples[0].point, suppressing: suppressing)
        if resolved.outcome == .cut { invalidate() }
        return resolved
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
        StrokeGeometry.splitStrokeRuns(stroke.samples, removing: cuts)
            .map { piece(of: stroke, samples: $0.samples, parameters: $0.parameters) }
    }

    /// One piece of a split stroke: its own geometry, rendering on its parent's dab lattice.
    ///
    /// Shared by every cutter — the eraser's three modes and the lasso move — so a piece cut one way
    /// is bit-identical to a piece cut the other way from the same run, and so the two cannot come to
    /// disagree about what a child inherits. Static, so it cannot re-enter `lock`.
    ///
    /// `parameters` are positions in **this stroke's** domain; they are mapped back through the
    /// stroke's own lattice, so a grandchild points at the original ancestor's samples directly
    /// rather than at a chain.
    private static func piece(of stroke: VectorStroke, samples: [VectorSample],
                              parameters: [CGFloat]) -> VectorStroke {
        var piece = stroke
        // Fresh id: two pieces cannot share one. The dab seed travels via `DabLattice.seedID`
        // instead.
        piece.id = UUID()
        piece.samples = samples
        let mapped = stroke.lattice.map { parameters.map($0.parentParameter(of:)) } ?? parameters
        piece.lattice = DabLattice(samples: stroke.lattice?.samples ?? stroke.samples,
                                   parameters: mapped,
                                   seedID: stroke.lattice?.seedID ?? stroke.id)
        piece.sampleVisibilityThresholds = remapped(stroke.sampleVisibilityThresholds, onto: parameters)
        return piece
    }

    /// `sampleVisibilityThresholds` — an `[Int: CGFloat]` keyed by index into the *parent's* samples —
    /// re-keyed onto a piece's own indices.
    ///
    /// A cut renumbers samples, so carrying the dictionary across unchanged points every threshold at
    /// a different sample than the one it was recorded for. Latent rather than live today (nothing in
    /// the app populates it; the interpolation tests do), which is exactly why it is worth one
    /// function here instead of a corrupted in-between later. A boundary sample sits at a fractional
    /// parameter and so inherits nothing — it is a new sample, not one of the parent's.
    private static func remapped(_ thresholds: [Int: CGFloat]?, onto parameters: [CGFloat]) -> [Int: CGFloat]? {
        guard let thresholds, !thresholds.isEmpty else { return thresholds }
        var result: [Int: CGFloat] = [:]
        for (index, parameter) in parameters.enumerated() {
            let rounded = Int(parameter.rounded())
            guard abs(parameter - CGFloat(rounded)) < 1e-9, let value = thresholds[rounded] else { continue }
            result[index] = value
        }
        return result.isEmpty ? nil : result
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
            case .text(let text):
                // Text is content the punch can be hiding, and geometry the split could never have
                // removed — the vector eraser does not bite letterforms (`ADD_TEXT.md` §1, §5.4), so
                // any overlap means the punch is still doing work.
                if let ink = TextMeasure.inkBounds(of: text), ink.intersects(box) { return true }
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
        case .text(let text):
            // Ink, not the box: an empty or whitespace-only object is not a backdrop, and a punch
            // kept alive by a box with nothing in it is a hole in nothing that never gets collected.
            return TextMeasure.inkBounds(of: text)
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

    // MARK: - Lasso move
    //
    // LASSO_MOVE.md. A lasso move splits the display list **once**, at lift, and from that moment the
    // piece that travels is real geometry rather than a preview: every later nudge maps it and lands
    // as one undo step. What the artist drags is a Core Animation transform on a latched bitmap, so
    // the whole move costs three canvas renders — the hole, the float, and the bake — however many
    // times they nudge it.

    /// Which side of the loop a point is on. **Winding, matching `PixelOps.maskedPiece`'s `clip()`**,
    /// so a lasso means the same region on a vector layer as it does on a raster one. The loop is
    /// normalized before it gets here (`CanvasManager.beginVectorLassoMove`), which makes the two
    /// rules agree on it anyway; this is the rule the *fills* are also cut with when a fill does not
    /// carry `evenOddFill`.
    static let lassoFillRule: CGPathFillRule = .winding

    /// **A placed image's four corners as a closed path, in local space** — mapped exactly the way
    /// `draw(image:into:)` maps them, so the quad this returns is the rectangle the artist can see.
    ///
    /// Not `bounds(of:)`, which is the *circumscribing disc* of the scaled size: that is deliberately
    /// rotation-independent and therefore loose, which is right for a punch-overlap test and wrong
    /// for a membership rule the artist is going to check against the picture. And **not the four
    /// corners tested one at a time** — four corners inside a crescent-shaped loop does not mean the
    /// rectangle is inside it.
    static func quad(of element: VectorImageElement) -> CGPath {
        let size = element.image.size
        var t = CGAffineTransform(translationX: element.transform.position.x,
                                  y: element.transform.position.y)
            .rotated(by: element.transform.rotation)
            .scaledBy(x: element.transform.scale, y: element.transform.scale)
        return CGPath(rect: CGRect(x: -size.width / 2, y: -size.height / 2,
                                   width: size.width, height: size.height), transform: &t)
    }

    /// **A text box's four corners as a closed path.** `TextFrame.corners` *is* the frame — already
    /// turned, stretched or mirrored by whatever has been done to it — so this is exact for every
    /// pose a box can reach, where `boundingBox` is its axis-aligned hull and therefore loose the
    /// moment the box is not upright.
    static func quad(of frame: TextFrame) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: frame.corners)
        path.closeSubpath()
        return path
    }

    /// **Does `loop` catch `element` under `membership`?** The one place the per-kind membership rule
    /// is decided, for all three modes and all four kinds — so `splitForLassoMove`,
    /// `elementIDs(insideLocalPath:membership:)` and every mode of the Move picker cannot come to
    /// disagree about what "inside" means.
    ///
    /// `loopBounds` is `loop.boundingBoxOfPath` hoisted out by the caller: it is an `O(n)` walk of a
    /// path that can carry 1,500 points, and asking for it per element would put that walk inside the
    /// display-list loop.
    ///
    /// **Strokes are answered by the centre line in all three modes** (LASSO_MOVE.md §5.4), and the
    /// consequence under `.enclosed` is visible and benign: a thick stroke whose spine is enclosed
    /// travels whole even where its ink pokes out. The alternative — an outline-based Enclosed —
    /// fails the other way, leaving such a stroke behind *silently*, and ink membership has no
    /// primitive in this codebase anyway (§1, and §3 stage 4 keeps it on the board as a named
    /// deferred option).
    ///
    /// **`samples.contains` / `samples.allSatisfy`, not `membershipRuns`, and that is exact rather
    /// than an approximation.** `StrokeGeometry.membershipRuns` decides membership by
    /// `inside(sample.point)` alone and bisects only where two consecutive samples disagree, so a run
    /// marked inside exists exactly when some stored sample is inside, and every sample is inside
    /// exactly when no run is marked outside. Skipping it skips ~40 bisections per crossing for an
    /// answer that is the same bit.
    ///
    /// **Text and a placed image follow the mode in Touching and Enclosed and keep the centre in
    /// Cut** (owner, 2026-08-28), so each of the two new modes has one sentence true of every kind
    /// while Cut keeps what it has always been: the cut rule rounded for kinds that cannot be cut.
    /// Both are asked with the *same two `CGPath` booleans the fill arm uses*, on the element's own
    /// quad.
    ///
    /// **An area rule catches nothing with no area, and that is right rather than an edge case.**
    /// `.enclosed` asks for an intersection as well as an empty remainder, because a degenerate quad
    /// — an empty text box, a zero-size image — subtracts to nothing wherever it sits, and would
    /// otherwise report itself enclosed by a loop on the other side of the canvas. It draws nothing,
    /// so neither area mode carries it; `.cutting` still answers it by its centre.
    static func caught(_ element: VectorElement, by loop: CGPath, bounds loopBounds: CGRect,
                       using rule: CGPathFillRule, membership: LassoMembership) -> Bool {
        /// Both area rules, on one closed path: "the loop reaches it" and "the loop covers all of
        /// it". The `subtracting` runs first under `.enclosed` because it is the cheap reject.
        func area(_ path: CGPath, using pathRule: CGPathFillRule) -> Bool {
            switch membership {
            case .enclosed:
                guard path.subtracting(loop, using: pathRule).isEmpty else { return false }
                return !path.intersection(loop, using: pathRule).isEmpty
            case .cutting, .touching:
                return !path.intersection(loop, using: pathRule).isEmpty
            }
        }

        switch element {
        case .stroke(let stroke):
            guard !stroke.samples.isEmpty else { return false }
            switch membership {
            case .enclosed:
                return stroke.samples.allSatisfy { loop.contains($0.point, using: rule) }
            case .cutting, .touching:
                return stroke.samples.contains { loop.contains($0.point, using: rule) }
            }

        case .fill(let fill):
            // Each fill asked with **its own** rule, as the split cuts it: a clear-selection hole is
            // stored `evenOddFill`, and testing it as a winding path would report the very hole it
            // exists to make as solid ink the loop had caught.
            guard let path = fill.cgPath, path.boundingBoxOfPath.intersects(loopBounds) else {
                return false
            }
            return area(path, using: fill.evenOddFill ? .evenOdd : .winding)

        case .image(let image):
            guard membership != .cutting else {
                return loop.contains(image.transform.position, using: rule)
            }
            let quad = Self.quad(of: image)
            guard quad.boundingBoxOfPath.intersects(loopBounds) else { return false }
            return area(quad, using: .winding)

        case .text(let text):
            guard membership != .cutting else {
                let box = text.frame.boundingBox
                return loop.contains(CGPoint(x: box.midX, y: box.midY), using: rule)
            }
            let quad = Self.quad(of: text.frame)
            guard quad.boundingBoxOfPath.intersects(loopBounds) else { return false }
            return area(quad, using: .winding)
        }
    }

    /// Every element `loop` catches under `membership`, **cutting nothing**. Caller must hold `lock`.
    ///
    /// The shared body of `elementIDs(insideLocalPath:membership:)` and of `splitForLassoMove`'s two
    /// non-cutting arms, so the picker's Touching cannot drift from the recolour's answer for the
    /// kinds where the two agree.
    private func caughtIDs(insideLocalPath loop: CGPath, bounds loopBounds: CGRect,
                           strokeCandidates: Set<Int>, membership: LassoMembership) -> Set<UUID> {
        let rule = Self.lassoFillRule
        var insideIDs: Set<UUID> = []
        for (index, element) in _elements.enumerated() {
            // `strokeIndex()` holds centrelines only, so fills, images and text take a linear scan
            // against their own bounds inside `caught` — the same limitation, and the same shape, as
            // `splitForLassoMove`'s cutting arm.
            if element.stroke != nil, !strokeCandidates.contains(index) { continue }
            if Self.caught(element, by: loop, bounds: loopBounds, using: rule, membership: membership) {
                insideIDs.insert(element.id)
            }
        }
        return insideIDs
    }

    /// The display list split along `loop`, so that everything inside it can move on its own.
    ///
    /// Returns the new list, the ids of the elements that are inside — the ones a float carries — and
    /// whether an isolated render of those ids composited over the rest can differ from a render of
    /// the whole list (see `mayDiverge` below). **Nil when the loop catches nothing**, which is
    /// LASSO_MOVE.md §5's ruling that an empty lasso plus Move does nothing; answering it here rather
    /// than at the call site is what stops a caller inventing a fallback to moving the whole cel.
    ///
    /// `loop` is in this canvas's **local** space, and must already be normalized — see
    /// `localPath(fromCanvas:)` for the first and `CGPath.normalized(using:)` for the second. Neither
    /// is optional: stored geometry is local, so an unmapped canvas-space loop is correct on an
    /// untransformed layer and silently wrong on every layer Move has already touched; and Core
    /// Graphics leaves `intersection`/`subtracting` **undefined** for a non-simple path, which a raw
    /// lasso becomes the moment the artist loops back over their own line.
    ///
    /// **Membership is by the centre line, and that is not something this function does — it is what
    /// `StrokeGeometry.membershipRuns` already does.** The walk tests stored sample positions, which
    /// are the spine, and lands each crossing on the segment between two of them; nothing in it
    /// consults `size` or `pressure`. So applying LASSO_MOVE.md §5.4 means *not* adding a width term,
    /// and its consequence — a 40 pt stroke whose spine lies outside the loop does not move, even
    /// though its ink is inside — is the owner's ruling of 2026-08-21 rather than a defect.
    ///
    /// **An eraser mark is an ordinary element here** (owner, 2026-08-22): it takes the same
    /// containment test and the same split as a paint stroke, so a hole wholly inside the loop travels
    /// with the ink and a hole outside it stays. That is simpler than a special case and it is this
    /// app's own "the eraser is a stroke" decision applied once more. Its consequence is that a float
    /// made only of punches renders blank while it is dragged and lands when it bakes — see
    /// `renderIsolated(ids:)`.
    ///
    /// **`membership` is a parameter on this function rather than a sibling beside it** (TODO item
    /// (20)). A sibling would duplicate the broad phase, `lassoFillRule`, the linear scan for the
    /// three kinds the index does not hold, the `insideIDs.isEmpty` contract below and the
    /// `mayDiverge` call — five things that have to agree for the three modes to feel like one
    /// feature. It defaults to `.cutting`, so every call site and every test written before the modes
    /// existed compiles and passes untouched, which is the regression proof that Cut is unchanged.
    ///
    /// **The two new modes return `_elements` verbatim and cut nothing.** They are the classifier
    /// above, and the tuple is `liftWholeCel`'s shape: same lift, same nudges, same bake, same
    /// teardown. `mayDiverge` is still asked and is still needed — under `.enclosed` it fires *more*
    /// often rather than less, because fewer moved ids means more unmoved punches sitting above the
    /// lowest moved index.
    func splitForLassoMove(insideLocalPath loop: CGPath, membership: LassoMembership = .cutting)
        -> (elements: [VectorElement], insideIDs: Set<UUID>, mayDiverge: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard !_elements.isEmpty else { return nil }
        let box = loop.boundingBoxOfPath
        guard !box.isNull, !box.isEmpty else { return nil }
        // The same broad phase `cutAlongFootprint` uses, and with the same limitation: the index holds
        // strokes only, so fills, images and text take a linear scan against their own bounds below.
        let strokeCandidates = Set(strokeIndex().segments(near: box).map(\.elementIndex))
        let rule = Self.lassoFillRule

        guard membership.cutsAtTheBoundary else {
            let insideIDs = caughtIDs(insideLocalPath: loop, bounds: box,
                                      strokeCandidates: strokeCandidates, membership: membership)
            guard !insideIDs.isEmpty else { return nil }
            return (_elements, insideIDs, Self.mayDiverge(_elements, movedIDs: insideIDs))
        }

        var result: [VectorElement] = []
        result.reserveCapacity(_elements.count + 2)
        var insideIDs: Set<UUID> = []

        for (index, element) in _elements.enumerated() {
            switch element {
            case .stroke(let stroke):
                guard strokeCandidates.contains(index), !stroke.samples.isEmpty else {
                    result.append(element)
                    continue
                }
                let runs = StrokeGeometry.membershipRuns(stroke.samples) { loop.contains($0, using: rule) }
                // **The fast path, and it is the common case.** One run back means the stroke is
                // wholly in or wholly out, and it travels or stays *untouched* — same id, same
                // lattice, same dab phase. That is what stops a lasso re-rolling a scattering brush's
                // pattern just by picking it up.
                guard runs.count > 1 else {
                    if runs.first?.isInside == true { insideIDs.insert(stroke.id) }
                    result.append(element)
                    continue
                }
                // Both halves replace the parent **at the parent's index**, outside first
                // (LASSO_MOVE.md §5.2): appending instead would hoist a moved half above every
                // `.erase` punch in the list, and a punch masks only what is beneath it.
                for run in runs where !run.isInside {
                    result.append(.stroke(Self.piece(of: stroke, samples: run.samples, parameters: run.parameters)))
                }
                for run in runs where run.isInside {
                    let piece = Self.piece(of: stroke, samples: run.samples, parameters: run.parameters)
                    insideIDs.insert(piece.id)
                    result.append(.stroke(piece))
                }

            case .fill(let fill):
                guard let path = fill.cgPath, path.boundingBoxOfPath.intersects(box) else {
                    result.append(element)
                    continue
                }
                // Each fill is cut with **its own** rule, carried through to both halves — a hole
                // punched by an older build of Clear is stored `evenOddFill` and cutting it as a
                // winding path would fill in the very hole it exists to make. The concatenate-two-
                // paths-and-lean-on-even-odd trick that made those holes is deliberately not used
                // (it was `CanvasManager.clipPath`, deleted 2026-08-28 when Clear moved onto this
                // function): it is not a set operation and cannot answer whether a half is empty.
                let fillRule: CGPathFillRule = fill.evenOddFill ? .evenOdd : .winding
                let insidePart = path.intersection(loop, using: fillRule)
                guard !insidePart.isEmpty else { result.append(element); continue }
                let outsidePart = path.subtracting(loop, using: fillRule)
                guard !outsidePart.isEmpty else {
                    insideIDs.insert(fill.id)
                    result.append(element)
                    continue
                }
                // Both halves mint fresh ids, exactly as a split stroke's do: keeping the parent's on
                // one of them would make "which is the original" a coin flip the first time a lasso
                // cuts one fill into three.
                let insideFill = VectorFillElement(path: insidePart, color: fill.color,
                                                   opacity: fill.opacity, evenOddFill: fill.evenOddFill)
                let outsideFill = VectorFillElement(path: outsidePart, color: fill.color,
                                                    opacity: fill.opacity, evenOddFill: fill.evenOddFill)
                insideIDs.insert(insideFill.id)
                result.append(.fill(outsideFill))
                result.append(.fill(insideFill))

            case .image(let image):
                // A centre point rather than a centre line, which is the same principle for a kind
                // that has no spine.
                if loop.contains(image.transform.position, using: rule) { insideIDs.insert(image.id) }
                result.append(element)

            case .text(let text):
                // **Text moves whole** (LASSO_MOVE.md §5.3) — a lasso never cuts a letterform, the
                // same ruling `ADD_TEXT.md` §5.4 settled for the eraser.
                let boundingBox = text.frame.boundingBox
                if loop.contains(CGPoint(x: boundingBox.midX, y: boundingBox.midY), using: rule) {
                    insideIDs.insert(text.id)
                }
                result.append(element)
            }
        }

        guard !insideIDs.isEmpty else { return nil }
        return (result, insideIDs, Self.mayDiverge(result, movedIDs: insideIDs))
    }

    /// Which elements the loop catches — **without cutting anything**. The seam for an edit that
    /// changes an element's *appearance* rather than its geometry, of which Change Colour
    /// (`CanvasManager.recolorSelection`) is the first.
    ///
    /// `loop` carries `splitForLassoMove`'s two mandatory preconditions unchanged: local space
    /// (`localPath(fromCanvas:)`) and normalized (`CGPath.normalized(using:)`). Same broad phase,
    /// same `lassoFillRule`, same centre-line and centre-point rules — the whole point is that
    /// "what did the lasso catch" has one answer in this file, whatever the caller then does with it.
    ///
    /// **A sibling rather than a parameter on `splitForLassoMove`, because that function's *cutting*
    /// arm cannot answer this question.** That arm inserts a stroke's id only when the stroke is
    /// wholly inside; a straddling stroke is cut, and only the fresh inside piece enters the set.
    /// That is right for a move under Cut — only what is inside travels (LASSO_MOVE.md §5.1) — and
    /// wrong for a recolour, which the owner ruled splits nothing: *"It's alright if part of the
    /// stroke is outside the selection"* (2026-08-28). An element this returns is recoloured
    /// **whole**, ink outside the loop included. The two functions now share their body through
    /// `caughtIDs`, and `splitForLassoMove`'s two non-cutting arms *are* this predicate.
    ///
    /// **For a stroke the predicate collapses to "any stored sample inside", and that is not an
    /// approximation of the move's rule — it is bit-for-bit the same rule.**
    /// `StrokeGeometry.membershipRuns` decides membership by `inside(sample.point)` alone and only
    /// ever looks for a crossing where two *consecutive samples* disagree, so a run marked inside
    /// exists exactly when some stored sample is inside. Early-exit on the first; nothing here needs
    /// a crossing bisected, since no cut is made.
    ///
    /// **This answers containment, not eligibility, and the distinction is load-bearing rather than
    /// tidy.** Every kind is answered for, images and `.erase` strokes included; which kinds a given
    /// edit may then *touch* is that edit's business and belongs at the call site.
    ///
    /// `recolorSelection` skips placed images (`VectorImageElement` has no colour field) and `.erase`
    /// strokes (`.destinationOut` reads only alpha, so recolouring one changes no pixel). **A lasso
    /// move rules the exact opposite for the same two kinds** — LASSO_MOVE.md §5.7, verbatim: *"If
    /// the hole is fully inside, it moves it"* — because a hole has a position even though it has no
    /// colour. Bake either edit's kind filter in here and the other one silently inherits a rule its
    /// owner ruled against; for Move that failure is invisible, because the ink simply does not
    /// travel and nothing goes red.
    ///
    /// That was not hypothetical, and it has arrived. Move's three membership modes (TODO item (20))
    /// are `membership` below, and `.touching` is this predicate for strokes and fills exactly.
    ///
    /// **`membership` defaults to `.cutting`, which is the recolour's rule and not a coincidence.**
    /// Under `.cutting` a placed image and a text box are answered by their **centre** — a third rule,
    /// neither "touching" nor "wholly enclosed" — and that is what the owner ruled on 2026-08-28 for
    /// both the recolour and Move's Cut mode: it is the cut rule rounded for kinds that cannot be
    /// cut. The two new modes answer those kinds by their own quad instead, so that each of them has
    /// one sentence true of every kind. See `caught(_:by:bounds:using:membership:)`.
    ///
    /// `LassoMoveLogicTests.testContainmentAnswersForEveryKindIncludingTheOnesARecolourSkips` pins
    /// this: it asserts an eraser and a photo inside the loop come back in the set, so moving the
    /// recolour's skip down into this function fails a test *today* rather than at the moment Move
    /// reuses it.
    func elementIDs(insideLocalPath loop: CGPath,
                    membership: LassoMembership = .cutting) -> Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        guard !_elements.isEmpty else { return [] }
        let box = loop.boundingBoxOfPath
        guard !box.isNull, !box.isEmpty else { return [] }
        // `strokeIndex()` holds centrelines only, so fills, images and text take a linear scan
        // against their own bounds — the same limitation, and the same shape, as `splitForLassoMove`.
        let strokeCandidates = Set(strokeIndex().segments(near: box).map(\.elementIndex))
        return caughtIDs(insideLocalPath: loop, bounds: box,
                         strokeCandidates: strokeCandidates, membership: membership)
    }

    /// `splitForLassoMove`'s answer for **Move with no selection**: the whole cel travels, and
    /// nothing is cut. Same tuple, so `CanvasManager.beginVectorWholeCelMove` builds the identical
    /// `VectorFloat` the lasso builds and every nudge, undo, bake and teardown path is shared.
    ///
    /// Nil on an empty cel, for `splitForLassoMove`'s reason: answering it here rather than at the
    /// call site is what stops a caller inventing a float with nothing in it.
    ///
    /// **Every element id, with no containment test and no split — and the two obvious alternatives
    /// are both wrong.**
    ///
    ///   * *"The whole canvas was lassoed"*, taken literally as `splitForLassoMove(insideLocalPath:
    ///     canvasRect)`, would run `StrokeGeometry.membershipRuns` against the canvas edge: every
    ///     stroke crossing that edge would become **two permanent strokes with fresh ids**, and
    ///     everything wholly outside the canvas would be left behind. Off-canvas content is real
    ///     here — a stroke drawn past the edge, or content that a previous shrink put out there —
    ///     and abandoning it is exactly the artwork loss this whole change exists to end.
    ///   * *`localContentBounds()`* is worse still: it is an alpha scan of `renderLocalContent`,
    ///     which rasterizes into a context of exactly `size` at the local origin — so it can only
    ///     ever report ink that is already inside the canvas rect. Deriving the moved set from it
    ///     would exclude the very ink the clip is losing.
    ///
    /// So the answer is the identity: the moved set is the whole display list, which is what "move
    /// the whole cel" means, and it is the one reading under which no element can be dropped.
    ///
    /// **`mayDiverge` is over-conservative here, deliberately left as it is.** With every id moving,
    /// an isolated render of the moved set *is* a render of the whole list, so the latch could stand
    /// for the float's whole life — but `mayDiverge` answers yes for any cel holding an `.erase`
    /// stroke or a non-normal blend mode, so such a cel drops its latch at every gesture end and
    /// re-renders. That is correct (it shows the truth) and merely costs one render per gesture;
    /// reading the extra renders later as a bug is the mistake this paragraph exists to prevent.
    func liftWholeCel() -> (elements: [VectorElement], insideIDs: Set<UUID>, mayDiverge: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard !_elements.isEmpty else { return nil }
        let allIDs = Set(_elements.map(\.id))
        return (_elements, allIDs, Self.mayDiverge(_elements, movedIDs: allIDs))
    }

    /// Whether "render the moved ids alone, composite over the rest" can differ from "render the whole
    /// list" — i.e. whether the latched float is an approximation rather than the truth.
    ///
    /// Three ways it can be, and each is a case where an element's pixels depend on what is beneath it
    /// in the *same* display list, which Core Animation's source-over of two bitmaps cannot reproduce:
    /// a moved eraser mark has nothing under it in the float and so draws nothing at all; a moved
    /// stroke with a blend mode blends against the float's own transparency instead of the artwork;
    /// and a punch that stays behind, sitting above the lowest moved element, no longer has that
    /// element beneath it to bite.
    ///
    /// The common case is false, and the caller keeps its latch across every nudge for three renders
    /// in the whole move. When it is true the latch is dropped at each gesture end and the layer
    /// re-rendered, so what the artist is looking at between drags is always the truth.
    private static func mayDiverge(_ elements: [VectorElement], movedIDs: Set<UUID>) -> Bool {
        var lowestMoved = Int.max
        for (index, element) in elements.enumerated() where movedIDs.contains(element.id) {
            lowestMoved = min(lowestMoved, index)
            guard let stroke = element.stroke else { continue }
            if stroke.composite == .erase || stroke.brush.blendMode != .normal { return true }
        }
        guard lowestMoved < elements.count else { return false }
        for index in (lowestMoved + 1)..<elements.count {
            let element = elements[index]
            if element.stroke?.composite == .erase, !movedIDs.contains(element.id) { return true }
        }
        return false
    }

    /// One element moved by `t`, in this canvas's local space.
    ///
    /// **One function for every kind, so no call site can carry one half of an element and not the
    /// other.** The half that is easiest to miss is a stroke's `DabLattice`: `stamp` draws from
    /// `lattice?.samples ?? stroke.samples`, so mapping `samples` alone moves the geometry and not one
    /// pixel of the ink. The eraser's Modes 2 and 3 dodge that by dropping the lattice, and that
    /// escape is not available here — a lasso removes no geometry, and dropping the lattice would
    /// re-phase every dab and visibly re-roll a scattering brush the instant the artist nudged.
    ///
    /// **`t` must be a similarity** — translate · rotate · uniform scale. That is what the lasso
    /// float's box can express (`LayerTransform` is position + one scale + one rotation) and it is
    /// the whole reason a scale is cheap here: a point map alone cannot carry `VectorStroke.size`,
    /// `LayerTransform.scale`/`rotation` or a text frame's point size, and each of those is picked
    /// out of `t` below rather than being left behind. A non-uniform or projective `t` would make
    /// `hypot(t.a, t.b)` a plausible lie — one number standing in for two different axis scales — so
    /// the shape is asserted rather than hoped for. Freeform and Distort do not widen this function;
    /// they need a different one — Freeform's is `mapping(_:throughStretch:)` below, which shares the
    /// stroke and fill arms with this one through `drawn(_:through:widthScale:)` and differs only in
    /// where the ink's width scale comes from.
    ///
    /// **A *reflection* passes that assert, and is deliberately allowed — for three of the four
    /// kinds.** The Move menu's Mirror folds one into `t` (`VectorFloat.mirror`), and the shape test
    /// above cannot see it: a reflection has equal axis norms and perpendicular axes, so `k` is still
    /// the true scale and strokes, fills and text follow the map exactly. What a reflection does break
    /// is `theta`, which `atan2(t.b, t.a)` reads as an *angle* — meaningless for a map that turns the
    /// plane over. That is read by the `.image` arm alone, which is why that one asserts the
    /// determinant is positive and the others do not; `canBeMirrored(_:)` below is the same fact stated
    /// where a caller can ask it *before* offering the artist the button.
    ///
    /// ## Why scaling one scalar is exact, and where it stops being
    ///
    /// Multiplying `stroke.size` by the similarity's own factor is not an approximation. It is exact,
    /// dab for dab: `BrushStamper.stampSpacing` is linear in brush size and `advance` walks in
    /// geometric distance, so a path *k*× longer walked with *k*× spacing takes the identical number
    /// of steps at the identical parameters. Identical count ⇒ the seeded `DabRNG` draws the
    /// identical sequence; identical parameters ⇒ `visibleRange` selects the identical dabs of a cut
    /// piece's parent walk. Measured across 264 similarity cases (k ∈ [0.25, 8], θ ∈ [0, 2.1]): worst
    /// dab displacement 1.3e-13 pt, worst parameter error 8.9e-16.
    /// `LassoMoveLogicTests.testAScaledPieceLandsEveryDabWhereTheSimilarityPutsIt` pins it.
    ///
    /// Three floors break the similarity, and they are inherited knowingly rather than fixed:
    ///
    ///  * **`stampSpacing`'s 1 pt floor** (`BrushStamper.stampSpacing`). Below
    ///    `brushSize * spacingFraction == 1` the spacing stops scaling with the size, so the scaled
    ///    stroke gets a different dab count. That binds at ordinary sizes, not only at hairlines —
    ///    under 20 pt for Hard Round, under 33 pt for the Pen. It costs no ink: dab diameter still
    ///    scales, so the stroke is the right weight and still solid. It re-rolls the dab RNG, which is
    ///    invisible on every brush whose `scatter` and `rotationJitter` are zero — which is all five
    ///    built-ins. `testTheSpacingFloorIsTheOnePlaceAScaleChangesTheDabCount` pins the boundary.
    ///  * **`stampDab`'s 0.5 pt diameter floor** and `stampApproximateSquare`'s 1 pt dab/step floors,
    ///    for the same reason at heavy shrink.
    ///  * **Pencil grain** is an absolute noise field keyed on canvas position, so it re-samples under
    ///    any map — as it already does for a plain translation, so a scale is no regression.
    ///
    /// Under rotation the dabs are exact too, with one cosmetic caveat: per-dab rotation jitter and
    /// scatter offsets are drawn in absolute angles, so a square-tipped or scattering brush keeps its
    /// dab *orientation* when the piece turns. Statistically identical, and invisible on a round dab.
    static func mapping(_ element: VectorElement, throughSimilarity t: CGAffineTransform) -> VectorElement {
        guard !t.isIdentity else { return element }
        // The codebase's one answer to "how much did this scale by" — `VectorCanvas.scale(of:)`, which
        // `addStroke` already uses to carry a canvas-space width into local space.
        let k = hypot(t.a, t.b)
        let theta = atan2(t.b, t.a)
        assert(abs(k - hypot(t.c, t.d)) <= 1e-6 * max(1, k)
               && abs(t.a * t.c + t.b * t.d) <= 1e-6 * max(1, k * k),
               "mapping(_:throughSimilarity:) was handed \(t), which scales or shears its two axes "
               + "differently. `k` would be one number standing in for two, and every width below "
               + "would be wrong in a way the live preview cannot show.")
        switch element {
        case .stroke, .fill:
            return drawn(element, through: t, widthScale: k) ?? element
        case .image(var image):
            // A placed image is a `LayerTransform` — position, **one** scale, one rotation — which is
            // exactly a similarity and so follows this map whole. It is also why a flip or a Freeform
            // stretch cannot be handed to this function: neither fits in that shape.
            assert(t.a * t.d - t.b * t.c > 0,
                   "mapping(_:throughSimilarity:) was handed the reflection \(t) with a placed image "
                   + "in the piece. `LayerTransform` has no flip, so `theta` below would turn the "
                   + "photo through \(theta) rad instead of mirroring it. "
                   + "Ask `canBeMirrored(_:)` before offering Mirror.")
            image.transform.position = image.transform.position.applying(t)
            if k != 1 { image.transform.scale *= k }
            if theta != 0 { image.transform.rotation += theta }
            return .image(image)
        case .text(let text):
            // **A reflection is safe here, and that is what makes Mirror available on text** — the
            // assert this arm used to carry was policy rather than a real limit, and the owner ruled
            // it out on 2026-08-27 (LASSO_MOVE.md §5.18). Three separate things have to be true and
            // each is:
            //
            //  * `corners` are mapped **point for point** below, so a negative determinant simply
            //    reverses their winding. `TextFrame.affineTransform` is the ratio of those corners to
            //    `size`, so it comes back with a negative determinant of its own — which it already
            //    permits (`abs(det) > 1e-9`) — and every path that draws text concatenates exactly
            //    that matrix. The glyphs come out reflected: the words read backwards, in the order
            //    they were laid out, which is the ruling verbatim.
            //  * `k = hypot(t.a, t.b)` is still the true scale of a reflected similarity: a reflection
            //    preserves length, so the box and the point size follow it correctly.
            //  * `theta` is **not read by this arm at all**. It is what makes the `.image` case above
            //    assert — a `LayerTransform` has only an angle to put a reflection in, and a half turn
            //    is not a mirror — and a text frame has four free corners instead, so there is nothing
            //    here for the sign to corrupt.
            return .text(Self.mapped(text, through: t, uniformScale: k))
        }
    }

    /// **The text arm of both public mappings**, differing only in where the uniform scale comes from
    /// — `hypot(t.a, t.b)` for a similarity, `sqrt(|det t|)` for a stretch, which are the same number
    /// wherever the two overlap. Shared for `drawn(_:through:widthScale:)`'s reason: the half the two
    /// agree about must not be able to drift.
    ///
    /// **`corners` follow `t` whole; `size` and the point size follow only its *uniform* part.** For a
    /// similarity those are one statement, and the invariant `TextFrame.Basis` documents —
    /// `basis.width == size.width` — comes through untouched. For a stretch they are two, and the
    /// difference between them is exactly the residual aspect: the layout box is scaled uniformly, so
    /// CoreText wraps the same words onto the same lines, and `TextFrame.affineTransform` carries the
    /// per-axis distortion into the glyphs at draw time. That is the owner's ruling of 2026-08-27 —
    /// *"Same words, same line breaks, wider or taller glyphs"* — and it is also what makes the stretch
    /// arm **reduce to the similarity arm exactly** at `aspect == 1`, rather than drawing the same
    /// pixels out of a different stored document (LASSO_MOVE.md §5.18).
    ///
    /// **Scaling `size` and `pointSize` at all is not optional**, and the reason is worth keeping:
    /// mapping the corners alone would draw correctly, since the frame's own map is the ratio of the
    /// corners to `size` — but `TextFrameDrag` and `TextFrame.resized(to:)` read `basis.width` as a
    /// *layout* extent and write it back into `size`, so the first handle drag or the first keystroke
    /// into a still-`autoSize` box would snap the type back to the size it had before the move. Under
    /// a stretch the residual breaks that equality on purpose, and `TextFrame.needsBoxSpaceSizing` is
    /// what discharges it: both of those functions ask it and route through the frame's own map
    /// instead of through its basis.
    private static func mapped(_ text: VectorTextElement, through t: CGAffineTransform,
                               uniformScale k: CGFloat) -> VectorTextElement {
        var text = text
        // Stored **local**, despite `TextFrame.corners`' own doc saying canvas space — that
        // comment is written from the authoring perspective, and `localText(fromCanvas:)` maps
        // every incoming frame through `_transform.inverted()` before it is stored. Translating
        // stored corners by a canvas-space delta on a transformed layer sends the text somewhere
        // else entirely.
        text.frame.corners = text.frame.corners.map { $0.applying(t) }
        if k != 1 {
            text.frame.size = CGSize(width: text.frame.size.width * k,
                                     height: text.frame.size.height * k)
            // Stored unclamped; `Typography.pointSizeRange` (8...512) is applied at render, so a
            // piece shrunk past the floor and dragged back comes back at full size.
            text.recipe.typography.pointSize *= k
        }
        return text
    }

    /// **One element moved by a non-uniform `t` — the Move bar's Freeform.**
    ///
    /// `mapping(_:throughSimilarity:)` asserts its two axes scale alike, and its own doc says why:
    /// `hypot(t.a, t.b)` would be one number standing in for two. This is the other function that
    /// sentence promises, and it differs in exactly one place — where the ink's width comes from.
    ///
    /// ## The ink keeps its shape; the path stretches. Owner's ruling, 2026-08-26
    ///
    /// *"There should be an option on if the ink should be scaled/deformed or should stay the same
    /// when distorted"*, **defaulting to ink-keeps-its-shape** — one toggle over Freeform and Distort
    /// together. That default is what this function is: the centre line goes wherever `t` puts it, and
    /// the dab stays **round**. A 3:1 horizontal stretch gives a stroke whose spine is three times as
    /// long and whose ink is still a circle, not an ellipse.
    ///
    /// It is also the reason this stage needs **no renderer change at all**. The deforming half is a
    /// `saveGState`/`concatenate`/`restoreGState` around `DabGradientCache.stamp`, whose
    /// `drawRadialGradient` already draws an exact ellipse under a non-uniform CTM — but it needs the
    /// residue *stored on the stroke*, and therefore a `Codable` field, a decode default and a second
    /// implementation in both `DabTarget`s. None of that is here, and none of it is owed until the
    /// toggle ships.
    ///
    /// ## Which of the two scales the round dab takes
    ///
    /// **`sqrt(|det t|)` — the geometric mean of the two axis scales**, not one axis, not neither.
    /// Three things follow and each is the reason:
    ///
    ///  * **It agrees with Uniform where the two overlap.** For a similarity `sqrt(|det|) == k`
    ///    exactly, so a Freeform drag along the box's own diagonal produces the identical document a
    ///    Uniform drag would have. Taking "the ink never scales in Freeform" instead — the literal
    ///    reading of the owner's earlier *"default being no scaling"*, which was said of **Distort**,
    ///    where there is no global scale to speak of — would put a discontinuity exactly there: the
    ///    same visible gesture would thicken the ink in one mode and not the other.
    ///  * **It is the only choice that is symmetric in the two axes.** Picking `|t.a|` would make a
    ///    3:1 stretch and a 1:3 stretch produce different ink weights for the same shape turned
    ///    ninety degrees.
    ///  * **It composes.** `sqrt(|det|)` is multiplicative, so stretching 2:1 and then 1:2 leaves the
    ///    width exactly where it started rather than drifting by a factor per gesture.
    ///
    /// The stroke's own dab walk still pays `mapping(_:throughSimilarity:)`'s three floors, and one
    /// more besides: under a *non*-uniform map the walk is no longer similar to itself, so the dab
    /// count and phase genuinely do change. Nothing is lost by it — the weight and the path are both
    /// right — but the exactness claim the similarity carries does **not** extend here, and no test
    /// should be written as though it did.
    ///
    /// ## Text stretches; a placed image is the one kind this still refuses
    ///
    /// **Text distorts its letterforms and does not re-flow** — the owner's ruling of 2026-08-27,
    /// verbatim in LASSO_MOVE.md §5.18: *"Same words, same line breaks, wider or taller glyphs."* A
    /// `TextFrame` already stores four free corners, so a stretch costs it no new field and no decode
    /// migration; `mapped(_:through:uniformScale:)` is where the split between the box and the residual
    /// aspect is written down, and it is what makes this arm reduce to the similarity arm exactly at
    /// `aspect == 1`.
    ///
    /// A **placed image** genuinely cannot. `VectorImageElement.transform` *is* a `LayerTransform` —
    /// position, one scale, one rotation — with nowhere to put a second axis scale any more than a
    /// flip, so teaching it costs a stored field and a persistence migration and is its own stage (the
    /// owner's *"Teach images to hold a stretched shape"*). `canBeStretched(_:)` is the question asked
    /// *before* the artist is offered the mode, exactly as `canBeMirrored(_:)` is asked before they are
    /// offered the button; the two answers now differ, which is what that pair of properties was always
    /// separate for.
    static func mapping(_ element: VectorElement, throughStretch t: CGAffineTransform) -> VectorElement {
        guard !t.isIdentity else { return element }
        let k = sqrt(abs(t.a * t.d - t.b * t.c))
        switch element {
        case .stroke, .fill:
            return drawn(element, through: t, widthScale: k) ?? element
        case .text(let text):
            // `sqrt(|det t|)` is the uniform part, and it is the *same* choice §5.17 made for a
            // stroke's width — for a similarity it is `hypot(t.a, t.b)` to the last bit, which is what
            // makes a diagonal Freeform drag on a text box produce the identical document a Uniform
            // drag would. Everything `t` carries beyond it — the per-axis residue, and the shear a
            // non-uniform map leaves on a box the artist had rotated — lands in `corners`, where
            // `TextFrame.affineTransform` reads it as the glyphs' own distortion.
            return .text(mapped(text, through: t, uniformScale: k))
        case .image:
            assertionFailure("mapping(_:throughStretch:) was handed a placed image, whose "
                             + "`LayerTransform` cannot hold the per-axis stretch in \(t). Ask "
                             + "`canBeStretched(_:)` before offering Freeform.")
            return element
        }
    }

    /// The two kinds that follow **any** affine — a polyline of points carrying one scalar width, and
    /// a `CGPath`. Nil for the two whose own placement is a `LayerTransform` or four ordered corners,
    /// which each caller answers for itself because the answer differs: a similarity carries them and
    /// a stretch cannot.
    ///
    /// Shared by both public mappings so the half they agree about cannot drift — the same discipline
    /// `mapping(_:throughSimilarity:)`'s own header states for the kinds. `widthScale` is the one
    /// number they disagree about, and each derives it where the argument for it is written down.
    private static func drawn(_ element: VectorElement, through t: CGAffineTransform,
                              widthScale k: CGFloat) -> VectorElement? {
        var transform = t
        switch element {
        case .stroke(var stroke):
            stroke.samples = stroke.samples.map {
                let p = $0.point.applying(t)
                return VectorSample(x: p.x, y: p.y, pressure: $0.pressure)
            }
            if var lattice = stroke.lattice {
                lattice.samples = lattice.samples.map {
                    let p = $0.point.applying(t)
                    return VectorSample(x: p.x, y: p.y, pressure: $0.pressure)
                }
                stroke.lattice = lattice
            }
            // The scalar `BrushStamper` actually stamps with. Guarded on `k != 1` so a pure
            // translation leaves the stored number bit-identical rather than multiplied by a 1.0 that
            // rounding might not be.
            if k != 1 { stroke.size *= k }
            return .stroke(stroke)
        case .fill(let fill):
            // A `CGPath` carries the whole affine, scale and rotation included, so a fill needs no
            // currency of its own. (`copy(using:)` works in single precision — a mapped coordinate is
            // right to about 1e-6 of its magnitude, not to 1e-9.)
            guard let path = fill.cgPath, let moved = path.copy(using: &transform) else { return nil }
            var mapped = VectorFillElement(path: moved, color: fill.color, opacity: fill.opacity,
                                           evenOddFill: fill.evenOddFill)
            // The id is identity, not geometry: a nudge moves an element, it does not mint a new one,
            // and the float tracks its pieces by id.
            mapped.id = fill.id
            return .fill(mapped)
        case .image, .text:
            return nil
        }
    }

    /// Whether this element can go through `mapping(_:throughStretch:)` — i.e. whether **Freeform** is
    /// offerable on a float carrying it.
    ///
    /// The same shape as `canBeMirrored(_:)` below and for the same underlying reason, but they are
    /// two questions and not one: a reflection is a *similarity* that only the `.image` arm mishandles,
    /// and a per-axis stretch is not a similarity at all. **They no longer coincide** — as of the
    /// owner's ruling of 2026-08-27 a text box does both and a placed image still does neither — which
    /// is what the Move bar asking each separately was always for.
    ///
    ///  * a **stroke** is points plus one width, and a stretch moves the points and scales the width
    ///    by the map's own area root — visibly right, and the only sense in which a round dab can
    ///    follow a non-uniform map without becoming an ellipse;
    ///  * a **fill** is a `CGPath`, which carries any affine exactly, stretch included — so a fill is
    ///    the one kind Freeform is *perfect* on;
    ///  * a **text box** is four free corners over a layout `size`, so the stretch has somewhere to go
    ///    that costs no stored field and no decode migration: the box takes the map's *uniform* part,
    ///    which keeps the same words on the same lines, and the residual per-axis part stays in the
    ///    corners, where `TextFrame.affineTransform` reads it as the glyphs' own distortion. That is
    ///    the ruling — *"Same words, same line breaks, wider or taller glyphs"* — and it is a different
    ///    problem from perspective text, which needs the map to stop being affine at all;
    ///  * a **placed image** stores position, **one** scale and one rotation. There is nowhere in that
    ///    shape for two axis scales, and inventing one means a stored field and a decode migration. It
    ///    is the one kind still refused, and the only reason the two properties below are not now the
    ///    same function.
    static func canBeStretched(_ element: VectorElement) -> Bool {
        switch element {
        case .stroke, .fill, .text: return true
        case .image: return false
        }
    }

    /// Whether `mapping(_:throughSimilarity:)` would actually **carry** this element, or silently
    /// hand back the one it was given.
    ///
    /// **The nil that `mapping` swallows is a partial resize.** `drawn(_:through:widthScale:)`
    /// returns nil for a `.fill` whose archived `pathData` will not unarchive, and `mapping`'s
    /// `?? element` then keeps the element **unmapped** — which is right for a lasso nudge (one
    /// stubborn fill stays put; the artist can see it and try again) and is data corruption for a
    /// canvas resize, where that fill is left at coordinates the rest of the document no longer uses.
    /// CANVAS_RESIZE.md §5 rule 11 refuses the whole operation instead, and this is the predicate
    /// `CanvasManager.planResize(to:mode:)` asks before it writes anything.
    ///
    /// **A decode, not a render, and only one kind can fail it.** `.stroke` is a point array and one
    /// scalar; `.text` is four corners and a point size; `.image` is a `LayerTransform` — none of the
    /// three decodes anything on this path, and an `.image` whose `UIImage` has no `cgImage` is not a
    /// failure *here* either: this map moves its transform and never touches its pixels, and both
    /// raster primitives draw through `UIImage.draw(in:)`, which needs no `cgImage`. (CANVAS_RESIZE.md
    /// §2 lists `image.cgImage == nil` among the resize's failure modes; on the shipped code it is
    /// not one, and refusing a resize for it would decline a document nothing else declines.)
    /// `.fill` is the whole of it, and it fails exactly when `NSKeyedUnarchiver` cannot read the
    /// path — a damaged file, or an archive that failed at birth, which `VectorFillElement.init`'s
    /// `?? Data()` can produce.
    ///
    /// The map itself is not a parameter because it cannot change the answer: `CGPath.copy(using:)`
    /// succeeds for every invertible affine once there is a path to copy, and a resize's map always
    /// is one (`k > 0`). The unarchive is deterministic, so an element this admits is one the
    /// mutation pass will carry.
    static func canBeMapped(_ element: VectorElement) -> Bool {
        switch element {
        case .stroke, .text, .image: return true
        case .fill(let fill): return fill.cgPath != nil
        }
    }

    /// Whether this element can go through `mapping(_:throughSimilarity:)` with a **reflection** — the
    /// Move menu's Mirror — rather than only with an orientation-preserving similarity.
    ///
    /// Three kinds can, exactly, and one cannot at all:
    ///
    ///  * a **stroke** follows the map point for point, and its one scalar (`size`) is untouched by a
    ///    reflection, whose `k` is 1. A reflection preserves arc length, so `BrushStamper` walks the
    ///    identical number of dabs at the identical parameters and the seeded RNG draws the identical
    ///    sequence — the same argument the scale case makes above, with `k == 1`;
    ///  * a **fill** is a `CGPath`, which carries any affine including this one. Reversing every
    ///    subpath's winding together leaves the same interior under both fill rules;
    ///  * a **text box** is four corners over a layout size, and reflecting them reverses their
    ///    winding — which is precisely what a mirror *is*. The corners' order is not a fact the layout
    ///    acts on; the layout runs in the box's own coordinates and `TextFrame.affineTransform` carries
    ///    it out, sign and all, so a negative determinant reflects the rendered glyphs and the words
    ///    read backwards. **The owner ruled that is the wanted behaviour** on 2026-08-27
    ///    (LASSO_MOVE.md §5.18): a mirror reflects what is drawn, as in a real mirror, and does not
    ///    re-lay-out the string right-to-left. Mirror and mirror back is the original, exactly;
    ///  * a **placed image**'s whole placement is a `LayerTransform` — position, one *unsigned-in-
    ///    practice* scale, one rotation. There is no flip in that shape and no way to put one there
    ///    without a stored field and a decode migration, so a mirrored photo is not expressible. It is
    ///    the one kind left, and the `.image` arm of `mapping(_:throughSimilarity:)` still asserts.
    ///
    /// Stated here, beside the function that would be wrong, rather than in the Move bar: the bar asks
    /// (`CanvasManager.mirrorUnavailableReason`) and the `.image` arm above asserts. A third kind added
    /// to `VectorElement` has to answer this switch before it can be lassoed and mirrored.
    static func canBeMirrored(_ element: VectorElement) -> Bool {
        switch element {
        case .stroke, .fill, .text: return true
        case .image: return false
        }
    }

    /// One stroke's worth of what a Mode 2 gesture is about to do, described so a caller can show it
    /// without knowing anything about display lists.
    ///
    /// **Two halves, and the second one is not optional.** Erasing the doomed span alone is wrong,
    /// and wrong in a way that is easy to reason past: `BrushStamper` gives every stroke round end
    /// caps, so the two pieces a cut leaves behind grow caps of their own that reach *back into* the
    /// gap by the stroke's own radius. Cut a 40pt line with an 8pt eraser and the two new caps meet
    /// in the middle — the display list gains an element and **not one pixel changes**. A preview
    /// that only erased would open a hole the lift then fills back in.
    ///
    /// So: erase the span, then draw the surviving pieces' cap ends back. What is left is exactly
    /// `ink(stroke) − ink(pieces)`, which is the definition of what the cut removes.
    struct CutPreviewEdit {
        /// The dab-lattice walk to replay for the erase: the parent's samples for a piece carrying a
        /// `DabLattice`, the stroke's own otherwise. Canvas space.
        var eraseWalk: [VectorSample]
        /// `BrushStamper.seed(for:)`'s input — the lattice's parent id where there is one — so the
        /// erase lands on the same dabs the render put down.
        var eraseSeedID: UUID
        /// Spans of `eraseWalk`'s parametric domain to erase.
        var eraseRanges: [ClosedRange<CGFloat>]
        /// A surviving piece, and the window of it worth drawing back. Only the ends that abut a cut
        /// are in any window: the rest of the piece was never erased, and re-painting it would put
        /// this stroke's colour over whatever crosses above it.
        struct Restamp {
            var samples: [VectorSample]
            var range: ClosedRange<CGFloat>
        }
        var restamps: [Restamp]
        var brush: Brush
        /// Canvas-space diameter, i.e. the stored size through the layer transform's scale.
        var size: CGFloat
        var opacity: Double
        var color: UIColor
    }

    /// What a Mode 2 gesture ending here would take away, as something a caller can draw.
    /// **Reads only** — no element is touched, `version` does not move, and no render cache is
    /// dropped.
    ///
    /// This is `cutAlongFootprint`'s geometry with the splice removed: the same spatial-index query,
    /// the same `VectorEraser.cutRanges` probe walk, the same `effectiveCuts` merge, and the same
    /// `StrokeGeometry.splitStroke` pieces. It is that sharing, not a comment, that keeps
    /// `StrokeCanvasView`'s live preview showing what the lift will actually do — the two answers
    /// come out of one function.
    ///
    /// **Why not just punch the eraser's footprint, the way Mode 1 does.** Because Mode 2 does not
    /// remove the footprint. It removes the parametric spans of a stroke's *centreline* that lie
    /// under the footprint — the stroke's whole **width** over those spans — and then gives the two
    /// surviving pieces round end caps that grow straight back into the gap by the stroke's own
    /// radius. Both terms are large, they pull in opposite directions, and neither is the footprint:
    ///
    /// - Cut a **40pt** line with an **8pt** eraser and the caps meet in the middle: the display list
    ///   gains an element and **not one pixel changes**. MEASURED, `VectorCutPreviewLogicTests`.
    /// - Cut the same line with a **60pt** eraser and about a third of the footprint's width survives
    ///   as caps.
    ///
    /// A footprint punch is wrong in the same direction in both: it shows a nib-shaped bite that the
    /// lift has to hand back. This returns the actual difference instead.
    func cutPreviewEdits(alongPath canvasSpaceSamples: [VectorSample], brush: Brush, size: CGFloat,
                         accumulating accumulated: inout [UUID: [ClosedRange<CGFloat>]]) -> [CutPreviewEdit] {
        lock.lock()
        defer { lock.unlock() }
        guard !canvasSpaceSamples.isEmpty else { return [] }
        guard _elements.contains(where: { $0.stroke != nil }) else { return [] }

        let localSamples = Self.localSamples(canvasSpaceSamples, through: _transform)
        let rawScale = Self.scale(of: _transform)
        let scale = rawScale > 0 ? rawScale : 1
        let localSize = size / scale
        guard let sweep = VectorEraser.Sweep(samples: localSamples, brush: brush,
                                             size: localSize) else { return [] }

        let candidates = Set(strokeIndex().segments(near: sweep.bounds).map(\.elementIndex))
        guard !candidates.isEmpty else { return [] }
        let nibRadius = StrokeGeometry.stampRadius(forPressure: 1, brush: brush, size: size)

        var edits: [CutPreviewEdit] = []
        for index in candidates.sorted() {
            guard let stroke = _elements[index].stroke, stroke.composite == .paint else { continue }
            let increment = Self.effectiveCuts(VectorEraser.cutRanges(in: stroke.samples, sweep: sweep),
                                               in: stroke.samples)
            guard !increment.isEmpty else { continue }
            let domainEnd = CGFloat(Swift.max(stroke.samples.count - 1, 0))
            // **The caps have to be drawn against the whole gesture's cut, not this increment's.**
            // A piece's cap sits at the cut boundary, and the boundary moves outward with every touch
            // sample; caps drawn at the boundaries the gesture passed through are ink the finished cut
            // does not leave, and left alone they fill the gap in completely behind the eraser. So the
            // caller carries the accumulated cut per stroke across the drag and it is merged here.
            let previous = accumulated[stroke.id] ?? []
            let merged = StrokeGeometry.mergedCuts(previous + increment, clampedTo: 0...domainEnd)
            guard merged != previous else { continue }
            accumulated[stroke.id] = merged

            // The same fallback `stamp(stroke:into:isEraser:)` makes: a lattice with no usable range
            // would replay the *parent* whole, which is worse than ignoring it.
            let lattice = stroke.lattice.flatMap { $0.range == nil ? nil : $0 }
            let source = lattice?.samples ?? stroke.samples
            let canvasSize = stroke.size * scale
            let strokeRadius = StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush,
                                                          size: canvasSize)

            var eraseRanges: [ClosedRange<CGFloat>] = []
            for cut in increment {
                // Widened by the stroke's own radius before anything else: the cap drawn at the
                // *previous* boundary lies within one radius of it, on the gap side, and this is the
                // pass that clears it. On the other side the widening reaches into ink that survives,
                // which the restamp below puts back — its window is `strokeRadius + nibRadius`, so it
                // always covers what this took.
                let widened = Self.extend(cut, in: stroke.samples, by: strokeRadius / scale,
                                          clampedTo: 0...domainEnd)
                // A cut is expressed in the stroke's own domain; the walk being replayed is the
                // parent's, so the two ends move across with `DabLattice.parentParameter(of:)` —
                // exactly how the piece's own `visibleRange` was derived when it was cut.
                var span = lattice.map { $0.parentParameter(of: widened.lowerBound)
                                             ... $0.parentParameter(of: widened.upperBound) } ?? widened
                if let whole = lattice?.range {
                    let low = Swift.max(span.lowerBound, whole.lowerBound)
                    let high = Swift.min(span.upperBound, whole.upperBound)
                    guard high >= low else { continue }
                    span = low...high
                }
                eraseRanges.append(span)
            }
            guard !eraseRanges.isEmpty else { continue }

            // How far back into the erased gap a surviving cap can reach: its own radius, plus the
            // nib's, because the erase is a capsule of the nib's radius around the doomed centreline
            // and the cap has to be restored everywhere that capsule took it.
            let reach = strokeRadius + nibRadius
            var restamps: [CutPreviewEdit.Restamp] = []
            for run in StrokeGeometry.splitStrokeRuns(stroke.samples, removing: merged) {
                let canvasRun = Self.canvasSamples(run.samples, through: _transform)
                guard let first = run.parameters.first, let last = run.parameters.last else { continue }
                let startAbutsACut = first > StrokeGeometry.epsilon
                let endAbutsACut = last < domainEnd - StrokeGeometry.epsilon
                guard startAbutsACut || endAbutsACut else { continue }
                for window in Self.endWindows(of: canvasRun, reach: reach,
                                              fromStart: startAbutsACut, fromEnd: endAbutsACut) {
                    restamps.append(CutPreviewEdit.Restamp(samples: canvasRun, range: window))
                }
            }

            edits.append(CutPreviewEdit(eraseWalk: Self.canvasSamples(source, through: _transform),
                                        eraseSeedID: lattice?.seedID ?? stroke.id,
                                        eraseRanges: eraseRanges,
                                        restamps: restamps,
                                        brush: stroke.brush,
                                        size: canvasSize,
                                        opacity: stroke.opacity,
                                        color: stroke.uiColor))
        }
        return edits
    }

    /// `range` grown by `arcLength` points of the stroke at each end, in the sample-index domain.
    ///
    /// Walked by arc length for the same reason `endWindows` is, and rounded outward to a whole
    /// sample for the same reason: too generous by less than one segment is safe here, because the
    /// restamp that follows covers strictly more than this took away.
    private static func extend(_ range: ClosedRange<CGFloat>, in samples: [VectorSample],
                               by arcLength: CGFloat,
                               clampedTo domain: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        guard samples.count > 1, arcLength > 0 else { return range }

        func walk(from parameter: CGFloat, step: Int) -> CGFloat {
            let anchor = StrokeGeometry.interpolatedSample(in: samples, at: parameter)?.point
            var i = Int(step < 0 ? parameter.rounded(.down) : parameter.rounded(.up))
            i = Swift.max(0, Swift.min(i, samples.count - 1))
            // The partial step from a fractional boundary to its neighbouring sample counts: a cut
            // edge lands between samples far more often than on one.
            var travelled = anchor.map { hypot(samples[i].x - $0.x, samples[i].y - $0.y) } ?? 0
            while i + step >= 0, i + step < samples.count, travelled < arcLength {
                travelled += hypot(samples[i + step].x - samples[i].x, samples[i + step].y - samples[i].y)
                i += step
            }
            return CGFloat(i)
        }

        let low = Swift.max(domain.lowerBound, Swift.min(range.lowerBound, walk(from: range.lowerBound, step: -1)))
        let high = Swift.min(domain.upperBound, Swift.max(range.upperBound, walk(from: range.upperBound, step: 1)))
        return low > high ? range : low...high
    }

    /// The parametric windows of `samples` lying within `reach` of whichever ends are asked for.
    /// Two windows that meet collapse into one over the whole piece — which is what a short piece
    /// between two cuts wants, and it is also why this cannot just return one range per end.
    ///
    /// Walked by arc length rather than by sample count: `reach` is a radius in points, and a stroke's
    /// samples are as far apart as the pen was moving fast. The walk stops on the first sample at or
    /// beyond `reach` and keeps it whole rather than interpolating, so a window can only ever be too
    /// generous by less than one segment — and being too generous only means re-drawing ink that was
    /// never erased.
    private static func endWindows(of samples: [VectorSample], reach: CGFloat,
                                   fromStart: Bool, fromEnd: Bool) -> [ClosedRange<CGFloat>] {
        guard !samples.isEmpty, fromStart || fromEnd else { return [] }
        guard samples.count > 1 else { return [0...0] }
        let domainEnd = CGFloat(samples.count - 1)

        func walk(from index: Int, step: Int) -> Int {
            var travelled: CGFloat = 0
            var i = index
            while i + step >= 0, i + step < samples.count, travelled < reach {
                travelled += hypot(samples[i + step].x - samples[i].x, samples[i + step].y - samples[i].y)
                i += step
            }
            return i
        }

        let high = fromStart ? CGFloat(walk(from: 0, step: 1)) : 0
        let low = fromEnd ? CGFloat(walk(from: samples.count - 1, step: -1)) : domainEnd
        if fromStart && fromEnd {
            return low <= high ? [0...domainEnd] : [0...high, low...domainEnd]
        }
        return fromStart ? [0...high] : [low...domainEnd]
    }

    /// Draws one `CutPreviewEdit` into `target` — the whole of what a live Mode 2 preview *does*, and
    /// the reason it is here rather than in `StrokeCanvasView`: this file is in the UI-test target and
    /// that one is not, so the preview can be asserted against real pixels without a simulator.
    ///
    /// Erase first, then draw the caps back, in that order and never the other way: the erase is a
    /// `.destinationOut` punch and would take the restored caps with it.
    ///
    /// The erase's colour is arbitrary — `.destinationOut` reads only the dab's alpha coverage, which
    /// is why `stamp(stroke:into:isEraser: true)` above hands the *stroke's* colour through unchanged
    /// and is none the worse for it. The restamp's colour is not arbitrary and is the stroke's own.
    static func applyPreview(_ edit: CutPreviewEdit, into target: DabTarget) {
        let walk = edit.eraseWalk.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
        for range in edit.eraseRanges {
            BrushStamper.stampStroke(into: target, samples: walk, brush: edit.brush,
                                     color: .black, brushSize: edit.size,
                                     brushOpacity: edit.opacity, isEraser: true,
                                     seed: BrushStamper.seed(for: edit.eraseSeedID),
                                     visibleRange: range)
        }
        for restamp in edit.restamps {
            let samples = restamp.samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
            // No seed: a piece is minted with a fresh `id` at commit time, so there is no seed the
            // preview could match. Scatter and rotation jitter therefore land somewhere else in the
            // preview than they will after the cut — for a scattering brush this is an approximation,
            // and for every non-scattering one (`BrushStamper.stampDab` touches the RNG nowhere else
            // for a round shape) it is exact.
            BrushStamper.stampStroke(into: target, samples: samples, brush: edit.brush,
                                     color: edit.color, brushSize: edit.size,
                                     brushOpacity: edit.opacity, isEraser: false,
                                     visibleRange: restamp.range)
        }
    }

    /// Mode 3: **every** stroke whose centreline passes under the eraser's footprint loses the span
    /// between its own neighbouring crossings. Caller must hold `lock`. Returns the ids under the tip
    /// alongside the outcome, so the driver can suppress them next sample; passing every id on the
    /// layer in `suppressing` makes this a pure, non-mutating query.
    ///
    /// One footprint, many victims, is the owner's ruling of 2026-08-18 — *"the eraser brush size
    /// should be the radius around which everything is erased… if I erase the section where two lines
    /// intersect, it should erase both of them"*. It was one victim until then, chosen as the nearest
    /// centreline, and the size only gated reachability.
    ///
    /// **Assumption, stated because the owner has not been asked yet**: a stroke is taken when its
    /// *centreline* passes under the footprint, not merely when its ink does. That makes the circle the
    /// user sees exactly the rule, at the cost of a thick line being left alone when the eraser clips
    /// only its edge.
    ///
    /// Every victim is bracketed against the **pristine** display list and the splices applied
    /// afterwards, in descending index. Two lines that cross each other and are both taken in one tap
    /// must each see the other's original geometry, or whichever went second would compute its bracket
    /// against a stroke that no longer crosses it and be deleted whole.
    private func cutToIntersection(sweep: VectorEraser.Sweep, near hitPoint: CGPoint,
                                   suppressing: Set<UUID>)
        -> (outcome: VectorEraser.CutOutcome, underTip: Set<UUID>) {
        let index = strokeIndex()
        let candidates = Set(index.segments(near: sweep.bounds).map(\.elementIndex))
        guard !candidates.isEmpty else { return (.missed, []) }

        // Everything the eraser came down on: every candidate whose centreline the footprint actually
        // reaches (a near miss cuts nothing).
        var victims: [(index: Int, stroke: VectorStroke, parameter: CGFloat)] = []
        var underTip: Set<UUID> = []
        for elementIndex in candidates.sorted() {
            guard let stroke = _elements[elementIndex].stroke, stroke.composite == .paint,
                  !stroke.samples.isEmpty else { continue }
            guard let hit = StrokeGeometry.closestPoint(onPolyline: stroke.samples, to: hitPoint),
                  sweep.contains(hit.point) else { continue }
            underTip.insert(stroke.id)
            guard !suppressing.contains(stroke.id) else { continue }
            victims.append((elementIndex, stroke, hit.parameter))
        }
        guard !underTip.isEmpty else { return (.missed, []) }
        // Past this point the tip *is* over ink, so every remaining exit says `.unchanged` rather than
        // `.missed` — the driver must stay latched until the finger leaves those strokes.
        guard !victims.isEmpty else { return (.unchanged, underTip) }

        // INFERRED, not measured: this is the one place the change costs more per touch sample. Each
        // victim runs the same per-stroke work the single target used to — a spatial-index query and
        // an O(segments × segments) intersection test against each neighbour — so a wide eraser over
        // n strokes is n times the old cost. The index bounds `others` per victim and n is the number
        // of centrelines inside one nib, so it is small in practice; if a drag ever stutters in a
        // dense drawing, this loop is where to look first.
        var splices: [(index: Int, pieces: [VectorElement])] = []
        for victim in victims {
            // Everything that could cross it, with a width-aware tolerance per pair: lines whose ink
            // visibly touches read as crossed even when the centrelines miss.
            let targetReach = StrokeGeometry.stampRadius(forPressure: 1, brush: victim.stroke.brush,
                                                         size: victim.stroke.size)
            guard let targetBounds = StrokeGeometry.bounds(of: victim.stroke.samples,
                                                           padding: targetReach) else { continue }
            var others: [(points: [CGPoint], tolerance: CGFloat)] = []
            for elementIndex in Set(index.segments(near: targetBounds).map(\.elementIndex)).sorted()
            where elementIndex != victim.index {
                guard let other = _elements[elementIndex].stroke, other.composite == .paint,
                      other.samples.count > 1 else { continue }
                let reach = StrokeGeometry.stampRadius(forPressure: 1, brush: other.brush, size: other.size)
                others.append((other.samples.map(\.point), targetReach + reach))
            }

            let cuts = Self.effectiveCuts(VectorEraser.cutToIntersection(in: victim.stroke.samples,
                                                                         at: victim.parameter,
                                                                         others: others, footprint: sweep),
                                          in: victim.stroke.samples)
            guard !cuts.isEmpty else { continue }

            var pieces: [VectorElement] = []
            for run in StrokeGeometry.splitStroke(victim.stroke.samples, removing: cuts) {
                var piece = victim.stroke
                piece.id = UUID()
                piece.samples = run
                // As in Mode 2: deletes geometry, so the piece is its own stroke from here on.
                piece.lattice = nil
                pieces.append(.stroke(piece))
            }
            splices.append((victim.index, pieces))
        }
        guard !splices.isEmpty else { return (.unchanged, underTip) }

        // Descending, so an earlier splice cannot invalidate a later index.
        for splice in splices.sorted(by: { $0.index > $1.index }) {
            if let replaced = _elements[splice.index].stroke { underTip.remove(replaced.id) }
            for piece in splice.pieces { if let stroke = piece.stroke { underTip.insert(stroke.id) } }
            _elements.replaceSubrange(splice.index...splice.index, with: splice.pieces)
        }
        return (.cut, underTip)
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

    /// The **topmost** text object whose box covers `point`, or nil for a tap on bare canvas. What
    /// the text tool's placement tap asks before it makes a new box, so tapping an existing label
    /// re-opens it instead of starting a fresh one on top of it.
    ///
    /// **The box is hit, not the glyphs.** Tapping the hole in an "O" is tapping the text — an artist
    /// aims at the word, and a glyph-exact test would make a light script face nearly untappable and
    /// would need a full CoreText layout per candidate per tap. Every editor tests the box.
    ///
    /// **And it is the box through `H⁻¹`, not the box's bounding rectangle.** `TextFrame` is a layout
    /// box plus the four canvas points its corners map to; the inverse of that map sends `point` back
    /// into box-local space, where the test is `0…width × 0…height`. Containment in the *quad* is the
    /// same predicate written without the matrix — a homography maps the box onto the quad and takes
    /// straight lines to straight lines, so "inside the box" and "inside the quad" are one statement —
    /// which is why stage 3 can answer it exactly with no `Homography` type, a stage before that type
    /// exists. Testing `frame.boundingBox` instead would claim the empty corners of a rotated box,
    /// and `TextHitTestLogicTests` pins exactly that difference.
    ///
    /// `slop` widens the target by a fingertip, measured to the quad's edges rather than to a
    /// rectangle's, so a rotated box is no harder to hit than an upright one.
    ///
    /// **The point is mapped into local space first**, unlike `topmostStroke(atCanvasPoint:)` beside
    /// it, which tests a canvas-space point against local geometry and is therefore off by the
    /// layer's transform on a layer that has been moved. That is a pre-existing gap in a query used
    /// only by the motion-group retagging tap; it is not repeated here.
    func topmostText(atCanvasPoint point: CGPoint, slop: CGFloat = 6) -> VectorTextElement? {
        lock.lock()
        defer { lock.unlock() }
        var point = point
        var slop = slop
        if !_transform.isIdentity {
            point = point.applying(_transform.inverted())
            let s = Self.scale(of: _transform)
            if s > 0 { slop /= s }
        }
        for element in _elements.reversed() {
            guard let text = element.text else { continue }
            if Self.frame(text.frame, contains: point, slop: slop) { return text }
        }
        return nil
    }

    /// Point-in-quad with a slop collar. Space-agnostic: `point` and `frame.corners` must simply be
    /// in the *same* space — `topmostText(atCanvasPoint:)` maps the tap into local space first,
    /// because that is where a `VectorCanvas` stores its geometry. See there for why this is the
    /// `H⁻¹` test and not an approximation of one.
    /// **Stage 4 moved the body onto `TextFrame.contains(_:slop:)`** and left this as the name the
    /// display list calls it by. The live overlay needs the identical predicate for its own hit test
    /// (`TextOverlayView.hitTest`), and two copies of a point-in-quad test are two chances for the
    /// re-open query and the editor to disagree about where the text is.
    static func frame(_ frame: TextFrame, contains point: CGPoint, slop: CGFloat = 0) -> Bool {
        frame.contains(point, slop: slop)
    }

    // MARK: - Rendering

    /// What an empty canvas renders to instead of a canvas-sized sheet of transparent pixels. Every
    /// `render()` caller draws the result into a rect it already knows (the canvas bounds, or a
    /// texture's own size), so a 1×1 stretched over that rect is pixel-for-pixel the same nothing —
    /// and `localContentBounds()`, the one caller that reads the image instead of drawing it, wants
    /// nil for an empty canvas anyway.
    private static let transparentPixel: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1),
                                format: PixelOps.transparentFormat()).image { _ in }
    }()

    /// Rasterizes all content to a canvas-native `UIImage` (cached by `version`, one slot per
    /// quality). Strokes are stamped via `BrushStamper`; images drawn with their transforms; then the
    /// whole thing is drawn through the overall `transform`.
    ///
    /// `quality` changes only how a *stroke* is put down — see `RenderQuality`. The isolation rules
    /// that make an eraser correct are identical for both.
    func render(quality: RenderQuality = .full) -> UIImage {
        lock.lock()
        defer { lock.unlock() }
        return renderLocked(quality: quality)
    }

    /// `render(quality:)`, but **only while this canvas is still at `version`** — nil the moment the
    /// artist has moved on.
    ///
    /// This is what lets a bake share the display path's rasterize instead of doubling it, and it is
    /// the reason `Frozen` below carries a live reference alongside its frozen values. The two paths
    /// that want a vector cel's pixels at pen-up are `StrokeCanvasView.refreshDisplay` and the
    /// compositor's snapshot; both memoize into `cachedImage`, so today's synchronous ordering makes
    /// the second a cache read. Freezing the *values* and rendering them somewhere else would give a
    /// correct picture and stamp every dab of the cel a second time — the pessimisation this method
    /// exists to refuse. When the version has moved, the caller falls back to the values it froze,
    /// which is the whole atomicity guarantee and is the rare branch rather than the hot one.
    ///
    /// The version test and the render are one lock acquisition on purpose: taken separately, the
    /// image handed back could be of a version other than the one that was checked.
    func render(quality: RenderQuality, ifStillAtVersion version: Int) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard self.version == version else { return nil }
        return renderLocked(quality: quality)
    }

    /// What `render(quality:)` would hand back **without rasterizing anything** — the question
    /// `StrokeCanvasView.refreshDisplay` has to ask before it decides whether to block.
    ///
    /// Three answers rather than an optional, because "there is nothing to draw" and "there is
    /// something to draw and it is not rendered yet" are different instructions to a display: the
    /// first is free and final, the second is a dispatch. `.ready` also covers the empty canvas's
    /// shared 1×1, which `render()` returns without memoizing — see there.
    enum CachedRender {
        /// Nothing to draw. `renderIfNonEmpty()`'s nil, decided without touching a pixel.
        case empty(version: Int)
        /// The memoized render at `version`.
        case ready(UIImage, version: Int)
        /// Non-empty, not memoized: rasterizing is the only way to get `version`'s pixels.
        case needsRasterize(version: Int)

        /// What goes in a display's base slot for the two answers that have one now — nil for an
        /// empty canvas, which is a picture rather than a missing one (see `renderIfNonEmpty`).
        var image: UIImage? {
            if case .ready(let image, _) = self { return image }
            return nil
        }

        var version: Int {
            switch self {
            case .empty(let version), .ready(_, let version), .needsRasterize(let version):
                return version
            }
        }
    }

    func cachedRender(quality: RenderQuality = .full) -> CachedRender {
        lock.lock()
        defer { lock.unlock() }
        guard !_elements.isEmpty else { return .empty(version: version) }
        let memo = quality == .full ? cachedImage : cachedPreviewImage
        if let memo { return .ready(memo, version: version) }
        return .needsRasterize(version: version)
    }

    /// One canvas's render inputs, read under a **single** lock acquisition — what a `LeafSnapshot`
    /// carries so a composite can rasterize a vector tier off the main actor without the artist's
    /// next dab tearing the frame.
    ///
    /// **Reading the version and the elements under two acquisitions is the defect this type
    /// closes**: the key would then name a version the pixels are not.
    struct Frozen {
        /// The canvas these values came from, so `render` can share its memo while it is still at
        /// `version` — see `VectorCanvas.render(quality:ifStillAtVersion:)`.
        fileprivate let source: VectorCanvas
        /// `source.version` at the instant of the read.
        let version: Int
        /// `source`'s memo at `version`, when it had one. Present is the common case at rest and the
        /// end of the story — there is nothing left to rasterize.
        fileprivate let memoized: UIImage?

        // The values themselves. Copy-on-write, so freezing them is a retain rather than a copy —
        // which is the reason `Cel`'s two *class* tiers are the problem and its arrays are not.
        fileprivate let size: CGSize
        fileprivate let elements: [VectorElement]
        fileprivate let transform: CGAffineTransform
        fileprivate let suppressed: Set<UUID>

        /// The pixels these frozen values render to, safe to call from any thread.
        ///
        /// Three answers in the order they get cheaper to be wrong about: the memo the canvas already
        /// had, the memo it is about to have (still at `version`, so its render *is* these values and
        /// the two paths share one rasterize), and — only once the artist has moved on — a canvas
        /// built from the frozen values, which nothing else can reach and which is therefore the
        /// atomicity guarantee this whole type exists for.
        func render(quality: RenderQuality) -> UIImage {
            if let memoized { return memoized }
            if let shared = source.render(quality: quality, ifStillAtVersion: version) { return shared }
            // Built here rather than at freeze time so a mint over a hundred leaves allocates
            // nothing: this branch is reached only by a resolve the artist has raced.
            let detached = VectorCanvas(size: size, elements: elements, transform: transform)
            // Assigned rather than passed to the initialiser because it is transient state (see
            // `suppressedElementIDs`) and the setter is the one place that knows to invalidate; on a
            // canvas nobody has rendered yet that invalidation costs a counter.
            if !suppressed.isEmpty { detached.suppressedElementIDs = suppressed }
            return detached.render(quality: quality)
        }
    }

    /// Freezes this canvas's render inputs. See `Frozen`.
    ///
    /// `quality` picks which memo is looked at, so a request that will rasterize at `.preview` does
    /// not freeze a `.full` image it is never going to draw.
    func freeze(quality: RenderQuality) -> Frozen {
        lock.lock()
        defer { lock.unlock() }
        return Frozen(source: self, version: version,
                      memoized: quality == .full ? cachedImage : cachedPreviewImage,
                      size: size, elements: _elements, transform: _transform,
                      suppressed: _suppressedElementIDs)
    }

    /// Caller must hold `lock`.
    private func renderLocked(quality: RenderQuality) -> UIImage {
        // An empty canvas is now the steady state of a freshly added layer, and it is reached
        // eagerly: `StrokeCanvasView.vectorCanvas`'s `didSet` renders on assignment. Without this,
        // every empty vector layer would retain 16.8 MB of transparent pixels at 2048², 64 MB at
        // 4000², for nothing. `transform` deliberately isn't part of the test — an affine of nothing
        // is still nothing. (It used to be reachable: `resized(to:offset:)` left empty canvases
        // carrying a translation, which is exactly when a project has the most of them. It bakes
        // now, so no canvas the app produces carries one at all.)
        //
        // Nothing is memoized here on purpose: there is no allocation to amortize, and caching would
        // make `hasCachedImage` report a claim on memory that was never made, so eviction would
        // spend its budget on canvases that cost nothing.
        guard !_elements.isEmpty else { return Self.transparentPixel }
        switch quality {
        case .full: if let cachedImage { return cachedImage }
        case .preview: if let cachedPreviewImage { return cachedPreviewImage }
        }
        rasterizations += 1
        let bounds = CGRect(origin: .zero, size: size)
        let format = PixelOps.transparentFormat()

        // 1. Content in local (untransformed) space. The suppressed elements are skipped, not removed
        //    — see `suppressedElementIDs`.
        let content = renderLocalContent(elements: Self.visible(_elements, suppressing: _suppressedElementIDs),
                                         quality: quality)

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

    /// `render()` for the display path, which can say "no image" in a way the drawing paths cannot.
    /// An empty layer's image view is left holding nil rather than a stretched transparent pixel:
    /// Core Animation skips the layer's contents entirely instead of compositing a blank sheet over
    /// every frame, and with vector as the default layer kind that is the common case, not the edge.
    func renderIfNonEmpty(quality: RenderQuality = .full) -> UIImage? {
        isEmpty ? nil : render(quality: quality)
    }

    /// `_elements` minus the suppressed ones. A free identity return when nothing is suppressed,
    /// which is every render outside a text edit or a lasso move.
    private static func visible(_ elements: [VectorElement], suppressing ids: Set<UUID>) -> [VectorElement] {
        ids.isEmpty ? elements : elements.filter { !ids.contains($0.id) }
    }

    /// **Only** the elements named by `ids`, drawn through the same walk and the same isolation rules
    /// the whole layer uses, in canvas space — the picture a lasso move's floating piece shows while
    /// the artist drags it, exactly complementary to what `render()` shows with the same ids
    /// suppressed.
    ///
    /// Nil when nothing matches, so a caller cannot mistake an empty float for a working one.
    ///
    /// **A float of nothing but eraser marks legitimately renders blank, and that is not a failure.**
    /// A punch has no ink of its own — it lowers the alpha of what is beneath it *in the same display
    /// list* (rule 3 above) — so drawn alone into a transparent bitmap it draws nothing. The hole it
    /// makes reappears where it lands, when the move bakes. Nothing here or in
    /// `CanvasManager.beginVectorLassoMove` may read a blank image as "the lasso caught nothing".
    ///
    /// **Deliberately not memoized**, for `render()`'s own stated reason: it is called once per latch,
    /// and caching it would make `hasCachedImage` report a claim on memory the canvas is not making,
    /// so eviction would spend its budget on an image nothing is holding.
    func renderIsolated(ids: Set<UUID>) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        let isolated = _elements.filter { ids.contains($0.id) }
        guard !isolated.isEmpty else { return nil }
        rasterizations += 1
        let content = renderLocalContent(elements: isolated)
        guard !_transform.isIdentity else { return content }
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            ctx.cgContext.concatenate(_transform)
            content.draw(in: bounds)
        }
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
    ///
    /// **`elements` is a parameter rather than `_elements` filtered in here, and that is deliberate.**
    /// Two callers want different subsets — the display wants everything except what is suppressed,
    /// a lasso move's floating piece wants only the suppressed ones — and giving the second its own
    /// renderer would fork the three rules above, so that the float and the layer it was lifted out
    /// of could come to disagree about isolation. One walk, two lists.
    private func renderLocalContent(elements: [VectorElement], quality: RenderQuality = .full) -> UIImage {
        // `render()` has already returned by the time an empty canvas would reach here, so this
        // guard is for `localContentBounds()`: it spares the Move tool a canvas-sized rasterize plus
        // a several-million-pixel alpha scan to conclude what emptiness already said. Asked of the
        // *filtered* list, so a cel whose only element is the one being edited says the same.
        guard !elements.isEmpty else { return Self.transparentPixel }
        // `.standard` is load-bearing: `.preferredRange` defaults to `.automatic`, which on a
        // wide-colour iPad backs the context with an extended-range 16-bit bitmap, and stamping
        // thousands of radial gradients into that is drastically slower than into 8-bit. No fidelity
        // is lost — every raster tier already renders and persists as 8-bit deviceRGB.
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard
        // Hoisted so `lastRenderDabCount` can be read off it once the (synchronous) renderer closure
        // below has finished drawing.
        var target: CGContextDabTarget!
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            // One target — and so one `DabGradientCache` — for the whole walk: a per-run target would
            // throw away the cache's hit rate at every fill or eraser.
            target = CGContextDabTarget(cg)
            var index = 0
            while index < elements.count {
                switch elements[index] {
                case .fill(let fill):
                    Self.draw(fill: fill, into: cg)
                    index += 1
                case .image(let element):
                    Self.draw(image: element, into: cg)
                    index += 1
                case .text(let element):
                    // Ends a paint run exactly as a fill or an image does (rule 1 above): a stroke
                    // before it and a stroke after it must not blend against each other through it.
                    Self.draw(text: element, into: cg, quality: quality)
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
        lastRenderDabCount = target.dabCount
        return image
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

    /// Draws a text element's glyphs into the layer's local space.
    ///
    /// **It routes to `TextLayout.draw`, which is the same routine the raster bake and the live
    /// on-canvas overlay both draw through** — `ADD_TEXT.md` §2's closing warning is that sharing a
    /// *transform* does not make two rasterizers agree, and stage 1's own report says the overlay's
    /// `UITextView` draws no glyphs at all for exactly this reason. Adding a second rasterizer here
    /// would put TextKit on screen and CoreText in the artwork; there is one, and this is it.
    ///
    /// `quality` is accepted and deliberately ignored. `.preview` exists because a *stroke* costs
    /// hundreds of dabs and can be approximated by one stroked path; a CoreText pass into a text-box
    /// path is well under a millisecond (§4 rule 3) and has no cheaper form that is still text, so
    /// both tiers draw the same glyphs. The parameter is in the signature so that a future tier which
    /// *does* want a cheaper text — a grey bar while scrubbing, say — has somewhere to go, and so the
    /// reader is told the omission was decided rather than overlooked.
    ///
    /// **Stage 4 draws through `TextFrame.affineTransform`**, so a rotated or independently-scaled
    /// box flattens turned rather than through its bounding box — one concatenated matrix, no
    /// bitmap, no resampling, and byte-identical to stage 3 for an upright frame because there that
    /// matrix *is* the translate stage 3 wrote.
    ///
    /// **Stage 5 filled in the middle branch**: a `.projective` frame goes through
    /// `TextLayout.drawWarped`, which rasterises the glyphs at box size and carries them onto the
    /// quad with the `warpHomography` kernel. The bounding-box draw is still here and still the last
    /// resort, but it now means only "this quad has collapsed", not "this quad has perspective".
    /// Routing through `TextLayout` rather than warping here is stage 3's rasterizer rule one level
    /// up: there is one place text turns into pixels, and the bake and the flatten share it.
    ///
    /// **Known and not fixed: the `.projective` arm runs per *invalidation*, not per commit.**
    /// ADD_TEXT.md §4 rule 7 sizes the warp as "one canvas-sized cost, once, at bake", and that is
    /// true of the raster bake. It is not true here. A vector cel holding warped text re-runs a
    /// supersampled CoreText pass and a synchronous GPU round-trip (`MetalWarpEngine.warp` ends in
    /// `waitUntilCompleted`) on every flatten — a timeline tick, a thumbnail regen, an onion-skin
    /// pass. Rule 4 keeps the *bumps* down to two per text session, so this is bounded by how often
    /// something else invalidates the layer rather than by typing; the affine arm above has no such
    /// cost because it resamples nothing.
    ///
    /// A memo keyed on frame + recipe is the obvious fix and was **deliberately not taken here**:
    /// `TextRecipe` and `TextFrame` are `Equatable` but not `Hashable`, so it is a conformance
    /// spread across four types rather than a cache line, and the entry it would hold is a
    /// destination-sized bitmap in the budget §4 rule 6 describes as "a cliff, not a slope" — where
    /// an over-budget composite is declined *silently* and drops the whole upload cache
    /// process-wide. That is a trade the owner should make, not one to slip in beside a bug fix.
    /// [BUGS.md](BUGS.md) carries it.
    private static func draw(text element: VectorTextElement, into cg: CGContext, quality: RenderQuality) {
        _ = quality
        let frame = element.frame
        let box = frame.boundingBox
        guard !element.recipe.string.isEmpty, box.width > 0, box.height > 0 else { return }
        let font = FontLibrary.shared.resolve(element.recipe.font,
                                              size: element.recipe.typography.clamped.pointSize).font
        cg.saveGState()
        if let transform = frame.affineTransform {
            cg.concatenate(transform)
            TextLayout.draw(element.recipe, font: font, boxSize: frame.size,
                            clip: !frame.autoSize, into: cg)
        } else if TextLayout.drawWarped(element.recipe, frame: frame,
                                        clip: cg.boundingBoxOfClipPath) {
            // Nothing more: the warp drew itself, in the layer's own local coordinates — and inside
            // the context's own clip, which is the memory bound. This static has no canvas size to
            // pass and does not need one: `boundingBoxOfClipPath` is the flatten's own bounds here
            // (`renderLocalContent` builds the context at `size` and concatenates nothing before
            // this call), and it is the honest question anyway — a texel CoreGraphics is about to
            // discard is one the warp should never have allocated.
        } else {
            cg.translateBy(x: box.minX, y: box.minY)
            TextLayout.draw(element.recipe, font: font, boxSize: box.size,
                            clip: !frame.autoSize, into: cg)
        }
        cg.restoreGState()
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
    ///
    /// **The discriminator is read in two steps — raw `String` first, then looked up — and that split
    /// is the point.** A well-formed `kind` this build has no case for is a *newer file in an older
    /// build*: expected, benign, and nothing is wrong with the document. A missing, non-string, or
    /// structurally broken element is a defect. Decoding them both as an anonymous `DecodingError`
    /// makes the two indistinguishable, so `Failure.unknownKind` carries the first out separately and
    /// `VectorCanvasData.DecodeReport` counts them apart.
    enum ElementData: Codable {
        case stroke(VectorStroke)
        case fill(VectorFillElement)
        case image(ImageRef)
        /// **No sidecar and no `TextRef`.** `VectorTextElement` is the first vector element whose
        /// runtime and persisted forms are the same type — it holds no runtime resource, so it needs
        /// none of the `ImageRef` / `<project>/images/` machinery `.image` forces on `ProjectStore`,
        /// and the whole object rides inline in the cel's own `<celID>_vector.json`.
        ///
        /// The `"text"` discriminator is the fourth case the two-step decode above was built for. An
        /// older build meeting it loses **this element** and keeps the rest of the cel; before the
        /// per-element decode landed (`ADD_TEXT.md` stage 2) it would have swallowed the error and
        /// degraded the whole cel to `.empty`, discarding every stroke, fill and image on it.
        case text(VectorTextElement)

        /// The one decode failure worth naming. Everything else stays a `DecodingError` and is
        /// classified as malformed — see `VectorCanvasData.DecodeReport`.
        enum Failure: Error, Equatable {
            /// A `kind` string this build has no case for, e.g. an element written by a later version.
            case unknownKind(String)
        }

        private enum Kind: String, Codable { case stroke, fill, image, text }
        private enum CodingKeys: String, CodingKey { case kind, stroke, fill, image, text }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Decoded as `String`, not as `Kind`: `Kind`'s synthesized decoder answers the same
            // `dataCorrupted` for "no such case" as for "not a string at all", and those are the two
            // cases this whole design exists to tell apart.
            let raw = try c.decode(String.self, forKey: .kind)
            guard let kind = Kind(rawValue: raw) else { throw Failure.unknownKind(raw) }
            switch kind {
            case .stroke: self = .stroke(try c.decode(VectorStroke.self, forKey: .stroke))
            case .fill: self = .fill(try c.decode(VectorFillElement.self, forKey: .fill))
            case .image: self = .image(try c.decode(ImageRef.self, forKey: .image))
            case .text: self = .text(try c.decode(VectorTextElement.self, forKey: .text))
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
            case .text(let text):
                try c.encode(Kind.text, forKey: .kind)
                try c.encode(text, forKey: .text)
            }
        }
    }

    var elements: [ElementData]
    /// Overall transform as [a, b, c, d, tx, ty]; missing/short → identity.
    var transform: [Double]

    /// What `init(from:)` had to skip, and why. Empty for a payload built in memory.
    ///
    /// Decoding this payload is **per element**: one unreadable entry costs that entry and nothing
    /// else. It used to cost the cel — `ProjectStore`'s load wrapped the whole decode in `try?` and
    /// fell back to `VectorCanvas.empty`, so a single field it could not read discarded every stroke,
    /// fill, image and erase element the artist had drawn, silently, and the next save wrote the loss
    /// to disk. That is the failure mode this type is now shaped to make impossible.
    ///
    /// Not `Codable` and deliberately absent from `CodingKeys`: it describes *this decode*, not the
    /// document. Re-encoding a payload that dropped elements writes only the survivors, which is the
    /// honest thing to write — the report exists so the load path can say out loud that it happened
    /// before that point is reached.
    struct DecodeReport: Equatable {
        /// Discriminators this build has no case for, in file order. A project saved by a newer build
        /// and opened by an older one lands here; it is the expected, benign case, and the element
        /// belongs to a feature that does not exist in this binary.
        var unknownKinds: [String] = []
        /// Entries whose kind this build *does* know but whose payload would not decode — plus, on a
        /// legacy payload, any entry at all that would not decode (those files predate the
        /// discriminator, so "unknown kind" is not a thing they can express). A real defect: a bug or
        /// a damaged file, not a version gap.
        var malformedCount: Int = 0
        /// What each malformed entry *was*, in file order, for the ones whose discriminator was itself
        /// still readable — `"stroke"`, `"fill"`, `"image"`, `"text"`.
        ///
        /// **Shorter than `malformedCount` whenever an entry was broken at the discriminator**, which
        /// is why the two are separate rather than one array with a count. The count is the number the
        /// artist is owed; this is only how much of it can be named. A legacy payload names nothing at
        /// all, since those files have no discriminator to read.
        ///
        /// It exists so the save prompt can say "2 brush strokes and 1 fill on the Ink layer" rather
        /// than "3 elements failed to decode" — the artist judges the sentence, not the decoder.
        var malformedKinds: [String] = []

        var droppedCount: Int { unknownKinds.count + malformedCount }
        var isClean: Bool { droppedCount == 0 }
    }

    var decodeReport = DecodeReport()

    /// One slot of the persisted `elements` array, decoded so a failure is a *value* rather than a
    /// thrown error.
    ///
    /// **`init(from:)` never throws, and that is the load-bearing part rather than a stylistic
    /// choice.** `JSONDecoder`'s unkeyed container advances `currentIndex` only *after* a successful
    /// `decode`, so the obvious hand-rolled `while !container.isAtEnd { do { … } catch { continue } }`
    /// over `[ElementData]` re-reads the failing slot forever. Decoding `[LossySlot]` in one call
    /// sidesteps it entirely: every slot succeeds, and the ones holding nothing say why.
    private struct LossySlot: Decodable {
        enum Outcome {
            case decoded(ElementData)
            case unknownKind(String)
            /// The discriminator, when it was readable — see `DecodeReport.malformedKinds`. Nil when
            /// the entry was broken at the `kind` key itself, or is not an object at all.
            case malformed(String?)
        }
        let outcome: Outcome

        /// Just the discriminator, re-read on its own after a failed decode. A second, one-key pass
        /// over the same slot rather than a value threaded out of the first: `ElementData.init(from:)`
        /// throws from wherever it got to, and the *payload* it was decoding is what failed, so the
        /// `kind` beside it is usually still perfectly good. Reading it costs one `String` on a path
        /// that is already the failure path.
        private enum KindProbe: String, CodingKey { case kind }

        init(from decoder: Decoder) throws {
            do {
                outcome = .decoded(try ElementData(from: decoder))
            } catch ElementData.Failure.unknownKind(let raw) {
                outcome = .unknownKind(raw)
            } catch {
                let kind = try? decoder.container(keyedBy: KindProbe.self).decode(String.self, forKey: .kind)
                outcome = .malformed(kind)
            }
        }
    }

    /// `LossySlot` for the legacy parallel arrays, which carry no discriminator at all — so every
    /// failure there is malformed by definition and there is nothing to classify.
    private struct LossyValue<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

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
    var texts: [VectorTextElement] {
        elements.compactMap { if case .text(let text) = $0 { return text } else { return nil } }
    }

    private enum CodingKeys: String, CodingKey {
        case elements
        /// Legacy keys. Decoded, never written.
        ///
        /// `transform` joined the other three in TODO item (12) stage 3: a cel's geometry is stored
        /// in canvas coordinates, so there is nothing for a stored affine to mean. It is still read,
        /// and `canvasSpaceElements(resolvingImages:)` bakes what it finds.
        case transform
        /// Pre-display-list. Decoded when `elements` is absent.
        case strokes, fills, images
    }

    init(elements: [ElementData], transform: [Double]) {
        self.elements = elements
        self.transform = transform
    }

    /// **Writes canvas-space geometry and no transform at all** — TODO item (12) stage 3.
    ///
    /// The `transform` key is decode-only now, alongside the three legacy parallel arrays in
    /// `CodingKeys`, and it is left out of `encode(to:)` rather than written as `[1,0,0,1,0,0]`: a
    /// missing key decodes to `[]`, which `affineTransform` has always answered `.identity` for, so
    /// a build that predates this reads the baked geometry and applies nothing — the correct picture,
    /// with no version gap in either direction and 48 bytes a cel less on disk.
    ///
    /// The bake here is a no-op for anything the app produces, since nothing writes `_transform` any
    /// more (`setVectorTransform` went in stage 2, `resized(to:offset:)` bakes). It is kept because
    /// `VectorCanvas.init(size:elements:transform:)` still accepts one, so "the payload dropped a
    /// transform the canvas was carrying" would otherwise be a silent way to lose geometry.
    init(from canvas: VectorCanvas, imageFileNames: [UUID: String]) {
        let carried = canvas.transform
        let source = carried.isIdentity
            ? canvas.elements
            : canvas.elements.map { VectorCanvas.mapping($0, throughSimilarity: carried) }
        elements = source.compactMap { element in
            switch element {
            case .stroke(let stroke): return .stroke(stroke)
            case .fill(let fill): return .fill(fill)
            case .text(let text): return .text(text)
            case .image(let el):
                // An image whose PNG was never written has no name to reference, so it is dropped
                // rather than persisted as a dangling ref.
                guard let name = el.fileName ?? imageFileNames[el.id] else { return nil }
                return .image(ImageRef(fileName: name, x: el.transform.position.x, y: el.transform.position.y,
                                       scale: el.transform.scale, rotation: el.transform.rotation))
            }
        }
        transform = []
    }

    /// **The rule: a broken *element* costs that element; a broken *payload* still throws.**
    ///
    /// The two are different events and the load path needs them apart — "this file is not a vector
    /// payload at all" is unsalvageable and worth shouting about, while "this file has an entry I
    /// cannot read" costs one entry and the rest of the drawing is fine. So the container itself, and
    /// the choice between the ordered and legacy shapes, are still `try`; only the entries inside are
    /// tolerated.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A missing or unreadable transform costs the transform, not the drawing. `affineTransform`
        // below has always answered `.identity` for anything that is not six numbers and its comment
        // has always said so; it was this line, requiring the key, that could still throw the cel away
        // over it.
        transform = (try? c.decode([Double].self, forKey: .transform)) ?? []

        if let slots = try c.decodeIfPresent([LossySlot].self, forKey: .elements) {
            var decoded: [ElementData] = []
            decoded.reserveCapacity(slots.count)
            var report = DecodeReport()
            for slot in slots {
                switch slot.outcome {
                case .decoded(let element): decoded.append(element)
                case .unknownKind(let raw): report.unknownKinds.append(raw)
                case .malformed(let kind):
                    report.malformedCount += 1
                    if let kind { report.malformedKinds.append(kind) }
                }
            }
            elements = decoded
            decodeReport = report
            return
        }
        // Legacy payload: three parallel arrays and no z-order. Rebuild the old draw order — fills,
        // images, then strokes — so an existing project opens looking as it did.
        //
        // Per-element tolerance does not disturb that reconstruction: a dropped entry leaves a gap in
        // its own bucket and the three buckets are still concatenated fills → images → strokes, so
        // the surviving elements sit in exactly the relative order they would have had.
        let strokes = try c.decode([LossyValue<VectorStroke>].self, forKey: .strokes)
        let fills = try c.decode([LossyValue<VectorFillElement>].self, forKey: .fills)
        let images = try c.decode([LossyValue<ImageRef>].self, forKey: .images)
        elements = fills.compactMap { $0.value.map(ElementData.fill) }
            + images.compactMap { $0.value.map(ElementData.image) }
            + strokes.compactMap { $0.value.map(ElementData.stroke) }
        decodeReport = DecodeReport(malformedCount: strokes.count + fills.count + images.count - elements.count)
    }

    /// Legacy arrays are deliberately *not* mirrored alongside the ordered form: an `.erase` stroke
    /// listed in a legacy `strokes` array would render as paint in an older build.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elements, forKey: .elements)
    }

    /// Rebuilds the ordered display list **in canvas coordinates**, turning each `ImageRef` back into
    /// a `VectorImageElement` via `resolveImage`. A ref whose PNG can't be loaded is dropped — the
    /// same `compactMap` behaviour the load path had before, just kept here so ordering logic lives
    /// in one place.
    ///
    /// **`affineTransform` is baked in here, which is the whole of TODO item (12) stage 3's decode
    /// half, and it is on this accessor rather than in `ProjectStore` for two reasons.** It is the
    /// one door every caller already goes through, so no construction site can forget it and hand a
    /// `VectorCanvas` a transform it should not have; and it sits *after* the per-element `LossySlot`
    /// decode, so a cel whose payload dropped an element bakes the survivors, which is the honest
    /// thing to do and matches what re-encoding this type already does.
    ///
    /// It is exact: `mapping(_:throughSimilarity:)` measures 1.3e-13 pt over 264 similarity cases,
    /// and the only two writers that ever produced a stored transform — the deleted
    /// `setVectorTransform`, through `affine(from:pivot:)` with `aspect == 1`, and
    /// `resized(to:offset:)`, a pure translation — could only produce a similarity. The **rendered**
    /// result changes for a shrunk cel, and better: the bake is a native re-stamp where the stored
    /// transform was a bitmap magnify of a display list already clipped in local space.
    /// Documents are expendable (TODO.md, the owner 2026-08-27), so this is not migration machinery
    /// that has to be kept working — it is twelve lines that open the owner's current file correctly,
    /// and it costs nothing on a file this build wrote, where `transform` is absent.
    func canvasSpaceElements(resolvingImages resolveImage: (ImageRef) -> UIImage?) -> [VectorElement] {
        let stored = affineTransform
        let rebuilt = localElements(resolvingImages: resolveImage)
        guard !stored.isIdentity else { return rebuilt }
        return rebuilt.map { VectorCanvas.mapping($0, throughSimilarity: stored) }
    }

    /// The display list as the file literally holds it, before `affineTransform` is baked in. Private
    /// to the accessor above — nothing outside this type has any business with layer-local geometry.
    private func localElements(resolvingImages resolveImage: (ImageRef) -> UIImage?) -> [VectorElement] {
        elements.compactMap { data in
            switch data {
            case .stroke(let stroke): return .stroke(stroke)
            case .fill(let fill): return .fill(fill)
            case .text(let text): return .text(text)
            case .image(let ref):
                guard let image = resolveImage(ref) else { return nil }
                return .image(VectorImageElement(image: image,
                                                 transform: LayerTransform(position: CGPoint(x: ref.x, y: ref.y),
                                                                           scale: ref.scale, rotation: ref.rotation),
                                                 fileName: ref.fileName))
            }
        }
    }

    /// What the *file* said, which since TODO item (12) stage 3 is only ever something an older
    /// build wrote — `canvasSpaceElements(resolvingImages:)` bakes it and nothing writes it back.
    /// Six numbers or nothing: a missing, short or unreadable key is identity, which it has answered
    /// since long before it was load-bearing.
    var affineTransform: CGAffineTransform {
        guard transform.count == 6 else { return .identity }
        return CGAffineTransform(a: CGFloat(transform[0]), b: CGFloat(transform[1]), c: CGFloat(transform[2]),
                                 d: CGFloat(transform[3]), tx: CGFloat(transform[4]), ty: CGFloat(transform[5]))
    }
}
