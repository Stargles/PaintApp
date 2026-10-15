import UIKit

/// **The ink that is on screen but is not in the layer's installed base**, as a value.
///
/// One invariant, and the whole of this type is holding it:
///
/// > *The pictures shown above the base are exactly the ink the installed base does not contain.*
///
/// **The defect it closes** ([BUGS.md](BUGS.md), 2026-09-04, "Starting a stroke before the last one
/// has rendered leaves the last one off screen"). RENDER.md §2.13 moved the pen-up rasterize off the
/// main thread, so between a stroke committing and its render landing the base slot holds a picture
/// the stroke is *not* in, and the stroke's own live scratch stands in for it. That worked for one
/// stroke and could not work for two: there is a single `scratchView`, so beginning stroke *n+1*
/// put its pixels where stroke *n*'s were and **stroke *n* was on screen nowhere at all** — not in
/// the base, which predates it, and not in the overlay, which the new stroke had taken. The artist
/// watched a finished stroke vanish and come back.
///
/// The fix is to stop conflating the two meanings the overlay had. *"The stroke under the pen"* is
/// one thing and *"ink the base does not have yet"* is another; the live scratch is the first, this
/// is the second, and a stroke moves from one to the other at pen-up.
///
/// **It allocates no pixels.** A held picture is the `UIImage` the live scratch was already showing
/// or the frozen `IOSurface` a held edit was already presenting
/// — windowed to the stroke's own box (`StrokeScratch`), never canvas-sized — so holding it retains
/// a bitmap that existed a moment ago and would otherwise have been released. It is in fact *less*
/// than the shipped code held: that kept the whole `StrokeScratch`, including its
/// `RasterLayerTexture` window and both of its memoized composites, until the render landed.
///
/// **And it is bounded by pen travel rather than by canvas area.** A picture is held from its
/// stroke's pen-up until a base containing it is installed — one render, MEASURED at 14.4 ms on
/// Test1 at 4096² and 27.3 ms at 6000² (`StrokeHandoffBench`) — so the set holds the strokes an
/// artist finished inside one render. A stroke's window is proportional to its own length and a long
/// stroke takes long enough to draw that its render lands first, which is why the sum does not grow
/// with the canvas: it grows with how far a pen can travel in one render, and that is the same few
/// hundred points at 512² as at 6000².
///
/// **Why a value type in `Views/` rather than state inside the view.** `StrokeCanvasView.swift` is
/// not a member of the UI-test target — it drags in `StrokeGestureRecognizer` and the rest of the
/// touch stack — so nothing nested inside it can be asserted headlessly, which is exactly why this
/// defect went two months without a test. `VectorPreviewPlan` and `DeferredVectorRender` are the two
/// existing members of that family and this is the third; the view holds one of these and obeys it.
struct UnlandedInk {

    /// One finished stroke's picture, exactly as the live scratch was showing it a moment before.
    ///
    /// The three display fields are the same three `StrokeCanvasView.showOverlays` reads off a live
    /// `StrokeScratch`, and they are copied rather than referenced for one reason: the scratch is
    /// released at pen-up now, so the picture has to outlive it.
    struct Picture {
        /// Identity, monotonic per view. Present so a test can say *which* picture without
        /// comparing bitmaps, and so the view can tell "the same held set" from "a set that happens
        /// to be the same length" when it decides whether to rebuild its layers.
        let id: Int
        /// **The `VectorCanvas.version` this ink is in.** A base rasterized at this version or later
        /// contains it, which is the whole of `retire(upTo:)`.
        let version: Int
        /// Where the picture goes, in canvas points — `StrokeScratch.windowRect`.
        let windowRect: CGRect
        /// What the picture is shown at — `StrokeScratch`'s own display alpha, which is the stroke's
        /// opacity for `.additive` and 1 for the two roles that have already applied it inside their
        /// pixels. BRUSH.md §2.11's cap, on the display side.
        let alpha: CGFloat
        /// Whether the picture *stands in for* the base inside its window rather than sitting over
        /// it — a vector eraser or an element edit. The base is punched out underneath, exactly as it
        /// is for a live one.
        enum Mode {
            case additive
            case localReplacement
            case celContent(CGPath)
        }
        let mode: Mode
        var replacesBase: Bool {
            if case .additive = mode { return false }
            return true
        }
        enum Contents {
            case image(UIImage)
            case surface(WindowSurfaceView.FrozenWindow)

            /// Preserve UIImage's scale/orientation handling for strokes, while a frozen window
            /// hands its existing surface straight to Core Animation. Neither arm copies pixels.
            func makeView() -> UIView {
                let view: UIView
                switch self {
                case .image(let image): view = UIImageView(image: image)
                case .surface(let frozen):
                    view = UIView()
                    view.layer.contents = frozen.surface
                    view.layer.contentsScale = 1
                    view.layer.contentsGravity = .resize
                }
                view.layer.magnificationFilter = .nearest
                view.layer.minificationFilter = .trilinear
                return view
            }
        }
        let contents: Contents

        init(id: Int, version: Int, windowRect: CGRect, alpha: CGFloat,
             replacesBase: Bool, contents: Contents) {
            self.id = id
            self.version = version
            self.windowRect = windowRect
            self.alpha = alpha
            self.mode = replacesBase ? .localReplacement : .additive
            self.contents = contents
        }

        init(id: Int, version: Int, windowRect: CGRect, replacing footprint: CGPath, contents: Contents) {
            self.id = id
            self.version = version
            self.windowRect = windowRect
            self.alpha = 1
            self.mode = .celContent(footprint)
            self.contents = contents
        }

        func footprint(placement: CelContentPlacement) -> CGPath {
            if case .celContent(let path) = mode { return path }
            let local = CGPath(rect: windowRect, transform: nil)
            return placement.ink?.mapped(local) ?? local
        }

        /// The wrapper has no pixel storage. Its mask lives in the common shown space, while old
        /// additive/eraser textures keep the same origin-anchored local pose they have always used.
        func makeCanvasView(size: CGSize, placement: CelContentPlacement) -> UIView {
            let wrapper = UIView(frame: CGRect(origin: .zero, size: size))
            let image = contents.makeView()
            image.frame = windowRect
            image.contentMode = .scaleToFill
            image.isUserInteractionEnabled = false
            if case .celContent = mode { wrapper.addSubview(image) }
            else {
                let local = UIView(frame: wrapper.bounds)
                local.layer.anchorPoint = .zero
                local.layer.position = .zero
                local.layer.transform = placement.ink?.layerTransform ?? CATransform3DIdentity
                local.addSubview(image)
                wrapper.addSubview(local)
            }
            wrapper.alpha = alpha
            wrapper.isUserInteractionEnabled = false
            return wrapper
        }

        init(id: Int, version: Int, windowRect: CGRect, alpha: CGFloat,
             replacesBase: Bool, image: UIImage) {
            self.init(id: id, version: version, windowRect: windowRect, alpha: alpha,
                      replacesBase: replacesBase, contents: .image(image))
        }
    }

    /// **In commit order, which is z-order.** Source-over of finished strokes in the order they were
    /// made is precisely what `VectorCanvas.renderLocalContent` does to a run of `.normal` paint
    /// strokes — each stroke flattened at its own opacity, then composited — so the screen and the
    /// base that replaces it are the same arithmetic rather than an approximation of it.
    private(set) var pictures: [Picture] = []

    var isEmpty: Bool { pictures.isEmpty }

    /// A held picture's visible part after newer replacements have covered it. A replacement's
    /// transparent pixels still remove earlier ink, so ordinary source-over stacking is not enough.
    struct VisiblePicture {
        let picture: Picture
        /// In canvas-local points; nil means the entire window remains visible.
        let clip: CGPath?

        func applyClip(to view: UIView) {
            guard let clip else {
                if view.layer.mask != nil { view.layer.mask = nil }
                return
            }
            var local = CGAffineTransform(translationX: -view.frame.minX,
                                          y: -view.frame.minY)
            let mask = (view.layer.mask as? CAShapeLayer) ?? {
                let created = CAShapeLayer()
                created.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
                view.layer.mask = created
                return created
            }()
            mask.frame = view.bounds
            mask.path = clip.copy(using: &local)
        }
    }

    struct DisplayPlan {
        let pictures: [VisiblePicture]
        /// A geometric union: overlapping replacement windows never cancel each other's hole.
        let baseHole: CGPath?
    }

    /// Walk newest to oldest, cutting every earlier picture under each newer replacement. The
    /// Core Graphics booleans are shared with selection composition; no pixel buffers are made.
    /// `covering` contains newer live replacement windows, which also cover held pictures.
    func displayPlan(covering: [CGRect] = []) -> DisplayPlan {
        displayPlan(placement: .identity, coveringPaths: covering.map { CGPath(rect: $0, transform: nil) })
    }

    func displayPlan(placement: CelContentPlacement, coveringPaths: [CGPath]) -> DisplayPlan {
        var covered: CGPath?
        func cover(_ path: CGPath) {
            guard !path.isEmpty else { return }
            covered = covered.map { $0.union(path, using: .winding) } ?? path
        }
        for path in coveringPaths { cover(path) }
        var visible: [VisiblePicture] = []
        for picture in pictures.reversed() {
            let footprint = picture.footprint(placement: placement)
            let clip: CGPath?
            if let covered, footprint.boundingBoxOfPath.intersects(covered.boundingBoxOfPath) {
                clip = footprint.subtracting(covered, using: .winding)
            } else { clip = nil }
            visible.append(VisiblePicture(picture: picture, clip: clip))
            if picture.replacesBase { cover(footprint) }
        }
        return DisplayPlan(pictures: visible.reversed(), baseHole: covered)
    }

    /// Every finished window survives until a base containing it lands. In particular, a second
    /// replacement can be disjoint from the first; retaining only the newer one loses visible ink.
    mutating func hold(_ picture: Picture) {
        pictures.append(picture)
    }

    /// **A base rasterized at `version` has been installed, so everything it contains stops being
    /// un-landed.** `<=` rather than `==`: renders are dispatched per commit onto one serial queue
    /// and a later one is a superset, so a base can arrive that covers several held pictures at once
    /// — which is exactly what happens when an artist finishes two strokes inside one render.
    mutating func retire(upTo version: Int) {
        pictures.removeAll { $0.version <= version }
    }

    /// **Nothing held is about this canvas any more.** Five callers, and each is a case where the
    /// base slot stops being a picture of the same list: the view is handed a different
    /// `VectorCanvas` (a layer, cel or frame change), the base becomes a derived in-between frame,
    /// the composite takes over drawing this layer, an eraser's synchronous touch-down render has
    /// just made the base current, or a lasso move latches its float over the whole layer.
    mutating func removeAll() {
        pictures.removeAll()
    }
}
