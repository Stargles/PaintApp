import Foundation
import CryptoKit

/// **Bake files kept between launches** (SCHEDULER_DESIGN.md §7, owner ruling Q2) — the option
/// "Keep baked frames between launches", off by default.
///
/// ## Why a kept bake is not a bake key's file
///
/// A `FrameBakeKey` names a picture by the identities of the pieces in memory (`LayerContentVersion`'s
/// `residencyID` is a `UUID()` per object, its versions count from zero at every open), so a key means
/// nothing in the next launch and a file named by one is never asked for again. What survives a launch
/// is the saved package. A kept bake is therefore filed **by frame number under a token of the package it
/// depicts** — `<root>/<token>/<frame>.pbk` — and the baker adopts one only for a frame nothing has
/// touched since that package was opened (`FrameBaker.adopt`).
///
/// - **The token** is the SHA-256 of the package's `manifest.json`, which every save rewrites, so any
///   change to the saved scene is a new token and the old set is never read for it.
/// - **A save promotes**: the frames the baker holds clean at the moment the scene was frozen are cloned
///   (`clonefile`, copy-on-write — no second copy of the bytes on APFS) into `<root>/<new token>/`, and
///   every other token's set is deleted.
/// - **An open adopts**: a kept file is cloned to the name the new session's key gives it and its header
///   digest is rewritten to match; from there it is an ordinary bake file in the working store.
///
/// ## Where they live, and what they never do
///
/// `<Projects>/.bakes.nosync/<projectID>/<resolution>/` — in the same library as the packages (so they
/// travel with it), **never inside a package**: a save rebuilds the package through a staging folder, a
/// backup or a trash move clones or moves the whole package, and a package shared or exported from Files
/// is the folder itself, so a bake inside would be copied into every one of them. The name is dotted, so
/// the gallery lists no folder for it; `.nosync`, so iCloud Drive does not upload it; and it is excluded
/// from backup. A duplicate gets a new project ID and so no bakes (they are rebuilt, not copied); a
/// rename or a move between gallery folders keeps the ID and so keeps them; a trashed project's are
/// swept at the next launch. The whole folder obeys the disk limit (`BakeDiskLimit`).
nonisolated enum KeptBakes {

    static let folderName = ".bakes.nosync"

    /// A kept file's extension: the working store's own format, named by frame.
    private static let fileExtension = "pbk"

    // MARK: - Where

    static func folder(in projectsDirectory: URL) -> URL {
        projectsDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    static func root(projectsDirectory: URL, projectID: UUID, renderResolution: RenderResolution) -> URL {
        folder(in: projectsDirectory)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(renderResolution.rawValue, isDirectory: true)
    }

    /// The token of the package at `packageURL`: the first 16 bytes of the SHA-256 of its manifest, as
    /// hex. Nil when the package has no readable manifest.
    static func token(ofPackageAt packageURL: URL) -> String? {
        guard let manifest = try? Data(contentsOf: packageURL.appendingPathComponent("manifest.json")) else { return nil }
        return SHA256.hash(data: manifest).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileURL(_ frame: Int, root: URL, token: String) -> URL {
        root.appendingPathComponent(token, isDirectory: true)
            .appendingPathComponent("\(frame).\(fileExtension)", isDirectory: false)
    }

    // MARK: - Adopting

    /// The frames kept for `token` — the set an open may adopt from.
    static func frames(in root: URL, token: String) -> Set<Int> {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(token, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
        return Set(names.filter { $0.pathExtension == fileExtension }
            .compactMap { Int($0.deletingPathExtension().lastPathComponent) })
    }

    /// Makes `destination` a bake file for `digest` out of frame `frame`'s kept file, and answers its
    /// size — nil when the kept file is missing or is not a file this build wrote (a format change reads
    /// as a miss: the frame is baked again). A clone first, so the kept copy is never written to; the
    /// header's digest is then rewritten to name the session's key, which is the whole of the change.
    static func adopt(frame: Int, root: URL, token: String, into destination: URL, digest: Data) -> Int? {
        let source = fileURL(frame, root: root, token: token)
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path), digest.count == 32 else { return nil }
        try? fm.removeItem(at: destination)
        guard clone(source, to: destination) else { return nil }
        do {
            let handle = try FileHandle(forUpdating: destination)
            defer { try? handle.close() }
            guard let head = try handle.read(upToCount: FrameBakeStore.headerBytes), BakeFile.Header.parse(head) != nil else {
                try? fm.removeItem(at: destination)
                return nil
            }
            try handle.seek(toOffset: 32)
            try handle.write(contentsOf: digest)
        } catch {
            try? fm.removeItem(at: destination)
            return nil
        }
        return (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    // MARK: - Promoting

    /// Replaces the kept set with `frames` as they are on disk now, filed under `token`, nearest the
    /// playhead first and no more than `limit` bytes in all. Every other token's set goes — the set
    /// depicts one saved package. Built beside and renamed into place, so a crash leaves the old set
    /// or the new one, never half. Answers how many frames were kept.
    @discardableResult
    static func promote(_ frames: [(frame: Int, source: URL)], playhead: Int, root: URL, token: String, limit: Int) -> Int {
        let fm = FileManager.default
        let building = root.appendingPathComponent(token + ".building", isDirectory: true)
        let final = root.appendingPathComponent(token, isDirectory: true)
        try? fm.removeItem(at: building)
        do { try fm.createDirectory(at: building, withIntermediateDirectories: true) } catch { return 0 }
        excludeFromBackup(folder: root.deletingLastPathComponent().deletingLastPathComponent())
        var kept = 0, bytes = 0
        for (frame, source) in frames.sorted(by: { abs($0.frame - playhead) < abs($1.frame - playhead) }) {
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size > 0, bytes + size <= limit else { continue }
            let destination = building.appendingPathComponent("\(frame).\(fileExtension)", isDirectory: false)
            guard clone(source, to: destination) else { continue }
            kept += 1
            bytes += size
        }
        // Everything else under the root goes: other tokens (older saves) and any abandoned build.
        for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where item.lastPathComponent != building.lastPathComponent {
            try? fm.removeItem(at: item)
        }
        if kept == 0 {
            try? fm.removeItem(at: building)
            return 0
        }
        guard (try? fm.moveItem(at: building, to: final)) != nil else {
            try? fm.removeItem(at: building)
            return 0
        }
        return kept
    }

    // MARK: - Launch

    /// The launch pass. With the option off the whole folder goes (the bake is emptied at launch, as it
    /// always was). With it on, a folder whose project has no package any more (trashed, or deleted)
    /// goes, and the rest is trimmed to `limit` bytes, least recently written project first.
    /// `liveProjectIDs` is read by the caller, which knows how to walk the library.
    static func launchPass(projectsDirectory: URL, keeping: Bool, liveProjectIDs: () -> Set<UUID>, limit: Int) {
        let fm = FileManager.default
        let folder = folder(in: projectsDirectory)
        guard fm.fileExists(atPath: folder.path) else { return }
        guard keeping else {
            try? fm.removeItem(at: folder)
            return
        }
        let live = liveProjectIDs()
        var survivors: [(url: URL, modified: Date, bytes: Int)] = []
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            guard let id = UUID(uuidString: item.lastPathComponent), live.contains(id) else {
                try? fm.removeItem(at: item)
                continue
            }
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            survivors.append((item, modified, directorySize(item)))
        }
        var total = survivors.reduce(0) { $0 + $1.bytes }
        for oldest in survivors.sorted(by: { $0.modified < $1.modified }) where total > limit {
            try? fm.removeItem(at: oldest.url)
            total -= oldest.bytes
        }
    }

    // MARK: - Files

    private static func clone(_ source: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        let status: Int32 = source.withUnsafeFileSystemRepresentation { s in
            destination.withUnsafeFileSystemRepresentation { d in
                guard let s, let d else { return -1 }
                return clonefile(s, d, 0)
            }
        }
        if status == 0 { return true }
        return (try? fm.copyItem(at: source, to: destination)) != nil
    }

    private static func directorySize(_ url: URL) -> Int {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return walker.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)
    }

    /// Bakes are a cache: nothing here is worth a backup's space.
    private static func excludeFromBackup(folder: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        try? url.setResourceValues(values)
    }
}
