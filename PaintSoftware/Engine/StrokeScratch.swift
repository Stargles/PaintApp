import UIKit
import CoreGraphics

/// The live-stroke drawing surface, sized to the stroke instead of to the canvas.
///
/// **Why this exists: a 16383² canvas is 1 GiB per RGBA buffer and the iPad has ~1.4 GiB before
/// jetsam.** Every live stroke used to open a `RasterLayerTexture` at `canvasSize` on touch-down,
/// materialise its full-canvas `CGContext` on the first dab, and mint a full-canvas `makeImage()`
/// per touch-move batch — which is copy-on-write, so the *next* dab duplicated the whole thing.
/// Two touch-moves into a stroke the live set was several canvases. The artist's report was
/// "a 16k by 16k canvas crashes when you draw something", and every term in that arithmetic is
/// canvas *area* against a stroke that touches a few thousand pixels.
///
/// So the scratch is a **window**: a rectangle in canvas point space that starts at the first dab
/// and grows to contain the stroke, clamped to the canvas. Nothing here is proportional to canvas
/// area — the peak is the stroke's own bounding box plus its growth margin.
///
/// **Growth is geometric per axis, and it has to be — on both counts.** Outsetting by a fixed pad
/// would reallocate every time the pen left the window, which is O(n²) copying over a long stroke.
/// So an axis the stroke has left is outset by half of *that axis's* own extent (floored at
/// `minimumPad`): it at least doubles, the box's area at least doubles with it, and the total
/// copying over a stroke is O(final area) rather than O(area × reallocations). An axis the stroke
/// has **not** left is not outset at all — it needs no headroom, and the guarantee above is already
/// paid by the axis that moved. That is what keeps a straight line's window a band as wide as the
/// line rather than a square as big as its length. The gesture that made the case is one screen inch
/// of pen travel at 16383², MEASURED on the owner's iPad 9 at **8617×8611 — 283.1 MB** round a stroke
/// whose own box is 54 KB; simulating both rules over that gesture gives **8639×134, 4.42 MB**
/// (PERFORMANCE §9 item 1, which also records that the width still overshoots the ink about
/// threefold because an outset grows both sides of the axis). A stroke that really does cross the
/// whole canvas ends up with a canvas-sized window, which is correct rather than a failure: that
/// stroke's dirty rect *is* the canvas.
///
/// **The three roles are the same distinction `VectorScratchRole` draws, and they decide how the
/// window reaches the screen as well as how it commits.** `.additive` holds only this stroke's own
/// ink and is composited *over* the layer's picture, so the layer's picture stays on screen
/// underneath and the commit is a source-over draw at the stroke's own opacity. `.subtractive` holds
/// this stroke's own **removal coverage** and *stands in for* the layer's picture inside the window,
/// so the display has to hide the layer's picture there (`StrokeCanvasView.showOverlays` punches it
/// out) and the commit is one `.destinationOut` merge of that coverage at the stroke's opacity.
/// `.replacing` presents a frozen ordered native vector list through the same bounded window; it
/// allocates one rendered content image and has no raster commit.
///
/// **`.subtractive` is BRUSH.md §2.11's eraser and the arithmetic is exact.** N `.destinationOut`
/// dabs at `aᵢ` punched one at a time leave `∏(1 - aᵢ)` — a number no cap can be applied to, because
/// the punching already happened. A coverage window accumulates the same dabs source-over to
/// `A = 1 - ∏(1 - aᵢ)` and one punch at the stroke's opacity `o` leaves `1 - o·A`. At `o == 1` those
/// are the same number; below it, only the second obeys *"a 50% eraser removes exactly 50% wherever
/// the stroke goes, however often it crosses back over itself"*.
final class StrokeScratch: DabTarget {

    /// What the window's pixels mean, and therefore how they are shown and how they commit.
    enum Role {
        /// This stroke's ink and nothing else, over the layer's own picture.
        case additive
        /// This stroke's **removal coverage** and nothing else — BRUSH.md §2.11's eraser. `backdrop`
        /// is the layer's own picture, used to *show* the removal (the coverage punched out of a crop
        /// of it) and to decide whether there is anything to remove at all; the window itself never
        /// holds a pixel of it. **Nil is a legitimate empty start**: a layer with no bitmap yet has
        /// nothing to erase.
        case subtractive(backdrop: CelContentPicture?)
        /// A bounded native display-list replacement used while vector geometry is being edited.
        /// Its pixels are rendered directly from `celContent` into `windowRect`; no raster scratch
        /// is allocated alongside that presentation window.
        case replacing
    }

    let canvasSize: CGSize
    let role: Role

    /// Captured once at touch-down. Placement and source identity cannot change under this scratch.
    struct CelContent {
        let backing: CelPixelSnapshot?
        let ink: CelContentPicture.Ink
        let placement: CelContentPlacement
    }
    private(set) var celContent: CelContent?
    private var contentPresentation: (version: Int, value: CelContentPicture.RenderedWindow)?

    /// The existing window version also owns the complete shown picture. A recreated window drops
    /// this memo with its other image memos, so version zero never aliases an earlier texture.
    var renderedCelContent: CelContentPicture.RenderedWindow? {
        guard let celContent, !windowRect.isNull else { return nil }
        let version = window?.version ?? -1
        if let cached = contentPresentation, cached.version == version { return cached.value }
        let picture: CelContentPicture
        if case .replacing = role {
            // Drawn off main by `replaceCelContent`; only a finished picture is ever answered.
            return contentPresentation?.value
        } else {
            guard let window, let image else { return nil }
            picture = CelContentPicture(size: canvasSize, window: windowRect,
                backing: celContent.backing, patch: nil, ink: celContent.ink, inkPatch: image)
        }
        guard let rendered = picture.rendered(placement: celContent.placement) else { return nil }
        contentPresentation = (version, rendered)
        return rendered
    }

    /// **Where a `.replacing` scratch's pictures are drawn** (SCHEDULER rules 1, 2 and 4). Rendering the
    /// admitted window re-draws every element in it, which at 5000² with five vector layers took a
    /// 6.1 s main-thread pass in one eraser stroke (nov17 `handoff-1`), so main never does it: it
    /// records the newest display list and the render runs on this queue, latest wins.
    private static let renderQueue = DispatchQueue(label: "com.paintapp.StrokeScratch.render",
                                                   qos: .userInitiated)
    private var renders: LatestWins?
    /// The newest replacement asked for, and the one whose picture `contentPresentation` holds.
    private var requestedRender = 0
    private var shownRender = 0
    /// Main-thread landing of a finished picture; the view re-reads `renderedCelContent` and swaps it in.
    var onRenderLanded: (() -> Void)?

    /// Test seam: called with `Thread.isMainThread` for every replacement render.
    nonisolated(unsafe) static var renderObserver: ((_ onMain: Bool) -> Void)?

    /// Whether a newer display list than the picture on screen has been admitted.
    var hasPendingRender: Bool { requestedRender != shownRender }

    /// Replaces the frozen display list and admits its measured damage into the existing geometric
    /// window. The window's picture is drawn off the main thread (latest wins); until it lands
    /// `renderedCelContent` keeps answering the last finished one, never an older or blank one.
    func replaceCelContent(ink: CelContentPicture.Ink, damage: CGRect) -> Bool {
        guard case .replacing = role, let celContent,
              let next = nextWindowRect(containing: damage) else { return false }
        let updated = CelContent(backing: celContent.backing, ink: ink,
                                 placement: celContent.placement)
        let picture = CelContentPicture(size: canvasSize, window: next,
            backing: updated.backing, patch: nil, ink: updated.ink)
        self.celContent = updated
        windowRect = next
        requestedRender += 1
        let revision = requestedRender
        let placement = updated.placement
        let renders = self.renders ?? MainActor.assumeIsolated { LatestWins(queue: Self.renderQueue) }
        self.renders = renders
        MainActor.assumeIsolated {
            renders.request { [weak self] in
                guard self != nil else { return nil }
                return {
                    Self.renderObserver?(Thread.isMainThread)
                    let rendered = picture.rendered(placement: placement)
                    return { [weak self] in
                        guard let self, revision == self.requestedRender else { return }
                        guard let rendered else {
                            self.failure = picture.hasFailed ? .unreadableBacking : .allocationRefused
                            return
                        }
                        self.failure = nil
                        self.contentPresentation = (-1, rendered)
                        self.shownRender = revision
                        self.onRenderLanded?()
                    }
                }
            }
        }
        return true
    }

    /// **Lift only**: makes the shown picture the newest one, drawing it here if the background render
    /// has not landed, so a finished stroke is never handed off one step behind (erased ink would come
    /// back). One window-sized render at pen-up, not one per move.
    func settleCelContent() {
        guard case .replacing = role, hasPendingRender, let celContent, !windowRect.isNull else { return }
        MainActor.assumeIsolated { renders?.cancel() }
        let picture = CelContentPicture(size: canvasSize, window: windowRect,
            backing: celContent.backing, patch: nil, ink: celContent.ink)
        Self.renderObserver?(Thread.isMainThread)
        guard let rendered = picture.rendered(placement: celContent.placement) else {
            failure = picture.hasFailed ? .unreadableBacking : .allocationRefused
            return
        }
        failure = nil
        contentPresentation = (-1, rendered)
        shownRender = requestedRender
    }

    /// Reuses the touch-down reference frames and their original display-list slots while replacing
    /// only editable geometry. `contentPresentation` is the one invalidated image memo.
    func replaceVectorDisplay(elements: [VectorElement], rewriting: Set<UUID>, damage: CGRect) -> Bool {
        guard let celContent,
              case .ordinary(let source, let captured, _) = celContent.ink else { return false }
        let references = Dictionary(uniqueKeysWithValues: captured.filter(\.isReference).map { ($0.id, $0) })
        let ordered = elements.map { element in
            element.isReference ? (references[element.id] ?? element) : element
        }
        let referenceIDs = Set(ordered.lazy.filter(\.isReference).map(\.id))
        let frozen = source.replacingDisplayElements(ordered, rewriting: rewriting,
                                                      referenceIDs: referenceIDs)
        return replaceCelContent(ink: .ordinary(source: frozen, elements: ordered, rewriting: rewriting),
                                 damage: damage)
    }

    /// Whether this replacement currently contains a successfully rendered picture for all of the
    /// supplied damage. The admitted window and its existing failure latch are the validity record;
    /// a refused later growth can retain an older image, but that image is not current for the new
    /// damage and must not be presented or handed off.
    func hasCurrentReplacementWindow(covering damage: CGRect) -> Bool {
        guard case .replacing = role, !damage.isNull, !damage.isInfinite,
              damage.width > 0, damage.height > 0,
              case .success = lastMutationResult,
              windowRect.contains(damage) else { return false }
        // The picture may be one step behind the display list while the background render runs;
        // the last finished one stays up, and lift settles it (`settleCelContent`).
        return renderedCelContent != nil
    }

    /// **The stroke's own opacity — BRUSH.md §2.11's cap, applied once when the window merges.**
    /// Stored rather than passed to `commit`, because the display needs the same number (`.additive`
    /// shows the window at this alpha, `.subtractive` punches the backdrop with it) and two callers
    /// each supplying it is two chances for the picture under the pen and the ink that lands to
    /// disagree.
    let opacity: CGFloat
    /// How the finished stroke meets the layer. `.normal` for everything but a brush carrying a blend
    /// mode; the eraser's punch is `.subtractive`'s own arithmetic rather than a mode carried here.
    let blendMode: CGBlendMode

    /// **The paper this stroke lays its ink through — BRUSH.md §2.25**, or nil for a brush with none.
    ///
    /// Stored here for the reason `opacity` is stored here rather than passed to `commit`: the
    /// display shows the same picture the commit lands, and two callers each supplying it is two
    /// chances for what is under the pen and what is drawn to disagree.
    ///
    /// The live tier stamps straight into the window as the pen moves; paper is applied at merge.
    let texture: BrushTextureSettings?

    /// Whether the window stands in for the layer's own picture inside `windowRect`, rather than
    /// sitting over it. Read by the display to decide whether to punch the base out.
    var replacesBase: Bool {
        switch role {
        case .additive: return false
        case .subtractive, .replacing: return true
        }
    }

    /// The window's rectangle in canvas point space — integral, and clamped to the canvas.
    /// `.null` until the first dab, which is what makes a touch that never moves cost nothing.
    private(set) var windowRect: CGRect = .null

    private var window: RasterLayerTexture?
    private let residency: RasterResidency
    private var failure: RasterResidency.Failure?
    var lastMutationResult: Result<Void, RasterResidency.Failure> {
        if let failure { return .failure(failure) }
        return window?.lastMutationResult ?? .success(())
    }

    /// The dirty rect accumulated by windows this stroke has already outgrown. The live window's
    /// own `strokeDirtyRect` is unioned onto it by `dirtyRect`; reallocation folds one into the
    /// other, so a stroke that grows its window three times still reports the union of every dab.
    private var carriedDirtyRect: CGRect?

    /// Smallest margin a growth leaves around the dabs that forced it. Large enough that ordinary
    /// pen travel between reallocations is many samples, small enough to be noise next to any
    /// canvas worth worrying about.
    private static let minimumPad: CGFloat = 64

    init(canvasSize: CGSize, role: Role, opacity: CGFloat = 1, blendMode: CGBlendMode = .normal,
         texture: BrushTextureSettings? = nil, celContent: CelContent? = nil,
         residency: RasterResidency = .shared) {
        self.canvasSize = canvasSize
        self.role = role
        self.opacity = opacity
        self.blendMode = blendMode
        self.texture = texture
        self.celContent = celContent
        self.residency = residency
    }

    // MARK: - Reading

    /// **What the display shows for this window**, or nil before the first dab lands.
    ///
    /// For `.additive` and `.replacing` that is the window's own pixels. For `.subtractive` the
    /// window holds *coverage*, which is not a picture of anything — so the removal is drawn as a
    /// removal: the backdrop under the window, with the coverage punched out of it at the stroke's
    /// opacity. That is the same arithmetic `commit` performs against the cel, one crop wide, which
    /// is what makes the ink that lands the ink that was under the pen.
    var image: UIImage? {
        if case .replacing = role { return renderedCelContent?.image }
        guard let window, !windowRect.isNull else { return nil }
        guard case .subtractive(let backdrop) = role else { return windowContents }
        // Memoized on the window's own version, exactly as `RasterLayerTexture.renderToUIImage` is
        // memoized on it. `StrokeCanvasView.refreshDisplay` asks for this once per SwiftUI pass and
        // several of those can land between two dabs; without the memo each one would be a fresh
        // window-sized composite, and the view's identity check (`scratchView.image !== image`)
        // would never hit either.
        if let cached = punchedImage, cachedPunchVersion == window.version { return cached }
        guard let coverage = windowContents else { return nil }
        guard let punched = renderedImage(size: windowRect.size, drawing: { context in
            let completed = backdrop?.draw(into: context,
                content: CGRect(origin: CGPoint(x: -windowRect.minX, y: -windowRect.minY), size: canvasSize),
                placement: .identity) ?? true
            coverage.draw(at: .zero, blendMode: .destinationOut, alpha: opacity)
            return completed
        }) else { return nil }
        punchedImage = punched
        cachedPunchVersion = window.version
        return punched
    }

    /// `.subtractive`'s display image and the window version it was built from. Nil for every other
    /// role, which never mints one.
    private var punchedImage: UIImage?
    private var cachedPunchVersion: Int = -1

    /// **The window's own pixels with BRUSH.md §2.25's paper multiplied in** — what this stroke's ink
    /// (or its removal coverage) actually *is*, once the texture has had its say.
    ///
    /// **This is the live tier's merge point.** The window holds the accumulated dabs, and `commit`
    /// applies the paper and stroke opacity once.
    ///
    /// `.replacing` is excluded because its native display-list render already contains the layer's ink.
    ///
    /// Memoized on the window's own version, exactly as the punch above is and for the same reason:
    /// `StrokeCanvasView.refreshDisplay` asks several times between two dabs.
    private var windowContents: UIImage? {
        guard let window, !windowRect.isNull else { return nil }
        let raw: UIImage
        switch window.renderToUIImage() {
        case .success(let image): raw = image
        case .failure(let error): failure = error; return nil
        }
        guard let texture, texture.depth > 0, texturesItsOwnWindow else { return raw }
        if let cached = texturedImage, cachedTextureVersion == window.version { return cached }
        guard let textured = renderedImage(size: windowRect.size, drawing: { context in
            raw.draw(at: .zero)
            BrushTextureMerge.apply(texture, into: context,
                                    over: CGRect(origin: .zero, size: windowRect.size),
                                    canvasOrigin: windowRect.origin)
            return true
        }) else { return nil }
        texturedImage = textured
        cachedTextureVersion = window.version
        return textured
    }

    private var texturedImage: UIImage?
    private var cachedTextureVersion: Int = -1

    /// Whether this role's window is one stroke's own accumulation — see `windowContents`.
    private var texturesItsOwnWindow: Bool {
        switch role {
        case .additive, .subtractive: return true
        case .replacing: return false
        }
    }

    /// Union of every dab this stroke has laid, in canvas point space — what the raster undo step
    /// crops its before/after patches to, and the measure of what this class exists to bound.
    var dirtyRect: CGRect? {
        guard let live = window?.strokeDirtyRect else { return carriedDirtyRect }
        let offset = live.offsetBy(dx: windowRect.minX, dy: windowRect.minY)
        return carriedDirtyRect?.union(offset) ?? offset
    }

    /// Pixels the window is actually holding. Nothing in the app reads this; it is the number the
    /// logic tests assert against, because "bounded by the stroke and not by the canvas" is a claim
    /// about exactly this quantity.
    var windowPixelCount: Int {
        guard let window else { return 0 }
        return window.pixelWidth * window.pixelHeight
    }

    // MARK: - DabTarget

    /// No-ops. `BrushStamper.stampStroke` brackets its walk with these to maintain a *persistent*
    /// texture's stroke count; a scratch is thrown away at lift and nothing counts strokes on it.
    /// They stay no-ops rather than forwarding: the live tier has no group to retain between calls.
    func beginStroke() {}
    func endStroke() {}

    /// **A group held here rather than forwarded, because the window can move under it.**
    ///
    /// `RasterLayerTexture` merges a group by opening a transparency layer on its own bitmap — and a
    /// dab outside the current window *replaces* that bitmap with a larger one (`window(containing:)`),
    /// which would throw the open layer and everything drawn into it away. So the dabs are collected
    /// in canvas space here, the window is grown once to contain all of them, and only then is the
    /// group opened on the window that is going to keep them. Nothing is buffered outside a group,
    /// which is the live walk's whole path: it stamps straight through, and the merge is `commit`.
    func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?) {}
    func endStrokeGroup() {}

    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        if case .replacing = role { return }
        guard radius > 0, alpha > 0 else { return }
        // `options: []` on the dab's radial gradient paints nothing past `radius`, so this is the
        // exact bound — the same rectangle `RasterLayerTexture.stampCircle` accumulates.
        let bounds = dabCircleBounds(at: point, radius: radius)
        guard let window = window(containing: bounds) else { return }
        window.stampCircle(at: CGPoint(x: point.x - windowRect.minX, y: point.y - windowRect.minY),
                           radius: radius, color: color, alpha: alpha, hardness: hardness,
                           blendMode: blendMode)
    }

    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
        if case .replacing = role { return }
        guard diameter > 0, alpha > 0 else { return }
        // A turned square reaches further than an unturned one — up to `diameter · √2 / 2` at 45° —
        // and the window has to contain the pixels, not the nominal size. `dabImageBounds` is the
        // same function `RasterLayerTexture.stampImage` accumulates its dirty rect with, so the
        // window and the dirty rect cannot disagree about what a dab covered.
        let bounds = dabImageBounds(at: point, diameter: diameter, angle: angle)
        guard let window = window(containing: bounds) else { return }
        window.stampImage(texture, at: CGPoint(x: point.x - windowRect.minX, y: point.y - windowRect.minY),
                          diameter: diameter, angle: angle, color: color, alpha: alpha,
                          blendMode: blendMode)
    }

    // MARK: - Selection clip

    /// Clears this stroke's window pixels outside `path` (canvas space). The window holds only
    /// this stroke's ink or removal coverage, so its clipped commit preserves the backdrop.
    func clip(to path: CGPath) {
        guard let window, !windowRect.isNull else { return }
        let current: UIImage
        switch window.renderToUIImage() {
        case .success(let image): current = image
        case .failure(let error): failure = error; return
        }
        carriedDirtyRect = dirtyRect
        let clipped = RasterLayerTexture.rendered(size: windowRect.size, canvasOrigin: windowRect.origin,
                                                   using: residency) { context in
            context.translateBy(x: -windowRect.minX, y: -windowRect.minY)
            context.saveGState()
            context.addPath(path)
            context.clip()
            current.draw(at: windowRect.origin, blendMode: .copy, alpha: 1)
            context.restoreGState()
            return true
        }
        switch clipped {
        case .success(let prepared): self.window = prepared
        case .failure(let error): failure = error; return
        }
        punchedImage = nil
        texturedImage = nil
        contentPresentation = nil
    }

    // MARK: - Commit

    /// **Writes the window into `texture` at its own origin — and this is BRUSH.md §2.11's merge.**
    /// The one place the three roles' arithmetic differs:
    ///
    /// - `.additive` composites this stroke's ink at the stroke's own opacity and blend mode. That
    ///   is the cap: the window already holds the sum of the dabs' flow, however often they crossed,
    ///   and one draw at `opacity` is what stops the crossing reaching further than the stroke may.
    /// - `.subtractive` punches the coverage out at the same opacity, which is the identical
    ///   statement for the eraser — see the type comment for why one punch of the sum is not the sum
    ///   of the punches.
    /// - `.replacing` is a display-only native geometry snapshot and has no raster commit.
    /// Prepare both undo pictures before the live tier changes. The final picture is drawn directly
    /// into owned storage; the live write is one admitted copy and cannot leave a half-stroke.
    func preparedPatch(over before: RasterSource, in rect: CGRect) -> Result<RasterSource, RasterResidency.Failure> {
        if case .failure(let error) = lastMutationResult { return .failure(error) }
        guard let contents = windowContents else { return .failure(failure ?? .unreadableBacking) }
        return before.resolveImage().flatMap { base in
            RasterSource.render(size: rect.size, using: residency) { _ in
                base.draw(at: .zero)
                let origin = CGPoint(x: windowRect.minX - rect.minX, y: windowRect.minY - rect.minY)
                switch role {
                case .additive: contents.draw(at: origin, blendMode: blendMode, alpha: opacity)
                case .subtractive: contents.draw(at: origin, blendMode: .destinationOut, alpha: opacity)
                case .replacing: return false
                }
                return true
            }
        }
    }

    @discardableResult
    func commit(into texture: RasterLayerTexture) -> Result<Void, RasterResidency.Failure> {
        if case .failure(let error) = lastMutationResult { return .failure(error) }
        if case .replacing = role { return .success(()) }
        guard !windowRect.isNull else { return .success(()) }
        if case .subtractive(let backdrop) = role, backdrop == nil, !texture.hasContent { return .success(()) }
        return texture.copiedPatch(in: windowRect).flatMap { before in
            guard let before else { return .success(()) }
            return preparedPatch(over: before, in: windowRect).flatMap { after in
                after.resolveImage().flatMap { texture.restore(patch: $0, at: windowRect.origin) }
            }
        }
    }

    // MARK: - The window

    /// The window enlarged if necessary to contain `rect`, or nil when `rect` lies entirely off the
    /// canvas — off-canvas pixels are storable nowhere and displayable nowhere, so a dab there is
    /// dropped rather than growing the box to reach it.
    private func window(containing rect: CGRect) -> RasterLayerTexture? {
        guard failure == nil else { return nil }
        if case .replacing = role { return nil }
        guard let next = nextWindowRect(containing: rect) else { return nil }
        if let window, next == windowRect { return window }
        let previous: UIImage?
        do { previous = try window?.renderToUIImage().get() }
        catch { failure = error; return nil }
        let prepared = RasterLayerTexture.rendered(size: next.size, canvasOrigin: next.origin, using: residency) { _ in
            previous?.draw(at: CGPoint(x: windowRect.minX - next.minX, y: windowRect.minY - next.minY),
                           blendMode: .copy, alpha: 1)
            return true
        }
        let grown: RasterLayerTexture
        switch prepared {
        case .success(let value): grown = value
        case .failure(let error): failure = error; return nil
        }
        carriedDirtyRect = dirtyRect
        windowRect = next
        window = grown
        punchedImage = nil
        texturedImage = nil
        contentPresentation = nil
        return grown
    }

    /// The existing geometric growth rule without allocating a raster surface. Native display-list
    /// replacements use this same admitted rectangle for their sole rendered image.
    private func nextWindowRect(containing rect: CGRect) -> CGRect? {
        guard failure == nil, !rect.isNull, !rect.isInfinite else { return nil }
        // Rounded the way `RasterLayerTexture` rounds its own size, so the window's pixel grid is
        // the cel's pixel grid: an integral origin is what makes a dab land on exactly the pixels it
        // would have landed on stamped straight into the cel, sub-pixel phase included.
        let canvas = CGRect(origin: .zero, size: CGSize(width: canvasSize.width.rounded(),
                                                        height: canvasSize.height.rounded()))
        // `rect` itself is never clamped — a dab pressed against the edge has a circle that pokes
        // past it — but `windowRect` always is (`next` below is `.intersection(canvas)`), and
        // nothing off-canvas is storable or displayable. So the containment test has to compare
        // against the part of `rect` that could ever land in the window, or a dab straddling any
        // edge would fail `contains` forever and rebuild on every single one of them.
        let onCanvas = rect.intersection(canvas)
        // Checked before the fast path rather than after: `CGRect.contains(.null)` is true, so a
        // dab that has drifted entirely off-canvas would otherwise pass containment against
        // whatever window already exists instead of being dropped.
        guard !onCanvas.isNull else { return nil }
        if !windowRect.isNull, windowRect.contains(onCanvas) { return windowRect }
        let wanted = windowRect.isNull ? rect : windowRect.union(rect)
        let held = windowRect.isNull ? CGSize.zero : windowRect.size
        let next = wanted.insetBy(dx: -Self.pad(held: held.width, wanted: wanted.width),
                                  dy: -Self.pad(held: held.height, wanted: wanted.height))
            .integral.intersection(canvas)
        guard next.width >= 1, next.height >= 1 else { return nil }
        return next
    }

    /// How far one axis is outset when the window is rebuilt. `held` is what that axis measures now
    /// (zero before the first dab), `wanted` what it has to measure to contain the union.
    ///
    /// **Zero for an axis the union did not exceed**, which is the whole difference between a band
    /// and a square: a horizontal stroke never leaves the window vertically, so its height is
    /// whatever the first dab set and stays there. Nothing is given up by that — the reallocation
    /// was forced by the *other* axis, that axis at least doubles, so the box's area at least
    /// doubles and the amortisation the class comment argues for is already paid.
    ///
    /// Half of `held` rather than of `wanted` when it does grow, so a fast pen that jumps far past
    /// the window in one batch gets its jump plus half the old box rather than half the new one —
    /// still at least a doubling of the axis, without paying for headroom the size of the leap.
    private static func pad(held: CGFloat, wanted: CGFloat) -> CGFloat {
        guard wanted > held else { return 0 }
        return max(minimumPad, held / 2)
    }

    private func renderedImage(size: CGSize, drawing: (CGContext) -> Bool) -> UIImage? {
        switch RasterSource.render(size: size, using: residency, drawing: drawing).flatMap({ $0.resolveImage() }) {
        case .success(let image): return image
        case .failure(let error): failure = error; return nil
        }
    }
}
