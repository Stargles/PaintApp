import Foundation

/// **How much free disk the machine has** — the one platform fact the bake's limit needs, behind a
/// seam so the engine asks a question and a test (or another OS) answers it.
nonisolated protocol DiskSpace: Sendable {
    /// Bytes an app may still write on the volume holding `url`, or nil when the volume cannot say.
    func freeBytes(at url: URL) -> Int?
}

/// **The disk limit for baked frames** — SCHEDULER_DESIGN.md §3 (d): `min(4 GiB, 10% of free disk)`,
/// and always 2 GiB left free. Read from the machine when a store opens and again when a write
/// fails, never assumed: the figures here are the policy, the disk is the input.
///
/// "Free disk" is what the volume has plus what this store already holds, so the limit does not
/// shrink as the bakes it counts fill the volume. Below the reserve the limit is 0: no bake is
/// written and the canvas draws from its layers as it did before there was a bake, which is a slower
/// canvas and never a wrong or a missing one.
nonisolated enum BakeDiskLimit {

    static let cap = 4 * 1024 * 1024 * 1024
    static let fractionDivisor = 10
    static let reserve = 2 * 1024 * 1024 * 1024

    /// The limit for a volume with `capacity` bytes available to bakes (free plus already held).
    static func bytes(capacity: Int) -> Int {
        guard capacity > reserve else { return 0 }
        return min(cap, capacity / fractionDivisor, capacity - reserve)
    }

    /// Who answers "how much is free". The app's is `AppleDisk`; a test substitutes a fixed answer
    /// and restores it.
    nonisolated(unsafe) static var disk: DiskSpace = AppleDisk()

    /// Capacity as read now: what the volume has free plus `held`. Nil when the volume cannot say —
    /// the caller then keeps the figure it had, or, with none, assumes the cap.
    static func capacity(at url: URL, held: Int) -> Int? {
        disk.freeBytes(at: existingAncestor(of: url)).map { $0 + held }
    }

    /// A directory that exists, at or above `url`: a root not yet created still lives on a volume.
    private static func existingAncestor(of url: URL) -> URL {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }
}
