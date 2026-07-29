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

        // Light-grey backing for the drawable padding margin: fills the whole (padded) container and
        // sits behind the white paper, so wherever the paper is inset by `canvasPadding` the grey shows
        // through as the margin. At padding 0 the paper covers it edge-to-edge and it's never seen.
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

        let shapeOverlay = ShapeOverlayView()
        shapeOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(shapeOverlay)
        context.coordinator.shapeOverlay = shapeOverlay

        // Paper is inset from the container by `canvasPadding` on each side (the artwork rect); the
        // coordinator updates these constants in `updatePaper()`. Positive top/leading, negative
        // bottom/trailing so a larger padding shrinks the white paper inward, revealing the grey margin.
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
            shapeOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
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
            // Move the end that was actually grabbed, leaving the other anchored.
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
        // Both handle drags are pure geometry — see `ShapeGeometry.draggingCorner`/`draggingEdge`,
        // which is where the rotation-inverted local-frame mapping and the oval's axis math live.
        // Writing the whole resulting geometry back (rather than only the fields a given drag can
        // change) is the same update either way: a drag that leaves rotation alone writes back the
        // rotation it read.
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
        weak var paperView: UIView?
        /// The four constraints pinning the white paper to the container, whose constants are the
        /// `canvasPadding` inset on each side (see `updatePaper`).
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
        /// (which would otherwise be silently swallowed) triggers a user-facing alert instead.
        weak var catchAllTapRecognizer: UILongPressGestureRecognizer?
        /// Counts live canvas touches — engages the shape constraint snap (rect→square, oval→circle,
        /// line→nearest 15°) whenever a second one is down.
        weak var touchCountRecognizer: TouchCountRecognizer?

        // Smart-shape overlay and detection state
        weak var shapeOverlay: ShapeOverlayView?
        /// True while the two-finger snap constraint is engaged on the pending shape. Owned here
        /// rather than by the overlay, because the touches that engage it usually land on the canvas
        /// rather than on the overlay (which only claims its handles).
        private(set) var isShapeConstraintEngaged = false
        /// Debounces the snap by `shapeConstraintDelay` so a quick two-finger tap — undo — doesn't
        /// flash a shape into its snapped form on the way past.
        private var shapeConstraintTimer: Timer?
        private static let shapeConstraintDelay: TimeInterval = 0.12
        /// See `scheduleShapePreviewRenderIfNeeded`.
        private var isShapePreviewRenderScheduled = false
        /// Accumulated canvas-space stroke samples from the current stroke (for shape detection
        /// and later collapsing onto the detected shape geometry).
        private var shapeDetectionSamples: [VectorSample] = []
        /// Timer that fires after the user holds the finger still for ~1s — triggers shape detection.
        private var shapeHoldTimer: Timer?
        /// True when a shape detection is in progress (timer running).
        private var shapeDetectionActive = false
        /// The stroke view that started the current detection stroke (needed to revert on shape found).
        private weak var shapeDetectionHost: LayerHostView?
        // Interactive-fill drag state, captured at press-down: the finger's start point in fixed
        // screen (host) space, and all three fill settings at that moment. The drag is horizontal-only —
        // its rightward travel raises whichever single setting is currently selected (canvasManager
        // .fillSelectedAxis, default gap-closing), relative to these baselines; the others hold.
        private var fillDragStartHost: CGPoint?
        private var fillDragStartGap: CGFloat = 0
        private var fillDragStartThreshold: CGFloat = 0
        private var fillDragStartEdge: CGFloat = 0

        /// Finger travel (in screen points) that sweeps a fill setting across its whole slider range.
        /// Deliberately generous so fine adjustments are easy; the value is clamped in CanvasManager.
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
            // Inset the paper to the artwork rect; the grey backdrop shows through the resulting margin.
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
                host.strokeView.onStrokeBegan = { [weak self, weak host] in
                    guard let self else { return }
                    // A stroke is a canvas edit, so any adjustable fill/shape bakes before this one
                    // changes a single pixel: they become the older undo steps and this stroke
                    // undoes first, and the caller snapshots the raster for undo *after* this
                    // returns, so the baked content is part of that snapshot rather than lost by it.
                    //
                    // This is also what makes drawing straight over a pending shape work in one
                    // touch: the shape overlay only claims touches on its handles, so this stroke's
                    // very first touch arrives here, bakes the shape, and then goes on to draw —
                    // rather than being consumed as a dismissal the user has to follow with a
                    // second touch to actually start drawing.
                    self.commitTransientsAndRefresh()
                    // Begin accumulating stroke points for smart-shape detection.
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
                        // Shape following: the user is still holding after detection. For lines,
                        // just move the endpoint. For rects & ovals, the finger angle sets
                        // rotation and the distance sets a uniform scale from centre — see
                        // `ShapeGeometry.following(_:from:)`, measured against the frame captured
                        // on the first sample of the drag.
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
                    // Touching the canvas at all — even a finger tap that the pencil-only gate below
                    // rejects — dismisses whatever top-bar dropdown is open (see CanvasManager.
                    // interactionBegan), so continuing to draw both closes the menu and keeps drawing.
                    self?.canvasManager.interactionBegan.send()
                }
                host.strokeView.onStrokeEnded = { [weak self, weak host] in
                    guard let self else { return }
                    self.canvasManager.refreshUndoRedoState()
                    self.cancelShapeDetection()
                    // If the shape was being followed (finger down since detection), lift transitions
                    // it to the adjustable state — no stroke was committed (it was reverted), so skip
                    // the normal stroke-end path. `endInteractiveShape` self-guards on finger-down.
                    if self.canvasManager.shapeGestureActive {
                        self.canvasManager.endInteractiveShape()
                        self.updateShapeOverlay()
                        return
                    }
                    // Normal stroke-end path.
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
                    // Vector layers route drawing into their VectorCanvas instead of the raster (nil
                    // for raster layers, so the stroke view stays in raster mode there).
                    let targetVector = celIdx.flatMap { canvasManager.layers[index].cels[$0].vector }
                    if host.strokeView.vectorCanvas !== targetVector {
                        host.strokeView.vectorCanvas = targetVector
                    } else {
                        // Same backing instance, but it may have been mutated in place — a shape or
                        // fill baking down, an undo/redo of one, a vector transform or image import.
                        // Neither `RasterLayerTexture` nor `VectorCanvas` changes the `layers` value
                        // when its content changes, so this version check is the only thing that
                        // brings the display back in sync. See `displayedRasterVersion`.
                        host.strokeView.refreshDisplayIfStale()
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
                // Select/Move take over touch handling entirely while engaged (via SelectionOverlayView/
                // FloatingPieceOverlayView, both above the whole layer stack), so drawing is disabled then too.
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

            // Enable the catch-all gesture when no layers exist or the active layer is hidden,
            // so a drawing-tool touch triggers a user-facing alert instead of being silently swallowed.
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

        /// Drives `ObjectTransformOverlayView` (a generic single-`LayerTransform` handle box) from the
        /// active vector layer's aggregate transform while `isVectorTransforming` is on — the only
        /// remaining user of this overlay now that dedicated object layers are gone (inserted photos
        /// are vector elements moved as part of their layer's overall transform, same as this).
        func updateTransformOverlay() {
            guard let overlay = transformOverlay, let container = containerView else { return }
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else {
                overlay.isHidden = true
                return
            }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]

            // Vector layer being transformed: box just the layer's own content (its bounding box in
            // local space), driven by the VectorCanvas's current overall transform — not the whole
            // canvas, so Move only carries the actual drawn content along, matching the raster Move
            // tool's use of the content's bounding box.
            if layer.kind == .vector, layer.isVisible, canvasManager.isVectorTransforming,
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
                  let canvasSize = canvasManager.canvasSize,
                  let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame),
                  let vector = canvasManager.layers[index].cels[celIdx].vector else { return }
            // Same pivot `updateTransformOverlay` handed the overlay: the content's own local bounding
            // box center, fixed for the gesture since the raw (untransformed) geometry doesn't change
            // while it's only being moved/scaled/rotated.
            let localBounds = vector.localContentBounds() ?? CGRect(origin: .zero, size: canvasSize)
            let pivot = CGPoint(x: localBounds.midX, y: localBounds.midY)
            canvasManager.setVectorTransform(transform, layerIndex: index, pivot: pivot)
            // VectorCanvas is a reference type mutated in place, so refresh its host directly
            // (the @Published layers array didn't change identity).
            let layerID = canvasManager.layers[index].id
            layerHosts[layerID]?.strokeView.refreshDisplay()
        }

        /// What a layer's `bakedImageView` should show for its active cel: the real `bakedImage`,
        /// or — while that exact cel's content is lifted into a Move (not Duplicate) piece — the
        /// transient "hole" preview computed at lift time, which isn't written into the model until
        /// the piece commits (see `CanvasManager.beginMove`/`commitFloatingPieceIfNeeded`).
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
            // Layer hosts are added to `container` after this overlay (see CanvasView.makeUIView), so
            // without this the marching ants/hatch render *underneath* every layer's own content —
            // bring it back to front whenever it has something to show or is actively capturing a new
            // lasso/rectangle drag, same pattern updateTransformOverlay uses for its own overlay.
            if overlay.isCapturingGestures || canvasManager.selection != nil {
                container.bringSubviewToFront(overlay)
            }
        }

        func updateFloatingOverlay() {
            floatingOverlay?.update(canvasManager.floatingPiece)
            guard let overlay = floatingOverlay, let container = containerView else { return }

            // A piece lifted by the Move tool still belongs to its source layer, so it has to render
            // in that layer's place in the stack — floating it above everything makes content that
            // should sit *under* the layers above it appear on top while it's being dragged.
            //
            // Every other case (no piece, or a duplicate/paste that isn't tied to a position in the
            // stack) puts it back at the front. Without that `else`, one move would leave the overlay
            // wedged below a layer host for good, and the next operation would render behind it.
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
            // Render inline the first time (otherwise the shape would be invisible for a frame the
            // moment it's detected); after that let the coalescing below carry it.
            if canvasManager.activeShapePreviewImage == nil { canvasManager.renderActiveShapePreview() }
            overlay.update(shape: shape,
                           previewImage: canvasManager.activeShapePreviewImage,
                           showHandles: isAdjustable)
            scheduleShapePreviewRenderIfNeeded()
            // Put the overlay above every layer host so it's visible and, in the adjustable
            // state, its handles are hit-testable. During shape following (finger still down)
            // we disable interaction so touches pass through to the stroke view, which routes
            // them back to `updateInteractiveShape`.
            container.bringSubviewToFront(overlay)
            overlay.isUserInteractionEnabled = isAdjustable
        }

        /// Coalesces preview re-renders to one per run-loop turn. A Pencil delivers several coalesced
        /// samples per frame and each one moves the shape, but re-stamping a canvas-sized preview for
        /// every sample would cost far more than the one frame of lag this trades for. Feeding the
        /// result straight to the overlay (rather than re-entering `updateShapeOverlay`) also keeps
        /// this from scheduling itself in a loop.
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
        /// `reconcileLayers` does the same per layer on each SwiftUI pass; this is the synchronous
        /// form, for the moment a transient bakes — the overlay drawing its preview is torn down
        /// immediately, so waiting a pass for the baked pixels to appear shows a visible flicker.
        func syncLayerDisplays() {
            for host in layerHosts.values {
                host.strokeView.refreshDisplayIfStale()
            }
        }

        /// Bakes whatever is transient (shape or fill) and brings the canvas back in sync in the
        /// same turn — the entry point for every "the user did something that ends shape editing"
        /// path in this coordinator.
        func commitTransientsAndRefresh() {
            canvasManager.beginCanvasEdit()
            syncLayerDisplays()
            updateShapeOverlay()
            // Nothing is pending any more, so the snap has nothing to constrain — drop it here
            // rather than waiting for the fingers holding it to leave.
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

            // Not per-layer (there's only one global selected tool), so it lives outside the
            // per-layer caching guard below and is kept in sync on every call. Also suspended while
            // Select is engaged or a piece is floating — same conditions `shouldInteract` already
            // gates the stroke view on above — so the fill tool's one-finger press can't fire
            // underneath (and race) the Selection/Move overlays' own gestures on the same touch.
            fillTapRecognizer?.isEnabled = (canvasManager.selectedTool == .fill)
                && activePanel != .select && canvasManager.floatingPiece == nil

            // Same reasoning as fillTapRecognizer above: kept in sync on every call, outside the
            // AppliedTool caching guard below, since toggling "paint outside selection" or making/
            // clearing a selection doesn't otherwise touch any of that struct's fields. Only applies
            // to the exact layer/cel the selection belongs to (selection is always cleared when the
            // active layer/cel moves away from it — see handleActiveContextChanged).
            let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame)
            let celID = celIdx.map { layer.cels[$0].id }
            if let selection = canvasManager.selection, !canvasManager.allowsPaintingOutsideSelection,
               selection.layerID == layer.id, selection.celID == celID {
                host.strokeView.selectionClipPath = selection.path
            } else {
                host.strokeView.selectionClipPath = nil
            }

            // Eraser gets its own brush/size/opacity, entirely separate from the paint brush's, so
            // switching tools never clobbers either one's settings (see CanvasManager's eraser state).
            let isEraser = canvasManager.selectedTool == .eraser
            let activeSize = isEraser ? canvasManager.eraserSize : canvasManager.brushSize
            let activeOpacity = isEraser ? canvasManager.eraserOpacity : canvasManager.brushOpacity
            let activeBrush = isEraser ? canvasManager.selectedEraserBrush : canvasManager.selectedBrush

            // Only push new tool settings into the view when something tool-relevant actually
            // changed, same caching reason as before (this method runs on every SwiftUI re-render).
            let desired = AppliedTool(tool: canvasManager.selectedTool, color: canvasManager.brushColor, size: activeSize, opacity: activeOpacity, brush: activeBrush)
            guard lastAppliedTool[layer.id] != desired else { return }
            lastAppliedTool[layer.id] = desired

            host.strokeView.brushColor = canvasManager.brushColor.resolvedUIColor(opacity: 1)
            host.strokeView.brushSize = activeSize
            host.strokeView.brushOpacity = activeOpacity
            host.strokeView.brush = activeBrush
            host.strokeView.isEraser = isEraser
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
            // The timer resets on meaningful moves — fires 0.8s after the finger stops.
            shapeHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.fireShapeDetection()
                }
            }
        }

        /// Last position at which the hold timer was (re)started. Used to filter out sub-pixel
        /// micro-moves that Apple Pencil generates even when held still, which would otherwise
        /// prevent the timer from ever completing.
        private var shapeLastPoint: CGPoint?

        /// Captured on the first sample after shape following begins, and held for the rest of that
        /// drag: where the finger was relative to the shape's centre, how big the shape was, and the
        /// rotation it was already detected at. Nil until then. See `ShapeGeometry.FollowFrame`,
        /// which carries the math and the reason the shape's own rotation has to be part of it.
        private var shapeFollowFrame: ShapeGeometry.FollowFrame?

        /// Writes a dragged geometry back onto the pending shape and repaints the overlay. The one
        /// place a handle drag or a follow-the-finger sample lands, so each of those only has to
        /// produce the new `ShapeGeometry` (see `ShapeGeometry`'s handle-dragging section).
        ///
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
            // Only restart the timer if the finger / pencil moved more than 2pt — Apple Pencil
            // generates continual micro-moves that would otherwise never let the timer fire.
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

            // Revert the partial stroke that was painted during the hold period.
            // strokeBeforeSnapshot becomes nil, so the subsequent handleEnd bails out early.
            if host.strokeView.vectorCanvas != nil {
                host.strokeView.revertVectorStrokeToSnapshot()
            } else {
                host.strokeView.revertStrokeToSnapshot()
            }

            canvasManager.beginInteractiveShape(shape, samples: samples)
            updateShapeOverlay()
            // The snapping finger may already have been down before the hold timer fired, in which
            // case no touch event is coming to engage the constraint — re-read the count instead.
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

            // Drives the shape constraint snap: it reports the live canvas touch count, and two or
            // more touches engage the snap (after a short delay — see `canvasTouchCountChanged`).
            // Unlike the two-finger long press this replaced, it also fires when the second touch
            // joins a sequence the pen started seconds ago, which is exactly the "keep the pen down
            // after the shape appears, then drop a finger to snap it" gesture — a long press with
            // `numberOfTouchesRequired = 2` has already failed by then, because it starts its clock
            // on the first touch and gives up when the fingers aren't all down in time.
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

            // One-finger press-drag that drives the fill tool: press applies the fill, then dragging
            // adjusts gap-closing (vertical) and edge overlap (horizontal) live. `minimumPressDuration = 0`
            // makes a plain tap register immediately (press + lift with no drag == a one-shot fill).
            // Kept disabled except while the fill tool is selected (toggled in updateActiveLayerAndTool)
            // rather than gated only inside the handler, so it never competes for single-finger touches
            // with the active layer's own stroke capture while a drawing tool is active.
            let fillPress = UILongPressGestureRecognizer(target: self, action: #selector(handleFillPress(_:)))
            fillPress.minimumPressDuration = 0
            fillPress.numberOfTouchesRequired = 1
            fillPress.delegate = self
            fillPress.cancelsTouchesInView = false
            fillPress.isEnabled = false
            view.addGestureRecognizer(fillPress)
            fillTapRecognizer = fillPress

            // Catch-all gesture for when no layers or the active layer is hidden: fires immediately
            // on any single-finger touch so we can surface an actionable alert instead of silently
            // swallowing the touch. Disabled by default — enabled in reconcileLayers only when the
            // canvas can't accept drawing input.
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
            canvasManager.cancelInteractiveFillDrag()
            if canvasManager.shapeGestureActive {
                // Two fingers on a pending shape mean "snap it" (the touch counter engages that),
                // not "pan the canvas" — so don't set gesture anchors here. Panning only takes over
                // once the user keeps moving, which `commitSnappedShapeIfTransforming` reads as
                // "done editing", bakes the shape, and anchors from there.
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
            // The shape snap isn't released here: it follows the touches themselves (see
            // `canvasTouchCountChanged`), which is what lets the pen lift out of a snapped shape
            // while the snapping finger is still down.
        }

        /// The shared body of the three canvas-transform gestures. Pan, pinch and rotate run the
        /// identical state machine and the identical side effects; the only thing that differs is
        /// which live value each contributes, which `applyLiveValue` supplies (nothing, for pan —
        /// its contribution is the offset `updateLiveOffset` derives from the touch location).
        ///
        /// Two orderings inside here are load-bearing and must not be rearranged:
        ///
        /// 1. In `.changed`, the touch-count guard runs *before*
        ///    `commitSnappedShapeIfTransforming`. A lifting finger can still produce one more
        ///    `.changed` as the recognizer's geometry collapses from 2 touches to 1 (or 0), and
        ///    that is not an intentional transform. With the two the other way round, simply
        ///    lifting the second finger out of a two-finger snap baked the shape instead of just
        ///    releasing the snap — a real shipped bug, fixed in session 49. Note the guard
        ///    `return`s, so a collapsing event also contributes no live value and no offset.
        /// 2. `applyLiveValue` runs *after* `beginAnchorIfNeeded` / the commit above and *before*
        ///    `updateLiveOffset`, which reads `liveScale` to place the anchor — feeding it a stale
        ///    scale would slip the content out from under the fingers by one event.
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
            // Pan contributes no live value of its own; the offset comes from the touch location.
            handleTransformGesture(recognizer) { _ in }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            handleTransformGesture(recognizer) { self.liveScale = $0.scale }
        }

        @objc func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            handleTransformGesture(recognizer) { self.liveRotation = $0.rotation }
        }

        @objc func handleTwoFingerTap() {
            // A two-finger tap means undo. undo() itself resolves any in-flight fill first (a fill still
            // under the finger is dropped; a lifted, adjustable one is committed so undo reverts it),
            // so it does exactly one thing rather than both discarding a fill and undoing the prior step.
            canvasManager.undo()
        }

        // MARK: - Two-finger snap constraint

        /// The number of touches on the canvas changed. Two or more of them, while a shape is
        /// pending, means the snap constraint: a rectangle becomes a square, an oval a circle, a
        /// line jumps to the nearest 15°. Applies whether the shape is still following the pen
        /// (finger added mid-stroke) or already adjustable (two fingers on the canvas).
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

        /// Releases the snap one run-loop turn later rather than inline.
        ///
        /// The same touch event that drops the count below two can also be the pen leaving the
        /// board, and it is the pen's lift — `CanvasManager.endInteractiveShape` — that makes a snap
        /// permanent. Both arrive through recognizers attached to the same event, which UIKit fires
        /// in no defined order, so releasing inline would be a coin flip on whether the circle the
        /// user just settled springs back into the oval it was drawn as. Deferring lets the lift
        /// land first however the event was ordered; the count is re-read on the way out so a finger
        /// that came straight back down doesn't lose its snap.
        private func releaseShapeConstraintAfterCurrentEvent() {
            guard isShapeConstraintEngaged else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, (self.touchCountRecognizer?.activeCount ?? 0) < 2 else { return }
                self.setShapeConstraint(false)
            }
        }

        /// Engages or releases the snap constraint on the pending shape.
        private func setShapeConstraint(_ on: Bool) {
            guard isShapeConstraintEngaged != on else { return }
            isShapeConstraintEngaged = on
            guard canvasManager.shapeGestureActive else { return }
            canvasManager.updateInteractiveShape(isConstrained: on)
            updateShapeOverlay()
        }

        /// While a shape is snapped, a two-finger *pan/zoom/rotate* means the user is done editing
        /// it: bake it and hand the gesture over to the canvas transform. Shared by all three
        /// transform recognizers, which otherwise carried three copies of this.
        private func commitSnappedShapeIfTransforming(at location: CGPoint) {
            guard canvasManager.isShapeInAdjustableState, isShapeConstraintEngaged else { return }
            // Commit without clearing the constraint first: the shape has to bake in the snapped
            // form the user is looking at. `commitTransientsAndRefresh` drops the constraint on the
            // way out, once there's no longer a shape for it to apply to.
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
            // Only respond for drawing tools — fill/select have their own paths.
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
                // Continuing to fill dismisses whatever top-bar dropdown is open instead of the first
                // touch being silently swallowed (see CanvasManager.interactionBegan).
                canvasManager.interactionBegan.send()
                // container's bounds are exactly canvasSize (see hostBoundsDidChange), so location(in:)
                // there yields canvas-pixel coordinates — the top-left-origin space the fill engine and
                // the onion-skin/thumbnail renderers use. The drag delta, in contrast, is measured in
                // fixed screen (host) space so the feel is independent of the canvas's current zoom.
                fillDragStartHost = recognizer.location(in: host)
                fillDragStartGap = canvasManager.fillGapClosingDistance
                fillDragStartThreshold = canvasManager.fillThreshold
                fillDragStartEdge = canvasManager.fillExpand
                let canvasPoint = recognizer.location(in: container)
                // Pressing back inside the current adjustable fill (finger lifted, preview still
                // live) resumes drag-adjusting it. A press anywhere else is a new fill, which bakes
                // the adjustable one first — `beginInteractiveFill` goes through `beginCanvasEdit`,
                // so this doesn't have to commit by hand.
                if canvasManager.isFillInAdjustableState, canvasManager.isPointInPendingFill(at: canvasPoint) {
                    canvasManager.resumeInteractiveFillDrag()
                } else {
                    canvasManager.beginInteractiveFill(at: canvasPoint)
                }
            case .changed:
                guard let start = fillDragStartHost else { return }
                let dx = recognizer.location(in: host).x - start.x
                // Horizontal-only: rightward travel raises the single selected setting across its range;
                // the other two hold at their press-down baselines.
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
