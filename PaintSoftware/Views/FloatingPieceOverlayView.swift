import UIKit

/// Renders the live `FloatingPiece` as a PowerPoint/Keynote-style transform box — a dashed outline
/// you drag anywhere on to move, corner + edge handles to resize, and one rotate handle above the
/// top edge — rather than multi-touch gestures. Lives in `CanvasView`'s `container` above
/// `SelectionOverlayView`, so its coordinate space matches canvas points exactly (same placement and
/// handle-drag technique as the object-layer work's `ObjectTransformOverlayView`).
final class FloatingPieceOverlayView: UIView {
    var onTransformChange: ((FloatingTransform) -> Void)?
    var onRequestCommit: (() -> Void)?

    private var piece: FloatingPiece?

    private let pieceImageView = UIImageView()
    private let outlineView = UIView()
    private let outlineDashLayer = CAShapeLayer()
    private let corners: [HandleView] = (0..<4).map { _ in HandleView(kind: .scale) }
    private let edges: [HandleView] = (0..<4).map { _ in HandleView(kind: .scale) }
    private let rotateHandle = HandleView(kind: .rotate)
    private let rotateLine = UIView()

    private var dragStartTransform: FloatingTransform = .identity
    private var dragStartTouch: CGPoint = .zero
    /// The opposite corner/edge (in canvas space), captured at the start of a resize drag and held
    /// fixed for its duration so the resize anchors there instead of at the piece's center.
    private var dragAnchor: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true

        pieceImageView.isUserInteractionEnabled = false
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapOutside(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Handles can end up outside this view's own bounds (the rotate handle, or a corner/edge when
    /// the piece sits near the canvas edge) — without this override those touches never reach them,
    /// since UIKit only recurses into subviews once a point is inside the hit-testing view's own
    /// bounds. Same technique as `ObjectTransformOverlayView`.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }

    func update(_ newPiece: FloatingPiece?) {
        piece = newPiece
        isHidden = newPiece == nil
        isUserInteractionEnabled = newPiece != nil
        guard newPiece != nil else { return }
        layoutFromPiece()
    }

    private func layoutFromPiece() {
        guard let piece else { return }
        pieceImageView.image = piece.pieceImage
        let t = piece.transform
        let affine = CGAffineTransform.identity
            .rotated(by: t.rotation)
            .scaledBy(x: t.scaleX * (t.flipH ? -1 : 1), y: t.scaleY * (t.flipV ? -1 : 1))

        pieceImageView.bounds = CGRect(origin: .zero, size: piece.baseSize)
        pieceImageView.transform = affine
        pieceImageView.center = t.position

        outlineView.bounds = pieceImageView.bounds
        outlineView.transform = affine
        outlineView.center = t.position
        outlineDashLayer.frame = outlineView.bounds
        outlineDashLayer.path = CGPath(rect: outlineView.bounds, transform: nil)

        let hw = piece.baseSize.width / 2, hh = piece.baseSize.height / 2
        let cornerLocal = [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh), CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)]
        let edgeLocal = [CGPoint(x: 0, y: -hh), CGPoint(x: hw, y: 0), CGPoint(x: 0, y: hh), CGPoint(x: -hw, y: 0)]

        for (i, local) in cornerLocal.enumerated() { corners[i].center = project(local, transform: t) }
        // Edge (single-axis) handles only make sense in Freeform — Uniform/Distort/Warp keep the
        // aspect ratio locked, so only corner handles are shown for those.
        let showEdgeHandles = piece.mode == .freeform
        for (i, local) in edgeLocal.enumerated() {
            edges[i].center = project(local, transform: t)
            edges[i].isHidden = !showEdgeHandles
        }

        let topCenter = project(CGPoint(x: 0, y: -hh), transform: t)
        let upDirection = CGPoint(x: sin(t.rotation), y: -cos(t.rotation))
        let handleDistance: CGFloat = 32
        let rotateCenter = CGPoint(x: topCenter.x + upDirection.x * handleDistance, y: topCenter.y + upDirection.y * handleDistance)
        rotateHandle.center = rotateCenter

        rotateLine.bounds = CGRect(x: 0, y: 0, width: 1.5, height: handleDistance)
        rotateLine.center = CGPoint(x: (topCenter.x + rotateCenter.x) / 2, y: (topCenter.y + rotateCenter.y) / 2)
        rotateLine.transform = CGAffineTransform(rotationAngle: t.rotation)
    }

    /// Maps a point in the piece's own local space (untransformed, centered on its own origin) into
    /// this view's coordinate space by applying the current scale/flip/rotation/position.
    private func project(_ local: CGPoint, transform t: FloatingTransform) -> CGPoint {
        let sx = t.scaleX * (t.flipH ? -1 : 1)
        let sy = t.scaleY * (t.flipV ? -1 : 1)
        let x = local.x * sx, y = local.y * sy
        let r = t.rotation
        let rx = x * cos(r) - y * sin(r)
        let ry = x * sin(r) + y * cos(r)
        return CGPoint(x: t.position.x + rx, y: t.position.y + ry)
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
            dragAnchor = project(oppositeCornerLocal(index, size: piece.baseSize), transform: dragStartTransform)
        case .changed:
            resizeFromAnchor(current: recognizer.location(in: self), uniform: piece.mode != .freeform, axisIsHorizontal: nil)
        default:
            break
        }
    }

    @objc private func handleEdgePan(_ recognizer: UIPanGestureRecognizer) {
        guard let piece, piece.mode == .freeform, let handle = recognizer.view else { return }
        let index = handle.tag // 0=top, 1=right, 2=bottom, 3=left
        switch recognizer.state {
        case .began:
            dragStartTransform = piece.transform
            dragAnchor = project(oppositeEdgeLocal(index, size: piece.baseSize), transform: dragStartTransform)
        case .changed:
            resizeFromAnchor(current: recognizer.location(in: self), uniform: false, axisIsHorizontal: (index == 1 || index == 3))
        default:
            break
        }
    }

    private func oppositeCornerLocal(_ index: Int, size: CGSize) -> CGPoint {
        let hw = size.width / 2, hh = size.height / 2
        switch index {
        case 0: return CGPoint(x: hw, y: hh)   // dragging TL -> anchor BR
        case 1: return CGPoint(x: -hw, y: hh)  // dragging TR -> anchor BL
        case 2: return CGPoint(x: -hw, y: -hh) // dragging BR -> anchor TL
        default: return CGPoint(x: hw, y: -hh) // dragging BL -> anchor TR
        }
    }

    private func oppositeEdgeLocal(_ index: Int, size: CGSize) -> CGPoint {
        let hw = size.width / 2, hh = size.height / 2
        switch index {
        case 0: return CGPoint(x: 0, y: hh)    // dragging top -> anchor bottom
        case 1: return CGPoint(x: -hw, y: 0)   // dragging right -> anchor left
        case 2: return CGPoint(x: 0, y: -hh)   // dragging bottom -> anchor top
        default: return CGPoint(x: hw, y: 0)   // dragging left -> anchor right
        }
    }

    /// Un-rotates the anchor→touch vector into the piece's local (unrotated) axes to derive new
    /// scale(s), then re-derives `position` from the fixed anchor so it visually stays put.
    /// `axisIsHorizontal` nil means both axes move together (corner drag); non-nil restricts the
    /// change to one axis (edge drag).
    private func resizeFromAnchor(current: CGPoint, uniform: Bool, axisIsHorizontal: Bool?) {
        guard let piece else { return }
        let r = dragStartTransform.rotation
        let dx = current.x - dragAnchor.x, dy = current.y - dragAnchor.y
        let localW = dx * cos(-r) - dy * sin(-r)
        let localH = dx * sin(-r) + dy * cos(-r)

        let baseW = max(piece.baseSize.width, 1), baseH = max(piece.baseSize.height, 1)
        var updated = dragStartTransform
        var localHalfW: CGFloat = 0
        var localHalfH: CGFloat = 0

        switch axisIsHorizontal {
        case true:
            updated.scaleX = max(abs(localW) / baseW, 0.02)
            localHalfW = (localW >= 0 ? 1 : -1) * updated.scaleX * baseW / 2
        case false:
            updated.scaleY = max(abs(localH) / baseH, 0.02)
            localHalfH = (localH >= 0 ? 1 : -1) * updated.scaleY * baseH / 2
        case nil:
            var scaleX = max(abs(localW) / baseW, 0.02)
            var scaleY = max(abs(localH) / baseH, 0.02)
            if uniform {
                let s = max(scaleX, scaleY)
                scaleX = s; scaleY = s
            }
            updated.scaleX = scaleX
            updated.scaleY = scaleY
            localHalfW = (localW >= 0 ? 1 : -1) * scaleX * baseW / 2
            localHalfH = (localH >= 0 ? 1 : -1) * scaleY * baseH / 2
        }

        let rotatedX = localHalfW * cos(r) - localHalfH * sin(r)
        let rotatedY = localHalfW * sin(r) + localHalfH * cos(r)
        updated.position = CGPoint(x: dragAnchor.x + rotatedX, y: dragAnchor.y + rotatedY)
        apply(updated)
    }

    // MARK: - Commit (tap outside the box)

    @objc private func handleTapOutside(_ recognizer: UITapGestureRecognizer) {
        guard let piece else { return }
        let location = recognizer.location(in: self)
        if !piece.transformedBounds.insetBy(dx: -8, dy: -8).contains(location) {
            onRequestCommit?()
        }
    }

    private func apply(_ updated: FloatingTransform) {
        piece?.transform = updated
        layoutFromPiece()
        onTransformChange?(updated)
    }
}

private final class HandleView: UIView {
    enum Kind { case scale, rotate }

    init(kind: Kind) {
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        layer.cornerRadius = kind == .scale ? 4 : 12
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.systemBlue.cgColor
        backgroundColor = kind == .scale ? .white : .systemBlue
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
