import Foundation

/// **The machine's cores, read from it** — the one file in the scheduler's seam that reads `sysctl`.
///
/// Apple silicon names its performance levels: `hw.perflevel0` is the fast cores and `hw.perflevel1`
/// the efficient ones (the A13 in the minimum iPad 9: 2 and 4). A machine without levels reports all
/// its active cores as fast.
struct AppleMachine: Machine {
    let fastCores: Int
    let efficientCores: Int

    init() {
        let fast = Self.sysctlInt("hw.perflevel0.physicalcpu")
        let efficient = Self.sysctlInt("hw.perflevel1.physicalcpu")
        if let fast, fast > 0 {
            fastCores = fast
            efficientCores = max(0, efficient ?? 0)
        } else {
            fastCores = max(1, Self.sysctlInt("hw.activecpu") ?? 1)
            efficientCores = 0
        }
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
