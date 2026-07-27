import Foundation

/// A single global, byte-budgeted undo/redo stack shared by every mutating action in the app
/// (strokes, fills, layer/folder structure, animation timeline edits, ...). Replaces the old
/// per-layer `UndoManager` instances: callers describe *what changed* as an `undo`/`redo`
/// closure pair plus a rough retained-byte cost, and hand it to `record(_:)` — this class owns
/// all the undo/redo stack bookkeeping so that logic exists in exactly one place.
///
/// Trimming is budgeted by approximate retained bytes rather than step count: a single stroke
/// on a large canvas can retain tens of MB (the before/after image snapshot), so a fixed step
/// count doesn't actually bound memory the way a byte budget does.
final class UndoHistory {
    struct Action {
        let name: String
        let cost: Int
        let undo: () -> Void
        let redo: () -> Void
    }

    private(set) var undoStack: [Action] = []
    private(set) var redoStack: [Action] = []
    var maxCost: Int

    init(maxCost: Int = 300 * 1024 * 1024) {
        self.maxCost = maxCost
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func record(_ action: Action) {
        undoStack.append(action)
        redoStack.removeAll()
        trim()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
        redoStack.append(action)
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action.redo()
        undoStack.append(action)
    }

    func removeAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Evicts the oldest undoable actions once retained cost (across both stacks — a redo
    /// entry still holds the same captured state as its undo counterpart) exceeds the budget.
    /// Only trims `undoStack`: a redo-able action is the most recent thing the user did, so
    /// it's kept even if that means momentarily exceeding budget until the next `record(_:)`.
    private func trim() {
        var total = undoStack.reduce(0) { $0 + $1.cost } + redoStack.reduce(0) { $0 + $1.cost }
        while total > maxCost, !undoStack.isEmpty {
            total -= undoStack.removeFirst().cost
        }
    }
}
