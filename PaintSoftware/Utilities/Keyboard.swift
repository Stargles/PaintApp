import Combine
import SwiftUI
import UIKit

// **The software keyboard, in one file.** Nothing in the app is laid out around it (`ignoringTheKeyboard`,
// applied at the root of every screen), so what is typed into is covered if it is low on the screen. The two
// surfaces that keep what is being typed in view — the layer rail's rename and the text tool's pan of the
// canvas — each ask "how much of my bottom does it cover?", and both ask it through `KeyboardFrame` rather
// than each decoding the notification their own way.

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
