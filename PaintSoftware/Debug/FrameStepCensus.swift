import Foundation
import QuartzCore

/// **What the last frame step cost the artist, in milliseconds from the tap** — SCHEDULER_DESIGN.md
/// §9's M1 and S1's gate number, published on `canvas.host` as
/// `step:<frame>,<decodeMs>,<shownMs>,<mainDecodes>`:
///
/// - `frame` — the frame the last step went to (0-based);
/// - `decodeMs` — the first baked-frame decode that began after the step, or `-` for none (a ring hit);
/// - `shownMs` — when a whole picture of that frame was put on screen, or `-` while it is not;
/// - `mainDecodes` — baked-frame decodes the main thread has run since launch. Rule 2 says 0.
///
/// A probe read off the app's own clock, so a test needs no screenshot to time a step — screenshots
/// are what it uses to say the picture was never a mix.
enum FrameStepCensus {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var frame: Int?
    nonisolated(unsafe) private static var steppedAt: CFTimeInterval = 0
    nonisolated(unsafe) private static var decodeAt: CFTimeInterval?
    nonisolated(unsafe) private static var shownAt: CFTimeInterval?
    nonisolated(unsafe) private static var mainDecodes = 0

    /// The playhead was stepped to `frame`. Main thread.
    static func stepped(to frame: Int) {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        self.frame = frame
        steppedAt = now
        decodeAt = nil
        shownAt = nil
    }

    /// A baked frame's decode began, on whichever thread runs it.
    static func decodeStarted(onMain: Bool) {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        if onMain { mainDecodes += 1 }
        if frame != nil, decodeAt == nil { decodeAt = now }
    }

    /// A whole picture of `frame` reached the screen. Main thread.
    static func shown(frame shownFrame: Int) {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        guard shownFrame == frame, shownAt == nil else { return }
        shownAt = now
    }

    /// The `step:` field.
    static var field: String {
        lock.lock(); defer { lock.unlock() }
        func ms(_ time: CFTimeInterval?) -> String {
            time.map { String(Int((($0 - steppedAt) * 1000).rounded())) } ?? "-"
        }
        return "\(frame.map(String.init) ?? "-"),\(ms(decodeAt)),\(ms(shownAt)),\(mainDecodes)"
    }
}
