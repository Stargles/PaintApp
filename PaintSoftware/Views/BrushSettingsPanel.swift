import SwiftUI
import PhotosUI
import UIKit

/// The brushes menu driven by the paint brush's `CanvasManager` state (`selectedBrush`/`brushSize`/
/// `brushOpacity`), plus the two pieces unique to the paint brush — importing a custom texture, and a
/// solid-color preview swatch.
///
/// **The importer moved to the `+`.** It was the panel's `accessory`, a row under six sliders, which
/// put it below the fold: the owner reported having to scroll to find it. BRUSH.md §7.1 puts the `+`
/// top-right of the first thing the menu shows, and §2.20 already named that button as where §12
/// stage 12's `.abr`/`.brush` importers land beside it. Its identifier is unchanged
/// (`brushPanel.importCustomBrush`) because what it does is unchanged.
struct BrushSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var customBrushPickerItem: PhotosPickerItem?
    @State private var isPickingCustomBrush = false
    @State private var importError: String?

    private static let spec = StrokeSettingsSpec(
        title: "Brush",
        idPrefix: "brushPanel",
        selectedBrush: \.selectedBrush,
        size: \.brushSize,
        opacity: \.brushOpacity,
        selectPreset: { manager, preset in manager.selectBrush(preset) },
        previewTool: .brush
    )

    var body: some View {
        StrokeSettingsPanel(
            canvasManager: canvasManager,
            library: canvasManager.brushLibrary,
            spec: Self.spec,
            accessory: { importErrorRow },
            addMenuItems: { importButton },
            preview: { preview }
        )
        // The picker is raised from a `Menu` item, so it cannot be the `PhotosPicker` button itself —
        // a menu row is not a place a picker can present from. The flag is the whole of that
        // indirection; everything past `loadTransferable` is exactly what it was.
        .photosPicker(isPresented: $isPickingCustomBrush, selection: $customBrushPickerItem, matching: .images)
        .onChange(of: customBrushPickerItem) { _, newItem in
            Task { await importCustomBrush(newItem) }
        }
    }

    // MARK: - Custom brush import

    private var importButton: some View {
        Button {
            isPickingCustomBrush = true
        } label: {
            Label("Import Custom Brush", systemImage: "plus.square.dashed")
        }
        .accessibilityIdentifier("brushPanel.importCustomBrush")
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
    private func importCustomBrush(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            await MainActor.run { importError = "Couldn't read that image" }
            return
        }
        await MainActor.run {
            do {
                try canvasManager.importCustomBrush(from: image)
                importError = nil
            } catch BrushTipImport.Failure.blankMask {
                importError = "That image is blank — a brush needs dark marks on a light background, or its own transparency"
            } catch BrushTipImport.Failure.couldNotWrite(let error) {
                importError = "Couldn't save the brush texture: \(error.localizedDescription)"
            } catch {
                importError = "Couldn't convert that image to a brush texture"
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(alignment: .leading) {
            Text("Preview")
                .foregroundColor(.white)
                .padding(.horizontal)

            ZStack {
                Color.white
                    .frame(height: 100)
                Circle()
                    .fill(canvasManager.brushColor.opacity(canvasManager.brushOpacity))
                    .frame(width: canvasManager.brushSize, height: canvasManager.brushSize)
            }
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}
