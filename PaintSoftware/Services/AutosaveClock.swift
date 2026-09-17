import Foundation
import Combine

/// When the next autosave is due — TODO (76), the scheduling half, kept pure so it can be tested
/// without a run loop.
///
/// **Two timers folded into one due time.** An edit arms a short fuse (`settle`) that every further
/// edit pushes back, so a burst of strokes costs one save once the pen has rested; the first unsaved
/// edit also starts a long one (`ceiling`) that nothing pushes back, so a session that never rests
/// still saves every half minute. The due time is the earlier of the two.
///
/// **A save never fires into a gesture or a playing scene.** `isHeld` is the caller's word for "the
/// artist is mid-stroke, mid-drag, playing, or resizing, or a save is already in flight"; while it is
/// true `fire(at:)` refuses, and `dueAt` stays where it is so the release lets it through at once.
/// The hold is the caller's to describe, because this type knows nothing about strokes — it knows
/// three timestamps.
///
/// **What counts as an edit is the caller's definition too**, and `ContentView` uses the app's own:
/// every mutating action is registered with the undo history, so `CanvasManager.documentEdited`
/// fires from that funnel and from undo and redo. A pan, a frame change or a slider is not an edit;
/// those ride on whichever save comes next.
struct AutosaveClock: Equatable {
    /// How long after the last edit a save fires, if nothing else happens.
    var settle: TimeInterval = 2.5
    /// How long after the first unsaved edit a save fires regardless.
    var ceiling: TimeInterval = 30

    private var firstUnsavedEdit: TimeInterval?
    private var lastEdit: TimeInterval?

    init(settle: TimeInterval = 2.5, ceiling: TimeInterval = 30) {
        self.settle = settle
        self.ceiling = ceiling
    }

    /// Whether anything has changed since the last save this clock was told about.
    var hasUnsavedEdits: Bool { firstUnsavedEdit != nil }

    /// When the next save is due, or nil with nothing to save.
    var dueAt: TimeInterval? {
        guard let first = firstUnsavedEdit, let last = lastEdit else { return nil }
        return min(last + settle, first + ceiling)
    }

    mutating func noteEdit(at now: TimeInterval) {
        if firstUnsavedEdit == nil { firstUnsavedEdit = now }
        lastEdit = now
    }

    /// Answers whether a save should start now, and if so forgets the edits it will carry. `held`
    /// is the caller's "not now": the due time is kept, so the next call after the hold lifts fires.
    ///
    /// **The edits are forgotten before the save has landed, on purpose.** Whatever is edited
    /// between this call and the landing is a new edit, noted afresh, and carried by the next save —
    /// which is exactly the guarantee "an edit during a save is not lost" needs, and it needs
    /// nothing from the save's completion to hold.
    mutating func fire(at now: TimeInterval, held: Bool) -> Bool {
        guard !held, let due = dueAt, now >= due else { return false }
        firstUnsavedEdit = nil
        lastEdit = nil
        return true
    }

    /// A save that happened for another reason — the artist leaving, the app backgrounding — carries
    /// everything, so nothing is owed.
    mutating func noteSaved() {
        firstUnsavedEdit = nil
        lastEdit = nil
    }
}

/// Runs an `AutosaveClock` against a document: subscribes to its edits, keeps one timer pointed at
/// the clock's due time, and calls `save` when the clock says so and `isHeld` says nothing is in the
/// way. `ContentView` owns one and hands it the manager in the editor.
///
/// **One timer, re-armed from the due time, never a poll.** Each edit moves the due time and re-arms;
/// a timer that fires into a hold re-arms for a second later, which is the only repeat in here and
/// only while something is held. `savesInFlight` is counted here rather than in the view because
/// every kind of save — the artist's exit, the scene phase, this one — reports through the same
/// two calls, and the count is part of the hold.
@MainActor
final class AutosaveDriver: ObservableObject {
    private(set) var clock = AutosaveClock()
    private(set) var savesInFlight = 0
    private var timer: Timer?
    private var edits: AnyCancellable?
    private var isHeld: () -> Bool = { true }
    private var save: () -> Void = {}

    /// Starts following `manager`'s edits. Replacing a previous document drops its subscription and
    /// forgets its edits — they belong to a manager that is no longer on screen and whose exit save
    /// already carried them.
    func follow(_ manager: CanvasManager, isHeld: @escaping () -> Bool, save: @escaping () -> Void) {
        stop()
        self.isHeld = isHeld
        self.save = save
        edits = manager.documentEdited.sink { [weak self] in self?.noteEdit() }
    }

    func stop() {
        edits = nil
        timer?.invalidate()
        timer = nil
        clock.noteSaved()
    }

    private func noteEdit() {
        clock.noteEdit(at: Date.timeIntervalSinceReferenceDate)
        arm()
    }

    /// Points the timer at the clock's due time; a due time already past under a hold is looked at
    /// again in a second, and one already past with no hold fires now.
    func arm() {
        timer?.invalidate()
        timer = nil
        guard let due = clock.dueAt else { return }
        let delay = max(due - Date.timeIntervalSinceReferenceDate, isHeld() ? 1 : 0)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
    }

    private func fire() {
        guard clock.fire(at: Date.timeIntervalSinceReferenceDate, held: isHeld()) else {
            arm()
            return
        }
        save()
    }

    /// A save of any kind is starting: it carries every edit noted so far, and holds the next until
    /// it lands.
    func saveStarted() {
        clock.noteSaved()
        savesInFlight += 1
    }

    func saveFinished() {
        savesInFlight -= 1
        arm()
    }
}
