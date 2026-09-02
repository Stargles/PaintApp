import Foundation

/// **A named set of elements that move together under a pose channel** — KEYFRAMES.md §2.11 and §3.4.
///
/// **It mirrors `MotionGroup` exactly, and that is a decision rather than a copy.** §3.4: a
/// document-level identity carrying **no geometry** — id, display name, tag colour — with membership
/// as a **field on the element** (`animationGroupID`). `MotionGroup` is identity, `MotionGroupBinding`
/// inside the recipe is the geometry, and the split is the codebase's own settled shape. Here the
/// geometry is the `TransformTrack` on the cel, for the same reason: a pose only means anything
/// relative to a particular cel's rest box.
///
/// **Why not reuse `MotionGroup` itself.** §2.8: the two features must stay distinguishable in the
/// artist's vocabulary as well as in the code. A motion group answers *"which strokes does the
/// in-betweener warp together"*; an animation group answers *"which elements does this keyframed
/// transform move"*. An artist who grouped a character's arm for interpolation has said nothing about
/// what a camera move should carry, and sharing one tag would silently make those the same statement.
///
/// **`.cel` is not one of these.** `TransformChannelID.cel` moves whatever is on the cel, resolved per
/// frame, so a stroke drawn after the channel exists joins the move — see that type for why
/// expressing the whole cel as a group whose membership happens to be everything is the wrong shape.
struct AnimationGroup: Identifiable, Codable, Equatable {

    var id: UUID = UUID()

    var displayName: String

    /// The swatch this group is drawn in when the timeline or a channel list names it. Deliberately
    /// unrelated to the paint colour of its members, `MotionGroup.tagColor`'s argument verbatim:
    /// tagging is a separate attribute, so colour-coding still works on fully coloured art where two
    /// red things move differently.
    var tagColor: CodableColor

    init(id: UUID = UUID(), displayName: String, tagColor: CodableColor) {
        self.id = id
        self.displayName = displayName
        self.tagColor = tagColor
    }

    private enum CodingKeys: String, CodingKey { case id, displayName, tagColor }

    /// Hand-written to the repo's usual rule: a group saved before a field existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        tagColor = try c.decodeIfPresent(CodableColor.self, forKey: .tagColor)
            ?? CodableColor(red: 0.2, green: 0.6, blue: 1, alpha: 1)
    }
}

// MARK: - Membership

/// **The accessor VECTOR_INTERPOLATION items 11/41 ask for, built once for both features** — §3.4's
/// *"it must go on every element kind, not just strokes… doing it once serves both"*.
///
/// `motionGroupID` deliberately gets **no** setter here. It is on two of the four kinds today and
/// promoting it is that feature's stage 6; adding a half-total accessor for it would be a silent
/// no-op on a fill, which is exactly the wart items 11/41 record. This one is total.
extension VectorElement {

    /// Which animation group this element belongs to. Nil is untagged, which is every element in a
    /// document that has never been keyframed.
    var animationGroupID: UUID? {
        switch self {
        case .stroke(let stroke): return stroke.animationGroupID
        case .fill(let fill): return fill.animationGroupID
        case .image(let image): return image.animationGroupID
        case .text(let text): return text.animationGroupID
        }
    }

    /// `self` with its membership set. A value-returning form rather than a mutating setter because
    /// `VectorElement` is an enum over four payloads and every caller here is inside a `map`.
    func taggedForAnimation(_ group: UUID?) -> VectorElement {
        switch self {
        case .stroke(var stroke): stroke.animationGroupID = group; return .stroke(stroke)
        case .fill(var fill): fill.animationGroupID = group; return .fill(fill)
        case .image(var image): image.animationGroupID = group; return .image(image)
        case .text(var text): text.animationGroupID = group; return .text(text)
        }
    }

    /// Whether this element is moved by `channel` — `.cel` carries everything, a group carries its
    /// own members and nothing else.
    func isMoved(by channel: TransformChannelID) -> Bool {
        switch channel {
        case .cel: return true
        case .group(let id): return animationGroupID == id
        }
    }
}
