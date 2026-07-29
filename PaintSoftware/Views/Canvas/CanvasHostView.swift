import UIKit

/// Fills the SwiftUI container and reports layout changes so the coordinator
/// can refit the canvas when the window/split-view size changes.
final class CanvasHostView: UIView {
    var onLayout: (() -> Void)?
    /// Set once by `CanvasView.makeUIView`. `UndoManager` no longer backs undo/redo (see
    /// `CanvasManager.history`), so hardware-keyboard Cmd-Z/Cmd-Shift-Z needs an explicit
    /// `UIKeyCommand` pair instead of relying on the responder chain's built-in undo-manager
    /// integration.
    weak var canvasManager: CanvasManager?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(handleUndoKeyCommand)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(handleRedoKeyCommand))
        ]
    }

    @objc private func handleUndoKeyCommand() { canvasManager?.undo() }
    @objc private func handleRedoKeyCommand() { canvasManager?.redo() }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
