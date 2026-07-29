import UIKit

/// Reports how many touches are currently on the canvas without ever recognizing anything itself,
/// so it can sit alongside every other recognizer without competing for a single touch.
///
/// This exists because the smart-shape snap constraint has to engage when a finger joins a touch
/// sequence that is *already* under way — the pen has been drawing for a second or more by then.
/// `UILongPressGestureRecognizer(numberOfTouchesRequired: 2)`, which used to drive the snap, has
/// long since failed by that point: it starts its clock on the first touch and gives up when the
/// required fingers aren't all down in time. Counting touches directly has no such window.
final class TouchCountRecognizer: UIGestureRecognizer {
    var onCountChanged: ((Int) -> Void)?

    /// Touches currently down, for anything that needs the count at a moment no touch event is
    /// arriving — e.g. a shape appearing under fingers that were already resting on the canvas.
    var activeCount: Int { active.count }

    private var active: Set<UITouch> = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        active.formUnion(touches)
        onCountChanged?(active.count)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        active.subtract(touches)
        onCountChanged?(active.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        active.subtract(touches)
        onCountChanged?(active.count)
    }

    override func reset() {
        super.reset()
        guard !active.isEmpty else { return }
        active.removeAll()
        onCountChanged?(0)
    }
}
