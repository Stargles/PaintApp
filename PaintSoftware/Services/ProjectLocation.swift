import Foundation

extension Notification.Name {
    /// Posted on the main thread whenever `ProjectLocation.status` changes — the folder was adopted,
    /// reverted, or failed to re-resolve at launch. The gallery re-lists and re-draws its banner.
    static let projectLocationDidChange = Notification.Name("PaintApp.ProjectLocationDidChange")
}

/// **Where the artist's projects live, which is deliberately not "inside this app"** — TODO (36).
///
/// The owner, 2026-09-07: *"Every time a test build gets uploaded to Ipad currently, everything is
/// wiped."* That is not a bug in the deploy script; it is what an app container **is**. Everything
/// under `Documents/` belongs to the installed app, and a reinstall is entitled to replace it — which
/// is exactly what happened on 2026-09-07, when a measurement pass wiped the container and destroyed
/// the owner's `AnimationTest` document with no recovery. A folder the artist picks in Files sits
/// **outside** the container, in a volume the installer never touches, and that is the whole feature.
///
/// ## Why this is not `BrushStorage`'s seam
///
/// `BrushStorage` reserved room for this and priced it at *"five one-line brackets"* — one
/// `startAccessingSecurityScopedResource` around each of its five accesses. **That estimate does not
/// generalise to projects, and copying it here would be a bug.** `ProjectStore` and
/// `ProjectBackupManager` between them touch the filesystem in ~60 places (every cel PNG, the staged
/// package, each backup slot, the trash, the size walk), several of them on background queues and
/// several *concurrently* — `loadInBackground` fans the per-cel decode across cores. Security-scoped
/// access is refcounted per URL but the balance has to be exact, and a bracket that leaks on one of
/// sixty error paths revokes access for the whole app at an unpredictable moment.
///
/// So the shape here is a **process-lifetime hold**: resolve the bookmark once at launch, call
/// `startAccessingSecurityScopedResource()` once, and never stop until the folder is swapped for
/// another one. That is the pattern Apple documents for an app that adopts a folder as its library
/// rather than opening a document, and it makes every one of those sixty accesses an ordinary
/// `FileManager` call with no new failure mode.
///
/// ## A failure to re-resolve is a sentence, never a fallback
///
/// The dangerous version of this feature is the quiet one: the chosen folder is on an external drive
/// that is unplugged, the resolve fails, the app falls back to its container, and the artist saves a
/// day's work into the exact place this feature exists to get out of. **So the fallback happens (the
/// app must still open) and it is loud** — `status` stays `.unavailable`, carrying the folder's name
/// and a plain-English reason, and the gallery draws a banner off it that cannot be dismissed while
/// the condition holds. `resolveOnLaunch()` returns that status rather than a `Bool` nobody reads;
/// this repo has a filed bug that is precisely a discarded `Bool` (`beginContainerPoseMove`).
///
/// ## Test seams
///
/// `defaults` and `appFolderOverride` exist because a bookmark is process-and-device state: a logic
/// test that wrote `UserDefaults.standard` would leak into the next run in the simulator container,
/// which CLAUDE.md records costing 15 reds when `CanvasManager.renderResolution` did it. Both are
/// restored in `tearDown` by the suites that set them.
///
/// Pure Foundation, no UIKit: this file is compiled into the UI-test bundle the same way
/// `ProjectBackupManager` is.
nonisolated enum ProjectLocation {

    // MARK: - Test seams

    /// Which defaults the bookmark is persisted in. Logic tests point this at a per-test suite.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    /// What "the app's own folder" means. Logic tests point this at a temp directory so they never
    /// touch the real container.
    nonisolated(unsafe) static var appFolderOverride: URL?

    // MARK: - Persisted keys

    /// The security-scoped bookmark for the chosen folder. Internal so tests can clear it.
    static let bookmarkDefaultsKey = "PaintApp.projectLocation.bookmark"
    /// The gallery's "your work is inside the app" warning has been answered. Lives here rather than
    /// on `GalleryView` so `-resetGallery` can clear it: that flag is compiled into the test bundle,
    /// which has no app views in it.
    static let invitationDismissedDefaultsKey = "PaintApp.gallery.storageInvitationDismissed"
    /// The folder's display name, kept **beside** the bookmark rather than derived from it, because
    /// the failure this has to describe is exactly the one where the URL cannot be produced. Without
    /// it the banner would have to say "a folder" instead of naming the one the artist chose.
    static let displayNameDefaultsKey = "PaintApp.projectLocation.displayName"

    // MARK: - Status

    enum Status: Equatable {
        /// No folder chosen — projects live in the app's own container, where a reinstall can take
        /// them. This is the default, and the gallery says so.
        case appFolder
        /// A folder the artist chose, resolved and accessible.
        case chosen(URL)
        /// A folder the artist chose that could not be reached this launch. Carries what to tell
        /// them. Projects are being read and written from the app folder meanwhile.
        case unavailable(name: String, reason: String)

        /// The one sentence the artist sees. Nil when there is nothing wrong.
        var problem: String? {
            guard case let .unavailable(name, reason) = self else { return nil }
            return "Can’t reach “\(name)”, the folder your projects are saved in — \(reason) "
                 + "Nothing has been lost: your projects are still in that folder. "
                 + "Until it comes back, new work is being saved inside the app, where reinstalling "
                 + "the app would erase it."
        }

        /// What the settings row reads when nothing is wrong.
        var displayName: String {
            switch self {
            case .appFolder: return "Inside the app"
            case .chosen(let url): return url.lastPathComponent
            case .unavailable(let name, _): return name
            }
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var _status: Status = .appFolder
    /// The URL whose security scope this process is holding open, so `stopAccessing` is called on
    /// exactly the URL that `startAccessing` succeeded on. Nil when nothing is held.
    private nonisolated(unsafe) static var _heldScope: URL?

    static var status: Status {
        lock.lock(); defer { lock.unlock() }
        return _status
    }

    /// The app's own container folder. Not the same thing as `currentRoot` — that is the point.
    static var appFolder: URL {
        appFolderOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// **The directory `Projects/`, `Backups/` and `Trash/` hang off**, and the single value this
    /// whole type exists to produce. `ProjectBackupManager.documentsDirectory` reads it.
    ///
    /// An unavailable folder answers `appFolder`, which is the loud fallback described above: the app
    /// keeps working, and `status.problem` is non-nil for as long as it lasts.
    static var currentRoot: URL {
        lock.lock()
        let status = _status
        lock.unlock()
        if case .chosen(let url) = status { return url }
        return appFolder
    }

    /// Whether a folder is configured at all, however it is currently faring. Distinguishes "the
    /// artist never picked one" from "the one they picked is off the network right now", which the
    /// settings screen has to say differently.
    static var hasChosenFolder: Bool {
        defaults.data(forKey: bookmarkDefaultsKey) != nil
    }

    // MARK: - Launch

    /// Resolves the stored bookmark and takes the process-lifetime access hold.
    ///
    /// Returns the resulting status rather than a `Bool`, so a caller cannot discard the interesting
    /// half. Idempotent: calling it twice releases the first hold before taking the second.
    @discardableResult
    static func resolveOnLaunch() -> Status {
        let resolved = resolveStoredBookmark()
        setStatus(resolved)
        return resolved
    }

    /// The resolve, with no side effects on `_status` — factored out so `adopt` can re-use it and so
    /// a test can ask what a given defaults state resolves to.
    private static func resolveStoredBookmark() -> Status {
        guard let data = defaults.data(forKey: bookmarkDefaultsKey) else { return .appFolder }
        let name = defaults.string(forKey: displayNameDefaultsKey) ?? "your projects folder"

        var isStale = false
        let url: URL
        do {
            // `.withSecurityScope` is a macOS option; on iOS a bookmark minted from a URL the
            // document picker vended resolves back security-scoped with no options at all.
            url = try URL(resolvingBookmarkData: data, options: [],
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            return .unavailable(name: name,
                                reason: "the system could not find it. It may have been renamed, "
                                      + "moved, or deleted.")
        }

        // **`startAccessingSecurityScopedResource()` returning false is not by itself a refusal**,
        // and reading it as one would be a bug. It answers false for any URL that is not
        // security-scoped in the first place — a folder inside the app's own container, a path a
        // test hands over — and those are perfectly writable. What the app actually needs to know is
        // whether it can read and write there, so that is what gets asked, and the scope call's
        // answer only shapes *which* sentence a failure gets.
        let scoped = url.startAccessingSecurityScopedResource()

        // A folder on an unplugged drive, or an iCloud folder whose contents have not come down yet,
        // resolves — and is then not there. A folder whose permission has lapsed is there and will
        // not take a write. Probing both is what turns a stream of silent save failures into one
        // sentence, and the probe is a single file created and removed.
        guard (try? url.checkResourceIsReachable()) == true, canWrite(into: url) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return .unavailable(name: name, reason: scoped
                ? "it isn’t there right now. If it is on a drive or a server, reconnect it; if it "
                + "is in iCloud Drive, it may still be downloading."
                : "this app no longer has permission to open it. Choose it again to restore access.")
        }

        if scoped { hold(url) }
        if isStale { persistBookmark(for: url, name: url.lastPathComponent) }
        return .chosen(url)
    }

    /// Whether a file can be created in `url` right now. One write and one delete — cheaper than
    /// `isWritableFile`, which answers from the permission bits and says yes about a folder on a
    /// volume that has gone read-only.
    private static func canWrite(into url: URL) -> Bool {
        let probe = url.appendingPathComponent(".paintapp-access-probe-\(UUID().uuidString)")
        guard (try? Data().write(to: probe)) != nil else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    // MARK: - Choosing

    /// What `adopt` did, so the caller can tell the artist rather than guessing.
    struct AdoptionResult {
        let status: Status
        let migration: ProjectLibraryMigration.Report
    }

    /// **Points the library at `folder`, moving what is already saved into it.**
    ///
    /// `folder` must be a URL the document picker vended (it arrives security-scoped and the caller
    /// has already started accessing it) or, in a test, an ordinary writable directory.
    ///
    /// The migration is the delicate half and it is `ProjectLibraryMigration`'s to argue for; what
    /// matters here is the **order**. The bookmark is persisted only *after* the copy has verified,
    /// so a crash mid-migration leaves the app still pointing at the old root, with every project
    /// intact there — the state it started in. Adopting first and copying second would leave a
    /// half-filled new root as the live one, which is the outcome CLAUDE.md's brief calls "worse than
    /// either end state".
    @discardableResult
    static func adopt(_ folder: URL) throws -> AdoptionResult {
        let source = currentRoot
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // **Minted before the migration, written after it**, and the two halves are separated for
        // different reasons. Minting first is a precondition check: a folder whose bookmark cannot be
        // made is one the app will not find again next launch, and discovering that *after* moving
        // the library would leave every project in a folder the app no longer points at — an empty
        // gallery with the work sitting somewhere the artist was not told about. Writing it after is
        // what makes an interrupted migration resumable: until it lands, the app still points at the
        // old root, so choosing the same folder again picks up where it stopped (see
        // `ProjectLibraryMigration`'s `alreadyThere` path).
        let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil,
                                               relativeTo: nil)

        let report: ProjectLibraryMigration.Report
        if folder.standardizedFileURL == source.standardizedFileURL {
            report = .empty
        } else {
            report = ProjectLibraryMigration.migrate(from: source, to: folder)
        }

        defaults.set(bookmark, forKey: bookmarkDefaultsKey)
        defaults.set(folder.lastPathComponent, forKey: displayNameDefaultsKey)
        // Re-resolve rather than trusting the URL in hand: this is the same code path the next launch
        // will take, so a bookmark that cannot round-trip is discovered now, while the artist is
        // looking at the picker, instead of silently at the launch after next.
        let status = resolveStoredBookmark()
        setStatus(status)
        return AdoptionResult(status: status, migration: report)
    }

    /// Puts the library back inside the app, migrating the chosen folder's contents home so the
    /// gallery is not suddenly empty. The chosen folder keeps nothing — same copy-verify-remove.
    @discardableResult
    static func revertToAppFolder() -> ProjectLibraryMigration.Report {
        let source = currentRoot
        let destination = appFolder
        let report = source.standardizedFileURL == destination.standardizedFileURL
            ? .empty
            : ProjectLibraryMigration.migrate(from: source, to: destination)
        defaults.removeObject(forKey: bookmarkDefaultsKey)
        defaults.removeObject(forKey: displayNameDefaultsKey)
        setStatus(.appFolder)
        return report
    }

    // MARK: - Internals

    private static func persistBookmark(for url: URL, name: String) {
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            defaults.set(data, forKey: bookmarkDefaultsKey)
            defaults.set(name, forKey: displayNameDefaultsKey)
        }
    }

    /// Takes the process-lifetime access hold, releasing any previous one first.
    private static func hold(_ url: URL) {
        lock.lock()
        let previous = _heldScope
        _heldScope = url
        lock.unlock()
        if let previous, previous != url { previous.stopAccessingSecurityScopedResource() }
    }

    private static func setStatus(_ new: Status) {
        lock.lock()
        let changed = _status != new
        _status = new
        if case .chosen = new {} else {
            let previous = _heldScope
            _heldScope = nil
            lock.unlock()
            previous?.stopAccessingSecurityScopedResource()
            if changed { announce() }
            return
        }
        lock.unlock()
        if changed { announce() }
    }

    private static func announce() {
        NotificationCenter.default.post(name: .projectLocationDidChange, object: nil)
    }

    /// Drops all state — for tests only, so one suite's chosen folder cannot reach the next.
    static func resetForTesting() {
        lock.lock()
        let held = _heldScope
        _heldScope = nil
        _status = .appFolder
        lock.unlock()
        held?.stopAccessingSecurityScopedResource()
    }
}
