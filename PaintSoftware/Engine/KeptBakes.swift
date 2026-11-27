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
/// ## Where they live, and what follows the package
///
/// `<package>/bakes/<resolution>/<token>/<frame>.pbk` — **inside the scene's own package** (owner
/// ruling, 2026-11-26), so a share, an AirDrop, a backup, a duplicate and a trash move carry them
/// without any code of their own, and the artist accepts that those grow by the bakes. A save rebuilds
/// the package through a staging folder that has no `bakes/`, then promotes the new set into the landed
/// package, so a package never holds more than the one set for its newest manifest. A copy of a package
/// (a duplicate gets a new manifest, and so a new token) holds a set no manifest asks for: the launch
/// pass sweeps it. The whole library obeys the disk limit (`BakeDiskLimit`).

nonisolated enum KeptBakes {

    static let folderName = "bakes"

    /// A kept file's extension: the working store's own format, named by frame.
    private static let fileExtension = "pbk"

    // MARK: - Where

    /// Where the kept frames of `package` live, for one render resolution.
    static func root(package: URL, renderResolution: RenderResolution) -> URL {
        package.appendingPathComponent(folderName, isDirectory: true)
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

    /// The launch pass over every package in the library. With the option **off** every package's
    /// `bakes/` goes — the setting means a scene holds none, including ones it was given inside a
    /// package it was sent or restored from. With it **on**, what no manifest asks for goes (a set for
    /// an older save, a duplicate's copy, an abandoned build), and the rest is trimmed to `limit` bytes
    /// in all, the least recently written package's first.
    static func launchPass(packages: [URL], keeping: Bool, limit: Int) {
        let fm = FileManager.default
        var survivors: [(url: URL, modified: Date, bytes: Int)] = []
        for package in packages {
            let folder = package.appendingPathComponent(folderName, isDirectory: true)
            guard fm.fileExists(atPath: folder.path) else { continue }
            guard keeping else {
                try? fm.removeItem(at: folder)
                continue
            }
            let token = token(ofPackageAt: package)
            for resolution in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                for set in (try? fm.contentsOfDirectory(at: resolution, includingPropertiesForKeys: nil)) ?? []
                where set.lastPathComponent != token {
                    try? fm.removeItem(at: set)
                }
            }
            let bytes = directorySize(folder)
            guard bytes > 0 else {
                try? fm.removeItem(at: folder)
                continue
            }
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            survivors.append((folder, modified, bytes))
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
}

/// What a save hands `KeptBakes.promote`: frozen on the main actor with the scene, used on the save queue.
struct KeptBakeSnapshot {
    let frames: [(frame: Int, source: URL)]
    let playhead: Int
    let renderResolution: RenderResolution
    let limit: Int
}
