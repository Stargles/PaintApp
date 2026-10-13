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
/// An instance of the defaults rather than a static that writes through — CLAUDE.md carries the section
/// on a `UserDefaults`-backed static that outlived the test that set it — so the logic tests hand it a
/// suite of their own.
enum CanvasRepairCount {
    /// Also the `@AppStorage` key the Settings menu reads, which is what keeps its row current while the
    /// menu is open.
    static let defaultsKey = "paintapp.canvasFreezesCaught"

    static func current(in defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: defaultsKey)
    }

    /// One more repair, counted. Answers the new total.
    @discardableResult
    static func record(in defaults: UserDefaults = .standard) -> Int {
        let total = current(in: defaults) + 1
        defaults.set(total, forKey: defaultsKey)
        return total
    }

    /// The Settings row's text.
    static func title(_ count: Int) -> String { "Canvas freezes caught: \(count)" }
}
