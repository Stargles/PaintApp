import SwiftUI
import PhotosUI
import UIKit

/// The brushes menu driven by the paint brush's profile (`CanvasManager.toolProfiles.brush`), plus the two pieces unique to the paint brush — importing a custom texture, and a
/// solid-color preview swatch.
///
/// **The importer moved to the `+`.** It was the panel's `accessory`, a row under six sliders, which
/// put it below the fold: the owner reported having to scroll to find it. BRUSH.md §7.1 puts the `+`
/// top-right of the first thing the menu shows, and §2.20 already named that button as where §12
/// stage 12's `.abr`/`.brush` importers land beside it. Its identifier is unchanged
/// (`brushPanel.importCustomBrush`) because what it does is unchanged.
struct BrushSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    /// BRUSH.md §2.20's second tap. Answered by `DrawingView`, which raises §2.24's full-screen
    /// editor — see `StrokeSettingsPanel`.
    let onEditBrush: () -> Void
    @State private var customBrushPickerItem: PhotosPickerItem?
    @State private var isPickingCustomBrush = false
    @State private var importError: String?

    static let spec = StrokeSettingsSpec(
        title: "Brush",
        idPrefix: "brushPanel",
        tool: .brush
    )

    var body: some View {
        StrokeSettingsPanel(
            canvasManager: canvasManager,
            library: canvasManager.brushLibrary,
            spec: Self.spec,
            onEditBrush: onEditBrush,
            accessory: { importErrorRow },
            addMenuItems: { importButton }
        )
        // The picker stays attached to the panel after its menu row goes away. Its selected item
        // owns the transfer task, including cancellation on a new selection or panel dismissal.
        .photosPicker(isPresented: $isPickingCustomBrush, selection: $customBrushPickerItem, matching: .images)
        .task(id: customBrushPickerItem) { [item = customBrushPickerItem] in
            await importCustomBrush(item)
        }
    }

    // MARK: - Custom brush import

    private var importButton: some View {
        MenuItem("Import Custom Brush", systemImage: "plus.square.dashed",
                 identifier: "brushPanel.importCustomBrush") {
            isPickingCustomBrush = true
        }
    }

    @ViewBuilder
    private var importErrorRow: some View {
        if let importError {
            Text(importError)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .accessibilityIdentifier("brushPanel.importError")
        }
    }

    /// Hands the picked image to `CanvasManager.importCustomBrush` and says what came back.
    ///
    /// **Everything except the photo picker is on the other side of that call, deliberately.** What a
    /// tip file has to be is `BrushTipImport`'s rule, and which brush stamps it, which group it lands
    /// in and whether it becomes the active one is the manager's; a copy of either here would be a
    /// second definition to keep in step, and — the reason that matters — nothing in a `View` is
    /// reachable from the logic tier, so a rule written here is a rule no test can drive. All that is
    /// left is the four failures the artist can act on.
    @MainActor
    private func importCustomBrush(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            try await canvasManager.importCustomBrush(
                loadingData: { try await item.loadTransferable(type: Data.self) },
                whileCurrent: { customBrushPickerItem == item })
            guard !Task.isCancelled, customBrushPickerItem == item else { return }
            importError = nil
            customBrushPickerItem = nil
        } catch {
            guard !(error is CancellationError), !Task.isCancelled, customBrushPickerItem == item else { return }
            switch error {
            case BrushTipImport.Failure.couldNotLoadImage:
                importError = "Couldn't read that image"
            case BrushTipImport.Failure.blankMask:
                importError = "That image is blank — a brush needs dark marks on a light background, or its own transparency"
            case BrushTipImport.Failure.couldNotWrite(let failure):
                importError = "Couldn't save the brush texture: \(failure.localizedDescription)"
            default:
                importError = "Couldn't convert that image to a brush texture"
            }
            customBrushPickerItem = nil
        }
    }

}
