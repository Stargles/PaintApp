import CoreGraphics
import Foundation

/// One cel, addressed from anywhere in the document.
///
/// A layer id as well as a cel id because a recipe's sources are allowed to span layers — lineart on
/// one, flats on another (`PLAN.md` §5.0 step 2, requirement 5) — so "which cel" is not answerable
/// from the owning layer alone.
struct CelRef: Codable, Equatable, Hashable {
    var layerID: UUID
    var celID: UUID
}

/// One keyframe a recipe reads from: the cels that together make up the drawing at that point in
/// the motion.
///
/// A list rather than a single cel because a keyframe pose is often spread across layers, and those
/// layers must be interpolated *together* — a lineart arm and its flat colour have to be warped by
/// one lattice or they drift apart. §5.1 is the other half of that guarantee (a shared motion group);
/// this is the half that says which content is in play.
struct InterpolationReference: Codable, Equatable {
    var cels: [CelRef]

    init(cels: [CelRef] = []) {
        self.cels = cels
    }

    init(layerID: UUID, celID: UUID) {
        self.cels = [CelRef(layerID: layerID, celID: celID)]
    }
}

/// Generate an in-between from the references, or re-pose a drawing this cel already has.
///
/// Two commands, never conflated — `PLAN.md` §10 decision 3. In `.generate` every element is derived
/// from the references; in `.reproject` the cel's own strokes are kept and only their pose slides
/// along the A→C motion, so the artist's linework is never replaced.
enum InterpolationMode: String, Codable {
    case generate
    case reproject
}

/// How `t` is remapped before it is used — the easing of the in-between.
///
/// Kept as data rather than a closure because it persists, and because a guide stroke's stylus
/// velocity is *derived into* one of these (`PLAN.md` §6.1): arc length per unit stylus time is a
/// spacing function, and `.sampled` is where that lands.
struct SpacingCurve: Codable, Equatable {

    enum Kind: String, Codable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        /// `samples` is the curve, read at evenly spaced inputs.
        case sampled
    }

    var kind: Kind

    /// For `.sampled`: eased outputs at evenly spaced inputs — `samples[0]` is the value at `t = 0`,
    /// `samples[count - 1]` the value at `t = 1`, everything between linearly interpolated. Empty
    /// for every other kind, and a `.sampled` curve with fewer than two entries falls back to linear
    /// rather than failing, because a half-recorded guide should not break the frame.
    var samples: [CGFloat]

    init(kind: Kind = .linear, samples: [CGFloat] = []) {
        self.kind = kind
        self.samples = samples
    }

    static let linear = SpacingCurve()

    /// `t` after easing, clamped to `0...1` on the way in.
    func eased(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        switch kind {
        case .linear:
            return x
        case .easeIn:
            return x * x
        case .easeOut:
            return x * (2 - x)
        case .easeInOut:
            return x * x * (3 - 2 * x)
        case .sampled:
            guard samples.count >= 2 else { return x }
            let scaled = x * CGFloat(samples.count - 1)
            let i = min(Int(scaled.rounded(.down)), samples.count - 2)
            let f = scaled - CGFloat(i)
            return samples[i] + (samples[i + 1] - samples[i]) * f
        }
    }
}

/// How one motion group moves across this recipe's span.
///
/// The group itself is document-level and carries no geometry (`MotionGroup`); the geometry is
/// per-keyframe and lives here, because it only means anything relative to a particular A→C pair.
struct MotionGroupBinding: Codable, Equatable {

    var groupID: UUID

    /// One lattice per entry in the recipe's `references`, **in the same order**.
    ///
    /// Aligned rather than named `latticeA`/`latticeC` for the same reason `references` is a list:
    /// a spline across four keyframes (`PLAN.md` §10 decision 7) is four lattices, and a pair of
    /// fields could not express it without a migration. A binding whose count does not match
    /// `references` is malformed; `InterpolationRecipe.isWellFormed` is what says so.
    var lattices: [Lattice]

    /// Per-group easing override. Nil means the recipe's own `spacing` applies.
    var spacing: SpacingCurve?

    /// Guides driving this group specifically. The recipe-level `guideIDs` binds to every group;
    /// this binds to one. See `GuideStroke`.
    var guideIDs: [UUID]

    init(groupID: UUID, lattices: [Lattice] = [], spacing: SpacingCurve? = nil, guideIDs: [UUID] = []) {
        self.groupID = groupID
        self.lattices = lattices
        self.spacing = spacing
        self.guideIDs = guideIDs
    }
}

/// Something the artist drew *at* the in-between, stored where it can survive the slider moving.
///
/// The stroke's samples are in the **rest space of its group's lattice**, not in the space it was
/// drawn in: `Lattice.carriedToRest` carries a stroke drawn at *t* back through the inverse map, and
/// from there it re-warps with everything else on every subsequent tick (`PLAN.md` §5.4). Storing it
/// as drawn would strand it in place while the rest of the frame moved on — the thing the brief
/// means by "seamlessly".
///
/// When it becomes visible is on the stroke itself (`VectorStroke.visibilityThreshold`), for the
/// reason that field exists: a stroke that is later split or copied has to take its own visibility
/// with it, and a side table would have to be mirrored at every one of those sites.
struct LocalEdit: Identifiable, Codable {

    var id: UUID = UUID()

    /// The stroke, in rest space. Erasers included — an eraser is a stroke here as everywhere else
    /// (`VECTOR_ERASER_PLAN.md` §2.1), so it warps and fades with no eraser-specific code.
    var stroke: VectorStroke

    /// Whose lattice carries it. Nil for an edit made while nothing was grouped, which the evaluator
    /// warps with the recipe's whole-frame lattice.
    var groupID: UUID?

    init(id: UUID = UUID(), stroke: VectorStroke, groupID: UUID? = nil) {
        self.id = id
        self.stroke = stroke
        self.groupID = groupID
    }
}

/// What makes a cel an **interpolated** cel: its content is computed from `references` at time `t`
/// rather than stored.
///
/// This is `PLAN.md` §4's load-bearing decision in one type. An inbetween is *derived, never
/// stored*, and every awkward requirement in the brief falls out of that: sliding the frame in time
/// is a change to `t`; editing a keyframe updates the inbetween for free because the references are
/// by identity; and editing the inbetween works because those edits live in keyframe space
/// (`LocalEdit`).
///
/// It is a value type inside `Cel`, which is a value type inside `Layer.cels`, which
/// `CanvasManager.StructureSnapshot` copies wholesale — so undo covers everything here with no new
/// machinery (`PLAN.md` §9). That placement is the reason the recipe is a struct and not a class.
///
/// ## What is deliberately *not* here
///
/// No embeddings, and no cell or vertex indices of any kind. A `LatticeEmbedding` is derivable from
/// geometry plus its lattice, and `Lattice.expanded(toContain:)` shifts every cell and vertex index
/// when the lattice grows (`LatticeExpansion` exists to translate them). Persisting an index would
/// mean either re-mapping it on every expansion or version-stamping it to catch a stale one;
/// re-deriving it on load costs a single pass and cannot be silently wrong. See `HANDOFF.md` §5.7.
struct InterpolationRecipe: Codable {

    /// The keyframes this cel is derived from, **in time order**.
    ///
    /// A list, not a `(previous, next)` pair. Two entries is today's pairwise case; four entries is
    /// the spline of `PLAN.md` §10 decision 7, with no model change. That constraint is load-bearing
    /// — do not collapse it back into two fields.
    var references: [InterpolationReference]

    /// Where in the span this cel sits: `0` at the first reference, `1` at the last. With today's
    /// two-element list this is exactly the artist's slider.
    ///
    /// Normalised across the *whole* span rather than indexed per segment, so that adding a
    /// reference does not silently move existing cels. How a `t` between two interior references
    /// maps onto a segment is the evaluator's business (uniform today); note that once a spline
    /// ships, changing that mapping changes what an already-saved `t` means, so it is picked once.
    var t: CGFloat

    /// Generate from the references, or re-pose this cel's own drawing. See `InterpolationMode`.
    var mode: InterpolationMode

    /// Per-motion-group motion. A recipe with no bindings warps the whole frame as one group, which
    /// is the honest degenerate case rather than an error (`PLAN.md` §10 decision 2).
    var groups: [MotionGroupBinding]

    /// Guides bound to the whole frame — every group. Per-group guides live on the binding.
    var guideIDs: [UUID]

    /// Strokes drawn at an in-between, stored in keyframe space. See `LocalEdit`.
    var localEdits: [LocalEdit]

    /// Frame-wide easing. A group with its own `spacing` overrides this.
    var spacing: SpacingCurve

    init(references: [InterpolationReference] = [],
         t: CGFloat = 0,
         mode: InterpolationMode = .generate,
         groups: [MotionGroupBinding] = [],
         guideIDs: [UUID] = [],
         localEdits: [LocalEdit] = [],
         spacing: SpacingCurve = .linear) {
        self.references = references
        self.t = t
        self.mode = mode
        self.groups = groups
        self.guideIDs = guideIDs
        self.localEdits = localEdits
        self.spacing = spacing
    }

    private enum CodingKeys: String, CodingKey {
        case references, t, mode, groups, guideIDs, localEdits, spacing
    }

    /// Hand-written for the reason every decoder in this repo is: a recipe saved by an earlier build
    /// must not fail to load because a field added later is absent. Only `references` and `t` are
    /// required — everything else has a meaningful empty value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        references = try c.decode([InterpolationReference].self, forKey: .references)
        t = try c.decode(CGFloat.self, forKey: .t)
        mode = try c.decodeIfPresent(InterpolationMode.self, forKey: .mode) ?? .generate
        groups = try c.decodeIfPresent([MotionGroupBinding].self, forKey: .groups) ?? []
        guideIDs = try c.decodeIfPresent([UUID].self, forKey: .guideIDs) ?? []
        localEdits = try c.decodeIfPresent([LocalEdit].self, forKey: .localEdits) ?? []
        spacing = try c.decodeIfPresent(SpacingCurve.self, forKey: .spacing) ?? .linear
    }

    /// Every cel any part of this recipe reads, deduplicated. What a "does this keyframe still
    /// exist" check and a re-evaluation dependency both want.
    var referencedCels: [CelRef] {
        var seen = Set<CelRef>()
        var result: [CelRef] = []
        for reference in references {
            for cel in reference.cels where seen.insert(cel).inserted {
                result.append(cel)
            }
        }
        return result
    }

    /// True when the recipe describes something evaluable: at least two keyframes, and every group
    /// carrying one lattice per keyframe.
    ///
    /// Checked rather than assumed because a recipe can be malformed by editing *around* it —
    /// deleting a referenced cel, or adding a reference without re-registering the groups — and the
    /// evaluator should be able to say "not yet" instead of indexing off the end of an array.
    var isWellFormed: Bool {
        guard references.count >= 2 else { return false }
        return groups.allSatisfy { $0.lattices.count == references.count }
    }

    /// `t` after the group's own easing, or the recipe's if the group does not override it.
    func easedT(forGroup groupID: UUID?) -> CGFloat {
        let curve = groupID.flatMap { id in groups.first { $0.groupID == id }?.spacing } ?? spacing
        return curve.eased(t)
    }
}
