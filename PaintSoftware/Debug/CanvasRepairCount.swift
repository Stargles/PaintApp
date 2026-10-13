import Foundation

/// **How many times the canvas has found its gesture recognizers stranded and replaced them**
/// (`CanvasView.Coordinator.replaceStrandedRecognizers`) — kept across launches, and for the app as a
/// whole rather than for a scene or a document, because it is a fact about the build the owner is
/// holding and not about anything they drew.
///
/// **Why a counter and not only the flight file.** Each repair saves a flight file, but a file exists
/// only if the recorder is on and the owner sends it back; the count is on the screen of the Settings
/// menu next to "Save Last 90 Seconds" and in every flight's header, so a build's repair rate can be
/// set beside the next build's by reading one number off the iPad before installing and after
/// using it. It is the measure of a fix (BUGS.md, the stranded recognizers): a build that is right
/// stops counting, and it does not depend on the recorder to say so.
///
/// Kept app-wide in `AppSettings` (`canvasRepairCount`, `recordCanvasRepair`); this names its row.
enum CanvasRepairCount {
    /// The Settings row's text.
    static func title(_ count: Int) -> String { "Canvas freezes caught: \(count)" }
}
