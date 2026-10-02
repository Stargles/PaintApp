import SwiftUI
import UIKit

/// **A name that is edited where it is shown** — the scene's title in the top bar and a layer's or
/// folder's name in its row. The owner, 2026-10-02: Scribble is refused app-wide (`ScribbleRefusal`), so
/// the tap-to-rename sheet and the rename alerts, which only existed to give handwriting a field of its
/// own, go; a name is typed into where it stands.
///
/// **One rule, so every name behaves alike.**
///
///  * Tapping the field begins editing, with the whole name selected: typing replaces it, and a second
///    tap puts the caret where a typo is.
///  * **Return commits, and so does a touch anywhere else** — the field watches the window while it is
///    being edited (`tapAway`) and lets go of the keyboard at the first touch that is not its own, so the
///    touch that takes the artist to the next thing also finishes this one. The touch still reaches what
///    it was aimed at.
///  * **An empty name, or an unchanged one, commits nothing**: the field shows the name it had. A layer
///    with no name is a row nobody can find, and an edit that changed nothing is not an undo step.
///  * Only the name the artist typed leaves, trimmed, through `onCommit` — the model's own rename
///    (`renameLayer`, `renameFolder`, the scene's `projectName`) is what records it.
///
/// **A `UITextField`, not a SwiftUI `TextField`, for both homes.** One of them is a table cell, and both
/// need the window-wide tap-away that no SwiftUI field offers; one component with one behaviour is the
/// point of having it. `InlineNameFieldView` is the SwiftUI door for the top bar.
final class InlineNameField: UITextField, UITextFieldDelegate, UIGestureRecognizerDelegate {

    /// The name as the model has it. What editing starts from, and what an empty or unchanged edit
    /// shows again. Reassigning it while the field is being edited leaves the artist's text alone.
    var name: String = "" {
        didSet { if !isFirstResponder { text = name } }
    }

    /// The artist finished with a name that is not empty and not the one it had — trimmed.
    var onCommit: ((String) -> Void)?

    /// Editing ended, committed or not. After `onCommit`, so a caller that hides the field here finds the
    /// model already renamed.
    var onEndEditing: (() -> Void)?

    /// Room either side of the text, so the edit background does not hug the glyphs.
    private static let inset: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        borderStyle = .none
        textColor = .white
        tintColor = .systemBlue
        returnKeyType = .done
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        autocapitalizationType = .words
        clearButtonMode = .whileEditing
        layer.cornerRadius = 6
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: Self.inset, dy: 0) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: Self.inset, dy: 0) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: Self.inset, dy: 0) }

    /// The width the name takes, with its insets — what a caller laying the field out around its text asks.
    var intrinsicTextWidth: CGFloat {
        ((text ?? name) as NSString).size(withAttributes: [.font: font ?? UIFont.systemFont(ofSize: 17)]).width
            + 2 * Self.inset
    }

    // MARK: - Editing

    func textFieldDidBeginEditing(_ textField: UITextField) {
        backgroundColor = UIColor.white.withAlphaComponent(0.14)
        text = name
        window?.addGestureRecognizer(tapAway)
        // After UIKit has put the caret where the tap landed: the whole name is selected, so a new one is
        // typed straight over it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFirstResponder else { return }
            self.selectAll(nil)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        resignFirstResponder()
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        tapAway.view?.removeGestureRecognizer(tapAway)
        backgroundColor = .clear
        let typed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        text = name
        if !typed.isEmpty, typed != name {
            name = typed
            onCommit?(typed)
        }
        onEndEditing?()
    }

    // MARK: - A touch anywhere else finishes the edit

    /// Present on the window only while the field is being edited. Zero press duration, so it begins on
    /// touch-down rather than after a tap has been told from a drag; it cancels nothing and delays
    /// nothing, so the touch goes on to do whatever it was aimed at — the next row, a tool, the canvas.
    private lazy var tapAway: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(touchedElsewhere(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        return recognizer
    }()

    @objc private func touchedElsewhere(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began { resignFirstResponder() }
    }

    /// Not the field's own touches — a tap in the text moves the caret, and the clear button is a subview
    /// of the field.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        return !view.isDescendant(of: self)
    }

    /// Never in the way of another recognizer: it only watches.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// `InlineNameField` for SwiftUI — the scene's title in the top bar. The field is always on screen and
/// shows `name`; the artist taps it and types.
struct InlineNameFieldView: UIViewRepresentable {
    let name: String
    var onCommit: (String) -> Void

    /// The floor and ceiling of the field's width. A short name stays a target a fingertip can find, and a
    /// long one is clipped in the bar rather than pushing the icons either side of it.
    static let widthRange: ClosedRange<CGFloat> = 120...240
    private static let height: CGFloat = 34

    func makeUIView(context: Context) -> InlineNameField {
        let field = InlineNameField()
        field.textAlignment = .center
        field.font = .preferredFont(forTextStyle: .body)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: InlineNameField, context: Context) {
        field.name = name
        field.onCommit = onCommit
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: InlineNameField, context: Context) -> CGSize? {
        let ceiling = min(Self.widthRange.upperBound, proposal.width ?? Self.widthRange.upperBound)
        let wanted = min(max(field.intrinsicTextWidth + 24, Self.widthRange.lowerBound), ceiling)
        return CGSize(width: wanted, height: Self.height)
    }
}
