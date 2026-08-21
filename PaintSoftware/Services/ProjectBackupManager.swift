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

    static var documentsDirectory: URL {
        rootDirectoryOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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

    // MARK: - Launch-time maintenance

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
        if args.contains("-resetGallery") {
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
        purgeExpiredTrash()
        pruneToSizeCap()
    }

    /// ProjectStore.save stages new packages at `.saving-*` before swapping; a crash between
    /// staging and swapping leaves one behind. It's not user data (the live package was never
    /// touched), so it's just clutter to remove.
    static func cleanupStaleSaveDirectories() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.lastPathComponent.hasPrefix(".saving-") {
            try? fm.removeItem(at: url)
        }
    }

    /// Every project whose package fails validation gets auto-restored from its newest intact
    /// backup; the damaged package is moved to Trash (never destroyed silently). A damaged project
    /// with no backups is left in place — the gallery surfaces it as damaged instead of dropping it.
    static func repairCorruptedProjects() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "paintproj" {
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
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else { return }
        let sig = sanitizedSignature(signature)
        for url in urls where url.pathExtension == "paintproj" {
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
            let liveExists = parsed.map {
                FileManager.default.fileExists(atPath: projectsDirectory.appendingPathComponent("\($0.base).paintproj").path)
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
    private struct ManifestSkeleton: Decodable {
        var id: UUID
        var layers: [Layer]
        struct Layer: Decodable {
            var cels: [Cel]
        }
        struct Cel: Decodable {
            var rasterFileName: String
            var fillImageFileName: String?
            var bakedImageFileName: String?
            var vectorFileName: String?
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
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)

        func fileIntact(_ name: String, isPNG: Bool) -> Bool {
            let fileURL = imagesDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: fileURL.path) else { return false }
            guard isPNG else { return true }
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
            let head = try? handle.read(upToCount: pngMagic.count)
            try? handle.close()
            guard let head else { return false }
            return head.count == pngMagic.count && [UInt8](head) == pngMagic
        }

        for layer in skeleton.layers {
            for cel in layer.cels {
                if !fileIntact(cel.rasterFileName, isPNG: true) { return false }
                if let fill = cel.fillImageFileName, !fileIntact(fill, isPNG: true) { return false }
                if let baked = cel.bakedImageFileName, !fileIntact(baked, isPNG: true) { return false }
                if let vector = cel.vectorFileName, !fileIntact(vector, isPNG: false) { return false }
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
