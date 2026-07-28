import Foundation

struct LayerFolder: Identifiable {
    let id: UUID
    var name: String
    var isExpanded: Bool = true
    var isVisible: Bool = true
    /// Set when this folder is nested inside another. Ordering among siblings is derived from the
    /// layers each folder holds — see `CanvasManager.layerStackRows`.
    var parentFolderID: UUID? = nil
}
