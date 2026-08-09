import Foundation

/// How a group's content is carried from one keyframe to the next. `.crossFade` is the universal
/// fallback and must be correct on its own; `.clean` is a per-group refinement on the same lattice,
/// degrading to `.crossFade` until a better matcher lands; `.auto` picks between them per group
/// from the confidence of the match.
enum GroupInterpolation: String, Codable {
    case auto
    case clean
    case crossFade
}

/// A set of strokes that move together, named at the *document* level rather than owned by a
/// layer or cel: a lineart stroke on layer 3 and a flat colour on layer 4 can carry the same `id`,
/// so one lattice warps both and they *cannot* drift apart — a structural guarantee, not two
/// independent interpolations that happen to agree.
///
/// Carries **no geometry**. A group is an identity and a few display attributes; the geometry it
/// implies is per keyframe pair and lives in the recipe (`MotionGroupBinding`), because a lattice
/// only means anything relative to a particular A→C span.
struct MotionGroup: Identifiable, Codable, Equatable {

    var id: UUID = UUID()

    var displayName: String

    /// The swatch this group is drawn in while interpolate mode is on. Deliberately unrelated to
    /// the paint colour of the strokes in it: tagging is a *separate attribute* with a one-shot
    /// "tag by stroke colour" populate action, not a live binding, so colour-coding still works on
    /// fully coloured art where two red things move differently, and recolouring a stroke
    /// afterwards cannot silently move it to a different motion group.
    var tagColor: CodableColor

    var mode: GroupInterpolation = .auto

    init(id: UUID = UUID(), displayName: String, tagColor: CodableColor,
         mode: GroupInterpolation = .auto) {
        self.id = id
        self.displayName = displayName
        self.tagColor = tagColor
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, tagColor, mode
    }

    /// Hand-written to the repo's usual rule: a group saved before a field existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        tagColor = try c.decodeIfPresent(CodableColor.self, forKey: .tagColor)
            ?? CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        mode = try c.decodeIfPresent(GroupInterpolation.self, forKey: .mode) ?? .auto
    }
}
