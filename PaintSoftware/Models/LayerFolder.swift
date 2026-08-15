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
    ///
    /// One case now, not two: a node's inputs are its ordinary children, so there is nothing left to
    /// tag them with. See `CompositorRole` below for the migration that retires the old `.slot` tag.
    var compositorRole: CompositorRole? = nil

    /// §4.4's second wrapper (phase 9b): a grade applied once to this folder's finished composite —
    /// the 1-input node form, where "input" is *this container's own slot composite* rather than the
    /// accumulated backdrop a `.compositing` layer grades. No `CompositorRole` case is needed for
    /// it: presence alone makes an ordinary `.stack`-arity-1 folder an effect node, the same recipe
    /// `alphaMask` and `compositorRole` above already use — optional, absent means "not one".
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
    var maxInputCount: Int? {
        guard case .fixed(let count)? = compositorOp?.arity else { return nil }
        return count
    }
}
