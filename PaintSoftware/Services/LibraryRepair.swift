import Foundation
import os

/// **What every one-shot repair of the artist's library shares** — the walk over every package they
/// have, and the rewrite of one JSON file that leaves the package dated as it was.
///
/// TODO.md's rule: *"a format change ships with a one-shot repair that rewrites the owner's existing
/// files (Projects, Backups, Trash) to the new format at launch"*, deleted once the owner confirms. The one-shot
/// repairs use this — pose tracks, tools and masks — and it goes with the last
/// of them.
nonisolated enum LibraryRepair {
    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "LibraryRepair")

    /// The same one-shot repairs on an explicit restore’s staged copy. Update snapshots stay in the
    /// earlier format on purpose; repairing them in place would destroy the untouched recovery copy.
    /// No cel is rendered or eagerly loaded here: the current manifest is decoded as metadata, then
    /// the existing package validator checks every referenced file.
    static func prepareForCurrentRead(_ package: URL) -> Bool {
        let pose = LegacyPoseTrackRepair.repair(packageAt: package)
        guard pose.failed.isEmpty, pose.skippedKeys.isEmpty else { return false }
        // A fresh reader of the persisted library avoids reading the UI’s mutable brush store from
        // the startup maintenance queue. This is used only while the tool-settings repair exists.
        let earlier = LegacyToolSettingsRepair.EarlierAppWideTools(defaults: .standard,
                                                                  library: BrushLibraryStore(arguments: []))
        switch LegacyToolSettingsRepair.repair(packageAt: package, from: earlier) {
        case .alreadyCurrent, .repaired: break
        case .unreadable, .notWritten: return false
        }
        switch LegacyMaskRepair.repair(packageAt: package) {
        case .alreadyCurrent, .repaired: break
        case .unreadable, .notWritten: return false
        }
        // Stream-placement repair joins this sequence at integration, before current validation.
        do {
            let data = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
            _ = try JSONDecoder().decode(ProjectManifest.self, from: data)
        } catch {
            log.error("Restored scene cannot be read: \(String(describing: error), privacy: .public)")
            return false
        }
        return ProjectBackupManager.validateProject(at: package)
    }


    /// One package of the library, and its path below the library root for a report.
    struct Package {
        let url: URL
        let path: String
    }

    /// Every package under `Projects/`, `Backups/` and `Trash/` of the library root — the saved
    /// versions are where an artist's earlier work still is — except the slots whose names start with
    /// `untouchedPrefix`: the running build's own update snapshot, which keeps the files as they were.
    static func packages(leavingUntouched untouchedPrefix: String?) -> [Package] {
        let root = ProjectBackupManager.documentsDirectory
        let rootComponents = root.standardizedFileURL.pathComponents
        return ["Projects", "Backups", "Trash"].flatMap { directory in
            ProjectBackupManager.allProjectPackages(in: root.appendingPathComponent(directory, isDirectory: true))
        }
        .filter { package in untouchedPrefix.map { !package.lastPathComponent.hasPrefix($0) } ?? true }
        .map { url in
            Package(url: url, path: url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count)
                .joined(separator: "/"))
        }
    }

    /// Writes `object` as `url`'s JSON, atomically. False when it could not be written.
    static func write(_ object: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Runs `rewrite` over `package` and, when it changed something, dates the package as it was: a
    /// saved version without a timestamp in its name is dated by its folder, which the rewrite touched.
    static func keepingItsDate(_ package: URL, _ rewrite: () -> Bool) {
        let modified = (try? FileManager.default.attributesOfItem(atPath: package.path))?[.modificationDate] as? Date
        guard rewrite(), let modified else { return }
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: package.path)
    }
}
