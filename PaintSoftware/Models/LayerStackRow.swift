import Foundation

/// One row of the layer stack as presented top-to-bottom in the layer panel and the animation
/// timeline. See `CanvasManager.layerStackRows`. `index` is the row's position in
/// `CanvasManager.layers` (bottom-to-top), so it is only valid for the snapshot it came from;
/// `depth` is how many folders the row sits inside, which drives its indentation.
enum LayerStackRow: Identifiable, Equatable {
    case folder(id: UUID, depth: Int, kind: FolderKind)
    case layer(id: UUID, index: Int, depth: Int)

    /// What a folder row *is* in a compositor graph (§4.3).
    ///
    /// Carried on the row rather than looked up again by each consumer because a node is stored as an
    /// ordinary `LayerFolder` — containment, spans and the ordering rules deliberately cannot tell
    /// the two apart, so the presented row list is the first place the distinction exists at all, and
    /// the layer panel and the timeline read one answer rather than each deriving their own.
    ///
    /// **A payload rather than another case of `LayerStackRow`.** A node is a folder in every
    /// structural sense, and `isFolder`/`folderID` — which the drop resolution, the restack anchors
    /// and the row heights all ask — are asking exactly that. Splitting it out would make every one
    /// of those call sites answer a question it was not asking, and would let a `default:` clause
    /// silently drop a node row instead of failing to compile.
    enum FolderKind: Equatable {
        case group
        case compositorNode
    }

    var id: UUID {
        switch self {
        case .folder(let id, _, _):   return id
        case .layer(let id, _, _):    return id
        }
    }

    var depth: Int {
        switch self {
        case .folder(_, let depth, _):   return depth
        case .layer(_, _, let depth):    return depth
        }
    }

    var layerIndex: Int? {
        if case .layer(_, let index, _) = self { return index }
        return nil
    }

    var folderID: UUID? {
        if case .folder(let id, _, _) = self { return id }
        return nil
    }

    var isFolder: Bool { folderID != nil }

    var folderKind: FolderKind? {
        if case .folder(_, _, let kind) = self { return kind }
        return nil
    }

    /// **The row as a keyframe target** — what the graph editor band opens under.
    ///
    /// Every row is one: a layer is `.layer(id:)` and a folder is `.folder(id:)`, which is what lets
    /// `TimelineRowLayout.make` resolve an expansion to a row without asking which kind it names.
    /// By id rather than by `index`, because an id survives a restack and a folder collapsing above
    /// it, and a folder has no index to be addressed by in the first place.
    var keyframeTarget: KeyframeTarget {
        switch self {
        case .folder(let id, _, _):   return .folder(id: id)
        case .layer(let id, _, _):    return .layer(id: id)
        }
    }
}

extension LayerStackRow.FolderKind {

    /// Reads §4.3's `compositorRole` tag off a folder.
    init(_ folder: LayerFolder) {
        self = folder.isCompositorNode ? .compositorNode : .group
    }
}
