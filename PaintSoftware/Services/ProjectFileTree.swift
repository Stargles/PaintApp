import Foundation

/// Strict filesystem reads used before deleting library data. Unknown or linked entries are not
/// empty files/directories; callers preserve them when their identity cannot be established.
nonisolated enum ProjectFileTree {
    enum Entry: Equatable {
        case directory
        case file(bytes: UInt64)
    }

    enum ReadError: Error {
        case unsupportedEntry(URL)
    }

    static func entry(at url: URL) throws -> Entry {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [
            .isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey
        ])
        guard values.isSymbolicLink == false else { throw ReadError.unsupportedEntry(url) }
        if values.isDirectory == true { return .directory }
        guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else {
            throw ReadError.unsupportedEntry(url)
        }
        return .file(bytes: UInt64(size))
    }

    static func children(of directory: URL) throws -> [URL] {
        guard try entry(at: directory) == .directory else {
            throw ReadError.unsupportedEntry(directory)
        }
        return try FileManager.default.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: nil)
    }

    /// Exact tree/content identity, including empty directories, with at most two 64 KiB file
    /// buffers. Aggregate sizes alone cannot establish that an existing destination is our copy.
    static func matches(source: URL, destination: URL) throws -> Bool {
        let sourceEntry = try entry(at: source)
        guard sourceEntry == (try entry(at: destination)) else { return false }
        switch sourceEntry {
        case .directory:
            let sourceChildren = try children(of: source)
            let destinationChildren = try children(of: destination)
            let names = Set(sourceChildren.map(\.lastPathComponent))
            guard names == Set(destinationChildren.map(\.lastPathComponent)) else { return false }
            for child in sourceChildren {
                guard try matches(source: child,
                                  destination: destination.appendingPathComponent(child.lastPathComponent)) else {
                    return false
                }
            }
            return true
        case .file:
            let first = try FileHandle(forReadingFrom: source)
            defer { try? first.close() }
            let second = try FileHandle(forReadingFrom: destination)
            defer { try? second.close() }
            while true {
                let a = try first.read(upToCount: 64 * 1024) ?? Data()
                let b = try second.read(upToCount: 64 * 1024) ?? Data()
                guard a == b else { return false }
                if a.isEmpty { return true }
            }
        }
    }
}
