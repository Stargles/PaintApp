import Foundation

/// A snapshot of which layers are visible, associated with a named view.
/// When a view preset is active, toggling layer visibility auto-saves to it.
struct ViewPreset: Identifiable {
    let id: UUID
    var name: String
    var layerVisibility: [UUID: Bool] // layerID -> isVisible
    var folderVisibility: [UUID: Bool] = [:] // folderID -> isVisible
}
