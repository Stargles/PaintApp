import CoreGraphics
import Foundation

/// A stroke sample that also knows *when* it was made.
///
/// A separate type from `VectorSample`, decided in `PLAN.md` §6.3 and worth restating because the
/// temptation to unify them is constant: `VectorSample` is in every saved project and on the hot
/// path, so adding a timestamp to it would mean a `Codable` migration on the most numerous type in
/// the format plus eight bytes on every sample of every ordinary stroke, for a field only guides
/// read. Guides are not stamped by `BrushStamper` at all — they draw as a thin overlay path — so
/// they share none of that hot path and gain nothing from sharing its type.
struct TimedSample: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var pressure: CGFloat

    /// Seconds since the first sample of the gesture. Relative rather than absolute so a guide means
    /// the same thing after a save/load, and because only the *shape* of the timing matters — it is
    /// normalised into a spacing curve.
    ///
    /// `UITouch.timestamp` already carries this at the recogniser; it is simply discarded today.
    var time: TimeInterval

    var point: CGPoint { CGPoint(x: x, y: y) }

    init(x: CGFloat, y: CGFloat, pressure: CGFloat, time: TimeInterval) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.time = time
    }

    init(point: CGPoint, pressure: CGFloat, time: TimeInterval) {
        self.init(x: point.x, y: point.y, pressure: pressure, time: time)
    }
}

/// Which of a guide's two signals are in play.
///
/// One gesture carries both — the path is a trajectory constraint, the stylus velocity along it is a
/// spacing function (`PLAN.md` §6.1) — and they are independently useful, so which ones apply is a
/// property of the guide rather than something inferred.
enum GuideRole: String, Codable {
    case trajectory
    case timing
    case both
}

/// The keyframe span a guide was authored against.
///
/// Scopes the guide library ("which guides were drawn on this interval") rather than binding a guide
/// to a recipe — that binding runs the other way, from the recipe's `guideIDs`, which is what makes
/// requirement 7's reuse across frames a reference and not a copy (`PLAN.md` §6.4).
struct KeyframeInterval: Codable, Equatable, Hashable {
    var start: CelRef
    var end: CelRef

    init(start: CelRef, end: CelRef) {
        self.start = start
        self.end = end
    }
}

/// A path the artist draws to say how the motion should arc, and how it should be spaced in time.
///
/// Document-level, not cel content — the same choice as `MotionGroup` and for the same reason: a
/// guide is meant to be reusable across frames and across a whole cycle, so recipes reference it by
/// id. It is invisible outside interpolate mode.
struct GuideStroke: Identifiable, Codable, Equatable {

    var id: UUID = UUID()

    /// The path, with stylus timing. Geometry gives the trajectory; arc length travelled per unit
    /// stylus time gives the easing, which is the part of the brief's idea that gets ease-out for
    /// free with no graph editor. Deriving a `SpacingCurve` from that timing is the evaluator's job,
    /// not this type's — see `IMPLEMENTATION.md` Phase 7.
    var samples: [TimedSample]

    var interval: KeyframeInterval

    /// The motion groups this guide drives. **Empty means every group** — the whole-frame binding of
    /// `PLAN.md` §10 decision 6, which costs nothing precisely because the binding is a set of ids.
    var boundGroups: [UUID]

    var role: GuideRole = .both

    init(id: UUID = UUID(), samples: [TimedSample] = [], interval: KeyframeInterval,
         boundGroups: [UUID] = [], role: GuideRole = .both) {
        self.id = id
        self.samples = samples
        self.interval = interval
        self.boundGroups = boundGroups
        self.role = role
    }

    private enum CodingKeys: String, CodingKey {
        case id, samples, interval, boundGroups, role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        samples = try c.decodeIfPresent([TimedSample].self, forKey: .samples) ?? []
        interval = try c.decode(KeyframeInterval.self, forKey: .interval)
        boundGroups = try c.decodeIfPresent([UUID].self, forKey: .boundGroups) ?? []
        role = try c.decodeIfPresent(GuideRole.self, forKey: .role) ?? .both
    }

    /// True when this guide drives `groupID` — either by naming it, or by being a whole-frame guide.
    func drives(_ groupID: UUID) -> Bool {
        boundGroups.isEmpty || boundGroups.contains(groupID)
    }
}
