import SwiftUI
import PencilKit
import UIKit

private extension Color {
    /// Extracts explicit RGBA components and rebuilds a plain, non-dynamic UIColor, rather than
    /// handing PKInkingTool a `UIColor(Color)` conversion resolved through whatever trait collection
    /// happens to be current when this UIKit-side coordinator method runs (outside of a SwiftUI body
    /// evaluation, so there's no guarantee it resolves against the same appearance the swatch preview
    /// used) — this guarantees the ink color always matches exactly what was picked.
    func resolvedUIColor(opacity: Double) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r, green: g, blue: b, alpha: a * CGFloat(opacity))
    }
}

/// A PKCanvasView with its own private undo stack, so switching which
/// layer/frame is active doesn't corrupt PencilKit's undo history.
final class TrackedCanvasView: PKCanvasView {
    let localUndoManager = UndoManager()
    var layerID: UUID?

    override var undoManager: UndoManager? { localUndoManager }
}

/// One slot in the layer stack: an optional static image (for photo layers)
/// underneath a drawable PencilKit canvas.
final class LayerHostView: UIView {
    let imageView = UIImageView()
    /// Raster content "baked" into this layer's active cel by a select/move/fill/clear operation
    /// (see `Cel.bakedImage`), or the transient "hole" preview while that cel's content is lifted
    /// into a floating piece. Sits below `canvasView`'s live strokes, above `imageView`.
    let bakedImageView = UIImageView()
    let canvasView = TrackedCanvasView()

    init() {
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        bakedImageView.isUserInteractionEnabled = false
        bakedImageView.isHidden = true
        bakedImageView.translatesAutoresizingMaskIntoConstraints = false

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(bakedImageView)
        addSubview(canvasView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bakedImageView.topAnchor.constraint(equalTo: topAnchor),
            bakedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bakedImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bakedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor)
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
        container.addSubview(onionSkin)

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
        context.coordinator.selectionOverlay = selectionOverlay
        context.coordinator.floatingOverlay = floatingOverlay
        context.coordinator.setUpGestures(on: container)

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
        context.coordinator.updateSelectionOverlay()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.hostBoundsDidChange()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(canvasManager: canvasManager)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var canvasManager: CanvasManager

        weak var hostView: CanvasHostView?
        weak var containerView: UIView?
        weak var onionSkinView: UIImageView?
        weak var paperView: UIView?
        weak var selectionOverlay: SelectionOverlayView?
        weak var floatingOverlay: FloatingPieceOverlayView?
        var activePanel: ActivePanel = .none
        var layerHosts: [UUID: LayerHostView] = [:]

        weak var panRecognizer: UIPanGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var rotationRecognizer: UIRotationGestureRecognizer?

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

        /// Guards against reassigning PKCanvasView.tool on every SwiftUI re-render. Reassigning the
        /// tool mid-stroke (canvasViewDrawingDidChange fires on every point of an in-progress stroke)
        /// corrupts PencilKit's in-flight stroke capture, producing dropped/garbled strokes.
        private struct AppliedTool: Equatable {
            let tool: Tool
            let color: Color
            let size: CGFloat
            let opacity: Double
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
                host.canvasView.delegate = self
                host.canvasView.layerID = layer.id
                host.canvasView.isScrollEnabled = false
                host.canvasView.panGestureRecognizer.isEnabled = false
                host.canvasView.pinchGestureRecognizer?.isEnabled = false

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

            let policy: PKCanvasViewDrawingPolicy = canvasManager.pencilOnlyDrawing ? .pencilOnly : .anyInput

            for (index, layer) in canvasManager.layers.enumerated() {
                guard let host = layerHosts[layer.id] else { continue }
                if host.canvasView.drawingPolicy != policy {
                    host.canvasView.drawingPolicy = policy
                }
                if host.isHidden != !layer.isVisible { host.isHidden = !layer.isVisible }
                let targetAlpha = CGFloat(layer.opacity)
                if host.alpha != targetAlpha { host.alpha = targetAlpha }
                if host.imageView.image !== layer.backgroundImage { host.imageView.image = layer.backgroundImage }
                if host.imageView.isHidden != !layer.isImageLayer { host.imageView.isHidden = !layer.isImageLayer }

                let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame)

                let displayedBaked = bakedImageToDisplay(layerIndex: index, celIndex: celIdx)
                if host.bakedImageView.image !== displayedBaked { host.bakedImageView.image = displayedBaked }
                let bakedHidden = displayedBaked == nil
                if host.bakedImageView.isHidden != bakedHidden { host.bakedImageView.isHidden = bakedHidden }

                // While this cel's content is floating (lifted into a Move piece), its live strokes
                // are hidden — the "hole" is shown via bakedImageView's remainder preview instead —
                // so the lifted content doesn't render twice (once floating, once still in place).
                // Hiding the view, rather than reassigning canvasView.drawing to an empty PKDrawing,
                // is deliberate: reassigning .drawing fires canvasViewDrawingDidChange, which writes
                // the (now-empty) drawing back into the model's @Published `layers` — and because two
                // separately-constructed empty PKDrawing values don't compare equal, that write never
                // stabilizes, so every render re-triggers another one. An infinite render loop (SwiftUI
                // and PencilKit's delegate callback re-triggering each other) was observed from exactly
                // this pattern. Hiding the subview sidesteps PKDrawing entirely.
                let isFloatingSource = isFloatingMoveSource(layerIndex: index, celIndex: celIdx)
                if host.canvasView.isHidden != isFloatingSource {
                    host.canvasView.isHidden = isFloatingSource
                }
                if !isFloatingSource {
                    let targetDrawing = celIdx.map { canvasManager.layers[index].cels[$0].drawing } ?? PKDrawing()
                    if host.canvasView.drawing != targetDrawing {
                        host.canvasView.drawing = targetDrawing
                    }
                }
                // Disabling only canvasView.isUserInteractionEnabled isn't enough: each LayerHostView
                // fully covers the container and stacks as a sibling, so an inactive host still
                // swallows touches via UIView's default hitTest (which returns the host itself once
                // its non-interactive subviews all reject the point), preventing the touch from ever
                // reaching an active layer underneath. Disabling the host itself lets hit-testing
                // fall through to the next layer down.
                // Select/Move take over touch handling entirely while engaged (via SelectionOverlayView/
                // FloatingPieceOverlayView, both above the whole layer stack), so drawing is disabled then too.
                let shouldInteract = (index == canvasManager.currentLayerIndex) && celIdx != nil
                    && activePanel != .select && canvasManager.floatingPiece == nil
                if host.isUserInteractionEnabled != shouldInteract {
                    host.isUserInteractionEnabled = shouldInteract
                }
                if host.canvasView.isUserInteractionEnabled != shouldInteract {
                    host.canvasView.isUserInteractionEnabled = shouldInteract
                }
            }
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
                host.canvasView.undoManager?.removeAllActions()
                lastActiveKey = activeKey
            }
            canvasManager.activeUndoManager = host.canvasView.undoManager
            canvasManager.refreshUndoRedoState()

            // Only construct+assign a new tool when something tool-relevant actually changed.
            // Reassigning PKCanvasView.tool mid-stroke (this method runs on every SwiftUI re-render,
            // and a re-render happens on every point of an in-progress stroke) corrupts PencilKit's
            // in-flight stroke capture, which is what caused strokes to drop or render as garbage.
            let desired = AppliedTool(tool: canvasManager.selectedTool, color: canvasManager.brushColor, size: canvasManager.brushSize, opacity: canvasManager.brushOpacity)
            guard lastAppliedTool[layer.id] != desired else { return }
            lastAppliedTool[layer.id] = desired

            let color = canvasManager.brushColor.resolvedUIColor(opacity: canvasManager.brushOpacity)
            switch canvasManager.selectedTool {
            case .pen:
                host.canvasView.tool = PKInkingTool(.pen, color: color, width: canvasManager.brushSize)
            case .pencil:
                host.canvasView.tool = PKInkingTool(.pencil, color: color, width: canvasManager.brushSize)
            case .eraser:
                host.canvasView.tool = PKEraserTool(.bitmap, width: canvasManager.brushSize)
            }
        }

        func updateOnionSkin() {
            guard let onionSkinView, let canvasSize = canvasManager.canvasSize else { return }
            guard canvasManager.isOnionSkinEnabled,
                  canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
                  let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame - 1) else {
                onionSkinView.isHidden = true
                return
            }

            let drawing = canvasManager.layers[canvasManager.currentLayerIndex].cels[celIdx].drawing
            onionSkinView.image = drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: 1.0)
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
            // (e.g. every point of an in-progress stroke), which could otherwise perturb PencilKit's
            // active touch tracking.
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
            return otherGestureRecognizer === activeHost.canvasView.drawingGestureRecognizer
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

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let tracked = canvasView as? TrackedCanvasView, let layerID = tracked.layerID,
                  let layerIndex = canvasManager.layers.firstIndex(where: { $0.id == layerID }),
                  let celIndex = canvasManager.activeCelIndex(inLayer: layerIndex, atFrame: canvasManager.currentFrame) else { return }
            canvasManager.updateCelDrawing(layerIndex: layerIndex, celIndex: celIndex, drawing: canvasView.drawing)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            guard let tracked = canvasView as? TrackedCanvasView, let layerID = tracked.layerID,
                  let layerIndex = canvasManager.layers.firstIndex(where: { $0.id == layerID }),
                  let celIndex = canvasManager.activeCelIndex(inLayer: layerIndex, atFrame: canvasManager.currentFrame) else { return }
            canvasManager.strokeEnded(layerIndex: layerIndex, celIndex: celIndex)
            canvasManager.refreshUndoRedoState()
        }
    }
}
