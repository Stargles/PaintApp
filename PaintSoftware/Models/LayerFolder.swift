import Foundation

struct LayerFolder: Identifiable {
    let id: UUID
    var name: String
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
    var compositorRole: CompositorRole? = nil
}

// MARK: - Compositor nodes (§4.3)

/// What a folder is inside a compositor graph.
///
/// §4.3's storage decision, stated as a field: **a node is a folder whose children are exactly its
/// slot folders, and a slot is an ordinary folder that is auto-created, undeletable, and tagged with
/// its owning node and slot index.** Containment, spans, the restack arithmetic and the panel's rows
/// all go on reading a plain `LayerFolder` and need no case of their own.
///
/// What the tag buys is the two behaviours that have no precedent anywhere in the tree: a folder that
/// refuses to be deleted, and a set of siblings that must stay adjacent. Both are enforced *before*
/// the shape breaks (`CanvasManager.deleteFolder`, and the drop guards in `CanvasManager+LayerTree`)
/// rather than repaired after, because a stranded slot carries nothing that says which node it lost.
enum CompositorRole: Equatable {

    /// This folder is a compositor node: its children are its input slots, and `op` combines them.
    case node(op: CompositorOp)

    /// This folder is input slot `index` of the node folder `node`.
    ///
    /// **Index 0 is the backdrop.** §4.3 defines a Mix as "slot 1 composited over slot 0", which is
    /// the direction a plain stack already reads — lower row underneath — so a two-input node and a
    /// two-layer stack agree about which one is on top. `containerEntries` is what keeps this index
    /// and the order the slots present in from drifting apart.
    case slot(node: UUID, index: Int)
}

extension CompositorRole: Codable {

    // The op is written as its own string rather than as `CompositorOp`'s layout: that enum belongs
    // to the compositor and gains a case whenever an op is added, and a document already on disk must
    // not change meaning when it does.
    private enum CodingKeys: String, CodingKey { case kind, op, mixMode, node, index }

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
        case "slot":
            self = .slot(node: try container.decode(UUID.self, forKey: .node),
                         index: try container.decode(Int.self, forKey: .index))
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
        case .slot(let node, let index):
            try container.encode("slot", forKey: .kind)
            try container.encode(node, forKey: .node)
            try container.encode(index, forKey: .index)
        }
    }
}

extension LayerFolder {

    /// True when this folder is a node, whose children are its input slots.
    var isCompositorNode: Bool { compositorOp != nil }

    /// How this node combines its inputs, or nil when the folder is not a node. An ordinary folder
    /// is the arity-1 case and the derivation reads `.stack` for it without needing it stored.
    var compositorOp: CompositorOp? {
        if case .node(let op)? = compositorRole { return op }
        return nil
    }

    var isInputSlot: Bool { inputSlotIndex != nil }

    /// Which input this folder is, if it is one. Zero is the backdrop.
    var inputSlotIndex: Int? {
        if case .slot(_, let index)? = compositorRole { return index }
        return nil
    }

    /// The node this folder is an input to, if it is one.
    var owningNodeID: UUID? {
        if case .slot(let node, _)? = compositorRole { return node }
        return nil
    }
}
