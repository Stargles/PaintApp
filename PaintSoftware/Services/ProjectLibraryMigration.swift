import Foundation

/// **Moves the whole library from one root to another without a window in which anything is only
/// half-somewhere** — TODO (36)'s third bullet, and the half where a mistake costs the artwork this
/// feature exists to protect.
///
/// ## The invariant
///
/// *At every instant, every project exists **complete** in at least one of the two roots.*
///
/// That is stronger than "the migration succeeds", and it is the only property worth engineering for,
/// because the process can die at any line: a jetsam kill, a crash, the artist swiping the app away
/// mid-copy. `moveItem` cannot provide it across volumes — a cross-volume move is a copy and a delete
/// with no atomicity between them, and the chosen folder is on a different volume by construction
/// (that is the entire point of choosing it). So this is **copy, verify, then remove**, one item at a
/// time, and the removal of an item's source is the *last* thing that happens to that item.
///
/// ## What each failure leaves behind
///
/// | killed during | destination | source | next run |
/// |---|---|---|---|
/// | `copyItem` | a partial `.migrating-<uuid>` | untouched | the husk is swept, the item copied again |
/// | verify | a complete `.migrating-<uuid>` | untouched | same |
/// | the rename into place | either the staged name or the final one; both complete | untouched | if final, verified and the source removed; if staged, swept and re-copied |
/// | `removeItem(source)` | complete | possibly partial | the destination is live and correct; the container husk is what a reinstall deletes anyway |
///
/// There is no row in which an item is incomplete in both roots, which is the invariant. The worst
/// outcome is a **duplicate**, never a loss — chosen deliberately, because a duplicate is visible in
/// the gallery and a loss is not.
///
/// ## Why staging under `.migrating-` rather than copying straight to the final name
///
/// A partial directory sitting at `Sequence 1.paintproj` is indistinguishable from a damaged project,
/// and `ProjectBackupManager.repairCorruptedProjects` would find it at the next launch and start
/// restoring backups over a copy that was merely unfinished. Staging under a name nothing else looks
/// at, and renaming *within the destination directory* (which is atomic — same volume, same
/// directory), means the final name never exists in an incomplete state.
///
/// ## Verification
///
/// A copy is accepted when the destination holds the same number of files as the source and the same
/// total bytes, and — for a `.paintproj` — when `ProjectBackupManager.validateProject` passes on the
/// **copy**. The byte total is what catches a truncated write; the validator is what catches a
/// package that was already damaged before the move, which is not this pass's to repair but is very
/// much its business not to advertise as migrated.
///
/// Pure Foundation, so it compiles into the UI-test bundle like `ProjectBackupManager`.
nonisolated enum ProjectLibraryMigration {

    /// The three top-level directories that make up a library. `Projects` is the artwork; `Backups`
    /// and `Trash` are the two things standing between the artist and a bad save, so they travel too
    /// — a relocation that left the safety net in the container would quietly halve the protection
    /// on the very files it was moving.
    static let subdirectories = ["Projects", "Backups", "Trash"]

    /// Prefix for a staged, not-yet-verified copy. Nothing else in the app looks at names starting
    /// with a dot inside these directories, and `ProjectStore.listProjects` filters on the
    /// `.paintproj` extension, so a husk is invisible to the gallery even before it is swept.
    static let stagingPrefix = ".migrating-"

    struct Report: Equatable {
        /// Items whose copy verified and whose source was removed.
        var moved: [String] = []
        /// Items already present at the destination under the same name with matching contents — a
        /// previous interrupted run's work, adopted rather than repeated.
        var alreadyThere: [String] = []
        /// Items whose copy could not be verified. Their sources were **left alone**.
        var failed: [String] = []
        /// Items copied under a different name because the destination already held something
        /// different by that name. Never a clobber.
        var renamed: [String] = []

        var isEmpty: Bool { moved.isEmpty && alreadyThere.isEmpty && failed.isEmpty && renamed.isEmpty }
        static let empty = Report()

        /// One sentence for the artist, or nil when there is nothing to say.
        var summary: String? {
            if isEmpty { return nil }
            var parts: [String] = []
            let carried = moved.count + alreadyThere.count + renamed.count
            if carried > 0 { parts.append("Moved \(carried) item\(carried == 1 ? "" : "s") into the new folder.") }
            if !renamed.isEmpty {
                parts.append("\(renamed.count) had to be renamed because the folder already held "
                             + "something by that name.")
            }
            if !failed.isEmpty {
                parts.append("\(failed.count) could not be copied and " +
                             "\(failed.count == 1 ? "was" : "were") left where "
                             + "\(failed.count == 1 ? "it" : "they") \(failed.count == 1 ? "was" : "were"): "
                             + failed.sorted().joined(separator: ", ") + ".")
            }
            return parts.joined(separator: " ")
        }
    }

    /// Copies every library item from `source` to `destination`, verifying each before removing it
    /// from the source. Never throws: a migration that gives up halfway must leave the artist with a
    /// working app and a report, not an alert about an `NSError`.
    static func migrate(from source: URL, to destination: URL) -> Report {
        var report = Report()
        let fm = FileManager.default
        for sub in subdirectories {
            let sourceDir = source.appendingPathComponent(sub, isDirectory: true)
            guard fm.fileExists(atPath: sourceDir.path) else { continue }
            let destinationDir = destination.appendingPathComponent(sub, isDirectory: true)
            try? fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            sweepStaging(in: destinationDir)
            guard let items = try? fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                migrateItem(item, into: destinationDir, sub: sub, report: &report)
            }
        }
        return report
    }

    // MARK: - One item

    private static func migrateItem(_ item: URL, into destinationDir: URL, sub: String,
                                    report: inout Report) {
        let fm = FileManager.default
        let name = item.lastPathComponent
        // A staged husk left by an interrupted run in the *source* is not artwork; do not carry it.
        guard !name.hasPrefix(stagingPrefix), !name.hasPrefix(".saving-") else {
            try? fm.removeItem(at: item)
            return
        }
        let label = "\(sub)/\(name)"

        var target = destinationDir.appendingPathComponent(name)
        var wasRenamed = false
        if fm.fileExists(atPath: target.path) {
            if matches(source: item, destination: target) {
                // A previous run copied this and died before removing the source. Finish its job.
                if (try? fm.removeItem(at: item)) != nil { report.alreadyThere.append(label) }
                else { report.failed.append(label) }
                return
            }
            target = uniqueURL(in: destinationDir, basedOn: name)
            wasRenamed = true
        }

        let staged = destinationDir.appendingPathComponent(stagingPrefix + UUID().uuidString,
                                                           isDirectory: true)
        guard (try? fm.copyItem(at: item, to: staged)) != nil else {
            try? fm.removeItem(at: staged)
            report.failed.append(label)
            return
        }
        guard matches(source: item, destination: staged),
              !isPackage(item) || ProjectBackupManager.validateProject(at: staged) else {
            try? fm.removeItem(at: staged)
            report.failed.append(label)
            return
        }
        guard (try? fm.moveItem(at: staged, to: target)) != nil else {
            try? fm.removeItem(at: staged)
            report.failed.append(label)
            return
        }
        // Only now, with a complete verified copy at its final name, is the source expendable.
        try? fm.removeItem(at: item)
        if wasRenamed { report.renamed.append(label) } else { report.moved.append(label) }
    }

    private static func isPackage(_ url: URL) -> Bool { url.pathExtension == "paintproj" }

    /// Removes staged husks a previous interrupted run left behind. Safe by construction: nothing
    /// but this file ever writes a name with that prefix, and a husk is by definition a copy whose
    /// source was still intact when it was abandoned.
    static func sweepStaging(in directory: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasPrefix(stagingPrefix) {
            try? fm.removeItem(at: item)
        }
    }

    // MARK: - Verification

    /// File count and total bytes, walked recursively without descending into nothing — a
    /// `.paintproj` **is** a directory, so this walks straight through it, which is what makes the
    /// comparison meaningful for a package as well as for a folder of them.
    struct Census: Equatable {
        var files = 0
        var bytes: UInt64 = 0
    }

    static func census(of url: URL) -> Census {
        let fm = FileManager.default
        var out = Census()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return out }
        if !isDirectory.boolValue {
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? nil
            out.files = 1
            out.bytes = size ?? 0
            return out
        }
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return out }
        for item in items {
            let sub = census(of: item)
            out.files += sub.files
            out.bytes += sub.bytes
        }
        return out
    }

    /// Whether `destination` is a faithful copy of `source`. Same file count and same total bytes.
    ///
    /// **Not a byte-for-byte content compare, and that is a measured trade rather than a shortcut**:
    /// a real library is hundreds of megabytes of PNG, and hashing it doubles a migration the artist
    /// is watching. What this catches is the failure that actually happens — a copy cut short by a
    /// kill or a full disk, which loses whole files or truncates the one in flight, and moves the
    /// total. What it would miss is a copy that silently altered a byte in place, which APFS does not
    /// do. `validateProject` runs on top of this for packages, which re-reads every PNG header.
    static func matches(source: URL, destination: URL) -> Bool {
        let a = census(of: source)
        guard a.files > 0 else { return census(of: destination).files == 0 }
        return a == census(of: destination)
    }

    private static func uniqueURL(in directory: URL, basedOn name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var suffix = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            let url = directory.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            suffix += 1
        }
    }
}
