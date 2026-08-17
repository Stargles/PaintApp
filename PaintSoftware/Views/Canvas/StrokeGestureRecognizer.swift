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

    /// How many **fingers** are down alongside the tracked touch right now — the "keep the pen held
    /// down and put a finger on the canvas" signal, reported from the recognizer that is already
    /// holding the pen.
    ///
    /// **This is a second, independent source for a fact `TouchCountRecognizer` also reports, and the
    /// duplication is the point.** That one lives on the canvas *container*, several views up from
    /// wherever the touch actually lands, so it depends on the whole hit-test path staying open. This
    /// one is on the view that is already receiving the pen's own samples, and the touch it counts is
    /// the very touch `shouldIgnoreAdditionalTouches` is being consulted about — if the pen is
    /// drawing, this recognizer is being fed, and a finger that joins the sequence arrives here or
    /// nowhere. `Coordinator.refreshShapeConstraint` takes the larger of the two counts, so the snap
    /// engages if *either* sees the finger, and records both so a capture says which did.
    ///
    /// Pencil touches are deliberately not counted: a second pencil is not the gesture, and the
    /// tracked touch itself must never count as its own companion.
    var onAccompanyingFingersChanged: ((Int) -> Void)?

    private var trackedTouch: UITouch?

    /// **`requiresExclusiveTouchType = false` is what makes the pen-plus-finger snap reachable at
    /// all, and it is the whole of the fix.** UIKit's default is `YES`, and the SDK header states
    /// the consequence outright: *"once it receives a touch of a certain type, it will ignore new
    /// touches of other types, until it is reset to `UIGestureRecognizerStatePossible`."*
    ///
    /// This recognizer takes the pencil at touch-down and holds it for the length of the stroke, so
    /// with the default every `.direct` touch that lands afterwards — the snapping finger, and a
    /// palm alike — is filtered out **before binding**, not declined afterwards. That distinction is
    /// exactly what the owner's 2026-08-17 capture shows and what three sessions of reading could
    /// not: the finger's `began` line carries `gr: 6` naming only `canvas.twoFingerTap`,
    /// `canvas.threeFingerTap` and system recognizers, while the pencil's carries `gr: 15`; and
    /// `ignore(_:for:)` above — which logs every refusal — is silent for that finger. Never bound,
    /// never refused. The recognizers that *did* get it are precisely the ones holding no pencil
    /// touch at the time; every one that was holding the pencil (this one, `canvas.touchCounter`,
    /// pan/pinch/rotation, and Apple's own `PKTextInputDrawingGestureRecognizer`) was excluded.
    /// Touch **type** is the only axis that partitions those 15 that way.
    ///
    /// `UIView.isMultipleTouchEnabled` (set in `StrokeCanvasView.init`) was a real and necessary
    /// prerequisite — without it the second touch is not delivered to the view at all — but it is
    /// upstream of this and could not have been sufficient, because type exclusivity is decided per
    /// *recognizer*, not per view. That is why the fix shipped before this one changed nothing on
    /// device.
    ///
    /// Turning it off does not widen what this class accepts: `touchesBegan` still refuses a finger
    /// that would interrupt a pencil stroke, by type, and only counts one while a shape is
    /// following. It widens what this class is *offered*, which is the prerequisite for either.
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        requiresExclusiveTouchType = false
    }

    /// Non-pencil touches that joined this sequence after `trackedTouch` and are being ignored rather
    /// than failing the stroke. Held so their *lift* is reported too — `touchesEnded` below returns
    /// early for any touch that is not the tracked one, so without this set a finger going down would
    /// engage the snap and a finger coming up would never release it.
    private var accompanyingFingers: Set<UITouch> = []

    private func reportAccompanyingFingers() { onAccompanyingFingersChanged?(accompanyingFingers.count) }

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

    /// Instrumentation only — behaviour is `super`'s, unchanged.
    ///
    /// UIKit calls this when a touch is refused to this recognizer, which is the *other* way a touch
    /// can be missing from `touchesBegan`. There is no overridable "should I ignore this" — the
    /// decision is private, reached through the delegate's `gestureRecognizer(_:shouldReceive:)` —
    /// but the refusal itself lands here, and that is the half worth recording. Pair it with the
    /// `gr`/`grNames` fields the tap writes on the touch's own `began` line: those say whether this
    /// recognizer was in the touch's bound set at all. Bound and then ignored is a delegate problem;
    /// never bound is a delivery problem; silence in both is neither, and they want different fixes.
    override func ignore(_ touch: UITouch, for event: UIEvent) {
        ActionRecorder.ifRecording {
            $0.note("ignore \($0.nameFor(self)) <- \(touch.type == .pencil ? "pencil" : "finger")"
                    + " phase:\(touch.phase.rawValue) tracking:\(trackedTouch != nil)")
        }
        super.ignore(touch, for: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onAnyTouchBegan?()
        if let tracked = trackedTouch {
            let arrivals = touches.filter { $0 !== tracked }
            // Nothing new began — UIKit does not re-deliver a touch's `began`, so this is defensive
            // only, but every branch below reads "what arrived" and an empty answer means "nothing".
            guard !arrivals.isEmpty else { return }
            let fingers = arrivals.filter { $0.type != .pencil }
            if shouldIgnoreAdditionalTouches?() == true {
                // A smart shape is following the pen: this finger means "snap it". Counted, so the
                // coordinator has the signal; the stroke keeps the recognizer either way.
                guard !fingers.isEmpty else { return }
                accompanyingFingers.formUnion(fingers)
                reportAccompanyingFingers()
                return
            }
            // **Palm rejection, stated rather than inherited.** Until `isMultipleTouchEnabled` was set
            // on the canvas views (see `StrokeCanvasView.init`) a second touch in a later event was
            // never delivered here at all, so a palm landing mid-stroke was harmless by accident. It
            // arrives now, and it must not take the artist's stroke away: a hand resting on the glass
            // is not a request to stop drawing, and `failTrackedStroke` discards everything painted so
            // far with no undo step (see `handleCancel`).
            //
            // The rule is by *type*, not by count: **a finger cannot interrupt a pencil stroke.** A
            // second pencil still can — that is not a palm, it is a different pen — and a finger can
            // still interrupt a *finger* stroke, which is what hands a one-finger drag over to the
            // two-finger canvas transform and is the behaviour this class was written around. So this
            // narrows the fail path to exactly the sequences that meant it, and it is not a
            // relaxation: before this line the palm did not reach the fail path either.
            //
            // Not counted as an accompanying finger. A palm that was already resting when the shape
            // formed is not "adding a finger while the pen is down", and counting it would snap a
            // shape the artist never asked to snap.
            //
            // **`ignore` rather than a bare `return`, and that part is load-bearing.** A recognizer is
            // only `reset()` once *every* touch it is associated with has finished, so a palm merely
            // left unhandled would keep this recognizer out of `.possible` for as long as the hand
            // rests — after the pen has lifted and the stroke is long over. That recognizer is the one
            // `Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)` points canvas pan/pinch/
            // rotate at, so the cost of getting this wrong is a canvas that will not move, which is a
            // failure this file has seen from two other directions already. Disowning the touch is
            // what keeps the palm out of that bookkeeping. The *snapping* finger in the branch above
            // is deliberately not disowned: its `touchesEnded` is what releases the snap, and a
            // disowned touch delivers nothing further here.
            if tracked.type == .pencil, arrivals.count == fingers.count {
                for finger in fingers { ignore(finger, for: event) }
                return
            }
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
        // Before the tracked-touch guard: a snapping finger lifting is not the tracked touch, and it
        // is exactly the event that has to release the snap. Lifting the *pen* first while the finger
        // stays down is a state the shape gesture supports (see `endInteractiveShape`), so the two
        // are tracked independently rather than one clearing the other.
        releaseAccompanying(touches)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        transition(to: .ended)
        onEnd?(trackedTouch)
        self.trackedTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        releaseAccompanying(touches)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        transition(to: .cancelled)
        self.trackedTouch = nil
        onCancel?()
    }

    private func releaseAccompanying(_ touches: Set<UITouch>) {
        guard !accompanyingFingers.isEmpty, !accompanyingFingers.isDisjoint(with: touches) else { return }
        accompanyingFingers.subtract(touches)
        reportAccompanyingFingers()
    }

    override func reset() {
        super.reset()
        // UIKit's own return to `.possible`, which no assignment in this class produces and no action
        // message announces. It is the line that proves a stroke recognizer *did* recycle — the
        // absence of which is the deadlock this recorder was built to catch.
        ActionRecorder.ifRecording { $0.recognizerTransition(self, to: .possible, source: "reset") }
        trackedTouch = nil
        // `UITouch` objects are recycled by UIKit, so a stale member here would be indistinguishable
        // from a live one on the next sequence — and a snap that never releases is worse than one
        // that never engages. The sequence is over; the count is zero by definition.
        guard !accompanyingFingers.isEmpty else { return }
        accompanyingFingers.removeAll()
        reportAccompanyingFingers()
    }

    /// Gives up a stroke already in progress. Failing without this left the partial stroke painted
    /// into the layer with no undo step behind it (the recognizer stops receiving touches the moment
    /// it fails, so `onEnd` never came), which is how a two-finger pan started mid-stroke used to
    /// leave a permanent, un-undoable mark.
    ///
    /// **What the readback on the next line defends against, and what it does not.** This is reached
    /// only from `touchesBegan`, and only when a touch is already tracked — so the recognizer is in
    /// `.began` or `.changed`, never `.possible`. `.failed` is documented as a transition *out of
    /// `.possible`*, so this assignment is, on paper, not a legal move. If UIKit were to drop it, the
    /// recognizer would sit in `.began` with `trackedTouch` already nil: `touchesEnded` and
    /// `touchesCancelled` would both bail at their `guard let trackedTouch`, no terminal state would
    /// ever be reached, `reset()` would never run, and the recognizer would never return to
    /// `.possible`. That recognizer is exactly the one
    /// `Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)` points canvas pan/pinch/rotate at,
    /// so two-finger canvas movement would be dead for the life of the view while drawing kept
    /// working. Re-reading `state` and falling back to `.cancelled` — legal from `.began` and
    /// `.changed` both — closes that off.
    ///
    /// **Whether any of that can actually happen is unverified, in both directions.** Nothing in this
    /// repo reaches this function: measured, every two-finger gesture the test suite synthesises
    /// arrives as a single `touchesBegan` carrying `touches.count == 2`, which is caught by the
    /// `touches.count == 1` guard above and takes the ordinary, legal `.possible → .failed` path.
    /// `failTrackedStroke` is only reachable when a second touch lands in a *later* event than the
    /// first, which is what a real hand does and what no test here produces. So we have never
    /// observed UIKit honouring `.began → .failed`, and we have never observed it dropping one
    /// either. Treat the paragraph above as the hazard this line is priced against, not as something
    /// that was seen.
    ///
    /// **It is emphatically not the "canvas freezes until you quit and re-enter" bug.** An earlier
    /// version of this comment claimed it was; that attribution was wrong. The real trigger is a
    /// stroke that begins while one of the timeline's popovers ("Add Drawing" / "Paste" / loop) is
    /// still up: the popover is dismissed *by* the touch that starts the stroke, and its teardown
    /// mid-sequence is what strands this recognizer without a `reset()`. The fix is in
    /// `AnimationTimeline` — `.onReceive(canvasManager.interactionBegan)` closes the three popovers
    /// before the touch becomes a stroke — and the pair of tests in `CanvasTransformFreezeUITests`
    /// (the failing case plus the dismiss-first control) is what pins it there. Nothing in this file
    /// was load-bearing for that bug.
    ///
    /// Two alternatives were considered. Assigning `.cancelled` unconditionally is one line shorter
    /// and always legal, but `.cancelled` means "I recognized, then was cancelled", a *weaker*
    /// release of a failure requirement than `.failed`'s "I never recognized" — so it would change
    /// the release semantics of every ordinary pan-begun-mid-stroke, on every build, to guard against
    /// something never observed. Deleting the readback instead was the other: it is the honest
    /// response to "no test covers this", but the line costs one comparison, provably cannot change
    /// behaviour on any build where `.failed` is honoured, and is the cheaper side of a bet whose odds
    /// nobody here knows. It stays as defence-in-depth. If it ever needs settling, the thing to write
    /// is a test that delivers the second touch in its own event.
    private func failTrackedStroke() {
        trackedTouch = nil
        transition(to: .failed)
        // Routed through `transition` as well, so a recording shows *which* of the two branches ran.
        // That is the only evidence anyone will ever get about the open question above: this file
        // has no test reaching it, but a recorder file that shows a `.cancelled` here would settle
        // it on the spot.
        if state != .failed { transition(to: .cancelled) }
        onCancel?()
    }
}
