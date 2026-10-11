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
    /// The tracked touch went away without finishing its stroke. Distinct from `onEnd` because the
    /// stroke did not reach its lift — and **the reason decides what happens to the ink**, which is
    /// the whole of `StrokeGiveUp`: a second finger arriving hands the sequence to the transform
    /// recognizers and the dab so far is rolled back, while a sequence that simply stopped being
    /// delivered gets committed with an undo step rather than thrown away.
    ///
    /// This replaced a bare `onCancel` that meant "roll back" unconditionally, which is how a stroke
    /// drawn under a timeline menu came to vanish the moment the artist started the next one.
    var onGiveUp: ((StrokeGiveUp) -> Void)?
    /// Fires once per fresh touch sequence, the instant this recognizer knows the touch is not one of
    /// two or more that arrived together in the same `touchesBegan` call — **before** the pencil-only
    /// gate, so a finger tap under pencil-only mode still reports here even though it goes on to fail
    /// and never draws, and a tap on a stroke canvas still closes an open top-bar dropdown.
    ///
    /// **This is a report, not a verdict.** A hand lands the two fingers of a pan 10–20 ms apart in
    /// two separate events, so the first finger reaches here alone and is indistinguishable from the
    /// start of a stroke; what it is gets decided by `CanvasManager.canvasInteractionBegan`, which
    /// watches a finger for a moment before it stops playback or closes a panel, and acts on a
    /// pencil — the touch that cannot be half of a transform — at once. That is why the touch comes
    /// with it. A touch that arrives *with* another in one batch (`pinch` and `rotate`, which is all
    /// XCUITest can synthesise) never reaches here at all.
    var onSingleTouchBegan: ((UITouch) -> Void)?

    private var trackedTouch: UITouch?

    /// **`requiresExclusiveTouchType = false` makes who may interrupt a stroke this recogniser's own
    /// decision, in `touchesBegan`, and not UIKit's filter.** UIKit's default is `YES`, and the SDK
    /// header states the consequence outright: *"once it receives a touch of a certain type, it will
    /// ignore new touches of other types, until it is reset to `UIGestureRecognizerStatePossible`."*
    /// With the default a palm landing mid pen stroke would be filtered out before binding, and so
    /// would a pencil landing mid *finger* stroke — which must hand the stroke over, not be dropped.
    /// Turned off, both are offered and answered below by type.
    ///
    /// `UIView.isMultipleTouchEnabled` (set in `StrokeCanvasView.init`) is the prerequisite for a second
    /// touch being delivered to the view at all; type exclusivity is decided per *recogniser*, not per
    /// view.
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        requiresExclusiveTouchType = false
    }

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
    /// Cost per stroke sample: one state compare. `.changed` to `.changed` is not a transition, so
    /// only the stroke's handful of real ones reach the recorder.
    private func transition(to newState: UIGestureRecognizer.State) {
        if newState != state {
            ActionRecorder.ifRecording { $0.recognizerTransition(self, to: newState, source: "inline") }
        }
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
        if let tracked = trackedTouch {
            // **First: is the tracked stroke alive, or is it a corpse?** Everything below this line
            // was written for one situation — a second touch landing while the artist's first is
            // still on the glass — and until now it was applied to both, because the class could not
            // tell them apart. That mis-answer is symptom 1 of the owner's 2026-08-18 report: a
            // stroke whose delivery was cut by a presentation teardown leaves this recognizer
            // holding a dead touch, the next stroke's touch-down lands here, and the hand-off path
            // discards the ink that is sitting visible on the canvas. See `StrokeInterruption`.
            let reason = StrokeInterruption.giveUpReason(
                trackedTouchIsAmongArrivals: touches.contains(tracked),
                trackedTouchIsStillInTheEvent: event.allTouches?.contains(tracked) ?? true,
                trackedTouchHasFinished: tracked.phase == .ended || tracked.phase == .cancelled)
            if reason == .interrupted {
                giveUpTrackedStroke(.interrupted)
                return
            }
            let arrivals = touches.filter { $0 !== tracked }
            // Nothing new began — UIKit does not re-deliver a touch's `began`, so this is defensive
            // only, but every branch below reads "what arrived" and an empty answer means "nothing".
            guard !arrivals.isEmpty else { return }
            let fingers = arrivals.filter { $0.type != .pencil }
            // **Palm rejection, stated rather than inherited.** Until `isMultipleTouchEnabled` was set
            // on the canvas views (see `StrokeCanvasView.init`) a second touch in a later event was
            // never delivered here at all, so a palm landing mid-stroke was harmless by accident. It
            // arrives now, and it must not take the artist's stroke away: a hand resting on the glass
            // is not a request to stop drawing, and `giveUpTrackedStroke(.handedOver)` discards everything painted so
            // far with no undo step (see `handleCancel`).
            //
            // The rule is by *type*, not by count: **a finger cannot interrupt a pencil stroke.** A
            // second pencil still can — that is not a palm, it is a different pen — and a finger can
            // still interrupt a *finger* stroke, which is what hands a one-finger drag over to the
            // two-finger canvas transform and is the behaviour this class was written around. So this
            // narrows the fail path to exactly the sequences that meant it, and it is not a
            // relaxation: before this line the palm did not reach the fail path either.
            //
            // **`ignore` rather than a bare `return`, and that part is load-bearing.** A recognizer is
            // only `reset()` once *every* touch it is associated with has finished, so a palm merely
            // left unhandled would keep this recognizer out of `.possible` for as long as the hand
            // rests — after the pen has lifted and the stroke is long over. That recognizer is the one
            // `Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)` points canvas pan/pinch/
            // rotate at, so the cost of getting this wrong is a canvas that will not move, which is a
            // failure this file has seen from two other directions already. Disowning the touch is
            // what keeps the palm out of that bookkeeping.
            //
            // **A finger that lands while a drag takes a modifier never gets here** — it is a hold
            // (`ModifierHold`) and hit-tests to the shield, so the finger that snaps a shape and the
            // one that steadies a Move box are not this recognizer's to decline.
            if tracked.type == .pencil, arrivals.count == fingers.count {
                for finger in fingers { ignore(finger, for: event) }
                return
            }
            giveUpTrackedStroke(.handedOver)
            return
        }
        guard touches.count == 1, let touch = touches.first else {
            transition(to: .failed)
            return
        }
        // A fresh sequence, and it is not one of two-or-more touches that arrived in this same
        // batch. Before the pencil-only gate below, on purpose: a finger tap under pencil-only mode
        // must still close an open panel even though it goes on to fail and never draws.
        onSingleTouchBegan?(touch)
        guard !requiresPencilOnly || touch.type == .pencil else {
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
        // `.interrupted`, not `.handedOver`: UIKit cancels a sequence when it takes the touch away —
        // a presentation coming down over the canvas, the app going to the background, a view leaving
        // the hierarchy — and in every one of those the artist drew a line and meant it. The
        // hand-off case does not come through here at all; it is decided in `touchesBegan`.
        onGiveUp?(.interrupted)
    }

    override func reset() {
        super.reset()
        // UIKit's own return to `.possible`, which no assignment in this class produces and no action
        // message announces. It is the line that proves a stroke recognizer *did* recycle — the
        // absence of which is the deadlock this recorder was built to catch.
        ActionRecorder.ifRecording { $0.recognizerTransition(self, to: .possible, source: "reset") }
        trackedTouch = nil
    }

    /// Gives up a stroke already in progress, and says why. **The reason is what decides whether
    /// the artist keeps their ink** — see `StrokeGiveUp`, which is where that decision lives.
    ///
    /// Failing without this left the partial stroke painted into the layer with no undo step behind
    /// it (the recognizer stops receiving touches the moment it fails, so `onEnd` never came), which
    /// is how a two-finger pan started mid-stroke used to leave a permanent, un-undoable mark. That
    /// is still exactly right for `.handedOver`. It was being applied to `.interrupted` too, and
    /// there it is the 2026-08-18 report: ink the artist drew on purpose, discarded because the path
    /// that discards a stray pan-dab was the only path there was.
    ///
    /// **What the readback on the third line defends against, and what it does not.** The recognizer
    /// here is in `.began` or `.changed`, never `.possible`. `.failed` is documented as a transition
    /// *out of `.possible`*, so this assignment is, on paper, not a legal move. If UIKit were to drop
    /// it, the recognizer would sit in `.began` with `trackedTouch` already nil: `touchesEnded` and
    /// `touchesCancelled` would both bail at their `guard let trackedTouch`, no terminal state would
    /// ever be reached, `reset()` would never run, and the recognizer would never return to
    /// `.possible`. That recognizer is exactly the one
    /// `Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)` points canvas pan/pinch/rotate at,
    /// so two-finger canvas movement would be dead for the life of the view while drawing kept
    /// working. Re-reading `state` and falling back to `.cancelled` — legal from `.began` and
    /// `.changed` both — closes that off.
    ///
    /// **Whether any of that can happen is still unverified in both directions**, and the
    /// `.interrupted` arm has not changed that: XCUITest cannot deliver a second touch in its own
    /// event, so no test in this repo reaches this function from `touchesBegan`. What did change is
    /// that the function is now reachable from a *first* touch — the one that finds a corpse — which
    /// is a sequence a real hand produces constantly and a synthesised gesture never does.
    ///
    /// **On the reported freeze.** A UIKit popover torn down mid-sequence stranded this recognizer
    /// without a `reset()`; the editor has no UIKit presentations over the canvas any more
    /// (`CanvasPresentation`'s header), and this file's contribution to that class of bug is the
    /// `.interrupted` arm below.
    ///
    /// **What this does not fix, stated so nobody re-derives it.** The touch that *discovered* the
    /// corpse does not go on to draw: it returns here, having committed the previous stroke, and the
    /// recognizer lands in a terminal state where it receives nothing further until UIKit resets it.
    /// So an interrupted stroke still costs the artist one swallowed touch — the third attempt is the
    /// first that draws. Binding the new touch instead would mean driving `state` from `.changed` or
    /// `.ended` back to `.began`, which is not a documented transition, and getting that wrong breaks
    /// drawing outright rather than delaying it by one touch. `StrokeInterruptionLogicTests` records
    /// the limit as a test so that it stays a known cost rather than becoming a new surprise.
    /// **This recognizer has been stranded and is about to be replaced** (`StrokeCanvasView
    /// .replaceStrokeRecognizerIfStranded`): a stroke it was still tracking ends here, as
    /// `.interrupted`, because no touch will ever reach this instance again to end it. Its own state is
    /// left alone — UIKit no longer resets it, which is the whole problem.
    func relinquishStrandedStroke() {
        guard trackedTouch != nil else { return }
        trackedTouch = nil
        onGiveUp?(.interrupted)
    }

    private func giveUpTrackedStroke(_ reason: StrokeGiveUp) {
        trackedTouch = nil
        transition(to: .failed)
        // Routed through `transition` as well, so a recording shows *which* of the two branches ran.
        // That is the only evidence anyone will ever get about the open question above: this file
        // has no test reaching it, but a recorder file that shows a `.cancelled` here would settle
        // it on the spot.
        if state != .failed { transition(to: .cancelled) }
        onGiveUp?(reason)
    }
}
