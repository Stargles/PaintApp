import SwiftUI

// MARK: - Views
//
// View presets: named snapshots of which layers and folders are visible, so an animator can flip
// between "rough only", "inks + colour" and so on. Extracted from CanvasManager.swift as an
// extension — all state still lives on the class itself (see that file's header), so every view
// binding is unchanged.

extension CanvasManager {

    /// Adds a new view preset capturing the current visibility state of all layers and folders.
    func addViewPreset() {
        withStructureUndo(name: "Add View") {
            var vis: [UUID: Bool] = [:]
            for layer in layers { vis[layer.id] = layer.isVisible }
            var folderVis: [UUID: Bool] = [:]
            for folder in folders { folderVis[folder.id] = folder.isVisible }
            let preset = ViewPreset(id: UUID(), name: "View \(viewPresets.count + 1)",
                                    layerVisibility: vis, folderVisibility: folderVis)
            viewPresets.append(preset)
            activeViewPresetIndex = viewPresets.count - 1
        }
    }

    /// Switches to the view preset at `index`, or back to "no view" (all layers visible) for any
    /// index outside `viewPresets`. Passing -1 is the canonical way to clear the active view.
    func selectViewPreset(at index: Int) {
        withStructureUndo(name: "Switch View") {
            if viewPresets.indices.contains(index) {
                activeViewPresetIndex = index
                applyViewPreset(viewPresets[index])
            } else {
                activeViewPresetIndex = -1
                for idx in layers.indices where !layers[idx].isVisible {
                    layers[idx].isVisible = true
                    layers[idx].isFillReference = true
                }
                for idx in folders.indices where !folders[idx].isVisible {
                    folders[idx].isVisible = true
                }
            }
        }
    }

    /// Deletes a view preset, keeping `activeViewPresetIndex` pointed at the same preset it was on
    /// (or dropping to "no view" when the active one is the one being deleted).
    func deleteViewPreset(at index: Int) {
        guard viewPresets.indices.contains(index) else { return }
        withStructureUndo(name: "Delete View") {
            viewPresets.remove(at: index)
            if activeViewPresetIndex == index {
                selectViewPreset(at: -1)
            } else if index < activeViewPresetIndex {
                activeViewPresetIndex -= 1
            }
        }
    }

    /// Cycles to the next view preset. After the last preset, returns to "no view" mode
    /// where all layers are visible.
    func cycleViewPreset() {
        if viewPresets.isEmpty {
            addViewPreset()
            return
        }
        selectViewPreset(at: activeViewPresetIndex + 1 >= viewPresets.count ? -1 : activeViewPresetIndex + 1)
    }

    /// Applies a view preset's visibility snapshot to all layers and folders.
    private func applyViewPreset(_ preset: ViewPreset) {
        for idx in layers.indices {
            if let vis = preset.layerVisibility[layers[idx].id] {
                layers[idx].isVisible = vis
                layers[idx].isFillReference = vis
            }
        }
        for idx in folders.indices {
            if let vis = preset.folderVisibility[folders[idx].id] {
                folders[idx].isVisible = vis
            }
        }
    }

    /// Saves the current visibility state of every layer and folder into the active view preset (if any).
    ///
    /// Not `private`: `toggleLayerVisibility` and `toggleFolderVisibility` stay in CanvasManager.swift
    /// and call this, and Swift scopes `private` to the file rather than the type.
    func saveVisibilityToActiveView() {
        guard viewPresets.indices.contains(activeViewPresetIndex) else { return }
        for layer in layers {
            viewPresets[activeViewPresetIndex].layerVisibility[layer.id] = layer.isVisible
        }
        for folder in folders {
            viewPresets[activeViewPresetIndex].folderVisibility[folder.id] = folder.isVisible
        }
    }

    /// Name of the active view for display purposes, or "All" when no view is active.
    var activeViewName: String {
        guard viewPresets.indices.contains(activeViewPresetIndex) else { return "All" }
        return viewPresets[activeViewPresetIndex].name
    }
}
