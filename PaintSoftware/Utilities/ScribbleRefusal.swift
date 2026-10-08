import UIKit

/// **Scribble (iPadOS handwriting-to-text) is refused for every text input in the app, by this one
/// mechanism.** The pencil is the brush here: a pencil resting near a text field — the hex field under
/// the colour picker's opacity bar, the title, a layer's name — is handed to handwriting instead of to
/// whatever the artist was dragging, and the control they were using stops responding.
///
/// **How.** UIKit has no switch for it: there is no `isScribbleEnabled`, handwriting is attached to
/// every editable `UITextInput` unconditionally, and the one documented veto is an added
/// `UIScribbleInteraction` whose delegate says no (`UIScribbleInteraction.h`: *"you may also need to
/// suppress Scribble in views that handle Pencil events directly, like a drawing canvas, since nearby
/// text fields could take over the Pencil events for writing"*). `install()` hooks
/// `didMoveToWindow` on `UITextField` and `UITextView` once, at launch, and the hook adds that
/// interaction to each text input as it comes on screen.
///
/// **Why a hook and not a component every call site uses.** The app's text inputs are SwiftUI
/// `TextField`s, the `UITextField` of an inline name (`InlineNameField`), one `UITextView` on the
/// canvas, and whatever is added next. The only place all of them pass through is UIKit's own text
/// classes, so that is where the refusal lives: a future field cannot forget it, and there is no
/// per-feature blocker to keep in step with the others.
/// `ScribbleRefusalLogicTests` fails if any other file builds a Scribble interaction.
///
/// **Unconditional, and there is no finer seam.** The delegate is asked once, with a location and
/// nothing else, before a tap or a stroke has been told apart; no later callback can revise the
/// answer. A refused text field still takes a tap, the keyboard and a hardware keyboard exactly as
/// before — only handwriting into it is gone.
///
/// Rejected: `UITextInputContext.current.pencilInputExpected = false`. It is process-wide and
/// undocumented as a setter, and it changes which input the keyboard expects rather than who owns the
/// touch.
enum ScribbleRefusal {

    /// Installs the hook. Idempotent, and cheap to call twice; `PaintApp.init` calls it before any view
    /// exists.
    static func install() {
        _ = hooks
    }

    private static let hooks: Void = {
        hookDidMoveToWindow(of: UITextField.self)
        hookDidMoveToWindow(of: UITextView.self)
    }()

    /// The one delegate every refusing interaction shares. `UIScribbleInteraction` holds its delegate
    /// weakly, so it has to be held somewhere that outlives every text input; a nil delegate would
    /// default to *allowing* Scribble, silently.
    private static let refuser = Refuser()

    private final class Refuser: NSObject, UIScribbleInteractionDelegate {
        func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
            // iOS asking at all is the evidence that Scribble was about to take the pencil: the one
            // on-device proof that this path runs, readable in an `ActionRecorder` file.
            ActionRecorder.ifRecording {
                $0.note("scribble.veto x=\(Int(location.x.rounded())) y=\(Int(location.y.rounded()))")
            }
            return false
        }
    }

    /// Runs the class's own `didMoveToWindow` first and then adds the refusal. The IMP found by
    /// `class_getInstanceMethod` is the nearest implementation up the chain, so calling it is what a
    /// `super` call would do; `class_replaceMethod` then installs ours on `cls` itself whether or not
    /// `cls` had an implementation of its own.
    private static func hookDidMoveToWindow(of cls: UIView.Type) {
        let selector = #selector(UIView.didMoveToWindow)
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        typealias DidMoveToWindow = @convention(c) (UIView, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: DidMoveToWindow.self)
        let hook: @convention(block) (UIView) -> Void = { input in
            original(input, selector)
            // UIKit calls `didMoveToWindow` on the main thread and only there.
            MainActor.assumeIsolated { refuse(input) }
        }
        class_replaceMethod(cls, selector, imp_implementationWithBlock(hook), method_getTypeEncoding(method))
    }

    /// Adds the refusing interaction unless the input already carries it — a field moves between
    /// windows, and every move calls the hook again.
    private static func refuse(_ input: UIView) {
        guard !input.interactions.contains(where: { ($0 as? UIScribbleInteraction)?.delegate === refuser }) else { return }
        input.addInteraction(UIScribbleInteraction(delegate: refuser))
    }
}
