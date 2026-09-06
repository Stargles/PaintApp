import UIKit

/// Renders the live `FloatingPiece` as a PowerPoint/Keynote-style transform box — a dashed outline
/// you drag anywhere on to move, corner + edge handles to resize, and one rotate handle above the
/// top edge — rather than multi-touch gestures. Lives in `CanvasView`'s `container` above
/// `SelectionOverlayView`, so its coordinate space matches canvas points exactly (same placement and
/// handle-drag technique as the object-layer work's `ObjectTransformOverlayView`).
final class FloatingPieceOverlayView: TransformOverlayView, OffCanvasHandleHitTesting {
    /// **One callback carrying both halves of the pose**, not two — see
    /// `CanvasManager.updateFloatingPose(transform:distortQuad:)`. The quad is nil from every arm
    /// that does not distort, which is how "this gesture left the corners alone" is said.
    var onPoseChange: ((FloatingTransform, Quad?) -> Void)?
    var onRequestCommit: (() -> Void)?

    /// Mirrors `CanvasManager.pencilOnlyDrawing`, pushed down every `updateFloatingOverlay()` call —
    /// the same pattern `SelectionOverlayView.pencilOnlyDrawing`'s doc comment describes. TODO (47):
    /// the tap-outside commit below used to run unconditionally, on the theory that settling a float
    /// writes nothing so pencil-only mode had no stake in it. The owner's report is the eyedropper's
    /// exemption read the other way — committing ends the piece's adjustable state, and a resting
    /// hand mid-Move must not decide that for the artist.
    var pencilOnlyDrawing: Bool = false

    private var piece: FloatingPiece?

    private let pieceImageView = UIImageView()
    private let outlineView = UIView()
    private let outlineDashLayer = CAShapeLayer()
    private let corners: [TransformHandleView] = (0..<4).map { _ in TransformHandleView(kind: .scale, cornerRadius: 4) }
    private let edges: [TransformHandleView] = (0..<4).map { _ in TransformHandleView(kind: .scale, cornerRadius: 4) }
    private let rotateHandle = TransformHandleView(kind: .rotate)
    private let rotateLine = UIView()

    private var dragStartTransform: FloatingTransform = .identity
    private var dragStartTouch: CGPoint = .zero
    /// The Uniform/Freeform corner or edge drag in flight, latched at touch-down so the resize
    /// anchors on the opposite corner/edge instead of on the piece's centre. Nil for every other
    /// gesture, and nil for a corner drag in Distort — see `FloatingResizeDrag`.
    private var resizeDrag: FloatingResizeDrag?
    /// The Distort corner drag in flight, latched at touch-down. Nil for every other gesture, and
    /// nil for a corner drag in Uniform or Freeform — the mode is read once, at `.began`, so
    /// switching the picker under a finger already down cannot change what that finger means
    /// (`ObjectTransformDrag.isFreeform`'s own rule).
    private var distortDrag: FloatingDistortDrag?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true

        pieceImageView.isUserInteractionEnabled = false
        // The piece is the artist's own ink, lifted at canvas resolution, so it is minified onto the
        // screen like every other artwork view and loses thin lines the same way without a mipmap
        // chain — `LayerHostView.init` carries the measurement. Ink that vanishes while it is being
        // dragged and comes back on commit is the sharpest form of that defect.
        //
        // Only the minification half. This view carries the artist's own resize drag as a
        // `CGAffineTransform` on top of the container's zoom, so what it is magnified by is a
        // deliberate scale of the content rather than the zoom the layer hosts' `.nearest` contract
        // is written about — a question this line does not answer and does not need to.
        pieceImageView.layer.minificationFilter = .trilinear
        addSubview(pieceImageView)

        outlineView.backgroundColor = .clear
        outlineDashLayer.fillColor = UIColor.clear.cgColor
        outlineDashLayer.strokeColor = UIColor.white.cgColor
        outlineDashLayer.lineWidth = 1.5
        outlineDashLayer.lineDashPattern = [5, 4]
        outlineView.layer.addSublayer(outlineDashLayer)
        addSubview(outlineView)

        rotateLine.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        addSubview(rotateLine)

        for corner in corners { addSubview(corner) }
        for edge in edges { addSubview(edge) }
        addSubview(rotateHandle)

        let move = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        move.maximumNumberOfTouches = 1
        outlineView.addGestureRecognizer(move)

        for (index, corner) in corners.enumerated() {
            corner.tag = index
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleCornerPan(_:)))
            pan.maximumNumberOfTouches = 1
            corner.addGestureRecognizer(pan)
        }
        for (index, edge) in edges.enumerated() {
            edge.tag = index
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
            pan.maximumNumberOfTouches = 1
            edge.addGestureRecognizer(pan)
        }

        let rotate = UIPanGestureRecognizer(target: self, action: #selector(handleRotatePan(_:)))
        rotate.maximumNumberOfTouches = 1
        rotateHandle.addGestureRecognizer(rotate)

        // `TouchTypeTapGestureRecognizer`, not a plain `UITapGestureRecognizer` — see
        // `handleTapOutside` and `pencilOnlyDrawing`'s doc comment (TODO 47).
        let tap = TouchTypeTapGestureRecognizer(target: self, action: #selector(handleTapOutside(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// **`claimsTouch` is not asked and there is no `hitTest` override, so this is a total claim.**
    /// The view is pinned to the whole container, so the moment a piece is floating every touch
    /// inside the canvas is its — including the tap outside the piece that commits it.
    ///
    /// A lassoed *vector* piece reaches the same behaviour by a different route, because
    /// `ObjectTransformOverlayView` claims only its own grips: its tap-away rides a container
    /// recognizer instead (`CanvasView.Coordinator.handleMoveBoxCommit`, `CanvasTouchOwner`'s
    /// `.moveBoxCommit`). Until 2026-08-22 it had no tap-away commit at all, and that asymmetry was
    /// the whole of defect (j) — a touch away from a vector box did nothing and said nothing.
    ///
    /// `isInteractive` is handed in rather than derived from `newPiece` here: it is
    /// `CanvasTouchInputs.floatingOverlayIsInteractive`, one of the fourteen gates, and the whole
    /// point of the conversion is that a gate is read from the shared answer instead of spelled
    /// again wherever the view happens to be updated.
    func update(_ newPiece: FloatingPiece?, isInteractive: Bool) {
        piece = newPiece
        isHidden = newPiece == nil
        isUserInteractionEnabled = isInteractive
        guard newPiece != nil else { return }
        layoutFromPiece()
    }

    /// The grips, for a point outside the canvas rectangle that `CanvasContainerView` would
    /// otherwise never pass on — a box scaled larger than the document puts all four corners out
    /// there, and until 2026-09-06 none of them could be grabbed.
    ///
    /// **Only a grip, never this view itself**, which is the whole reason this is a separate entry
    /// point rather than a call to `hitTest`: `TransformOverlayView.point(inside:)` returns `true`
    /// unconditionally, so `hitTest` here answers *every* point with the overlay, and off the canvas
    /// that would hand the tap-away commit every touch on the black surround.
    ///
    /// Front to back over `subviews`, rather than over the three stored arrays, so the answer stays
    /// the z-order UIKit would have used if it had asked.
    func offCanvasHandle(at point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled else { return nil }
        // `!handle.isHidden` is load-bearing rather than defensive: `layoutFromPiece` hides the four
        // edge grips outside Freeform while leaving them positioned, so without it a Uniform box
        // would be single-axis-resizable off the canvas and nowhere else.
        for case let handle as TransformHandleView in subviews.reversed() where !handle.isHidden {
            if handle.point(inside: handle.convert(point, from: self), with: event) { return handle }
        }
        return nil
    }

    private func layoutFromPiece() {
        guard let piece else { return }
        // **`outlineDashLayer` is a bare `CAShapeLayer`, not a view's backing layer, so it gets no
        // automatic action suppression and `path`/`frame` are both animatable.** Set outside a
        // transaction they picked up Core Animation's default 0.25 s implicit animation while
        // `pieceImageView.layer.transform` — a backing layer, where UIKit returns a null action
        // outside an animation block — moved on the same frame the finger did. The artwork tracked
        // the drag and the dashes swam after it, worst under Distort where the path changes shape
        // on every delta rather than merely translating. `SelectionOverlayView` already does this
        // around its own ants layers and says why; nothing in this file did until now.
        //
        // Around the whole body rather than the two assignments: every layer this function touches
        // is being placed to match a pose that is already on screen, and none of it is ever meant to
        // animate.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        pieceImageView.image = piece.pieceImage
        let t = piece.transform
        let quad = piece.canvasQuad

        // **The whole of the live Distort preview, and it rasterizes nothing** — LASSO_MOVE.md §4
        // rule 2, which a re-warp per touch-move would break outright. A 2D homography *is* what a
        // `CATransform3D`'s `m14`/`m24` express, so the same matrix the bake warps through carries the
        // drag on the GPU for free; `Homography.catransform3D` owns the row-vector transposition that
        // makes it come out as foreshortening rather than as a shear.
        //
        // **Anchor point and position are zero and the bounds origin is zero**, which is what makes
        // the layer's whole layer-to-superlayer map that one matrix — the contract
        // `Homography.catransform3D`'s doc states. Both are put back on the affine arm below, so a
        // piece that stops being distorted (Reset) goes straight back to the `center`-based layout.
        if piece.distortQuad != nil, let homography = piece.homography {
            pieceImageView.transform = .identity
            pieceImageView.bounds = CGRect(origin: .zero, size: piece.baseSize)
            pieceImageView.layer.anchorPoint = .zero
            pieceImageView.layer.position = .zero
            pieceImageView.layer.transform = homography.catransform3D

            // **The outline stays an ordinary axis-aligned view, and that is a fix rather than a
            // simplification.** A projective `CATransform3D` draws correctly and **hit-tests
            // unreliably**: UIKit inverts a layer's transform to decide whether a touch is inside it,
            // and with `m14`/`m24` live that inversion stops answering. This view carries the move
            // band's pan recognizer, so putting the matrix on it silently took the band away the
            // moment a piece was distorted — the piece could be reshaped and then not dragged.
            // `DistortUITests` caught it; nothing in the model could have.
            //
            // So the band claims the quad's **bounding box** while the dashes are drawn along the
            // quad itself. The band over-claims at the corners by however much the quad is
            // foreshortened, which is bounded and benign: the four grips are later subviews and are
            // therefore hit first, so the only touches the difference changes are ones that would
            // otherwise have fallen through to the tap-away commit.
            let outline = quad.boundingBox
            outlineView.layer.transform = CATransform3DIdentity
            outlineView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            outlineView.transform = .identity
            outlineView.bounds = CGRect(origin: .zero, size: outline.size)
            outlineView.center = CGPoint(x: outline.midX, y: outline.midY)
            outlineDashLayer.frame = outlineView.bounds
            let path = CGMutablePath()
            path.addLines(between: quad.points.map {
                CGPoint(x: $0.x - outline.minX, y: $0.y - outline.minY)
            })
            path.closeSubpath()
            outlineDashLayer.path = path
        } else {
            let affine = CGAffineTransform.identity
                .rotated(by: t.rotation)
                .scaledBy(x: t.scaleX * (t.flipH ? -1 : 1), y: t.scaleY * (t.flipV ? -1 : 1))

            for view in [pieceImageView, outlineView] {
                view.layer.transform = CATransform3DIdentity
                view.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            }
            pieceImageView.bounds = CGRect(origin: .zero, size: piece.baseSize)
            pieceImageView.transform = affine
            pieceImageView.center = t.position

            outlineView.bounds = pieceImageView.bounds
            outlineView.transform = affine
            outlineView.center = t.position
            outlineDashLayer.frame = outlineView.bounds
            outlineDashLayer.path = CGPath(rect: outlineView.bounds, transform: nil)
        }

        let hw = piece.baseSize.width / 2, hh = piece.baseSize.height / 2
        let edgeLocal = [CGPoint(x: 0, y: -hh), CGPoint(x: hw, y: 0), CGPoint(x: 0, y: hh), CGPoint(x: -hw, y: 0)]

        // **The grips read `FloatingPiece.canvasQuad`, the same value the outline, the tap-away
        // bounds and the bake's warp read**, so a handle cannot sit anywhere but on the corner it
        // drags. For an undistorted piece this is the same four points `t.projected` gave, through
        // the same `affineTransform` `transformedBounds` has always used.
        for i in 0..<4 { corners[i].center = quad[i] }
        // Edge (single-axis) handles only make sense in Freeform — Uniform and Distort have no
        // single-axis gesture, the first because it scales both axes together and the second because
        // a corner already moves freely.
        let showEdgeHandles = piece.mode == .freeform && piece.distortQuad == nil
        for (i, local) in edgeLocal.enumerated() {
            edges[i].center = t.projected(local)
            edges[i].isHidden = !showEdgeHandles
        }

        // Midway along the quad's own top edge, so the knob stays over the edge it belongs to under
        // a foreshortening as well as under a rotation. `(p0 + p1) / 2` is `t.projected(0, -hh)`
        // exactly whenever the quad is the plain box, since an affine carries midpoints to midpoints.
        let topCenter = CGPoint(x: (quad.p0.x + quad.p1.x) / 2, y: (quad.p0.y + quad.p1.y) / 2)
        placeRotateHandle(rotateHandle, line: rotateLine, topCenter: topCenter, rotation: t.rotation)
    }

    // MARK: - Move (drag anywhere on the outline)

    @objc private func handleMovePan(_ recognizer: UIPanGestureRecognizer) {
        guard piece != nil else { return }
        switch recognizer.state {
        case .began:
            dragStartTransform = piece!.transform
        case .changed:
            let translation = recognizer.translation(in: self)
            var updated = dragStartTransform
            updated.position = CGPoint(x: dragStartTransform.position.x + translation.x, y: dragStartTransform.position.y + translation.y)
            apply(updated)
        default:
            break
        }
    }

    // MARK: - Rotate handle

    @objc private func handleRotatePan(_ recognizer: UIPanGestureRecognizer) {
        guard let piece else { return }
        switch recognizer.state {
        case .began:
            dragStartTransform = piece.transform
            dragStartTouch = recognizer.location(in: self)
        case .changed:
            let center = dragStartTransform.position
            let startAngle = atan2(dragStartTouch.y - center.y, dragStartTouch.x - center.x)
            let current = recognizer.location(in: self)
            let currentAngle = atan2(current.y - center.y, current.x - center.x)
            var updated = dragStartTransform
            updated.rotation = dragStartTransform.rotation + (currentAngle - startAngle)
            apply(updated)
        default:
            break
        }
    }

    // MARK: - Corner / edge resize (anchor-preserving: the opposite corner/edge stays put)

    @objc private func handleCornerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let piece, let handle = recognizer.view else { return }
        let index = handle.tag // 0=TL, 1=TR, 2=BR, 3=BL
        switch recognizer.state {
        case .began:
            dragStartTransform = piece.transform
            // Latched at touch-down with everything else on this gesture, so flipping the Move bar's
            // picker mid-drag cannot change what the finger already down means.
            distortDrag = piece.mode == .distort ? FloatingDistortDrag(piece: piece, corner: index) : nil
            // **The anchor is the *quad's* opposite corner, not the box's** — see
            // `FloatingResizeDrag`, which is where the whole of this arm's arithmetic now lives and
            // where the reduction to the old box expression is pinned. Latching the box corner is
            // what made a distorted piece jump the instant a Uniform or Freeform corner drag began,
            // because the grip the finger was on is drawn from `canvasQuad` in every mode and
            // `distortQuad` outlives a mode switch.
            resizeDrag = FloatingResizeDrag(piece: piece, corner: index)
        case .changed:
            if let distortDrag {
                // A delta that would make an undrawable quad is refused rather than clamped, so the
                // handle sticks and the piece stays exactly where the last valid one put it.
                guard let quad = distortDrag.quad(draggedTo: recognizer.location(in: self)) else { return }
                apply(dragStartTransform, distortQuad: quad)
                return
            }
            guard let resizeDrag else { return }
            apply(resizeDrag.transform(draggedTo: recognizer.location(in: self)))
        default:
            distortDrag = nil
            resizeDrag = nil
        }
    }

    @objc private func handleEdgePan(_ recognizer: UIPanGestureRecognizer) {
        // The same condition `layoutFromPiece`'s `showEdgeHandles` uses, so a hidden grip cannot be
        // dragged: a distorted box's edges have no single axis for this arm to move along.
        guard let piece, piece.mode == .freeform, piece.distortQuad == nil,
              let handle = recognizer.view else { return }
        let index = handle.tag // 0=top, 1=right, 2=bottom, 3=left
        switch recognizer.state {
        case .began:
            dragStartTransform = piece.transform
            resizeDrag = FloatingResizeDrag(piece: piece, edge: index)
        case .changed:
            guard let resizeDrag else { return }
            apply(resizeDrag.transform(draggedTo: recognizer.location(in: self)))
        default:
            resizeDrag = nil
        }
    }

    // MARK: - Commit (tap outside the box)

    /// **Gated on pencil-only drawing since TODO (47)** — owner: *"when you are moving an object with
    /// pen only draw on and then tap somewhere else on the canvas with your hand, it bakes the
    /// move... it should only do that when the pen is tapped."* Read straight off
    /// `recognizer.lastTouchType`, ahead of the bounds check: a finger elsewhere on the canvas must do
    /// whatever a finger does outside a Move (nothing, here — the piece stays exactly as adjustable as
    /// it was), not commit.
    @objc private func handleTapOutside(_ recognizer: TouchTypeTapGestureRecognizer) {
        guard let piece else { return }
        guard !pencilOnlyDrawing || recognizer.lastTouchType == .pencil else { return }
        let location = recognizer.location(in: self)
        if !piece.transformedBounds.insetBy(dx: -8, dy: -8).contains(location) {
            onRequestCommit?()
        }
    }

    /// **The one funnel every arm writes through**, so no gesture can update the model and the layout
    /// out of step. The affine arms — move, rotate, corner scale, edge scale — never name
    /// `distortQuad`, and carry whatever the piece already had; only the Distort corner passes one.
    ///
    /// No arm *clears* it, which is why the parameter is a plain `Quad?` rather than a
    /// distinguish-nil-from-absent double optional: Reset is the only thing that takes a distort
    /// back, and it does so on the model (`CanvasManager.resetFloating`) where it belongs beside the
    /// transform it is putting back at the same time.
    private func apply(_ updated: FloatingTransform, distortQuad: Quad? = nil) {
        let quad = distortQuad ?? piece?.distortQuad
        piece?.transform = updated
        piece?.distortQuad = quad
        layoutFromPiece()
        onPoseChange?(updated, quad)
    }
}
