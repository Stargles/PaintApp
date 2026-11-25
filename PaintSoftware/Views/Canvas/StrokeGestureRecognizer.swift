import UIKit

/// **Delivers one touch to a layer as a stroke.** It hears every touch on its view and draws with the one
/// the canvas says may draw (`CanvasTouchCore.drawer`): a lone finger, or a pencil. Whether it is a
/// stroke at all, and when it stops being one because a second finger made it a pan, is the canvas's
/// decision (`mayDraw`, `giveUp`); this keeps only which touch it is drawing with.
final class StrokeGestureRecognizer: ListeningGestureRecognizer {
    var requiresPencilOnly = false
    /// Whether the canvas lets this touch draw. Asked once, as it lands.
    var mayDraw: ((UITouch, UIEvent) -> Bool)?
    var onBegin: ((UITouch) -> Void)?
    var onMove: ((UITouch, UIEvent) -> Void)?
    var onEnd: ((UITouch) -> Void)?
    /// The tracked touch went away without finishing its stroke, and **the reason decides what happens to
    /// the ink** (`StrokeGiveUp`).
    var onGiveUp: ((StrokeGiveUp) -> Void)?
    /// A touch landed that may draw — **before** the pencil-only gate, so a finger tap under pencil-only
    /// mode still closes an open top-bar dropdown though it never draws.
    ///
    /// **This is a report, not a verdict.** A hand lands the two fingers of a pan 10–20 ms apart in
    /// two separate events, so the first finger reaches here alone and is indistinguishable from the
    /// start of a stroke; what it is gets decided by `CanvasManager.canvasInteractionBegan`, which
    /// watches a finger for a moment before it stops playback or closes a panel, and acts on a
    /// pencil — the touch that cannot be half of a transform — at once. That is why the touch comes
    /// with it. A touch that arrives *with* another in one event never reaches here at all.
    var onSingleTouchBegan: ((UITouch) -> Void)?

    private var trackedTouch: UITouch?

    /// Instrumentation only — behaviour is `super`'s, unchanged. A touch refused here is the *other* way
    /// one can be missing from `touchesBegan`; pair the line with the touch's own `gr` field, which says
    /// whether this recognizer was in its bound set at all.
    override func ignore(_ touch: UITouch, for event: UIEvent) {
        ActionRecorder.ifRecording {
            $0.note("ignore \($0.nameFor(self)) <- \(touch.type == .pencil ? "pencil" : "finger")"
                    + " phase:\(touch.phase.rawValue) tracking:\(trackedTouch != nil)")
        }
        super.ignore(touch, for: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first(where: { mayDraw?($0, event) ?? false }) else { return }
        // A stroke whose end never reached this view: the artist drew it and meant it, and the touch
        // that found it draws too.
        giveUp(.interrupted)
        onSingleTouchBegan?(touch)
        guard !requiresPencilOnly || touch.type == .pencil else { return }
        trackedTouch = touch
        note("began")
        onBegin?(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        onMove?(trackedTouch, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        self.trackedTouch = nil
        note("ended")
        onEnd?(trackedTouch)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        // The system takes a touch away when a presentation comes over the canvas or the app goes to the
        // background, and in both the artist drew a line and meant it.
        giveUp(.interrupted)
    }

    /// Ends the stroke being drawn, if there is one, short of its lift.
    func giveUp(_ reason: StrokeGiveUp) {
        guard trackedTouch != nil else { return }
        trackedTouch = nil
        note(reason.rawValue)
        onGiveUp?(reason)
    }

    private func note(_ what: String) {
        ActionRecorder.ifRecording { $0.model("stroke", "\($0.nameFor(self)) \(what)") }
    }
}
