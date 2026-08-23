import Foundation

// MARK: - Who owns a canvas touch

/// The one place that answers "who owns this canvas touch".
///
/// **Why this type exists.** A single one-finger touch on the canvas is arbitrated today by
/// fourteen independent decisions spread over three unrelated UIKit mechanisms — recognizer
/// `isEnabled`, view `isUserInteractionEnabled`, and `hitTest` overrides — each of which spells its
/// own predicate over the same four inputs (`selectedTool`, `activePanel`, `floatingPiece`, the
/// active layer's state), and a fifth question (`shouldRequireFailureOf`) reads three of them back
/// out. Four defects trace to that arrangement, three of them inside one week:
///
///  * 2026-08-22 — the pick tool was dead with the Select panel open. The eyedropper's recognizer
///    consulted `activePanel`; the selection overlay's gate never consulted `selectedTool`; **the
///    touch was owned by nobody.** Fixed by one shared property, `isEyedropperArmed`, which is this
///    idea applied exactly once.
///  * 2026-08-22 (`30e38e3`) — dragging a smart shape's outline drew a stroke, because
///    `ShapeOverlayView.hitTest` claimed the handles and declined everything else. A different
///    mechanism, the same class of defect.
///  * 2026-08-17 — the eyedropper picked a colour **and** painted, because `shouldInteract`'s tool
///    clause was a hand-maintained `!= .fill` list. `Tool.paintsOnCanvas` was the fix, and is the
///    shape this file copies.
///  * Still open — "two-finger pan/pinch/rotate is dead while Fill is selected, on device"
///    (BUGS.md). See `transformDependencyIsUnresolvable` for what this type can and cannot say
///    about it.
///
/// **What makes it structural rather than sloppy, and why the function takes a value.**
/// `activePanel` is `@State` on `DrawingView`, while `selectedTool` and `floatingPiece` live on
/// `CanvasManager`. *No single object can see all four inputs*, which is why no single function
/// exists today. So this one reaches for nothing: it takes `CanvasTouchInputs` explicitly, which is
/// what lets `activePanel` stay where it is and what makes the whole answer testable headlessly —
/// the same argument `Tool.paintsOnCanvas` makes one clause smaller.
///
/// **Scope: one finger, and the arbitration only.** Two-finger navigation (pan / pinch / rotate) is
/// deliberately not an owner here. Those three recognizers are never gated by tool, panel, floating
/// piece or layer state; the only thing that can stall them is the failure dependency in
/// `CanvasView.shouldRequireFailure`, which this file models separately as
/// `transformWaitsOnActiveStroke` / `transformDependencyIsUnresolvable` rather than folding into the
/// owner.
///
/// **`contenders(in:)` is the interesting half.** Today's mechanisms are *not* mutually exclusive:
/// every container-mounted recognizer carries `cancelsTouchesInView = false`, and a recognizer
/// attached to an ancestor still receives a touch that a descendant's `hitTest` claimed. So two
/// mechanisms can — and in the cases below do — both act on one touch. `contenders(in:)` returns
/// every mechanism that would act; `owner(in:)` returns the first by precedence, or `.nobody`.
/// A count other than one is a defect, and `CanvasTouchOwnerLogicTests` pins the exact set.
enum CanvasTouchOwner: String, CaseIterable, Hashable {
    /// The active layer's own `StrokeGestureRecognizer`, inside its `LayerHostView`. The stroke, the
    /// erase, and the smart-shape gesture that grows out of holding one still.
    case activeLayerStroke

    /// `SelectionOverlayView`, capturing a new selection because the Select panel is open.
    case selectionOverlay

    /// `SelectionOverlayView` again, but borrowed by the fill tool's lasso mode. A different action
    /// from the same view, so a different owner: one ends in a `Selection`, the other in a fill.
    case lassoFill

    /// The fill tool's `fillTapRecognizer` — flood mode only; lasso mode is `.lassoFill`.
    case fillPress

    /// The eyedropper's `eyedropperTapRecognizer`.
    case eyedropper

    /// The text tool's `textTapRecognizer`, which places a new box.
    case textPress

    /// `FloatingPieceOverlayView`. **A total claim**: it is pinned to the whole container, has no
    /// `hitTest` override, and goes interactive the moment a piece is floating, so every touch
    /// inside the canvas is its — including the tap-outside that commits the piece.
    case floatingPiece

    /// `ShapeOverlayView`, on a touch that landed on a pending shape's handle or its outline.
    case shapeOverlay

    /// `TextOverlayView`, on a touch that landed in a live text box or on its move band.
    case textOverlay

    /// `TextTransformOverlayView`, on a touch that landed on one of a live text box's grips.
    case textTransformOverlay

    /// `ObjectTransformOverlayView`, on a touch that landed on the Move box's grips or its interior
    /// — a vector layer mid-transform, or a lassoed vector piece floating.
    case objectTransformOverlay

    /// `GuideOverlayView`, on a touch that landed on a guide grip.
    case guideOverlay

    /// `catchAllTapRecognizer` — the touch the canvas cannot act on, which exists to *say so*
    /// ("no layers", "this layer is hidden", "a value layer holds no pixels") rather than swallow it.
    case catchAllNotice

    /// Nobody claims this touch, and nothing tells the artist why. **This is exactly the state the
    /// 2026-08-22 pick-tool bug was in**, which is why it is a named case a test can assert on
    /// rather than a fallthrough.
    case nobody
}

// MARK: - The inputs, stated

/// What the active layer is, as far as owning a touch is concerned.
///
/// **Kind only — whether it is on screen is a separate input.** Three distinctions and no more,
/// because these are the three the fourteen gates make of a layer's *kind*. Visibility is
/// `CanvasTouchInputs.activeLayerIsOnScreen`, and the two axes are deliberately not folded together:
/// `reconcileLayers` decides `host.isHidden` from visibility and `host.isUserInteractionEnabled`
/// from `shouldInteract`, which never consults visibility, so a hidden `.value` layer and a hidden
/// `.vector` layer answer the gates differently from a hidden `.raster` one. A single enum with a
/// `.hidden` case cannot say which kind is hidden, and both ways of resolving that lose a state the
/// app can actually be in: fold a hidden value layer into `.hidden` and `shouldInteract` wrongly
/// goes true (which stakes pan/pinch/rotate on a recognizer in an invisible view — see
/// `transformDependencyIsUnresolvable`); fold it into `.noDrawingSurface` and the catch-all stops
/// raising "this layer is hidden". Two axes cost one `Bool` and lose neither.
enum CanvasActiveLayer: String, CaseIterable, Hashable {
    /// No layers at all, or `currentLayerIndex` parked out of range — `deleteLayer` leaves it at -1
    /// when the last layer goes, so this is a real running state and not only an empty document.
    case none

    /// A `.value` layer: `Layer.hasNoDrawingSurface`. Neither of its modes holds pixels for a stroke
    /// to land in.
    case noDrawingSurface

    case vector
    case raster

    var exists: Bool {
        switch self {
        case .none: return false
        case .noDrawingSurface, .vector, .raster: return true
        }
    }

    /// `Layer.hasNoDrawingSurface`, restated over the states this enum keeps apart.
    var hasNoDrawingSurface: Bool {
        switch self {
        case .noDrawingSurface: return true
        case .none, .vector, .raster: return false
        }
    }
}

/// Which live overlay chrome the touch landed on, or `.none` for plain canvas.
///
/// **This is the position-dependent half of the arbitration, made explicit.** Five `hitTest`
/// overrides each claim a small target and decline everything else; whether they claim *this* touch
/// is a question about where the finger is, which no amount of state can answer. So the caller
/// answers it — by asking the overlays, exactly as `handleTextPress` already does — and hands the
/// answer in. `30e38e3` was a defect in precisely this half: the shape overlay claimed the handles,
/// declined the outline, and the outline drag became a stroke.
enum CanvasTouchChrome: String, CaseIterable, Hashable {
    /// Plain canvas: no overlay's `hitTest` claimed this point.
    case none
    /// `ShapeOverlayView.target(at:)` answered — a handle, or the pending shape's outline.
    case shapeHandleOrOutline
    /// `TextOverlayView.hitTest` answered — inside a live text box, or on its move band.
    case textBoxOrBand
    /// `TextTransformOverlayView.handle(at:)` answered — one of the box's grips.
    case textHandle
    /// `ObjectTransformOverlayView.target(at:)` answered — a Move grip, or the box's interior.
    case transformBoxOrHandle
    /// `GuideOverlayView.grip(at:)` answered.
    case guideGrip

    /// The overlay that owns a touch on this chrome. Exhaustive, no `default:`: a sixth overlay that
    /// learns to claim a target has to say who that makes the owner.
    var owner: CanvasTouchOwner? {
        switch self {
        case .none: return nil
        case .shapeHandleOrOutline: return .shapeOverlay
        case .textBoxOrBand: return .textOverlay
        case .textHandle: return .textTransformOverlay
        case .transformBoxOrHandle: return .objectTransformOverlay
        case .guideGrip: return .guideOverlay
        }
    }
}

/// Everything the fourteen gates read, in one value.
///
/// Taken as a struct rather than read off `CanvasManager` because **no object can see all of it**:
/// `panel` is `@State` on `DrawingView` and the rest is on the manager. That is the whole reason
/// this is a value type and the function is `static`.
struct CanvasTouchInputs: Hashable {
    var tool: Tool
    var fillMode: FillMode
    var panel: ActivePanel
    /// `CanvasManager.floatingPiece != nil` — a raster Move/Duplicate piece.
    var hasFloatingPiece: Bool
    /// `CanvasManager.vectorFloat != nil` — a lassoed vector region floating (LASSO_MOVE.md).
    /// **A different input from `hasFloatingPiece`, and the asymmetry between them is a live
    /// defect** — see `CanvasTouchOwnerLogicTests`' conflict table.
    var hasVectorFloat: Bool
    /// `CanvasManager.isVectorTransforming` — Move engaged on a vector layer with no selection.
    var isVectorTransforming: Bool
    var activeLayer: CanvasActiveLayer
    /// `isLayerEffectivelyVisible(currentLayerIndex)` — the layer's own switch *and* every enclosing
    /// folder's (§4.1). `reconcileLayers` sets `host.isHidden = !this`, and UIKit delivers no touch
    /// to a hidden view, so this is a gate in its own right — one that `shouldInteract` never
    /// mentions because it is applied through a different property one line above it.
    ///
    /// **Kept apart from `activeLayer` on purpose.** The host can be `isUserInteractionEnabled` and
    /// invisible at the same time, and that combination is what `transformDependencyIsUnresolvable`
    /// is about. See `CanvasActiveLayer`'s own comment for why one enum cannot carry both.
    var activeLayerIsOnScreen: Bool
    var chrome: CanvasTouchChrome

    init(tool: Tool,
         fillMode: FillMode = .flood,
         panel: ActivePanel = .none,
         hasFloatingPiece: Bool = false,
         hasVectorFloat: Bool = false,
         isVectorTransforming: Bool = false,
         activeLayer: CanvasActiveLayer = .raster,
         activeLayerIsOnScreen: Bool = true,
         chrome: CanvasTouchChrome = .none) {
        self.tool = tool
        self.fillMode = fillMode
        self.panel = panel
        self.hasFloatingPiece = hasFloatingPiece
        self.hasVectorFloat = hasVectorFloat
        self.isVectorTransforming = isVectorTransforming
        self.activeLayer = activeLayer
        // Normalised rather than stored as given: a layer that does not exist is not on
        // screen, and letting the value type hold that pair would be the same class of
        // mistake as the collapsed enum this axis replaced.
        self.activeLayerIsOnScreen = activeLayer.exists && activeLayerIsOnScreen
        self.chrome = chrome
    }
}

// MARK: - The fourteen gates, each restated once

extension CanvasTouchInputs {
    /// `activePanel == .select`. **The only distinction any gate makes over `ActivePanel`** — every
    /// one of the fourteen spells `== .select` or `!= .select` and ignores the other nine cases.
    /// Named so that the enumeration in the tests proves that rather than assuming it.
    var selectPanelIsOpen: Bool { panel == .select }

    /// `CanvasView.Coordinator.isEyedropperArmed`, verbatim. **The Select panel is deliberately
    /// absent**: Select is a panel, not a `Tool`, so arming the eyedropper does not close it, and
    /// the momentary pick is the artist's most recent word. That absence is the 2026-08-22 fix.
    var isEyedropperArmed: Bool { tool == .eyedropper && !hasFloatingPiece }

    /// `CanvasView.Coordinator.isLassoFilling`, verbatim. The Select panel wins the tie: a selection
    /// drag begun there must not turn into a fill because the fill tool happens to be the last one
    /// picked in the toolbar.
    var isLassoFilling: Bool {
        tool == .fill && fillMode == .lasso && !selectPanelIsOpen && !hasFloatingPiece
    }

    /// `reconcileLayers`' `shouldInteract`, verbatim — the layer host's and its stroke view's
    /// `isUserInteractionEnabled`.
    ///
    /// **It does not consult visibility, and that is not an oversight in the restatement — it is
    /// what the code says.** Visibility is applied one line up as `host.isHidden`, a different
    /// mechanism, which is why `activeHostReceivesTouches` exists below and why the two differ.
    var activeHostIsInteractive: Bool {
        activeLayer.exists
            && tool.paintsOnCanvas
            && !selectPanelIsOpen
            && !hasFloatingPiece
            && !hasVectorFloat
            && !(isVectorTransforming && activeLayer == .vector)
            && !activeLayer.hasNoDrawingSurface
    }

    /// Whether a touch can actually reach the active layer's stroke recognizer: interactive *and*
    /// on screen. The two halves come from two different mechanisms and disagree whenever the active
    /// layer is hidden with a paint tool selected.
    var activeHostReceivesTouches: Bool { activeHostIsInteractive && activeLayerIsOnScreen }

    /// `updateSelectionOverlay`'s `overlay.isCapturingGestures`, verbatim.
    var selectionOverlayIsCapturing: Bool {
        isLassoFilling
            || (selectPanelIsOpen && !hasFloatingPiece && !hasVectorFloat && !isEyedropperArmed)
    }

    /// `FloatingPieceOverlayView.update` — `isUserInteractionEnabled = newPiece != nil`, on a view
    /// pinned to the whole container with no `hitTest` override.
    var floatingOverlayIsInteractive: Bool { hasFloatingPiece }

    /// `updateActiveLayerAndTool`'s `fillTapRecognizer.isEnabled`, as the assignment spells it.
    ///
    /// **The assignment sits below a `guard` this predicate does not restate, and that is a defect
    /// rather than a simplification.** In `updateActiveLayerAndTool` the eyedropper's and the text
    /// tool's gates are written *above* `guard canvasManager.layers.indices.contains(...)`, with a
    /// doc comment explaining why; the fill's is written below it, along with `guard let host`. So
    /// with no layers — or with `currentLayerIndex` parked at -1 mid-delete — the fill recognizer is
    /// never re-evaluated and keeps whatever value it last held. This property states the answer the
    /// gate *means*, which is a behaviour change on exactly that combination; it is listed as a
    /// chosen answer in `CanvasTouchOwnerLogicTests`.
    var fillPressIsEnabled: Bool {
        tool == .fill && fillMode == .flood && !selectPanelIsOpen && !hasFloatingPiece
    }

    /// `eyedropperTapRecognizer.isEnabled = isEyedropperArmed`.
    var eyedropperPressIsEnabled: Bool { isEyedropperArmed }

    /// `textTapRecognizer.isEnabled`, verbatim. The Select clause is real rather than the
    /// eyedropper's bug in a different hat: `ActionsMenu.addTextRow` closes the Select panel on the
    /// way into text mode, so the two clauses cannot both bite.
    var textPressIsEnabled: Bool { tool == .text && !selectPanelIsOpen && !hasFloatingPiece }

    /// `reconcileLayers`' `needsCatch`, verbatim: no layers, the active layer not effectively
    /// visible, or the active layer holding no pixels.
    var catchAllIsEnabled: Bool {
        !activeLayer.exists || !activeLayerIsOnScreen || activeLayer.hasNoDrawingSurface
    }

    /// Whether the catch-all would actually *say* anything. `handleCatchAllTap` asks
    /// `Tool.paintsOnCanvas` before raising a notice — the path exists to explain why a touch that
    /// would have drawn did not, and the fill and the eyedropper are not owed an explanation.
    var catchAllRaisesNotice: Bool { catchAllIsEnabled && tool.paintsOnCanvas }
}

// MARK: - The fifteenth question: what the transform recognizers wait on

extension CanvasTouchInputs {
    /// `CanvasView.shouldRequireFailure`, reduced. It reads three flags back off the view hierarchy —
    /// the host's `isUserInteractionEnabled`, the stroke view's, and the stroke recognizer's
    /// `isEnabled` — and the first two are both `shouldInteract` while the third is never assigned
    /// anywhere in the app. So the whole predicate is `activeHostIsInteractive`.
    ///
    /// `true` means pan / pinch / rotate must wait for the active layer's stroke recognizer to fail
    /// before they may begin.
    var transformWaitsOnActiveStroke: Bool { activeHostIsInteractive }

    /// **When that dependency is staked on a recognizer that cannot resolve.**
    ///
    /// The dependency asks "is the active host accepting touches?". The question that decides
    /// whether the stroke recognizer will ever reach a terminal state is "did *this* touch reach the
    /// host?", and two things can answer no while `shouldInteract` is still true:
    ///
    ///  * the host is hidden (`!activeLayerIsOnScreen`) — `shouldInteract` never consults visibility,
    ///    so it stays `true`, `host.isHidden` is set `true` one line above it, and UIKit delivers
    ///    nothing to a hidden view's recognizers;
    ///  * an overlay above the hosts claimed the touch in its `hitTest` — a shape outline, a text
    ///    box or grip, a Move grip, a guide grip.
    ///
    /// In both, the stroke recognizer sits in `.possible` having received nothing, which is the
    /// deadlock `shouldRequireFailure`'s own doc comment closed for *inactive* layers and left open
    /// here. The symptom is a canvas that will not pan, pinch or rotate.
    ///
    /// **This does not explain BUGS.md's "two-finger pan is dead while Fill is selected".** With
    /// Fill selected `Tool.paintsOnCanvas` is false, so `shouldInteract` is false, so no dependency
    /// is stated at all — the arbitration layer exonerates itself there, and the search belongs
    /// elsewhere. It does describe a *different* dead canvas, reachable with a brush selected.
    var transformDependencyIsUnresolvable: Bool {
        guard transformWaitsOnActiveStroke else { return false }
        return !activeLayerIsOnScreen || chrome != .none
    }
}

// MARK: - The answer

extension CanvasTouchOwner {
    /// Every mechanism that would act on this touch, most specific first.
    ///
    /// **More than one is not a modelling artefact — it is what the app does.** Each container-mounted
    /// recognizer sets `cancelsTouchesInView = false`, and UIKit delivers a touch to the recognizers
    /// of every view in its responder chain, so a `hitTest` claim by an overlay does not take the
    /// touch away from the fill press underneath it. `handleTextPress` compensates by re-running the
    /// text overlays' own `hitTest` before it acts, which is the one place that double delivery is
    /// handled today; that compensation is modelled here.
    static func contenders(in i: CanvasTouchInputs) -> [CanvasTouchOwner] {
        var result: [CanvasTouchOwner] = []

        if let chromeOwner = i.chrome.owner { result.append(chromeOwner) }

        // A total claim over the container, so it precedes everything mounted below it — but not the
        // recognizers mounted on the container itself, which is why it does not return early.
        if i.floatingOverlayIsInteractive { result.append(.floatingPiece) }

        if i.selectionOverlayIsCapturing {
            result.append(i.isLassoFilling ? .lassoFill : .selectionOverlay)
        }

        // Only where no overlay claimed the point: every one of the five `hitTest` overrides sits
        // above the layer hosts, and a claim there is what keeps the touch off the stroke view.
        if i.activeHostReceivesTouches, i.chrome == .none { result.append(.activeLayerStroke) }

        if i.eyedropperPressIsEnabled { result.append(.eyedropper) }
        if i.fillPressIsEnabled { result.append(.fillPress) }
        // `handleTextPress`' own guard: a tap that landed on the live box or on one of its grips
        // does nothing here, or tapping into your own text would commit it and open a fresh box.
        if i.textPressIsEnabled, i.chrome != .textBoxOrBand, i.chrome != .textHandle {
            result.append(.textPress)
        }
        if i.catchAllRaisesNotice { result.append(.catchAllNotice) }

        return result
    }

    /// The single mechanism entitled to act on this touch.
    ///
    /// **Behaviour-preserving where the gates agree**: with exactly one contender this returns it,
    /// which is what happens today. Where they disagree it returns the first by the precedence
    /// `contenders(in:)` lists — that is a *choice*, and every combination in which it has to be made
    /// is enumerated by `CanvasTouchOwnerLogicTests.testEveryTouchWithMoreThanOneClaimant` so the
    /// list can be reviewed rather than discovered later.
    static func owner(in i: CanvasTouchInputs) -> CanvasTouchOwner {
        contenders(in: i).first ?? .nobody
    }
}

// MARK: - What each tool brings of its own

extension Tool {
    /// The container-mounted recognizer this tool owns, or nil when its canvas touch goes to the
    /// active layer's stroke view instead.
    ///
    /// **Exhaustive, with no `default:`, for the reason `Tool.paintsOnCanvas` is** — that property
    /// replaced a hand-maintained `!= .fill` exclusion list that adding `.eyedropper` to the enum did
    /// not grow, and the owner reported the result on 2026-08-17. A tool added after this cannot
    /// repeat it: it will not compile until it names its recognizer or says it has none.
    ///
    /// The two answers are complementary by construction — a tool with a recognizer here is a tool
    /// `paintsOnCanvas` returns false for, and `CanvasTouchOwnerLogicTests` asserts that rather than
    /// trusting it.
    func canvasRecognizerOwner(fillMode: FillMode) -> CanvasTouchOwner? {
        switch self {
        case .pen, .pencil, .eraser:
            return nil
        case .fill:
            switch fillMode {
            case .flood: return .fillPress
            case .lasso: return .lassoFill
            }
        case .eyedropper:
            return .eyedropper
        case .text:
            return .textPress
        }
    }
}
