import Foundation

/// **Free disk on Apple platforms** — `volumeAvailableCapacityForImportantUsage`, which counts space
/// the system will purge (its own caches) as free, the number an app is told it may use.
struct AppleDisk: DiskSpace {
    func freeBytes(at url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int(free)
    }
}
