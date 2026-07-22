import SwiftUI
import UIKit

/// A single-touch stroke-capture gesture recognizer: claims exactly one touch as the "drawing"
/// touch (mirroring the role `PKCanvasView.drawingGestureRecognizer` used to play) and fails
/// immediately if a second touch arrives, so the container's two-finger pan/pinch/rotate
/// recognizers — which dynamically wait for this recognizer to fail, see `Coordinator.
/// gestureRecognizer(_:shouldRequireFailureOf:)` — can take over cleanly instead of racing a
/// stray single-finger dot.
final class StrokeGestureRecognizer: UIGestureRecognizer {
    var requiresPencilOnly = true
    var onBegin: ((UITouch) -> Void)?
    var onMove: ((UITouch, UIEvent) -> Void)?
    var onEnd: ((UITouch) -> Void)?

    private var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first,
              !requiresPencilOnly || touch.type == .pencil else {
            state = .failed
            return
        }
        trackedTouch = touch
        state = .began
        onBegin?(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .changed
        onMove?(trackedTouch, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .ended
        onEnd?(trackedTouch)
        self.trackedTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .cancelled
        onEnd?(trackedTouch)
        self.trackedTouch = nil
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }
}

/// Drawing surface replacing PencilKit's `PKCanvasView`: captures raw touches via
/// `StrokeGestureRecognizer`, smooths them through a `StrokeStabilizer`, and stamps the active
/// `Brush` (shape, hardness, pressure dynamics, scatter/rotation jitter, grain) directly into the
/// active cel's `RasterLayerTexture` (see that type's doc comment for why — pixel-crisp zoom,
/// custom brush dynamics, and app-owned stabilization all need native-resolution raster strokes
/// instead of PencilKit's vector ones). Square/custom-shaped brushes are approximated as a tiled
/// grid of round dabs (see `stampApproximateSquare`) rather than a real quad/textured-image
/// primitive, since `RasterLayerTexture` only exposes a circular stamp — that's real follow-up work
/// for whoever owns that type, not implemented here.
///
/// Known placeholder limitation: stamps composite into the raster individually with `.normal`
/// blend, so overlapping stamps within one stroke build opacity up (a slow stroke reads darker/
/// blotchier than a fast one at the same brush opacity). The real renderer (Worker A) fixes this
/// the Procreate/Photoshop way — accumulate a stroke into its own buffer at full strength, then
/// composite that buffer once at brush opacity on stroke-end — which is out of scope for the
/// foundation.
final class StrokeCanvasView: UIView {
    let localUndoManager = UndoManager()
    override var undoManager: UndoManager? { localUndoManager }

    var layerID: UUID?
    var raster: RasterLayerTexture? {
        didSet { refreshDisplay() }
    }
    var brushColor: UIColor = .black
    var brushSize: CGFloat = 5
    var brushOpacity: Double = 1
    /// The full active brush preset (shape, hardness, spacing, stabilization, dynamics, scatter/
    /// rotation jitter, grain, blend mode) — everything `stampOne`/`stampPath` need beyond the live
    /// `brushSize`/`brushOpacity` above, which `CanvasManager` keeps as separate published
    /// properties precisely so sliders can move them independently of the selected preset (see that
    /// type's doc comment on `selectedBrush`).
    var brush: Brush = BrushLibrary.softRound {
        didSet { stabilizer.stabilization = brush.stabilization }
    }
    var isEraser: Bool = false
    var pencilOnlyDrawing: Bool = true {
        didSet { strokeRecognizer.requiresPencilOnly = pencilOnlyDrawing }
    }

    /// Called once per completed stroke (touch up) and once per undo/redo — hooks back into
    /// `CanvasManager.strokeEnded` for thumbnail regen / undo-button refresh.
    var onStrokeEnded: (() -> Void)?

    let strokeRecognizer = StrokeGestureRecognizer()
    private let imageView = UIImageView()
    private var strokeBeforeSnapshot: (image: UIImage?, count: Int)?
    /// The last position actually stamped, so `stampPath(to:)` can lay down evenly-spaced stamps
    /// *between* input samples rather than one dot per sample — otherwise a fast (or sparsely
    /// sampled) drag draws a dotted, gappy line, which among other things lets the bucket fill leak
    /// straight through the gaps in a lineart wall.
    private var lastStampPoint: CGPoint?
    /// Smooths raw touch positions into a trailing "follow" point before they reach `stampPath` —
    /// see `StrokeStabilizer`'s doc comment. Reset to the raw touch-down position at the start of
    /// every stroke (`handleBegin`) so the first stamp always lands exactly under the touch rather
    /// than smoothing in from wherever an earlier, unrelated stroke left the trailing point.
    private var stabilizer = StrokeStabilizer(stabilization: 0.2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        // Same fix already applied to fillImageView/bakedImageView (see LayerHostView): native-
        // resolution raster content should zoom blocky, not bilinearly blurred.
        imageView.layer.magnificationFilter = .nearest
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        strokeRecognizer.onBegin = { [weak self] touch in self?.handleBegin(touch) }
        strokeRecognizer.onMove = { [weak self] touch, event in self?.handleMove(touch, event) }
        strokeRecognizer.onEnd = { [weak self] touch in self?.handleEnd(touch) }
        addGestureRecognizer(strokeRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshDisplay() {
        imageView.image = raster?.renderToUIImage()
    }

    private func handleBegin(_ touch: UITouch) {
        guard let raster else { return }
        strokeBeforeSnapshot = (raster.renderToUIImage(), raster.strokeCount)
        raster.beginStroke()
        lastStampPoint = nil
        let input = StrokeInput(touch: touch, in: self)
        stabilizer.reset(to: input.position)
        stampPath(to: input.position, pressure: input.pressure)
        refreshDisplay()
    }

    private func handleMove(_ touch: UITouch, _ event: UIEvent) {
        guard raster != nil else { return }
        // Coalesced touches carry the full-rate sample history since the last redraw, not just
        // the latest point — matters for fast strokes so segments don't look faceted. Stamps go
        // into the persistent raster individually, but the (O(canvas)) display refresh happens
        // once for the whole batch, not per sample.
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let input = StrokeInput(touch: sample, in: self)
            let smoothed = stabilizer.update(rawPoint: input.position)
            stampPath(to: smoothed, pressure: input.pressure)
        }
        refreshDisplay()
    }

    private func handleEnd(_ touch: UITouch) {
        guard let raster, let before = strokeBeforeSnapshot else { return }
        // Stamp through to the exact *raw* lift point, bypassing the stabilizer, so the stroke
        // still actually reaches where the touch ended even when stabilization is smoothing/lagging
        // behind — without this, the last sub-spacing segment is dropped (for a heavily-stabilized
        // brush, the trailing point could still be lagging well behind at lift time), which for a
        // shape like a traced square leaves gaps right at the corners (its edge endpoints), and a
        // bucket fill leaks straight through them.
        let input = StrokeInput(touch: touch, in: self)
        stampPath(to: input.position, pressure: input.pressure)
        raster.endStroke()
        lastStampPoint = nil
        refreshDisplay()
        let after = (raster.renderToUIImage(), raster.strokeCount)
        registerRasterUndo(raster: raster, from: before, to: after)
        strokeBeforeSnapshot = nil
        onStrokeEnded?()
    }

    /// Classic reversible-closure undo registration (same pattern as `CanvasManager.
    /// registerFillUndo`/`SelectionModels.registerUndoableCelChange`): each undo re-registers the
    /// opposite action, so redo — and further undo/redo cycling — keeps working. A whole-image
    /// snapshot per stroke, not a dirty-rect crop; fine for a placeholder, but real bounded/cropped
    /// undo storage (see BUGS.md's engine-rewrite notes) is real follow-up work, not done here.
    private func registerRasterUndo(raster: RasterLayerTexture, from: (image: UIImage?, count: Int), to: (image: UIImage?, count: Int)) {
        localUndoManager.registerUndo(withTarget: self) { target in
            raster.reset(to: from.image, strokeCount: from.count)
            target.refreshDisplay()
            target.onStrokeEnded?()
            target.registerRasterUndo(raster: raster, from: to, to: from)
        }
        localUndoManager.setActionName("Stroke")
    }

    /// Lays down stamps from `lastStampPoint` up to `point`, spaced a fraction of the brush diameter
    /// apart (`brush.spacingFraction`), so consecutive input samples are joined into a continuous
    /// line instead of isolated dots. Leftover distance shorter than one spacing step is carried
    /// forward (via keeping `lastStampPoint` where it is) until enough accumulates.
    private func stampPath(to point: CGPoint, pressure: CGFloat) {
        guard raster != nil else { return }
        guard let last = lastStampPoint else {
            stampOne(at: point, pressure: pressure)
            lastStampPoint = point
            return
        }
        let dx = point.x - last.x, dy = point.y - last.y
        let distance = hypot(dx, dy)
        // The 1pt floor keeps thin/tight-spacing brushes continuous even at spacingFraction ~= 0.
        let spacing = max(brushSize * CGFloat(brush.spacingFraction), 1)
        guard distance >= spacing else { return } // not far enough yet — accumulate on the next sample
        let steps = Int(distance / spacing)
        for i in 1...steps {
            let t = (CGFloat(i) * spacing) / distance
            stampOne(at: CGPoint(x: last.x + dx * t, y: last.y + dy * t), pressure: pressure)
        }
        let coveredT = (CGFloat(steps) * spacing) / distance
        lastStampPoint = CGPoint(x: last.x + dx * coveredT, y: last.y + dy * coveredT)
    }

    /// Stamps one dab at `point`, honoring the active brush's shape, hardness, pressure dynamics
    /// (size and opacity), scatter, rotation jitter, and grain. The eraser path is left exactly as
    /// it was before brush support existed (fixed size/hardness, no brush shape/dynamics) — an
    /// eraser conceptually erases with a plain round tool regardless of which paint brush happens to
    /// be selected, matching how Procreate's eraser works independently of the current brush.
    private func stampOne(at point: CGPoint, pressure: CGFloat) {
        guard let raster else { return }
        if isEraser {
            let radius = brushSize / 2
            // .destinationOut: the stamp's alpha controls how much is removed, so a soft edge erases
            // softly (a flat .clear would hard-cut the whole disc regardless of falloff).
            raster.stampCircle(at: point, radius: radius, color: .black, alpha: 1, hardness: 0.6, blendMode: .destinationOut)
            return
        }

        let pressureValue = Double(max(0, min(pressure, 1)))
        let sizeFraction = brush.dynamics.sizeFraction(forPressure: pressureValue)
        let opacityFraction = brush.dynamics.opacityFraction(forPressure: pressureValue)
        let diameter = max(brushSize * CGFloat(sizeFraction), 0.5)
        let radius = diameter / 2
        let alpha = CGFloat(brushOpacity) * CGFloat(brush.flow) * CGFloat(opacityFraction)
        guard alpha > 0, radius > 0 else { return }

        let stampPoint = applyScatter(to: point, radius: radius)
        let hardness = CGFloat(brush.hardness)
        let blendMode = brush.blendMode.cgBlendMode

        switch brush.shape {
        case .softRound, .hardRound, .pen:
            raster.stampCircle(at: stampPoint, radius: radius, color: brushColor, alpha: alpha, hardness: hardness, blendMode: blendMode)
        case .pencil:
            let grainMultiplier = brush.grain.isEnabled ? grainAlphaMultiplier(at: stampPoint, grain: brush.grain) : 1
            raster.stampCircle(at: stampPoint, radius: radius, color: brushColor, alpha: alpha * grainMultiplier, hardness: hardness, blendMode: blendMode)
        case .square, .custom:
            // RasterLayerTexture only exposes a circular stamp primitive (see its doc comment: a
            // real quad/textured-image primitive is Worker A's follow-up, out of scope for this
            // file) — approximate both square and custom-texture brushes the same way, as a tiled
            // grid of small round dabs. See stampApproximateSquare's doc comment for the tradeoffs.
            let rotation: CGFloat = brush.rotationJitter > 0
                ? CGFloat.random(in: -CGFloat.pi...CGFloat.pi) * CGFloat(brush.rotationJitter)
                : 0
            stampApproximateSquare(at: stampPoint, diameter: diameter, rotation: rotation, color: brushColor, alpha: alpha, hardness: hardness, blendMode: blendMode)
        }
    }

    /// Randomly offsets a stamp's position by up to `scatter * diameter`, in a random direction —
    /// `Brush.scatter` is 0 for every built-in preset, so this is a no-op unless a user (or a future
    /// preset) turns it on.
    private func applyScatter(to point: CGPoint, radius: CGFloat) -> CGPoint {
        guard brush.scatter > 0 else { return point }
        let maxOffset = radius * 2 * CGFloat(brush.scatter)
        let angle = CGFloat.random(in: 0..<(2 * .pi))
        let distance = CGFloat.random(in: 0...maxOffset)
        return CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
    }

    /// Per-stamp opacity multiplier for the Pencil brush's "tooth", from `BrushGrain.noiseValue` (a
    /// procedural stand-in for a scanned paper texture — see that function's doc comment). At
    /// `grain.depth == 0` this is always 1 (no modulation); at `depth == 1` it's the raw 0...1 noise
    /// value, so lighter grain "valleys" let noticeably less ink through per stamp.
    private func grainAlphaMultiplier(at point: CGPoint, grain: BrushGrain) -> CGFloat {
        let noise = BrushGrain.noiseValue(atX: Double(point.x), y: Double(point.y), scale: grain.scale, rotation: grain.rotation)
        let depth = CGFloat(max(0, min(grain.depth, 1)))
        return (1 - depth) + depth * CGFloat(noise)
    }

    /// Approximates a square (or custom-texture, pending real texture support) stamp as a small grid
    /// of overlapping round dabs tiled across the stamp's footprint, optionally rotated as a whole
    /// (for `rotationJitter`). `RasterLayerTexture` only exposes a circular stamp primitive — adding
    /// a real single-pass rect/textured-quad primitive there is Worker A's file, out of scope here —
    /// so this is a pragmatic approximation, not a true square stamp: edges come out scalloped
    /// rather than crisp, and overlapping dabs can build up opacity at their seams (the same already-
    /// documented limitation as this view's per-stamp compositing generally, see this file's top doc
    /// comment). Good enough to prove square/custom brushes exist and behave brush-like; a real
    /// quad/textured stamp primitive in `RasterLayerTexture` is real follow-up work, not done here.
    private func stampApproximateSquare(at center: CGPoint, diameter: CGFloat, rotation: CGFloat, color: UIColor, alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        guard let raster, diameter > 0 else { return }
        let half = diameter / 2
        let dabDiameter = max(diameter * 0.42, 1)
        let dabRadius = dabDiameter / 2
        let step = max(dabDiameter * 0.65, 1)
        let cosR = cos(rotation), sinR = sin(rotation)

        var y = -half
        while y <= half {
            var x = -half
            while x <= half {
                let rx = x * cosR - y * sinR
                let ry = x * sinR + y * cosR
                raster.stampCircle(at: CGPoint(x: center.x + rx, y: center.y + ry), radius: dabRadius, color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
                x += step
            }
            y += step
        }
    }
}

/// One slot in the layer stack: an optional static image (for object/photo layers, positioned by its
/// own position/scale/rotation via `objectTransform` rather than pinned to the host's edges — see
/// `applyObjectTransform`), a raster fill layer (bucket-fill output for the current cel, pinned
/// edge-to-edge), and a drawable stroke canvas on top — so fill color always sits visually behind
/// that layer's own ink strokes.
final class LayerHostView: UIView {
    let imageView = UIImageView()
    let fillImageView = UIImageView()
    /// Raster content "baked" into this layer's active cel by a select/move/fill/clear operation
    /// (see `Cel.bakedImage`), or the transient "hole" preview while that cel's content is lifted
    /// into a floating piece. Sits above `fillImageView`, below `strokeView`'s live strokes.
    let bakedImageView = UIImageView()
    let strokeView = StrokeCanvasView()

    init() {
        super.init(frame: .zero)
        imageView.isUserInteractionEnabled = false
        imageView.isHidden = true

        // The fill raster is always rendered at exactly canvasSize (see FloodFillEngine), matching this
        // view's bounds 1:1, so a plain stretch-to-fill can't introduce any resampling blur at the edges.
        fillImageView.contentMode = .scaleToFill
        fillImageView.translatesAutoresizingMaskIntoConstraints = false

        bakedImageView.isUserInteractionEnabled = false
        bakedImageView.isHidden = true
        bakedImageView.translatesAutoresizingMaskIntoConstraints = false

        strokeView.backgroundColor = .clear
        strokeView.isOpaque = false
        strokeView.translatesAutoresizingMaskIntoConstraints = false

        // The whole layer stack is magnified via a CGAffineTransform scale on the container (see
        // Coordinator.applyTransform), not by re-rasterizing at a higher resolution — Core Animation's
        // default magnificationFilter (.linear) would bilinearly blur these raster layers' textures as
        // the user zooms in. Nearest-neighbor keeps pixels crisp/blocky at high zoom instead. strokeView
        // sets this on its own internal image view (see StrokeCanvasView.init).
        imageView.layer.magnificationFilter = .nearest
        fillImageView.layer.magnificationFilter = .nearest
        bakedImageView.layer.magnificationFilter = .nearest

        addSubview(imageView)
        addSubview(fillImageView)
        addSubview(bakedImageView)
        addSubview(strokeView)
        NSLayoutConstraint.activate([
            // imageView is deliberately NOT pinned here: object layers position it directly via
            // bounds/transform/center in applyObjectTransform, which Auto Layout constraints would fight.
            fillImageView.topAnchor.constraint(equalTo: topAnchor),
            fillImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bakedImageView.topAnchor.constraint(equalTo: topAnchor),
            bakedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bakedImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bakedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            strokeView.topAnchor.constraint(equalTo: topAnchor),
            strokeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            strokeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            strokeView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Fills the SwiftUI container and reports layout changes so the coordinator
/// can refit the canvas when the window/split-view size changes.
final class CanvasHostView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct CanvasView: UIViewRepresentable {
    @ObservedObject var canvasManager: CanvasManager
    var activePanel: ActivePanel = .none

    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.isAccessibilityElement = true
        host.accessibilityIdentifier = "canvas.host"

        let container = UIView()
        container.backgroundColor = .clear
        host.addSubview(container)

        let paper = UIView()
        paper.backgroundColor = .white
        paper.isUserInteractionEnabled = false
        paper.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(paper)

        let onionSkin = UIImageView()
        onionSkin.contentMode = .scaleAspectFit
        onionSkin.isUserInteractionEnabled = false
        onionSkin.translatesAutoresizingMaskIntoConstraints = false
        // Deliberately left on the default (bilinear) filter: onion skin is a translucent reference
        // ghost of the previous frame, shown independent of the current layer's own opacity — nearest-
        // neighbor made that ghost render as a sharp, distractingly pixelated overlay instead of the
        // soft blended reference it's meant to be.
        container.addSubview(onionSkin)

        let transformOverlay = ObjectTransformOverlayView()
        transformOverlay.isHidden = true
        transformOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(transformOverlay)

        let selectionOverlay = SelectionOverlayView()
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(selectionOverlay)

        let floatingOverlay = FloatingPieceOverlayView()
        floatingOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(floatingOverlay)

        NSLayoutConstraint.activate([
            paper.topAnchor.constraint(equalTo: container.topAnchor),
            paper.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            paper.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            paper.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            onionSkin.topAnchor.constraint(equalTo: container.topAnchor),
            onionSkin.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            onionSkin.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            onionSkin.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            transformOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            transformOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            transformOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            transformOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            selectionOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            floatingOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            floatingOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            floatingOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            floatingOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        context.coordinator.hostView = host
        context.coordinator.containerView = container
        context.coordinator.onionSkinView = onionSkin
        context.coordinator.paperView = paper
        context.coordinator.transformOverlay = transformOverlay
        context.coordinator.selectionOverlay = selectionOverlay
        context.coordinator.floatingOverlay = floatingOverlay
        context.coordinator.setUpGestures(on: container)

        transformOverlay.onTransformChange = { [weak coordinator = context.coordinator] transform in
            coordinator?.objectTransformChanged(transform)
        }
        selectionOverlay.onFinishPath = { [weak coordinator = context.coordinator] path in
            coordinator?.canvasManager.finishSelection(path: path)
        }
        selectionOverlay.onAutomaticTap = { [weak coordinator = context.coordinator] point in
            coordinator?.canvasManager.finishAutomaticSelection(at: point)
        }
        floatingOverlay.onTransformChange = { [weak coordinator = context.coordinator] transform in
            coordinator?.canvasManager.updateFloatingTransform(transform)
        }
        floatingOverlay.onRequestCommit = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.commitFloatingPieceIfNeeded()
        }

        host.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.hostBoundsDidChange()
        }

        context.coordinator.activePanel = activePanel
        context.coordinator.reconcileLayers()
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateSelectionOverlay()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.hostBoundsDidChange()

        return host
    }

    func updateUIView(_ uiView: CanvasHostView, context: Context) {
        context.coordinator.activePanel = activePanel
        context.coordinator.updatePaper()
        context.coordinator.reconcileLayers()
        context.coordinator.updateActiveLayerAndTool()
        context.coordinator.updateOnionSkin()
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateSelectionOverlay()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.hostBoundsDidChange()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(canvasManager: canvasManager)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canvasManager: CanvasManager

        weak var hostView: CanvasHostView?
        weak var containerView: UIView?
        weak var onionSkinView: UIImageView?
        weak var paperView: UIView?
        weak var transformOverlay: ObjectTransformOverlayView?
        weak var selectionOverlay: SelectionOverlayView?
        weak var floatingOverlay: FloatingPieceOverlayView?
        var activePanel: ActivePanel = .none
        var layerHosts: [UUID: LayerHostView] = [:]

        weak var panRecognizer: UIPanGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var rotationRecognizer: UIRotationGestureRecognizer?
        weak var fillTapRecognizer: UITapGestureRecognizer?

        private var fitScale: CGFloat = 1
        private var baseCenter: CGPoint?

        private var committedScale: CGFloat = 1
        private var committedRotation: CGFloat = 0
        private var committedOffset: CGSize = .zero

        private var liveScale: CGFloat = 1
        private var liveRotation: CGFloat = 0
        private var liveOffset: CGSize = .zero

        // The screen point + container center captured when the first of pan/pinch/rotation begins,
        // used to keep whatever content point is under the fingers fixed on screen as scale/rotation
        // change (rather than always zooming/rotating around the canvas's own center).
        private var gestureAnchorHost0: CGPoint?
        private var gestureAnchorCenter0: CGPoint?

        // Rotation snaps to the nearest right angle when close to one, like Procreate, but releases
        // the snap if the user holds within the snap zone for more than a second.
        private let rotationSnapThreshold: CGFloat = 5 * .pi / 180
        private var snapEngagedAt: Date?

        private var lastAppliedTransform: (scale: CGFloat, rotation: CGFloat, offset: CGSize)?

        private struct ActiveKey: Equatable {
            let layerID: UUID
            let frame: Int
        }
        private var lastActiveKey: ActiveKey?

        /// Guards against reassigning the stroke view's tool settings on every SwiftUI re-render
        /// (this method runs on every re-render, including mid-stroke ones).
        private struct AppliedTool: Equatable {
            let tool: Tool
            let color: Color
            let size: CGFloat
            let opacity: Double
            let brush: Brush
        }
        private var lastAppliedTool: [UUID: AppliedTool] = [:]
        private var lastOrderedLayerIDs: [UUID] = []

        init(canvasManager: CanvasManager) {
            self.canvasManager = canvasManager
        }

        // MARK: - Layer stack

        func updatePaper() {
            guard let paperView else { return }
            paperView.backgroundColor = UIColor(canvasManager.canvasBackgroundColor)
            paperView.isHidden = !canvasManager.isCanvasBackgroundVisible
        }

        func reconcileLayers() {
            guard let container = containerView else { return }

            let currentIDs = Set(canvasManager.layers.map(\.id))
            for (id, host) in layerHosts where !currentIDs.contains(id) {
                host.removeFromSuperview()
                layerHosts.removeValue(forKey: id)
                lastAppliedTool.removeValue(forKey: id)
            }

            for layer in canvasManager.layers where layerHosts[layer.id] == nil {
                let host = LayerHostView()
                host.strokeView.layerID = layer.id
                host.strokeView.onStrokeEnded = { [weak self, weak host] in
                    guard let self, let host, let layerID = host.strokeView.layerID,
                          let layerIndex = self.canvasManager.layers.firstIndex(where: { $0.id == layerID }),
                          let celIndex = self.canvasManager.activeCelIndex(inLayer: layerIndex, atFrame: self.canvasManager.currentFrame) else { return }
                    self.canvasManager.strokeEnded(layerIndex: layerIndex, celIndex: celIndex)
                    self.canvasManager.refreshUndoRedoState()
                }

                host.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(host)
                NSLayoutConstraint.activate([
                    host.topAnchor.constraint(equalTo: container.topAnchor),
                    host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    host.trailingAnchor.constraint(equalTo: container.trailingAnchor)
                ])
                layerHosts[layer.id] = host
            }

            let orderedIDs = canvasManager.layers.map(\.id)
            if orderedIDs != lastOrderedLayerIDs {
                for layer in canvasManager.layers {
                    if let host = layerHosts[layer.id] {
                        container.bringSubviewToFront(host)
                    }
                }
                lastOrderedLayerIDs = orderedIDs
            }

            for (index, layer) in canvasManager.layers.enumerated() {
                guard let host = layerHosts[layer.id] else { continue }
                if host.strokeView.pencilOnlyDrawing != canvasManager.pencilOnlyDrawing {
                    host.strokeView.pencilOnlyDrawing = canvasManager.pencilOnlyDrawing
                }
                if host.isHidden != !layer.isVisible { host.isHidden = !layer.isVisible }
                let targetAlpha = CGFloat(layer.opacity)
                if host.alpha != targetAlpha { host.alpha = targetAlpha }

                if layer.isObjectLayer {
                    if host.imageView.image !== layer.objectImage { host.imageView.image = layer.objectImage }
                    host.imageView.isHidden = false
                    applyObjectTransform(layer.objectTransform, imageSize: layer.objectImage?.size, to: host.imageView)
                } else {
                    host.imageView.isHidden = true
                }

                let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame)

                let displayedBaked = bakedImageToDisplay(layerIndex: index, celIndex: celIdx)
                if host.bakedImageView.image !== displayedBaked { host.bakedImageView.image = displayedBaked }
                let bakedHidden = displayedBaked == nil
                if host.bakedImageView.isHidden != bakedHidden { host.bakedImageView.isHidden = bakedHidden }

                // While this cel's content is floating (lifted into a Move piece), its live strokes
                // are hidden — the "hole" is shown via bakedImageView's remainder preview instead —
                // so the lifted content doesn't render twice (once floating, once still in place).
                let isFloatingSource = isFloatingMoveSource(layerIndex: index, celIndex: celIdx)
                if host.strokeView.isHidden != isFloatingSource {
                    host.strokeView.isHidden = isFloatingSource
                }
                if !isFloatingSource {
                    let targetRaster = celIdx.map { canvasManager.layers[index].cels[$0].raster }
                    if host.strokeView.raster !== targetRaster {
                        host.strokeView.raster = targetRaster
                    }
                }
                let targetFillImage = celIdx.flatMap { canvasManager.layers[index].cels[$0].fillImage }
                if host.fillImageView.image !== targetFillImage {
                    host.fillImageView.image = targetFillImage
                }
                // Disabling only strokeView.isUserInteractionEnabled isn't enough: each LayerHostView
                // fully covers the container and stacks as a sibling, so an inactive host still
                // swallows touches via UIView's default hitTest (which returns the host itself once
                // its non-interactive subviews all reject the point), preventing the touch from ever
                // reaching an active layer underneath. Disabling the host itself lets hit-testing
                // fall through to the next layer down. The fill tool also disables it on the active
                // layer: it works via a tap gesture on the container, not stroke capture.
                // Object layers are never drawable — they're moved/scaled/rotated via the transform
                // overlay instead, which lives above the whole layer stack (see updateTransformOverlay).
                // Select/Move take over touch handling entirely while engaged (via SelectionOverlayView/
                // FloatingPieceOverlayView, both above the whole layer stack), so drawing is disabled then too.
                let shouldInteract = (index == canvasManager.currentLayerIndex) && celIdx != nil
                    && !layer.isObjectLayer && canvasManager.selectedTool != .fill
                    && activePanel != .select && canvasManager.floatingPiece == nil
                if host.isUserInteractionEnabled != shouldInteract {
                    host.isUserInteractionEnabled = shouldInteract
                }
                if host.strokeView.isUserInteractionEnabled != shouldInteract {
                    host.strokeView.isUserInteractionEnabled = shouldInteract
                }
            }
        }

        private func applyObjectTransform(_ transform: LayerTransform, imageSize: CGSize?, to imageView: UIImageView) {
            guard let imageSize, imageSize.width > 0, imageSize.height > 0 else { return }
            if imageView.bounds.size != imageSize {
                imageView.bounds = CGRect(origin: .zero, size: imageSize)
            }
            let newTransform = CGAffineTransform.identity.rotated(by: transform.rotation).scaledBy(x: transform.scale, y: transform.scale)
            if imageView.transform != newTransform {
                imageView.transform = newTransform
            }
            if imageView.center != transform.position {
                imageView.center = transform.position
            }
        }

        // MARK: - Object transform overlay

        func updateTransformOverlay() {
            guard let overlay = transformOverlay, let container = containerView else { return }
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else {
                overlay.isHidden = true
                return
            }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard layer.isObjectLayer, layer.isVisible, let image = layer.objectImage else {
                overlay.isHidden = true
                return
            }
            overlay.update(transform: layer.objectTransform, imageSize: image.size)
            container.bringSubviewToFront(overlay)
        }

        func objectTransformChanged(_ transform: LayerTransform) {
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return }
            canvasManager.updateObjectTransform(layerIndex: canvasManager.currentLayerIndex, transform: transform)
        }

        /// What a layer's `bakedImageView` should show for its active cel: the real `bakedImage`,
        /// or — while that exact cel's content is lifted into a Move (not Duplicate) piece — the
        /// transient "hole" preview computed at lift time, which isn't written into the model until
        /// the piece commits (see `CanvasManager.beginMove`/`commitFloatingPieceIfNeeded`).
        private func bakedImageToDisplay(layerIndex: Int, celIndex: Int?) -> UIImage? {
            guard let celIndex else { return nil }
            if let piece = canvasManager.floatingPiece, piece.kind == .move,
               piece.sourceLayerIndex == layerIndex, piece.sourceCelIndex == celIndex {
                return piece.remainderPreview
            }
            return canvasManager.layers[layerIndex].cels[celIndex].bakedImage
        }

        private func isFloatingMoveSource(layerIndex: Int, celIndex: Int?) -> Bool {
            guard let celIndex, let piece = canvasManager.floatingPiece, piece.kind == .move else { return false }
            return piece.sourceLayerIndex == layerIndex && piece.sourceCelIndex == celIndex
        }

        // MARK: - Select & Move overlays

        func updateSelectionOverlay() {
            guard let overlay = selectionOverlay else { return }
            overlay.mode = canvasManager.selectionMode
            overlay.isCapturingGestures = (activePanel == .select) && (canvasManager.floatingPiece == nil)
            overlay.updateSelection(canvasManager.selection)
        }

        func updateFloatingOverlay() {
            floatingOverlay?.update(canvasManager.floatingPiece)
        }

        func updateActiveLayerAndTool() {
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard let host = layerHosts[layer.id] else { return }

            let activeKey = ActiveKey(layerID: layer.id, frame: canvasManager.currentFrame)
            if activeKey != lastActiveKey {
                host.strokeView.undoManager?.removeAllActions()
                lastActiveKey = activeKey
            }
            canvasManager.activeUndoManager = host.strokeView.undoManager
            let newCanUndo = host.strokeView.undoManager?.canUndo ?? false
            let newCanRedo = host.strokeView.undoManager?.canRedo ?? false
            if canvasManager.canUndo != newCanUndo || canvasManager.canRedo != newCanRedo {
                // Mutating @Published state synchronously here would be "publishing changes from
                // within view updates" (this method runs inside CanvasView.updateUIView), which
                // SwiftUI warns can cause undefined/re-entrant behavior. In practice that showed up
                // as a hang right when the active layer's identity changed (e.g. right after
                // deleting a layer), since removeAllActions() above flips canUndo/canRedo on the
                // same pass. Defer the publish to the next run loop turn instead.
                DispatchQueue.main.async { [weak self] in
                    self?.canvasManager.refreshUndoRedoState()
                }
            }

            // Not per-layer (there's only one global selected tool), so it lives outside the
            // per-layer caching guard below and is kept in sync on every call.
            fillTapRecognizer?.isEnabled = (canvasManager.selectedTool == .fill)

            // Only push new tool settings into the view when something tool-relevant actually
            // changed, same caching reason as before (this method runs on every SwiftUI re-render).
            let desired = AppliedTool(tool: canvasManager.selectedTool, color: canvasManager.brushColor, size: canvasManager.brushSize, opacity: canvasManager.brushOpacity, brush: canvasManager.selectedBrush)
            guard lastAppliedTool[layer.id] != desired else { return }
            lastAppliedTool[layer.id] = desired

            host.strokeView.brushColor = canvasManager.brushColor.resolvedUIColor(opacity: 1)
            host.strokeView.brushSize = canvasManager.brushSize
            host.strokeView.brushOpacity = canvasManager.brushOpacity
            host.strokeView.brush = canvasManager.selectedBrush
            host.strokeView.isEraser = (canvasManager.selectedTool == .eraser)
            // .fill is handled by fillTapRecognizer, not the stroke view — the canvas is
            // non-interactive there (see reconcileLayers' shouldInteract).
        }

        func updateOnionSkin() {
            guard let onionSkinView, canvasManager.canvasSize != nil else { return }
            guard canvasManager.isOnionSkinEnabled,
                  canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
                  let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame - 1) else {
                onionSkinView.isHidden = true
                return
            }

            onionSkinView.image = canvasManager.layers[canvasManager.currentLayerIndex].cels[celIdx].raster.renderToUIImage()
            onionSkinView.alpha = CGFloat(canvasManager.onionSkinOpacity)
            onionSkinView.isHidden = false
        }

        // MARK: - Fit / transform

        func hostBoundsDidChange() {
            guard let host = hostView, let container = containerView,
                  let canvasSize = canvasManager.canvasSize,
                  canvasSize.width > 0, canvasSize.height > 0 else { return }

            if container.bounds.size != canvasSize {
                container.bounds = CGRect(origin: .zero, size: canvasSize)
            }

            let hostBounds = host.bounds
            guard hostBounds.width > 0, hostBounds.height > 0 else { return }
            fitScale = min(hostBounds.width / canvasSize.width, hostBounds.height / canvasSize.height)
            if baseCenter == nil {
                baseCenter = CGPoint(x: hostBounds.midX, y: hostBounds.midY)
            }
            applyTransform()
        }

        /// The rotation actually used for rendering: snaps to the nearest right angle when the raw
        /// angle is close to one, unless the user has held within that snap zone for over a second
        /// (which releases the snap so they can keep rotating past it).
        private func effectiveRotation() -> CGFloat {
            let raw = committedRotation + liveRotation
            let quarterTurn = CGFloat.pi / 2
            let nearest = (raw / quarterTurn).rounded() * quarterTurn
            guard abs(raw - nearest) < rotationSnapThreshold else {
                snapEngagedAt = nil
                return raw
            }
            if snapEngagedAt == nil {
                snapEngagedAt = Date()
            }
            if let engaged = snapEngagedAt, Date().timeIntervalSince(engaged) > 1.0 {
                return raw
            }
            return nearest
        }

        private func applyTransform() {
            guard let container = containerView, let baseCenter else { return }
            let scale = fitScale * committedScale * liveScale
            let rotation = effectiveRotation()
            let offset = CGSize(width: committedOffset.width + liveOffset.width, height: committedOffset.height + liveOffset.height)

            // Reassigning .transform/.center to identical values still forces a Core Animation
            // update pass; guard it so it never happens on renders unrelated to the canvas transform
            // (e.g. every point of an in-progress stroke), which could otherwise perturb the active
            // stroke's touch tracking.
            if let last = lastAppliedTransform, last.scale == scale, last.rotation == rotation, last.offset == offset {
                return
            }
            lastAppliedTransform = (scale, rotation, offset)

            container.transform = CGAffineTransform.identity.rotated(by: rotation).scaledBy(x: scale, y: scale)
            container.center = CGPoint(x: baseCenter.x + offset.width, y: baseCenter.y + offset.height)
        }

        // MARK: - Gestures

        func setUpGestures(on view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            pan.cancelsTouchesInView = false
            view.addGestureRecognizer(pan)
            panRecognizer = pan

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            pinch.cancelsTouchesInView = false
            view.addGestureRecognizer(pinch)
            pinchRecognizer = pinch

            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotation.delegate = self
            rotation.cancelsTouchesInView = false
            view.addGestureRecognizer(rotation)
            rotationRecognizer = rotation

            let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
            twoFingerTap.numberOfTouchesRequired = 2
            twoFingerTap.cancelsTouchesInView = false
            view.addGestureRecognizer(twoFingerTap)

            let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
            threeFingerTap.numberOfTouchesRequired = 3
            threeFingerTap.cancelsTouchesInView = false
            view.addGestureRecognizer(threeFingerTap)

            twoFingerTap.require(toFail: threeFingerTap)

            // One-finger tap that drives the fill tool. Kept disabled except while the fill tool is
            // selected (toggled in updateActiveLayerAndTool) rather than gated only inside the handler,
            // so it never competes for single-finger touches with the active layer's own stroke
            // capture while a drawing tool is active.
            let fillTap = UITapGestureRecognizer(target: self, action: #selector(handleFillTap(_:)))
            fillTap.delegate = self
            fillTap.cancelsTouchesInView = false
            fillTap.isEnabled = false
            view.addGestureRecognizer(fillTap)
            fillTapRecognizer = fillTap
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let transformRecognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0 }
            return transformRecognizers.contains(where: { $0 === gestureRecognizer }) &&
                   transformRecognizers.contains(where: { $0 === otherGestureRecognizer })
        }

        /// Dynamically requires the transform recognizers to wait on the *currently active* layer's
        /// drawing gesture recognizer only. A static `require(toFail:)` against every layer (including
        /// inactive ones, whose recognizers never receive touches because isUserInteractionEnabled is
        /// false and therefore never reach `.failed`) permanently deadlocks two-finger pan/zoom/rotate
        /// as soon as a second layer exists. This is evaluated fresh for every gesture attempt instead.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let transformRecognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0 }
            guard transformRecognizers.contains(where: { $0 === gestureRecognizer }) else { return false }
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return false }
            let activeLayer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard let activeHost = layerHosts[activeLayer.id] else { return false }
            return otherGestureRecognizer === activeHost.strokeView.strokeRecognizer
        }

        // MARK: - Shared anchor-preserving pan/zoom/rotate

        /// Captures the touch centroid and container center at the start of whichever of
        /// pan/pinch/rotation begins first, so all three can share one anchor for this touch sequence.
        private func beginAnchorIfNeeded(at location: CGPoint) {
            guard gestureAnchorCenter0 == nil, let container = containerView else { return }
            gestureAnchorHost0 = location
            gestureAnchorCenter0 = container.center
        }

        /// Keeps the content point that was under the fingers at gesture-start pinned under the
        /// fingers' *current* location as scale/rotation change, and also carries plain panning
        /// (when scale/rotation are unchanged, this reduces to "offset by however far fingers moved").
        private func updateLiveOffset(currentLocation: CGPoint) {
            guard let host0 = gestureAnchorHost0, let center0 = gestureAnchorCenter0 else { return }
            let d0 = CGPoint(x: host0.x - center0.x, y: host0.y - center0.y)
            let theta = effectiveRotation() - committedRotation // this gesture's rotation contribution only
            let s = liveScale
            let rotatedScaled = CGPoint(
                x: s * (d0.x * cos(theta) - d0.y * sin(theta)),
                y: s * (d0.x * sin(theta) + d0.y * cos(theta))
            )
            liveOffset = CGSize(
                width: currentLocation.x - rotatedScaled.x - center0.x,
                height: currentLocation.y - rotatedScaled.y - center0.y
            )
        }

        /// Folds live scale/rotation/offset into the committed baseline once *all* of pan/pinch/rotation
        /// have ended, rather than each committing independently (fingers rarely lift in perfect sync,
        /// and committing one gesture's contribution while another is still live would jump visually).
        private func commitLiveTransformIfAllEnded() {
            let states: [UIGestureRecognizer.State] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0?.state }
            guard !states.contains(.began), !states.contains(.changed) else { return }
            // No upper bound — zoom is unlimited. The tiny floor only guards against the scale
            // collapsing to zero/negative if a pinch's fingers cross, not a real zoom limit.
            committedScale = max(committedScale * liveScale, 0.01)
            committedRotation = effectiveRotation()
            committedOffset.width += liveOffset.width
            committedOffset.height += liveOffset.height
            liveScale = 1
            liveRotation = 0
            liveOffset = .zero
            gestureAnchorHost0 = nil
            gestureAnchorCenter0 = nil
            snapEngagedAt = nil
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let host = hostView else { return }
            switch recognizer.state {
            case .began:
                beginAnchorIfNeeded(at: recognizer.location(in: host))
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .changed:
                // Once a finger lifts, pan (which requires exactly 2 touches) ends immediately
                // while pinch/rotation are still tracking the one remaining finger and would
                // otherwise report a jumped centroid. Freeze here and let the final commit use
                // whatever was last valid, instead of chasing that jump.
                guard recognizer.numberOfTouches >= 2 else { return }
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .ended, .cancelled:
                commitLiveTransformIfAllEnded()
            default:
                break
            }
            applyTransform()
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let host = hostView else { return }
            switch recognizer.state {
            case .began:
                beginAnchorIfNeeded(at: recognizer.location(in: host))
                liveScale = recognizer.scale
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .changed:
                guard recognizer.numberOfTouches >= 2 else { return }
                liveScale = recognizer.scale
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .ended, .cancelled:
                commitLiveTransformIfAllEnded()
            default:
                break
            }
            applyTransform()
        }

        @objc func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            guard let host = hostView else { return }
            switch recognizer.state {
            case .began:
                beginAnchorIfNeeded(at: recognizer.location(in: host))
                liveRotation = recognizer.rotation
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .changed:
                guard recognizer.numberOfTouches >= 2 else { return }
                liveRotation = recognizer.rotation
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .ended, .cancelled:
                commitLiveTransformIfAllEnded()
            default:
                break
            }
            applyTransform()
        }

        @objc func handleTwoFingerTap() {
            canvasManager.undo()
        }

        @objc func handleThreeFingerTap() {
            canvasManager.redo()
        }

        @objc func handleFillTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let container = containerView else { return }
            // container's bounds are exactly canvasSize (see hostBoundsDidChange), so location(in:)
            // already yields canvas-pixel coordinates — the same top-left-origin space FloodFillEngine
            // and the onion-skin/thumbnail renderers use.
            let point = recognizer.location(in: container)
            canvasManager.performFill(at: point)
        }

    }
}
