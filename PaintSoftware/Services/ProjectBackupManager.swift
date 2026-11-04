import Foundation
import Combine
import os

/// Foolproof, space-bounded protection against losing artwork to app updates, crashes, and
/// corruption. Everything is layered so that no single failure can destroy the last copy:
///
/// 1. Atomic saves — `ProjectStore.save` stages the new package at a temp path and only swaps it
///    over the live one once it validates, so a crash/kill mid-save can never half-write a project.
/// 2. Rotating backups — the pre-save state of every project is stashed in
///    `Documents/Backups/<projectID>/` on each save (a rename: free), and the just-saved state is
///    cloned to `latest.paintproj` via APFS copy-on-write (shared blocks: near-zero extra space).
///    Even a project saved only once has a restore point.
/// 3. Update snapshots — at launch, if the app binary changed (store update OR dev redeploy, which
///    doesn't bump the version string — so the binary's modification date is what's compared),
///    every project is snapshotted *before anything else can touch it*.
/// 4. Auto-repair — at launch, any project package that fails validation is restored from its
///    newest intact backup; the damaged package goes to Trash, never silent destruction.
/// 5. Trash — "delete" is a move to `Documents/Trash/`, auto-purged after 7 days.
///
/// Space is bounded by the age schedule `VersionRetention` applies to every dated restore point
/// (at most 44 a project, spread over a month), the trash retention window, and a global
/// `maxTotalBackupBytes` cap — which never deletes a project's last remaining restore point.
///
/// File discovery and damage checks use a Foundation-only manifest skeleton. Restores also decode
/// the current manifest strictly before replacement, without loading the scene’s cels.
nonisolated enum ProjectBackupManager {

    // MARK: - Configuration (overridable by logic tests)

    /// Overrides the directory holding Projects/Backups/Trash. Nil (default) = the app's real
    /// Documents directory. Logic tests point this at a per-test temp folder.
    nonisolated(unsafe) static var rootDirectoryOverride: URL?

    nonisolated(unsafe) static var trashRetentionInterval: TimeInterval = 7 * 24 * 60 * 60
    /// The shipped cap on all backups together. **Logical bytes** — a clone is counted in full, so
    /// the real disk cost is about a third of this; the owner ruled that stay uncounted (2026-10-10).
    static let defaultMaxTotalBackupBytes: UInt64 = 4_000_000_000
    nonisolated(unsafe) static var maxTotalBackupBytes: UInt64 = defaultMaxTotalBackupBytes

    /// Where the app signature (version + build + binary mtime) seen at the previous launch is kept.
    /// Logic tests point this at a suite of their own.
    nonisolated(unsafe) static var settings: AppSettings = .standard

    // MARK: - Directories

    /// **The root the whole library hangs off, which is not necessarily inside this app** — TODO
    /// (36). `ProjectLocation.currentRoot` is the app's own `Documents` until the artist picks a
    /// folder in Files, and their chosen folder afterwards. The test override still wins over both,
    /// so every existing logic test is unaffected and none of them can reach a real bookmark.
    static var documentsDirectory: URL {
        rootDirectoryOverride ?? ProjectLocation.currentRoot
    }

    static var projectsDirectory: URL {
        ensured(documentsDirectory.appendingPathComponent("Projects", isDirectory: true))
    }

    static var backupsRootDirectory: URL {
        ensured(documentsDirectory.appendingPathComponent("Backups", isDirectory: true))
    }

    static var trashDirectory: URL {
        ensured(documentsDirectory.appendingPathComponent("Trash", isDirectory: true))
    }

    static func backupsDirectory(projectID: UUID) -> URL {
        ensured(backupsRootDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true))
    }

    private static func ensured(_ dir: URL) -> URL {
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Walking the tree

    /// **Every project package under `Projects/`, however deeply the artist has filed it** — TODO
    /// (36)'s sub-folders, seen from the safety net's side.
    ///
    /// This is the load-bearing consequence of letting the gallery hold folders, and it is easy to
    /// miss because nothing goes red: the three maintenance passes below (`cleanupStaleSaveDirectories`,
    /// `repairCorruptedProjects`, `snapshotAllProjectsForAppUpdate`) each used
    /// `contentsOfDirectory(at: projectsDirectory)`, which is one level. The moment a project lives in
    /// `Projects/Scene 3/`, a **flat** walk stops snapshotting it before an update, stops repairing it
    /// after one, and stops sweeping its staged saves — silently, for exactly the files the artist
    /// cared enough about to organise.
    ///
    /// **It does not descend into a package**, which `FileManager.enumerator` would: a `.paintproj` is
    /// a directory, and walking into one would return its `images/` folder as a candidate and cost a
    /// recursive stat of every PNG in the library on each launch.
    ///
    /// **`Trash/` is walked by this too, and that is deliberate rather than opportunistic** — TODO
    /// (36)'s last line. A trash entry is filed under the same folder path its project had, so the
    /// two trees have exactly one shape between them and exactly one walker for it.
    static func allProjectPackages(in directory: URL? = nil) -> [URL] {
        let root = directory ?? projectsDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [URL] = []
        for item in items {
            if item.pathExtension == "paintproj" {
                out.append(item)
            } else if isDirectory(item), !item.lastPathComponent.hasPrefix(".") {
                out.append(contentsOf: allProjectPackages(in: item))
            }
        }
        return out
    }

    /// Sub-folders of one directory in the project tree. Packages are directories too, so the
    /// extension check is what separates "a folder the artist made" from "a project".
    static func subfolders(of directory: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return items.filter {
            $0.pathExtension != "paintproj" && !$0.lastPathComponent.hasPrefix(".") && isDirectory($0)
        }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    /// **`directory`'s path components below `root`, or nil when it is not below `root` at all.**
    /// `Projects/Scene 3/Shot 1` under `Projects` is `["Scene 3", "Shot 1"]`; `Projects` itself is
    /// `[]`, which is the top of the tree and not the same answer as nil.
    ///
    /// **No Unicode normalisation step, deliberately**, where `ProjectPackageName.stem` needs one.
    /// That one compares a name against `fileExists` — a syscall, which compares bytes. This compares
    /// `String`s in Swift, and Swift's `==` is canonical-equivalence-aware, so a decomposed component
    /// handed back by the volume already equals the precomposed one the root was built from. A
    /// `precomposedStringWithCanonicalMapping` here would be a line no test could ever take red.
    ///
    /// Nil is a *safe* answer everywhere it is used: a trash entry whose origin is unknown goes to
    /// `Trash/` itself, and an entry at `Trash/` itself restores to the top of the tree.
    static func folderComponents(of directory: URL, under root: URL) -> [String]? {
        let rootParts = root.standardizedFileURL.pathComponents
        let directoryParts = directory.standardizedFileURL.pathComponents
        guard directoryParts.count >= rootParts.count,
              Array(directoryParts.prefix(rootParts.count)) == rootParts else { return nil }
        return Array(directoryParts.dropFirst(rootParts.count))
    }

    // MARK: - Launch-time maintenance

    /// Every window shares one launch pass. The gallery and its writers only exist after the
    /// maintenance worker has finished reconciling packages, backups and Trash.
    @MainActor
    final class Startup: ObservableObject {
        @Published private(set) var isReady = false
        private var started = false
        private let maintenance: @Sendable () -> Void

        init(maintenance: @escaping @Sendable () -> Void = { ProjectBackupManager.runStartupMaintenance() }) {
            self.maintenance = maintenance
        }

        func start() async {
            guard !started else { return }
            started = true
            await Task.detached(priority: .userInitiated) { [maintenance] in
                maintenance()
            }.value
            isReady = true
        }
    }

    /// Compile-time platform fact used to keep persistent test resets and corruption off physical
    /// devices, including Release builds.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Runs once per launch behind the startup gate. Order matters: wipe for tests →
    /// test-corruption hook → stale temp cleanup → update snapshots → repair → purge. Every step
    /// is individually failure-proof (all `try?`); this pass must never crash the app it protects.
    static func runStartupMaintenance() {
        let args = ProcessInfo.processInfo.arguments

        // Launch-arg test hooks (never present in normal runs):
        //   -resetGallery               wipe Projects/Backups/Trash, the projects-folder choice and the
        //                               update signature (and, synchronously in `PaintApp.init`, the
        //                               artist's app-wide preferences — see `AppSettings.forgetIfRequested`)
        //   -simulateProjectCorruption  make the newest project's persisted recent colour unreadable,
        //                               so strict model decoding and backup repair can be observed.
        // These test flags mutate persistent data. A compile-time simulator guard is required even in
        // Release: `-resetGallery` previously erased the owner's saved library from a physical iPad.
        if args.contains("-resetGallery") && Self.isSimulator {
            // **Put the library back inside the app before wiping anything** — TODO (36). The three
            // directories below are resolved through `ProjectLocation`, so on a device that had
            // adopted a folder in Files this flag would reach *outside* the container and delete the
            // artist's real library. Forgetting the bookmark first makes the wipe container-only by
            // construction, which is the same reasoning the simulator guard above is built on: this
            // flag must not be able to touch anything a reinstall could not.
            ProjectLocation.settings.forgetLibraryLocation()
            ProjectLocation.resetForTesting()
            let fm = FileManager.default
            for dir in [projectsDirectory, backupsRootDirectory, trashDirectory] {
                try? fm.removeItem(at: dir)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            settings.lastAppSignature = nil
        }
        if args.contains("-simulateProjectCorruption") && Self.isSimulator {
            simulateNewestProjectCorruption()
        }

        cleanupStaleSaveDirectories()
        ProjectStore.RasterStorage.cleanupStaleSessionsOnLaunch()
        FrameExportFile.cleanupAbandoned()

        // App updated or redeployed? Snapshot every valid project BEFORE anything else can touch
        // them, so a bad update can never destroy the only copy of pre-update work.
        takeUpdateSnapshotIfNeeded()

        repairCorruptedProjects()

        // TODO (57): move each project's JSON sidecars out from under `images/`. **After the repair**
        // so a damaged package is restored before we look at it, and **before the purges** so nothing
        // is name-matched against a half-reconciled tree. It is idempotent, it never copies, it
        // deletes no file (the one removal it makes is `rmdir` on a content directory it emptied,
        // which the kernel refuses if anything is in it), and a third run changes nothing — see
        // `ProjectPackageLayout.tidy`.
        ProjectPackageLayout.tidyEveryProject()

        purgeExpiredTrash()
        pruneToSizeCap()
    }

    /// Saving and restoring stage new packages at `.saving-*` before swapping; a crash between
    /// staging and swapping leaves one behind. It's not user data (the live package was never
    /// touched), so it's just clutter to remove.
    static func cleanupStaleSaveDirectories() {
        ProjectStore.serializingPackageMutation {
            cleanupStaleSaveDirectories(in: projectsDirectory)
        }
    }

    /// Recursive since TODO (36): a project saved inside `Projects/Scene 3/` stages its package
    /// beside itself, so a one-level sweep would leave every nested `.saving-*` on disk forever.
    private static func cleanupStaleSaveDirectories(in directory: URL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls {
            if url.lastPathComponent.hasPrefix(".saving-") {
                try? fm.removeItem(at: url)
            } else if url.pathExtension != "paintproj", !url.lastPathComponent.hasPrefix("."),
                      isDirectory(url) {
                cleanupStaleSaveDirectories(in: url)
            }
        }
    }

    /// Every project whose package fails validation gets auto-restored from its newest intact
    /// backup; the damaged package is moved to Trash (never destroyed silently). A damaged project
    /// with no backups is left in place — the gallery surfaces it as damaged instead of dropping it.
    static func repairCorruptedProjects() {
        for url in allProjectPackages() {
            // `validateProject` first checks the light package skeleton and linked files. It does
            // not decode every editor-state value, so finish the current-format manifest check
            // before deciding that a package is safe to leave in Projects.
            guard !validateProject(at: url) || !currentManifestIsReadable(at: url) else { continue }
            _ = restoreNewestValidBackup(forProjectAt: url, trashTag: "corrupt")
        }
    }

    private static func currentManifestIsReadable(at projectURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: projectURL.appendingPathComponent("manifest.json")) else {
            return false
        }
        return currentManifestIsReadable(data)
    }

    private static func currentManifestIsReadable(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(ProjectManifest.self, from: data)) != nil
    }

    // MARK: - App-update detection & snapshots

    /// Takes this build's update snapshot once: every intact project is cloned into a `preupdate-`
    /// slot before startup maintenance can change it.
    static func takeUpdateSnapshotIfNeeded() {
        let signature = currentAppSignature
        if settings.lastAppSignature != signature {
            guard snapshotAllProjectsForAppUpdate(signature: signature) else { return }
            settings.lastAppSignature = signature
        }
    }

    /// Version + build + the app binary's modification date. The binary date is what actually
    /// catches dev/AI redeploys, which reinstall the app without bumping the version string.
    static var currentAppSignature: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        var stamp = "0"
        if let exe = Bundle.main.executableURL,
           let values = try? exe.resourceValues(forKeys: [.contentModificationDateKey]),
           let date = values.contentModificationDate {
            stamp = String(date.timeIntervalSince1970)
        }
        return "\(short)|\(build)|\(stamp)"
    }

    /// Clones every intact project into a `preupdate-<signature>` backup slot. Damaged projects are
    /// skipped here (the repair pass owns them) so we don't propagate a broken state as a "backup".
    @discardableResult
    static func snapshotAllProjectsForAppUpdate(signature: String) -> Bool {
        guard copyUpdateSnapshots(signature: signature, projects: allProjectPackages(), validating: { validateProjectForRestore(at: $0) }) else { return false }
        pruneUpdateSnapshots()
        return true
    }

    /// Copying and retention are separate so a format conversion can protect original bytes first,
    /// then validate and replace every version before permitting any retention deletion.
    static func copyUpdateSnapshots(signature: String, projects: [URL], validating validator: (URL) -> Bool) -> Bool {
        let sig = sanitizedSignature(signature)
        for url in projects {
            guard validator(url), let id = manifestID(at: url) else { continue }
            let dir = backupsDirectory(projectID: id)
            writeOriginMarker(directory: dir, projectFileName: url.lastPathComponent)
            let slot = uniqueSlotURL(directory: dir, prefix: "preupdate-\(sig)")
            guard cloneItem(at: url, to: slot) else {
                try? FileManager.default.removeItem(at: slot)
                return false
            }
        }
        return true
    }

    /// Retention follows a completed update operation, never a partially protected library.
    static func pruneUpdateSnapshots() {
        for id in Set(allProjectPackages().compactMap { manifestID(at: $0) }) {
            pruneBackups(forProjectID: id)
        }
    }

    private static func sanitizedSignature(_ signature: String) -> String {
        String(signature.map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(40))
    }

    // MARK: - Save-time rotation

    /// Which restore point a save's stash of the live package becomes.
    ///
    /// **The autosave is why there are two.** Before it, a save happened when the artist left the
    /// editor, so every "Before save" slot was a session's opening state. A save every thirty
    /// seconds through the same slots would make each of them thirty seconds of work, and the state
    /// the artist opened the document in — the one worth going back to after a bad session — would
    /// be lost within the session. So the first save of a document session stashes a dated version
    /// as before, and every save after it refreshes one rolling slot instead: "Before save" keeps
    /// meaning *as opened*, and "Before last save" is the thirty seconds the autosave just
    /// replaced. `ProjectStore.PackageLedger.landedAt` is what tells the two apart.
    enum SaveStash {
        /// A fresh `auto-<timestamp>` slot, thinned by age in `pruneBackups`.
        case sessionStart
        /// The one `before-last-save` slot, replaced in place.
        case rolling
    }

    static let rollingSlotName = "before-last-save.paintproj"

    /// Stashes the current on-disk package into the restore point `stash` names (a rename — free)
    /// and frees `projectURL` for the freshly staged package. Returns false only if the old package
    /// could neither be moved nor copied — in which case the caller must NOT clobber it.
    static func stashLiveProjectForSave(projectURL: URL, projectID: UUID, stash: SaveStash) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectURL.path) else { return true }
        let dir = backupsDirectory(projectID: projectID)
        writeOriginMarker(directory: dir, projectFileName: projectURL.lastPathComponent)
        let slot: URL
        switch stash {
        case .sessionStart:
            slot = uniqueSlotURL(directory: dir, prefix: "auto")
        case .rolling:
            slot = dir.appendingPathComponent(rollingSlotName)
            // The previous rolling stash goes before the live package moves, never after: a kill
            // between the two lines loses a restore point, and the other order would lose the
            // project.
            try? fm.removeItem(at: slot)
        }
        if (try? fm.moveItem(at: projectURL, to: slot)) != nil { return true }
        if cloneItem(at: projectURL, to: slot), (try? fm.removeItem(at: projectURL)) != nil { return true }
        return false
    }

    /// Refreshes the `latest.paintproj` restore point — an exact clone of the just-saved live
    /// package. This is the primary recovery source for "the app updated/crashed and now my file
    /// won't open": it always holds the most recent successfully-saved state, even for a project
    /// saved only once (where rotation has no previous state to stash).
    static func refreshLatestSnapshot(projectURL: URL, projectID: UUID) {
        guard FileManager.default.fileExists(atPath: projectURL.path) else { return }
        let dir = backupsDirectory(projectID: projectID)
        writeOriginMarker(directory: dir, projectFileName: projectURL.lastPathComponent)
        _ = cloneItem(at: projectURL, to: latestSnapshotURL(directory: dir))
    }

    static func latestSnapshotURL(directory: URL) -> URL {
        directory.appendingPathComponent("latest.paintproj")
    }

    /// A fresh slot for a save that must **not** touch the live project package.
    ///
    /// The one caller is `ProjectStore`'s `.writeAside` path (see `SaveDamageGate`): a project that
    /// loaded with something unreadable, whose artist has not yet said whether the damaged original
    /// may be overwritten. Their edits still have to land somewhere — a background save that wrote
    /// nothing would lose them to the next jetsam kill — so a complete package goes here instead, and
    /// the project file is left exactly as it was.
    ///
    /// **It is an ordinary slot in the project's own backup folder, on purpose.** `listBackups` picks
    /// up any `.paintproj` in that directory, so it appears in the gallery's Versions sheet beside
    /// "Last saved state" and "Before save" with no new UI at all, and `restoreNewestValidBackup`
    /// will reach for it during launch repair exactly as it would any other restore point.
    static func unsavedChangesSlotURL(projectURL: URL, projectID: UUID) -> URL {
        let dir = backupsDirectory(projectID: projectID)
        writeOriginMarker(directory: dir, projectFileName: projectURL.lastPathComponent)
        return uniqueSlotURL(directory: dir, prefix: "unsaved")
    }

    /// The slots that carry their own date: one per session (`auto-`), per app update (`preupdate-`)
    /// and per save made aside (`unsaved-`). `latest` and the rolling slot are replaced in place and
    /// never thinned.
    private static let datedSlotPrefixes = ["auto-", "preupdate-", "unsaved-"]

    /// Thins one project's dated restore points to what `VersionRetention` keeps, whatever kind each
    /// is — an app update's snapshot is a version like any other, and keeps its "Before app update"
    /// label in the list for as long as the schedule keeps it. Run after every save and every update
    /// snapshot.
    static func pruneBackups(forProjectID id: UUID, now: Date = Date()) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: backupsDirectory(projectID: id), includingPropertiesForKeys: nil) else { return }
        let slots = urls.filter { url in
            url.pathExtension == "paintproj" && datedSlotPrefixes.contains { url.lastPathComponent.hasPrefix($0) }
        }
        let kept = VersionRetention.keep(
            slots.map { VersionRetention.Version(id: $0.deletingPathExtension().lastPathComponent, date: slotDate($0)) },
            now: now)
        for url in slots where !kept.contains(url.deletingPathExtension().lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Backup discovery & restore

    struct ProjectBackup: Identifiable {
        let url: URL
        var id: String { url.lastPathComponent }
        /// Human description of the slot kind ("Last saved state" / "Before save" / "Before app update").
        let label: String
        let date: Date
        let isLatest: Bool
        let isValid: Bool
    }

    /// Finds the backup folder belonging to a live project package. Normally keyed by the
    /// manifest's project ID; when the manifest is unreadable (exactly the corruption case), falls
    /// back to a unique `origin.name` marker. Multiple matching scene names are ambiguous.
    static func backupDirectory(forProjectAt projectURL: URL) -> URL? {
        let fm = FileManager.default
        if let id = manifestID(at: projectURL) {
            let dir = backupsRootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
            if fm.fileExists(atPath: dir.path) { return dir }
        }
        guard let dirs = try? fm.contentsOfDirectory(at: backupsRootDirectory, includingPropertiesForKeys: nil) else { return nil }
        let matches = dirs.filter { dir in
            (try? String(contentsOf: dir.appendingPathComponent("origin.name"), encoding: .utf8)) == projectURL.lastPathComponent
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// All restore points for a project, `latest` first then newest-to-oldest.
    static func listBackups(forProjectAt projectURL: URL) -> [ProjectBackup] {
        guard let dir = backupDirectory(forProjectAt: projectURL),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension == "paintproj" }
            .map { backupInfo(for: $0) }
            .sorted { lhs, rhs in
                if lhs.isLatest != rhs.isLatest { return lhs.isLatest }
                return lhs.date > rhs.date
            }
    }

    /// Validates a staged clone in the current format before replacing the live scene.
    /// The original restore point is never rewritten; the displaced live scene remains recoverable
    /// in Trash. Staging uses the save prefix so the existing crash-cleanup sweep also removes an
    /// interrupted restore’s temporary package.
    @discardableResult
    static func restoreBackup(at backupURL: URL, toProjectAt projectURL: URL, trashTag: String = "replaced") -> Bool {
        let fm = FileManager.default
        guard validateProjectForRestore(at: backupURL) else { return false }
        let staged = projectURL.deletingLastPathComponent()
            .appendingPathComponent(".saving-restore-\(UUID().uuidString).paintproj")
        defer { try? fm.removeItem(at: staged) }
        guard cloneItem(at: backupURL, to: staged), validateProjectForRestore(at: staged) else { return false }
        var displaced: URL?
        if fm.fileExists(atPath: projectURL.path) {
            guard let trash = moveToTrash(projectURL, tag: trashTag) else { return false }
            displaced = trash
        }
        do {
            try fm.moveItem(at: staged, to: projectURL)
            return true
        } catch {
            if let displaced { try? fm.moveItem(at: displaced, to: projectURL) }
            return false
        }
    }

    /// The automatic-repair path: restores from the newest backup that itself passes validation.
    @discardableResult
    static func restoreNewestValidBackup(forProjectAt projectURL: URL, trashTag: String = "corrupt") -> Bool {
        for backup in listBackups(forProjectAt: projectURL) where backup.isValid {
            if restoreBackup(at: backup.url, toProjectAt: projectURL, trashTag: trashTag) { return true }
        }
        return false
    }

    private static func backupInfo(for url: URL) -> ProjectBackup {
        let name = url.deletingPathExtension().lastPathComponent
        let isLatest = url.lastPathComponent == "latest.paintproj"
        let label: String
        if isLatest {
            label = "Last saved state"
        } else if name.hasPrefix("preupdate-") {
            label = "Before app update"
        } else if name.hasPrefix("unsaved-") {
            // Said from the artist's side: these are their edits, kept because the project file was
            // left alone rather than overwritten. See `unsavedChangesSlotURL`.
            label = "Unsaved changes"
        } else if url.lastPathComponent == rollingSlotName {
            label = "Before last save"
        } else {
            label = "Before save"
        }
        return ProjectBackup(url: url, label: label, date: slotDate(url), isLatest: isLatest, isValid: validateProjectForRestore(at: url))
    }

    // MARK: - Trash

    struct TrashItem: Identifiable {
        let url: URL
        /// **The entry's path relative to `Trash/`, not its filename.** Two projects called "Boat"
        /// deleted from two different folders in the same second produce the same filename, and a
        /// `ForEach` given two rows with one identity draws one of them never — the failure
        /// `ProjectSummary` already carries a note about. The relative path is unique by
        /// construction, because it is a path.
        let id: String
        let displayName: String
        /// **The folder it was deleted from, relative to `Projects/`.** Empty means the top of the
        /// tree — which is also what an entry deleted by a build that had no folders answers, and
        /// that is the right answer for it rather than a fallback.
        let originComponents: [String]
        let deletedAt: Date
        let sizeBytes: UInt64

        /// Where the row says it came from, in the breadcrumb's own vocabulary.
        var originDisplay: String {
            (["Projects"] + originComponents).joined(separator: " / ")
        }
    }

    /// **Moves a package into Trash (never a hard delete), under a mirror of the folder path it was
    /// filed in.** Returns the trash URL.
    ///
    /// A project deleted from `Projects/Scene 3/Shot 1/` lands at `Trash/Scene 3/Shot 1/`, and that
    /// mirrored path **is** the origin marker TODO (36)'s last line asked for. It is not stored
    /// anywhere: it is where the entry is. A marker in the filename would have to escape `/` and
    /// would blow the 255-byte component limit on a deep path; one in the manifest would mean writing
    /// into artwork on the way to deleting it, and a damaged package could not take one; one in a
    /// sidecar beside the entry can be separated from it by any operation that moves one and not the
    /// other — `ProjectLibraryMigration.uniqueURL` renames a colliding item, and it would rename the
    /// two halves apart. A location cannot disagree with itself.
    ///
    /// Falling back to `Trash/` itself when the mirror cannot be made is deliberate and is the only
    /// direction that is safe: a delete must never fail because a directory could not be created, and
    /// an entry at `Trash/` restores to the top of the tree, which is exactly what the shipped build
    /// does for every entry.
    @discardableResult
    static func moveToTrash(_ url: URL, tag: String) -> URL? {
        let fm = FileManager.default
        let directory = trashFolder(mirroring: url.deletingLastPathComponent())
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(base)__\(tag)__\(timestampString()).paintproj")
        if fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)__\(tag)__\(timestampString())-\(UUID().uuidString.prefix(4)).paintproj")
        }
        return (try? fm.moveItem(at: url, to: candidate)).map { candidate }
    }

    /// The directory under `Trash/` that mirrors `projectFolder`'s path under `Projects/`, created if
    /// it is not there. `Trash/` itself for a project at the top of the tree, for one filed somewhere
    /// outside `Projects/` altogether, and for a mirror that could not be created.
    private static func trashFolder(mirroring projectFolder: URL) -> URL {
        guard let components = folderComponents(of: projectFolder, under: projectsDirectory),
              !components.isEmpty else { return trashDirectory }
        let mirror = components.reduce(trashDirectory) { $0.appendingPathComponent($1, isDirectory: true) }
        try? FileManager.default.createDirectory(at: mirror, withIntermediateDirectories: true)
        return isDirectory(mirror) ? mirror : trashDirectory
    }

    /// Every trash entry, however deep the folder it was deleted from was. The same walker the
    /// project tree uses, pointed at the other tree — see `allProjectPackages`.
    static func listTrash() -> [TrashItem] {
        allProjectPackages(in: trashDirectory).map(trashItem).sorted { $0.deletedAt > $1.deletedAt }
    }

    private static func trashItem(at url: URL) -> TrashItem {
        let parsed = parseTrashName(url.deletingPathExtension().lastPathComponent)
        let origin = folderComponents(of: url.deletingLastPathComponent(), under: trashDirectory) ?? []
        return TrashItem(url: url,
                         id: (origin + [url.lastPathComponent]).joined(separator: "/"),
                         displayName: parsed?.base ?? url.deletingPathExtension().lastPathComponent,
                         originComponents: origin,
                         deletedAt: parsed?.date ?? fileDate(url),
                         sizeBytes: directorySize(url))
    }

    /// **What a restore did**, so the gallery can say it instead of the artist finding out later.
    /// Every field is derived from where the project ended up, not from an intention recorded
    /// earlier — so there is nothing here that can be true of a restore that did not happen.
    struct TrashRestore {
        /// Where the project is now.
        let url: URL
        /// The folder it came from, relative to `Projects/`. Empty is the top of the tree.
        let origin: [String]
        /// The folder path it asked for and could not have, because it is no longer there. Nil when
        /// the project landed exactly where it was deleted from — including at the top of the tree,
        /// which is not a displacement.
        let missingOriginFolder: String?
        /// The name it had to take because its own was occupied. Nil when it kept its own.
        let renamedTo: String?

        /// The sentence the artist is shown, or nil when the restore needs no explanation. **This
        /// being nil in the ordinary case is the point**: a notice on every restore is one nobody
        /// reads by the third time.
        var notice: String? {
            var parts: [String] = []
            if let missingOriginFolder {
                parts.append("The folder it was deleted from — “\(missingOriginFolder)” — is not "
                             + "there any more, so it has been put at the top of the gallery.")
            }
            if let renamedTo {
                parts.append("Something was already there under its old name, so it is now called "
                             + "“\(renamedTo)”. Nothing was replaced.")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    /// **Puts a trashed package back in the folder it was deleted from** — TODO (36)'s last line.
    ///
    /// The move is a `rename(2)`: `Trash/` and `Projects/` are siblings under one root, so it is
    /// atomic and the package is complete in exactly one place at every instant. Nothing is ever
    /// overwritten — a name already taken at the origin disambiguates the way a second project of the
    /// same name always has — and nothing is created: an origin folder that has gone is reported, not
    /// re-invented, because a folder appearing that the artist deleted is a side effect they did not
    /// ask for and cannot see coming.
    ///
    /// Returns nil when the move or its collision-name write failed. The entry remains complete
    /// in Trash and remains listed.
    @discardableResult
    static func restoreFromTrash(_ trashURL: URL) -> TrashRestore? {
        let base = parseTrashName(trashURL.deletingPathExtension().lastPathComponent)?.base ?? "Recovered"
        let origin = folderComponents(of: trashURL.deletingLastPathComponent(), under: trashDirectory) ?? []
        let wanted = origin.reduce(projectsDirectory) { $0.appendingPathComponent($1, isDirectory: true) }
        // The filesystem answers this, every time, at the moment of the restore. The mirrored path
        // says where the project *was*; only `isDirectory` says whether that place still exists, and
        // it is the one that wins.
        let originIsThere = origin.isEmpty || isDirectory(wanted)

        let destination = uniqueProjectURL(baseName: base, in: originIsThere ? wanted : projectsDirectory)
        let landedStem = destination.deletingPathExtension().lastPathComponent
        guard ProjectPackageName.move(trashURL, to: destination,
            retitling: landedStem == base ? nil : landedStem) != nil else { return nil }
        pruneEmptyTrashFolders()
        return TrashRestore(url: destination,
                            origin: origin,
                            missingOriginFolder: originIsThere ? nil : origin.joined(separator: " / "),
                            renamedTo: landedStem == base ? nil : landedStem)
    }

    /// **Removes mirror folders under `Trash/` that a purge or a restore emptied**, depth-first. A
    /// mirror folder is not a record of anything on its own — an empty one would say a project came
    /// from somewhere while holding no project — and it is the one piece of this design that would
    /// otherwise accumulate for ever. `Trash/` itself is never asked, because only items *inside* a
    /// scanned directory are.
    ///
    /// **`rmdir(2)` rather than `contentsOfDirectory` then `removeItem`**, which is
    /// `ProjectPackageLayout.pruneEmptyContentDirectories`' reason reached one door over and with
    /// more at stake here. The kernel refuses a non-empty directory itself, in one call, with no
    /// window between the check and the removal — and `FileManager.removeItem` is **recursive**, so a
    /// check-then-remove would delete a whole package that a `moveToTrash` landed in the mirror
    /// microseconds after the check said it was empty. That interleaving is reachable rather than
    /// theoretical: `runStartupMaintenance` is detached and calls `purgeExpiredTrash` while the
    /// gallery is already on screen with a Delete on every tile. `ENOTEMPTY` and `ENOENT` are both
    /// the ordinary answer and neither is worth reading — a hidden file keeps its folder, which is
    /// the safe direction.
    static func pruneEmptyTrashFolders() {
        pruneEmptyFolders(under: trashDirectory)
    }

    static func pruneEmptyFolders(under directory: URL) {
        guard let items = try? ProjectFileTree.children(of: directory) else { return }
        for item in items where item.pathExtension != "paintproj"
            && (try? ProjectFileTree.entry(at: item)) == .directory {
            pruneEmptyFolders(under: item)
            _ = item.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return rmdir(path)
            }
        }
    }

    /// Removes expired Trash entries. History belongs to a project UUID, and survives while any
    /// live or retained Trash package owns that UUID. Unknown ownership preserves all histories.
    static func purgeExpiredTrash(now: Date = Date()) {
        let fm = FileManager.default
        guard let packages = try? projectPackages(in: trashDirectory) else { return }
        var removedProjectIDs: Set<UUID> = []
        for item in packages.map(trashItem) where now.timeIntervalSince(item.deletedAt) > trashRetentionInterval {
            let id = try? projectID(at: item.url)
            do {
                try fm.removeItem(at: item.url)
                if let id { removedProjectIDs.insert(id) }
            } catch {
                // A package that could not be removed still owns its recovery history.
            }
        }
        if !removedProjectIDs.isEmpty,
           let liveIDs = try? projectIDs(in: projectsDirectory),
           let trashIDs = try? projectIDs(in: trashDirectory),
           (try? ProjectFileTree.entry(at: backupsRootDirectory)) == .directory {
            for id in removedProjectIDs.subtracting(liveIDs.union(trashIDs)) {
                let directory = backupsRootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
                guard (try? ProjectFileTree.entry(at: directory)) == .directory else { continue }
                try? fm.removeItem(at: directory)
            }
        }
        pruneEmptyTrashFolders()
    }

    /// Unlike the gallery's tolerant listing, deletion needs a complete ownership census. A failed
    /// listing, linked entry or unreadable manifest cannot establish that a history has no owner.
    private static func projectIDs(in directory: URL) throws -> Set<UUID> {
        try Set(projectPackages(in: directory).map { try projectID(at: $0) })
    }

    static func projectPackages(in directory: URL) throws -> [URL] {
        var packages: [URL] = []
        for item in try ProjectFileTree.children(of: directory) where !item.lastPathComponent.hasPrefix(".") {
            let entry = try ProjectFileTree.entry(at: item)
            if item.pathExtension == "paintproj" {
                guard entry == .directory else { throw CocoaError(.fileReadCorruptFile) }
                packages.append(item)
            } else if entry == .directory {
                packages.append(contentsOf: try projectPackages(in: item))
            }
        }
        return packages
    }

    private static func projectID(at package: URL) throws -> UUID {
        guard try ProjectFileTree.entry(at: package) == .directory,
              case .file = try ProjectFileTree.entry(at: package.appendingPathComponent("manifest.json")),
              let id = manifestID(at: package) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return id
    }

    /// A free package name for `baseName` **inside `directory`**. Per-folder, for
    /// `ProjectStore.createNewProjectURL`'s reason: two shots both called "Rough" in different scenes
    /// is the ordinary case once there are folders, and the app renaming one of them would be the app
    /// renaming the artist's work for nothing.
    static func uniqueProjectURL(baseName: String, in directory: URL) -> URL {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : baseName
        var candidate = directory.appendingPathComponent("\(base).paintproj")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix).paintproj")
            suffix += 1
        }
        return candidate
    }

    // MARK: - Global size cap

    /// Global space safety net, deleting oldest-first across all backup slots and trash. Never
    /// deletes a `latest` snapshot, and never deletes a project's last remaining restore point —
    /// the cap goes soft when enforcing it would leave a project unrecoverable.
    static func pruneToSizeCap() {
        let fm = FileManager.default
        var total = directorySize(backupsRootDirectory) + directorySize(trashDirectory)
        guard total > maxTotalBackupBytes else { return }

        var candidates: [(url: URL, date: Date, size: UInt64, backupDir: URL?)] = []
        if let dirs = try? fm.contentsOfDirectory(at: backupsRootDirectory, includingPropertiesForKeys: nil) {
            for dir in dirs {
                guard let slots = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                for slot in slots where slot.pathExtension == "paintproj" && slot.lastPathComponent != "latest.paintproj" {
                    candidates.append((slot, slotDate(slot), directorySize(slot), dir))
                }
            }
        }
        for item in listTrash() {
            candidates.append((item.url, item.deletedAt, item.sizeBytes, nil))
        }
        candidates.sort { $0.date < $1.date } // oldest first

        var checkedDirectories: Set<URL> = []
        var protectedRestorePoints: Set<URL> = []
        for c in candidates {
            guard total > maxTotalBackupBytes else { break }
            if let dir = c.backupDir {
                if checkedDirectories.insert(dir).inserted,
                   !validateProjectForRestore(at: latestSnapshotURL(directory: dir)) {
                    let slots = candidates.reversed().filter { $0.backupDir == dir }
                    if let usable = slots.first(where: { validateProjectForRestore(at: $0.url) }) {
                        protectedRestorePoints.insert(usable.url)
                    } else {
                        // No proven fallback: uncertain data cannot make another deletion safe.
                        protectedRestorePoints.formUnion(slots.map(\.url))
                    }
                }
                if protectedRestorePoints.contains(c.url) { continue }
            }
            if (try? fm.removeItem(at: c.url)) != nil {
                total = total > c.size ? total - c.size : 0
            }
        }
        // The cap deletes trash entries too, so it can empty a mirror folder like a purge can.
        pruneEmptyTrashFolders()
    }

    // MARK: - Validation

    /// Minimal mirror of `ProjectManifest`'s *file-reference* surface. Decoding this instead of the
    /// real manifest is deliberate: this file is shared with the UI-test bundle, which doesn't have
    /// the app's model types — and ignoring every non-file key keeps the check robust against
    /// future manifest schema additions.
    ///
    /// **Internal rather than private since TODO (57)**: `ProjectPackageLayout.tidy` asks this
    /// manifest exactly the same question — which files does this package name, and for which cel —
    /// and two decoders for one question is how the writer and the validator drift apart.
    struct ManifestSkeleton: Decodable {
        var id: UUID
        var layers: [Layer]
        /// Mirrors `ProjectManifest.name` — the project's title, which since TODO (57) part 2 is what
        /// the package *directory* is named after.
        ///
        /// **Optional, where `ProjectManifest.name` is not**, for `Cel.id`'s reason one door over:
        /// this struct decodes less than the manifest holds rather than more, several logic-test
        /// fixtures hand-build a manifest with no `name` key at all, and a required field would take
        /// them red for nothing. Nil means only that the launch pass leaves that package's directory
        /// name alone — there is no title to reconcile it against.
        var name: String?
        /// Mirrors `ProjectManifest.brushTableFileName` — BRUSH.md §5.4. It is checked for the reason
        /// `vectorFileName` is: without it every stroke in the package names a brush that cannot be
        /// resolved, so the package's ink is gone. Unlike the recipe sidecar this is not a link whose
        /// loss costs only the link, which is why it is validated on day one.
        var brushTableFileName: String?
        struct Layer: Decodable {
            var cels: [Cel]
        }
        struct Cel: Decodable {
            /// Mirrors `CelManifest.id`, and it is what TODO (57)'s resolver needs to derive a bare
            /// legacy sidecar name's *new* address (`ProjectPackageLayout.existingURL`).
            ///
            /// **Optional, where `CelManifest.id` is not, and that is deliberate rather than sloppy.**
            /// Every manifest this app has ever written carries it, so requiring it here would reject
            /// nothing real — but two logic-test fixtures hand-build a cel as
            /// `["rasterFileName": …, "rasterOmitted": true]` with no `id` key, and this struct's
            /// whole character is that it decodes less than the manifest holds rather than more. Nil
            /// costs only the alternate probe, and a package with no cel ids has no moved sidecars to
            /// probe for.
            var id: UUID?
            var rasterFileName: String
            /// Mirrors `CelManifest.rasterOmitted`: the cel's raster tier held no bitmap, so no PNG
            /// was written and `rasterFileName` names a file that is legitimately not there. Without
            /// this key here the validator would call every such package damaged, and — because
            /// `ProjectStore.writeAtomically` gates the atomic swap on this very function — every
            /// save of a document with one blank cel would be quietly trashed instead of committed.
            var rasterOmitted: Bool?
            var bakedImageFileName: String?
            var vectorFileName: String?
            /// Mirrors `CelManifest.animationFileName` — KEYFRAMES.md §3.5's *"add it to the
            /// validator on day one"*.
            ///
            var animationFileName: String?

            /// This cel's recorded name for one of the three moved roles — TODO (57). One switch so
            /// the validator and `ProjectPackageLayout.tidy` cannot disagree about which field a role
            /// reads.
            func fileName(for role: ProjectPackageLayout.Role) -> String? {
                switch role {
                case .drawing:       return vectorFileName
                case .animation:     return animationFileName
                case .interpolation: return interpolationFileName
                default:             return nil
                }
            }
            /// A named recipe must exist and decode as current metadata before ordinary reads or saves.
            var interpolationFileName: String?
        }
    }

    private static let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// A project package counts as intact when its manifest decodes and every file the manifest
    /// references (raster/fill/baked PNGs, vector JSON) both exists and — for PNGs — starts with the
    /// 8-byte PNG signature (catches crash-truncated writes, not just missing files).
    static func validateProject(at url: URL) -> Bool {
        guard let manifestURL = try? ProjectPackageLayout.resolve("manifest.json", in: url),
              let data = try? Data(contentsOf: manifestURL) else { return false }
        return validateProjectFiles(at: url, manifestData: data) && ProjectRecipeMetadata.validate(in: url, manifestData: data)
    }

    /// Restores require a strictly readable current manifest as well as intact referenced files and
    /// ink metadata. Validation never rewrites the source version or loads its cel pictures.
    static func validateProjectForRestore(at url: URL) -> Bool {
        guard let manifestURL = try? ProjectPackageLayout.resolve("manifest.json", in: url),
              let data = try? Data(contentsOf: manifestURL),
              currentManifestIsReadable(data) else { return false }
        return validateProjectFiles(at: url, manifestData: data)
            && ProjectRecipeMetadata.validate(in: url, manifestData: data)
            && ProjectRecipeMetadata.validateRestoreStreams(in: url, manifestData: data)
    }

    private static func validateProjectFiles(at url: URL, manifestData: Data) -> Bool {
        let fm = FileManager.default
        guard let skeleton = try? JSONDecoder().decode(ManifestSkeleton.self, from: manifestData) else {
            return false
        }
        do {
            // **Resolved through `ProjectPackageLayout`, not joined to `images/`** — TODO (57). The
            // address of a sidecar is a question with one answer, and this is the third place that asks
            // it. Without this the validator would call a package mid-migration damaged — a file moved to
            // `drawings/` while the manifest still names it bare is *exactly* the state a crash between
            // the move and the manifest rewrite leaves — `repairCorruptedProjects` would restore over it,
            // and `tidy`'s own step-0 guard would refuse to finish the migration that would fix it.
            func fileIntact(_ name: String, isPNG: Bool, role: ProjectPackageLayout.Role, cel: UUID?) throws -> Bool {
                let fileURL = try ProjectPackageLayout.existingURL(named: name, role: role, cel: cel, in: url)
                guard fm.fileExists(atPath: fileURL.path) else { return false }
                guard isPNG else { return true }
                guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
                let head = try? handle.read(upToCount: pngMagic.count)
                try? handle.close()
                guard let head else { return false }
                return head.count == pngMagic.count && [UInt8](head) == pngMagic
            }

            // In the package root beside `brushes/`, not in `images/`, so it gets its own existence check
            // rather than `fileIntact`'s.
            if let brushTable = skeleton.brushTableFileName,
               !fm.fileExists(atPath: try ProjectPackageLayout.resolve(brushTable, in: url).path) { return false }

            for layer in skeleton.layers {
                for cel in layer.cels {
                    // **Absent-because-omitted and absent-because-lost stay different states**, and
                    // telling them apart is the entire job of this line. A cel that says `rasterOmitted`
                    // never had a PNG and must validate; a cel that names one and cannot produce it is
                    // damaged exactly as it always was — `BackupManagerLogicTests` pins both directions.
                    if cel.rasterOmitted != true,
                       !(try fileIntact(cel.rasterFileName, isPNG: true, role: .raster, cel: cel.id)) { return false }
                    if let baked = cel.bakedImageFileName,
                       !(try fileIntact(baked, isPNG: true, role: .baked, cel: cel.id)) { return false }
                    if let vector = cel.vectorFileName,
                       !(try fileIntact(vector, isPNG: false, role: .drawing, cel: cel.id)) { return false }
                    if let animation = cel.animationFileName,
                       !(try fileIntact(animation, isPNG: false, role: .animation, cel: cel.id)) { return false }
                }
            }
            return true
        } catch { return false }
    }

    /// The project ID from a package's manifest, or nil if the manifest is missing/unreadable.
    static func manifestID(at url: URL) -> UUID? {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let skeleton = try? JSONDecoder().decode(ManifestSkeleton.self, from: data) else { return nil }
        return skeleton.id
    }

    // MARK: - File helpers

    /// APFS copy-on-write clone (instant, shares data blocks with the source until either diverges)
    /// with a plain-copy fallback. This is what keeps "a backup of every save" cheap in both time
    /// and disk: unchanged PNG blocks are never duplicated.
    @discardableResult
    static func cloneItem(at src: URL, to dst: URL) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: dst) // both clonefile and copyItem require dst to not exist
        let status: Int32 = src.withUnsafeFileSystemRepresentation { s in
            dst.withUnsafeFileSystemRepresentation { d in
                guard let s, let d else { return -1 }
                return clonefile(s, d, 0)
            }
        }
        if status == 0 { return true }
        return (try? fm.copyItem(at: src, to: dst)) != nil
    }

    static func directorySize(_ url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += UInt64(max(size, 0))
        }
        return total
    }

    private static func uniqueSlotURL(directory: URL, prefix: String) -> URL {
        let fm = FileManager.default
        let base = "\(prefix)-\(timestampString())"
        var candidate = directory.appendingPathComponent("\(base).paintproj")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(n).paintproj")
            n += 1
        }
        return candidate
    }

    @discardableResult
    private static func writeOriginMarker(directory: URL, projectFileName: String) -> Bool {
        do {
            try projectFileName.write(to: directory.appendingPathComponent("origin.name"),
                                      atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }

    /// Explicit moves preserve the exact old marker on refusal, including absence. A Trash package's
    /// timestamped filename cannot stand in for the marker its live scene previously wrote.
    static func withProjectRenameOrigin(projectID: UUID, to filename: String,
                                        _ move: () -> URL?) -> URL? {
        let fm = FileManager.default
        let directory = backupsRootDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard fm.fileExists(atPath: directory.path) else { return move() }
        let marker = directory.appendingPathComponent("origin.name")
        let original: Data?
        do { original = fm.fileExists(atPath: marker.path) ? try Data(contentsOf: marker) : nil }
        catch { return nil }
        guard writeOriginMarker(directory: directory, projectFileName: filename) else { return nil }
        let landed = move()
        if landed == nil {
            do {
                if let original { try original.write(to: marker, options: .atomic) }
                else { try fm.removeItem(at: marker) }
            } catch {
                Logger(subsystem: "Starg.PaintSoftware", category: "ProjectRename")
                    .error("Backup origin rollback failed: \(String(describing: error), privacy: .public)")
            }
        }
        return landed
    }

    /// **Points a project's backup folder at the name its package is about to have** — TODO (57)
    /// part 2, called by the launch rename pass *before* it moves the directory.
    ///
    /// `origin.name` is the fallback `backupDirectory(forProjectAt:)` uses when a package's manifest
    /// has become unreadable, and it is `purgeExpiredTrash`'s history key. It records the package's
    /// filename at the moment some backup slot was minted and is otherwise never rewritten, so a
    /// directory rename would strand it — the one case where the fallback matters is exactly the one
    /// where the primary manifest-id lookup cannot answer.
    ///
    /// **Written before the move, and only into a folder that already exists.** Before, because a
    /// crash between the two leaves a marker naming a package that is about to appear rather than one
    /// that has already gone; and `backupsDirectory(projectID:)` *creates* the folder it names, which
    /// would leave an empty `Backups/<uuid>/` behind for every project that has never been saved by
    /// this build.
    static func noteProjectRenamed(projectID: UUID, to projectFileName: String) {
        let dir = backupsRootDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        writeOriginMarker(directory: dir, projectFileName: projectFileName)
    }

    /// "<base>__<tag>__<yyyyMMdd-HHmmss>" -> (base, tag, date). The base may itself contain "__".
    private static func parseTrashName(_ name: String) -> (base: String, tag: String, date: Date)? {
        guard let regex = try? NSRegularExpression(pattern: "^(.*)__([a-z]+)__([0-9]{8}-[0-9]{6})(?:-[0-9A-Fa-f]{4})?$"),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              match.numberOfRanges == 4,
              let baseRange = Range(match.range(at: 1), in: name),
              let tagRange = Range(match.range(at: 2), in: name),
              let dateRange = Range(match.range(at: 3), in: name),
              let date = parseTimestamp(String(name[dateRange])) else { return nil }
        return (String(name[baseRange]), String(name[tagRange]), date)
    }

    private static func slotDate(_ url: URL) -> Date {
        timestampFromName(url.deletingPathExtension().lastPathComponent) ?? fileDate(url)
    }

    /// The stamp is the end of the name, before an optional collision counter. Anchored there because
    /// an update snapshot's name carries the app signature first, and a signature's own digits can
    /// look like a stamp — and now that a version's date decides whether it is deleted, a wrong one
    /// is no longer just an odd sort order.
    private static func timestampFromName(_ name: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]{8}-[0-9]{6}(?=(?:-[0-9]+)?$)"),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range, in: name) else { return nil }
        return parseTimestamp(String(name[range]))
    }

    private static func fileDate(_ url: URL) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date) ?? Date.distantPast
    }

    private static let timestampFormat = "yyyyMMdd-HHmmss"

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = timestampFormat
        return formatter
    }()

    static func timestampString(_ date: Date = Date()) -> String {
        timestampFormatter.string(from: date)
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        timestampFormatter.date(from: string)
    }

    private static func simulateNewestProjectCorruption() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else { return }
        let projects = urls.filter { $0.pathExtension == "paintproj" }.sorted { fileDate($0) < fileDate($1) }
        guard let newest = projects.last else { return }
        let manifestURL = newest.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var editorState = manifest["editorState"] as? [String: Any],
              var tools = editorState["tools"] as? [String: Any],
              var panel = tools["colorPanel"] as? [String: Any],
              var recent = panel["recentColors"] as? [[String: Any]],
              !recent.isEmpty else { return }
        recent[0]["hex"] = "not-a-color"
        panel["recentColors"] = recent
        tools["colorPanel"] = panel
        editorState["tools"] = tools
        manifest["editorState"] = editorState
        guard let damaged = try? JSONSerialization.data(withJSONObject: manifest) else { return }
        try? damaged.write(to: manifestURL, options: .atomic)
    }
}
