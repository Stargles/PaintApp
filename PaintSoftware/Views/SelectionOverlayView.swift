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
        liveShadowLayer.isHidden = true
        layer.addSublayer(liveShadowLayer)

        liveLayer.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
        liveLayer.strokeColor = UIColor.white.cgColor
        liveLayer.lineWidth = 1.5
        liveLayer.lineDashPattern = [6, 4]
        layer.addSublayer(liveLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = 0
        animation.toValue = 10
        animation.duration = 0.6
        animation.repeatCount = .infinity
        antsLayer.add(animation, forKey: "marchingAnts")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshHatchPath() // the "outside" rect tracks the view's own bounds, which can change on rotation/resize
    }

    /// - Parameter allowsOutsideInteraction: when false (the default "deny" state) and a selection
    ///   exists, the exterior hatch is shown to signal that painting/erasing/filling outside the
    ///   selection is blocked; when true, the hatch is hidden since nothing outside is actually
    ///   restricted.
    func updateSelection(_ selection: Selection?, allowsOutsideInteraction: Bool) {
        currentSelectionPath = selection?.path
        antsShadowLayer.path = selection?.path
        antsShadowLayer.isHidden = selection == nil
        antsLayer.path = selection?.path
        antsLayer.isHidden = selection == nil
        hatchIsEnabled = selection != nil && !allowsOutsideInteraction
        refreshHatchPath()
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
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
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

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isCapturingGestures else { return }
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
            liveShadowLayer.path = path
            liveLayer.path = path
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

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard isCapturingGestures, mode == .automatic else { return }
        onAutomaticTap?(recognizer.location(in: self))
    }
}
