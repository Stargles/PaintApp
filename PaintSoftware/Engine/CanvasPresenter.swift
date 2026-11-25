/// **What the canvas shows changes whole, or not at all** — SCHEDULER.md rule 10, and the half of
/// SCHEDULER_DESIGN.md §2.1 that S1 builds.
///
/// The canvas is drawn by one whole picture (the baked frame, `BakedFrameWindow`) or by the layers'
/// own pictures (the hosts), and each part draws its window off the main thread into a back surface
/// of its own (`WindowSurfaceView`). Left alone each part swaps the moment its draw is done, so a frame
/// step reached the screen a layer at a time — five independent landings on the owner's scene, which
/// is the stagger he reported. While this presenter **holds**, a part's finished draw is *parked*
/// here instead of swapped, and the set goes up in one call — every parked swap, and whatever the
/// caller does alongside (taking the whole picture down) — once the caller says it is complete. Until
/// then the last complete picture stays (owner Q1, 2026-11-25).
///
/// The rule of completeness is `isComplete`'s: every part is either already showing what it should
/// or has parked the picture it should show *now* — a part parks with `isCurrent`, its own "is this
/// still the picture I was asked for", so a picture parked for the frame a burst of steps has already
/// left can never complete a set for the frame it is on. The caller names the parts; it does not
/// decide what to swap.
///
/// Platform-free: parts are any objects, swaps are closures. `CanvasView.Coordinator` wraps
/// `present` in one Core Animation transaction.
@MainActor
final class CanvasPresenter {

    /// Whether a part's new picture waits for the set.
    private(set) var isHolding = false
    private var parked: [ObjectIdentifier: (isCurrent: () -> Bool, swap: () -> Void, drop: () -> Void)] = [:]
    /// Called after a part parks, so the caller can ask whether the set is complete.
    var onPark: (() -> Void)?
    /// How many sets have gone up — `presented:` on `canvas.host`.
    private(set) var setsPresented = 0

    /// From now, every part's new picture waits for the set.
    func hold() { isHolding = true }

    /// Parks `part`'s finished draw. A part parked again drops its older picture: only the newest of a
    /// part ever goes up. Only while holding — a part not held swaps on its own.
    func park(_ part: AnyObject, isCurrent: @escaping () -> Bool, swap: @escaping () -> Void,
              drop: @escaping () -> Void) {
        guard isHolding else { return swap() }
        parked.removeValue(forKey: ObjectIdentifier(part))?.drop()
        parked[ObjectIdentifier(part)] = (isCurrent, swap, drop)
        onPark?()
    }

    /// Whether `part` has parked the picture it should show now.
    func hasCurrentPicture(_ part: AnyObject) -> Bool { parked[ObjectIdentifier(part)]?.isCurrent() == true }

    /// Whether every part shows what it should, or has parked the picture it should show now.
    func isComplete<Part: AnyObject>(_ parts: [Part], showing: (Part) -> Bool) -> Bool {
        parts.allSatisfy { hasCurrentPicture($0) || showing($0) }
    }

    /// **The set goes up**: `alongside`, then every parked picture that is still current, in this one
    /// call, and the hold ends; a parked picture no longer wanted is dropped, never shown. The caller
    /// makes the call one transaction.
    func present(alongside: () -> Void = {}) {
        isHolding = false
        let parts = parked.values
        parked = [:]
        alongside()
        for part in parts { part.isCurrent() ? part.swap() : part.drop() }
        setsPresented += 1
    }
}
