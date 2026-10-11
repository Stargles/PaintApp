import SwiftUI
import UIKit

/// **Where a hold lands** — see `ModifierHold` for the rule. A transparent view over the whole window
/// that is hit-tested **first**, and answers `self` only to a touch the rule makes a hold, `nil` to
/// every other (the touch falls through to whatever is under it, as if the view were not there).
///
/// **Hit-testing is the mechanism, and it is the one that needs no cooperation from anyone.** A touch
/// is bound to a view once, at touch-down, and every recogniser that will ever read it is chosen from
/// that view's ancestors. A touch bound here has none of the app's: no button action on its lift, no
/// `tap` on a cel row, no scrub on the ruler, no dab from the canvas's stroke recogniser, no slider
/// grabbed at touch-down. A recogniser-side claim races the ones that act at touch-down, and the app's
/// own history is the argument against reaching for one (`AnchoredMenu`'s header on the popover gate
/// that stranded the canvas's recognisers).
///
/// It has no responder behaviour of its own: the touches it is bound to are dropped here rather than
/// handed up the chain.
final class HoldShieldView: UIView {
    private let hold: ModifierHold

    init(hold: ModifierHold) {
        self.hold = hold
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Only a touch **landing** is hit-tested for a view to bind to, so a `.began` touch in the event is
    /// what makes this a landing; anything else (a hover, a probe with no event) falls through.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let began = event?.allTouches?.contains(where: { $0.phase == .began }) == true
        guard let event, event.type == .touches, event.timestamp > 0, hold.claimsLanding else { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

/// Hangs the hold on the window for as long as the editor is in it: the one `TouchCountRecognizer` that
/// counts every touch whatever view it is bound to, and the `HoldShieldView` above everything.
///
/// **On the window, like `AnchoredMenuRouterHost`**, and for its reason: a view can only be told about
/// touches that hit-test into it, and the count has to include the touch that is a hold.
struct ModifierHoldHost: UIViewRepresentable {

    let hold: ModifierHold

    func makeUIView(context: Context) -> HostView {
        HostView(hold: hold)
    }

    func updateUIView(_ host: HostView, context: Context) {}

    static func dismantleUIView(_ host: HostView, coordinator: ()) {
        host.uninstall()
    }

    /// Takes no touches itself and draws nothing; it is here to have a window to hang things on and a
    /// lifetime to match the editor's.
    final class HostView: UIView, UIGestureRecognizerDelegate {
        private let hold: ModifierHold
        private let counter = TouchCountRecognizer(target: nil, action: nil)
        private let shield: HoldShieldView

        init(hold: ModifierHold) {
            self.hold = hold
            shield = HoldShieldView(hold: hold)
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            counter.name = "window.touchCounter"
            counter.delegate = self
            counter.onTouchesChanged = { [weak hold] _ in hold?.onTouchesChanged?() }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            uninstall()
            guard let window else { return }
            window.addGestureRecognizer(counter)
            shield.frame = window.bounds
            window.addSubview(shield)
            hold.counter = counter
        }

        func uninstall() {
            counter.view?.removeGestureRecognizer(counter)
            shield.removeFromSuperview()
            if hold.counter === counter { hold.counter = nil }
        }

        /// **The counter recognises alongside everything.** It never recognises anything itself, but
        /// UIKit makes recognisers exclusive by default and fails the rest of a touch's recognisers the
        /// moment one of them recognises — which would end the count on the very touch it is there to
        /// qualify.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gestureRecognizer === counter
        }
    }
}
