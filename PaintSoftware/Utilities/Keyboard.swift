import Combine
import SwiftUI
import UIKit

// **The software keyboard, in one file.** Nothing in the app is laid out around it (`ignoringTheKeyboard`,
// applied at the root of every screen), so what is typed into is covered if it is low on the screen. The two
// surfaces that keep what is being typed in view — a name typed in a scrolling list (`KeyboardScrollClearance`)
// and the text tool's pan of the canvas — each ask "how much of my bottom does it cover?", and both ask it
// through `KeyboardFrame` rather than each decoding the notification their own way.

extension View {
    /// **Keeps the keyboard out of this screen's layout — the whole screen's, not one field's.** SwiftUI
    /// answers a keyboard by squeezing the root into what it leaves, and a root whose content needs more
    /// than that overflows it *centred*: the editor's top bar went off the top of the screen while the
    /// scene's name was being typed (the owner, 2026-10-10, in landscape). `ignoresSafeArea(.keyboard)` alone
    /// is not enough, because the root still reports the content's own minimum to the window and is
    /// centred on it; a `GeometryReader` reports exactly what it is offered, so what it holds is never
    /// positioned by what it needs. Apply it once, to a window's root; a sheet is a window of its own.
    func ignoringTheKeyboard() -> some View {
        GeometryReader { screen in
            self.frame(width: screen.size.width, height: screen.size.height)
        }
        .ignoresSafeArea(.keyboard)
    }
}

enum KeyboardFrame {
    /// The keyboard's frame in screen coordinates as it is about to be: each time it rises, moves or goes
    /// away. A keyboard on its way out reports a frame below the screen.
    static var willChange: AnyPublisher<CGRect, Never> {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue }
            .eraseToAnyPublisher()
    }
}

extension View {
    /// Keeps `covered` at how much of this view's bottom the keyboard covers (`UIView.keyboardOverlap`), for a
    /// view that must lay itself out above the keyboard though nothing else is laid out around it — a
    /// floating menu, which has no scroll view to scroll when the keyboard is over all of it.
    func keyboardCoveredBottom(_ covered: Binding<CGFloat>) -> some View {
        background(KeyboardCoveredReader(covered: covered))
    }
}

private struct KeyboardCoveredReader: UIViewRepresentable {
    @Binding var covered: CGFloat

    func makeUIView(context: Context) -> Reader {
        let reader = Reader()
        reader.isUserInteractionEnabled = false
        return reader
    }

    func updateUIView(_ reader: Reader, context: Context) {
        reader.onChange = { overlap in
            // Alongside the keyboard's own slide, so what rides above it moves with it.
            withAnimation(.easeOut(duration: 0.25)) { covered = overlap }
        }
    }

    final class Reader: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var subscription: AnyCancellable?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            subscription = window == nil ? nil : KeyboardFrame.willChange
                .sink { [weak self] frame in
                    guard let self else { return }
                    self.onChange?(self.keyboardOverlap(frame))
                }
        }
    }
}

extension UIView {
    /// How much of this view's bottom the keyboard covers, `keyboardFrame` being what `KeyboardFrame` gave
    /// (screen coordinates). Zero when the keyboard is away or does not reach the bottom of the screen: a
    /// floating keyboard covers a patch the artist put there and moves with their hand, not a strip.
    func keyboardOverlap(_ keyboardFrame: CGRect) -> CGFloat {
        guard let screen = window?.screen, keyboardFrame.maxY >= screen.bounds.maxY - 1 else { return 0 }
        let covered = convert(keyboardFrame, from: screen.coordinateSpace)
        return max(0, bounds.maxY - max(covered.minY, bounds.minY))
    }
}

/// **Keeps a view that is being typed into above the keyboard, inside the scroll view it stands in** — the
/// list scrolls and the screen does not. The scroll view is given as much bottom inset as the keyboard covers
/// of it, so its last row can be scrolled up out from under the keyboard, and the view is scrolled to inside
/// what is left; both go back when the clearance ends. Every inline rename in a scrolling list gets this from
/// `InlineNameField` itself — the layer rail's rows, the gallery's folder tiles, the timeline's animation
/// groups — so no list asks for it and none keeps its own copy.
final class KeyboardScrollClearance {
    /// Breathing room kept between the view and the keyboard's top, and above it when it is scrolled to the
    /// top of the list.
    private static let margin: CGFloat = 12

    private weak var scrollView: UIScrollView?
    private weak var target: UIView?
    private let restingInset: CGFloat
    private let restingIndicatorInset: CGFloat
    private var subscription: AnyCancellable?

    /// Nil when `target` stands in no scroll view — a title in a bar has nothing to scroll.
    init?(keeping target: UIView) {
        guard let scrollView = target.enclosingScrollView else { return nil }
        self.scrollView = scrollView
        self.target = target
        restingInset = scrollView.contentInset.bottom
        restingIndicatorInset = scrollView.verticalScrollIndicatorInsets.bottom
        subscription = KeyboardFrame.willChange.sink { [weak self] frame in self?.follow(frame) }
    }

    deinit { end() }

    func end() {
        subscription = nil
        guard let scrollView else { return }
        scrollView.contentInset.bottom = restingInset
        scrollView.verticalScrollIndicatorInsets.bottom = restingIndicatorInset
        // UIKit leaves the offset where the inset let it go, which is past the end of the content once the
        // inset is gone — a list shorter than the screen would rest scrolled clean out of its own view.
        let inset = scrollView.adjustedContentInset
        let lowest = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        if scrollView.contentOffset.y > lowest {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: lowest), animated: true)
        }
        self.scrollView = nil
    }

    private func follow(_ keyboardFrame: CGRect) {
        guard let scrollView, let target else { return }
        let overlap = scrollView.keyboardOverlap(keyboardFrame)
        scrollView.contentInset.bottom = restingInset + overlap
        scrollView.verticalScrollIndicatorInsets.bottom = restingIndicatorInset + overlap
        scrollView.scrollRectToVisible(scrollView.convert(target.bounds, from: target).insetBy(dx: 0, dy: -Self.margin),
                                       animated: true)
    }
}

extension UIView {
    /// The nearest scroll view this view stands in, or nil.
    fileprivate var enclosingScrollView: UIScrollView? {
        var view = superview
        while let candidate = view {
            if let scrollView = candidate as? UIScrollView { return scrollView }
            view = candidate.superview
        }
        return nil
    }
}
