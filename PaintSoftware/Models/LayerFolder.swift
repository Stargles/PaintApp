import Foundation

struct LayerFolder: Identifiable {
    let id: UUID
    var name: String
    /// Whether `name` above is the artist's own answer — `Layer.hasCustomName`'s twin, argued there.
    ///
    /// A folder needs it for the same reason a layer does and one more: a node's name is a claim about
    /// what the node *does*, and a node does exactly one thing (`effect` below says why). So "Mix 1"
    /// on a node the artist has since set to Gaussian Blur is not merely stale, it names the operation
    /// the node no longer performs. `setNodeEffect` and `setMixBlendMode` therefore rename as they
    /// reshape — and stop the moment this is true.
    var hasCustomName: Bool = false
    var isExpanded: Bool = true
    var isVisible: Bool = true
    /// Set when this folder is nested inside another. Ordering among siblings is derived from the
    /// layers each folder holds — see `CanvasManager.layerStackRows`.
    var parentFolderID: UUID? = nil

    // MARK: - Group properties (§4.1)
    //
    // A folder stopped being only a panel affordance in phase 4: it is a compositing unit, and these
    // are what hang on it. Each defaults to its identity, so a folder nobody has touched composites
    // exactly as one that predates them — which is what lets existing projects decode unchanged.

    /// Applied once to the group's finished composite, never per child. The two differ wherever
    /// children overlap, and only the first is what "group opacity" means.
    var opacity: Double = 1

    var blendMode: BlendMode = .normal

    /// Isolated (§3 decision 2, §4.2): children start from transparent and blend only against each
    /// other, and the finished buffer composites into the parent with this group's own opacity and
    /// blend mode. Pass-through — `false` — lets children blend against the backdrop below the
    /// group, which is Photoshop's and CSP's default and this app's *toggle* rather than its default.
    ///
    /// Unobservable until phase 5 gave children something other than source-over to do — with every
    /// child at `.normal`, isolation changes no pixel, since children composited onto transparency
    /// and then drawn over the backdrop equal children drawn straight onto it. Storing and honouring
    /// it a phase early is what let phase 5 add blend modes and only blend modes.
    var isIsolated: Bool = true

    /// The group's own mask (§6.2), applied once to its finished composite for the same reason its
    /// opacity and blend mode are: masking each child instead clips the children rather than the
    /// group, which is a different picture wherever they overlap. A group can be masked *and* be a
    /// mask source.
    var alphaMask: AlphaMask? = nil

    /// What this folder is in a compositor graph (§4.3), or nil for an ordinary group — which is
    /// every folder in every project saved before phase 8, and the whole of why that needs no
    /// migration. Follows `alphaMask`'s recipe exactly: optional, absent means "not one".
    ///
    /// One case now, not two: a node's inputs are its ordinary children, so there is nothing left to
    /// tag them with. See `CompositorRole` below for the migration that retires the old `.slot` tag.
    var compositorRole: CompositorRole? = nil

    /// §4.4's second wrapper (phase 9b): a grade applied once to this folder's finished composite —
    /// the 1-input node form, where "input" is *this container's own slot composite* rather than the
    /// accumulated backdrop a `.value` layer in effect mode grades. No `CompositorRole` case is
    /// needed for it: presence alone makes a `.stack`-op folder an effect node, the same recipe
    /// `alphaMask` and `compositorRole` above already use — optional, absent means "not one".
    ///
    /// **This is also how a Mix node becomes an effect node**, and no `CompositorOp.effect` case was
    /// added for it. A `.mix` folded two isolated slots; an effect folds one — but "fold one input"
    /// is precisely what `.stack` already does, and `RenderNode.effect` is already carried off this
    /// field for *any* op by the folder derivation and applied after the fold by both backends. So
    /// the op-and-effect pair is `op == .stack, effect != nil`, and switching a node between the two
    /// forms is two field writes with no new enum case, no `Compositor`/`MetalCompositor` branch and
    /// no Metal kernel. `CanvasManager.setNodeEffect` and `setMixBlendMode` are the two writers, and
    /// each clears what the other set — the pair must never both be live on one node, because an op
    /// that both blends two inputs and grades one is two unrelated answers to "what does this node
    /// do" and there is nothing to say which runs first.
    var effect: Effect? = nil
}

// MARK: - Compositor nodes (§4.3)

/// What a folder is inside a compositor graph.
///
/// §4.3's storage decision, stated as a field: **a node is a folder, and its children are its
/// inputs** — one per direct child, in stacking order, bottom child first. Containment, spans, the
/// restack arithmetic and the panel's rows all go on reading a plain `LayerFolder` and need no case
/// of their own, and a node's operands need no tag at all: **input index is position**.
///
/// One case, deliberately. The enum survives the deletion of `.slot` because the *op* still has to be
/// stored somewhere and because a future op arrives as data on this case rather than as a new field.
enum CompositorRole: Equatable {

    /// This folder is a compositor node: its children are its inputs, and `op` combines them.
    case node(op: CompositorOp)
}

extension CompositorRole: Codable {

    // The op is written as its own string rather than as `CompositorOp`'s layout: that enum belongs
    // to the compositor and gains a case whenever an op is added, and a document already on disk must
    // not change meaning when it does.
    private enum CodingKeys: String, CodingKey { case kind, op, mixMode }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "node":
            switch try container.decodeIfPresent(String.self, forKey: .op) {
            case "mix":
                self = .node(op: .mix(try container.decodeIfPresent(BlendMode.self, forKey: .mixMode) ?? .normal))
            default:
                self = .node(op: .stack)
            }
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container,
                                                   debugDescription: "Unknown compositor role \"\(kind)\"")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .node(let op):
            try container.encode("node", forKey: .kind)
            switch op {
            case .stack:
                try container.encode("stack", forKey: .op)
            case .mix(let mode):
                try container.encode("mix", forKey: .op)
                try container.encode(mode, forKey: .mixMode)
            }
        }
    }

    /// **The whole of the input-slot migration, written as a line someone can find.**
    ///
    /// A node saved before this change is a node folder plus two child folders tagged
    /// `{"kind":"slot", …}` holding the artwork. Read that tag as *no role* and the same document
    /// becomes a node with two plain-folder children in the same order — `parentFolderID` already
    /// names the node and `containerEntries` already ranks them bottom-to-top, so slot 0 stays the
    /// backdrop. The folders keep their "Input A"/"Input B" names, which is harmless and still reads.
    ///
    /// Not left to `FolderManifest`'s `try?`, which would swallow a thrown "unknown role" into nil and
    /// migrate correctly by accident, riding on error handling that exists for a different reason (an
    /// op from a future build). A migration nobody can grep for is a migration nobody can change.
    static func decodeIfSupported<K: CodingKey>(from container: KeyedDecodingContainer<K>,
                                                forKey key: K) throws -> CompositorRole? {
        guard container.contains(key), !(try container.decodeNil(forKey: key)) else { return nil }
        let stored = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: key)
        guard try stored.decode(String.self, forKey: .kind) != "slot" else { return nil }
        return try container.decode(CompositorRole.self, forKey: key)
    }
}

extension LayerFolder {

    /// True when this folder is a node, whose direct children are its inputs.
    var isCompositorNode: Bool { compositorOp != nil }

    /// How this node combines its inputs, or nil when the folder is not a node. An ordinary folder
    /// is the arity-1 case and the derivation reads `.stack` for it without needing it stored.
    var compositorOp: CompositorOp? {
        if case .node(let op)? = compositorRole { return op }
        return nil
    }

    /// How many direct children this folder will accept, or nil for "as many as the artist likes" —
    /// every ordinary folder, and every variadic node. The one number the drop guards enforce, in
    /// `canDrop(inContainer:moving:)` and again in the restacks it fronts for.
    ///
    /// **An effect node is the arity-1 case, and it is stated here rather than in `CompositorOp`.**
    /// The op it stores is `.stack`, which is variadic because stacking N composites bottom-to-top
    /// genuinely is — what caps this node at one input is not the op but the grade hanging beside it
    /// (see `effect` above): §4.4's 1-input node form takes *this container's composite* and returns
    /// it regraded, so a second operand is a thing the form has no place for. Teaching `.stack`'s
    /// arity about `effect` was not an option — `CompositorOp` is a value the folder holds and cannot
    /// see the folder holding it — and a whole `CompositorOp.effect(Effect)` case to carry a number
    /// this one line already carries would have duplicated the grade's storage, forced a branch into
    /// both backends' `fold` and both `Codable` halves of `CompositorRole`, and left two places a
    /// grade could live that have to agree.
    ///
    /// So one clause, in the one property the drop guards read. `canDrop` and both restacks pick it
    /// up unchanged.
    ///
    /// A node that already holds two children when the artist picks an effect keeps them, and this
    /// then reads 1 against a real child count of 2 — see `CanvasManager.setNodeEffect`, which is
    /// where that choice is argued. The `<` in `canDrop` handles the over-count exactly right: no
    /// third child may land, and reordering the two that are there stays legal.
    var maxInputCount: Int? {
        if isCompositorNode, effect != nil { return 1 }
        guard case .fixed(let count)? = compositorOp?.arity else { return nil }
        return count
    }

    /// **The grade at one frame, and the one function a later keyframe phase changes** — the folder
    /// half of `Layer.layerEffect(atFrame:)`, and `ValueFill.resolvedColor(atFrame:)`'s argument for
    /// the third time.
    ///
    /// Constant today: it is the `effect` field above, with the frame ignored. Stated as a function of
    /// the frame anyway, because the grade reaches the compositor through `RenderNode.effect` and
    /// `CanvasManager.renderNodes(inContainer:atFrame:)` is the last place the frame is in scope
    /// before it gets there. Resolving further in — in `Compositor.fold`, or by giving `RenderNode` a
    /// track instead of a value — would put the constant where the frame is not, and a keyframe phase
    /// would then have to cut this seam under a deadline instead of finding it already cut.
    ///
    /// **Named `resolvedEffect` rather than `effect(atFrame:)`, on purpose.** Swift will happily take
    /// a method whose base name matches the stored property, and `folder.effect` would then differ
    /// from `folder.effect(atFrame:)` by an argument label alone — one keystroke between "the grade at
    /// this frame" and "the grade the artist last typed", in a codebase whose sibling accessor
    /// (`Layer.layerEffect`) already carries a warning about being confused with the raw field.
    /// `ValueFill` made the same call and for the same reason: it stores `color` and resolves
    /// `resolvedColor(atFrame:)`.
    ///
    /// The raw `effect` field stays what everything *structural* reads — `maxInputCount` above,
    /// `setNodeEffect`, the panel's rows — because presence is a property of the folder and not of the
    /// playhead. That division holds only for as long as a track cannot turn a grade on or off at a
    /// frame; `CanvasManager.compositorSizeGate` is the other place that assumption is load-bearing.
    func resolvedEffect(atFrame frame: Int) -> Effect? { effect }
}
