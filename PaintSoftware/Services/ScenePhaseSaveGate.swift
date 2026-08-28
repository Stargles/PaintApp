import SwiftUI

/// Which `scenePhase` changes are worth a save.
///
/// SwiftUI reports a phase, not a direction, and `.inactive` is on **both** legs of an app switch:
/// `active → inactive → background` leaving, `background → inactive → active` coming back. The
/// original guard looked only at the new phase (`newPhase == .inactive || newPhase == .background`),
/// so a single round trip out to another app and back fired three saves — and one of the three
/// landed on the return leg, with the artist watching the screen. That is the freeze the owner
/// reported as "returning from another app freezes for a few seconds" and shrugged off as expected.
/// It is not expected: `ProjectStore.save` composites the whole canvas on the main actor before it
/// hands anything to a background queue, so those saves are main-thread stalls, and two of the three
/// were writing a document nothing had touched since the first one.
///
/// The rule is a direction rather than a destination: **save when leaving `.active`, never when
/// returning to it.** Only an active scene can have been drawn on, so a save on the way out is the
/// one that carries new work; every phase change that follows it until the scene is active again is
/// a change to a document that provably has not moved.
///
/// It is phrased as "was active, is no longer" rather than an allow-list of the two departures we
/// know about, because the failure modes are not symmetric. Missing a save loses the artist's work;
/// an extra save costs a stall. Should SwiftUI ever add a fourth phase, `active → newPhase` reads as
/// a departure and saves, which is the direction to be wrong in.
enum ScenePhaseSaveGate {

    /// Whether the transition `oldPhase → newPhase` should write the project to disk.
    ///
    /// Both arguments come straight from `onChange(of:)`'s two-value closure, so there is no
    /// "first change with no prior phase" to handle — SwiftUI delivers the initial phase as state,
    /// not as a change, and a scene that launches directly into `.background` therefore produces no
    /// call at all. Nothing is lost by that: a scene that was never active was never drawn on, and
    /// `ContentView.saveIfNeeded` refuses to save from anywhere but the editor regardless.
    static func shouldSave(from oldPhase: ScenePhase, to newPhase: ScenePhase) -> Bool {
        oldPhase == .active && newPhase != .active
    }

    /// Whether a save may **start** at all, whoever asked for it — the second gate, and the one that
    /// is not about the scene phase.
    ///
    /// `shouldSave` above answers "is this transition worth a save"; this answers "is the document in
    /// a state that can be written". Every caller of `ContentView.saveIfNeeded` passes through it,
    /// not only the phase change, because the third condition is about the document rather than
    /// about what asked.
    ///
    /// **`isResizing` is CANVAS_RESIZE.md §5 rule 12, and the owner's 2026-08-28 ruling makes it more
    /// necessary rather than less.** A canvas resize rewrites every cel's buffers and then
    /// `canvasSize`; a save that lands between those two is a package whose manifest header and whose
    /// PNGs disagree — and `ProjectStore.decodeCel` builds every texture at the manifest's size and
    /// `RasterLayerTexture.setContents` stretches a mismatched PNG to fit, aspect and all, so that
    /// document does not fail to open. It opens, silently non-uniformly stretched, which is the worst
    /// class of bug this codebase can ship. The window is real but narrow: the mutation walk is one
    /// synchronous main-actor turn and no `scenePhase` change can be delivered during it, so what
    /// this gate actually covers is the *announced* path's `Task.yield()` — the one turn the run loop
    /// gets, deliberately, so the busy overlay can be drawn.
    ///
    /// Refusing rather than deferring: a resize is at most seconds, `completion` still runs so
    /// nothing is left hanging, and the artist's next stroke or next backgrounding saves the finished
    /// document. Losing a save is a stall; writing a half-resized package is a corrupted drawing.
    static func mayStartSave(screenIsEditor: Bool, hasCanvas: Bool, isResizing: Bool) -> Bool {
        screenIsEditor && hasCanvas && !isResizing
    }
}
