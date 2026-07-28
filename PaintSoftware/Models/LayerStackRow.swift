import Foundation

/// One row of the layer stack as presented top-to-bottom in the layer panel and the animation
/// timeline. See `CanvasManager.layerStackRows`. `index` is the row's position in
/// `CanvasManager.layers` (bottom-to-top), so it is only valid for the snapshot it came from;
/// `depth` is how many folders the row sits inside, which drives its indentation.
enum LayerStackRow: Identifiable, Equatable {
    case folder(id: UUID, depth: Int)
    case layer(id: UUID, index: Int, depth: Int)

    var id: UUID {
        switch self {
        case .folder(let id, _):      return id
        case .layer(let id, _, _):    return id
        }
    }

    var depth: Int {
        switch self {
        case .folder(_, let depth):      return depth
        case .layer(_, _, let depth):    return depth
        }
    }

    var layerIndex: Int? {
        if case .layer(_, let index, _) = self { return index }
        return nil
    }

    var folderID: UUID? {
        if case .folder(let id, _) = self { return id }
        return nil
    }

    var isFolder: Bool { folderID != nil }
}
