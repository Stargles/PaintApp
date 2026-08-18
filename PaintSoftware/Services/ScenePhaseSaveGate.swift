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
}
