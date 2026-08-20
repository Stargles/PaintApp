import Foundation

/// Which project the gallery is opening, and what a tap is allowed to start while it is.
///
/// **Opening a project was the longest main-thread stall in the app and had never had a spinner.**
/// `ProjectStore.load` was `@MainActor` and fully serial: per cel a PNG decode, then a full
/// canvas-sized `CGContext` allocation and draw, then `regenerateAllThumbnails()` walking the lot
/// again guaranteed cache-cold. The cost is driven by cel count, so it does not shrink at the owner's
/// 2048×1024 the way an area-scaled cost does, and it is the first thing that happens every session.
/// `GalleryView.open` called it straight out of a tap handler — no `Task`, no loading state, nothing
/// on screen — so the app went dead and the honest reading of that is "it crashed".
///
/// **The wait is now much shorter and this type still earns its keep.** PERFORMANCE.md item 9 moved
/// the decode off the main thread and deferred the thumbnails
/// (`ProjectStore.loadInBackground`), so the gallery path is a fraction of what it was — but it is not
/// zero, the spinner is still what the artist sees while it runs, and the two rules below are about
/// what a *tap* is allowed to start rather than about how long the work takes.
///
/// This type is the small part of that fix worth isolating: not the spinner, which is a view, but the
/// **two rules a spinner creates**, both of which are silent when wrong.
///
/// 1. *One load at a time.* A frozen app invites a second tap, and two loads means two
///    `CanvasManager`s built at once, competing for the same cores, with whichever finishes last
///    winning — a lottery between two projects rather than a slow open of one.
/// 2. *Every load ends.* `load` returns nil for a package that fails manifest decode, and the gallery
///    stays put. If `finish` were reached only on success, a damaged project would leave the gallery
///    behind a spinner it can never dismiss, having reported a hang for a file that was merely
///    broken. So `finish` is unconditional at the call site and this type has no "succeeded" path at
///    all — there is nothing to forget.
///
/// A value type with no view in it, so both rules are headless assertions rather than a UI test.
struct GalleryOpenState: Equatable {

    /// The project being opened, or nil when the gallery is idle.
    private(set) var openingProjectID: UUID?

    /// Whether the gallery is busy, and therefore whether the grid should refuse further taps.
    var isBusy: Bool { openingProjectID != nil }

    /// Whether *this* tile should show its spinner. Per-project rather than a bare `isBusy` because
    /// the artist tapped a particular tile and the feedback should be on the thing they touched;
    /// a spinner floating over the grid says the app is busy without saying at what.
    func isOpening(_ projectID: UUID) -> Bool { openingProjectID == projectID }

    /// Claims the gallery for `projectID`, or returns false if a load is already running.
    ///
    /// Returns a `Bool` rather than being callable-and-ignorable so the caller cannot start work this
    /// type just refused; `@discardableResult` is deliberately absent for the same reason.
    mutating func begin(_ projectID: UUID) -> Bool {
        guard openingProjectID == nil else { return false }
        openingProjectID = projectID
        return true
    }

    /// Releases the gallery. Idempotent, and says nothing about whether the load succeeded — see
    /// rule 2 above.
    mutating func finish() {
        openingProjectID = nil
    }
}
