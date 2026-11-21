import Foundation
import SwiftUI
import UIKit

/// **Notices that the last run died while the artist was looking at it, and keeps what it saw.**
///
/// The repeated iPad crash is the display server (`backboardd`) being Jetsam-killed, which takes the app
/// down with it and gives the app no callback at all — so the only in-process evidence is an absence: the
/// previous run never said it had left the foreground. Two small files in Application Support carry that:
///
/// - `foreground.marker` — `foreground` from the moment the scene is active, `away` from the moment it
///   goes to the background. A run that ends **while `away`** (iOS reclaiming a suspended app, the artist
///   swiping it out of the switcher) is a normal end and reports nothing; a run found still `foreground`
///   at the next launch died in the artist's hands.
/// - `ring.jsonl` — the flight recorder's last 90 s, rewritten every few seconds while events keep
///   arriving (`ActionRecorder.persistRing`), so a kill loses seconds, not the run.
///
/// On a crash the ring is promoted to `Recordings/crash-<date>-<UUID>.jsonl` — the folder the Settings list
/// already shows with Share and Delete — under a header line saying why it exists.
///
/// **Everything here runs on one serial utility queue, in the order it was asked**, so the launch check
/// always reads the marker before the first `foreground` write replaces it, and no file work is ever on the
/// main thread (docs/SCHEDULER.md).
struct UncleanExitWatch {
    enum Mark: String { case foreground, away }

    /// `Application Support/CrashWatch` — outside `Documents`, which the artist sees in Files.app.
    let directory: URL
    var markerURL: URL { directory.appendingPathComponent("foreground.marker") }
    var ringURL: URL { directory.appendingPathComponent("ring.jsonl") }

    static let standard = UncleanExitWatch(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CrashWatch", isDirectory: true))

    /// The one decision: only a run last seen in the foreground died there. No marker is a first launch.
    static func endedUncleanly(lastMark: Mark?) -> Bool { lastMark == .foreground }

    func lastMark() -> (mark: Mark, at: String)? {
        guard let data = try? Data(contentsOf: markerURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let raw = object["mark"], let mark = Mark(rawValue: raw) else { return nil }
        return (mark, object["at"] ?? "")
    }

    func write(_ mark: Mark, at date: Date = Date()) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let object = ["mark": mark.rawValue, "at": ISO8601DateFormatter().string(from: date)]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        try? data.write(to: markerURL, options: .atomic)
    }

    /// The launch check. Reads the marker, resets it to `away` (so a second launch before the scene is
    /// active cannot report the same death twice), consumes the ring, and — only after an unclean end —
    /// writes the crash recording and returns its URL.
    @discardableResult
    func consumeLaunch(into recordings: URL, now: Date = Date()) -> URL? {
        let last = lastMark()
        let ring = try? Data(contentsOf: ringURL)
        try? FileManager.default.removeItem(at: ringURL)
        write(.away, at: now)
        guard Self.endedUncleanly(lastMark: last?.mark) else { return nil }
        try? FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let url = recordings.appendingPathComponent(ActionRecorder.recordingFilename(prefix: "crash", at: now))
        let header = ActionRecorder.line("header", [
            ("schema", .int(1)),
            ("mode", .str("crash")),
            ("note", .str("The previous run ended while the app was in the foreground: a crash, a force-quit while "
                          + "drawing, or the display server being killed. The lines after this header are its last "
                          + "90 s, from the flight recorder.")),
            ("lastForegroundMark", .str(last?.at ?? "")),
            ("detectedAt", .str(ISO8601DateFormatter().string(from: now))),
            ("ringBytes", .int(ring?.count ?? 0))
        ], at: 0)
        var out = Data((header + "\n").utf8)
        if let ring { out.append(ring) }
        do { try out.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    // MARK: - The serial queue and the app's hooks

    static let queue = DispatchQueue(label: "paintapp.unclean-exit", qos: .utility)

    /// Called once from `PaintApp.init`. Nothing touches disk on the caller; `reported` is called on main
    /// with the promoted file's URL after an unclean end.
    static func checkLaunch(watch: UncleanExitWatch = .standard, recordings: URL = ActionRecorder.directory,
                            reported: @escaping (URL) -> Void) {
        // A simulator run kills the app on purpose all the time (every XCUITest that relaunches), so there
        // it is armed only by `-uiTestCrashWatch`; on the iPad it is always on.
        guard !ProjectBackupManager.isSimulator || ProcessInfo.processInfo.arguments.contains("-uiTestCrashWatch")
        else { return }
        queue.async {
            guard let url = watch.consumeLaunch(into: recordings) else { return }
            DispatchQueue.main.async { reported(url) }
        }
    }

    /// Called from the scene-phase change. Only `.active` and `.background` write: `.inactive` is the
    /// stretch while a system sheet or the switcher is up and says nothing about leaving. The write is
    /// held open with a background task, because leaving the foreground is the moment the process is
    /// about to be suspended.
    static func mark(for phase: ScenePhase) -> Mark? {
        switch phase {
        case .active: return .foreground
        case .background: return .away
        default: return nil
        }
    }

    static func scenePhaseChanged(to phase: ScenePhase, watch: UncleanExitWatch = .standard) {
        guard let mark = mark(for: phase) else { return }
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = app.beginBackgroundTask(withName: "unclean-exit-marker") {
            app.endBackgroundTask(task)
        }
        queue.async {
            watch.write(mark)
            if task != .invalid { DispatchQueue.main.async { app.endBackgroundTask(task) } }
        }
    }
}
