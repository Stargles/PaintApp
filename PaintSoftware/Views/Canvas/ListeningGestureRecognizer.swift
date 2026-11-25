import UIKit

/// **A recognizer that hears touches and recognizes nothing.** It never leaves `.possible`, so it has no
/// state for UIKit to reset between sequences and so none to leave it in; it prevents no other recognizer
/// and none prevents it, and it is in no failure requirement, so nothing UIKit does to another recognizer
/// can end what this one hears.
///
/// What the touches mean is each subclass's own state, kept by its own code — which is the point: the
/// canvas's recognizers used to be UIKit's, and 43 flights from the owner's iPad show UIKit leaving them
/// terminal for good (`CanvasTouchCore`).
class ListeningGestureRecognizer: UIGestureRecognizer {

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        // UIKit defaults this to `YES`, and the SDK header says what that costs: *"once it receives a
        // touch of a certain type, it will ignore new touches of other types, until it is reset."* A
        // recognizer that is never reset would hear a pencil and no finger beside it.
        requiresExclusiveTouchType = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
