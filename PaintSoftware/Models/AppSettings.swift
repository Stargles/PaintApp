import Combine
import Foundation
import os

/// **What the app keeps for itself rather than for any one scene** — TODO (176)'s one global store.
///
/// The owner ruled every option onto one of three levels. A scene's own tools and view are saved in its
/// manifest (`EditorStateManifest`); what resets each launch is plain model state with no persistence
/// code at all; and what is about the device, the app or the artist's whole library — the finger/Pencil
/// gate, the render knob, where the projects folder is, the gallery folder they were in, the last laptop
/// streamed from, the palettes library — is here. **This is the only reader and writer of `UserDefaults`
/// in the app.** The brush library is the one other app-wide store, and it is a file of its own
/// (`BrushLibraryStore`), because it is data the artist made rather than a setting.
///
/// ## How a value is kept
///
/// **One key per value**, so a value added by a later build never makes the ones already saved
/// unreadable, and an absent key is simply that value's default. Every key is in `Key`; the strings are
/// the ones each value was already saved under, so nothing an existing install holds has to move.
///
/// **A stored value this build cannot read is never read as the default and never written over.**
/// Everything here is a plist scalar the app itself wrote, which cannot fail to read, except the render
/// knob, whose unknown value — one a newer build added — shows as Full and stays stored until the artist
/// picks another.
///
/// **An instance over a `UserDefaults`, not a static that writes through.** CLAUDE.md carries the section
/// on a `UserDefaults`-backed static that outlived the test that set it; logic tests hand this a suite of
/// their own, and the model never touches it — `AppSettingsKeeper` carries the two values that live on a
/// `CanvasManager` between the two.
nonisolated struct AppSettings: @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The app's own settings.
    static let standard = AppSettings()

    /// Every key this store owns.
    enum Key {
        static let pencilOnlyDrawing = "paintapp.pencilOnlyDrawing"
        static let renderResolution = "paintapp.renderResolution"
        static let lastStreamHost = "streamScreen.lastHost"
        static let lastStreamPort = "streamScreen.lastPort"
        static let projectsFolderBookmark = "PaintApp.projectLocation.bookmark"
        static let projectsFolderName = "PaintApp.projectLocation.displayName"
        static let storageInvitationDismissed = "PaintApp.gallery.storageInvitationDismissed"
        static let galleryFolder = "paintapp.galleryFolder"
        static let canvasRepairCount = "paintapp.canvasFreezesCaught"
        static let lastAppSignature = "PaintApp.projectBackup.lastAppSignature"
    }

    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "AppSettings")

    // MARK: - The device and the app

    /// **Fingers Can Paint**, inverted: whether only the Apple Pencil draws. About the artist's
    /// hardware, not any one drawing. Off until chosen — an on-by-default gate would silently swallow
    /// every finger touch on a device with no Pencil, reading as "drawing is broken".
    var pencilOnlyDrawing: Bool {
        get { defaults.bool(forKey: Key.pencilOnlyDrawing) }
        nonmutating set { defaults.set(newValue, forKey: Key.pencilOnlyDrawing) }
    }

    /// **Render Resolution** — about the machine and the artist's tolerance for a soft preview, so a
    /// document carried to a faster iPad does not bring a downgraded canvas with it. Full until chosen:
    /// a reduced default would leave an artist who never opens the menu concluding the app renders
    /// softly, with nothing on screen to say a control exists.
    var renderResolution: RenderResolution {
        get {
            guard let stored = defaults.string(forKey: Key.renderResolution) else { return .full }
            guard let resolution = RenderResolution(rawValue: stored) else {
                Self.log.fault("Render Resolution \(stored, privacy: .public) is not one this build knows; showing Full and leaving it stored")
                return .full
            }
            return resolution
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.renderResolution) }
    }

    /// **How many times the canvas has found its gesture recognizers stranded and replaced them** —
    /// `CanvasRepairCount`, a fact about the build the owner is holding and not about anything drawn.
    var canvasRepairCount: Int {
        defaults.integer(forKey: Key.canvasRepairCount)
    }

    /// One more repair, counted. Answers the new total.
    @discardableResult
    func recordCanvasRepair() -> Int {
        let total = canvasRepairCount + 1
        defaults.set(total, forKey: Key.canvasRepairCount)
        return total
    }

    /// The app signature (version + build + binary date) seen at the previous launch — bookkeeping
    /// for `ProjectBackupManager`'s update snapshot, not an option.
    var lastAppSignature: String? {
        get { defaults.string(forKey: Key.lastAppSignature) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastAppSignature) }
    }

    // MARK: - The library

    /// The security-scoped bookmark for the projects folder the artist chose in Files, and the folder's
    /// name kept beside it — `ProjectLocation`'s, which says why the name cannot be derived from it.
    var projectsFolderBookmark: Data? {
        get { defaults.data(forKey: Key.projectsFolderBookmark) }
        nonmutating set { defaults.set(newValue, forKey: Key.projectsFolderBookmark) }
    }

    var projectsFolderName: String? {
        get { defaults.string(forKey: Key.projectsFolderName) }
        nonmutating set { defaults.set(newValue, forKey: Key.projectsFolderName) }
    }

    /// The gallery's "your work is inside the app" warning has been answered.
    var storageInvitationDismissed: Bool {
        get { defaults.bool(forKey: Key.storageInvitationDismissed) }
        nonmutating set { defaults.set(newValue, forKey: Key.storageInvitationDismissed) }
    }

    /// **The gallery folder the artist was in**, as folder names below `Projects/` — `[]` is the top of
    /// the tree. Names rather than a URL so a library moved to another root re-roots instead of pointing
    /// at a stale path; the gallery walks back to the nearest folder still there.
    var galleryFolder: [String] {
        get { defaults.stringArray(forKey: Key.galleryFolder) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.galleryFolder) }
    }

    /// **The last laptop streamed from** — the Connect sheet's prefill, and the document-level
    /// connection's endpoint (STREAM.md §6). Each stream keeps its own host and port in the document;
    /// this is only which one was used last.
    var lastStreamEndpoint: StreamEndpoint? {
        get {
            guard let host = defaults.string(forKey: Key.lastStreamHost), !host.isEmpty else { return nil }
            let port = defaults.integer(forKey: Key.lastStreamPort)
            guard port > 0, port <= 65535 else { return nil }
            return StreamEndpoint(host: host, port: UInt16(port))
        }
        nonmutating set {
            defaults.set(newValue?.host, forKey: Key.lastStreamHost)
            defaults.set(newValue.map { Int($0.port) }, forKey: Key.lastStreamPort)
        }
    }

    // MARK: - Launch-argument test hooks

    /// The UI tests' "launch as if this were the first time": `-resetEditorPreferences` (which
    /// `PaintUITestCase.launchIntoEditor` passes on every launch) and `-resetGallery` forget the
    /// artist's app-wide preferences. The projects folder and the
    /// update signature are `-resetGallery`'s alone, forgotten by `ProjectBackupManager` beside the
    /// library it wipes and only in a simulator. Synchronous, in `PaintApp.init`, because the first
    /// document reads these as it opens.
    func forgetIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-resetEditorPreferences") || arguments.contains("-resetGallery") {
            for key in [Key.pencilOnlyDrawing, Key.renderResolution, Key.lastStreamHost, Key.lastStreamPort,
                        Key.galleryFolder, Key.canvasRepairCount] {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// `-resetGallery`'s half: the library is going back inside the app, so the folder it pointed at
    /// and the answered warning go with it.
    func forgetLibraryLocation() {
        for key in [Key.projectsFolderBookmark, Key.projectsFolderName, Key.storageInvitationDismissed] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// **Carries the two app-wide values that live on a `CanvasManager`** — Fingers Can Paint and Render
/// Resolution — between it and `AppSettings`: hands them to each document as it enters the editor and
/// saves every change the artist makes to them, as it is made. `ContentView` holds one.
///
/// The model itself touches no store, so a logic test that flips one leaves nothing behind for the next
/// `CanvasManager()` to find.
final class AppSettingsKeeper {
    private let settings: AppSettings
    private var changes: Set<AnyCancellable> = []

    init(settings: AppSettings = .standard) {
        self.settings = settings
    }

    /// Puts the saved values on `manager` and saves each change to them from here on, letting go of the
    /// previous document's.
    func follow(_ manager: CanvasManager) {
        changes.removeAll()
        manager.pencilOnlyDrawing = settings.pencilOnlyDrawing
        manager.renderResolution = settings.renderResolution
        let settings = self.settings
        manager.$pencilOnlyDrawing.dropFirst().removeDuplicates()
            .sink { settings.pencilOnlyDrawing = $0 }
            .store(in: &changes)
        manager.$renderResolution.dropFirst().removeDuplicates()
            .sink { settings.renderResolution = $0 }
            .store(in: &changes)
    }
}
