import UIKit

/// Which touch type a `touchesBegan(_:with:)` set resolves to, for a recognizer that only cares
/// about "was the pencil among these touches" — pencil wins the tie even though `Set<UITouch>`
/// iterates in no defined order, because the fact that matters is "the artist's pen is down", not
/// which member of the set UIKit happened to store first. An artist's off-hand can rest on the
/// glass while the pencil draws, and that resting contact must not flip `lastTouchType` to `.direct`.
///
/// Used by `TouchTypePanGestureRecognizer`/`TouchTypeTapGestureRecognizer` below.
/// `TouchTypePressRecognizer.touchesBegan` in CanvasView.swift applies the identical rule inline;
/// not shared with it because that recognizer predates this pair and touching it is out of scope
/// for the lasso pencil-only-mode fix this exists for.
///
/// Pulled out as its own file, as a function of bare `UITouch.TouchType` values rather than `UITouch`
/// itself, purely so it is unit-testable: nothing outside UIKit can construct a `UITouch`, so a
/// function that needed the touches themselves could only be exercised by a live gesture — the same
/// limitation `StrokePathFitLogicTests` notes for its own domain. Living in its own
/// UIKit-only/CoreGraphics-only file (no `View`, no `App`) is what lets it join the "App sources
/// shared with PaintSoftwareUITests" group in the project file and be tested headlessly, the same
/// arrangement `StrokeGeometry.swift`/`VectorEraser.swift` use — see `BrushEngineLogicTests`'s doc
/// comment for why `@testable import PaintSoftware` doesn't work for a `bundle.ui-testing` product.
///
/// Returns `nil` for an empty set, which callers treat as "leave `lastTouchType` at whatever it
/// already was" — mirroring `TouchTypePressRecognizer`, which also only overwrites on a non-empty set.
func resolvedLastTouchType<S: Sequence>(from types: S) -> UITouch.TouchType? where S.Element == UITouch.TouchType {
    var first: UITouch.TouchType?
    for type in types {
        if first == nil { first = type }
        if type == .pencil { return type }
    }
    return first
}

/// **Whether an input that pencil-only mode gates may proceed** — the app's one predicate, spelled
/// once.
///
/// It is written inline at nine call sites (`CanvasView.Coordinator`'s five, `SelectionOverlayView`'s
/// two, `FloatingPieceOverlayView`'s one) as
/// `!canvasManager.pencilOnlyDrawing || recognizer.lastTouchType == .pencil`, and this is that
/// expression given a name so that the tenth — TODO (59)'s graph-editor marquee — cannot invent its
/// own spelling. The existing nine are deliberately left alone: each already has a doc comment
/// arguing why *it* is gated, and rewriting them would be churn in files this function cannot be
/// tested through anyway. **New gates use this.**
///
/// The rule is `CanvasView.Coordinator.setUpGestures`' rule verbatim: the question is not "is this a
/// touch?" but *"would this input have drawn?"* — pencil-only means drawing is the pen's job, never
/// that the app stops listening to hands.
func pencilOnlyDrawingAllows(_ touchType: UITouch.TouchType, pencilOnly: Bool) -> Bool {
    !pencilOnly || touchType == .pencil
}

/// A pan recognizer that remembers what kind of touch started it.
///
/// Same shape and same reason as `CanvasView.TouchTypePressRecognizer` — see that type's doc
/// comment for the full argument, including why `UIGestureRecognizerDelegate.shouldReceive` (which
/// *does* get the `UITouch`) was rejected in favor of a subclass. Not literally reused because it
/// subclasses `UILongPressGestureRecognizer`, and the lasso/rectangle drag needs a real
/// `UIPanGestureRecognizer` for its `.began`/`.changed`/`.ended` states and `location(in:)` — there
/// is no common ancestor below `UIGestureRecognizer` to hang one shared implementation on, so the
/// `touchesBegan` override is duplicated rather than abstracted; only the tie-break
/// (`resolvedLastTouchType`) is shared.
///
/// Originally declared in `SelectionOverlayView.swift`, alongside its one call site there. Moved
/// here (TODO 47) once `FloatingPieceOverlayView` needed `TouchTypeTapGestureRecognizer` too and
/// that file is not part of the "app sources shared with PaintSoftwareUITests" group this one is —
/// see this file's own header for why that group has to stay UIKit-only.
final class TouchTypePanGestureRecognizer: UIPanGestureRecognizer {
    /// The touch type of the most recent touch to land on this recognizer. `.direct` (finger) is the
    /// conservative initial value, same reasoning as `TouchTypePressRecognizer.lastTouchType`.
    private(set) var lastTouchType: UITouch.TouchType = .direct

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let type = resolvedLastTouchType(from: touches.map(\.type)) {
            lastTouchType = type
        }
        super.touchesBegan(touches, with: event)
    }
}

/// Same idea as `TouchTypePanGestureRecognizer`, for a plain tap — `SelectionOverlayView`'s
/// automatic-selection tap, and since TODO (47) the vector and raster Move box's tap-away commit
/// (`CanvasView.Coordinator.handleMoveBoxCommit`, `FloatingPieceOverlayView.handleTapOutside`).
final class TouchTypeTapGestureRecognizer: UITapGestureRecognizer {
    private(set) var lastTouchType: UITouch.TouchType = .direct

    /// **Where this tap began**, in window coordinates — the second fact this subclass exists to
    /// carry, and it is carried for the same reason as the first: `UITapGestureRecognizer` reports
    /// only `location(in:)`, which at `.ended` is where the finger *left*, and two handlers need to
    /// know where it *arrived*.
    ///
    /// **A tap recognizer does not fail on movement, so "a tap" and "a short drag" are the same
    /// event.** `allowableMovement` is `UILongPressGestureRecognizer` API and has no counterpart
    /// here; a tap's internal slop is undocumented and generous, and the owner's recording of
    /// 2026-09-07 has one recognizing after **25.2 pt** of travel. So any handler that asks *"was
    /// this touch on X?"* and asks it of the release point is asking about a point the artist never
    /// chose. That is the whole of the vector Move box's unwanted bake: a corner drag in Uniform
    /// mode rescales along the touch-down *bearing* from the box centre and discards the drag's
    /// angle, so the box's own corner and the finger sit on one circle about the anchor and separate
    /// the moment the bearing drifts — and every point of that circle but the four corners is
    /// outside the box. Release there and `canvasChrome(at:)` answers `.none`, which is the app's
    /// spelling of "the artist tapped away", which settles the float. `FloatingPieceOverlayView`'s
    /// raster twin had it identically, against `piece.transformedBounds`.
    ///
    /// **Window coordinates, so one latch serves readers in different views** — this recognizer is
    /// mounted on the canvas container in one case and on a container-sized overlay in the other,
    /// and `convert(_:from: nil)` is the whole of what each needs.
    ///
    /// The distinction worth keeping when a third reader arrives: a handler asking *"was this touch
    /// on X?"* must ask at touch-down, because membership is what the artist chose when they landed.
    /// A handler asking *"where did the artist point?"* — `SelectionOverlayView.handleTap`'s
    /// automatic-selection tap — may read either end and is deliberately left reading `location(in:)`.
    private(set) var firstTouchLocationInWindow: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let type = resolvedLastTouchType(from: touches.map(\.type)) {
            lastTouchType = type
        }
        // **`numberOfTouches == 0` is read before `super`, so it is "this is the first touch of the
        // sequence"** — which is what makes the latch fresh per tap without an override of
        // `reset()`. Reset would work and is where the symmetric spelling would put it, but it only
        // runs on the way out of a non-`.possible` state; a sequence that never leaves `.possible`
        // would leave the previous tap's point standing, and a *stale* answer to "did this begin on
        // the box" is exactly the failure this property exists to remove.
        if numberOfTouches == 0, let touch = touches.first {
            firstTouchLocationInWindow = touch.location(in: nil)
        }
        super.touchesBegan(touches, with: event)
    }
}

/// **`TouchTypePanGestureRecognizer` for a `UILongPressGestureRecognizer`** — the shape the timeline
/// uses for a drag that must keep its touch from the first point of travel
/// (`TimelineGraphBandView.panRecognizer`, `TimelineRulerView.panRecognizer`), which is UIKit's
/// answer to `DragGesture(minimumDistance: 0)`.
///
/// The third copy of one four-line override, and the reason it is a copy is stated on
/// `TouchTypePanGestureRecognizer`: there is no common ancestor below `UIGestureRecognizer` to hang
/// one implementation on, and only the tie-break (`resolvedLastTouchType`) is shared. It is *not*
/// `CanvasView.TouchTypePressRecognizer` reused, because that type lives in a file this one cannot
/// be reached from — `CanvasView.swift` is not in the "app sources shared with PaintSoftwareUITests"
/// group and this file is, which is the whole reason the tie-break lives here.
final class TouchTypeLongPressGestureRecognizer: UILongPressGestureRecognizer {
    /// The touch type of the most recent touch to land on this recognizer. `.direct` (finger) is the
    /// conservative initial value, `TouchTypePanGestureRecognizer.lastTouchType`'s rule.
    private(set) var lastTouchType: UITouch.TouchType = .direct

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let type = resolvedLastTouchType(from: touches.map(\.type)) {
            lastTouchType = type
        }
        super.touchesBegan(touches, with: event)
    }
}
