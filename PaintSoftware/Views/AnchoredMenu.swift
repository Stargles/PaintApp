import SwiftUI
import UIKit

// The placement arithmetic and the dismissal rule live in `AnchoredMenuGeometry.swift`, with no
// SwiftUI in them, so `AnchoredMenuLogicTests` can pin both without a simulator.

// MARK: - The touch observer

/// A gesture recognizer that recognises nothing, ever, and exists only to be told when a touch
/// begins.
///
/// **This is the whole answer to TODO (39) and to the canvas freeze.** A `.popover` dismisses itself
/// by covering the screen with `_UIPassthroughGateGestureRecognizer`, which swallows drags whole and
/// — worse — strands every canvas recognizer bound alongside it when it goes away under a live
/// two-finger gesture (`CanvasPresentation`'s header). This does the opposite: it fails immediately,
/// so it delays nothing, cancels nothing and competes with nothing, and the touch it reported goes on
/// to reach whatever was under it. One drag dismisses the menu **and** scrolls the track, which is
/// what the owner asked for.
///
/// `cancelsTouchesInView = false` is what makes it passive rather than merely quiet: without it, a
/// recognizer that reaches a terminal state cancels the touches it saw.
final class PassiveTouchDownObserver: UIGestureRecognizer {

    /// The touch's location in the recognizer's view, and the view UIKit bound it to.
    var onTouchDown: ((CGPoint, UIView?) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first, let host = view {
            onTouchDown?(touch.location(in: host), touch.view)
        }
        // Terminal on the first touch of every sequence: this is an observer, and a recognizer that
        // stays `.possible` is one that other recognizers can be made to wait on.
        state = .failed
    }
}

/// **The one place that decides whether an open presentation closes.** Every `AnchoredMenu` in the
/// editor — the timeline's own and every `CanvasPresentation` `View.canvasPresentationHost` draws —
/// tells this where it is while it is on screen, and one `PassiveTouchDownObserver` on the window
/// asks `AnchoredMenuDismissal.presentationsToDismiss` which of them each new touch has left.
///
/// **One observer for the editor's lifetime, never one per menu**, because the observer is itself a
/// recognizer bound to the canvas touches, and a menu that took its observer down with it would be
/// removing a recognizer from under the very two-finger gesture whose first finger closed it — the
/// shape of the freeze this replaced. This one is installed when the editor reaches a window and is
/// removed only when the editor leaves it.
///
/// **Touches outside the app's own content are not "outside the menu".** A `Menu` raised from inside
/// a presented picker (the palette menu in `ColorPickerPanel`), an alert, a sheet and the keyboard
/// are all drawn by UIKit outside the root view controller's view; a touch on one of them is a touch
/// on something the presentation raised or sits under, and closing the presentation for it would
/// tear down the picker the artist is still using.
final class AnchoredMenuRouter {
    private var open: [CanvasPresentation: (placement: AnchoredMenuDismissal.Placement, dismiss: () -> Void)] = [:]

    func place(_ presentation: CanvasPresentation, _ placement: AnchoredMenuDismissal.Placement,
               dismiss: @escaping () -> Void) {
        open[presentation] = (placement, dismiss)
    }

    func remove(_ presentation: CanvasPresentation) {
        open.removeValue(forKey: presentation)
    }

    fileprivate func touchDown(at point: CGPoint) {
        guard !open.isEmpty else { return }
        let doomed = AnchoredMenuDismissal.presentationsToDismiss(touchAt: point,
                                                                  open: open.mapValues(\.placement))
        for presentation in doomed { open[presentation]?.dismiss() }
    }
}

extension EnvironmentValues {
    /// The editor's `AnchoredMenuRouter`, provided once by `View.canvasPresentationHost`. Nil outside
    /// the editor, where there is no canvas and no anchored menu.
    @Entry var anchoredMenuRouter: AnchoredMenuRouter?
}

/// Hangs the router's one observer on the window for as long as it is in the hierarchy.
///
/// **On the window rather than on a view of its own**, because the point is to hear about touches
/// no menu covers — a view can only be told about touches that hit-test into it, and one big enough
/// to hear everything would be the screen-covering gate this replaced.
///
/// Coordinates are reported in the window's space, which is what `.frame(in: .global)` measures, so
/// the two are directly comparable.
struct AnchoredMenuRouterHost: UIViewRepresentable {

    let router: AnchoredMenuRouter

    func makeUIView(context: Context) -> ObserverHost {
        ObserverHost(router: router)
    }

    func updateUIView(_ host: ObserverHost, context: Context) {}

    static func dismantleUIView(_ host: ObserverHost, coordinator: ()) {
        host.uninstall()
    }

    /// Takes no touches itself (`isUserInteractionEnabled = false`) and draws nothing. It is here
    /// only to have a window to hang the recognizer on and a lifetime to match the editor's.
    final class ObserverHost: UIView {
        private let router: AnchoredMenuRouter
        private var observer: PassiveTouchDownObserver?

        init(router: AnchoredMenuRouter) {
            self.router = router
            super.init(frame: .zero)
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
            recognizer.onTouchDown = { [weak self, weak window] point, touched in
                guard let self, let content = window?.rootViewController?.view,
                      let touched, touched.isDescendant(of: content) else { return }
                self.router.touchDown(at: point)
            }
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
/// Every presentation over the canvas is one of these: the timeline's menus since TODO (39), and
/// every other `CanvasPresentation` since TODO (110) (`View.canvasPresentationHost`). The owner's
/// ruling on 2026-09-06 is why it is this rather than `UIPopoverPresentationController
/// .passthroughViews`: passthrough would have let the drag through while leaving the menu standing
/// over a track that had scrolled out from under it, and a cel menu names a *specific block*.
///
/// What it captures is exactly what it covers. There is no dismiss region, no gate, and no
/// presentation — a touch that lands anywhere else reaches whatever is there, and the editor's
/// `AnchoredMenuRouter` separately decides whether it closes this.
struct AnchoredMenu<Content: View>: View {

    /// Which presentation this is — what the router files its placement under.
    let presentation: CanvasPresentation

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

    @Environment(\.anchoredMenuRouter) private var router

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
                // **Drawn, rather than inherited from a presentation.** Every one of these used to get
                // a popover's chrome for free; their content is written in white labels (or
                // `.primary`) and the app is `.preferredColorScheme(.dark)`, so a near-black card is
                // what they were being shown on and what they still need.
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
                // Measured before placed: `placed` is empty-sized until `measured` arrives, which is
                // the state `AnchoredMenuDismissal` reads as "not laid out yet".
                .onChange(of: AnchoredMenuDismissal.Placement(menuFrame: placed, toggleControlFrame: toggleControl),
                          initial: true) { _, placement in
                    router?.place(presentation, placement, dismiss: onDismiss)
                }
        }
        .onPreferenceChange(AnchoredMenuSizeKey.self) { measured = $0 }
        .onDisappear { router?.remove(presentation) }
        // One identity per presentation, so a drawer that swaps which menu it shows in the same slot
        // (`AnimationTimeline.anchoredMenuLayer`) takes the old one's placement out of the router
        // rather than leaving it filed under a menu that is gone.
        .id(presentation)
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
