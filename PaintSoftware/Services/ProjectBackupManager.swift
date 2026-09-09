import Foundation

extension Notification.Name {
    /// Posted on the main thread when the launch-time backup maintenance pass finishes, so the
    /// gallery can re-list projects (a damaged project may have been auto-restored meanwhile).
    static let projectBackupMaintenanceDidFinish = Notification.Name("PaintApp.ProjectBackupMaintenanceDidFinish")
}

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
/// Space is bounded by rotation counts (`maxAutosaveBackupsPerProject`,
/// `maxPreUpdateBackupsPerProject`), the trash retention window, and a global
/// `maxTotalBackupBytes` cap — which never deletes a project's last remaining restore point.
///
/// This type is deliberately pure Foundation (no UIKit/SwiftUI, no app-model dependencies — the
/// manifest is probed via a private skeleton struct) so it can be compiled directly into the
/// UI-test bundle for logic tests, the same pattern as `Engine/Brush.swift` (see
/// `BrushEngineLogicTests.swift`'s header comment for why `@testable import` doesn't work there).
nonisolated enum ProjectBackupManager {

    // MARK: - Configuration (overridable by logic tests)

    /// Overrides the directory holding Projects/Backups/Trash. Nil (default) = the app's real
    /// Documents directory. Logic tests point this at a per-test temp folder.
    nonisolated(unsafe) static var rootDirectoryOverride: URL?

    nonisolated(unsafe) static var maxAutosaveBackupsPerProject = 5
    nonisolated(unsafe) static var maxPreUpdateBackupsPerProject = 3
    /// How many "saved without touching the project file" slots to keep — see
    /// `unsavedChangesSlotURL`. Rotated like the others so a project the artist keeps backgrounding
    /// without ever answering the damaged-save banner cannot grow its history without bound.
    nonisolated(unsafe) static var maxUnsavedBackupsPerProject = 5
    nonisolated(unsafe) static var trashRetentionInterval: TimeInterval = 7 * 24 * 60 * 60
    nonisolated(unsafe) static var maxTotalBackupBytes: UInt64 = 1_000_000_000

    /// UserDefaults key holding the app signature (version + build + binary mtime) seen at the
    /// previous launch. Internal (not private) so logic tests can clear it between runs.
    static let signatureDefaultsKey = "PaintApp.projectBackup.lastAppSignature"

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

    // MARK: - Launch-time maintenance

    /// Whether this build is running in a simulator, which is the only place `-resetGallery` is
    /// honoured.
    ///
    /// **This was `ProcessInfo.environment["SIMULATOR_DEVICE_NAME"] != nil` for one commit and the
    /// compile-time form is still the right one**, because a guard on a destructive path has to be
    /// *right* before it is testable and `targetEnvironment(simulator)` cannot be wrong. What a test
    /// can still reach is `honoursGalleryReset(isSimulator:)` below, which holds the *policy* — the
    /// part worth pinning — while this property holds only the fact.
    ///
    /// **What this rewrite did not do is fix the three red tests it was written to explain**, and the
    /// claim that it did stood here until 2026-09-07. This comment asserted that the environment read
    /// made the guard read `false` inside every UI test, so `-resetGallery` stopped clearing the
    /// gallery, so `GalleryRecoveryUITests`' backup-restore and trash-restore and
    /// `EraserAndPersistenceUITests.testSaveAndReloadPersistsStrokesAcrossAppRelaunch` went red
    /// together. All three still failed after the rewrite, and `ProjectStorageUITests` — which uses
    /// the same flag — was passing throughout, which was already enough to refute it. The actual
    /// cause was in the test target and nowhere near this file: `ed7c8f4` gave the gallery button an
    /// explicit accessibility identifier, which replaced the implicit one two helpers were reaching
    /// it by. The lesson is CLAUDE.md's, reached by yet another door — **a story that explains the
    /// symptom is not evidence that it is the cause**, and this one was plausible enough to be
    /// written into the source as settled fact before anything tested it.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// **The policy `-resetGallery` is gated on, separated from the platform fact so it can be
    /// tested.** A destructive test hook runs only in a simulator: on a physical device the three
    /// directories it clears hold work nobody can regenerate, and on 2026-09-07 it destroyed the
    /// owner's library from a Release build on their own iPad.
    static func honoursGalleryReset(isSimulator: Bool) -> Bool { isSimulator }

    /// Runs once per launch (detached from `PaintApp.init`). Order matters: wipe for tests →
    /// test-corruption hook → stale temp cleanup → update snapshots → repair → purge. Every step
    /// is individually failure-proof (all `try?`); this pass must never crash the app it protects.
    static func runStartupMaintenance() {
        let args = ProcessInfo.processInfo.arguments

        // Launch-arg test hooks (never present in normal runs):
        //   -resetGallery               wipe Projects/Backups/Trash and the update signature
        //   -simulateProjectCorruption  overwrite the newest project's manifest.json with garbage,
        //                               simulating an update/crash-damaged package, so the repair
        //                               pass below can be observed fixing it end-to-end.
        // **`-resetGallery` is refused off the simulator, and that guard is not paranoia.** On
        // 2026-09-07 a measurement pass passed it to a *Release build on the owner's own iPad* for
        // run-to-run isolation and destroyed every saved project, backup and trashed item on the
        // device. The flag reads as a test hook and behaves as one everywhere it is normally seen,
        // which is exactly why nothing stopped it: a physical device is the one place where the
        // directories it wipes hold work nobody can regenerate. Brushes and recordings survived only
        // because they live outside the three directories it clears.
        //
        // The simulator check is the whole guard, deliberately: `#if DEBUG` would not have helped,
        // because the build that did the damage was Release, and a device UI test that genuinely
        // needs a clean gallery can delete and reinstall the app instead, which is both narrower and
        // reversible.
        if args.contains("-resetGallery") && Self.honoursGalleryReset(isSimulator: Self.isSimulator) {
            // **Put the library back inside the app before wiping anything** — TODO (36). The three
            // directories below are resolved through `ProjectLocation`, so on a device that had
            // adopted a folder in Files this flag would reach *outside* the container and delete the
            // artist's real library. Forgetting the bookmark first makes the wipe container-only by
            // construction, which is the same reasoning the simulator guard above is built on: this
            // flag must not be able to touch anything a reinstall could not.
            ProjectLocation.defaults.removeObject(forKey: ProjectLocation.bookmarkDefaultsKey)
            ProjectLocation.defaults.removeObject(forKey: ProjectLocation.displayNameDefaultsKey)
            ProjectLocation.defaults.removeObject(forKey: ProjectLocation.invitationDismissedDefaultsKey)
            ProjectLocation.resetForTesting()
            let fm = FileManager.default
            for dir in [projectsDirectory, backupsRootDirectory, trashDirectory] {
                try? fm.removeItem(at: dir)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            UserDefaults.standard.removeObject(forKey: signatureDefaultsKey)
        }
        if args.contains("-simulateProjectCorruption") {
            simulateNewestProjectCorruption()
        }

        cleanupStaleSaveDirectories()

        // App updated or redeployed? Snapshot every valid project BEFORE anything else can touch
        // them, so a bad update can never destroy the only copy of pre-update work.
        let signature = currentAppSignature
        if UserDefaults.standard.string(forKey: signatureDefaultsKey) != signature {
            snapshotAllProjectsForAppUpdate(signature: signature)
            UserDefaults.standard.set(signature, forKey: signatureDefaultsKey)
        }

        repairCorruptedProjects()

        // TODO (57): move each project's JSON sidecars out from under `images/`. **After the repair**
        // so a damaged package is restored before we look at it, and **before the purges** so nothing
        // is name-matched against a half-reconciled tree. It is idempotent, it never copies or
        // deletes, and a third run changes nothing — see `ProjectPackageLayout.tidy`.
        ProjectPackageLayout.tidyEveryProject()

        purgeExpiredTrash()
        pruneToSizeCap()
    }

    /// ProjectStore.save stages new packages at `.saving-*` before swapping; a crash between
    /// staging and swapping leaves one behind. It's not user data (the live package was never
    /// touched), so it's just clutter to remove.
    static func cleanupStaleSaveDirectories() {
        cleanupStaleSaveDirectories(in: projectsDirectory)
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
            guard !validateProject(at: url) else { continue }
            _ = restoreNewestValidBackup(forProjectAt: url, trashTag: "corrupt")
        }
    }

    // MARK: - App-update detection & snapshots

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
    static func snapshotAllProjectsForAppUpdate(signature: String) {
        let sig = sanitizedSignature(signature)
        for url in allProjectPackages() {
            guard validateProject(at: url), let id = manifestID(at: url) else { continue }
            let dir = backupsDirectory(projectID: id)
            writeOriginMarker(directory: dir, projectFileName: url.lastPathComponent)
            _ = cloneItem(at: url, to: uniqueSlotURL(directory: dir, prefix: "preupdate-\(sig)"))
            pruneSlots(directory: dir, prefix: "preupdate-", keep: maxPreUpdateBackupsPerProject)
        }
    }

    private static func sanitizedSignature(_ signature: String) -> String {
        String(signature.map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(40))
    }

    // MARK: - Save-time rotation

    /// Stashes the current on-disk package into a new timestamped autosave slot (a rename — free)
    /// and frees `projectURL` for the freshly staged package. Returns false only if the old package
    /// could neither be moved nor copied — in which case the caller must NOT clobber it.
    static func stashLiveProjectForSave(projectURL: URL, projectID: UUID) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectURL.path) else { return true }
        let dir = backupsDirectory(projectID: projectID)
        writeOriginMarker(directory: dir, projectFileName: projectURL.lastPathComponent)
        let slot = uniqueSlotURL(directory: dir, prefix: "auto")
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

    /// Count-rotation for one project's autosave, pre-update and unsaved-changes slots (`latest` is
    /// never rotated).
    static func pruneBackups(forProjectID id: UUID) {
        let dir = backupsDirectory(projectID: id)
        pruneSlots(directory: dir, prefix: "auto-", keep: maxAutosaveBackupsPerProject)
        pruneSlots(directory: dir, prefix: "preupdate-", keep: maxPreUpdateBackupsPerProject)
        pruneSlots(directory: dir, prefix: "unsaved-", keep: maxUnsavedBackupsPerProject)
    }

    private static func pruneSlots(directory: URL, prefix: String, keep: Int) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let slots = urls
            .filter { $0.pathExtension == "paintproj" && $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { slotDate($0) > slotDate($1) } // newest first
        for url in slots.dropFirst(max(keep, 0)) {
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
    /// back to the `origin.name` marker every backup folder carries.
    static func backupDirectory(forProjectAt projectURL: URL) -> URL? {
        let fm = FileManager.default
        if let id = manifestID(at: projectURL) {
            let dir = backupsRootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
            if fm.fileExists(atPath: dir.path) { return dir }
        }
        guard let dirs = try? fm.contentsOfDirectory(at: backupsRootDirectory, includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            guard let origin = try? String(contentsOf: dir.appendingPathComponent("origin.name"), encoding: .utf8),
                  origin == projectURL.lastPathComponent else { continue }
            return dir
        }
        return nil
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

    /// Restores a backup over the live package. The live package (damaged or just newer) is moved
    /// to Trash rather than deleted, so even a mistaken restore is itself recoverable. The backup
    /// is *cloned*, not moved, so the restore point survives. Refuses to restore a backup that
    /// itself fails validation.
    @discardableResult
    static func restoreBackup(at backupURL: URL, toProjectAt projectURL: URL, trashTag: String = "replaced") -> Bool {
        let fm = FileManager.default
        guard validateProject(at: backupURL) else { return false }
        if fm.fileExists(atPath: projectURL.path) {
            guard moveToTrash(projectURL, tag: trashTag) != nil else { return false }
        }
        return cloneItem(at: backupURL, to: projectURL)
    }

    /// The automatic-repair path: restores from the newest backup that itself passes validation.
    @discardableResult
    static func restoreNewestValidBackup(forProjectAt projectURL: URL, trashTag: String = "corrupt") -> Bool {
        for backup in listBackups(forProjectAt: projectURL) where backup.isValid {
            return restoreBackup(at: backup.url, toProjectAt: projectURL, trashTag: trashTag)
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
        } else {
            label = "Before save"
        }
        return ProjectBackup(url: url, label: label, date: slotDate(url), isLatest: isLatest, isValid: validateProject(at: url))
    }

    // MARK: - Trash

    struct TrashItem: Identifiable {
        let url: URL
        var id: String { url.lastPathComponent }
        let displayName: String
        let deletedAt: Date
        let sizeBytes: UInt64
    }

    /// Moves a package into Trash (never a hard delete). Returns the trash URL.
    @discardableResult
    static func moveToTrash(_ url: URL, tag: String) -> URL? {
        let fm = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = trashDirectory.appendingPathComponent("\(base)__\(tag)__\(timestampString()).paintproj")
        if fm.fileExists(atPath: candidate.path) {
            candidate = trashDirectory.appendingPathComponent("\(base)__\(tag)__\(timestampString())-\(UUID().uuidString.prefix(4)).paintproj")
        }
        return (try? fm.moveItem(at: url, to: candidate)).map { candidate }
    }

    static func listTrash() -> [TrashItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "paintproj" }.map { url in
            let parsed = parseTrashName(url.deletingPathExtension().lastPathComponent)
            return TrashItem(url: url,
                             displayName: parsed?.base ?? url.deletingPathExtension().lastPathComponent,
                             deletedAt: parsed?.date ?? fileDate(url),
                             sizeBytes: directorySize(url))
        }.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Moves a trashed package back into Projects under a non-colliding name. Returns the new URL.
    @discardableResult
    static func restoreFromTrash(_ trashURL: URL) -> URL? {
        let parsed = parseTrashName(trashURL.deletingPathExtension().lastPathComponent)
        let destination = uniqueProjectURL(baseName: parsed?.base ?? "Recovered")
        return (try? FileManager.default.moveItem(at: trashURL, to: destination)).map { destination }
    }

    /// Permanently destroys trash items older than `trashRetentionInterval`. When a trashed project
    /// is destroyed, its per-project backup history goes too — but only if no *live* project uses
    /// the same package name (the user may have created a new project with the same name meanwhile).
    static func purgeExpiredTrash(now: Date = Date()) {
        for item in listTrash() where now.timeIntervalSince(item.deletedAt) > trashRetentionInterval {
            let parsed = parseTrashName(item.url.deletingPathExtension().lastPathComponent)
            // Tree-wide since TODO (36): a one-level check would call a project filed inside
            // `Projects/Scene 3/` non-existent and destroy its whole backup history the moment a
            // same-named trash item expired.
            let liveExists = parsed.map { p in
                allProjectPackages().contains { $0.lastPathComponent == "\(p.base).paintproj" }
            } ?? true // parse failure -> assume live exists -> keep the backups (safe direction)
            if !liveExists, let base = parsed?.base {
                deleteBackupDirectories(whoseOriginIs: "\(base).paintproj")
            }
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    private static func deleteBackupDirectories(whoseOriginIs projectFileName: String) {
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: backupsRootDirectory, includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            guard let origin = try? String(contentsOf: dir.appendingPathComponent("origin.name"), encoding: .utf8),
                  origin == projectFileName else { continue }
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func uniqueProjectURL(baseName: String) -> URL {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : baseName
        var candidate = projectsDirectory.appendingPathComponent("\(base).paintproj")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = projectsDirectory.appendingPathComponent("\(base) \(suffix).paintproj")
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

        var remainingPerDir: [URL: Int] = [:]
        for c in candidates where c.backupDir != nil {
            remainingPerDir[c.backupDir!, default: 0] += 1
        }
        for c in candidates {
            guard total > maxTotalBackupBytes else { break }
            if let dir = c.backupDir {
                let left = remainingPerDir[dir] ?? 0
                let hasLatest = fm.fileExists(atPath: latestSnapshotURL(directory: dir).path)
                // Keep at least one slot when there's no `latest` to fall back on.
                if left <= 1 && !hasLatest { continue }
                remainingPerDir[dir] = left - 1
            }
            if (try? fm.removeItem(at: c.url)) != nil {
                total = total > c.size ? total - c.size : 0
            }
        }
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
            var fillImageFileName: String?
            var bakedImageFileName: String?
            var vectorFileName: String?
            /// Mirrors `CelManifest.animationFileName` — KEYFRAMES.md §3.5's *"add it to the
            /// validator on day one"*.
            ///
            /// **`interpolationFileName` is still not here, and that is the gap this key exists not
            /// to inherit.** §3.5 records it as real and existing: a cel whose recipe sidecar is
            /// missing validates today and the atomic save proceeds over it. Fixing that is a change
            /// to what the validator *rejects* on documents that already exist, which is not this
            /// stage's to make; adding this one costs nothing, because no package in the world yet
            /// names an animation file.
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
            /// **Still not decoded, and the gap is still real** — see `animationFileName` above. A cel
            /// whose recipe sidecar is missing validates today and the atomic save proceeds over it.
            /// (57) resolves this field's *address* through the same rule as the other two, which is
            /// why the accessor above knows about it; closing the validation gap is a change to what
            /// existing documents are called damaged for, and is not this item's to make.
            var interpolationFileName: String?
        }
    }

    private static let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// A project package counts as intact when its manifest decodes and every file the manifest
    /// references (raster/fill/baked PNGs, vector JSON) both exists and — for PNGs — starts with the
    /// 8-byte PNG signature (catches crash-truncated writes, not just missing files).
    static func validateProject(at url: URL) -> Bool {
        let fm = FileManager.default
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let skeleton = try? JSONDecoder().decode(ManifestSkeleton.self, from: data) else {
            return false
        }
        // **Resolved through `ProjectPackageLayout`, not joined to `images/`** — TODO (57). The
        // address of a sidecar is a question with one answer, and this is the third place that asks
        // it. Without this the validator would call a package mid-migration damaged — a file moved to
        // `drawings/` while the manifest still names it bare is *exactly* the state a crash between
        // the move and the manifest rewrite leaves — `repairCorruptedProjects` would restore over it,
        // and `tidy`'s own step-0 guard would refuse to finish the migration that would fix it.
        func fileIntact(_ name: String, isPNG: Bool, role: ProjectPackageLayout.Role, cel: UUID?) -> Bool {
            let fileURL = ProjectPackageLayout.existingURL(named: name, role: role, cel: cel, in: url)
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
           !fm.fileExists(atPath: url.appendingPathComponent(brushTable).path) { return false }

        for layer in skeleton.layers {
            for cel in layer.cels {
                // **Absent-because-omitted and absent-because-lost stay different states**, and
                // telling them apart is the entire job of this line. A cel that says `rasterOmitted`
                // never had a PNG and must validate; a cel that names one and cannot produce it is
                // damaged exactly as it always was — `BackupManagerLogicTests` pins both directions.
                if cel.rasterOmitted != true,
                   !fileIntact(cel.rasterFileName, isPNG: true, role: .raster, cel: cel.id) { return false }
                if let fill = cel.fillImageFileName,
                   !fileIntact(fill, isPNG: true, role: .fill, cel: cel.id) { return false }
                if let baked = cel.bakedImageFileName,
                   !fileIntact(baked, isPNG: true, role: .baked, cel: cel.id) { return false }
                if let vector = cel.vectorFileName,
                   !fileIntact(vector, isPNG: false, role: .drawing, cel: cel.id) { return false }
                if let animation = cel.animationFileName,
                   !fileIntact(animation, isPNG: false, role: .animation, cel: cel.id) { return false }
            }
        }
        return true
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

    private static func writeOriginMarker(directory: URL, projectFileName: String) {
        try? projectFileName.write(to: directory.appendingPathComponent("origin.name"), atomically: true, encoding: .utf8)
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

    private static func timestampFromName(_ name: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]{8}-[0-9]{6}"),
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

    private static func timestampString(_ date: Date = Date()) -> String {
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
        try? Data("corrupted".utf8).write(to: newest.appendingPathComponent("manifest.json"))
    }
}
