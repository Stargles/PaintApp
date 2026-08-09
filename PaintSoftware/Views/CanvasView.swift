import SwiftUI
import UIKit
import Combine

struct CanvasView: UIViewRepresentable {
    @ObservedObject var canvasManager: CanvasManager
    var activePanel: ActivePanel = .none

    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.isAccessibilityElement = true
        host.accessibilityIdentifier = "canvas.host"
        host.canvasManager = canvasManager

        let container = UIView()
        container.backgroundColor = .clear
        host.addSubview(container)

        // Light-grey backing for the drawable padding margin: shows through wherever the paper is
        // inset by `canvasPadding`. Never seen at padding 0.
        let paddingBackdrop = UIView()
        paddingBackdrop.backgroundColor = UIColor(white: 0.85, alpha: 1)
        paddingBackdrop.isUserInteractionEnabled = false
        paddingBackdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(paddingBackdrop)

        let paper = UIView()
        paper.backgroundColor = .white
        paper.isUserInteractionEnabled = false
        paper.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(paper)

        let onionSkin = UIImageView()
        onionSkin.contentMode = .scaleAspectFit
        onionSkin.isUserInteractionEnabled = false
        onionSkin.translatesAutoresizingMaskIntoConstraints = false
        // Deliberately left on the default bilinear filter — nearest-neighbor made the onion-skin
        // ghost render as a distractingly pixelated overlay instead of a soft reference.
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

        let shapeOverlay = ShapeOverlayView()
        shapeOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(shapeOverlay)
        context.coordinator.shapeOverlay = shapeOverlay

        // Above everything, including the shape overlay: a guide annotates the whole frame. It
        // claims only its own handle hitboxes, so being topmost costs a shape handle only where
        // the two coincide — and the two are never both live, since guides need interpolate mode.
        let guideOverlay = GuideOverlayView()
        guideOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(guideOverlay)
        context.coordinator.guideOverlay = guideOverlay
        guideOverlay.onGripDragBegan = { [weak coordinator = context.coordinator] id, editing in
            guard let manager = coordinator?.canvasManager else { return }
            switch editing {
            case .handles: manager.beginGuideHandleDrag(guideID: id)
            case .spacing: manager.beginGuideSpacingDrag(guideID: id)
            case .none: break
            }
        }
        guideOverlay.onGripDragged = { [weak coordinator = context.coordinator] id, editing, index, point in
            guard let manager = coordinator?.canvasManager else { return }
            switch editing {
            case .handles:
                manager.dragGuideHandle(sampleIndex: index, to: point)
            case .spacing:
                // The chart wants a position along the guide, so the drag is projected onto the
                // path — keeps `GuideOverlayView` free of geometry.
                guard let guide = manager.guideStrokes.first(where: { $0.id == id }),
                      let path = GuidePath(samples: guide.samples) else { return }
                manager.dragGuideSpacingStop(index: index, to: path.arcFraction(nearest: point))
            case .none:
                break
            }
        }
        guideOverlay.onGripDragEnded = { [weak coordinator = context.coordinator] editing in
            guard let manager = coordinator?.canvasManager else { return }
            switch editing {
            case .handles: manager.commitGuideHandleDrag()
            case .spacing: manager.commitGuideSpacingDrag()
            case .none: break
            }
        }
        guideOverlay.onGripDragCancelled = { [weak coordinator = context.coordinator] editing in
            guard let manager = coordinator?.canvasManager else { return }
            switch editing {
            case .handles: manager.cancelGuideHandleDrag()
            case .spacing: manager.cancelGuideSpacingDrag()
            case .none: break
            }
        }

        // Paper is inset by `canvasPadding` on each side; positive top/leading, negative
        // bottom/trailing so a larger padding shrinks the paper inward, revealing the grey margin.
        let paperTop = paper.topAnchor.constraint(equalTo: container.topAnchor)
        let paperBottom = paper.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        let paperLeading = paper.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        let paperTrailing = paper.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        context.coordinator.paperInsetConstraints = (top: paperTop, bottom: paperBottom, leading: paperLeading, trailing: paperTrailing)

        NSLayoutConstraint.activate([
            paddingBackdrop.topAnchor.constraint(equalTo: container.topAnchor),
            paddingBackdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            paddingBackdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            paddingBackdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            paperTop, paperBottom, paperLeading, paperTrailing,
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
            floatingOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shapeOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            shapeOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            shapeOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shapeOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            guideOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            guideOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            guideOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            guideOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
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
        // One undo step per whole move/scale/rotate drag, not per intermediate value — see
        // `CanvasManager.beginStructureGesture`'s doc comment. (Covers object-layer transforms;
        // vector-layer whole-layer transforms mutate `VectorCanvas` in place and aren't captured
        // by this value-based snapshot — pre-existing gap, not introduced here.)
        transformOverlay.onGestureBegan = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.beginStructureGesture()
        }
        transformOverlay.onGestureEnded = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.commitStructureGesture(name: "Transform")
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
        shapeOverlay.onEndpointDragged = { [weak coordinator = context.coordinator] point, endpoint in
            guard let coordinator else { return }
            switch endpoint {
            case .start: coordinator.canvasManager.updateInteractiveShape(startPoint: point)
            case .end: coordinator.canvasManager.updateInteractiveShape(endPoint: point)
            }
            coordinator.updateShapeOverlay()
        }
        shapeOverlay.onRotationDragged = { [weak coordinator = context.coordinator] rotation in
            guard let coordinator else { return }
            coordinator.canvasManager.updateInteractiveShape(rotation: rotation)
            coordinator.updateShapeOverlay()
        }
        // Both handle drags are pure geometry — see `ShapeGeometry.draggingCorner`/`draggingEdge`.
        // The whole resulting geometry is written back either way.
        shapeOverlay.onCornerDragged = { [weak coordinator = context.coordinator] point, corner in
            guard let coordinator, let shape = coordinator.canvasManager.activeShape else { return }
            coordinator.applyShapeDrag(shape.draggingCorner(corner, to: point))
        }
        shapeOverlay.onEdgeDragged = { [weak coordinator = context.coordinator] point, edge in
            guard let coordinator, let shape = coordinator.canvasManager.activeShape else { return }
            coordinator.applyShapeDrag(shape.draggingEdge(edge, to: point))
        }

        host.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.hostBoundsDidChange()
        }

        context.coordinator.activePanel = activePanel
        context.coordinator.reconcileLayers()
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateSelectionOverlay()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.updateShapeOverlay()
        context.coordinator.hostBoundsDidChange()

        return host
    }

    func updateUIView(_ uiView: CanvasHostView, context: Context) {
        context.coordinator.activePanel = activePanel
        context.coordinator.updatePaper()
        context.coordinator.reconcileLayers()
        context.coordinator.updateActiveLayerAndTool()
        context.coordinator.updateInterpolationPreviews()
        context.coordinator.updateGuideOverlay()
        context.coordinator.updateOnionSkin()
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateSelectionOverlay()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.updateShapeOverlay()
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
        weak var guideOverlay: GuideOverlayView?
        /// The guide under the pen right now, pushed up from `StrokeCanvasView` per sample. Held here
        /// so `updateGuideOverlay` stays a pure function of coordinator state.
        private var liveGuidePoints: [CGPoint] = []
        var onionSkinSource: OnionSkinSource = PreviousCelOnionSkinSource()
        weak var paperView: UIView?
        /// The four constraints pinning the paper to the container; constants are the
        /// `canvasPadding` inset on each side.
        var paperInsetConstraints: (top: NSLayoutConstraint, bottom: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint)?
        weak var transformOverlay: ObjectTransformOverlayView?
        weak var selectionOverlay: SelectionOverlayView?
        weak var floatingOverlay: FloatingPieceOverlayView?
        var activePanel: ActivePanel = .none
        var layerHosts: [UUID: LayerHostView] = [:]

        weak var panRecognizer: UIPanGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var rotationRecognizer: UIRotationGestureRecognizer?
        weak var fillTapRecognizer: UILongPressGestureRecognizer?
        /// Enabled when there are no layers or the active layer is hidden, so a drawing-tool touch
        /// triggers a user-facing alert instead of being silently swallowed.
        weak var catchAllTapRecognizer: UILongPressGestureRecognizer?
        /// Counts live canvas touches — engages the shape constraint snap whenever a second is down.
        weak var touchCountRecognizer: TouchCountRecognizer?

        // Smart-shape overlay and detection state
        weak var shapeOverlay: ShapeOverlayView?
        /// True while the two-finger snap constraint is engaged. Owned here rather than by the
        /// overlay, since the engaging touches usually land on the canvas, not the overlay.
        private(set) var isShapeConstraintEngaged = false
        /// Debounces the snap so a quick two-finger tap-undo doesn't flash a snapped shape.
        private var shapeConstraintTimer: Timer?
        private static let shapeConstraintDelay: TimeInterval = 0.12
        /// See `scheduleShapePreviewRenderIfNeeded`.
        private var isShapePreviewRenderScheduled = false
        /// Accumulated canvas-space stroke samples from the current stroke, for shape detection.
        private var shapeDetectionSamples: [VectorSample] = []
        /// Fires after the user holds the finger still for ~1s — triggers shape detection.
        private var shapeHoldTimer: Timer?
        private var shapeDetectionActive = false
        /// The stroke view that started the current detection stroke, to revert on shape found.
        private weak var shapeDetectionHost: LayerHostView?
        // Interactive-fill drag state, captured at press-down. The drag is horizontal-only — its
        // rightward travel raises whichever setting is currently selected, relative to these baselines.
        private var fillDragStartHost: CGPoint?
        private var fillDragStartGap: CGFloat = 0
        private var fillDragStartThreshold: CGFloat = 0
        private var fillDragStartEdge: CGFloat = 0

        /// Finger travel that sweeps a fill setting across its whole slider range. Generous so fine
        /// adjustments are easy; clamped in CanvasManager.
        private static let fillDragSweepPoints: CGFloat = 320

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

        /// Guards against reassigning the stroke view's tool settings on every SwiftUI re-render,
        /// including mid-stroke ones.
        private struct AppliedTool: Equatable {
            let tool: Tool
            let color: Color
            let size: CGFloat
            let opacity: Double
            let brush: Brush
            /// Must be in the cache key: without it, changing eraser mode leaves every other field
            /// equal and the guard silently does nothing.
            let vectorEraserMode: VectorEraserMode
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
            // Inset the paper to the artwork rect; the grey backdrop shows through the margin.
            if let c = paperInsetConstraints {
                let p = canvasManager.canvasPadding
                if c.top.constant != p { c.top.constant = p }
                if c.leading.constant != p { c.leading.constant = p }
                if c.bottom.constant != -p { c.bottom.constant = -p }
                if c.trailing.constant != -p { c.trailing.constant = -p }
            }
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
                host.strokeView.canvasManager = canvasManager
                // Live guide feedback goes straight to the overlay, not through SwiftUI state — a
                // `@Published` write per touch sample would re-run every view body for the drag.
                host.strokeView.guideOverlayNeedsUpdate = { [weak self] samples in
                    guard let self else { return }
                    self.liveGuidePoints = samples.map(\.point)
                    self.updateGuideOverlay()
                }
                host.strokeView.onStrokeBegan = { [weak self, weak host] in
                    guard let self else { return }
                    // A stroke is a canvas edit, so any adjustable fill/shape bakes before this one
                    // changes a pixel: they become older undo steps, and this stroke's undo
                    // snapshot (taken after this returns) includes the baked content. This is also
                    // what lets drawing straight over a pending shape work in one touch — the first
                    // touch bakes the shape and then goes on to draw.
                    self.commitTransientsAndRefresh()
                    if let host { self.startShapeDetection(host: host) }
                }
                host.strokeView.onStrokeCancelled = { [weak self] in
                    self?.cancelShapeDetection()
                    self?.canvasManager.refreshUndoRedoState()
                }
                // A second finger during shape following means "snap", not "pan" — keep the pen.
                host.strokeView.strokeRecognizer.shouldIgnoreAdditionalTouches = { [weak self] in
                    self?.canvasManager.isShapeFollowingFinger ?? false
                }
                host.strokeView.onStrokeMoved = { [weak self, weak host] sample in
                    guard let self else { return }
                    if self.canvasManager.isShapeFollowingFinger {
                        // For lines, just move the endpoint. For rects & ovals, the finger angle
                        // sets rotation and the distance sets a uniform scale from centre — see
                        // `ShapeGeometry.following(_:from:)`.
                        let point = sample.point
                        if case .line? = self.canvasManager.activeShape?.kind {
                            self.canvasManager.updateInteractiveShape(endPoint: point)
                        } else if let shape = self.canvasManager.activeShape {
                            let frame = self.shapeFollowFrame ?? shape.followFrame(startingAt: point)
                            self.shapeFollowFrame = frame
                            self.applyShapeDrag(shape.following(point, from: frame), refreshOverlay: false)
                        }
                        self.updateShapeOverlay()
                    } else {
                        self.handleStrokeMoved(sample, host: host)
                    }
                }
                host.strokeView.strokeRecognizer.onAnyTouchBegan = { [weak self] in
                    // Touching the canvas at all dismisses whatever top-bar dropdown is open.
                    self?.canvasManager.interactionBegan.send()
                }
                host.strokeView.onStrokeEnded = { [weak self, weak host] in
                    guard let self else { return }
                    self.canvasManager.refreshUndoRedoState()
                    self.cancelShapeDetection()
                    // If the shape was being followed, lift transitions it to adjustable state; no
                    // stroke was committed (it was reverted), so skip the normal stroke-end path.
                    if self.canvasManager.shapeGestureActive {
                        self.canvasManager.endInteractiveShape()
                        self.updateShapeOverlay()
                        return
                    }
                    guard let host, let layerID = host.strokeView.layerID,
                          let layerIndex = self.canvasManager.layers.firstIndex(where: { $0.id == layerID }),
                          let celIndex = self.canvasManager.activeCelIndex(inLayer: layerIndex, atFrame: self.canvasManager.currentFrame) else { return }
                    self.canvasManager.strokeEnded(layerIndex: layerIndex, celIndex: celIndex)
                    self.updateShapeOverlay()
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

                let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame)

                let displayedBaked = bakedImageToDisplay(layerIndex: index, celIndex: celIdx)
                if host.bakedImageView.image !== displayedBaked { host.bakedImageView.image = displayedBaked }
                let bakedHidden = displayedBaked == nil
                if host.bakedImageView.isHidden != bakedHidden { host.bakedImageView.isHidden = bakedHidden }

                // While this cel's content is floating (lifted into a Move piece), its live strokes
                // are hidden so the content doesn't render twice.
                let isFloatingSource = isFloatingMoveSource(layerIndex: index, celIndex: celIdx)
                if host.strokeView.isHidden != isFloatingSource {
                    host.strokeView.isHidden = isFloatingSource
                }
                if !isFloatingSource {
                    let targetRaster = celIdx.map { canvasManager.layers[index].cels[$0].raster }
                    if host.strokeView.raster !== targetRaster {
                        host.strokeView.raster = targetRaster
                    }
                    // Vector layers route drawing into their VectorCanvas instead of the raster.
                    let targetVector = celIdx.flatMap { canvasManager.layers[index].cels[$0].vector }
                    if host.strokeView.vectorCanvas !== targetVector {
                        host.strokeView.vectorCanvas = targetVector
                    } else {
                        // Same instance, but may have been mutated in place; version check brings
                        // the display back in sync. See `displayedRasterVersion`.
                        host.strokeView.refreshDisplayIfStale()
                    }
                }
                let targetFillImage = celIdx.flatMap { canvasManager.layers[index].cels[$0].fillImage }
                if host.fillImageView.image !== targetFillImage {
                    host.fillImageView.image = targetFillImage
                }
                // Disabling only strokeView.isUserInteractionEnabled isn't enough: each LayerHostView
                // fully covers the container, so an inactive host still swallows touches via UIView's
                // default hitTest, blocking an active layer underneath. Disabling the host itself
                // lets hit-testing fall through. Select/Move also disable drawing while engaged.
                let shouldInteract = (index == canvasManager.currentLayerIndex) && celIdx != nil
                    && canvasManager.selectedTool != .fill
                    && activePanel != .select && canvasManager.floatingPiece == nil
                    && !(canvasManager.isVectorTransforming && layer.kind == .vector)
                if host.isUserInteractionEnabled != shouldInteract {
                    host.isUserInteractionEnabled = shouldInteract
                }
                if host.strokeView.isUserInteractionEnabled != shouldInteract {
                    host.strokeView.isUserInteractionEnabled = shouldInteract
                }
            }

            // Enable the catch-all gesture when no layers exist or the active layer is hidden.
            let needsCatch: Bool
            if canvasManager.layers.isEmpty {
                needsCatch = true
            } else if canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) {
                needsCatch = !canvasManager.layers[canvasManager.currentLayerIndex].isVisible
            } else {
                needsCatch = false
            }
            if catchAllTapRecognizer?.isEnabled != needsCatch {
                catchAllTapRecognizer?.isEnabled = needsCatch
            }
        }

        // MARK: - Vector-layer transform overlay

        /// Drives `ObjectTransformOverlayView` from the active vector layer's aggregate transform
        /// while `isVectorTransforming` is on — the only remaining user of this overlay.
        func updateTransformOverlay() {
            guard let overlay = transformOverlay, let container = containerView else { return }
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else {
                overlay.isHidden = true
                return
            }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]

            // Vector layer being transformed: box just the layer's own content, in local space, so
            // Move only carries the drawn content, matching the raster Move tool. Also checks
            // `activeCelIsInBetween` since the playhead can move onto an interpolated cel while the
            // transform is already on, where the box would be handles over a frame it can't move.
            if layer.kind == .vector, layer.isVisible, canvasManager.isVectorTransforming,
               !canvasManager.activeCelIsInBetween,
               let canvasSize = canvasManager.canvasSize,
               let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame),
               let vector = canvasManager.layers[canvasManager.currentLayerIndex].cels[celIdx].vector {
                let localBounds = vector.localContentBounds() ?? CGRect(origin: .zero, size: canvasSize)
                let pivot = CGPoint(x: localBounds.midX, y: localBounds.midY)
                overlay.update(transform: vector.layerTransform(pivot: pivot), imageSize: localBounds.size)
                container.bringSubviewToFront(overlay)
                return
            }

            overlay.isHidden = true
        }

        func objectTransformChanged(_ transform: LayerTransform) {
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return }
            let index = canvasManager.currentLayerIndex
            guard canvasManager.isVectorTransforming, canvasManager.layers[index].kind == .vector,
                  !canvasManager.activeCelIsInBetween,
                  let canvasSize = canvasManager.canvasSize,
                  let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame),
                  let vector = canvasManager.layers[index].cels[celIdx].vector else { return }
            // Same pivot `updateTransformOverlay` handed the overlay: the content's local bounding
            // box center, fixed for the gesture.
            let localBounds = vector.localContentBounds() ?? CGRect(origin: .zero, size: canvasSize)
            let pivot = CGPoint(x: localBounds.midX, y: localBounds.midY)
            canvasManager.setVectorTransform(transform, layerIndex: index, pivot: pivot)
            // VectorCanvas is a reference type mutated in place, so refresh its host directly.
            let layerID = canvasManager.layers[index].id
            layerHosts[layerID]?.strokeView.refreshDisplay()
        }

        /// What a layer's `bakedImageView` should show: the real `bakedImage`, or — while that cel's
        /// content is lifted into a Move piece — the transient "hole" preview computed at lift time.
        private func bakedImageToDisplay(layerIndex: Int, celIndex: Int?) -> UIImage? {
            guard let celIndex else { return nil }
            if let piece = canvasManager.floatingPiece, piece.kind == .move,
               canvasManager.layers[layerIndex].id == piece.sourceLayerID,
               canvasManager.layers[layerIndex].cels[celIndex].id == piece.sourceCelID {
                return piece.remainderPreview
            }
            return canvasManager.layers[layerIndex].cels[celIndex].bakedImage
        }

        private func isFloatingMoveSource(layerIndex: Int, celIndex: Int?) -> Bool {
            guard let celIndex, let piece = canvasManager.floatingPiece, piece.kind == .move else { return false }
            return canvasManager.layers[layerIndex].id == piece.sourceLayerID
                && canvasManager.layers[layerIndex].cels[celIndex].id == piece.sourceCelID
        }

        // MARK: - Select & Move overlays

        func updateSelectionOverlay() {
            guard let overlay = selectionOverlay, let container = containerView else { return }
            overlay.mode = canvasManager.selectionMode
            overlay.isCapturingGestures = (activePanel == .select) && (canvasManager.floatingPiece == nil)
            overlay.updateSelection(canvasManager.selection, allowsOutsideInteraction: canvasManager.allowsPaintingOutsideSelection)
            // Layer hosts are added after this overlay, so without this the marching ants/hatch
            // render underneath layer content — bring it back to front when it has something to show.
            if overlay.isCapturingGestures || canvasManager.selection != nil {
                container.bringSubviewToFront(overlay)
            }
        }

        func updateFloatingOverlay() {
            floatingOverlay?.update(canvasManager.floatingPiece)
            guard let overlay = floatingOverlay, let container = containerView else { return }

            // A piece lifted by the Move tool still belongs to its source layer, so it renders in
            // that layer's stack position rather than floating above everything above it. Every
            // other case puts it back at the front, or the overlay would stay wedged below.
            if let piece = canvasManager.floatingPiece, piece.kind == .move,
               let sourceIndex = canvasManager.layers.firstIndex(where: { $0.id == piece.sourceLayerID }),
               sourceIndex + 1 < canvasManager.layers.count,
               let hostAbove = layerHosts[canvasManager.layers[sourceIndex + 1].id] {
                container.insertSubview(overlay, belowSubview: hostAbove)
            } else {
                container.bringSubviewToFront(overlay)
            }
        }

        func updateShapeOverlay() {
            guard let overlay = shapeOverlay, let container = containerView else { return }
            guard canvasManager.shapeGestureActive, let shape = canvasManager.resolvedShape else {
                overlay.isActive = false
                return
            }
            let isAdjustable = canvasManager.isShapeInAdjustableState
            overlay.isActive = true
            // Render inline the first time so the shape isn't invisible for a frame; the
            // coalescing below carries subsequent renders.
            if canvasManager.activeShapePreviewImage == nil { canvasManager.renderActiveShapePreview() }
            overlay.update(shape: shape,
                           previewImage: canvasManager.activeShapePreviewImage,
                           showHandles: isAdjustable)
            scheduleShapePreviewRenderIfNeeded()
            // Above every layer host so it's visible and hit-testable; interaction is disabled
            // during shape following so touches pass through to the stroke view instead.
            container.bringSubviewToFront(overlay)
            overlay.isUserInteractionEnabled = isAdjustable
        }

        /// Coalesces preview re-renders to one per run-loop turn — a Pencil delivers several coalesced
        /// samples per frame, and re-stamping a canvas-sized preview per sample costs far more than
        /// the frame of lag this trades for. Feeds the overlay directly to avoid re-scheduling itself.
        private func scheduleShapePreviewRenderIfNeeded() {
            guard canvasManager.isActiveShapePreviewStale, !isShapePreviewRenderScheduled else { return }
            isShapePreviewRenderScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isShapePreviewRenderScheduled = false
                guard self.canvasManager.shapeGestureActive else { return }
                self.canvasManager.renderActiveShapePreview()
                self.shapeOverlay?.setPreviewImage(self.canvasManager.activeShapePreviewImage)
            }
        }

        /// Repaints every layer host whose backing content has drifted from what it last rendered.
        /// The synchronous form of `reconcileLayers`' per-pass version, needed for the moment a
        /// transient bakes so the baked pixels don't flicker in a pass later.
        func syncLayerDisplays() {
            for host in layerHosts.values {
                host.strokeView.refreshDisplayIfStale()
            }
        }

        /// Bakes whatever is transient (shape or fill) and brings the canvas back in sync in the
        /// same turn — the entry point for every path that ends shape editing.
        func commitTransientsAndRefresh() {
            canvasManager.beginCanvasEdit()
            syncLayerDisplays()
            updateShapeOverlay()
            // Nothing pending, so the snap has nothing left to constrain.
            if !canvasManager.shapeGestureActive {
                shapeConstraintTimer?.invalidate()
                shapeConstraintTimer = nil
                isShapeConstraintEngaged = false
            }
        }

        func updateActiveLayerAndTool() {
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard let host = layerHosts[layer.id] else { return }

            // Not per-layer, so it lives outside the AppliedTool caching guard below and stays in
            // sync every call. Suspended while Select is engaged or a piece is floating, so the fill
            // tool's press can't race the Selection/Move overlays' own gestures.
            fillTapRecognizer?.isEnabled = (canvasManager.selectedTool == .fill)
                && activePanel != .select && canvasManager.floatingPiece == nil

            // Also outside the AppliedTool guard: toggling "paint outside selection" doesn't touch
            // any of that struct's fields. Only applies to the layer/cel the selection belongs to.
            let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame)
            let celID = celIdx.map { layer.cels[$0].id }
            if let selection = canvasManager.selection, !canvasManager.allowsPaintingOutsideSelection,
               selection.layerID == layer.id, selection.celID == celID {
                host.strokeView.selectionClipPath = selection.path
            } else {
                host.strokeView.selectionClipPath = nil
            }

            // Eraser gets its own brush/size/opacity, separate from the paint brush's.
            let isEraser = canvasManager.selectedTool == .eraser
            let activeSize = isEraser ? canvasManager.eraserSize : canvasManager.brushSize
            let activeOpacity = isEraser ? canvasManager.eraserOpacity : canvasManager.brushOpacity
            let activeBrush = isEraser ? canvasManager.selectedEraserBrush : canvasManager.selectedBrush

            // Only push new tool settings when something tool-relevant actually changed.
            let desired = AppliedTool(tool: canvasManager.selectedTool, color: canvasManager.brushColor, size: activeSize, opacity: activeOpacity, brush: activeBrush, vectorEraserMode: canvasManager.vectorEraserMode)
            guard lastAppliedTool[layer.id] != desired else { return }
            lastAppliedTool[layer.id] = desired

            host.strokeView.brushColor = canvasManager.brushColor.resolvedUIColor(opacity: 1)
            host.strokeView.brushSize = activeSize
            host.strokeView.brushOpacity = activeOpacity
            host.strokeView.brush = activeBrush
            host.strokeView.isEraser = isEraser
            host.strokeView.vectorEraserMode = canvasManager.vectorEraserMode
            // .fill is handled by fillTapRecognizer, not the stroke view.
        }

        /// What an interpolated frame's pixels depend on. Recomputing only when this changes makes
        /// the preview affordable: `updateUIView` runs every SwiftUI pass, and evaluating a recipe is
        /// two lattice embeddings, an ARAP solve and two canvas-sized renders. Reference-canvas
        /// versions are in the key so editing a keyframe updates its in-betweens for free.
        private struct InterpolationPreviewKey: Equatable {
            let celID: UUID
            let t: CGFloat
            let preview: Bool
            /// True for the tinted group overlay rather than an in-between; the two share this
            /// dictionary so the key has to keep them apart.
            let overlay: Bool
            let thicknessFade: Bool
            /// Solo/mute state — an evaluation input, so it must be in the key.
            let hiddenGroups: Set<UUID>
            let referenceVersions: [Int]
            /// The recipe's local edits, by identity. No version number covers this: an edit at an
            /// in-between changes the recipe on the `Cel`, not a `VectorCanvas`. IDs rather than
            /// count, so undo/redo (remove/re-add the same edit) are told apart from a new one.
            let localEditIDs: [UUID]
            /// Guides live on `CanvasManager`, not any `VectorCanvas`, so no `referenceVersions`
            /// entry moves when one is edited — and `updateGuideStroke` keeps a guide's id on
            /// replace, so an id list wouldn't notice either. Compared by value instead.
            let guides: [GuideStroke]
        }
        private var interpolationPreviewKeys: [UUID: InterpolationPreviewKey] = [:]

        /// Renders each layer's interpolated frame, where it has one at the current frame, and clears
        /// it everywhere else. `.preview` quality while scrubbing, `.full` on release — cached in
        /// separate slots on `VectorCanvas` so switching doesn't throw the other away.
        func updateInterpolationPreviews() {
            for (layerIndex, layer) in canvasManager.layers.enumerated() {
                guard let host = layerHosts[layer.id] else { continue }
                guard let celIndex = canvasManager.activeCelIndex(inLayer: layerIndex,
                                                                  atFrame: canvasManager.currentFrame) else {
                    interpolationPreviewKeys.removeValue(forKey: layer.id)
                    host.strokeView.setInterpolationImage(nil)
                    continue
                }
                guard let recipe = layer.cels[celIndex].interpolation else {
                    // No recipe here, so this cel is a keyframe or ordinary drawing; the same seam
                    // carries the tinted motion-group overlay for it instead.
                    updateMotionGroupOverlay(layer: layer, celIndex: celIndex, host: host)
                    continue
                }
                let cel = layer.cels[celIndex]
                let key = InterpolationPreviewKey(
                    celID: cel.id,
                    t: recipe.t,
                    preview: canvasManager.isScrubbingInterpolation,
                    overlay: false,
                    thicknessFade: canvasManager.interpolationThicknessFade,
                    hiddenGroups: canvasManager.isInterpolateMode
                        ? canvasManager.hiddenMotionGroups : [],
                    referenceVersions: recipe.referencedCels.map { ref in
                        canvasManager.celIndices(forCel: ref.celID, inLayer: ref.layerID)
                            .flatMap { canvasManager.layers[$0.layer].cels[$0.cel].vector?.version } ?? -1
                    },
                    localEditIDs: recipe.localEdits.map(\.id),
                    guides: canvasManager.guides(driving: recipe))
                guard interpolationPreviewKeys[layer.id] != key else { continue }
                interpolationPreviewKeys[layer.id] = key
                host.strokeView.setInterpolationImage(
                    canvasManager.interpolatedImage(forCel: cel.id, inLayer: layer.id,
                                                    quality: key.preview ? .preview : .full))
            }
        }

        /// The tinted motion-group overlay, memoized on the same key as the in-between preview so an
        /// un-keyed render doesn't re-rasterise every keyframe on every SwiftUI pass. `t: 0` and
        /// `overlay: true` keep it from colliding with a preview key for the same cel; the cel's own
        /// `version` is what a retag moves.
        private func updateMotionGroupOverlay(layer: Layer, celIndex: Int, host: LayerHostView) {
            let cel = layer.cels[celIndex]
            guard canvasManager.isInterpolateMode, canvasManager.showMotionGroupOverlay,
                  let version = cel.vector?.version else {
                interpolationPreviewKeys.removeValue(forKey: layer.id)
                host.strokeView.setInterpolationImage(nil)
                return
            }
            let key = InterpolationPreviewKey(
                celID: cel.id, t: 0, preview: true, overlay: true,
                thicknessFade: false, hiddenGroups: [],
                referenceVersions: [version, canvasManager.motionGroups.count],
                localEditIDs: [], guides: [])
            guard interpolationPreviewKeys[layer.id] != key else { return }
            interpolationPreviewKeys[layer.id] = key
            host.strokeView.setInterpolationImage(
                canvasManager.motionGroupOverlayImage(forCel: cel.id, inLayer: layer.id))
        }

        /// The guide render pass — guides bound to the frame under the playhead, plus whatever is
        /// under the pen. Not memoized like `InterpolationPreviewKey`: this only sets two `CGPath`s,
        /// and `GuideOverlayView.update` does its own equality check. Grips show only while the
        /// Guide toggle is off — armed, every drag is a new guide with no exceptions.
        func updateGuideOverlay() {
            guard let guideOverlay else { return }
            let editing: GuideOverlayView.Editing =
                canvasManager.isDrawingGuide ? .none
                : canvasManager.isEditingGuideSpacing ? .spacing : .handles
            let guides = canvasManager.visibleGuideStrokes.map { guide in
                GuideOverlayView.Guide(id: guide.id,
                                       points: guide.samples.map(\.point),
                                       grips: grips(for: guide, editing: editing))
            }
            guideOverlay.update(guides: guides, live: liveGuidePoints, editing: editing)
            // Re-asserted every pass: `reconcileLayers` brings every layer host to front whenever
            // layer order changes, which puts hosts above this overlay. A transparent host still
            // lets the dashes show through visually while `hitTest` never reaches the handles.
            guideOverlay.superview?.bringSubviewToFront(guideOverlay)
        }

        /// A guide's grips for the active editor: sample-indexed shape handles, or the spacing
        /// chart's stops placed along the path. The chart's two end stops are the keyframes and
        /// aren't draggable, so they're dropped rather than drawn inert.
        private func grips(for guide: GuideStroke,
                           editing: GuideOverlayView.Editing) -> [GuideOverlayView.Guide.Grip] {
            switch editing {
            case .none:
                return []
            case .handles:
                return canvasManager.guideHandlePositions(for: guide).map {
                    GuideOverlayView.Guide.Grip(index: $0.sampleIndex, position: $0.position)
                }
            case .spacing:
                guard let chart = canvasManager.spacingChart(forGuide: guide.id),
                      let path = GuidePath(samples: guide.samples) else { return [] }
                let positions = chart.positions(on: path)
                return chart.draggable.map {
                    GuideOverlayView.Guide.Grip(index: $0, position: positions[$0])
                }
            }
        }

        func updateOnionSkin() {
            guard let onionSkinView else { return }
            guard canvasManager.isOnionSkinEnabled else {
                onionSkinView.isHidden = true
                return
            }
            // Interpolate mode wants the two reference keyframes rather than the previous cel.
            let source: OnionSkinSource = canvasManager.isInterpolateMode
                ? InterpolationReferenceOnionSkinSource()
                : onionSkinSource
            let frames = source.frames(for: canvasManager)
            guard !frames.isEmpty else {
                onionSkinView.isHidden = true
                return
            }

            onionSkinView.image = OnionSkinFrame.composite(frames, size: canvasManager.canvasSize)
            // Per-frame opacity is baked into the composite, so the view stays opaque here.
            onionSkinView.alpha = frames.count == 1 ? frames[0].opacity : 1
            onionSkinView.isHidden = false
        }

        // MARK: - Smart-shape detection (hold-to-detect: accumulate stroke points, fire after ~1s idle)

        private func startShapeDetection(host: LayerHostView) {
            guard canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil else { return }
            guard !canvasManager.shapeGestureActive else { return }
            shapeDetectionSamples.removeAll()
            shapeDetectionHost = host
            shapeDetectionActive = true
            shapeLastPoint = nil
            shapeFollowFrame = nil
            shapeHoldTimer?.invalidate()
            // Resets on meaningful moves — fires 0.8s after the finger stops.
            shapeHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.fireShapeDetection()
                }
            }
        }

        /// Last position the hold timer was (re)started at — filters out Apple Pencil's sub-pixel
        /// micro-moves, which would otherwise prevent the timer from ever completing.
        private var shapeLastPoint: CGPoint?

        /// Captured on the first sample of shape following: finger position relative to the shape's
        /// centre, its size, and its detected rotation. See `ShapeGeometry.FollowFrame`.
        private var shapeFollowFrame: ShapeGeometry.FollowFrame?

        /// Writes a dragged geometry back onto the pending shape and repaints the overlay.
        /// `refreshOverlay: false` is for callers that update the overlay themselves right after.
        fileprivate func applyShapeDrag(_ geometry: ShapeGeometry, refreshOverlay: Bool = true) {
            canvasManager.updateInteractiveShape(startPoint: geometry.startPoint,
                                                 endPoint: geometry.endPoint,
                                                 rotation: geometry.rotation)
            if refreshOverlay { updateShapeOverlay() }
        }

        private func handleStrokeMoved(_ sample: VectorSample, host: LayerHostView?) {
            guard shapeDetectionActive else { return }
            guard let host, host === shapeDetectionHost else { return }
            shapeDetectionSamples.append(sample)
            let point = sample.point
            // Only restart the timer past 2pt of movement — otherwise Pencil micro-moves never let it fire.
            if let last = shapeLastPoint {
                let dx = point.x - last.x, dy = point.y - last.y
                guard hypot(dx, dy) > 2 else { return }
            }
            shapeLastPoint = point
            shapeHoldTimer?.invalidate()
            shapeHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.fireShapeDetection()
                }
            }
        }

        private func cancelShapeDetection() {
            shapeHoldTimer?.invalidate()
            shapeHoldTimer = nil
            shapeDetectionActive = false
            shapeDetectionSamples.removeAll()
            shapeDetectionHost = nil
        }

        private func fireShapeDetection() {
            shapeHoldTimer = nil
            guard shapeDetectionActive else { return }
            shapeDetectionActive = false
            let samples = shapeDetectionSamples
            shapeDetectionSamples.removeAll()
            guard samples.count >= 3,
                  let host = shapeDetectionHost,
                  let layerID = host.strokeView.layerID,
                  let layerIndex = canvasManager.layers.firstIndex(where: { $0.id == layerID }) else {
                shapeDetectionHost = nil
                return
            }
            shapeDetectionHost = nil

            let points = samples.map(\.point)
            guard let shape = ShapeDetector.detect(from: points) else { return }

            // Revert the partial stroke painted during the hold period.
            if host.strokeView.vectorCanvas != nil {
                host.strokeView.revertVectorStrokeToSnapshot()
            } else {
                host.strokeView.revertStrokeToSnapshot()
            }

            canvasManager.beginInteractiveShape(shape, samples: samples)
            updateShapeOverlay()
            // A snapping finger may already have been down before the timer fired, so re-read the count.
            canvasTouchCountChanged(touchCountRecognizer?.activeCount ?? 0)
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

        /// Snaps to the nearest right angle when close to one, unless held within the snap zone for
        /// over a second (which releases it so the user can keep rotating past it).
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
            // update pass; guard it so unrelated renders (e.g. every point of a stroke) don't
            // perturb the active stroke's touch tracking.
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

            // Drives the shape constraint snap: reports the live canvas touch count, and two or more
            // engage the snap after a short delay (see `canvasTouchCountChanged`). Unlike a
            // two-finger long press, it still fires when a second touch joins a sequence the pen
            // started seconds ago — "keep the pen down, then drop a finger to snap it."
            let touchCounter = TouchCountRecognizer(target: self, action: nil)
            touchCounter.delegate = self
            touchCounter.onCountChanged = { [weak self] count in
                self?.canvasTouchCountChanged(count)
            }
            view.addGestureRecognizer(touchCounter)
            touchCountRecognizer = touchCounter

            let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
            threeFingerTap.numberOfTouchesRequired = 3
            threeFingerTap.cancelsTouchesInView = false
            view.addGestureRecognizer(threeFingerTap)

            twoFingerTap.require(toFail: threeFingerTap)

            // One-finger press-drag driving the fill tool: press applies the fill, dragging adjusts
            // settings live. `minimumPressDuration = 0` makes a plain tap a one-shot fill. Disabled
            // except while the fill tool is selected, so it never competes with stroke capture.
            let fillPress = UILongPressGestureRecognizer(target: self, action: #selector(handleFillPress(_:)))
            fillPress.minimumPressDuration = 0
            fillPress.numberOfTouchesRequired = 1
            fillPress.delegate = self
            fillPress.cancelsTouchesInView = false
            fillPress.isEnabled = false
            view.addGestureRecognizer(fillPress)
            fillTapRecognizer = fillPress

            // Catch-all for when no layers or the active layer is hidden: fires on any single-finger
            // touch to surface an alert instead of silently swallowing it. Disabled by default —
            // enabled in reconcileLayers only when the canvas can't accept drawing input.
            let catchAll = UILongPressGestureRecognizer(target: self, action: #selector(handleCatchAllTap(_:)))
            catchAll.minimumPressDuration = 0
            catchAll.numberOfTouchesRequired = 1
            catchAll.delegate = self
            catchAll.cancelsTouchesInView = false
            catchAll.isEnabled = false
            view.addGestureRecognizer(catchAll)
            catchAllTapRecognizer = catchAll
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let alwaysConcurrent: [UIGestureRecognizer?] = [fillTapRecognizer, catchAllTapRecognizer, touchCountRecognizer]
            if alwaysConcurrent.contains(where: { $0 === gestureRecognizer }) || alwaysConcurrent.contains(where: { $0 === otherGestureRecognizer }) {
                return true
            }
            let transformRecognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0 }
            return transformRecognizers.contains(where: { $0 === gestureRecognizer }) &&
                   transformRecognizers.contains(where: { $0 === otherGestureRecognizer })
        }

        /// Dynamically requires the transform recognizers to wait only on the currently active
        /// layer's drawing recognizer. A static `require(toFail:)` against every layer, including
        /// inactive ones that never reach `.failed`, would deadlock two-finger pan/zoom/rotate as
        /// soon as a second layer exists.
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
            canvasManager.cancelInteractiveFillDrag()
            if canvasManager.shapeGestureActive {
                // Two fingers on a pending shape mean "snap it," not "pan the canvas" — panning
                // only takes over once `commitSnappedShapeIfTransforming` reads continued movement
                // as "done editing" and anchors from there.
                return
            }
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
            let theta = effectiveRotation() - committedRotation // this gesture's contribution only
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

        /// Folds live scale/rotation/offset into the committed baseline once all of pan/pinch/rotation
        /// have ended, rather than each committing independently — fingers rarely lift in sync, and
        /// committing one gesture's contribution while another is live would jump visually.
        private func commitLiveTransformIfAllEnded() {
            let states: [UIGestureRecognizer.State] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0?.state }
            guard !states.contains(.began), !states.contains(.changed) else { return }
            // No upper bound on zoom; the tiny floor only guards against a pinch's fingers crossing.
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
            // The shape snap isn't released here: it follows the touches themselves (see
            // `canvasTouchCountChanged`), letting the pen lift out of a snapped shape while the
            // snapping finger is still down.
        }

        /// The shared body of the three canvas-transform gestures: identical state machine, only the
        /// live value each contributes differs (`applyLiveValue`; pan contributes none of its own).
        ///
        /// Two orderings here are load-bearing:
        /// 1. In `.changed`, the touch-count guard runs before `commitSnappedShapeIfTransforming` —
        ///    a lifting finger can still produce one more `.changed` as the recognizer collapses
        ///    from 2 touches to fewer, which must not be read as an intentional transform (a real
        ///    shipped bug otherwise: lifting the second finger baked the shape instead of releasing it).
        /// 2. `applyLiveValue` runs before `updateLiveOffset`, which reads `liveScale` to place the
        ///    anchor — a stale scale would slip the content out from under the fingers by one event.
        private func handleTransformGesture<Recognizer: UIGestureRecognizer>(
            _ recognizer: Recognizer, applyLiveValue: (Recognizer) -> Void) {
            guard let host = hostView else { return }
            switch recognizer.state {
            case .began:
                beginAnchorIfNeeded(at: recognizer.location(in: host))
                applyLiveValue(recognizer)
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .changed:
                guard recognizer.numberOfTouches >= 2 else { return }
                commitSnappedShapeIfTransforming(at: recognizer.location(in: host))
                applyLiveValue(recognizer)
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .ended, .cancelled:
                commitLiveTransformIfAllEnded()
            default:
                break
            }
            applyTransform()
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            handleTransformGesture(recognizer) { _ in }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            handleTransformGesture(recognizer) { self.liveScale = $0.scale }
        }

        @objc func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            handleTransformGesture(recognizer) { self.liveRotation = $0.rotation }
        }

        @objc func handleTwoFingerTap() {
            // undo() itself resolves any in-flight fill first, so this does exactly one thing.
            canvasManager.undo()
        }

        // MARK: - Two-finger snap constraint

        /// Two or more touches, while a shape is pending, means the snap constraint: rectangle to
        /// square, oval to circle, line to nearest 15°. Applies whether following the pen or already
        /// adjustable.
        private func canvasTouchCountChanged(_ count: Int) {
            guard canvasManager.shapeGestureActive, count >= 2 else {
                shapeConstraintTimer?.invalidate()
                shapeConstraintTimer = nil
                releaseShapeConstraintAfterCurrentEvent()
                return
            }
            guard shapeConstraintTimer == nil, !isShapeConstraintEngaged else { return }
            shapeConstraintTimer = Timer.scheduledTimer(withTimeInterval: Self.shapeConstraintDelay,
                                                        repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.shapeConstraintTimer = nil
                    guard self.canvasManager.shapeGestureActive else { return }
                    self.setShapeConstraint(true)
                }
            }
        }

        /// Releases the snap one run-loop turn later rather than inline: the same touch event that
        /// drops the count below two can also be the pen lifting, and `endInteractiveShape` is what
        /// makes a snap permanent. UIKit fires both recognizers in no defined order, so deferring
        /// lets the lift land first regardless of ordering; the count is re-read so a finger that
        /// came straight back down doesn't lose its snap.
        private func releaseShapeConstraintAfterCurrentEvent() {
            guard isShapeConstraintEngaged else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, (self.touchCountRecognizer?.activeCount ?? 0) < 2 else { return }
                self.setShapeConstraint(false)
            }
        }

        private func setShapeConstraint(_ on: Bool) {
            guard isShapeConstraintEngaged != on else { return }
            isShapeConstraintEngaged = on
            guard canvasManager.shapeGestureActive else { return }
            canvasManager.updateInteractiveShape(isConstrained: on)
            updateShapeOverlay()
        }

        /// While a shape is snapped, a two-finger pan/zoom/rotate means the user is done editing it:
        /// bake it and hand the gesture to the canvas transform.
        private func commitSnappedShapeIfTransforming(at location: CGPoint) {
            guard canvasManager.isShapeInAdjustableState, isShapeConstraintEngaged else { return }
            // Commit without clearing the constraint first: the shape must bake in the snapped
            // form shown. `commitTransientsAndRefresh` drops the constraint once there's no shape left.
            commitTransientsAndRefresh()
            if gestureAnchorCenter0 == nil, let container = containerView {
                gestureAnchorHost0 = location
                gestureAnchorCenter0 = container.center
            }
        }

        @objc func handleThreeFingerTap() {
            canvasManager.redo()
        }

        @objc func handleCatchAllTap(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            guard canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil || canvasManager.selectedTool == .eraser else { return }
            if canvasManager.layers.isEmpty {
                canvasManager.needsLayerAlert = true
            } else if canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
                      !canvasManager.layers[canvasManager.currentLayerIndex].isVisible {
                canvasManager.needsVisibilityAlert = true
            }
        }

        @objc func handleFillPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let container = containerView, let host = hostView else { return }
            switch recognizer.state {
            case .began:
                // Continuing to fill dismisses whatever top-bar dropdown is open.
                canvasManager.interactionBegan.send()
                // container's bounds equal canvasSize, so location(in:) there is canvas-pixel space.
                // The drag delta is measured in fixed screen (host) space so feel is zoom-independent.
                fillDragStartHost = recognizer.location(in: host)
                fillDragStartGap = canvasManager.fillGapClosingDistance
                fillDragStartThreshold = canvasManager.fillThreshold
                fillDragStartEdge = canvasManager.fillExpand
                let canvasPoint = recognizer.location(in: container)
                // Pressing back inside the current adjustable fill resumes drag-adjusting it. A
                // press elsewhere bakes it first via `beginInteractiveFill`'s `beginCanvasEdit`.
                if canvasManager.isFillInAdjustableState, canvasManager.isPointInPendingFill(at: canvasPoint) {
                    canvasManager.resumeInteractiveFillDrag()
                } else {
                    canvasManager.beginInteractiveFill(at: canvasPoint)
                }
            case .changed:
                guard let start = fillDragStartHost else { return }
                let dx = recognizer.location(in: host).x - start.x
                // Horizontal-only: rightward travel raises the selected setting; the others hold.
                func perPoint(_ range: ClosedRange<CGFloat>) -> CGFloat {
                    (range.upperBound - range.lowerBound) / Self.fillDragSweepPoints
                }
                switch canvasManager.fillSelectedAxis {
                case .gapClosing:
                    let gap = fillDragStartGap + dx * perPoint(CanvasManager.fillGapRange)
                    canvasManager.updateInteractiveFill(gapClosing: gap, threshold: fillDragStartThreshold, edgeOverlap: fillDragStartEdge)
                case .threshold:
                    let threshold = fillDragStartThreshold + dx * perPoint(CanvasManager.fillThresholdRange)
                    canvasManager.updateInteractiveFill(gapClosing: fillDragStartGap, threshold: threshold, edgeOverlap: fillDragStartEdge)
                case .edgeOverlap:
                    let edge = fillDragStartEdge + dx * perPoint(CanvasManager.fillExpandRange)
                    canvasManager.updateInteractiveFill(gapClosing: fillDragStartGap, threshold: fillDragStartThreshold, edgeOverlap: edge)
                }
            case .ended:
                canvasManager.endInteractiveFill()
                fillDragStartHost = nil
            case .cancelled, .failed:
                canvasManager.cancelInteractiveFillDrag()
                fillDragStartHost = nil
            default:
                break
            }
        }

    }
}
