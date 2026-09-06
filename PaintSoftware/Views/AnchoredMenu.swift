import SwiftUI
import UIKit

// The placement arithmetic and the dismissal rule live in `AnchoredMenuGeometry.swift`, with no
// SwiftUI in them, so `AnchoredMenuLogicTests` can pin both without a simulator.

// MARK: - The touch observer

/// A gesture recognizer that recognises nothing, ever, and exists only to be told when a touch
/// begins.
///
/// **This is the whole answer to TODO (39).** A `.popover` dismisses itself by covering the screen
/// with `_UIPassthroughGateGestureRecognizer`, which swallows every drag whole — the timeline did not
/// scroll, the ruler did not scrub, and the popover did not even go away. This does the opposite: it
/// fails immediately, so it delays nothing, cancels nothing and competes with nothing, and the touch
/// it reported goes on to reach whatever was under it. One drag dismisses the menu **and** scrolls
/// the track, which is what the owner asked for.
///
/// `cancelsTouchesInView = false` is what makes it passive rather than merely quiet: without it, a
/// recognizer that reaches a terminal state cancels the touches it saw.
final class PassiveTouchDownObserver: UIGestureRecognizer {

    var onTouchDown: ((CGPoint) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first, let host = view {
            onTouchDown?(touch.location(in: host))
        }
        // Terminal on the first touch of every sequence: this is an observer, and a recognizer that
        // stays `.possible` is one that other recognizers can be made to wait on.
        state = .failed
    }
}

/// Installs a `PassiveTouchDownObserver` on the window for as long as it is in the hierarchy.
///
/// **On the window rather than on a view of its own**, because the point is to hear about touches
/// the menu does *not* cover — a view can only be told about touches that hit-test into it, and one
/// big enough to hear everything would be the screen-covering gate this bug is about.
///
/// Coordinates are reported in the window's space, which is what `.frame(in: .global)` measures, so
/// the two are directly comparable.
struct WindowTouchObserver: UIViewRepresentable {

    let onTouchDown: (CGPoint) -> Void

    func makeUIView(context: Context) -> ObserverHost {
        let host = ObserverHost()
        host.onTouchDown = onTouchDown
        return host
    }

    func updateUIView(_ host: ObserverHost, context: Context) {
        host.onTouchDown = onTouchDown
    }

    static func dismantleUIView(_ host: ObserverHost, coordinator: ()) {
        host.uninstall()
    }

    /// Takes no touches itself (`isUserInteractionEnabled = false`) and draws nothing. It is here
    /// only to have a window to hang the recognizer on and a lifetime to match the menu's.
    final class ObserverHost: UIView {
        var onTouchDown: ((CGPoint) -> Void)?
        private var observer: PassiveTouchDownObserver?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            uninstall()
            guard let window else { return }
            let recognizer = PassiveTouchDownObserver(target: nil, action: nil)
            recognizer.onTouchDown = { [weak self] point in self?.onTouchDown?(point) }
            window.addGestureRecognizer(recognizer)
            observer = recognizer
        }

        func uninstall() {
            if let observer { observer.view?.removeGestureRecognizer(observer) }
            observer = nil
        }
    }
}

// MARK: - The menu itself

/// A menu drawn **inside the app's own view hierarchy**, hung off `anchor`.
///
/// This is what TODO (39) replaced the timeline's four `.popover`s with, and the owner's ruling on
/// 2026-09-06 is the reason it is this rather than `UIPopoverPresentationController.passthroughViews`:
/// passthrough would have let the drag through while leaving the menu standing over a track that had
/// scrolled out from under it, and a cel menu names a *specific block*.
///
/// What it captures is exactly what it covers. There is no dismiss region, no gate, and no
/// presentation — a touch that lands anywhere else reaches whatever is there, and separately tells
/// this to close.
struct AnchoredMenu<Content: View>: View {

    /// The control or block this hangs off, in global coordinates.
    let anchor: CGRect

    /// The control that toggles this menu, if it is a different thing from the anchor — see
    /// `AnchoredMenuDismissal.shouldDismiss`, where the exemption is explained.
    var toggleControl: CGRect?

    /// Names the menu for the accessibility tree, so a UI test can assert the menu is **on screen**
    /// rather than that a flag is set. A popover was findable by its content alone; an inline view
    /// in a `ZStack` needs to say so itself.
    let identifier: String

    let onDismiss: () -> Void

    @ViewBuilder let content: () -> Content

    /// The menu's measured size. `.zero` until the first layout pass, which is the state
    /// `AnchoredMenuDismissal` reads as "not laid out yet".
    @State private var measured: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.frame(in: .global)
            let placed = AnchoredMenuPlacement.frame(anchor: anchor, menuSize: measured, bounds: bounds)

            content()
                .fixedSize()
                .background(
                    GeometryReader { menu in
                        Color.clear.preference(key: AnchoredMenuSizeKey.self, value: menu.size)
                    }
                )
                // **Drawn, rather than inherited from a presentation.** These four menus used to get
                // a popover's chrome for free; three of their content views are written in white
                // labels and one in `.primary`, and the app is `.preferredColorScheme(.dark)`, so a
                // near-black card is what all four were being shown on and what all four still need.
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(white: 0.11).opacity(0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
                .position(x: placed.midX - bounds.minX, y: placed.midY - bounds.minY)
                // One frame invisible rather than one frame in the wrong place: `measured` is `.zero`
                // until the background above has reported, and a menu placed from a zero size would
                // flash at the anchor's centre before jumping.
                .opacity(measured == .zero ? 0 : 1)
                // A container element, so the menu is findable **as a menu** and its controls stay
                // findable inside it. Without `.contain` the identifier lands on a view that is not
                // an accessibility element at all, and a test can then only assert on the menu's
                // contents — which is exactly the "assert what is stored, not what is drawn" hole
                // that shipped three unusable features on 2026-09-05.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
                .background(
                    WindowTouchObserver { point in
                        if AnchoredMenuDismissal.shouldDismiss(touchAt: point,
                                                               menuFrame: placed,
                                                               toggleControlFrame: toggleControl) {
                            onDismiss()
                        }
                    }
                )
        }
        .onPreferenceChange(AnchoredMenuSizeKey.self) { measured = $0 }
    }
}

private struct AnchoredMenuSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Anchors

/// Where each anchored menu hangs from, collected from the controls themselves so nothing has to
/// hard-code a position that layout owns.
struct AnchoredMenuAnchorKey: PreferenceKey {
    static let defaultValue: [CanvasPresentation: CGRect] = [:]
    static func reduce(value: inout [CanvasPresentation: CGRect],
                       nextValue: () -> [CanvasPresentation: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's frame as the anchor for `presentation`.
    func anchoredMenuAnchor(_ presentation: CanvasPresentation) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: AnchoredMenuAnchorKey.self,
                                       value: [presentation: proxy.frame(in: .global)])
            }
        )
    }
}
