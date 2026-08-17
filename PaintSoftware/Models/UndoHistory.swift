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
        let label: HistoryActionLabel
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

    /// Reverts the most recent action and returns its label, or nil (and does nothing) if the
    /// stack is empty — the caller's signal for whether to raise an "Undid …" notice at all.
    @discardableResult
    func undo() -> HistoryActionLabel? {
        guard let action = undoStack.popLast() else { return nil }
        action.undo()
        redoStack.append(action)
        return action.label
    }

    /// Reapplies the most recently undone action and returns its label, or nil (and does nothing)
    /// if there is nothing to redo.
    @discardableResult
    func redo() -> HistoryActionLabel? {
        guard let action = redoStack.popLast() else { return nil }
        action.redo()
        undoStack.append(action)
        return action.label
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
