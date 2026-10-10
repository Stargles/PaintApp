import Foundation

/// **Which of a scene's saved versions to keep — decided by age, and by nothing else.**
///
/// The schedule is the grandfather–father–son thinning backup tools use: the newest few versions
/// are always kept, and beyond them the clock is cut into fixed slots — ten minutes wide for the
/// last hour, an hour wide for the last day, a day wide for the last week, a week wide for the last
/// month — and the **oldest** version in each slot survives. Everything else goes. A scene that is
/// worked on every day ends up with at most 44 versions (3 + 6 + 24 + 7 + 4) however many saves it
/// has had, and they are spread over a month instead of piled up in the last few minutes.
///
/// **Why the oldest in a slot, not the newest.** A version here is the state a scene was in *before*
/// a save, so the oldest version in a slot is the state the slot began with. A run of bad saves
/// cannot rotate that out: the 2026-10-10 build that read the owner's scene wrong and autosaved
/// minted five versions in nine minutes, and keeping the newest of those would have thrown away the
/// one good copy, which is the first of them, as soon as a fourth arrived. The newest versions are
/// still kept — that is what the first three are for.
///
/// **Slots are fixed stretches of the clock, not windows that slide with `now`.** A sliding window
/// re-decides every minute who is the survivor, so a stream of saves never lets anything graduate
/// into the next band; a fixed slot settles the moment its first version arrives and stays settled.
/// Slot boundaries are multiples of their width since the epoch, which needs no calendar, time zone
/// or daylight-saving rule, and nobody ever sees them.
///
/// **A date after `now` counts as now.** A clock that was wrong when a version was minted must not
/// make that version the newest forever, or crowd the genuine ones out of the newest three.
///
/// Pure Foundation, so it compiles into the UI-test bundle beside `ProjectBackupManager`, which
/// applies it to the files on disk.
nonisolated enum VersionRetention {

    /// One band of the schedule: the last `count` slots, each `width` seconds of the clock wide.
    struct Band: Equatable {
        let width: TimeInterval
        let count: Int
    }

    /// The newest versions kept whatever their age or their slot.
    static let newestKept = 3

    /// Finest first. The bands overlap on purpose: a version the ten-minute band lets go of is still
    /// the oldest of its hour, or its day, or its week, or it is nothing special and goes.
    static let bands = [
        Band(width: 10 * 60, count: 6),              // the last hour
        Band(width: 60 * 60, count: 24),             // the last day
        Band(width: 24 * 60 * 60, count: 7),         // the last week
        Band(width: 7 * 24 * 60 * 60, count: 4),     // the last month
    ]

    struct Version: Equatable {
        /// Names the version to its caller; also orders versions of the same instant, numerically
        /// ("…-2" before "…-10"), so a burst inside one second still has an oldest.
        let id: String
        let date: Date
    }

    /// The ids of the versions to keep. Anything not in the result is to be deleted.
    static func keep(_ versions: [Version], now: Date) -> Set<String> {
        let ordered = versions
            .map { (version: $0, date: min($0.date, now)) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.version.id.compare(rhs.version.id, options: .numeric) == .orderedAscending
            } // oldest first

        var kept = Set(ordered.suffix(newestKept).map(\.version.id))
        for band in bands {
            let current = slot(of: now, width: band.width)
            var filled = Set<Int>()
            for entry in ordered {
                let index = slot(of: entry.date, width: band.width)
                guard current - index < band.count, filled.insert(index).inserted else { continue }
                kept.insert(entry.version.id)
            }
        }
        return kept
    }

    private static func slot(of date: Date, width: TimeInterval) -> Int {
        Int((date.timeIntervalSince1970 / width).rounded(.down))
    }
}
