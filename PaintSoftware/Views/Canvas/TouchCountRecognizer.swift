import UIKit

/// Reports how many touches are currently on the canvas without ever recognizing anything itself,
/// so it can sit alongside every other recognizer without competing for a single touch.
///
/// This exists because the smart-shape snap constraint has to engage when a finger joins a touch
/// sequence that is *already* under way — the pen has been drawing for a second or more by then.
/// `UILongPressGestureRecognizer(numberOfTouchesRequired: 2)`, which used to drive the snap, has
/// long since failed by that point: it starts its clock on the first touch and gives up when the
/// required fingers aren't all down in time. Counting touches directly has no such window.
///
/// The count is reported **split by touch type**, because the gesture it drives is "keep the pen
/// held down, then drop a finger" and a bare total cannot say that. A total of 2 means "two contacts
/// of any kind", which is a different gesture: it is reached by two fingers panning the canvas, and
/// it is *not* reached by pen-plus-one-finger in whichever direction UIKit happens to deliver the
/// pencil to a container-level recognizer. The recognizer already holds each `UITouch`, so the type
/// was free all along — it was only being thrown away at the callback boundary.
final class TouchCountRecognizer: UIGestureRecognizer {
    var onTouchesChanged: ((_ total: Int, _ fingers: Int) -> Void)?

    /// Touches currently down, for anything that needs the count at a moment no touch event is
    /// arriving — e.g. a shape appearing under fingers that were already resting on the canvas.
    var activeCount: Int { active.count }

    /// Non-pencil touches currently down. The pen is not one of these even while it is drawing, so
    /// `fingerCount >= 1` during a pen stroke means exactly "a finger joined".
    var fingerCount: Int { active.filter { $0.type != .pencil }.count }

    private var active: Set<UITouch> = []

    private func report() { onTouchesChanged?(active.count, fingerCount) }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        // **Without this the count is a lie the moment a pencil is involved.** UIKit defaults
        // `requiresExclusiveTouchType` to `YES`, and the SDK header says what that costs: *"once it
        // receives a touch of a certain type, it will ignore new touches of other types, until it is
        // reset."* This recognizer takes the pencil at touch-down and then never leaves `.possible`
        // — so it is never reset while the pen is down, and every finger that joins the sequence is
        // filtered out before it is ever offered here.
        //
        // The owner's 2026-08-17 capture is unambiguous: `counter:1/0` while the pen draws,
        // `counter:1/0` still when the shape starts following, no `shape.touches` line at all when
        // the finger lands 0.48 s later, and `counter:0/0` when the *pencil* lifts while the finger
        // is still on the glass. A recognizer whose only job is counting touches was counting one of
        // two. `ignore(_:for:)` above is silent throughout, because this filtering happens at
        // binding, not at refusal — see `StrokeGestureRecognizer`'s own initialiser for the full
        // reading of that capture.
        //
        // Counting a resting palm is the price, and it is paid in `Coordinator
        // .currentAccompanyingFingers()`, which subtracts the fingers already down when the shape
        // began following rather than narrowing anything here. This recognizer must keep reporting
        // the truth; deciding which fingers *mean* something is not its job.
        requiresExclusiveTouchType = false
    }

    /// Instrumentation only — behaviour is `super`'s, unchanged. See the twin in
    /// `StrokeGestureRecognizer.ignore` for why a refusal is worth recording: this recognizer's whole
    /// job is counting touches, so one it is never offered is indistinguishable, from the inside,
    /// from one that never happened.
    override func ignore(_ touch: UITouch, for event: UIEvent) {
        ActionRecorder.ifRecording {
            $0.note("ignore \($0.nameFor(self)) <- \(touch.type == .pencil ? "pencil" : "finger")"
                    + " phase:\(touch.phase.rawValue) active:\(active.count)")
        }
        super.ignore(touch, for: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        active.formUnion(touches)
        report()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        active.subtract(touches)
        report()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        active.subtract(touches)
        report()
    }

    override func reset() {
        super.reset()
        guard !active.isEmpty else { return }
        active.removeAll()
        onTouchesChanged?(0, 0)
    }
}
