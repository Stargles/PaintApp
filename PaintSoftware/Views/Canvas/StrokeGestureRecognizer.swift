import UIKit

/// A single-touch stroke-capture gesture recognizer: claims exactly one touch as the "drawing"
/// touch (mirroring the role `PKCanvasView.drawingGestureRecognizer` used to play) and fails
/// immediately if a second touch arrives, so the container's two-finger pan/pinch/rotate
/// recognizers — which dynamically wait for this recognizer to fail, see `Coordinator.
/// gestureRecognizer(_:shouldRequireFailureOf:)` — can take over cleanly instead of racing a
/// stray single-finger dot.
final class StrokeGestureRecognizer: UIGestureRecognizer {
    var requiresPencilOnly = false
    var onBegin: ((UITouch) -> Void)?
    var onMove: ((UITouch, UIEvent) -> Void)?
    var onEnd: ((UITouch) -> Void)?
    /// The tracked touch went away without finishing its stroke — a second finger arrived and handed
    /// the sequence to the transform recognizers, or the system cancelled it. Distinct from `onEnd`
    /// because there is no stroke to commit: whatever was painted so far has to be rolled back.
    var onCancel: (() -> Void)?
    /// Fires for every touch that lands here, *before* the pencil-only gate below is even checked —
    /// used to dismiss an open top-bar dropdown the instant the canvas is touched at all. A finger tap
    /// while pencil-only mode is on fails that gate and never actually draws, but should still close
    /// whatever menu was open, same as a real stroke does (see `CanvasManager.interactionBegan`).
    var onAnyTouchBegan: (() -> Void)?
    /// When this answers true, a second touch arriving mid-stroke is ignored and the tracked touch
    /// keeps the recognizer, instead of failing it. Set while a smart shape is following the pen:
    /// that second finger means "snap this shape", not "start panning", and failing here would also
    /// strand the shape — a failed recognizer receives no further touches, so the pen lifting would
    /// never reach `onEnd` and the shape would never reach its adjustable state.
    var shouldIgnoreAdditionalTouches: (() -> Bool)?

    private var trackedTouch: UITouch?

    /// Every `state` write in this class goes through here so `ActionRecorder` sees the transition at
    /// the instant it happens.
    ///
    /// **Why a funnel rather than a `didSet` on `state`:** `UIGestureRecognizer.state` is inherited,
    /// and Swift will not let a subclass attach a property observer to it — the only ways in are
    /// overriding the property outright (which means reimplementing storage UIKit owns) or routing
    /// the assignments, and routing the seven of them is the smaller, safer edit. `UIGestureRecognizer`
    /// is also not KVO-compliant for `state`, so observing it from outside is not on the table.
    ///
    /// **Why this recognizer is instrumented from the inside at all**, when `WindowEventTap` already
    /// sweeps every recognizer's state after each event: this class is the one whose terminal state
    /// the transform gestures wait on (`Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)`),
    /// so its transitions are the ones that need exact ordering against the touch that caused them.
    /// The sweep would still catch them, but only after the whole event had been dispatched — by
    /// which time UIKit may already have reset `.ended` back to `.possible`, and the `.ended` would
    /// simply not be in the file. The recorder deduplicates the two routes, so this costs one extra
    /// line here and no duplicates there.
    ///
    /// Cost when not recording: one static `Bool` load. Nothing else in this function runs.
    private func transition(to newState: UIGestureRecognizer.State) {
        ActionRecorder.ifRecording { $0.recognizerTransition(self, to: newState, source: "inline") }
        state = newState
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onAnyTouchBegan?()
        if trackedTouch != nil {
            guard shouldIgnoreAdditionalTouches?() != true else { return }
            failTrackedStroke()
            return
        }
        guard touches.count == 1, let touch = touches.first,
              !requiresPencilOnly || touch.type == .pencil else {
            transition(to: .failed)
            return
        }
        trackedTouch = touch
        transition(to: .began)
        onBegin?(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        transition(to: .changed)
        onMove?(trackedTouch, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        transition(to: .ended)
        onEnd?(trackedTouch)
        self.trackedTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        transition(to: .cancelled)
        self.trackedTouch = nil
        onCancel?()
    }

    override func reset() {
        super.reset()
        // UIKit's own return to `.possible`, which no assignment in this class produces and no action
        // message announces. It is the line that proves a stroke recognizer *did* recycle — the
        // absence of which is the deadlock this recorder was built to catch.
        ActionRecorder.ifRecording { $0.recognizerTransition(self, to: .possible, source: "reset") }
        trackedTouch = nil
    }

    /// Gives up a stroke already in progress. Failing without this left the partial stroke painted
    /// into the layer with no undo step behind it (the recognizer stops receiving touches the moment
    /// it fails, so `onEnd` never came), which is how a two-finger pan started mid-stroke used to
    /// leave a permanent, un-undoable mark.
    private func failTrackedStroke() {
        trackedTouch = nil
        state = .failed
        onCancel?()
    }
}
