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
        // See `StrokeCanvasView.init` for the argument. Every view a canvas touch can be hit-tested
        // into needs it, and the two below are the ones that take the touch when the layer hosts are
        // interaction-disabled — which `reconcileLayers` does in five separate states.
        host.isMultipleTouchEnabled = true
        host.isAccessibilityElement = true
        host.accessibilityIdentifier = "canvas.host"
        // Which rendering path the canvas is on, and how many times the mid-stroke one has been
        // entered — see `Coordinator.SandwichPresentation` and `midStrokeEntryCount`. Stated here as
        // well as in the `didSet` because a `didSet` never fires for the initial value; the two
        // formats have to stay identical or the test helpers parse one of them into nothing.
        host.accessibilityLabel = "sandwich:off entries:0 shape:none text:none"
        host.canvasManager = canvasManager

        let container = UIView()
        container.backgroundColor = .clear
        container.isMultipleTouchEnabled = true
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

        // §5.2's sandwich: two views, three images from two producers. At rest the lower one carries
        // the **baked frame** and the upper one is empty; mid-stroke they carry `below` and `above`
        // with the active layer's own host between them. Added here so the *disengaged* z-order is
        // already `below < onionSkin < above < chrome`; `reconcileLayers` is what lifts `above` over
        // the layer hosts once the sandwich engages. See `updateSandwich`.
        let sandwichBelow = Coordinator.makeSandwichView()
        container.addSubview(sandwichBelow)

        // **The Behind ghost sits between the two sandwich views, not under both** —
        // EFFECT_BACKDROP.md §2.1, ruled 2026-08-27. Once an adjustment layer grades the paper the
        // composite is opaque from that node up, and a ghost under `below` would simply stop
        // existing. It is not composited into the request and so is never graded by an effect; it
        // just draws over the composite of the layers beneath the active one, and `above` still
        // covers it with the artwork on layers over the active one — which is what "Behind" means.
        //
        // Deliberately left on the default bilinear filter — nearest-neighbor made the onion-skin
        // ghost render as a distractingly pixelated overlay instead of a soft reference. That is
        // doubly true now: `OnionSkinBudget` can composite below canvas resolution on a large canvas,
        // and bilinear is what makes that invisible.
        let onionSkin = Coordinator.makeOnionSkinView()
        container.addSubview(onionSkin)

        let sandwichAbove = Coordinator.makeSandwichView()
        container.addSubview(sandwichAbove)
        context.coordinator.sandwichBelowView = sandwichBelow
        context.coordinator.sandwichAboveView = sandwichAbove

        // "In Front" is a second view rather than a re-ordering of the one below it. Onion skin has
        // to sit either mid-stack (Behind, above) or over everything, and `reconcileLayers` re-fronts the hosts
        // and `sandwichAbove` whenever the stack changes — so a single view would have to be
        // re-positioned from two places that do not know about each other. Two views, one of which is
        // always hidden, cost one empty `UIImageView` and remove the ordering rule entirely.
        let onionSkinFront = Coordinator.makeOnionSkinView()
        container.addSubview(onionSkinFront)

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

        // The live text editor (`ADD_TEXT.md` stage 1). Above the shape overlay because the text
        // overlay is the one the artist is looking at while a session is live, and because
        // `beginCanvasEdit` commits text *after* the shape for the same reason. It claims only its
        // own box and the move band around it — see `TextOverlayView.hitTest` — so being higher
        // costs the shape handles nothing.
        let textOverlay = TextOverlayView()
        textOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textOverlay)
        context.coordinator.textOverlay = textOverlay
        textOverlay.onDragBegan = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.beginTextFrameDrag()
        }
        textOverlay.onDragged = { [weak coordinator = context.coordinator] origin in
            coordinator?.canvasManager.dragTextFrame(toOrigin: origin)
        }
        textOverlay.onDragEnded = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.endTextFrameDrag()
        }
        textOverlay.onTextChanged = { [weak coordinator = context.coordinator] string in
            coordinator?.canvasManager.updateTextString(string)
        }
        textOverlay.onFocusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.canvasManager.textIsFocused = focused
            // **And re-run the overlay pass by hand, because `textIsFocused` is deliberately not
            // `@Published`** — it changes as the keyboard comes and goes and nothing was reading it
            // from a view until stage 5. `updateTextOverlay` now hides the nine grips while a
            // `.projective` box is being typed into (they would otherwise sit on a quad the artist
            // cannot see, inches from the flat editing box in front of it), and without this line
            // that would only take effect on whatever unrelated SwiftUI pass happened next.
            coordinator?.updateTextOverlay()
        }
        // The two hooks the model holds so it can drop the keyboard and route undo without knowing
        // what a first responder is. Weak on both sides: the manager outlives the view.
        context.coordinator.canvasManager.textFocusResigner = { [weak textOverlay] in
            textOverlay?.resignEditor()
        }
        context.coordinator.canvasManager.textEditUndoHandler = { [weak textOverlay] isRedo in
            textOverlay?.handleEditUndo(isRedo: isRedo) ?? false
        }

        // The text box's nine grips (`ADD_TEXT.md` §3 stage 4). A **sibling** of the editor rather
        // than a child of it — §1 "Handles live outside the warped layer" — and above it, so a touch
        // on a corner is a resize rather than a move: the grips' 44 pt targets overlap the editor's
        // move band by construction, and the more specific gesture has to win. It claims only those
        // targets, so the band and the canvas keep everything else.
        let textTransformOverlay = TextTransformOverlayView()
        textTransformOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textTransformOverlay)
        context.coordinator.textTransformOverlay = textTransformOverlay
        textTransformOverlay.onHandleDragBegan = { [weak coordinator = context.coordinator] handle in
            coordinator?.canvasManager.beginTextHandleDrag(handle)
        }
        textTransformOverlay.onHandleDragged = { [weak coordinator = context.coordinator] point in
            coordinator?.canvasManager.dragTextHandle(to: point)
        }
        textTransformOverlay.onHandleDragEnded = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.endTextHandleDrag()
        }

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
            onionSkinFront.topAnchor.constraint(equalTo: container.topAnchor),
            onionSkinFront.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            onionSkinFront.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            onionSkinFront.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sandwichBelow.topAnchor.constraint(equalTo: container.topAnchor),
            sandwichBelow.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sandwichBelow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sandwichBelow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sandwichAbove.topAnchor.constraint(equalTo: container.topAnchor),
            sandwichAbove.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sandwichAbove.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sandwichAbove.trailingAnchor.constraint(equalTo: container.trailingAnchor),
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
            textOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            textOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textTransformOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            textTransformOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textTransformOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textTransformOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            guideOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            guideOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            guideOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            guideOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        context.coordinator.hostView = host
        context.coordinator.containerView = container
        context.coordinator.onionSkinView = onionSkin
        context.coordinator.onionSkinFrontView = onionSkinFront
        context.coordinator.paperView = paper
        context.coordinator.transformOverlay = transformOverlay
        context.coordinator.selectionOverlay = selectionOverlay
        context.coordinator.floatingOverlay = floatingOverlay
        context.coordinator.setUpGestures(on: container)

        // One undo step per whole move/scale/rotate drag, not per intermediate value — see
        // `CanvasManager.beginStructureGesture`'s doc comment. (Covers object-layer transforms;
        // vector-layer whole-layer transforms mutate `VectorCanvas` in place and aren't captured
        // by this value-based snapshot — pre-existing gap, not introduced here.)
        transformOverlay.onHandleDragBegan = { [weak coordinator = context.coordinator] handle, point in
            coordinator?.beginObjectTransformDrag(handle, at: point)
        }
        transformOverlay.onHandleDragged = { [weak coordinator = context.coordinator] point in
            coordinator?.objectTransformDragged(to: point)
        }
        transformOverlay.onHandleDragEnded = { [weak coordinator = context.coordinator] in
            coordinator?.endObjectTransformDrag()
        }
        // One lasso gesture, two destinations. `SelectionOverlayView` already captures a lasso with
        // the right touch-type gating, the right coordinate space and a live preview, so the fill
        // tool's lasso mode borrows it whole rather than growing a fourth lasso implementation —
        // see `updateSelectionOverlay`, which is what decides which of the two is armed.
        selectionOverlay.onFinishPath = { [weak coordinator = context.coordinator] path in
            guard let coordinator else { return }
            if coordinator.isLassoFilling {
                // Begin-then-end, the same pair a one-shot tap makes: the fill stays *adjustable*
                // afterwards, so the Fill panel's sliders re-run this loop live exactly as they
                // re-run a bucket fill, and the next canvas edit bakes it.
                coordinator.canvasManager.beginInteractiveLassoFill(path: path)
                coordinator.canvasManager.endInteractiveFill()
            } else {
                coordinator.canvasManager.finishSelection(path: path)
            }
        }
        selectionOverlay.onAutomaticTap = { [weak coordinator = context.coordinator] point in
            coordinator?.canvasManager.finishAutomaticSelection(at: point)
        }
        floatingOverlay.onPoseChange = { [weak coordinator = context.coordinator] transform, distortQuad in
            coordinator?.canvasManager.updateFloatingPose(transform: transform, distortQuad: distortQuad)
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
        // The whole resulting geometry is written back either way. `anchor` is the canvas point the
        // overlay latched at touch-down; passing nil would make the math recompute it every frame,
        // which jumps the instant a drag crosses its own anchor.
        shapeOverlay.onCornerDragged = { [weak coordinator = context.coordinator] point, corner, anchor in
            guard let coordinator, let shape = coordinator.canvasManager.activeShape else { return }
            coordinator.applyShapeDrag(shape.draggingCorner(corner, to: point, anchor: anchor))
        }
        shapeOverlay.onEdgeDragged = { [weak coordinator = context.coordinator] point, edge, anchor in
            guard let coordinator, let shape = coordinator.canvasManager.activeShape else { return }
            coordinator.applyShapeDrag(shape.draggingEdge(edge, to: point, anchor: anchor))
        }
        // The one callback that arrives already resolved. A body drag is measured from the geometry
        // latched at touch-down, which only the overlay saw, so re-deriving it from `activeShape`
        // here would measure each delta against the answer the previous one gave.
        shapeOverlay.onBodyDragged = { [weak coordinator = context.coordinator] geometry in
            coordinator?.applyShapeDrag(geometry)
        }

        host.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.hostBoundsDidChange()
        }

        context.coordinator.activePanel = activePanel
        context.coordinator.reconcileLayers()
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateSelectionOverlay()
        // After the selection overlay, which re-fronts itself: a lasso move's box has to sit above
        // its own marching ants, and this is where it takes the front back.
        context.coordinator.updateVectorFloat()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.updateShapeOverlay()
        context.coordinator.updateTextOverlay()
        context.coordinator.hostBoundsDidChange()

        return host
    }

    func updateUIView(_ uiView: CanvasHostView, context: Context) {
        context.coordinator.activePanel = activePanel
        context.coordinator.updatePaper()
        context.coordinator.reconcileLayers()
        // Immediately after `reconcileLayers`, and before every overlay that re-fronts itself: the
        // "In Front" placement fronts the onion-skin view over `sandwichAbove`, and everything below
        // this line then lands above it. Ordering, not preference — moved here when placement
        // arrived.
        context.coordinator.updateOnionSkin()
        context.coordinator.updateActiveLayerAndTool()
        context.coordinator.updateInterpolationPreviews()
        // **From here down the order is a hit-testing rule, not a drawing one.** Two of these views
        // are pinned to the whole container with no `hitTest` override — `SelectionOverlayView` while
        // it is capturing, `FloatingPieceOverlayView` while a piece floats — so every overlay that
        // claims only its own grips has to sit *above* both of them or its grips are unreachable:
        // UIKit gives the touch to one view, and it gives it to the top one. That is what
        // `CanvasTouchOwner.contenders(in:)` means by an overlay claim displacing the other views,
        // and until 2026-08-22 the guide overlay was on the wrong side of it — fronted first, so
        // opening the Select panel or floating a piece quietly took its grips away.
        context.coordinator.updateSelectionOverlay()
        // Above the marching ants: a lasso move's box has to sit over its own selection outline, and
        // its grips over a capturing selection overlay. `updateVectorFloat` re-fronts it for the
        // first of those reasons and this pass covers the whole-layer transform, which has no float.
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateVectorFloat()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.updateGuideOverlay()
        context.coordinator.updateShapeOverlay()
        context.coordinator.updateTextOverlay()
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
        /// The "Behind" placement's view — under every layer host, over `sandwichBelow`
        /// (EFFECT_BACKDROP.md §2.1); `reconcileLayers` re-fronts it into that slot.
        weak var onionSkinView: UIImageView?
        /// The "In Front" placement's view — fronted over `sandwichAbove` by `updateOnionSkin`.
        weak var onionSkinFrontView: UIImageView?
        weak var guideOverlay: GuideOverlayView?
        /// The guide under the pen right now, pushed up from `StrokeCanvasView` per sample. Held here
        /// so `updateGuideOverlay` stays a pure function of coordinator state.
        private var liveGuidePoints: [CGPoint] = []
        var onionSkinSource: OnionSkinSource = OnionSkinSettingsSource()
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
        weak var fillTapRecognizer: TouchTypePressRecognizer?
        /// Enabled when there are no layers or the active layer is hidden, so a drawing-tool touch
        /// raises a user-facing notice instead of being silently swallowed.
        weak var catchAllTapRecognizer: TouchTypePressRecognizer?
        /// The tap that puts the vector Move box down. Enabled only while that box is on screen —
        /// `CanvasTouchInputs.moveBoxCommitIsEnabled`. See `handleMoveBoxCommit`.
        weak var moveBoxCommitRecognizer: UITapGestureRecognizer?
        /// The eyedropper's tap. A third `TouchTypePressRecognizer` rather than a third mechanism —
        /// see `setUpGestures`.
        weak var eyedropperTapRecognizer: TouchTypePressRecognizer?
        /// Guards against a second pick being scheduled while the first is still compositing off the
        /// main thread. Without it, a double-tap on a 4K canvas queues two full composites and the
        /// second one's result — taken from the same picture — arrives after the tool has already
        /// reverted. Read and written on the main actor only.
        var eyedropperPickInFlight = false
        /// True from the moment the eyedropper's recognizer begins until it ends or is cancelled —
        /// "a touch that came in through the eyedropper is still on the glass". Half of the join in
        /// `finishEyedropperIfSettled`; see `handleEyedropperPress` for what the join is for.
        var eyedropperTouchIsDown = false
        /// A resolved pick that still owes the tool revert. Set when the colour is applied, cleared
        /// when the revert actually happens. The other half of the join.
        var eyedropperRevertPending = false
        /// Counts live canvas touches — engages the shape constraint snap whenever a second is down.
        weak var touchCountRecognizer: TouchCountRecognizer?
        /// Fingers reported by the *active stroke's own* recognizer as accompanying the pen, the
        /// second source `refreshShapeConstraint` folds in. See
        /// `StrokeGestureRecognizer.onAccompanyingFingersChanged` for why there are two.
        private var strokeAccompanyingFingers = 0
        /// Fingers already on the glass at the moment a shape started following the pen — subtracted
        /// from the container counter so a *resting hand* cannot snap a shape nobody asked to snap.
        /// See `currentAccompanyingFingers()`.
        private var shapeFingerBaseline = 0

        // Smart-shape overlay and detection state
        weak var shapeOverlay: ShapeOverlayView?
        /// The live text editor. `ADD_TEXT.md` stage 1.
        weak var textOverlay: TextOverlayView?
        /// Its nine grips, in a sibling view above it. `ADD_TEXT.md` stage 4.
        weak var textTransformOverlay: TextTransformOverlayView?
        /// The text tool's placement tap. A fourth `TouchTypePressRecognizer`, not a fourth
        /// mechanism — see `setUpGestures`.
        weak var textTapRecognizer: TouchTypePressRecognizer?
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
        /// Fixed-rate poll that asks `shapeHoldClock` whether the hold is done. The deadline does
        /// *not* live here — the clock owns it, measured on the pen's own timestamps, so this
        /// timer's firing time never enters the decision. See `ShapeHoldClock`.
        private var shapeHoldTimer: Timer?
        /// Owns the hold decision. Rebuilt at the start of every detection stroke.
        private var shapeHoldClock = ShapeHoldClock()
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
        /// Whether the last ordering pass placed the sandwich views. The pass is gated on layer order
        /// changing, and engaging or disengaging the sandwich is the other thing that moves this
        /// z-order — see `reconcileLayers`.
        private var lastOrderedSandwichEngaged = false

        init(canvasManager: CanvasManager) {
            self.canvasManager = canvasManager
        }

        // MARK: - Layer stack

        /// Whether the composite currently on screen already contains the canvas colour.
        ///
        /// **This is the "or it is applied twice" half of EFFECT_BACKDROP.md §6 step 3.** Once
        /// `full` and `below` carry the paper, a `paperView` still painting under them is a second
        /// copy of it. An opaque colour hides that completely — white over white is white — and a
        /// translucent one does not: two 50% sheets are 75%, and the artist's canvas quietly darkens
        /// the moment an effect layer engages the sandwich.
        ///
        /// **Gated on the composite being on screen, not on the sandwich being engaged**, because
        /// those are not the same instant. `updateSandwich`'s "do not blank the hosts until the first
        /// composite has landed" trap returns early while the images are still being built, and
        /// hiding the paper in that window would flash the padding backdrop's grey across the canvas
        /// for the length of a rebuild. So `updateSandwich` sets this where it sets
        /// `sandwichPresentation`, and only after the images are actually installed.
        private var compositeCarriesThePaper = false

        func updatePaper() {
            guard let paperView else { return }
            paperView.backgroundColor = UIColor(canvasManager.canvasBackgroundColor)
            paperView.isHidden = !canvasManager.isCanvasBackgroundVisible || compositeCarriesThePaper
            // Inset the paper to the artwork rect; the grey backdrop shows through the margin.
            //
            // **Whole pixels, matching `RenderBackground.rect`.** The container's bounds are exactly
            // `canvasSize` (`hostBoundsDidChange`) and the composite is blitted into that same
            // container `.scaleToFill`, so one point here is one canvas pixel and the artwork rect
            // the compositor fills is this same integer inset. The two are shown in *alternation*,
            // never together (`isHidden` above), so a disagreement is not a double image — it is the
            // paper edge jumping by up to half a pixel the moment an adjustment layer engages the
            // sandwich. `CanvasManager+Fill` already spells the artwork rect this way; this is the
            // third consumer of the same rect and they now agree.
            //
            // Residual, and deliberately not chased: at 75%/50% the composite's inset is
            // `round(canvasPadding × scale) / scale`, up to a canvas pixel from this. At reduced
            // resolution the composite is magnified with `.linear` so its paper edge is soft anyway,
            // and `paperView` is hidden throughout.
            if let c = paperInsetConstraints {
                let p = canvasManager.canvasPadding.rounded()
                if c.top.constant != p { c.top.constant = p }
                if c.leading.constant != p { c.leading.constant = p }
                if c.bottom.constant != -p { c.bottom.constant = -p }
                if c.trailing.constant != -p { c.trailing.constant = -p }
            }
        }

        func reconcileLayers() {
            guard let container = containerView else { return }

            // Derived once per pass and threaded through: the ordering pass below has to know whether
            // the two sandwich views are in the stack, and `updateSandwich` needs the same tree for
            // its cache key. `renderTree` is O(layers × folders), the same order as the row generation
            // beside it, and deliberately not on the drawing path (§5.2).
            //
            // At `currentFrame` for the reason the value-layer swatch two hundred lines below already
            // gives: the frame is the argument a derivation asks for, and a live canvas pass is
            // always about the frame the playhead is on. Nothing in the tree varies with it yet.
            let tree = canvasManager.renderTree(atFrame: canvasManager.currentFrame)
            let sandwichEngaged = isSandwichEngaged(tree)

            // Derived once for the same reason, and used by both touch gates this function owns —
            // the active host's `isUserInteractionEnabled` and the catch-all recognizer's `isEnabled`.
            // They are two halves of one arrangement ("this touch is not the layer's; say why"), and
            // reading them off one value is what keeps them from drifting into the shapes
            // `CanvasTouchOwner`'s doc comment lists.
            let touch = canvasTouchInputs()

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
                // Debug-recorder name only (see `setUpGestures`). Per-layer rather than a bare
                // "stroke": every layer has one of these, and `shouldRequireFailureOf` names exactly
                // one of them, so a recording has to be able to tell them apart.
                host.strokeView.strokeRecognizer.name = "stroke.\(layer.id.uuidString.prefix(8))"
                // Live guide feedback goes straight to the overlay, not through SwiftUI state — a
                // `@Published` write per touch sample would re-run every view body for the drag.
                host.strokeView.guideOverlayNeedsUpdate = { [weak self] samples in
                    guard let self else { return }
                    self.liveGuidePoints = samples.map(\.point)
                    self.updateGuideOverlay()
                }
                host.strokeView.onStrokeBegan = { [weak self, weak host] in
                    guard let self else { return }
                    // A new stroke means the previous touch sequence is over, whatever UIKit did or
                    // did not call on the way out. `StrokeGestureRecognizer.reset()` clears its own
                    // count, but a recognizer stranded without a reset — which BUGS.md documents
                    // happening under a timeline popover — would leave this latched, and a latched
                    // finger count snaps the *next* shape the instant it forms, with nothing on the
                    // glass. Zeroed here rather than trusted, because the failure is silent.
                    self.strokeAccompanyingFingers = 0
                    // A stroke is a canvas edit, so any adjustable fill/shape bakes before this one
                    // changes a pixel: they become older undo steps, and this stroke's undo
                    // snapshot (taken after this returns) includes the baked content. This is also
                    // what lets drawing straight over a pending shape work in one touch — the first
                    // touch bakes the shape and then goes on to draw.
                    self.commitTransientsAndRefresh()
                    // Drawing on a frame with no block spawns one, right here, before the stroke
                    // reaches for its content tier. `handleBegin` calls this and *then* reads
                    // `vectorCanvas`/`raster`, so attaching the new cel's tiers synchronously is
                    // what lets the very touch that created the block also draw into it — a
                    // deferred refresh would drop the first stroke on the floor.
                    self.attachSpawnedCelIfFrameIsEmpty(host: host)
                    // After the cel spawn, and conditional on there being a tier to stamp into:
                    // `StrokeCanvasView.handleBegin` returns without ever reaching `onStrokeEnded`
                    // when both tiers are nil (the eraser on a frame with no block is the reachable
                    // case, since `attachSpawnedCelIfFrameIsEmpty` excludes it), and a latch set
                    // before that check would never be cleared — leaving the canvas showing the
                    // mid-stroke approximation while idle.
                    self.sandwichStrokeBegan(host: host)
                    // After `sandwichStrokeBegan`, which latches the mid-stroke state this reads,
                    // and after the cel spawn, which is what decides whether there is a stroke at
                    // all. §6.4: resolved here, once, and static until lift.
                    self.liveMaskStrokeBegan(host: host)
                    // Last, so it sees both the latch and the resolved mask. Without it the latch
                    // above is a variable nothing reads until some unrelated SwiftUI pass happens
                    // to come along — see `applySandwichPresentationNow`.
                    self.applySandwichPresentationNow()
                    if let host { self.startShapeDetection(host: host) }
                }
                host.strokeView.onStrokeCancelled = { [weak self] in
                    guard let self else { return }
                    self.isSandwichStrokeLive = false
                    // The clear needs applying for the same reason the latch does, and a cancel is
                    // the case with no publish to rely on at all: it restores the pre-touch content,
                    // so nothing about the model has moved for SwiftUI to notice. The key is back
                    // where the cached images were built, so this snaps straight to `full`.
                    self.applySandwichPresentationNow()
                    self.cancelShapeDetection()
                    // A cancel has to release a following shape for the same reason a lift does, or
                    // the shape is stranded: `shapeFingerDown` stays true, `isShapeInAdjustableState`
                    // stays false, and `updateShapeOverlay` therefore draws the outline with **no
                    // handles** and no interaction — a pending shape the artist can see and cannot
                    // touch, with no gesture left that would ever release it. `StrokeCanvasView`'s
                    // three cancel paths currently route a shape-following touch to `onStrokeEnded`
                    // instead, so this is unreachable today; it is here because the two booleans live
                    // on different objects (`shapeFollowingTouch` on the stroke view,
                    // `shapeFingerDown` on the manager) and only one of the two exits was covered.
                    if self.canvasManager.shapeGestureActive {
                        self.canvasManager.endInteractiveShape()
                        self.updateShapeOverlay()
                    }
                    // The cancel path discards whatever the stroke had painted, by design (see
                    // `StrokeCanvasView.handleCancel`) — which from the artist's chair is "my stroke
                    // vanished". Nothing named it in a recording before this line.
                    ActionRecorder.ifRecording {
                        $0.note("stroke cancelled — partial stroke discarded, no undo step")
                    }
                    self.canvasManager.refreshUndoRedoState()
                }
                // A second finger during shape following means "snap", not "pan" — keep the pen.
                host.strokeView.strokeRecognizer.shouldIgnoreAdditionalTouches = { [weak self] in
                    self?.canvasManager.isShapeFollowingFinger ?? false
                }
                // ...and having kept it, say so: this is the second source for "a finger joined the
                // pen", read off the recognizer the pen is already driving rather than off the
                // container four views up. See `onAccompanyingFingersChanged`. Only one stroke can be
                // live at a time, so one counter serves every host; `reset()` reports 0, which is
                // what keeps a torn-down host from leaving the snap latched on.
                host.strokeView.strokeRecognizer.onAccompanyingFingersChanged = { [weak self] fingers in
                    guard let self else { return }
                    self.strokeAccompanyingFingers = fingers
                    self.refreshShapeConstraint()
                }
                host.strokeView.onStrokeMoved = { [weak self, weak host] sample, penTime in
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
                        self.handleStrokeMoved(sample, penTime: penTime, host: host)
                    }
                }
                host.strokeView.strokeRecognizer.onAnyTouchBegan = { [weak self] in
                    // Touching the canvas at all dismisses whatever top-bar dropdown is open.
                    self?.canvasManager.canvasInteractionBegan()
                }
                host.strokeView.onStrokeEnded = { [weak self, weak host] in
                    guard let self else { return }
                    // Before the shape-following early return below: every path out of this closure
                    // is a lift, and a lift is what unfreezes the sandwich's cache key (see
                    // `makeSandwichKey`) so the canvas snaps back to the exact composite.
                    self.isSandwichStrokeLive = false
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
            // Engagement is in the gate as well as layer order: the sandwich views have to be lifted
            // into place the pass the compositor takes over, not only when the artist restacks.
            if orderedIDs != lastOrderedLayerIDs || sandwichEngaged != lastOrderedSandwichEngaged {
                // `below < onionSkin < hosts < above`, which is §5.2's sandwich in z-order with
                // EFFECT_BACKDROP.md §2.1's ghost threaded through it. The Behind skin is fronted
                // here rather than left where `makeUIView` put it because `sandwichBelowView` is
                // about to be lifted over it; it stays *under* the layer hosts, so a Behind ghost is
                // still behind the ink the artist is drawing, and only the composite of the layers
                // beneath the active one has moved under it. Everything else the old pass guaranteed
                // still holds: the chrome overlays re-front themselves later in `updateUIView`, so
                // they end up above `above`. `updateFloatingOverlay`'s Move case inserts the overlay
                // *below* a specific host, which still lands it between the two sandwich views —
                // correctly, since the layers above the Move source are inside `above`.
                if sandwichEngaged, let sandwichBelowView { container.bringSubviewToFront(sandwichBelowView) }
                // Unconditional: the "In Front" view is a different view (`onionSkinFrontView`) and
                // this one is hidden whenever that placement is selected, so fronting it costs
                // nothing and spares this pass a setting it has no other reason to read — the same
                // trade `updateOnionSkin` names where it fronts the other view.
                if let onionSkinView { container.bringSubviewToFront(onionSkinView) }
                for layer in canvasManager.layers {
                    if let host = layerHosts[layer.id] {
                        container.bringSubviewToFront(host)
                    }
                }
                if sandwichEngaged, let sandwichAboveView { container.bringSubviewToFront(sandwichAboveView) }
                lastOrderedLayerIDs = orderedIDs
                lastOrderedSandwichEngaged = sandwichEngaged
            }

            for (index, layer) in canvasManager.layers.enumerated() {
                guard let host = layerHosts[layer.id] else { continue }
                if host.strokeView.pencilOnlyDrawing != canvasManager.pencilOnlyDrawing {
                    host.strokeView.pencilOnlyDrawing = canvasManager.pencilOnlyDrawing
                }
                // `layer.isVisible`/`.opacity` are the layer's own switches; whether it actually
                // reaches the canvas also folds in every enclosing group's (§4.1) — Core Animation
                // gets one flat sibling per layer, so these are where that folding has to happen
                // for the live canvas. See `isLayerEffectivelyVisible`/`effectiveOpacity`'s doc
                // comments — the latter is a documented approximation, not exact group opacity.
                let effectivelyVisible = canvasManager.isLayerEffectivelyVisible(index)
                if host.isHidden != !effectivelyVisible { host.isHidden = !effectivelyVisible }
                // §6.5: while a mask-edit session is open, everything that isn't a legal source for
                // it dims — folded in here rather than as a separate overlay, since this is already
                // where every other per-layer canvas approximation (group opacity, visibility) gets
                // combined into the one number Core Animation takes.
                let targetAlpha = CGFloat(canvasManager.effectiveOpacity(ofLayer: index))
                    * canvasManager.maskEditCanvasDim(forLayerAt: index)
                if host.alpha != targetAlpha { host.alpha = targetAlpha }

                let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame)

                // §4.5's value layer on the live canvas: **a host with a background colour**, and
                // nothing else. Its three content views stay empty — the colour is not in a cel — so
                // the host's own background is what Core Animation draws, full-bleed, in stack order,
                // under `host.alpha` (which already folds in group opacity) and behind
                // `setBlanked`'s mask when the compositor takes over.
                //
                // **`needsCompositorOnCanvas` deliberately gains no clause for this**, and that is the
                // check rather than an omission: a value layer at Normal with no mask is an ordinary
                // opaque leaf, and a flat rect in a flat row of siblings is the one thing Core
                // Animation is good at — so it draws exactly what the compositor would. Give it a
                // blend mode or a mask and the *existing* clauses fire on it like any other leaf, and
                // the sandwich takes over with the resolved solid source. A clause here would have
                // pushed every document containing a flat colour onto the compositor for nothing.
                //
                // **This whole path is the *flat-colour* mode's, and `valueFill` is what confines it
                // there** — not a `kind` test, which is what it would have been if the accessor had
                // not been narrowed. A value layer in effect mode has no colour to paint: it grades
                // the backdrop beneath it, which is a thing one sibling view cannot do to another, so
                // it must be compositor-driven. `Layer.valueFill` answers nil the moment `effect` is
                // set (that is the mode discriminant), the `.map` below therefore yields nil, and the
                // line after it *assigns* that nil — which is the half worth stating, because the
                // failure this would otherwise be is silent: an `if let` here, or a "only write when
                // there is a colour" shortcut, would leave the flat colour the artist picked before
                // the flip painted over the grade for the rest of the session, and it would look like
                // the effect simply not working. The write is unconditional-when-different, so the
                // flip clears it on the same pass the mode changes.
                //
                // Nothing else is needed to make the grade appear: `needsCompositorOnCanvas`'s
                // *effect* clause (phase 9a) fires on the leaf, the sandwich engages, and `full` is
                // the graded composite. That clause reads `RenderNode.effect`, which the derivation
                // sets from the same `layerEffect` accessor, so the two answers cannot disagree —
                // "this host paints no colour" and "the compositor is on" are one condition read
                // twice, and `EffectLayerLogicTests` pins both halves.
                //
                // Resolved at `currentFrame` for `leafSnapshots`' reason: the frame is the argument a
                // later keyframe phase needs, and reading it here too keeps the live canvas and the
                // composite asking the same question. Gated on `celIdx` for the same reason the
                // snapshot is — a layer with no block at this frame contributes nothing at it.
                let fillColour = (celIdx == nil ? nil : layer.valueFill).map {
                    PixelOps.uiColor(from: $0.resolvedColor(atFrame: canvasManager.currentFrame).color)
                }
                if host.backgroundColor != fillColour { host.backgroundColor = fillColour }

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
                //
                // Deliberately *not* gated on `celIdx != nil` any more: the active layer stays
                // drawable on a frame no block covers, and the first stroke spawns the block (see
                // `attachSpawnedCelIfFrameIsEmpty`). Gating it here was the outer half of the
                // blank-frame bug — the touch never even reached the stroke view to be acted on.
                // `.compositing` and `.value` excluded too: neither holds pixels for a stroke to land
                // in (`addEffectLayer`'s and `addValueLayer`'s docs), so their hosts decline
                // interaction the same way a vector layer mid-transform does, and the catch-all below
                // takes the touch instead.
                //
                // **The tool clause asks the tool rather than listing tools.** It read
                // `selectedTool != .fill`, and that hand-maintained exclusion is exactly what the
                // eyedropper fell through: the tool shipped, the list did not grow, so the host
                // stayed interactive with the eyedropper selected and the picking touch started a
                // brush stroke alongside the pick (owner, 2026-08-17). `Tool.paintsOnCanvas` is an
                // exhaustive switch with no `default:`, so the next tool added has to answer.
                //
                // The six clauses that follow "is this the active layer" are
                // `CanvasTouchInputs.activeHostIsInteractive`, which every other gate that needs
                // them reads too — including `shouldRequireFailureOf`, which used to read this
                // property back off the view instead.
                let shouldInteract = (index == canvasManager.currentLayerIndex)
                    && touch.activeHostIsInteractive
                if host.isUserInteractionEnabled != shouldInteract {
                    host.isUserInteractionEnabled = shouldInteract
                }
                if host.strokeView.isUserInteractionEnabled != shouldInteract {
                    host.strokeView.isUserInteractionEnabled = shouldInteract
                }
            }

            // **RENDER.md §3.6's dirty sweep, at this pass's cadence and not on a hook** — see
            // `CanvasManager.syncFrameBake`, which carries the argument for why the pass *is* the
            // right clock. Before `updateSandwich`, so that a frame the baker already holds is asked
            // for after the sweep has had its say about whether it is still current.
            syncFrameBake()

            // After the per-layer loop, which owns `isHidden`/`alpha`/interaction — the sandwich's
            // blanking is a `layer.mask` and rides on top of all three (see `LayerHostView.setBlanked`).
            updateSandwich(tree: tree, engaged: sandwichEngaged)

            // Enable the catch-all gesture when no layers exist, the active layer is hidden — by its
            // own switch or by a group's gating it (§4.1), either reads as "hidden" here — or the
            // active layer has no drawing surface at all (`.value`), which `shouldInteract` above
            // has just as deliberately declined interaction for.
            //
            // The three cases are `CanvasTouchInputs.catchAllIsEnabled`, so this gate and
            // `shouldInteract` are now two readings of one value rather than two spellings that have
            // to be kept agreeing. **One state answers differently from the hand-spelled version it
            // replaces**: layers present but `currentLayerIndex` out of range used to fall to a bare
            // `else { false }`, and reads as "no active layer" here. `deleteLayer` is the only writer
            // that can park the index, it parks it at -1 only when the last layer goes (so
            // `layers.isEmpty` and both answers are `true`), and it clamps every other case — so the
            // difference is unreachable, and it is the reading the other thirteen gates already take.
            let needsCatch = touch.catchAllIsEnabled
            if catchAllTapRecognizer?.isEnabled != needsCatch {
                catchAllTapRecognizer?.isEnabled = needsCatch
            }
        }

        // MARK: - §5.2's sandwich
        //
        // Core Animation has no per-view Multiply against arbitrary siblings, so a blended layer
        // cannot be drawn by handing every layer to Core Animation as a flat sibling — which is what
        // `reconcileLayers` above does and will keep doing for every document that does not need
        // more. Where it does, the compositor draws instead, in two states over three images that
        // now come from two places:
        //
        //   at rest      the **baked frame** in the lower view, every host blanked. One image, exact
        //                for every mode and every nesting, byte-identical to the thumbnail — and,
        //                since RENDER.md §3.6 stage 4d, composited by `FrameBaker` on its own queue
        //                and read back off disk rather than composited here. A frame that is not
        //                baked yet is a miss, and a miss leaves the previous picture up (§2.10).
        //   mid-stroke   `composite(below)` | the active layer's live host | `composite(above)`.
        //
        // Both halves of the mid-stroke picture are approximations and both are deliberate for this
        // phase: the active layer's own mode degrades to normal because Core Animation is what draws
        // that view, and a layer *above* it degrades too because a texture composited onto
        // transparency has no backdrop left to blend against. `SandwichLogicTests` pins the exact
        // measured deltas (127, 127, 64) so that a later session cannot come to believe the
        // mid-stroke path is exact. Lift is what snaps it back to the baked frame.
        //
        // Both are cached, so switching state is an image swap — which is what lets the switch
        // happen on a stroke's first touch without a hitch, and what keeps the compositor off the
        // drawing path entirely (§2, §5.2). The two halves are still built here, by
        // `startSandwichRebuild`, and deliberately: they are a different product from the bake — cut
        // at the active leaf, wanted *now* on the artist's own gesture rather than eventually, and
        // never stored — so they belong on `sandwichQueue` at `.userInitiated` rather than behind a
        // frame queue at `.utility`. What they must share with the bake is not a thread but a
        // **size**, because `PixelOps.rasterize`'s memo is keyed on it; `FrameBaker.recipe` is where
        // that is arranged and argued.

        /// Whether §5.2's sandwich drives the live canvas at all this pass.
        ///
        /// **The predicate itself is `CanvasManager.sandwichEngagesOnCanvas(tree:)`** — every input to
        /// it is document state, and a `UIViewRepresentable` coordinator cannot be driven headlessly,
        /// so it lives beside `makeSandwichRecipe` where `SandwichLogicTests` can reach it. That is
        /// also where its clauses, and the 2026-08-29 removal of the in-between one, are written down.
        /// Nothing but the call is left here.
        ///
        /// **The price of disengaging is more than the blend mode**, which is worth knowing at the
        /// call site: `updateSandwich`'s disengage branch also calls `host.setContentMask(nil)`, so
        /// §6.4's alpha-mask *clipping* comes off the canvas for as long as a piece floats. A clip
        /// lost is more visible than a blend lost, and the trade is still the right way round — an
        /// unclipped picture of the artwork beats no picture of it.
        private func isSandwichEngaged(_ tree: [RenderNode]) -> Bool {
            canvasManager.sandwichEngagesOnCanvas(tree: tree)
        }

        /// Which picture the canvas is showing right now — and, since RENDER.md stage 4d, whether the
        /// bake for this frame has landed: `rest` is reached only when `sandwichFullKey` names the
        /// frame the artist is on (`updateSandwich`'s trap 2), so an XCUITest reading "stroke" long
        /// after lift is reading a bake that never arrived.
        ///
        /// Published on `canvas.host` for the same reason `LayerStackCell` carries its markers: which
        /// of two rendering paths the canvas is on is not otherwise visible to an XCUITest, and "the
        /// picture happens to look the same either way" is exactly what the containment test has to
        /// be able to tell apart. On the *label* rather than the value because `CanvasHostView`
        /// already computes `accessibilityValue` as the vector gesture trace `VectorEraserUITests`
        /// reads, and a canvas has no user-facing label to collide with. `canvas.host` is an
        /// accessibility element in its own right, which hides any descendant from the tree, so a 1×1
        /// marker view of the kind the layer panel uses could not be found inside it.
        private enum SandwichPresentation: String {
            /// Core Animation's flat row of hosts, unblanked — today's code path, unchanged.
            case disengaged = "off"
            case rest
            case midStroke = "stroke"
        }
        private var sandwichPresentation: SandwichPresentation = .disengaged {
            didSet {
                if sandwichPresentation == .midStroke, oldValue != .midStroke { midStrokeEntryCount += 1 }
                publishCanvasState()
            }
        }

        /// Publishes the Coordinator's own state on `canvas.host`'s accessibility label, for the same
        /// reason `SandwichPresentation` documents above: none of it is otherwise visible to an
        /// XCUITest. Five space-separated fields —
        ///
        ///     sandwich:<off|rest|stroke> entries:<n> shape:<none|following|adjustable>
        ///     xform:<scale>,<rotation>,<dx>,<dy> text:<none|box|editing>
        ///
        /// — read by `LayerUITests` (the first two) and `CanvasTransformFreezeUITests` (the rest).
        ///
        /// **`text` is here because `canvas.textEditor` cannot be queried, and a test that assumed it
        /// could passed while placing nothing.** `TextOverlayView`'s `UITextView` carries that
        /// identifier, but it is a descendant of `canvas.host`, and `canvas.host` is an accessibility
        /// element in its own right — which hides its whole subtree, exactly as the paragraph above
        /// says of a 1×1 marker view. So a text session is invisible to XCUITest by the same
        /// mechanism as everything else on this label, and it belongs on the same label. It
        /// distinguishes `box` from `editing` rather than collapsing to a bool for the reason `shape`
        /// splits `following` from `adjustable`: the owner's freeze report is specifically about
        /// being *"in the edit text keyboard menu"*, so whether the editor holds first responder is
        /// part of the state under test and not a detail.
        /// `xform` carries the *effective* transform, committed plus whatever a gesture is
        /// contributing live, so "a two-finger gesture moved the canvas" is a value comparison
        /// across the gesture rather than something only `container.transform` knows.
        ///
        /// `shape` is here because "did that gesture bake my shape?" and "is the shape stuck?" are
        /// both invisible otherwise — the overlay draws `CALayer`s, which carry no accessibility
        /// identity at all, so a test could see the ink a shape *became* but never the pending shape
        /// itself. It distinguishes `following` (pen still down) from `adjustable` (pen lifted,
        /// handles live) rather than collapsing to a bool, because a shape left in `following` with
        /// no pen on the glass is a stranded state, and telling the two apart is the whole diagnosis.
        private func publishCanvasState() {
            let scale = fitScale * committedScale * liveScale
            // The one place the canvas's screen scale leaves this coordinator. Every transform pass
            // already lands here — including the ones `applyTransform`'s identity guard skips, which
            // is the reason this method is called above it — so the stamp preview tracks a pinch made
            // with the other hand while a slider is held. `record` is silent unless a preview is
            // actually up; see `CanvasDisplayScale` for why that matters on a path that runs inside
            // `updateUIView`.
            canvasManager.canvasDisplayScale.record(scale)
            let rotation = committedRotation + liveRotation
            let dx = committedOffset.width + liveOffset.width
            let dy = committedOffset.height + liveOffset.height
            let shapeState: String
            if canvasManager.isShapeFollowingFinger { shapeState = "following" }
            else if canvasManager.isShapeInAdjustableState { shapeState = "adjustable" }
            else { shapeState = "none" }
            let textState: String
            if !canvasManager.textGestureActive { textState = "none" }
            else if canvasManager.textIsFocused { textState = "editing" }
            else { textState = "box" }
            hostView?.accessibilityLabel = "sandwich:\(sandwichPresentation.rawValue)"
                + " entries:\(midStrokeEntryCount)"
                + " shape:\(shapeState)"
                + String(format: " xform:%.4f,%.4f,%.2f,%.2f", scale, rotation, dx, dy)
                + " text:\(textState)"
        }

        /// How many times the canvas has *entered* the mid-stroke presentation, published beside the
        /// presentation itself.
        ///
        /// **The state alone is not observable at the moment that matters.** `sandwichPresentation`
        /// is only ever read by a test between gestures, and the whole mid-stroke half of §5.2 exists
        /// only while a touch is down — by the time XCUITest can look, lift has already put the
        /// canvas back to `.rest` whether or not a single frame of the mid-stroke picture was ever
        /// shown. Sampling during the gesture is not an option either: XCUITest synthesises events on
        /// the main thread and refuses to do it from anywhere else, so a test cannot drag and look at
        /// the same time. A latch is what closes that gap — a stroke that never entered `.midStroke`
        /// is exactly a stroke the artist watched produce no ink until they lifted.
        private var midStrokeEntryCount = 0

        weak var sandwichBelowView: UIImageView?
        weak var sandwichAboveView: UIImageView?

        /// The two composites of one rebuild — everything strictly below the active layer and
        /// everything strictly above — wrapped as `UIImage` once so assigning them is an identity
        /// check rather than a fresh wrapper, and therefore a Core Animation no-op, on every one of
        /// the many SwiftUI passes that change nothing.
        ///
        /// **`full` is not here any more: it is the baked frame** (RENDER.md §3.6, stage 4d). These
        /// two are the mid-stroke picture and nothing else — a different product from the bake, keyed
        /// additionally by which leaf the tree is cut at, and transient rather than stored.
        private var sandwichHalves: (below: UIImage, above: UIImage)?
        /// The key as of the last pass. What `makeSandwichKey` freezes the active layer against, and
        /// deliberately *not* the same thing as `sandwichCacheKey`.
        private var sandwichKey: SandwichKey?
        /// The key `sandwichHalves` was built from. Stale halves are still shown — they are at most
        /// one edit behind — while the rebuild that replaces them runs.
        private var sandwichCacheKey: SandwichKey?

        /// The rest picture, from the baker (§3.6), wrapped once for the same identity reason.
        ///
        /// **A miss keeps this exactly where it is**, which is §2.10's *"playback may be visibly
        /// stale while the bake catches up"*: `sandwichFullKey` still names the older frame, the
        /// canvas goes on showing it, and `FrameBaker.onFrameFinished` brings the pass that replaces
        /// it. That pairing is why the key is stored beside the image rather than derived — "is what
        /// I am holding this frame's picture?" is the question both §2.10 and trap 2 below ask.
        private var sandwichFull: UIImage?
        /// The `SandwichKey` `sandwichFull` was fetched for, or nil when it is a miss away from
        /// current. Compared rather than the bake key itself so that this costs a comparison the
        /// pass has already made: `SandwichKey` carries strictly more than `FrameBakeKey` does
        /// (the active leaf, and the content of a layer the bake key folds into the tree), so a
        /// `SandwichKey` that has not moved is a `FrameBakeKey` that has not moved.
        private var sandwichFullKey: SandwichKey?

        /// One rebuild of the two halves in flight at a time. See `startSandwichRebuild`.
        private var isSandwichRebuilding = false
        /// True from the first touch of a stroke to its lift. The only input to this whole section
        /// that a *dab* moves, and it moves nothing else: see `makeSandwichKey`.
        private var isSandwichStrokeLive = false

        static func makeSandwichView() -> UIImageView {
            let view = UIImageView()
            // The composite is exactly `canvasSize` and the container's bounds are too, so this is a
            // 1:1 blit and `.scaleToFill` cannot resample — the same reasoning `LayerHostView` gives
            // for `fillImageView`. Nearest-neighbor for the same reason it does as well: the whole
            // stack is magnified by a transform on the container, and bilinear would blur the very
            // pixels the host views keep crisp.
            view.contentMode = .scaleToFill
            view.layer.magnificationFilter = .nearest
            // Mipmapped the other way, for the reason `LayerHostView.init` measures: at rest this
            // view carries the baked frame, so it is how the *whole picture* reaches the screen
            // and an un-mipmapped minification loses thin ink out of all of it at once. Set here
            // rather than beside `magnificationFilter`'s reduced-composite switch in
            // `updateSandwich` because the answer does not depend on the composite's size —
            // `.trilinear` is right at full resolution and righter below it.
            view.layer.minificationFilter = .trilinear
            view.isUserInteractionEnabled = false
            view.isHidden = true
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }

        /// Latches the mid-stroke state. Called from `onStrokeBegan` *after* the cel spawn — see the
        /// comment there for why the condition is load-bearing rather than defensive.
        private func sandwichStrokeBegan(host: LayerHostView?) {
            guard let view = host?.strokeView, view.raster != nil || view.vectorCanvas != nil else { return }
            isSandwichStrokeLive = true
        }

        /// Puts §5.2's presentation on screen right now, for the touch callbacks that move
        /// `isSandwichStrokeLive` outside a SwiftUI pass.
        ///
        /// **The latch is not the state change — `updateSandwich` is, and it runs only from
        /// `reconcileLayers`, which runs only from a SwiftUI pass.** A dab publishes nothing, on
        /// purpose and load-bearingly (§5.2), so touching down does not cause a pass either. The
        /// *first* stroke on a frame gets one for free because the cel spawn beside it publishes;
        /// every stroke after that gets none, and the active layer's host stays blanked for the
        /// whole gesture. The artist then draws into a view the sandwich is deliberately hiding and
        /// sees no ink at all until they lift, which is the bug this closes — and every existing
        /// assertion about the canvas is taken after lift, where `full` has the stroke and
        /// everything looks right.
        ///
        /// This is the same reasoning `liveMaskStrokeBegan` already gives for resolving the mask at
        /// touch-down rather than leaving it to the next pass. Blanking needed it too.
        ///
        /// Deriving the tree is off `reconcileLayers`'s per-pass budget, but this is once per
        /// *stroke*, never per dab, and `liveMaskStrokeBegan` on the same touch already builds a
        /// whole `RenderRequest`. It schedules no composite: `makeSandwichKey` freezes the active
        /// layer's content version for the dab's duration, so the key has not moved and the
        /// compositor stays off the drawing path.
        private func applySandwichPresentationNow() {
            let tree = canvasManager.renderTree(atFrame: canvasManager.currentFrame)
            updateSandwich(tree: tree, engaged: isSandwichEngaged(tree))
        }

        /// The baker this coordinator has already given its callback to.
        ///
        /// **Weak and compared by identity rather than assigned once**, because `syncFrameBake`
        /// replaces the baker when the store's root moves — a different project, or the artist
        /// moving the Render Resolution knob. A callback installed once in `makeUIView` would be
        /// left on the discarded baker, and the canvas would stop being told its frames had landed
        /// the moment the knob was touched: §2.10 with no way out of it.
        private weak var observedFrameBaker: FrameBaker?

        /// Runs the sweep, starts the loop, and adopts whichever baker came out of it.
        ///
        /// Called from `reconcileLayers` — see `CanvasManager.syncFrameBake` for why that is the
        /// cadence rather than a hook.
        private func syncFrameBake() {
            canvasManager.syncFrameBake(suspended: isSandwichStrokeLive)
            let baker = canvasManager.frameBaker
            guard observedFrameBaker !== baker else { return }
            observedFrameBaker = baker
            baker.observeFrameFinished(self) { [weak self] frame in
                self?.bakerDidFinish(frame: frame)
            }
        }

        /// Picks the presentation, schedules a rebuild when the key has moved, and applies both.
        ///
        /// Called at the end of `reconcileLayers` — so every host exists and has had its own
        /// `isHidden`/`alpha`/interaction settled — and again from the far end of each rebuild.
        private func updateSandwich(tree: [RenderNode], engaged: Bool) {
            guard let belowView = sandwichBelowView, let aboveView = sandwichAboveView else { return }

            /// Every exit from this function agrees with the view stack about who is painting the
            /// paper — see `compositeCarriesThePaper`. Cheap enough to call unconditionally: every
            /// write inside `updatePaper` is guarded by a read, so an idle pass costs comparisons.
            func paperIsNowPaintedBy(_ theComposite: Bool) {
                compositeCarriesThePaper = theComposite
                updatePaper()
            }

            guard engaged else {
                paperIsNowPaintedBy(false)
                // Before the early return below, which is reached on every pass once the canvas has
                // settled onto Core Animation's path: a live mask installed while the sandwich was
                // engaged has to come off when it disengages, and a stroke that began while it was
                // already disengaged has no other place to be cleaned up. Gated on the stroke being
                // over, so disengaging mid-stroke is not what takes the clip away.
                if !isSandwichStrokeLive, liveMaskImage != nil {
                    for host in layerHosts.values { host.setContentMask(nil) }
                    liveMaskImage = nil
                }
                guard sandwichPresentation != .disengaged || sandwichHalves != nil
                        || sandwichFull != nil else { return }
                // Everything back to today's path, and the images dropped rather than kept warm: three
                // canvas-sized images is 50 MB at 2048² and 192 MB at 4000² (§5.3), which is not a
                // cache to hold against a document that has stopped needing it. Re-engaging pays one
                // rebuild.
                belowView.image = nil
                belowView.isHidden = true
                aboveView.image = nil
                aboveView.isHidden = true
                for host in layerHosts.values { host.setBlanked(false) }
                sandwichHalves = nil
                sandwichKey = nil
                sandwichCacheKey = nil
                // The baked frame goes with them, and for the same accounting rather than to save
                // the bake: the file stays on disk and re-engaging pays one decode, but a
                // canvas-sized `UIImage` held for a canvas that has stopped showing it is 16 MB at
                // 2048² with nothing on screen to justify it. With the image, not after it —
                // `sandwichFullKey` says "the picture we are holding is this frame's", and once we
                // are holding none it is a claim about nothing.
                sandwichFull = nil
                sandwichFullKey = nil
                // The mask image goes with them and for the same reason — it is another canvas-sized
                // 16 MB, and re-engaging pays one `makeMaskImage` alongside the one rebuild.
                liveMaskCache = nil
                sandwichPresentation = .disengaged
                return
            }

            let key = makeSandwichKey(tree: tree)
            sandwichKey = key
            if key != sandwichCacheKey { startSandwichRebuild(for: key) }
            // **The rest picture comes off the bake now** (§3.6), so this is a lookup and not a
            // composite: ring, then store, then a miss. A miss changes nothing on screen (§2.10) and
            // `FrameBaker.onFrameFinished` brings the pass that turns it into a hit.
            refreshBakedFull(for: key)

            // **Nearest-neighbour is right at full resolution and wrong below it.** `makeSandwichView`
            // chooses `.nearest` because the composite is exactly canvas-sized, so the only scaling is
            // the container's zoom transform and bilinear would blur pixels the host views keep crisp.
            // A reduced-resolution composite breaks that premise: the image is genuinely smaller than
            // the view, so *something* has to interpolate, and nearest turns one composite pixel into
            // a hard 2x2 block. That reads as a broken renderer rather than as a soft preview, which
            // is the difference between an artist using this setting and reporting it as a bug.
            //
            // **Asked of the image rather than of the setting, which is a correction.** The picker is
            // what the *next* composite will be sized by; this filter has to describe the image that
            // is on screen *now*, and those disagree for as long as a rebuild takes. Moving the knob
            // to Full leaves the previous position's halves displayed until the new pair lands, so
            // reading the picker would choose nearest for an image that genuinely needs
            // interpolating, and the blocky result would look like the bug the comment above exists
            // to prevent.
            // Either product answers: the bake and the halves are minted at one size, which is
            // `FrameBaker.recipe`'s whole argument for `.liveComposite`.
            let composited = sandwichFull?.size ?? sandwichHalves?.below.size ?? .zero
            let isReduced = composited != .zero
                && composited != (canvasManager.canvasSize ?? composited)
            let filter: CALayerContentsFilter = isReduced ? .linear : .nearest
            if belowView.layer.magnificationFilter != filter {
                belowView.layer.magnificationFilter = filter
                aboveView.layer.magnificationFilter = filter
            }

            // **Trap 2: stay mid-stroke until this frame's bake lands.** On lift the key unfreezes,
            // so the baker's key moves too and its file does not exist yet; flipping to rest right
            // away would show the picture composited *before* the stroke existed, and the artist
            // would watch their just-finished stroke vanish and come back a beat later.
            // `sandwichFullKey != key` is exactly "the frame lift asked for has not landed yet", and
            // it is the same condition this trap used before the bake existed — `sandwichCacheKey`
            // named the rebuild that was going to produce `full`, and this names the bake that is.
            //
            // Holding the mid-stroke pair is the *right* picture to hold meanwhile, not merely the
            // older one: the stroke is committed to the cel, the active host still draws it, and it
            // sits between two halves that never contained it.
            let midStroke = isSandwichStrokeLive
                || (sandwichPresentation == .midStroke && sandwichFullKey != key)

            // **Trap 1: do not blank the hosts until there is something to blank them in favour
            // of.** On the very first engage nothing is cached, and blanking now would flash an
            // empty canvas for however long the composite takes. Asked of the presentation actually
            // about to be applied, because the two now come from two places and either can be the
            // one that is missing.
            if midStroke {
                guard let halves = sandwichHalves else { return paperIsNowPaintedBy(false) }
                if belowView.image !== halves.below { belowView.image = halves.below }
                if aboveView.image !== halves.above { aboveView.image = halves.above }
            } else {
                guard let full = sandwichFull else { return paperIsNowPaintedBy(false) }
                if belowView.image !== full { belowView.image = full }
                // Nothing in the upper view at rest: the baked frame is the whole tree, so a second
                // image over it would be everything above the active layer drawn a second time.
                if aboveView.image != nil { aboveView.image = nil }
            }
            if belowView.isHidden { belowView.isHidden = false }
            let hideAbove = !midStroke
            if aboveView.isHidden != hideAbove { aboveView.isHidden = hideAbove }

            // The active layer's host is the middle of the sandwich and the only one that draws
            // itself; everything else is in one of the two composites already. At rest even that one
            // is blanked, because `full` includes it.
            let activeID = canvasManager.layers.indices.contains(canvasManager.currentLayerIndex)
                ? canvasManager.layers[canvasManager.currentLayerIndex].id : nil
            for (id, host) in layerHosts {
                let drawsItself = midStroke && id == activeID
                host.setBlanked(!drawsItself)
                // §6.4 rides on exactly the same predicate as blanking, which is the point: the one
                // host drawing its own pixels is the one place a mask can be applied, and every
                // other host's pixels are inside a composite that has already been clipped. Tying
                // the two together is also what removes the flash at both ends — the clip arrives
                // the moment the host starts drawing itself and leaves the moment `full` takes over,
                // rather than on the touch events, which are a beat early and a beat late.
                host.setContentMask(drawsItself ? liveMaskImage : nil)
            }
            // Trap 2 above keeps `midStroke` true until the rebuild lift asked for lands, so this is
            // the lift, not the touch-up — releasing it any earlier would drop the clip while the
            // host is still the thing on screen.
            if !midStroke { liveMaskImage = nil }
            sandwichPresentation = midStroke ? .midStroke : .rest
            // Both presentations put an image carrying the paper in `belowView` — `full` at rest,
            // `below` mid-stroke — so from here the `paperView` would be a second copy of it.
            paperIsNowPaintedBy(true)
        }

        // MARK: §6.4's live mask

        /// The mask clipping the active layer, resolved at the current stroke's first touch and held
        /// unchanged until it lifts — **§6.4's "the mask is static for the duration of a stroke"**,
        /// stored rather than recomputed because that is the whole of the guarantee. Nil when nothing
        /// clips the active layer, which is almost every document.
        private var liveMaskImage: CGImage?

        /// The last coverage turned into an image, and the coverage it came from.
        ///
        /// **The cache is here rather than on `ResolvedMask`, deliberately.** One `ResolvedMask` is
        /// shared by every layer using it and is read from `sandwichQueue`'s off-main rebuild, so a
        /// `lazy var` filled in on first access there is a data race — which is why
        /// `makeMaskImage()` is a method, and it must stay one.
        ///
        /// Identity is a sound key *because the entry retains the mask it keys on*: `MaskResolver`'s
        /// own cache hands back the same object for the same masks over the same content versions and
        /// a new one for anything else, so `===` answers "the same coverage" — but only while the old
        /// object cannot be deallocated and a new one land at its address. The same ABA hazard
        /// `LayerContentVersion` documents, closed the same way.
        private var liveMaskCache: (mask: ResolvedMask, image: CGImage)?

        /// Resolves the active layer's mask and installs it, from `onStrokeBegan`.
        ///
        /// Installed here rather than left to the next `updateSandwich` because there may not be one:
        /// a dab publishes nothing, so the pass that would install it is the pass this stroke is
        /// deliberately not causing. `updateSandwich` maintains it from here on.
        private func liveMaskStrokeBegan(host: LayerHostView?) {
            guard let host, let layerID = host.strokeView.layerID,
                  let index = canvasManager.layers.firstIndex(where: { $0.id == layerID }) else { return }
            liveMaskImage = resolveLiveMask(forLayerAt: index)
            host.setContentMask(liveMaskImage)
        }

        /// The coverage clipping one layer, as an image `CALayer.mask` can apply.
        ///
        /// **`makeRenderRequest` is what makes this agree with the compositor rather than merely
        /// resemble it.** `MaskResolver.coverage` keys on the masks plus the content versions of the
        /// layers they read, and a request built here carries the same `maskStacks` (derived from the
        /// whole tree, not from a sandwich half) and the same `contentVersions` as the three the
        /// rebuild composites — so this call and the compositor's hit the same cache entry and get
        /// back the same object. Not an equal mask: the same one.
        ///
        /// **`RenderSizing.liveComposite` is the other half of that claim, and without it the
        /// sentence above was true only at Full.** `MaskResolver.CacheKey` carries width and height,
        /// so a native-size resolve here and a reduced one in `makeSandwichRecipe` are two entries —
        /// two `ResolvedMask`s over two
        /// disjoint sets of canvas-sized `PixelOps.rasterize` flattens, evicting each other inside one
        /// budget, on exactly the documents that have masks to resolve.
        ///
        /// It is also cheap despite building a whole request, because `PixelOps.rasterize` is
        /// memoized on cel identity *and size* and the rebuild has just walked the same cels at the
        /// same size. `includeBackground` is false to match what `makeSandwichRecipe` passes, though
        /// nothing downstream reads it — `MaskResolver` composites each source stack onto transparency
        /// regardless.
        private func resolveLiveMask(forLayerAt index: Int) -> CGImage? {
            // The same frame the request below is built at, and it has to be: the two are compared
            // against each other by `MaskResolver`'s cache, so a tree derived at one frame and a
            // request at another would be a cache key describing a document that never existed.
            guard let masks = RenderNode.masksClipping(leafAt: index,
                                                       in: canvasManager.renderTree(atFrame: canvasManager.currentFrame)),
                  !masks.isEmpty,
                  let request = canvasManager.liveMaskRequest(atFrame: canvasManager.currentFrame),
                  let resolved = MaskResolver.coverage(for: masks, of: request) else { return nil }
            if let cached = liveMaskCache, cached.mask === resolved { return cached.image }
            guard let image = resolved.makeMaskImage() else { return nil }
            liveMaskCache = (mask: resolved, image: image)
            return image
        }

        // MARK: The cache key

        // `LayerContentVersion` — one layer's pixels at one frame, by model identity — used to be
        // declared here. It moved to `RenderRequest.swift` in phase 6, unchanged, when
        // `MaskResolver`'s cache turned out to need exactly the same answer; the request carries it
        // for both. Its doc comment carries the reasoning this key exists at all.

        /// What §5.2's cached composites depend on — everything *except* the live stroke.
        ///
        /// The same rule governs what may be in it as governs `InterpolationPreviewKey` above: every
        /// evaluation input, and nothing that moves per dab. **It is no longer *modelled* on that key,
        /// which as of 2026-08-29 has no field list to model** — it is `DerivedCelContent.identity`
        /// plus a quality. This one still enumerates by hand, because a composite's inputs are the
        /// tree and the document rather than one derivation; what it does not enumerate by hand any
        /// more is `contents`, which comes from `CanvasManager.contentVersion(ofLayer:atFrame:)` so
        /// that it and `leafSnapshots` cannot be short different fields. The derived tree carries every
        /// structural and group property already (`[RenderNode]` is `Equatable`), so it is most of
        /// the key on its own; the frame and the per-layer content versions are what it does not
        /// carry, and the active index is what decides *where the tree is cut*.
        ///
        /// `activeLayerIndex` moving rebuilds `below` and `above`, which is exactly right —
        /// switching layers changes where the tree is cut. **It reaches the rest picture not at all**,
        /// and no longer needs a second key beside this one to say so: the rest picture is the baked
        /// frame, `FrameBakeKey` has no field for the active leaf, so a layer tap is a hit in the
        /// ring rather than a composite that was going to be skipped. This key is also what
        /// `refreshBakedFull` compares against, and soundly — it carries strictly more than the bake
        /// key does, so a `SandwichKey` that has not moved is a `FrameBakeKey` that has not moved.
        private struct SandwichKey: Equatable {
            let tree: [RenderNode]
            let activeLayerIndex: Int
            let frame: Int
            /// Parallel to `layers`; nil where a layer has no cel at this frame.
            let contents: [LayerContentVersion?]
            /// **An evaluation input like any other, and the one that is easiest to leave out.**
            /// `RenderResolution` changes the size of every cached image without changing a
            /// single thing this key otherwise reads — not the tree, not a content version, not the
            /// frame — so omitting it leaves the canvas showing the previous resolution's images until
            /// something unrelated happens to move the key. That is not a stale *picture*, which this
            /// cache tolerates by design; it is a control that visibly does nothing when you use it.
            let renderResolution: RenderResolution
            /// **The paper is inside `full` and `below` now** (EFFECT_BACKDROP.md §6 step 3), so it is
            /// an evaluation input and belongs here for exactly `renderResolution`'s reason above.
            ///
            /// This is the key that decides whether to *rebuild at all* — and, through
            /// `refreshBakedFull`, whether the baked frame on hand is still this frame's. Without it
            /// nothing recomposites when the artist recolours the canvas. `FrameBakeKey` carries the
            /// resolved colour for the same reason from the other side of the seam.
            let canvasBackgroundColor: Color
            /// Invisible is not the same key as white — it is the difference between an effect
            /// grading a backdrop and an effect grading nothing, which is the whole subject here.
            let isCanvasBackgroundVisible: Bool
        }

        /// The active layer's content version as of the first key built after a vector text edit
        /// opened, and the layer it belongs to. Nil whenever no such edit is live.
        ///
        /// **Latched forward, not backward, and that is the difference from `isSandwichStrokeLive`.**
        /// A dab publishes nothing, so holding the *previous* pass's version is exactly right for a
        /// stroke. Opening a text edit does the opposite: it sets `VectorCanvas.editingElementID`,
        /// which invalidates, so the previous pass's version is the one that still had the object in
        /// the flatten — freezing against it would leave the committed glyphs composited underneath
        /// the live editor, i.e. the artist would see their text twice. So the first key after the
        /// session opens is computed fresh and *then* held for the rest of it.
        private var textEditHeldContent: (layerIndex: Int, content: LayerContentVersion?)?

        private func makeSandwichKey(tree: [RenderNode]) -> SandwichKey {
            let frame = canvasManager.currentFrame
            let active = canvasManager.currentLayerIndex
            let held = sandwichKey?.contents
            // `ADD_TEXT.md` §4 rule 5, the belt to rule 4's braces: a text edit session bumps the
            // canvas exactly twice (open, commit) on its own, and this stops anything *else* — a
            // timeline tick is the case §4 names — moving the key mid-session and paying for the
            // 276 ms snapshot `RenderRequest` records as the expensive half of a composite.
            let textEditLive = canvasManager.isTextEditLive
            if !textEditLive { textEditHeldContent = nil }
            let contents = canvasManager.layers.indices.map { index -> LayerContentVersion? in
                // **The active layer's content version is in the key only while no stroke is in
                // progress, and that one clause is both halves of the contract.** During a dab the
                // version is held at whatever it was when the dab started, so stamping invalidates
                // nothing and the compositor stays off the drawing path (§2 forbids it being on it).
                // On lift it goes live again, the key moves, and the canvas snaps to the exact
                // composite. Held rather than elided so that *starting* a stroke does not move the
                // key either — the state switch has to be an image swap, not a rebuild.
                if isSandwichStrokeLive, index == active, let held, held.indices.contains(index) {
                    return held[index]
                }
                if textEditLive, index == active, let latch = textEditHeldContent, latch.layerIndex == index {
                    return latch.content
                }
                // **`valueFill`, `effect` and the derivation are all in there, and none of them is
                // spelled out here any more.** They used to be, and the list was one field short: a
                // cel's *derivation* — what an interpolated in-between shows rather than stores — was
                // missing, so the key did not move when `t` moved and the canvas would have frozen on
                // the first in-between it composited the moment the sandwich started engaging on one.
                // Nothing about that failure looks wrong: `t` lives on the `Cel` and moves no version
                // number, and `SandwichKey` goes on comparing the whole node tree, so the composite
                // rebuilds dutifully from a stale leaf (KEYFRAMES §4.5).
                //
                // The answer is not a fourth argument here but **one builder** —
                // `CanvasManager.contentVersion(ofLayer:atFrame:)`, which `leafSnapshots` also goes
                // through. `SandwichKey` is documented as that function's mirror; sharing the field
                // list is what makes the claim structural rather than a promise two files keep by
                // hand. It resolves at `frame` for the same reason: a mirror that asks a different
                // question is the one shape a reader checking them will not catch.
                guard let content = canvasManager.contentVersion(ofLayer: index, atFrame: frame) else {
                    if textEditLive, index == active { textEditHeldContent = (index, nil) }
                    return nil
                }
                if textEditLive, index == active { textEditHeldContent = (index, content) }
                return content
            }
            return SandwichKey(tree: tree, activeLayerIndex: active, frame: frame, contents: contents,
                               renderResolution: canvasManager.renderResolution,
                               canvasBackgroundColor: canvasManager.canvasBackgroundColor,
                               isCanvasBackgroundVisible: canvasManager.isCanvasBackgroundVisible)
        }

        // MARK: Rebuilding

        /// Serialises the **whole** of every rebuild off the main thread — since RENDER.md stage 2
        /// that includes resolving the recipe's pixels, not only compositing them. `RenderRequest` is
        /// a pure value (§9.1 point 3 designed it to be exactly this) and `SandwichRecipe` is the
        /// instruction for building one, so the only main-thread work left is minting the recipe —
        /// O(layers), no pixel — and the assignment on the way back.
        private static let sandwichQueue = DispatchQueue(label: "com.paintapp.CanvasView.sandwich",
                                                         qos: .userInitiated)

        /// Asks the baker for this frame's finished picture, and holds it.
        ///
        /// **A miss leaves everything alone**, which is the whole of §2.10 in one line: the image and
        /// the key it belongs to move together or not at all, so a canvas holding frame 4's picture
        /// while the playhead sits on an unbaked frame 5 goes on showing frame 4 and *says* it is
        /// showing frame 4 — which is what trap 2 in `updateSandwich` reads to decide whether the
        /// rest presentation is ready.
        ///
        /// Gated on the key so that a hit is one dictionary comparison per pass rather than a mint
        /// and a digest. The mint behind `FrameBaker.image(atFrame:)` is O(layers) with no pixel
        /// work, but it is O(layers) on the main thread on every SwiftUI pass, and a canvas at rest
        /// has a great many passes that change nothing.
        private func refreshBakedFull(for key: SandwichKey) {
            guard sandwichFullKey != key else { return }
            guard let image = canvasManager.frameBaker.image(atFrame: canvasManager.currentFrame) else {
                return
            }
            sandwichFull = UIImage(cgImage: image, scale: 1, orientation: .up)
            sandwichFullKey = key
        }

        /// The baker's *"this frame is ready"*, wired to the canvas that is showing the previous one.
        ///
        /// Installed once from `makeUIView` — §2.10's other half. Without it a frame that lands
        /// while nothing else is happening sits on disk until some unrelated pass comes along, which
        /// is the "a control that visibly does nothing" failure in its rendering costume: at rest
        /// there is no next pass, because a canvas nobody is touching publishes nothing.
        private func bakerDidFinish(frame: Int) {
            guard frame == canvasManager.currentFrame else { return }
            applySandwichPresentationNow()
        }

        private func startSandwichRebuild(for key: SandwichKey) {
            // **Mutual exclusion, not a discard, and the difference is `finishSandwichRebuild`.**
            // §3.6 rules that the bake queue *"reorders, it never discards"*, and `FrameBaker`
            // honours that with `isBaking` — a flag every path clears before kicking again. This is
            // the same contract in the same shape: the far end reconciles, which re-derives the key
            // from the model and starts the rebuild this call declined, so a request arriving
            // mid-rebuild waits one iteration rather than evaporating. What it does *not* do is
            // start a second composite per SwiftUI pass, which on a serial queue during a scrub
            // would queue a rebuild per display frame and hand the artist a minutes-long backlog of
            // pictures nobody will see.
            guard !isSandwichRebuilding else { return }
            // Nil for a stale or non-leaf `activeLayerIndex`, or a degenerate canvas — it does not
            // fall back to `full`, deliberately, so that a wrong cut is never composited. The canvas
            // keeps showing whatever is cached (at most one edit stale), or stays on Core Animation's
            // path when nothing is cached yet. Both windows are one SwiftUI pass long in practice:
            // the index is only out of range between a delete and the reselect that follows it, and
            // the next pass schedules the rebuild this one declined.
            guard let recipe = canvasManager.makeSandwichRecipe(atFrame: canvasManager.currentFrame,
                                                                activeLayerIndex: canvasManager.currentLayerIndex)
            else { return }

            isSandwichRebuilding = true
            Self.sandwichQueue.async { [weak self] in
                // **The flatten happens here now, not on the main actor before the hop** — RENDER.md
                // §3.2. `resolve()` is pure over the values `makeSandwichRecipe` froze, so an edit
                // the artist makes while this runs reaches the live tiers and not these; the picture
                // that lands is the one the recipe named, which is at worst one edit stale and is
                // exactly what `finishSandwichRebuild`'s key check already tolerates.
                //
                // **`full` is deliberately not composited here.** It is the same product as the
                // baked frame, and §2.15 allows exactly one producer of it; that producer is
                // `FrameBaker`, which chunks the walk under a memory ceiling (§3.4) and writes the
                // result where play and export can read it. `SandwichRecipe.resolve()` still mints
                // it because the *cut* is defined against it — `below` and `above` are correct
                // precisely when they recompose to `full` — and that invariant is what
                // `SandwichLogicTests` pins. Nothing on the canvas resolves it.
                //
                // **`compositeHalves` rather than `Compositor.composite`, and that is the whole of
                // RENDER.md §2.12 on this path.** It takes each half through `StripedCompositor` and
                // `ChunkedCompositor` — the same two cuts the bake takes — so a document whose
                // textures do not fit the device is composited in horizontal bands at the size the
                // knob asked for, rather than refused by the GPU and re-rendered whole on the CPU
                // reference for the duration of every stroke. A document that fits takes the
                // identical path it took before: one composite per half, unwindowed, unchunked.
                let halves = recipe.compositeHalves()
                Task { @MainActor in
                    self?.finishSandwichRebuild(key: key, below: halves?.below, above: halves?.above)
                }
            }
        }

        private func finishSandwichRebuild(key: SandwichKey, below: CGImage?, above: CGImage?) {
            isSandwichRebuilding = false
            // Both or neither: a half-updated pair would put a `below` from this frame under an
            // `above` from the last one. `composite` returns nil only for a degenerate canvas.
            if let below, let above, key == sandwichKey {
                sandwichHalves = (below: UIImage(cgImage: below, scale: 1, orientation: .up),
                                  above: UIImage(cgImage: above, scale: 1, orientation: .up))
                sandwichCacheKey = key
            }
            // The whole reconciliation rather than only the image swap: this result may be the first
            // one, and the first one is what unblocks blanking the hosts (trap 1 in `updateSandwich`).
            // It is also what starts the next rebuild when this result was the stale one — the key it
            // recomputes is the model's current answer, not the one this rebuild was asked for — and
            // that is the whole of the "a declined request waits one iteration" contract the guard at
            // the top of `startSandwichRebuild` rests on.
            reconcileLayers()
        }

        // MARK: - Vector-layer transform overlay

        /// Drives `ObjectTransformOverlayView` from the lifted piece the Move tool is holding — the
        /// only remaining user of this overlay, and since TODO item (12) stage 2 its only arm.
        ///
        /// **A producer, not a consumer of `CanvasTouchOwner`.** What this feeds into the shared
        /// answer is `ObjectTransformOverlayView.claimsTouch(at:)`, via `canvasChrome(at:)`.
        ///
        /// **It does not consult layer visibility, deliberately** — see
        /// `CanvasTouchInputs.moveBoxIsUp`, which is this function restated and carries the ruling.
        /// The second arm it used to have, a whole vector layer mid-`isVectorTransforming`, did
        /// consult it; that arm and its flag are gone.
        func updateTransformOverlay() {
            guard let overlay = transformOverlay, let container = containerView else { return }
            if let float = canvasManager.vectorFloat,
               canvasManager.layerIndex(ofID: float.layerID) != nil {
                let pose = liveVectorFloatPose ?? Self.pose(of: float)
                // **The box is fitted, not the lift's** — `CanvasManager.fittedFrame(of:at:)` hugs
                // the ink in the box's own turned frame (LASSO_MOVE.md §5.22). It returns a frame
                // and writes nothing, so the float's own `contentSize` stays the lift's.
                overlay.update(isActive: true,
                               frame: CanvasManager.fittedFrame(of: float, at: pose),
                               canvasScale: canvasContentScale)
                container.bringSubviewToFront(overlay)
                return
            }
            deactivateTransformOverlay()
        }

        /// Hides the box, and ends any drag it was in the middle of.
        ///
        /// The second half is not belt and braces. A float can be settled out from under the artist's
        /// own finger — `rasterizeLayer` and `handleActiveContextChanged` both do it — and a live drag
        /// left latched on the stroke view would leave the piece showing a Core Animation transform
        /// nothing ever clears.
        private func deactivateTransformOverlay() {
            endObjectTransformDrag()
            transformOverlay?.deactivate()
        }

        // MARK: - The Move tool's floating piece

        /// The float's handle drag in flight. It used to have a sibling, `activeObjectTransform`, for
        /// the whole-layer arm; that arm is gone (TODO item (12) stage 2) and every Move drag on a
        /// vector layer — lassoed region or whole cel — is now this one latch.
        private var activeVectorFloatDrag: ObjectTransformDrag?

        /// Where the box is *right now*, while the finger is down — its similarity **and** its
        /// Freeform aspect, since the two together are the pose and either alone draws the box in a
        /// place the piece is not.
        ///
        /// **Held here rather than on the model, and that is the point.** `vectorFloat` is
        /// `@Published`, so writing the live value would put a whole SwiftUI pass on every touch-move
        /// of a gesture built specifically not to have one. The model learns the answer once, at the
        /// gesture's end, where it becomes one undo step.
        private var liveVectorFloatPose: ObjectTransformDrag.Pose?

        /// The pose a float is resting at — its box transform, its aspect and its hand-turned box
        /// angle, read as one value so no call site can pick up one and forget the others.
        ///
        /// The box angle joined for exactly that reason: it is the third field the box is drawn from,
        /// and a rebuild that read the other two would straighten a box the artist had turned on the
        /// first SwiftUI pass after the gesture ended.
        private static func pose(of float: VectorFloat) -> ObjectTransformDrag.Pose {
            ObjectTransformDrag.Pose(transform: float.frame.transform, aspect: float.frame.aspect,
                                     boxAngle: float.frame.boxAngle,
                                     stretchAxis: float.frame.stretchAxis)
        }

        /// Reconciles the layer host and the marching ants with `canvasManager.vectorFloat`, on every
        /// pass, the same self-healing shape as every other `update…` here.
        ///
        /// The latch is *armed* here rather than by the model, because arming it renders — and the
        /// model has no business rasterizing. `hasVectorFloat` is what keeps a pass that changes
        /// nothing free.
        func updateVectorFloat() {
            guard let float = canvasManager.vectorFloat, float.wantsLatch,
                  let host = layerHosts[float.layerID],
                  let vector = canvasManager.vectorCanvas(ofFloat: float) else {
                for host in layerHosts.values { host.strokeView.endVectorFloat() }
                selectionOverlay?.setLiveSelectionTransform(rasterFloatAntsTransform())
                return
            }
            if !host.strokeView.hasVectorFloat {
                // `latchedFrameTransform`, not the lift's: a `mayDiverge` float drops its latch
                // between gestures and re-arms against geometry that has since moved, so the bitmap
                // and the base it is measured from have to describe the same moment.
                host.strokeView.beginVectorFloat(
                    image: vector.renderIsolated(ids: float.insideIDs),
                    base: VectorCanvas.affine(from: float.latchedFrameTransform,
                                              aspect: float.latchedAspect,
                                              stretchAxis: float.latchedStretchAxis,
                                              pivot: float.pivot))
            }
            showVectorFloat(float, at: liveVectorFloatPose ?? Self.pose(of: float))
            if let container = containerView, let overlay = transformOverlay {
                container.bringSubviewToFront(overlay)
            }
        }

        /// The raster Move's version of travelling ants. Its piece writes its transform to the model
        /// on every delta already (`updateFloatingPose`), so unlike the vector float this needs
        /// no live latch of its own — it is the same one transform on the outline, read off the piece.
        private func rasterFloatAntsTransform() -> CGAffineTransform {
            guard let piece = canvasManager.floatingPiece, piece.kind == .move else { return .identity }
            return piece.liftTransform.affineTransform.inverted()
                .concatenating(piece.transform.affineTransform)
        }

        /// One delta's worth of display: a `UIView.transform` on the latched piece, and one
        /// `CALayer` transform on each of the two marching-ants layers. No allocation, no rasterize,
        /// no model write.
        private func showVectorFloat(_ float: VectorFloat, at pose: ObjectTransformDrag.Pose) {
            let placement = VectorCanvas.affine(from: pose.transform, aspect: pose.aspect,
                                                stretchAxis: pose.stretchAxis, pivot: float.pivot)
            // The piece is measured from where its *bitmap* sits, which is the lift for an ordinary
            // float and the last nudge for a re-armed one — `latchedAspect` as well as
            // `latchedFrameTransform`, or a stretch already in the bitmap would be applied twice.
            layerHosts[float.layerID]?.strokeView.updateVectorFloat(placement)
            // The ants are measured from where the *model's* selection path sits, which is the last
            // nudge. Identity between gestures, which is when the two are the same thing.
            let written = VectorCanvas.affine(from: float.frame.transform, aspect: float.frame.aspect,
                                              stretchAxis: float.frame.stretchAxis,
                                              pivot: float.pivot)
            selectionOverlay?.setLiveSelectionTransform(written.inverted().concatenating(placement))
        }

        func beginObjectTransformDrag(_ handle: ObjectTransformFrame.Handle, at point: CGPoint) {
            // **Without `beginStructureGesture()`**: `StructureSnapshot` captures `layers` by value
            // while `Cel.vector` is a class reference, so it would record a step that reverts
            // nothing. The float writes its own step per gesture end instead.
            guard let float = canvasManager.vectorFloat else { return }
            // **The mode is latched here, once**, with the rest of the drag — see
            // `ObjectTransformDrag.isFreeform`. The Move bar's picker stays live while a piece
            // floats, and reading it per delta would change what the finger already down means.
            activeVectorFloatDrag = ObjectTransformDrag(frame: float.frame, handle: handle,
                                                        at: point,
                                                        freeform: canvasManager.vectorFloatIsFreeform)
            // **A box-only turn never arms the latch.** `beginVectorFloatDrag` re-suppresses the
            // piece so a drag can be shown as a Core Animation transform on its own bitmap; this
            // gesture moves no ink, so there is nothing to show — and on a `mayDiverge` float, which
            // sits *un*-latched between gestures precisely so the artist is looking at the truth,
            // arming it would swap the truth for an approximation for the length of a gesture that
            // changes nothing about the drawing.
            if handle != .boxRotation { canvasManager.beginVectorFloatDrag() }
            // Synchronously, not on the next SwiftUI pass: the first delta can arrive before one.
            updateVectorFloat()
        }

        /// One delta. **The whole per-touch-move cost of a Move drag is this function**, so what is
        /// not in it matters as much as what is: no `localContentBounds()`, no `render()`, no
        /// canvas-sized allocation. The model write is an affine assignment, the display is a
        /// `UIView.transform`, and the box redraws five `CALayer`s.
        func objectTransformDragged(to point: CGPoint) {
            // **The float's delta writes nothing to the model.** The piece is a latched bitmap under a
            // Core Animation transform and the ants are two `CALayer` transforms; the geometry catches
            // up once, at the gesture's end.
            if let drag = activeVectorFloatDrag, let float = canvasManager.vectorFloat {
                let pose = drag.pose(draggedTo: point)
                liveVectorFloatPose = pose
                showVectorFloat(float, at: pose)
                // The re-fit is the one thing this function gained that is *not* free: it walks the
                // lifted ink's points once per touch-move. `MoveBoxInk` is why that is a pass over an
                // array of `CGPoint` rather than a walk of the display list, and
                // `PerfBaselineTests.testWhatOneFrameOfTheBoxKnobCosts` is the measurement.
                transformOverlay?.update(isActive: true,
                                         frame: CanvasManager.fittedFrame(of: float, at: pose),
                                         canvasScale: canvasContentScale)
            }
        }

        func endObjectTransformDrag() {
            guard let drag = activeVectorFloatDrag else { return }
            let pose = liveVectorFloatPose
            activeVectorFloatDrag = nil
            liveVectorFloatPose = nil
            if let pose {
                if drag.handle == .boxRotation {
                    // **The one gesture on this box that is not a nudge, and it is a ruling rather
                    // than an optimisation** (LASSO_MOVE.md §5.21): turning the box costs no undo
                    // step, so it must not go through `nudgeVectorFloat` — a zero-delta nudge is
                    // still a step, and were it the first one it would be the step carrying the
                    // pre-split display list, so one Undo would rejoin the cut stroke and dismiss
                    // the float. Only `boxAngle` is read out of the pose; `pose.transform` is the
                    // pose the drag started at, bit for bit.
                    canvasManager.turnVectorFloatBox(to: pose.boxAngle)
                } else {
                    // One gesture, one nudge, one undo step. No `commitStructureGesture` — see
                    // `beginObjectTransformDrag`.
                    canvasManager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect,
                                                   stretchAxis: pose.stretchAxis)
                }
            }
            updateVectorFloat()
        }

        /// Spawns a block on the active layer when the stroke that is *just now beginning* landed on
        /// a frame no block covers, and hands its content tiers straight to the stroke view.
        ///
        /// Called from `onStrokeBegan`, which `StrokeCanvasView.handleBegin` invokes before it reads
        /// `vectorCanvas`/`raster` — so the tiers assigned here are the ones this very stroke stamps
        /// into. Going through `reconcileLayers` instead would not do: it runs on the next SwiftUI
        /// render, by which time `handleBegin` has already given up on a nil raster and the stroke
        /// the artist drew to create the block would be the one stroke the block never receives.
        ///
        /// A no-op when the frame already has a block, which is the overwhelmingly common case.
        private func attachSpawnedCelIfFrameIsEmpty(host: LayerHostView?) {
            let index = canvasManager.currentLayerIndex
            // The eraser is excluded: it only ever takes content away, so a touch with it on an
            // empty frame has nothing to act on, and spawning a block would leave a blank one behind
            // plus an undo step for a gesture that changed nothing the artist can see.
            guard canvasManager.selectedTool != .eraser else { return }
            guard let host, canvasManager.layers.indices.contains(index),
                  host.strokeView.layerID == canvasManager.layers[index].id,
                  canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame) == nil,
                  let celIdx = canvasManager.ensureCelAtCurrentFrame(layerIndex: index) else { return }

            let cel = canvasManager.layers[index].cels[celIdx]
            host.strokeView.raster = cel.raster
            host.strokeView.vectorCanvas = cel.vector
            host.fillImageView.image = cel.fillImage
            host.bakedImageView.image = cel.bakedImage
            host.bakedImageView.isHidden = cel.bakedImage == nil
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

        // MARK: - Who owns a canvas touch

        /// **The one value every gate on this canvas reads.** Fourteen decisions across three UIKit
        /// mechanisms used to spell their own predicate over these same inputs, and four defects —
        /// three of them inside one week — came out of two of those spellings disagreeing. They are
        /// stated once now, in `CanvasTouchOwner`, and this is the only place that gathers the inputs.
        ///
        /// **It takes them rather than reaching for them, and that is structural.** `activePanel` is
        /// `@State` on `DrawingView`, mirrored down to this coordinator; `selectedTool`,
        /// `floatingPiece` and the layer stack are on `CanvasManager`. No *object* can see all of it,
        /// which is why the answer could not live on either of them and why `CanvasTouchOwner` is a
        /// pure function over a value — the same argument, and the same testability, as
        /// `Tool.paintsOnCanvas`.
        ///
        /// `chrome` is the position-dependent half and is `.none` for every state-only gate. Pass
        /// `canvasChrome(at:)` when the question is about a particular point.
        func canvasTouchInputs(chrome: CanvasTouchChrome = .none) -> CanvasTouchInputs {
            let index = canvasManager.currentLayerIndex
            let layer = canvasManager.layers.indices.contains(index) ? canvasManager.layers[index] : nil
            // **Eight one-line reads and no decision, which is the point.** The one part of this that
            // had a decision in it — a layer's kind mapped to the kind the gates make of it — is
            // `CanvasActiveLayer.init(kind:)`, in the model, where a logic test can reach it. What is
            // left is eight fields, each the property it is named for, because this function is the
            // half of the arrangement nothing in the fast tier can link (see that initialiser's
            // comment, and `CanvasTouchInputs`' own, for the gap that leaves and what covers it).
            return CanvasTouchInputs(
                tool: canvasManager.selectedTool,
                fillMode: canvasManager.fillMode,
                panel: activePanel,
                hasFloatingPiece: canvasManager.floatingPiece != nil,
                hasVectorFloat: canvasManager.vectorFloat != nil,
                activeLayer: CanvasActiveLayer(kind: layer?.kind),
                activeLayerIsOnScreen: layer != nil && canvasManager.isLayerEffectivelyVisible(index),
                chrome: chrome)
        }

        /// Which overlay's `hitTest` claims this point, in the order UIKit would ask them — the five
        /// `hitTest` overrides asked once, in one place, instead of by whoever remembers to.
        ///
        /// **Container coordinates.** Every one of these overlays is pinned to `containerView`, so a
        /// point in the container's space is a point in each of theirs; `handleTextPress` has relied
        /// on that since it grew its own hand-rolled version of this function.
        ///
        /// **The order is a stated precedence, not a reading of the view stack.** Every one of these
        /// five is `bringSubviewToFront`-ed by its own `update*` pass, so their real z-order depends
        /// on which pass ran last and is not something this function could ask. Only the first two
        /// are load-bearing today — `handleTextPress`, the one caller, asks whether the point is a
        /// live text box or one of its grips, and the text grips come first for the reason
        /// `makeUIView` gives where it adds them: a corner's target overlaps the move band, and the
        /// resize is the more specific gesture. A caller that needs a different tie-break between the
        /// other three should say so here rather than at its own site.
        func canvasChrome(at point: CGPoint) -> CanvasTouchChrome {
            if textTransformOverlay?.claimsTouch(at: point) == true { return .textHandle }
            if textOverlay?.claimsTouch(at: point) == true { return .textBoxOrBand }
            if transformOverlay?.claimsTouch(at: point) == true { return .transformBoxOrHandle }
            if shapeOverlay?.claimsTouch(at: point) == true { return .shapeHandleOrOutline }
            if guideOverlay?.claimsTouch(at: point) == true { return .guideGrip }
            return .none
        }

        // MARK: - Select & Move overlays

        /// Whether the fill tool's lasso mode currently owns the selection overlay's lasso gesture.
        /// The predicate and the reasoning are `CanvasTouchInputs.isLassoFilling`'s.
        var isLassoFilling: Bool { canvasTouchInputs().isLassoFilling }

        // **`isEyedropperArmed` was here and is deleted**, because both of its readers now take
        // `eyedropperPressIsEnabled` and `selectionOverlayIsCapturing` off the shared value instead —
        // and a forwarding property nobody reads is the thing that drifts next. It was the 2026-08-22
        // pick-tool fix, this idea applied exactly once; the reasoning is now on
        // `CanvasTouchInputs.isEyedropperArmed`, which is where searches for the name should land.

        func updateSelectionOverlay() {
            guard let overlay = selectionOverlay, let container = containerView else { return }
            let touch = canvasTouchInputs()
            let lassoFilling = touch.isLassoFilling
            overlay.mode = lassoFilling ? .lasso : canvasManager.selectionMode
            // Mirrored down every pass, same as `reconcileLayers` mirrors it to
            // `StrokeCanvasView.pencilOnlyDrawing` — see `SelectionOverlayView.pencilOnlyDrawing`'s
            // doc comment for why a selection drag needs this too. A lasso fill is a drawing edit by
            // the same test, so borrowing this recognizer also inherits the fix for free.
            overlay.pencilOnlyDrawing = canvasManager.pencilOnlyDrawing
            // `CanvasTouchInputs.selectionOverlayIsCapturing` — the same value
            // `updateActiveLayerAndTool` reads for the eyedropper's recognizer, which is the point:
            // its `!isEyedropperArmed` term is this overlay's half of the 2026-08-22 fix, and the two
            // sites disagreeing about it is what left the picking tap owned by nobody.
            overlay.isCapturingGestures = touch.selectionOverlayIsCapturing
            // The exterior hatch says "you cannot paint out there". While a piece is floating nobody
            // can paint anywhere — every host has declined interaction — so the stripes would be
            // stating a restriction that is not the live one, over artwork the artist is trying to
            // line the piece up against. The outline still shows, and travels with the piece.
            let floating = canvasManager.vectorFloat != nil || canvasManager.floatingPiece?.kind == .move
            overlay.updateSelection(canvasManager.selection,
                                    allowsOutsideInteraction: canvasManager.allowsPaintingOutsideSelection || floating)
            // LASSO_FILL.md §7.2/§7.4, pushed down the same way everything else here is: the overlay
            // decides whether this is new and owns the fade, so a pass that changes nothing costs a
            // UUID comparison. It is drawn here rather than over the layer stack because the tint has
            // to stay registered to the artwork when the artist zooms in to find their gap, and this
            // view is inside the transformed container.
            overlay.showLassoDiagnostic(canvasManager.lassoFillDiagnostic)
            // Layer hosts are added after this overlay, so without this the marching ants/hatch
            // render underneath layer content — bring it back to front when it has something to show.
            if overlay.isCapturingGestures || canvasManager.selection != nil
                || canvasManager.lassoFillDiagnostic != nil {
                container.bringSubviewToFront(overlay)
            }
        }

        func updateFloatingOverlay() {
            floatingOverlay?.update(canvasManager.floatingPiece,
                                    isInteractive: canvasTouchInputs().floatingOverlayIsInteractive)
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
            // First, and outside both guards: this is the funnel every shape-state transition already
            // goes through, so it is where the published `shape:` field stays honest even on the
            // passes that return early below.
            publishCanvasState()
            guard let overlay = shapeOverlay, let container = containerView else { return }
            guard canvasManager.shapeGestureActive, let shape = canvasManager.resolvedShape else {
                overlay.isActive = false
                return
            }
            let isAdjustable = canvasManager.isShapeInAdjustableState
            overlay.isActive = true
            // Set here as well as in `applyTransform`, so neither ordering of "transform changed" vs
            // "overlay appeared" can leave the handles the wrong size for a frame.
            overlay.canvasScale = canvasContentScale
            // Render inline the first time so the shape isn't invisible for a frame; the
            // coalescing below carries subsequent renders.
            if canvasManager.activeShapePreviewImage == nil { canvasManager.renderActiveShapePreview() }
            overlay.update(shape: shape,
                           previewImage: canvasManager.activeShapePreviewImage,
                           showHandles: isAdjustable)
            scheduleShapePreviewRenderIfNeeded()
            // Above every layer host so it's visible and hit-testable; interaction is disabled
            // during shape following so touches pass through to the stroke view instead.
            //
            // **A producer, not a consumer of `CanvasTouchOwner`, and deliberately left one.**
            // `isShapeInAdjustableState` turns on `shapeGestureActive` and `resolvedShape` — state
            // none of that type's four inputs can see — so it cannot be an answer read back out of
            // it. What it feeds in is `ShapeOverlayView.claimsTouch(at:)`, which is the half of this
            // view's `hitTest` that *is* arbitration, and which `canvasChrome(at:)` asks.
            container.bringSubviewToFront(overlay)
            overlay.isUserInteractionEnabled = isAdjustable
        }

        /// Pushes the live text session down to the on-canvas editor, and nothing else. Cheap on
        /// every pass where nothing changed — `TextOverlayView.update` is written around that, since
        /// this runs on every SwiftUI pass like every other `update*` here.
        func updateTextOverlay() {
            guard let overlay = textOverlay, let container = containerView else { return }
            let active = canvasManager.textGestureActive
            overlay.update(isActive: active,
                           frame: canvasManager.textFrame,
                           recipe: canvasManager.textRecipe,
                           canvasScale: canvasContentScale)
            // Fed the same frame on the same pass, so the grips and the outline they grip cannot be
            // a frame apart. Handles stay up for the whole session, keyboard or not — an artist
            // sizing a wrap width does it while reading the text.
            //
            // **With one exception, added in stage 5: a `.projective` box being typed into.**
            // ADD_TEXT.md §1's unwarp-while-typing rule puts a *flat* box on screen there while the
            // model keeps the warped quad, so grips drawn from the model would sit on a quad the
            // artist cannot see, several inches from the box they are looking at. Illustrator hides
            // its envelope handles inside "edit contents" for the same reason. Tapping away restores
            // both the perspective and the grips.
            let flatEditing = canvasManager.textFrame.mode == .projective && canvasManager.textIsFocused
            textTransformOverlay?.update(isActive: active && !flatEditing,
                                         frame: canvasManager.textFrame,
                                         canvasScale: canvasContentScale,
                                         cornerMode: canvasManager.textCornerMode)
            guard active else { return }
            // Above every layer host so the box is visible and its band hit-testable. It claims only
            // the box and the band (`TextOverlayView.hitTest`), so everything else still falls
            // through to whatever is underneath.
            container.bringSubviewToFront(overlay)
            // And the grips above the editor, for the reason `makeUIView` states where they are
            // added: a corner's target overlaps the move band, and the resize is the more specific
            // gesture.
            if let textTransformOverlay { container.bringSubviewToFront(textTransformOverlay) }
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
        ///
        /// **`waitingForTheRender: true` is what keeps that name true after RENDER.md stage 2**, and
        /// it is the second of the two callers that ask for it (`beginVectorFloat` is the other). The
        /// whole point here is that the overlay showing the transient comes off in the same turn the
        /// baked ink goes on; a deferred render would put a frame between the two, which is exactly
        /// the flicker this function exists to prevent. A shape or fill commit is a discrete gesture
        /// rather than a per-pass cost, so paying a rasterize for it is a trade this makes knowingly.
        func syncLayerDisplays() {
            for host in layerHosts.values {
                host.strokeView.refreshDisplayIfStale(waitingForTheRender: true)
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
            // **All four container recognizers, from one value, above the active-layer guard.**
            // Each of them used to carry its own spelling of the same four inputs, and the fill's
            // sat *below* the two guards further down — so with no layers, or with a layer whose
            // host had not been built yet, it was never re-evaluated and kept whatever value it last
            // held. `CanvasTouchInputs.fillPressIsEnabled` states the answer the assignment means,
            // which is why it moves up here with the other two; the live consequence is that Fill on
            // a document with no layers now dismisses an open menu and does nothing, instead of
            // being an inert tool whose recognizer was never switched on. `beginInteractiveFill`
            // guards the empty document itself.
            //
            // The reasoning that used to sit on each of the three lines now sits on the property it
            // moved into: `isEyedropperArmed` (why the Select panel is deliberately absent, and the
            // owner's bug of 2026-08-22), `textPressIsEnabled` (why text's Select clause is *not*
            // that bug in a different hat — `ActionsMenu.addTextRow` closes the panel on the way in,
            // and `SelectionAndMoveUITests.
            // testEnteringTextModeClosesTheSelectPanelSoTextsOwnGuardCannotBite` pins the order),
            // and `fillPressIsEnabled` (why lasso mode hands the drag to the selection overlay).
            let touch = canvasTouchInputs()
            eyedropperTapRecognizer?.isEnabled = touch.eyedropperPressIsEnabled
            textTapRecognizer?.isEnabled = touch.textPressIsEnabled
            fillTapRecognizer?.isEnabled = touch.fillPressIsEnabled
            // A fourth alongside them, added with the Move box's tap-away commit — see
            // `handleMoveBoxCommit`. Above the active-layer guard with the other three, and for the
            // fill's reason: the states it has to switch *off* in include ones where that guard
            // returns early.
            moveBoxCommitRecognizer?.isEnabled = touch.moveBoxCommitIsEnabled

            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard let host = layerHosts[layer.id] else { return }

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
        /// two lattice embeddings, an ARAP solve and two canvas-sized renders.
        ///
        /// **It has no field list of its own, and that is the whole point of this type.** It used to
        /// enumerate the evaluation's inputs by hand — `celID`, `t`, `thicknessFade`, `hiddenGroups`,
        /// the reference versions, the local-edit ids, the guides — from a different file than the
        /// evaluation, and VECTOR_INTERPOLATION settled fact 11 records what that cost: *"It has
        /// bitten three times."* The failure is silent in the worst way — the canvas shows a stale
        /// frame forever, with every version number in sight looking right. The list was **still**
        /// three fields short when this was written: `mode`, `spacing` and the groups' fitted lattices
        /// were absent, and it survived only because today's UI happens to move a reference cel's
        /// `version` whenever it moves one of them. `.reproject`'s subject — the cel's *own* vector
        /// version, which is that mode's entire content — was a fourth.
        ///
        /// So the fix is not three more fields. `identity` is `DerivedCelContent.identity`, minted in
        /// `CanvasManager.derivedCelContent` **from the same locals as the render thunk, twenty lines
        /// apart**, which is the anti-drift property: an input added to the evaluation is added in
        /// front of the eyes of whoever is adding it to the identity. There is no longer anywhere here
        /// for a field to go missing from. What is left is the one input that is genuinely this
        /// caller's and not the derivation's:
        ///
        /// - `preview` — which *quality* to ask for. Deliberately not in the identity: a derivation
        ///   names the picture, and `render(_:)` takes the quality, so the same in-between at two
        ///   qualities is one identity and two entries here. That is the shape the memo in
        ///   `PixelOps.rasterize` relies on, and it must not be pushed down.
        ///
        /// The tinted motion-group overlay shares this dictionary and is not a derivation at all, so
        /// it mints an identity of its own (`MotionGroupOverlayIdentity`). It needs no `overlay` flag
        /// to keep the two apart: `AnyHashable` compares unequal across types, which is a stronger
        /// separation than a `Bool` nobody can forget to set.
        private struct InterpolationPreviewKey: Equatable {
            let identity: AnyHashable
            let preview: Bool
        }

        /// The overlay arm's identity — see `InterpolationPreviewKey`. `motionGroups.count` is what a
        /// retag that leaves the cel alone moves; the cel's own `version` is what an edit moves.
        private struct MotionGroupOverlayIdentity: Hashable {
            let celID: UUID
            let vectorVersion: Int
            let groupCount: Int
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
                let cel = layer.cels[celIndex]
                guard cel.interpolation != nil else {
                    // No recipe here, so this cel is a keyframe or ordinary drawing; the same seam
                    // carries the tinted motion-group overlay for it instead. Asked of the recipe
                    // rather than of the derivation below, which also answers nil for a document with
                    // no canvas size — that is a cel with nothing to *render*, not a cel with nothing
                    // to *derive*, and it must not be handed to the overlay arm.
                    updateMotionGroupOverlay(layer: layer, celIndex: celIndex, host: host)
                    continue
                }
                // **The derivation is resolved before the key, and it is what the key is made of** —
                // see `InterpolationPreviewKey`.
                guard let derived = canvasManager.derivedCelContent(for: cel,
                                                                    atFrame: canvasManager.currentFrame) else {
                    // `interpolatedImage` answered nil here too, and the seam's contract is that nil
                    // means "not yet" rather than "empty" — a recipe can be malformed while a
                    // reference is being re-picked — so the cel falls back to what it stores rather
                    // than keeping a stale in-between on screen.
                    interpolationPreviewKeys.removeValue(forKey: layer.id)
                    host.strokeView.setInterpolationImage(nil)
                    continue
                }
                let key = InterpolationPreviewKey(identity: derived.identity,
                                                  preview: canvasManager.isScrubbingInterpolation)
                guard interpolationPreviewKeys[layer.id] != key else { continue }
                interpolationPreviewKeys[layer.id] = key
                // The derivation already in hand, rather than `interpolatedImage(forCel:inLayer:)`,
                // which would resolve a second one from the ids. Same pixels — that function is a thin
                // call through `derivedCelContent` — and one resolve instead of two on the path that
                // runs every SwiftUI pass.
                host.strokeView.setInterpolationImage(derived.render(key.preview ? .preview : .full))
            }
        }

        /// The tinted motion-group overlay, memoized in the same dictionary as the in-between preview
        /// so an un-keyed render doesn't re-rasterise every keyframe on every SwiftUI pass. Its
        /// identity is a different *type* from a derivation's, which is what keeps the two from
        /// colliding on one cel — see `InterpolationPreviewKey`.
        private func updateMotionGroupOverlay(layer: Layer, celIndex: Int, host: LayerHostView) {
            let cel = layer.cels[celIndex]
            guard canvasManager.isInterpolateMode, canvasManager.showMotionGroupOverlay,
                  let version = cel.vector?.version else {
                interpolationPreviewKeys.removeValue(forKey: layer.id)
                host.strokeView.setInterpolationImage(nil)
                return
            }
            let key = InterpolationPreviewKey(
                identity: AnyHashable(MotionGroupOverlayIdentity(celID: cel.id, vectorVersion: version,
                                                                 groupCount: canvasManager.motionGroups.count)),
                preview: true)
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
            //
            // **And it is asserted *after* the selection and floating overlays, which is why this
            // call moved down `updateUIView`.** Those two are pinned to the whole container with no
            // `hitTest` override, so with the Select panel open or a piece floating they were
            // swallowing every touch that would have reached a guide grip — the grips were on screen
            // and ungrabbable, and no gate said so. This overlay claims only its grips
            // (`GuideOverlayView.hitTest`), so sitting above them costs them nothing.
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

        // MARK: - Onion skin

        /// One of the two onion-skin views. Both are plain image views over the whole container; the
        /// only difference is where they were added, which is what "Behind"/"In Front" means.
        static func makeOnionSkinView() -> UIImageView {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            // A ghost is artwork — neighbouring frames' drawings — so it loses thin ink to
            // un-mipmapped minification exactly the way the live layers do (`LayerHostView.init`
            // carries the measurement), and a reference the artist cannot see is not a reference.
            // This is the one place `.trilinear` also agrees with the *magnification* choice: the
            // ghost is deliberately left on the default bilinear there (see `makeUIView`), because
            // a soft ghost is what is wanted at both ends of the zoom.
            view.layer.minificationFilter = .trilinear
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }

        /// What produced the image currently on screen. A hit means nothing the picture depends on
        /// has moved, and the composite — up to ten canvas-sized draws — is skipped entirely.
        ///
        /// **Keyed on the identity of the source images, not on their content.** `PixelOps.rasterize`
        /// is memoized per cel version, so it hands back *the same object* for the same drawing and a
        /// new one for an edited drawing; `===` is therefore an exact answer to "is this the same
        /// drawing", at no cost.
        ///
        /// **An `ObjectIdentifier` is an address, and it does not retain.** That makes identity a
        /// sound key only while the object it names cannot be deallocated and a different one land at
        /// the same address — the ABA hazard `LayerContentVersion` and `liveMaskCache` both document,
        /// and a live one here rather than a theoretical one: `PixelOps.rasterizeCache` evicts on a
        /// byte budget, so a scrub across a long animation genuinely frees these images. Closed the
        /// same way `liveMaskCache` closes it — `onionSkinKeyImages`/`onionSkinKeyMask` hold a
        /// reference to everything the key names, for exactly as long as the key is live.
        ///
        /// Interpolate mode's source mints a fresh image every call, so it never hits — unchanged
        /// from before this cache existed, and its frames are two rather than ten.
        private struct OnionSkinKey: Equatable {
            let images: [ObjectIdentifier]
            let opacities: [CGFloat]
            let tints: [UIColor?]
            let width: Int
            let height: Int
            let placement: OnionSkinSettings.Placement
            let mask: ObjectIdentifier?

            init(frames: [OnionSkinFrame], size: CGSize,
                 placement: OnionSkinSettings.Placement, mask: CGImage?) {
                images = frames.map { ObjectIdentifier($0.image) }
                opacities = frames.map(\.opacity)
                tints = frames.map(\.tint)
                width = Int(size.width.rounded())
                height = Int(size.height.rounded())
                self.placement = placement
                self.mask = mask.map(ObjectIdentifier.init)
            }
        }

        private var onionSkinKey: OnionSkinKey?
        /// Held only so `OnionSkinKey`'s addresses cannot alias — never read. See the key's doc
        /// comment. Cleared whenever the key is, so nothing outlives the entry it protects.
        private var onionSkinKeyImages: [UIImage] = []
        private var onionSkinKeyMask: CGImage?
        /// The clip installed on whichever onion view is showing, so the same mask is not re-assigned
        /// to Core Animation on every SwiftUI pass. Same reasoning as `LayerHostView.contentMaskImage`.
        private var onionSkinMaskImage: CGImage?
        private let onionSkinMaskLayer: CALayer = {
            let layer = CALayer()
            // Nearest for the clip edge, matching `LayerHostView.makeContentMask`: the composite it
            // clips keeps that edge crisp, and a bilinear mask would soften only our copy of it.
            layer.magnificationFilter = .nearest
            return layer
        }()

        func updateOnionSkin() {
            guard let behind = onionSkinView, let front = onionSkinFrontView else { return }
            let placement = canvasManager.onionSkin.placement
            let shown = placement == .behind ? behind : front
            let hidden = placement == .behind ? front : behind

            // Every write below is guarded by a read, because this runs on every SwiftUI pass and
            // almost all of them change nothing — the same discipline `reconcileLayers` and
            // `LayerHostView.setContentMask` already keep, so an idle pass costs comparisons rather
            // than Core Animation traffic.
            func clear(_ view: UIImageView) {
                // The unused view holds nothing: a canvas-sized image left on a hidden `UIImageView`
                // is still resident, and on a 4K document that is the whole onion-skin budget parked
                // where nobody can see it.
                if !view.isHidden { view.isHidden = true }
                if view.image != nil { view.image = nil }
                if view.layer.mask != nil { view.layer.mask = nil }
            }
            clear(hidden)

            func blank() {
                clear(shown)
                onionSkinMaskImage = nil
                onionSkinKey = nil
                onionSkinKeyImages = []
                onionSkinKeyMask = nil
            }

            guard canvasManager.isOnionSkinEnabled else { return blank() }

            // Interpolate mode wants the two reference keyframes rather than the neighbouring cels.
            let source: OnionSkinSource = canvasManager.isInterpolateMode
                ? InterpolationReferenceOnionSkinSource()
                : onionSkinSource
            let frames = source.frames(for: canvasManager)
            guard !frames.isEmpty, let canvasSize = canvasManager.canvasSize else { return blank() }

            // **§6.4's mask, applied to the ghost as well as to the artwork.** BUGS.md's
            // "The onion skin renders unmasked" is this line: the composite clips a masked layer
            // correctly and the unmasked skin underneath it did not, so ink appeared outside the mask
            // at low alpha. `resolveLiveMask` is reused rather than a second resolution path written,
            // exactly as that entry asks — it returns the *same* `CGImage` the compositor's own mask
            // cache holds, so this costs a dictionary lookup on a document with a mask and a
            // `renderTree` walk on every document without one. That walk is the third per pass
            // (`reconcileLayers` and `updateSandwich` each build one already) and is O(layers ×
            // folders) of array work with no pixels in it. A cheaper "does this document have any
            // masks at all" pre-check was considered and rejected: masks come from `alphaMask` *and*
            // from clip-to-below, on layers *and* on folders, so a hand-rolled version of that
            // question would be four places to keep in sync with `RenderTree`, and getting it wrong
            // silently un-fixes the bug this line exists for.
            //
            // The whole skin takes the current layer's mask because every skin comes from the current
            // layer. Interpolate mode's references can span layers, so it is left unclipped — a
            // reference is not the current drawing and has no single mask to inherit.
            let mask: CGImage? = canvasManager.isInterpolateMode
                ? nil
                : resolveLiveMask(forLayerAt: canvasManager.currentLayerIndex)

            // The artist's resolution setting, applied here and carried into the cache key below —
            // so changing it rebuilds rather than reusing a composite at the old resolution.
            let size = OnionSkinBudget.compositeSize(for: canvasSize,
                                                     resolution: canvasManager.onionSkin.resolution)
            let key = OnionSkinKey(frames: frames, size: size, placement: placement, mask: mask)
            if key != onionSkinKey {
                onionSkinKey = key
                onionSkinKeyImages = frames.map(\.image)
                onionSkinKeyMask = mask
                shown.image = OnionSkinFrame.composite(frames, size: size)
            }
            guard shown.image != nil else { return blank() }

            // **Always 1, and this used to be a bug.** `composite` already draws every frame at its
            // own opacity, and the line here previously multiplied a single frame's opacity in a
            // second time — so the shipped one-skin default rendered at 0.3 × 0.3 = 0.09 while the
            // comment above it said the opposite was happening.
            if shown.alpha != 1 { shown.alpha = 1 }
            applyOnionSkinMask(mask, to: shown, canvasSize: canvasSize)
            if shown.isHidden { shown.isHidden = false }

            // "In Front" has to out-rank `sandwichAbove`, which `reconcileLayers` fronts whenever the
            // stack changes. Done here every pass — `bringSubviewToFront` on a view already at the
            // front is a no-op inside UIKit — rather than by teaching `reconcileLayers` about a
            // setting it has no other reason to read.
            if placement == .inFront { shown.superview?.bringSubviewToFront(shown) }
        }

        /// Installs (or removes) the clip on whichever onion view is showing.
        ///
        /// **The frame is `canvasSize`, not `view.bounds`, and that is not a shortcut.** A mask
        /// layer's frame is in its owner's coordinate space, the onion views are pinned to a
        /// container whose bounds `hostBoundsDidChange` sets to exactly `canvasSize`, and this runs
        /// from `updateUIView` — which on the very first pass is *before* autolayout has sized
        /// anything. Reading `view.bounds` there gives `.zero`, and a zero-frame mask hides the layer
        /// completely rather than visibly wrongly. The canvas size is known here and is fixed for a
        /// document's life, so it is both the correct answer and the one available early.
        ///
        /// Implicit animation is off for `LayerHostView.setContentMask`'s reason: Core Animation's
        /// default would fade a clip in over a quarter second, on a change the artist did not make.
        private func applyOnionSkinMask(_ image: CGImage?, to view: UIImageView, canvasSize: CGSize) {
            // Three things have to agree, and the third is what a plain "has the image changed"
            // check misses: one `CALayer` can be the mask of only one layer at a time, so switching
            // placement has to re-install a mask image that has not itself changed.
            let installedHere = view.layer.mask === onionSkinMaskLayer
            let wanted = image != nil
            let frame = CGRect(origin: .zero, size: canvasSize)
            if onionSkinMaskImage === image, installedHere == wanted {
                if wanted, onionSkinMaskLayer.frame != frame { onionSkinMaskLayer.frame = frame }
                return
            }
            onionSkinMaskImage = image
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let image {
                onionSkinMaskLayer.contents = image
                onionSkinMaskLayer.frame = frame
                view.layer.mask = onionSkinMaskLayer
            } else {
                if installedHere { view.layer.mask = nil }
                onionSkinMaskLayer.contents = nil
            }
            CATransaction.commit()
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
            armShapeHoldTimer()
        }

        /// Starts the poll that asks `shapeHoldClock` whether the pen has been still long enough.
        ///
        /// The timer only *asks*; its own firing time is not an input to the answer, which is a
        /// subtraction between two `UITouch.timestamp`s. That is what makes a main-thread stall
        /// unable to manufacture a hold — see `ShapeHoldClock` for the full argument, and for why a
        /// wall-clock deadline (and then a tuned "was the app awake" threshold) were both wrong.
        ///
        /// A fixed-rate repeat rather than the old re-arm-per-sample: an Apple Pencil delivers ~120
        /// samples a second, so re-scheduling a one-shot `Timer` on every one of them allocated on
        /// the order of a hundred timers a second on the drawing hot path. Nothing needed the timer
        /// rebuilt; only the deadline moved, and the deadline no longer lives on the timer at all.
        private func armShapeHoldTimer() {
            shapeHoldTimer?.invalidate()
            shapeHoldClock = ShapeHoldClock()
            shapeHoldTimer = Timer.scheduledTimer(withTimeInterval: ShapeHoldClock.tickInterval,
                                                  repeats: true) { [weak self] timer in
                // `MainActor.assumeIsolated` rather than a `Task { @MainActor in }` hop: the timer
                // callback already runs on the main thread, so the hop was pure scheduling latency
                // between the tick and the answer.
                MainActor.assumeIsolated {
                    // A repeating timer is retained by the run loop, so unlike the one-shot it used
                    // to be it does not expire on its own — and a Coordinator torn down mid-stroke
                    // would leave it ticking for the life of the process. Every ordinary exit
                    // (`cancelShapeDetection`, `fireShapeDetection`) invalidates it; this covers the
                    // one that has no `self` left to do so.
                    guard let self else { timer.invalidate(); return }
                    guard self.shapeDetectionActive else { return }
                    if self.shapeHoldClock.isHoldComplete { self.fireShapeDetection() }
                }
            }
        }

        /// Last position that counted as movement — filters out Apple Pencil's sub-pixel micro-moves,
        /// which would otherwise mean the pen is never still and the hold could never complete.
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

        private func handleStrokeMoved(_ sample: VectorSample, penTime: TimeInterval, host: LayerHostView?) {
            guard shapeDetectionActive else { return }
            guard let host, host === shapeDetectionHost else { return }
            shapeDetectionSamples.append(sample)
            let point = sample.point
            // Only past 2pt does a sample count as movement — otherwise Pencil micro-moves would
            // mean the pen is never "still" and the hold could never complete.
            let moved: Bool
            if let last = shapeLastPoint {
                moved = hypot(point.x - last.x, point.y - last.y) > 2
            } else {
                moved = true
            }
            // **Every** sample is reported, moving or not: a sub-threshold sample is exactly what a
            // parked pen delivers, and it is what advances the "how long has it been still" end of
            // the subtraction. The old code returned here for those, which was fine when a wall-clock
            // Timer was counting and is the whole signal now that the pen's clock is.
            shapeHoldClock.sample(at: penTime, moved: moved)
            // Deliberately only on a real move, as before: a sub-threshold sample must accumulate
            // toward the 2pt threshold rather than resetting the reference under it, or a slow drag
            // made entirely of micro-moves would read as stillness.
            if moved { shapeLastPoint = point }
        }

        private func cancelShapeDetection() {
            shapeHoldTimer?.invalidate()
            shapeHoldTimer = nil
            shapeDetectionActive = false
            shapeDetectionSamples.removeAll()
            shapeDetectionHost = nil
        }

        private func fireShapeDetection() {
            // Mandatory now the tick repeats. A one-shot Timer that has fired is already off the run
            // loop, so dropping the reference used to be enough; a repeating one is retained by the
            // run loop and would keep calling into a Coordinator whose detection is over, forever.
            shapeHoldTimer?.invalidate()
            shapeHoldTimer = nil
            guard shapeDetectionActive else { return }
            shapeDetectionActive = false
            // Read before anything resets it: this is the quantity the whole fix turns on, and a
            // recording that shows it near 0 while wall clock jumped is the stall, stated.
            let stillOnFire = shapeHoldClock.stillDuration
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
            let shape = ShapeDetector.detect(from: points)
            // The one line a recording of this bug had no way to contain: the stall and the vanished
            // ink were both visible, but nothing said what joined them. Recording the `nil` outcome
            // is half the point — a hold that detected nothing silently kills shape detection for the
            // rest of the stroke (`shapeDetectionActive` is already false with no re-arm), which is
            // its own confusing behaviour and is otherwise invisible.
            ActionRecorder.ifRecording {
                $0.note("shapeHold fired after \(ShapeDetector.pathLength(points).rounded())pt, "
                        + "\(samples.count) samples, "
                        + String(format: "%.2fs still on the pen's clock", stillOnFire)
                        + " -> \(shape.map { String(describing: $0.kind) } ?? "none")")
            }
            guard let shape else { return }

            // Revert the partial stroke painted during the hold period.
            host.strokeView.discardStrokeInProgress()

            canvasManager.beginInteractiveShape(shape, samples: samples)
            updateShapeOverlay()
            // Whatever is on the glass *now* is the hand that drew the shape, not a request to snap
            // it. This is the moment `shouldIgnoreAdditionalTouches` starts answering true, so it is
            // also the only moment at which "already resting" and "joined afterwards" are
            // distinguishable — see `currentAccompanyingFingers()`. Seeded before the refresh below,
            // which would otherwise engage the snap on a palm the instant the shape appeared.
            shapeFingerBaseline = touchCountRecognizer?.fingerCount ?? 0
            refreshShapeConstraint()
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

        /// What one canvas point measures on screen. The shape overlay divides its chrome by this so
        /// handles stay a fixed size in screen points however far the artist has zoomed.
        private var canvasContentScale: CGFloat { fitScale * committedScale * liveScale }

        private func applyTransform() {
            // Before the guards below, and before the no-op early return: the label has to track the
            // transform even on the passes that change nothing in Core Animation, or a test reads a
            // stale value. See `publishCanvasState`.
            publishCanvasState()
            // Above the early return for exactly the reason stated for `publishCanvasState`: the
            // identity guard skips passes that change nothing in Core Animation, and anything
            // downstream that has to track the transform reads a stale value if it sits below.
            shapeOverlay?.canvasScale = canvasContentScale
            // The text box's outline and its move band are screen-point chrome for the same reason
            // the shape handles are, so the scale has to reach it on the same passes.
            textOverlay?.canvasScale = canvasContentScale
            // And its grips, which are the reason ADD_TEXT.md §1 forbids copying
            // `TransformHandleView`'s fixed 24×24: this is the push that keeps a handle 14 pt at
            // 0.3× zoom instead of 14 canvas points.
            textTransformOverlay?.canvasScale = canvasContentScale
            // And the Move tool's box, which carried the same defect until 2026-08-21 and is the
            // overlay ADD_TEXT.md §1 was pointing *at* when it said not to copy the fixed 24×24.
            transformOverlay?.canvasScale = canvasContentScale
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

            // After the identity guard above, so the recording gets one line per *actual* change
            // rather than one per SwiftUI pass — the guard already thins this to the transitions a
            // reader cares about. Both halves go in: the committed baseline and the live gesture
            // contribution are folded together only when every one of pan/pinch/rotation has ended
            // (`commitLiveTransformIfAllEnded`), so a recording that shows `live` never returning to
            // identity is showing a gesture that never finished.
            ActionRecorder.ifRecording {
                $0.transform(committedScale: committedScale, committedRotation: committedRotation,
                             committedOffset: committedOffset,
                             liveScale: liveScale, liveRotation: liveRotation, liveOffset: liveOffset,
                             appliedScale: scale, appliedRotation: rotation,
                             appliedOffset: CGSize(width: offset.width, height: offset.height))
            }

            container.transform = CGAffineTransform.identity.rotated(by: rotation).scaledBy(x: scale, y: scale)
            container.center = CGPoint(x: baseCenter.x + offset.width, y: baseCenter.y + offset.height)
        }

        // MARK: - Gestures

        /// **Which of these reject a finger while pencil-only drawing is on, and which must not.**
        /// The preference is `CanvasManager.pencilOnlyDrawing`, and the question is not "is this a
        /// touch?" but "would this input have drawn?" — pencil-only means *drawing* is the pen's job,
        /// never that the canvas stops listening to hands.
        ///
        ///  * `pan` / `pinch` / `rotation` — **never gated.** They are the two-finger navigation
        ///    transform and are the reason a hand is on the glass at all in pencil-only mode. Gating
        ///    them would leave an artist holding a pen unable to pan their own canvas.
        ///  * `twoFingerTap` (undo) / `threeFingerTap` (redo) — **never gated,** and deliberately so
        ///    rather than incidentally: these are multi-finger by design, have no pen spelling, and
        ///    the pen cannot supply a second contact. Gating them removes undo from the app.
        ///  * `touchCounter` — **never gated.** It exists to notice the finger that joins a sequence
        ///    the *pen* started ("keep the pen down, then drop a finger to snap the shape"), so a
        ///    finger is not merely allowed here, it is the entire signal.
        ///  * `fillPress` — **gated,** in `handleFillPress`. A fill is a drawing edit: it replaces
        ///    pixels, pushes an undo entry, and `minimumPressDuration = 0` makes a stray palm tap a
        ///    completed flood. This was the second hole in pencil-only mode, reported by the owner.
        ///  * `catchAll` — **half gated,** in `handleCatchAllTap`: the notice it raises is gated, the
        ///    menu dismissal is not. See that handler for why those two split.
        ///  * `eyedropperPress` — **gated,** in `handleEyedropperPress`, and it is the one entry here
        ///    whose gating is not about protecting pixels. A pick edits nothing and pushes no undo
        ///    entry, so "would this input have drawn?" answers no. It is gated anyway because of what
        ///    a pick *leads to*: it replaces the brush colour and reverts the tool, so a resting palm
        ///    would leave the artist holding a different colour and a different tool than the one
        ///    they put down — a state they then paint with. Pencil-only mode is a promise that a hand
        ///    on the glass changes nothing about drawing, and the colour about to be drawn with is
        ///    part of that.
        ///
        /// The per-layer stroke recognizer is not created here — `StrokeCanvasView` owns it and
        /// `reconcileLayers` mirrors the preference down to it. That was the *only* consumer of
        /// `pencilOnlyDrawing` before this pass, which is how the two holes above went unnoticed:
        /// every recognizer on this view was a stock UIKit type whose `@objc` action never sees a
        /// `UITouch`, so none of them *could* have asked. See `TouchTypePressRecognizer`.
        ///
        /// **`UIGestureRecognizer.name` is set on every recognizer here purely so `ActionRecorder`
        /// can name it in a recording** — the debug recorder discovers recognizers by walking the
        /// view hierarchy for named ones rather than having each register itself, which is what keeps
        /// it free when off (see `WindowEventTap.rescanRecognizers`). `name` is a debugging-only
        /// property; nothing in the app reads it, and setting it changes no behaviour.
        func setUpGestures(on view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            pan.cancelsTouchesInView = false
            pan.name = "canvas.pan"
            view.addGestureRecognizer(pan)
            panRecognizer = pan

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            pinch.cancelsTouchesInView = false
            pinch.name = "canvas.pinch"
            view.addGestureRecognizer(pinch)
            pinchRecognizer = pinch

            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotation.delegate = self
            rotation.cancelsTouchesInView = false
            rotation.name = "canvas.rotation"
            view.addGestureRecognizer(rotation)
            rotationRecognizer = rotation

            let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
            twoFingerTap.numberOfTouchesRequired = 2
            twoFingerTap.cancelsTouchesInView = false
            twoFingerTap.name = "canvas.twoFingerTap"
            view.addGestureRecognizer(twoFingerTap)

            // Drives the shape constraint snap: reports the live canvas touches split by type, and a
            // finger joining a pen-held shape engages the snap after a short delay (see
            // `canvasTouchesChanged`). Unlike a two-finger long press, it still fires when a touch
            // joins a sequence the pen started seconds ago — "keep the pen down, then drop a finger
            // to snap it."
            let touchCounter = TouchCountRecognizer(target: self, action: nil)
            touchCounter.delegate = self
            touchCounter.name = "canvas.touchCounter"
            // The counts themselves are read back off the recognizer inside
            // `refreshShapeConstraint`, alongside the stroke recognizer's own — this is the "and now
            // something changed" edge, not the value.
            touchCounter.onTouchesChanged = { [weak self] _, _ in
                self?.refreshShapeConstraint()
            }
            view.addGestureRecognizer(touchCounter)
            touchCountRecognizer = touchCounter

            let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
            threeFingerTap.numberOfTouchesRequired = 3
            threeFingerTap.cancelsTouchesInView = false
            threeFingerTap.name = "canvas.threeFingerTap"
            view.addGestureRecognizer(threeFingerTap)

            twoFingerTap.require(toFail: threeFingerTap)

            // One-finger press-drag driving the fill tool: press applies the fill, dragging adjusts
            // settings live. `minimumPressDuration = 0` makes a plain tap a one-shot fill. Disabled
            // except while the fill tool is selected, so it never competes with stroke capture.
            //
            // A `TouchTypePressRecognizer` for the same reason the catch-all below is one, and the
            // zero press duration is what makes it urgent here: a fill is applied on touch-down, so
            // there is no dwell in which a mistaken contact could be lifted before it did anything.
            let fillPress = TouchTypePressRecognizer(target: self, action: #selector(handleFillPress(_:)))
            fillPress.minimumPressDuration = 0
            fillPress.numberOfTouchesRequired = 1
            fillPress.delegate = self
            fillPress.cancelsTouchesInView = false
            fillPress.isEnabled = false
            fillPress.name = "canvas.fillPress"
            view.addGestureRecognizer(fillPress)
            fillTapRecognizer = fillPress

            // Catch-all for when no layers or the active layer is hidden: fires on any single touch
            // to surface a notice instead of silently swallowing it. Disabled by default — enabled in
            // reconcileLayers only when the canvas can't accept drawing input.
            //
            // A `TouchTypePressRecognizer` rather than a stock `UILongPressGestureRecognizer`: the
            // handler has to know whether the touch was a finger or the pencil, and a plain
            // recognizer's `@objc` action receives only the recognizer — `UIGestureRecognizer`
            // publishes `numberOfTouches` and `location(ofTouch:in:)` and nothing that reaches a
            // `UITouch`. See the subclass for why the delegate route was rejected.
            let catchAll = TouchTypePressRecognizer(target: self, action: #selector(handleCatchAllTap(_:)))
            catchAll.minimumPressDuration = 0
            catchAll.numberOfTouchesRequired = 1
            catchAll.delegate = self
            catchAll.cancelsTouchesInView = false
            catchAll.isEnabled = false
            catchAll.name = "canvas.catchAll"
            view.addGestureRecognizer(catchAll)
            catchAllTapRecognizer = catchAll

            // The eyedropper's tap. Disabled except while the eyedropper is selected, exactly as the
            // fill's press is — `reconcileLayers` flips both from `selectedTool`.
            //
            // **A third `TouchTypePressRecognizer`, not a third mechanism.** This is a canvas-touch
            // tool and so needs the same touch-type gate the fill and the lasso have, and the app now
            // has exactly two spellings of that gate: this subclass, and
            // `SelectionOverlayView`'s `TouchTypePan`/`TouchTypeTapGestureRecognizer` pair (both over
            // `resolvedLastTouchType`). A fourth would be a fourth place for the pencil test to drift.
            // This one is the right of the two here: the recognizer lives on the canvas host rather
            // than the selection overlay, and the shape wanted is the fill's — one touch, zero press
            // duration, a location read off the container.
            let eyedropperPress = TouchTypePressRecognizer(target: self, action: #selector(handleEyedropperPress(_:)))
            eyedropperPress.minimumPressDuration = 0
            eyedropperPress.numberOfTouchesRequired = 1
            eyedropperPress.delegate = self
            eyedropperPress.cancelsTouchesInView = false
            eyedropperPress.isEnabled = false
            eyedropperPress.name = "canvas.eyedropperPress"
            view.addGestureRecognizer(eyedropperPress)
            eyedropperTapRecognizer = eyedropperPress

            // The text tool's placement tap. A fourth `TouchTypePressRecognizer` for the reason the
            // eyedropper's comment above gives for the third: this is a canvas-touch tool and so
            // needs the same touch-type gate, and the app has exactly two spellings of that gate. A
            // fifth would be a fifth place for the pencil test to drift.
            //
            // `minimumPressDuration = 0` like the other two, but for the opposite reason to the
            // fill's: placing a box applies nothing and pushes no undo step, so there is nothing a
            // mistaken contact could do that tapping elsewhere does not undo by itself.
            let textPress = TouchTypePressRecognizer(target: self, action: #selector(handleTextPress(_:)))
            textPress.minimumPressDuration = 0
            textPress.numberOfTouchesRequired = 1
            textPress.delegate = self
            textPress.cancelsTouchesInView = false
            textPress.isEnabled = false
            textPress.name = "canvas.textPress"
            view.addGestureRecognizer(textPress)
            textTapRecognizer = textPress

            // The tap **away** from the vector Move box, which puts the box down — the vector half of
            // what `FloatingPieceOverlayView`'s own tap-outside already does for a raster piece.
            //
            // **On the container rather than on `ObjectTransformOverlayView`, because that overlay
            // claims only its own grips**, deliberately: everywhere else it is transparent to touch
            // so the canvas keeps panning and pinching while the box is up. A tap recognizer added to
            // it would therefore never fire off the box, which is precisely the tap this is for.
            //
            // A plain `UITapGestureRecognizer` and **not** a `TouchTypePressRecognizer`, unlike the
            // four above: settling a float writes nothing and records nothing (every nudge is already
            // its own undo step — LASSO_MOVE.md §5), so "would this input have drawn?" answers no and
            // pencil-only mode has no stake in it. The raster tap-outside is a plain tap for the same
            // reason, and matching it is the point.
            let moveBoxCommit = UITapGestureRecognizer(target: self, action: #selector(handleMoveBoxCommit(_:)))
            moveBoxCommit.numberOfTouchesRequired = 1
            moveBoxCommit.delegate = self
            moveBoxCommit.cancelsTouchesInView = false
            // **`delaysTouchesEnded = false` is the one place this diverges from the raster tap**, and
            // the reason is where it is mounted. `UIGestureRecognizer` withholds a view's
            // `touchesEnded` until the recognizer settles; the raster tap lives on the floating
            // overlay, so that is one view, but this one lives on the container and is therefore an
            // ancestor of every overlay and every layer host. `ObjectTransformOverlayView` ends its
            // drag out of raw `touchesEnded` — and that is where the float's one undo step per nudge
            // is written — so a delay there would be a delay on the artist's own Move gesture.
            moveBoxCommit.delaysTouchesEnded = false
            moveBoxCommit.isEnabled = false
            moveBoxCommit.name = "canvas.moveBoxCommit"
            view.addGestureRecognizer(moveBoxCommit)
            moveBoxCommitRecognizer = moveBoxCommit
        }

        /// Settles the vector Move box when the artist taps away from it — owner's ruling, 2026-08-22.
        ///
        /// **What it is fixing:** `FloatingPieceOverlayView` covers the whole container and commits a
        /// raster piece the moment you tap outside it, while a vector float's
        /// `ObjectTransformOverlayView` claims only its own grips, so there was no tap-away commit at
        /// all. `CanvasTouchOwnerLogicTests` counted 122 reachable combinations in which the touch was
        /// owned by nobody because of it: mid-Move on a vector layer, or with a lassoed piece
        /// floating, a touch away from the box did nothing *and said nothing* — where a hidden layer
        /// would at least have raised a banner. The owner chose this over leaving it silent and over
        /// raising a notice.
        ///
        /// **One arm, where there were two.** A float settles through `commitVectorFloatIfNeeded()` —
        /// the branch `TopToolbar.toggleMove` already takes when Move is engaged, so tapping away and
        /// tapping the Move button are the same call. It records no step of its own: a float's nudges
        /// are already on the stack one apiece (LASSO_MOVE.md §5). The second arm settled a whole-layer
        /// transform with `isVectorTransforming = false`; TODO item (12) stage 2 deleted it, because
        /// Move with no selection lifts a float now and takes the first branch.
        @objc func handleMoveBoxCommit(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let container = containerView else { return }
            // Before the ownership guard, as every canvas touch is: a tap that this handler declines
            // still closes an open top-bar dropdown.
            canvasManager.canvasInteractionBegan()
            let canvasPoint = recognizer.location(in: container)
            let touch = canvasTouchInputs(chrome: canvasChrome(at: canvasPoint))
            guard CanvasTouchOwner.owner(in: touch) == .moveBoxCommit else { return }
            canvasManager.commitVectorFloatIfNeeded()
        }

        /// The text tool's placement tap: put a box where the artist tapped and raise the keyboard.
        ///
        /// **A tap that lands on the live box does nothing here**, and the guard is the whole
        /// subtlety: `TextOverlayView` has already taken that touch (its `hitTest` claims the box and
        /// the band), but this recognizer sits on the *container* with `cancelsTouchesInView = false`
        /// and therefore sees it too. Without the guard, tapping into your own text to move the caret
        /// would commit that text and open a fresh empty box on top of it.
        ///
        /// **Gated on pencil-only drawing** like the fill and the eyedropper, and for the same
        /// reason stated there: placing text changes what the artist's next action does, and a
        /// resting palm must not do that.
        @objc func handleTextPress(_ recognizer: TouchTypePressRecognizer) {
            guard recognizer.state == .began, let container = containerView else { return }
            // **Above the pencil-only guard, as every canvas touch is**, and through
            // `canvasInteractionBegan()` rather than the raw subject: a finger this handler is about
            // to refuse still has to close whatever popover or dropdown is sitting over the canvas.
            // This was the app's one bare `interactionBegan.send()` until 2026-08-26 — see that
            // function's own comment for how a clean merge produced it.
            canvasManager.canvasInteractionBegan()
            guard !canvasManager.pencilOnlyDrawing || recognizer.lastTouchType == .pencil else { return }
            // container's bounds equal canvasSize, so `location(in:)` there is canvas-pixel space —
            // the same mapping `handleFillPress` uses.
            let canvasPoint = recognizer.location(in: container)
            // **The one handler in the app that defended itself, now asking the one function.** Both
            // text overlays are consulted, not just the editor: a grip sits *outside* the box, so
            // without the second test grabbing a corner handle would fall through to here and commit
            // the very session the artist was resizing — then open an empty box under their finger.
            // `canvasChrome(at:)` asks both (and the other three), and `contenders` is what encodes
            // the exemption, so the guard and the model cannot drift apart.
            //
            // **`owner` rather than `contenders` since 2026-08-22**, which is the whole of rule (i)
            // at this site: a guide grip or a shape handle under the finger used *not* to suppress
            // this tap — every container recognizer here sets `cancelsTouchesInView = false`, so
            // both acted — and the owner ruled that whatever chrome the artist grabbed wins. The
            // four sibling handlers now open with the same line. The `chrome` exemption for the two
            // text overlays stays inside `contenders`, because there this tap is not merely
            // outranked, it is wrong.
            //
            // **One clause did not survive the conversion, deliberately: `canvasManager.
            // textGestureActive`.** The guard used to read `if textGestureActive, hitTest != nil`,
            // and `claimsTouch` already carries the overlay's own `isActive` — which
            // `updateTextOverlay` mirrors from `textGestureActive` — so the model asks the *pushed*
            // copy where the old line also asked the live one. They differ for exactly one frame:
            // between a text session ending and the next `updateTextOverlay` pass hiding the editor,
            // a tap where the box still is used to place a **new** box on top of the one just
            // committed, and now places nothing. That is the better answer of the two (a tap that
            // lands on chrome the artist can still see should not act as if the chrome were gone),
            // it is one frame wide, and a second tap places the box — but it is a behaviour change
            // rather than a restatement, which is why it is written down here instead of being left
            // to be discovered.
            let touch = canvasTouchInputs(chrome: canvasChrome(at: canvasPoint))
            guard CanvasTouchOwner.owner(in: touch) == .textPress else { return }
            canvasManager.beginTextSession(at: canvasPoint)
            guard canvasManager.textGestureActive else { return }
            updateTextOverlay()
            // After `updateTextOverlay`, which is what un-hides the editor: `becomeFirstResponder`
            // on a hidden view is refused, and the refusal is silent — the box would appear with no
            // keyboard and no caret, and the artist would have to tap it a second time.
            textOverlay?.focusEditor()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let alwaysConcurrent: [UIGestureRecognizer?] = [fillTapRecognizer, catchAllTapRecognizer, touchCountRecognizer, eyedropperTapRecognizer, textTapRecognizer, moveBoxCommitRecognizer]
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
        ///
        /// The liveness guard below is the same argument one step further in. The comment above
        /// closed the *static* version of the deadlock — a named recognizer belonging to a layer that
        /// is not the active one. It did not close the case where the recognizer named is the active
        /// layer's and that layer is nonetheless not accepting touches: `reconcileLayers` turns
        /// `isUserInteractionEnabled` off on the active host for the fill tool, the Select panel, a
        /// floating Move piece, a vector layer mid-transform, and a layer with no drawing surface (see
        /// `shouldInteract`). In every one of those the recognizer sits in `.possible` receiving
        /// nothing, and stating a dependency on it is stating a dependency on something that has no
        /// reason to resolve. Returning false means "no dependency", which is the safe direction to
        /// err: the worst case is a stroke racing a transform on a host that is declining strokes
        /// anyway, and the best case is that two-finger pan keeps working in five states where it had
        /// no business being at risk.
        ///
        /// Kept deliberately narrow: it does not try to inspect `otherGestureRecognizer.state`. A
        /// recognizer legitimately sitting in `.began` mid-stroke is *exactly* what the dependency
        /// exists to wait for, so "is it in a terminal state?" is not a question that can be asked
        /// here without breaking the feature. Making the terminal transition reachable at all is
        /// `StrokeGestureRecognizer.failTrackedStroke`'s job. (The reported canvas freeze was *not*
        /// that path — it was popover teardown stranding the recognizer, fixed in `AnimationTimeline`
        /// and pinned by `CanvasTransformFreezeUITests`; see `failTrackedStroke`'s own doc.)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let answer = shouldRequireFailure(gestureRecognizer, of: otherGestureRecognizer)
            // Recorded on **every** call, not only when the answer changes: a `true` here is the edge
            // that can wedge pan/pinch/rotate behind a stroke recognizer, so the value of the line is
            // in pairing it with the `recognizer` lines around it — a `true` naming a recognizer that
            // the file then shows never reaching a terminal state *is* the bug, stated.
            ActionRecorder.ifRecording {
                $0.failureRequirement(asker: $0.nameFor(gestureRecognizer),
                                      other: $0.nameFor(otherGestureRecognizer),
                                      answer: answer)
            }
            return answer
        }

        private func shouldRequireFailure(_ gestureRecognizer: UIGestureRecognizer, of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let transformRecognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0 }
            guard transformRecognizers.contains(where: { $0 === gestureRecognizer }) else { return false }
            // **Asked, not read back.** This used to read three flags off the view hierarchy —
            // `activeHost.isUserInteractionEnabled`, `strokeView.isUserInteractionEnabled` and
            // `strokeView.strokeRecognizer.isEnabled` — which is a fourth question answered out of
            // three other gates' answers, and the reason this line appears in the architecture
            // review's finding at all. The first two are both `shouldInteract`, and the third is
            // never assigned anywhere in the app, so the whole predicate always was
            // `CanvasTouchInputs.activeHostIsInteractive`; it now says so, one pass earlier than
            // `reconcileLayers` can have pushed it down.
            //
            // What it asks and what it *should* ask still differ, and
            // `CanvasTouchInputs.transformDependencyIsUnresolvable` is where that is written down:
            // the question here is "is the active host accepting touches", where the one that decides
            // whether the stroke recognizer can ever reach a terminal state is "did *this* touch
            // reach it". Converting to `activeHostReceivesTouches` would close that — and would
            // change behaviour on a hidden active layer — so it is reported rather than shipped.
            guard canvasTouchInputs().transformWaitsOnActiveStroke else { return false }
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return false }
            let activeLayer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard let activeHost = layerHosts[activeLayer.id] else { return false }
            return otherGestureRecognizer === activeHost.strokeView.strokeRecognizer
        }

        // MARK: - Shared anchor-preserving pan/zoom/rotate

        /// Captures the touch centroid and container center at the start of whichever of
        /// pan/pinch/rotation begins first, so all three can share one anchor for this touch sequence.
        ///
        /// Seeded unconditionally, a pending shape included. This used to early-return while
        /// `shapeGestureActive`, on the rule "two fingers on a pending shape mean snap it, not pan
        /// the canvas", and the only thing that then seeded the anchor was
        /// `commitSnappedShapeIfTransforming` — the same call that baked the shape the owner wanted
        /// left alone. Delete that bake without this and `updateLiveOffset` bails on a nil
        /// `gestureAnchorHost0`, so the canvas silently refuses to move at all whenever a shape is
        /// pending: a dead-canvas symptom that looks nothing like the change that caused it. The old
        /// rule now lives on the snap itself, gated to `isShapeFollowingFinger` in
        /// `canvasTouchesChanged`, which is the more precise place for it.
        private func beginAnchorIfNeeded(at location: CGPoint) {
            canvasManager.cancelInteractiveFillDrag()
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
            // `canvasTouchesChanged`), letting the pen lift out of a snapped shape while the
            // snapping finger is still down.
        }

        /// The shared body of the three canvas-transform gestures: identical state machine, only the
        /// live value each contributes differs (`applyLiveValue`; pan contributes none of its own).
        ///
        /// **Moving the viewport is not editing the canvas.** A pan/pinch/rotate changes what the
        /// artist is looking at, not what is on the layer, so a pending smart shape must survive it —
        /// the owner's report is exactly that two-finger moving the canvas baked the shape. Only an
        /// edit that actually mutates content (a new stroke, a tool/layer/frame change, an undo) goes
        /// through `beginCanvasEdit` and bakes it. `.changed` used to call a
        /// `commitSnappedShapeIfTransforming` here that did the opposite.
        ///
        /// One ordering is load-bearing: `applyLiveValue` runs before `updateLiveOffset`, which reads
        /// `liveScale` to place the anchor — a stale scale would slip the content out from under the
        /// fingers by one event. The `numberOfTouches` guard also stays: a lifting finger can still
        /// produce one more `.changed` as the recognizer collapses from 2 touches to fewer, and that
        /// frame is not an intentional transform.
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

        /// The one expression both the engage and the release predicates read, so they cannot drift
        /// apart — `releaseShapeConstraintAfterCurrentEvent` needs the exact negation of the engage
        /// test and used to restate it by hand.
        ///
        /// **Why the container's count is baselined and the stroke recognizer's is not.** Now that
        /// `TouchCountRecognizer.requiresExclusiveTouchType` is off, the counter finally sees fingers
        /// during a pencil stroke — *all* of them, including a hand that was already resting when the
        /// shape formed. That hand is not the gesture; the gesture is "add a finger". Subtracting the
        /// count captured at `beginInteractiveShape` turns an absolute count into "how many joined
        /// since", which is what the owner actually describes. `StrokeGestureRecognizer`'s count needs
        /// no such correction: it only admits fingers that arrive *while* a shape is following (see
        /// `shouldIgnoreAdditionalTouches`), so a resting palm is already excluded there by
        /// construction, and it is that source — not this one — that carries the owner's gesture.
        ///
        /// The baseline ratchets **down** and never up. Without that, a palm that lifts mid-gesture
        /// would leave a permanent 1 subtracted and the real finger would never reach the threshold —
        /// a snap that silently stops working for the rest of the shape.
        private func currentAccompanyingFingers() -> Int {
            let counterFingers = touchCountRecognizer?.fingerCount ?? 0
            if counterFingers < shapeFingerBaseline { shapeFingerBaseline = counterFingers }
            let joined = max(0, counterFingers - shapeFingerBaseline)
            return max(joined, strokeAccompanyingFingers)
        }

        /// A finger joining a shape the **pen is still drawing** means the snap constraint: rectangle
        /// to square, oval to circle, line to nearest 15°.
        ///
        /// The owner states the gesture as "keep the pen held down and put a finger on the canvas",
        /// and the old predicate — an undifferentiated `count >= 2` — could not express that. It was
        /// wrong in both directions at once: too strict, because pen-plus-one-finger never reaches
        /// two if the pencil's `UITouch` is not delivered to this container-level recognizer, so the
        /// snap simply never engaged while the pen was down; and too loose, because any two contacts
        /// qualified, including the two fingers of an ordinary canvas pan. The second half is why the
        /// owner saw it snap only *after* lifting the pen and pinching — that pinch was the first
        /// moment the count unambiguously reached two, and the snap engaging there is also what fed
        /// the shape into the transform-path bake.
        ///
        /// Restricting this to `isShapeFollowingFinger` (pen still down) is therefore not a
        /// narrowing for its own sake — it is the companion change to removing the bake from the
        /// transform path, and without it a two-finger pan over a pending shape would snap it.
        ///
        /// **Splitting the count by type did not fix it on the owner's iPad, and the reason the first
        /// diagnosis missed is worth keeping.** It assumed the pencil's `UITouch` never reaches a
        /// container-level recognizer; the owner's own recording falsifies that — with the pen the
        /// only contact on the glass, `canvas.pan`, `canvas.pinch` and `canvas.rotation` are all
        /// consulted about failure requirements and all transition to `.failed`, which they can only
        /// do having received that touch. So the pencil is delivered, the old `total >= 2` predicate
        /// was satisfiable by pen-plus-finger, and it still never fired. What both predicates have in
        /// common is that they read **one** recognizer, four views above where the touch lands.
        ///
        /// Hence two sources, folded here. `TouchCountRecognizer` on the container is the one that
        /// can see touches no stroke is involved in; the active stroke's own recognizer is the one
        /// that cannot be starved while the pen is drawing, because it is the thing the pen is
        /// driving. The snap engages if either sees a finger. Which of them did is recorded, so one
        /// capture from the owner settles the open question instead of another round of reasoning.
        ///
        /// **That capture came back, and neither source had seen the finger — because neither had
        /// been offered it.** `UIGestureRecognizer.requiresExclusiveTouchType` defaults to `true`, so
        /// a recognizer holding the pencil is closed to `.direct` touches until it resets; both of
        /// these were holding the pencil. It is turned off in both recognizers' initialisers now, and
        /// that — not the predicate, and not `isMultipleTouchEnabled` alone — is what makes either
        /// source able to see the finger at all. Keeping two sources is still right: they fail in
        /// different ways, and the recorded line says which one fired.
        private func refreshShapeConstraint() {
            let counterTotal = touchCountRecognizer?.activeCount ?? 0
            let counterFingers = touchCountRecognizer?.fingerCount ?? 0
            let fingers = currentAccompanyingFingers()
            // Not debug cruft; it costs one static `Bool` load when off. Both sources are named
            // separately on purpose — `counter:2/1 stroke:0` and `counter:1/0 stroke:1` are the two
            // answers to "is the container recognizer being starved", and they differ in one line.
            ActionRecorder.ifRecording {
                $0.model("shape.touches",
                         "counter:\(counterTotal)/\(counterFingers) base:\(shapeFingerBaseline) "
                         + "stroke:\(strokeAccompanyingFingers) joined:\(fingers) "
                         + "following:\(canvasManager.isShapeFollowingFinger)")
            }
            guard canvasManager.isShapeFollowingFinger, fingers >= 1 else {
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
        /// ends the snapping gesture can also be the pen lifting, and `endInteractiveShape` is what
        /// makes a snap permanent. UIKit fires both recognizers in no defined order, so deferring
        /// lets the lift land first regardless of ordering; the signal is re-read so a finger that
        /// came straight back down doesn't lose its snap.
        ///
        /// The re-read predicate has to be the exact negation of `refreshShapeConstraint`'s engage
        /// predicate — **both sources included**. When the two disagree the snap either sticks after
        /// the gesture is over or drops a frame early, and with two sources the failure mode is
        /// sharper: reading only the container's counter here would release a snap the *stroke's*
        /// recognizer is still reporting a finger for, one run-loop turn after it engaged.
        private func releaseShapeConstraintAfterCurrentEvent() {
            guard isShapeConstraintEngaged else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let fingers = self.currentAccompanyingFingers()
                let stillSnapping = self.canvasManager.isShapeFollowingFinger && fingers >= 1
                guard !stillSnapping else { return }
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

        @objc func handleThreeFingerTap() {
            canvasManager.redo()
        }

        /// The touch the canvas cannot act on: no layers, the active layer hidden, or the active layer
        /// holding no pixels. Two separate jobs, and they are deliberately gated differently.
        ///
        /// **Dismissing the open menu is unconditional.** Touching the canvas at all closes whatever
        /// top-bar dropdown is open — that is what `StrokeGestureRecognizer.onAnyTouchBegan` does on
        /// every layer that *can* be drawn on, fired before its own pencil-only gate for exactly this
        /// reason. On this path it did not happen at all: the notice states are precisely the states in
        /// which `reconcileLayers` turns the active host's interaction off, so that host's recognizer
        /// never sees the touch and `onAnyTouchBegan` never runs, and nothing here sent the signal
        /// either. The result was that with the layer panel open, tapping the canvas to close it did
        /// nothing except produce a modal alert — the owner's report. The `send()` below is new
        /// behaviour, not a gate on existing behaviour.
        ///
        /// **Raising the notice is gated on the touch being one that could have drawn.** With
        /// pencil-only drawing on, a finger is not an input the canvas would have accepted anywhere,
        /// so telling the artist why their finger did not draw is answering a question they did not
        /// ask; `StrokeGestureRecognizer` fails such a touch silently on every ordinary layer and this
        /// path now matches it. The pencil is a drawing touch in both modes, so a pen tap on a value
        /// layer does both things: closes the menu *and* explains itself.
        @objc func handleCatchAllTap(_ recognizer: TouchTypePressRecognizer) {
            guard recognizer.state == .began else { return }
            // Before every other guard, including the tool check: any touch, any tool, any touch type.
            canvasManager.canvasInteractionBegan()
            // `Tool.paintsOnCanvas`, not a second spelling of the same three cases: this path exists
            // to explain why a touch that *would have drawn* did not, so it is asking `shouldInteract`'s
            // tool clause over again and must give the same answer. The fill and the eyedropper have
            // their own recognizers on this same view and are not owed an explanation — the
            // eyedropper in particular still picks with no layers at all, off the paper.
            guard canvasManager.selectedTool.paintsOnCanvas else { return }
            // **And a touch somebody else took is not owed one either** (rule (i), owner 2026-08-22).
            // `needsCatch` reads only the active layer's own state and never asks whether a floating
            // piece, the Select panel or a grabbed grip has taken the touch, so dragging a Move piece
            // over a hidden active layer raised "this layer is hidden" on every touch of the drag and
            // lassoing with no layers raised "no layers" on every drag. The notice is the last thing
            // in the precedence for exactly this reason: it explains a touch nobody acted on.
            if let container = containerView {
                let touch = canvasTouchInputs(chrome: canvasChrome(at: recognizer.location(in: container)))
                guard CanvasTouchOwner.owner(in: touch) == .catchAllNotice else { return }
            }
            // The same test `StrokeGestureRecognizer.touchesBegan` applies, read straight off the
            // source flag that `reconcileLayers` mirrors down to `StrokeCanvasView.pencilOnlyDrawing`
            // — not off a third copy of the preference, so the two paths cannot drift apart.
            guard !canvasManager.pencilOnlyDrawing || recognizer.lastTouchType == .pencil else { return }
            if canvasManager.layers.isEmpty {
                canvasManager.raise(.noLayers)
            } else if canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
                      !canvasManager.isLayerEffectivelyVisible(canvasManager.currentLayerIndex) {
                canvasManager.raise(.hiddenLayer)
            } else if canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
                      canvasManager.layers[canvasManager.currentLayerIndex].hasNoDrawingSurface {
                canvasManager.raise(.noDrawingSurface)
            }
        }

        /// The fill tool's press-drag, and pencil-only drawing's second hole (owner-reported): with
        /// the preference on, a finger tap flooded the artwork.
        ///
        /// **A fill is a drawing edit, so it answers to the drawing preference.** It replaces pixels
        /// and pushes an undo entry, which is what `StrokeGestureRecognizer.requiresPencilOnly` exists
        /// to keep a hand from doing; that the edit arrives through a press rather than a stroke is an
        /// implementation detail of the tool, not a difference the artist agreed to. And
        /// `minimumPressDuration = 0` makes it the worse of the two holes: the flood is applied on
        /// touch-down, so unlike a stroke there is no travel in which a mistaken contact does
        /// something small before it is noticed.
        ///
        /// **The gate is here and not in the recognizer**, which is the same split
        /// `handleCatchAllTap` makes and for the same reason — see `TouchTypePressRecognizer`. It sits
        /// *after* `canvasInteractionBegan()` deliberately: a rejected finger still closes whatever
        /// dropdown or popover is open, because closing a menu by tapping away from it is not drawing and
        /// every other canvas touch already does it. Beyond that the touch does nothing at all — no
        /// notice, no fill — matching what a finger does on an ordinary layer with the preference on.
        ///
        /// **Rejecting at `.began` has to bind the whole sequence, not just this callback.** UIKit
        /// goes on delivering `.changed` and `.ended` for a press this handler declined, and `.ended`
        /// used to call `endInteractiveFill()` unconditionally — which would have *committed the
        /// previous* adjustable fill, so a stray palm would have baked an edit the artist was still
        /// tuning. `fillDragStartHost` is the token that says "this sequence was accepted": it was
        /// already the guard on `.changed`, it is set only on an accepted `.began`, and the terminal
        /// cases now read it too. That is a no-op for every accepted press — a zero-duration long
        /// press always begins before it ends — and it is what makes the rejection total.
        @objc func handleFillPress(_ recognizer: TouchTypePressRecognizer) {
            guard let container = containerView, let host = hostView else { return }
            switch recognizer.state {
            case .began:
                // Continuing to fill dismisses whatever top-bar dropdown is open.
                canvasManager.canvasInteractionBegan()
                // The same test `StrokeGestureRecognizer.touchesBegan` applies, read straight off the
                // source flag rather than off a third copy of the preference, so the fill path and the
                // stroke path cannot drift apart.
                guard !canvasManager.pencilOnlyDrawing || recognizer.lastTouchType == .pencil else { return }
                // **Rule (i): whatever chrome the artist grabbed wins.** This recognizer is on the
                // container with `cancelsTouchesInView = false`, so an overlay claiming the point
                // takes nothing away from it — dragging a guide grip, a smart shape's handle or a
                // vector Move box with Fill selected used to move the chrome *and* dump a flood fill
                // underneath it. Declining here binds the whole sequence for the reason the doc
                // comment gives: `fillDragStartHost` stays nil, so `.changed` and `.ended` are no-ops
                // and no adjustable fill is committed by a press this handler refused.
                // container's bounds equal canvasSize, so location(in:) there is canvas-pixel space.
                let canvasPoint = recognizer.location(in: container)
                guard CanvasTouchOwner.owner(in: canvasTouchInputs(chrome: canvasChrome(at: canvasPoint))) == .fillPress else { return }
                // The drag delta is measured in fixed screen (host) space so feel is zoom-independent.
                fillDragStartHost = recognizer.location(in: host)
                fillDragStartGap = canvasManager.fillGapClosingDistance
                fillDragStartThreshold = canvasManager.fillThreshold
                fillDragStartEdge = canvasManager.fillEdgeOverlap
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
                // See the doc comment: `fillDragStartHost` is "this sequence was accepted", and a
                // declined press must not reach `endInteractiveFill` — which would commit whatever
                // fill was already adjustable.
                guard fillDragStartHost != nil else { return }
                canvasManager.endInteractiveFill()
                fillDragStartHost = nil
            case .cancelled, .failed:
                guard fillDragStartHost != nil else { return }
                canvasManager.cancelInteractiveFillDrag()
                fillDragStartHost = nil
            default:
                break
            }
        }

        /// The eyedropper's tap: take the colour under it as the brush colour, then go back to the
        /// tool that was selected before (`Tool.eyedropper`).
        ///
        /// **Gated on pencil-only drawing**, like `handleFillPress` and for the reason spelled out in
        /// `setUpGestures` — a pick edits nothing, but it changes the colour and the tool the artist's
        /// *next* stroke will use, and a resting palm must not do that.
        ///
        /// **The composite runs off the main thread.** `CanvasManager.pickColor` does all three steps
        /// in a row and is deliberately not what this calls: the middle step is a full-stack
        /// composite, which §11 measured at 84 ms against a 276 ms source snapshot on six layers at
        /// 2048², and doing that inline would freeze the canvas for the length of a tap on a large
        /// document. The split is the one `CanvasManager+Eyedropper.swift` is written around —
        /// `eyedropperRecipe` on the main actor captures the document as a value, `sampledColor` is
        /// pure and states it is safe from any thread (the same contract `Compositor.composite`
        /// makes), and `applyEyedropperResult` comes back to the main actor to write the colour.
        ///
        /// **The pick lands on touch-down; the *revert* waits for touch-up, and the gap between them
        /// is deliberate.** `minimumPressDuration = 0` means `.began` is touch-down, which is where
        /// the colour should be read from — it is the pixel the artist aimed at. But the revert puts
        /// a *painting* tool back, and `reconcileLayers` makes the active layer's host interactive
        /// again on the next SwiftUI pass the moment it sees one (`Tool.paintsOnCanvas`). Doing that
        /// under a touch that is still on the glass re-opens the owner's bug from the other side: the
        /// picking touch itself is safe, since UIKit bound it to the container at hit-test time and
        /// never re-routes a live touch, but any *new* contact is hit-tested when it arrives — a
        /// palm, a steadying finger, the artist starting their next stroke a frame early — and that
        /// one would land in a stroke view that had no business being live yet. Holding the revert
        /// until the recognizer says the touch is gone means the tool the artist put their pen down
        /// with is the tool it is lifted from, and the next touch is the first that can paint. That
        /// is the behaviour the owner specified, in their words on 2026-08-17: *"the brush stroke
        /// only is initiated the next time the pencil taps."*
        ///
        /// The two facts are joined in `finishEyedropperIfSettled` rather than sequenced, because
        /// neither reliably comes second: on a flick the touch is gone long before an 84 ms composite
        /// returns, and on a deliberate press the composite returns first. Whichever arrives last
        /// performs the revert.
        ///
        /// `guard` order below is load-bearing: `eyedropperTouchIsDown` is set for *every* `.began`,
        /// before the pencil-only gate and before the in-flight gate, so a touch that is declined or
        /// swallowed still holds the revert off while it is down. The state is cleared unconditionally
        /// on `.ended`/`.cancelled`, so no path can strand the artist in the eyedropper.
        @objc func handleEyedropperPress(_ recognizer: TouchTypePressRecognizer) {
            switch recognizer.state {
            case .began:
                break
            case .ended, .cancelled, .failed:
                eyedropperTouchIsDown = false
                finishEyedropperIfSettled()
                return
            default:
                return
            }
            eyedropperTouchIsDown = true
            guard let container = containerView else { return }
            // Before the gate, as every canvas touch is: a declined finger still closes an open
            // top-bar dropdown, because closing a menu by tapping away from it is not drawing.
            canvasManager.canvasInteractionBegan()
            guard !canvasManager.pencilOnlyDrawing || recognizer.lastTouchType == .pencil else { return }
            guard !eyedropperPickInFlight else { return }
            // **Rule (i)**, the same line the other four container recognizers now open with: with
            // the pick armed, dragging a guide grip or a shape handle used to move the chrome *and*
            // replace the brush colour and revert the tool — so the artist finished the drag holding
            // a different colour and a different tool than the one they started it with. Declining
            // here leaves `eyedropperRevertPending` false, so the `.ended` arm above has nothing to
            // settle and the tool is not disturbed.
            //
            // container's bounds are set to canvasSize (`applyTransform`) and it carries the
            // zoom/rotation as its own `transform`, so this single call *is* the view→canvas mapping
            // at any zoom and any rotation — UIKit inverts the transform. Same line `handleFillPress`
            // uses. See `Eyedropper`'s note on why the feature contains no transform arithmetic.
            let canvasPoint = recognizer.location(in: container)
            guard CanvasTouchOwner.owner(in: canvasTouchInputs(chrome: canvasChrome(at: canvasPoint))) == .eyedropper else { return }

            guard let recipe = canvasManager.eyedropperRecipe() else {
                canvasManager.applyEyedropperResult(nil, revertTool: false)
                eyedropperRevertPending = true
                finishEyedropperIfSettled()
                return
            }

            eyedropperPickInFlight = true
            // **`sandwichQueue`, not a global queue.** That queue is serial and its stated job is to
            // serialise "the composite half of every rebuild off the main thread" — a pick is one
            // more of those. On a global queue a pick landing just after an edit would composite the
            // whole stack *concurrently* with the sandwich rebuild doing the same, holding two
            // canvas-sized results at once on a canvas where `CompositorBudget` is already cutting
            // one composite into strips to fit. The cost of sharing it is that a pick can wait a rebuild out,
            // which is tens of milliseconds on a deliberate tap.
            Self.sandwichQueue.async { [weak self] in
                let picked = CanvasManager.sampledColor(from: recipe, atCanvasPoint: canvasPoint)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.eyedropperPickInFlight = false
                    self.canvasManager.applyEyedropperResult(picked, revertTool: false)
                    self.eyedropperRevertPending = true
                    self.finishEyedropperIfSettled()
                }
            }
        }

        /// Leaves the eyedropper once a pick has resolved *and* the touch that made it is off the
        /// glass — the join `handleEyedropperPress` describes. Idempotent and cheap, so both sides
        /// call it unconditionally rather than deciding which of them is last.
        private func finishEyedropperIfSettled() {
            guard eyedropperRevertPending, !eyedropperTouchIsDown, !eyedropperPickInFlight else { return }
            eyedropperRevertPending = false
            canvasManager.leaveEyedropper()
        }

    }
}

/// A press recognizer that remembers what kind of touch started it.
///
/// It exists for one reason: `UIGestureRecognizer` gives an `@objc` action the recognizer and nothing
/// else, and its public surface (`numberOfTouches`, `location(ofTouch:in:)`, `state`) never reaches a
/// `UITouch`. So a plain `UILongPressGestureRecognizer` cannot tell a finger from the pencil, and
/// both of the canvas's press handlers have to: `handleCatchAllTap`, or pencil-only drawing goes on
/// announcing "this layer has no drawing surface" at every finger tap — including the taps whose only
/// purpose was to close the layer panel — and `handleFillPress`, or the fill tool floods the artwork
/// from a palm the artist did not know was touching down.
///
/// **Both press recognizers are this type, and the policy is deliberately not in here.** The first
/// version of this class was `CatchAllTapRecognizer`, named after its one caller, and the shape of the
/// generalisation is worth stating because the obvious one is wrong: this could take a
/// `shouldAccept: (UITouch) -> Bool` and fail the sequence itself, which would make the fill case a
/// one-liner — and would break the catch-all, whose whole contract is that a rejected finger tap
/// *still* recognizes far enough to dismiss the open menu (see `handleCatchAllTap`). The two consumers
/// want the same fact and opposite answers to "and then what", so the fact is what is shared. Recording
/// the touch type is a mechanism; refusing the touch is a policy, and it lives with the handler that
/// has the rest of the context — the selected tool, the layer state, the menu.
///
/// **`UIGestureRecognizerDelegate.gestureRecognizer(_:shouldReceive:)` was the alternative**, and it
/// does receive the `UITouch`. It was rejected because the `Coordinator` is the shared delegate of
/// pan, pinch, rotation, the touch counter and both presses, so the stash would be written by every
/// recognizer's touches and read by two — the readers would have to filter by identity, and would
/// still be leaning on an ordering between a delegate callback and an action dispatch that UIKit
/// does not document. A subclass owns its own field and cannot be written by anything else, and the
/// codebase already reaches for exactly this shape twice (`StrokeGestureRecognizer` for the same
/// pencil test, `TouchCountRecognizer` for a live touch count).
final class TouchTypePressRecognizer: UILongPressGestureRecognizer {
    /// The touch type of the most recent touch to land on this recognizer.
    ///
    /// Written before `super.touchesBegan`, which is what can drive the recognizer to `.began` and
    /// dispatch the action, so the handler always reads this sequence's own value and never the
    /// previous one. Not cleared in `reset()` for the same reason from the other side: `reset()` runs
    /// at the end of a sequence, after the action, and clearing there would only create a window in
    /// which the value could read as unset. It is overwritten on every touch-down instead.
    ///
    /// `.direct` is the initial value — the conservative one. Read before any touch has arrived, which
    /// cannot actually happen, it would suppress a notice rather than raise a spurious one, and a
    /// spurious notice is the bug this type was added to fix.
    private(set) var lastTouchType: UITouch.TouchType = .direct

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // A pencil among the touches wins. `numberOfTouchesRequired` is 1, but UIKit still delivers
        // extra touches here, and "the artist has the pen down" is the fact the handler wants — not
        // "the arbitrary first member of a Set was a finger".
        if let touch = touches.first(where: { $0.type == .pencil }) ?? touches.first {
            lastTouchType = touch.type
        }
        super.touchesBegan(touches, with: event)
    }
}
