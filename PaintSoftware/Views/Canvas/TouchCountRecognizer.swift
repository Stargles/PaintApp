import UIKit

/// Counts the touches down anywhere in the window (`ModifierHold`), whichever view each is bound to.
///
/// **Split by touch type**, because the gesture it drives is "keep the pen held down, then drop a
/// finger" and a bare total cannot say that: a total of 2 is also two fingers panning the canvas. Counting
/// a resting palm is the price, and it is paid in `JoinedTouches`, which subtracts the fingers already
/// down when a shape began following; this must keep reporting the truth.
final class TouchCountRecognizer: ListeningGestureRecognizer, ModifierHold.Counter {
    var onTouchesChanged: ((_ total: Int) -> Void)?

    /// Touches currently down, for anything that needs the count at a moment no touch event is
    /// arriving — e.g. a shape appearing under fingers that were already resting on the canvas.
    var activeCount: Int { active.count }

    /// Non-pencil touches currently down. The pen is not one of these even while it is drawing, so
    /// `fingerCount >= 1` during a pen stroke means exactly "a finger joined".
    var fingerCount: Int { active.filter { $0.type != .pencil }.count }

    private var active: Set<UITouch> = []

    /// **The count with `touch` in it, whether or not this recognizer has heard of it yet.** Recognizers
    /// on different views are handed a touch-down in an order nothing promises, and a Move box's own
    /// pan sits on a view deeper than the host: read first, the plain count would leave the dragging
    /// touch out, a handle drag's baseline (`HandleDrag`) would be one short, and the drag would read
    /// as *joined by a finger* the moment it moved — a Move slowed to a fifth with nothing beside it.
    /// MEASURED as exactly that, once in a handful of runs. Passing nil asks for the count as it stands
    /// (every later read).
    func activeCount(including touch: UITouch?) -> Int {
        active.count + (touch.map { active.contains($0) ? 0 : 1 } ?? 0)
    }

    private func report() { onTouchesChanged?(active.count) }

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
        onTouchesChanged?(0)
    }
}
