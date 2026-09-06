import UIKit

/// On-canvas marching-ants rendering for the current `Selection`, plus gesture capture for creating
/// a new one. Lives inside `CanvasView`'s transformed `container`, so its own coordinate space
/// matches canvas points exactly (same placement pattern as the object-layer work's
/// `ObjectTransformOverlayView`).
final class SelectionOverlayView: UIView {
    var onFinishPath: ((CGPath) -> Void)?
    var onAutomaticTap: ((CGPoint) -> Void)?

    var mode: SelectionMode = .lasso

    /// Whether this view should currently intercept touches to create a selection — true only while
    /// the Select tool is active and nothing is floating (a pending move/duplicate takes priority).
    var isCapturingGestures: Bool = false {
        didSet { isUserInteractionEnabled = isCapturingGestures }
    }

    /// Mirrors `CanvasManager.pencilOnlyDrawing`, pushed down every `updateSelectionOverlay()` call
    /// the same way `reconcileLayers` mirrors it to `StrokeCanvasView.pencilOnlyDrawing`. Selection
    /// is a drawing-type edit under the "would this input have drawn" test in `CanvasView`'s gesture
    /// doc comment — it replaces what a later fill/paint sees as paintable — so a finger must be
    /// rejected here exactly as it is for a stroke, but `handlePan`/`handleTap` are stock recognizer
    /// actions that never see a `UITouch` to ask; see `TouchTypePanGestureRecognizer` below.
    var pencilOnlyDrawing: Bool = false

    /// A solid blue shadow directly under `antsLayer`'s white dashes: the blue shows through the gaps,
    /// giving a white & blue dotted line readable against both light and dark canvas content.
    private let antsShadowLayer = CAShapeLayer()
    private let antsLayer = CAShapeLayer()
    /// Solid blue shadow beneath the live lasso/rectangle preview — same white-on-blue technique
    /// so the in-progress outline is visible against the white canvas background.
    private let liveShadowLayer = CAShapeLayer()
    private let liveLayer = CAShapeLayer() // in-progress lasso/rectangle preview, while dragging
    /// Diagonal-stripe fill covering everything *outside* the current selection (even-odd: full view
    /// bounds minus the selection path), matching Procreate's "outside the selection is off-limits"
    /// treatment. Shown only while a selection exists and outside interaction is denied — see
    /// `updateSelection`.
    private let hatchLayer = CAShapeLayer()

    /// LASSO_FILL.md §7.2's collar tint: the reached set of a lasso fill that enclosed nothing, drawn
    /// registered to the artwork. Contents are a canvas-resolution image and this view's bounds *are*
    /// the canvas (`CanvasView` sets `container.bounds` to `canvasSize`), so it maps one to one.
    private let collarLayer = CALayer()
    /// §7.4's redraw of the loop, in the same white-on-blue dashes the artist watched themselves
    /// draw. Separate layers from `liveLayer`/`liveShadowLayer` rather than a reuse of them, because
    /// these fade out under an animation and the live pair must be instantly usable by the next
    /// gesture — a loop drawn during the fade would otherwise inherit an opacity on its way to zero.
    private let diagnosticLoopShadowLayer = CAShapeLayer()
    private let diagnosticLoopLayer = CAShapeLayer()
    /// The diagnostic currently on screen, so a repeated `updateSelectionOverlay` pass — there are
    /// many, and most change nothing — does not restart the fade from the top every time.
    private var shownDiagnosticID: UUID?

    private var lassoPoints: [CGPoint] = []
    private var rectStart: CGPoint?
    private var currentSelectionPath: CGPath?
    private var hatchIsEnabled: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        hatchLayer.fillColor = Self.makeHatchPattern().cgColor
        hatchLayer.fillRule = .evenOdd
        hatchLayer.isHidden = true
        layer.addSublayer(hatchLayer)

        // Under the marching ants and under the live preview: the tint is a wash over the artwork,
        // and an outline drawn on top of it stays readable where one drawn under it would not.
        collarLayer.isHidden = true
        collarLayer.opacity = 0
        // Nearest-neighbour so a zoomed-in canvas shows the collar's actual pixel boundary. The
        // artist is being asked to find a gap in their line; a bilinear smear over the very pixels
        // they are hunting for would defeat the whole point of showing it.
        collarLayer.magnificationFilter = .nearest
        collarLayer.minificationFilter = .nearest
        layer.addSublayer(collarLayer)

        antsShadowLayer.fillColor = UIColor.clear.cgColor
        antsShadowLayer.strokeColor = UIColor.systemBlue.cgColor
        antsShadowLayer.lineWidth = 2.5
        antsShadowLayer.isHidden = true
        layer.addSublayer(antsShadowLayer)

        antsLayer.fillColor = UIColor.clear.cgColor
        antsLayer.strokeColor = UIColor.white.cgColor
        antsLayer.lineWidth = 1.5
        antsLayer.lineDashPattern = [6, 4]
        antsLayer.isHidden = true
        layer.addSublayer(antsLayer)

        liveShadowLayer.fillColor = UIColor.clear.cgColor
        liveShadowLayer.strokeColor = UIColor.systemBlue.cgColor
        liveShadowLayer.lineWidth = 2.5
        // No `isHidden` here, unlike `antsShadowLayer`/`antsLayer` above: those sit under an
        // optional *committed* selection and need a flag because a nil path there means "no
        // selection yet" and "selection just got cleared" alike. This pair's path is only ever nil
        // between gestures (handlePan's `.ended`/default cases null it), and a `CAShapeLayer` with
        // `path == nil` already draws nothing — so `path` alone is the single source of truth for
        // visibility. A previous version hid this layer unconditionally at init and never un-hid it,
        // which left only `liveLayer`'s 1.5pt white dash visible while dragging: invisible over white
        // paper and the wrong colour over line art. Do not reintroduce an `isHidden` toggle in
        // `handleLassoPan`/`handleRectanglePan` — that would be a second mechanism racing the path
        // assignment to control the same thing.
        layer.addSublayer(liveShadowLayer)

        liveLayer.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
        liveLayer.strokeColor = UIColor.white.cgColor
        liveLayer.lineWidth = 1.5
        liveLayer.lineDashPattern = [6, 4]
        layer.addSublayer(liveLayer)

        // Styled exactly as the live preview, because it *is* the live preview brought back: §7.4
        // asks the artist to compare the fence they drew with the fence they thought they drew, and a
        // second visual vocabulary for the same curve would be a third thing to interpret. No dash
        // animation on these — a marching outline reads as "still working", which it is not.
        diagnosticLoopShadowLayer.fillColor = UIColor.clear.cgColor
        diagnosticLoopShadowLayer.strokeColor = UIColor.systemBlue.cgColor
        diagnosticLoopShadowLayer.lineWidth = 2.5
        diagnosticLoopShadowLayer.opacity = 0
        diagnosticLoopShadowLayer.isHidden = true
        layer.addSublayer(diagnosticLoopShadowLayer)

        diagnosticLoopLayer.fillColor = UIColor.clear.cgColor
        diagnosticLoopLayer.strokeColor = UIColor.white.cgColor
        diagnosticLoopLayer.lineWidth = 1.5
        diagnosticLoopLayer.lineDashPattern = [6, 4]
        diagnosticLoopLayer.opacity = 0
        diagnosticLoopLayer.isHidden = true
        layer.addSublayer(diagnosticLoopLayer)

        let pan = TouchTypePanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let tap = TouchTypeTapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        // Shared by `antsLayer` (the committed selection) and `liveLayer` (the in-progress preview),
        // so the outline marches identically whether the artist is still dragging or has lifted the
        // pen. `CABasicAnimation` conforms to `NSCopying` and `CALayer.add(_:forKey:)` copies what it
        // is given, so adding the one instance to two layers is safe — each layer owns its own copy
        // and they free-run independently (their phases can drift apart over a long drag, which is
        // invisible at 0.6s/cycle and not worth synchronising).
        //
        // Added here, at init, exactly once — NEVER from inside `handleLassoPan`/`handleRectanglePan`.
        // Those run on every `.changed` event of an active gesture, and `add(_:forKey:)` restarts the
        // animation from `fromValue` each time it's called for a given key; re-adding per-event resets
        // the phase every touch move, so under a fast stylus the dashes stutter or appear frozen
        // instead of marching. Set the path in the gesture handlers; leave the animation alone.
        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = 0
        animation.toValue = 10
        animation.duration = 0.6
        animation.repeatCount = .infinity
        antsLayer.add(animation, forKey: "marchingAnts")
        liveLayer.add(animation, forKey: "marchingAnts")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshHatchPath() // the "outside" rect tracks the view's own bounds, which can change on rotation/resize
        // Same reason, and the collar is the one layer here with a frame rather than a path: its
        // contents are the canvas, so its frame has to stay the canvas. Inside a `CATransaction` with
        // actions off, or a resize mid-fade animates the frame as well as the opacity.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collarLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: - The empty lasso fill's diagnostic (LASSO_FILL.md §7.2, §7.4)

    /// Shows `diagnostic` — the tinted collar and the loop that produced it — held at full strength
    /// and then faded out over `LassoFillDiagnostic.duration`. Nil takes whatever is up straight back
    /// off; a diagnostic already on screen is left to finish its fade rather than restarted.
    ///
    /// **The view owns the timing**, exactly as `DrawingView` owns the notice banner's: how long a
    /// transient stays up is a presentation decision, and driving it from Core Animation rather than
    /// from a model timer means a fade cannot be left half-finished by a state change elsewhere.
    ///
    /// The fade holds first and then falls (`holdFraction`), rather than easing out from frame one:
    /// the artist's eye has to arrive at the canvas before the picture is worth anything, and a
    /// linear fade spends its most legible moment on a screen nobody is looking at yet.
    func showLassoDiagnostic(_ diagnostic: LassoFillDiagnostic?) {
        guard let diagnostic else {
            if shownDiagnosticID != nil { clearLassoDiagnostic() }
            return
        }
        guard diagnostic.id != shownDiagnosticID else { return }
        shownDiagnosticID = diagnostic.id

        let duration = LassoFillDiagnostic.duration
        let hold = NSNumber(value: LassoFillDiagnostic.holdFraction)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collarLayer.frame = bounds
        collarLayer.contents = diagnostic.collar?.cgImage
        collarLayer.isHidden = diagnostic.collar == nil
        diagnosticLoopShadowLayer.path = diagnostic.loop
        diagnosticLoopLayer.path = diagnostic.loop
        diagnosticLoopShadowLayer.isHidden = false
        diagnosticLoopLayer.isHidden = false
        // The model value is the *end* state, so when the animation finishes the presentation already
        // matches it — no `fillMode = .forwards` and no removal flicker to reason about.
        collarLayer.opacity = 0
        diagnosticLoopShadowLayer.opacity = 0
        diagnosticLoopLayer.opacity = 0
        CATransaction.commit()

        for target in [collarLayer, diagnosticLoopShadowLayer, diagnosticLoopLayer] {
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, hold, 1]
            fade.duration = duration
            fade.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeIn)]
            target.add(fade, forKey: "lassoDiagnosticFade")
        }

        // Releases the canvas-sized image once it is invisible. Guarded on the id so a *newer*
        // diagnostic raised inside the window is not torn down by the older one's deadline — the same
        // stale-timer trap `DrawingView`'s `.task(id:)` avoids for the banner.
        let id = diagnostic.id
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.shownDiagnosticID == id else { return }
            self.clearLassoDiagnostic()
        }
    }

    private func clearLassoDiagnostic() {
        shownDiagnosticID = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for target in [collarLayer, diagnosticLoopShadowLayer, diagnosticLoopLayer] {
            target.removeAnimation(forKey: "lassoDiagnosticFade")
            target.opacity = 0
            target.isHidden = true
        }
        collarLayer.contents = nil
        diagnosticLoopShadowLayer.path = nil
        diagnosticLoopLayer.path = nil
        CATransaction.commit()
    }

    /// - Parameter allowsOutsideInteraction: when false (the default "deny" state) and a selection
    ///   exists, the exterior hatch is shown to signal that painting/erasing/filling outside the
    ///   selection is blocked; when true, the hatch is hidden since nothing outside is actually
    ///   restricted.
    func updateSelection(_ selection: Selection?, allowsOutsideInteraction: Bool) {
        currentSelectionPath = selection?.path
        antsShadowLayer.isHidden = selection == nil
        antsLayer.isHidden = selection == nil
        refreshAntsPath()
        hatchIsEnabled = selection != nil && !allowsOutsideInteraction
        refreshHatchPath()
    }

    /// The live projective warp, or nil while the map is affine — see `refreshAntsPath`.
    private var liveWarp: Homography?

    /// The path in the two ants layers: the selection's own, or its image under `liveWarp`.
    ///
    /// **Only the projective case pays this.** An affine map rides the layers' own transform for
    /// free and this leaves the stored path alone, which is what the two-case
    /// `FloatingPiece.antsMap` is for.
    private func refreshAntsPath() {
        let path = liveWarp.flatMap { warp in currentSelectionPath.flatMap { warp.mapped($0) } }
            ?? currentSelectionPath
        antsShadowLayer.path = path
        antsLayer.path = path
    }

    /// **The ants travel with a floating piece** (LASSO_MOVE.md §5.6 and its prior art: Photoshop and
    /// Illustrator both move the outline with the content), and this is how they do it while the
    /// finger is still down.
    ///
    /// A drag writes nothing to the model — that is the whole design of the float — so writing a
    /// moved `selection.path` per touch-move would put a `@Published` change, and therefore a whole
    /// SwiftUI pass, on every delta of a gesture built specifically not to have one. Two `CALayer`
    /// transforms cost nothing and land on the same frame the piece does. At the gesture's end the
    /// model catches up with the real path and this goes back to the identity, so the value on screen
    /// and the value in the document are the same thing at every rest state.
    ///
    /// The exterior hatch is hidden rather than transformed: it is "the view's bounds minus the
    /// selection", so moving it would drag its own outer edge into the canvas and leave an unhatched
    /// margin. It comes back, correct, when the moved path is written.
    /// **A distorted raster piece takes the `.warped` arm**, where there is no layer transform to
    /// ride: the path itself is re-mapped (`Homography.mapped`) and the layers are left at the
    /// identity. That arm cannot be an affine, which is the whole reason `antsMap` has two cases —
    /// see it for what the ants used to do instead.
    func setLiveSelectionTransform(_ map: FloatingAntsMap) {
        var isIdentity = false
        var warp: Homography?
        var affine = CGAffineTransform.identity
        switch map {
        case .affine(let transform):
            affine = transform
            isIdentity = transform.isIdentity
        case .warped(let homography):
            warp = homography
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if liveWarp != warp {
            liveWarp = warp
            refreshAntsPath()
        }
        antsLayer.setAffineTransform(affine)
        antsShadowLayer.setAffineTransform(affine)
        hatchLayer.isHidden = !isIdentity || !hatchIsEnabled || hatchLayer.path == nil
        CATransaction.commit()
    }

    private func refreshHatchPath() {
        guard hatchIsEnabled, let selectionPath = currentSelectionPath, bounds.width > 0, bounds.height > 0 else {
            hatchLayer.isHidden = true
            return
        }
        let combined = CGMutablePath()
        combined.addRect(bounds)
        combined.addPath(selectionPath)
        hatchLayer.path = combined
        hatchLayer.isHidden = false
    }

    /// A small tile with one diagonal line, tiled via `UIColor(patternImage:)`: because each tile's
    /// line connects seamlessly with its neighbors' (a single line at slope -1 per tile repeats into a
    /// continuous 45° hatch), this produces the full diagonal-stripe fill without hand-tiling a wider
    /// image.
    private static func makeHatchPattern() -> UIColor {
        let tile: CGFloat = 14
        let format = PixelOps.transparentFormat(scale: UIScreen.main.scale)
        let image = UIGraphicsImageRenderer(size: CGSize(width: tile, height: tile), format: format).image { ctx in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -2, y: tile + 2))
            path.addLine(to: CGPoint(x: tile + 2, y: -2))
            path.lineWidth = 1.5
            UIColor.black.withAlphaComponent(0.22).setStroke()
            path.stroke()
        }
        return UIColor(patternImage: image)
    }

    @objc private func handlePan(_ recognizer: TouchTypePanGestureRecognizer) {
        guard isCapturingGestures else { return }
        guard !pencilOnlyDrawing || recognizer.lastTouchType == .pencil else { return }
        switch mode {
        case .lasso: handleLassoPan(recognizer)
        case .rectangle: handleRectanglePan(recognizer)
        case .automatic: break // automatic selection is a tap, not a drag
        }
    }

    private func handleLassoPan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            lassoPoints = [location]
        case .changed:
            lassoPoints.append(location)
            let path = CGMutablePath()
            path.addLines(between: lassoPoints)
            // Actions disabled, same reason and same fix as `ShapeOverlayView.update`
            // (ShapeOverlayView.swift:218-222) and `GuideOverlayView.redraw`
            // (GuideOverlayView.swift:155-158): this runs on every touch-moved event of an active
            // drag, and without disabling implicit animations each `path` assignment picks up
            // CALayer's default ~0.25s animation, so the preview visibly lags behind the stylus
            // instead of tracking it.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            liveShadowLayer.path = path
            liveLayer.path = path
            CATransaction.commit()
        case .ended:
            lassoPoints.append(location)
            defer { lassoPoints = []; liveShadowLayer.path = nil; liveLayer.path = nil }
            guard lassoPoints.count > 2 else { return }
            let path = CGMutablePath()
            path.addLines(between: lassoPoints)
            path.closeSubpath()
            onFinishPath?(path)
        default:
            lassoPoints = []
            liveShadowLayer.path = nil
            liveLayer.path = nil
        }
    }

    private func handleRectanglePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            rectStart = location
        case .changed:
            guard let start = rectStart else { return }
            let path = CGPath(rect: rect(from: start, to: location), transform: nil)
            liveShadowLayer.path = path
            liveLayer.path = path
        case .ended:
            defer { rectStart = nil; liveShadowLayer.path = nil; liveLayer.path = nil }
            guard let start = rectStart else { return }
            let rect = rect(from: start, to: location)
            guard rect.width > 2, rect.height > 2 else { return }
            onFinishPath?(CGPath(rect: rect, transform: nil))
        default:
            rectStart = nil
            liveShadowLayer.path = nil
            liveLayer.path = nil
        }
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    @objc private func handleTap(_ recognizer: TouchTypeTapGestureRecognizer) {
        guard isCapturingGestures, mode == .automatic else { return }
        guard !pencilOnlyDrawing || recognizer.lastTouchType == .pencil else { return }
        onAutomaticTap?(recognizer.location(in: self))
    }
}

// `TouchTypePanGestureRecognizer` and `TouchTypeTapGestureRecognizer` moved to
// `TouchTypeResolution.swift` (TODO 47): `FloatingPieceOverlayView` needed the tap recognizer too,
// and that file — not this one — is the app source already shared into `PaintSoftwareUITests`'s
// compilation for exactly this reason. See its doc comment.
