import SwiftUI
import PhotosUI
import UIKit

/// Procreate-style brush settings: the shared `StrokeSettingsPanel` driven by the paint brush's
/// `CanvasManager` state (`selectedBrush`/`brushSize`/`brushOpacity`), plus the two pieces unique to
/// the paint brush — importing a custom texture, and a solid-color preview swatch.
struct BrushSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var customBrushPickerItem: PhotosPickerItem?
    @State private var importError: String?

    private static let spec = StrokeSettingsSpec(
        title: "Brush",
        idPrefix: "brushPanel",
        presets: \.availableBrushes,
        selectedBrush: \.selectedBrush,
        size: \.brushSize,
        opacity: \.brushOpacity,
        selectPreset: { manager, preset in manager.selectBrush(preset) },
        previewTool: .brush
    )

    var body: some View {
        StrokeSettingsPanel(
            canvasManager: canvasManager,
            spec: Self.spec,
            accessory: { importCustomBrushRow },
            preview: { preview }
        )
    }

    // MARK: - Custom brush import

    private var importCustomBrushRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            PhotosPicker(selection: $customBrushPickerItem, matching: .images) {
                HStack {
                    Image(systemName: "plus.square.dashed").frame(width: 24)
                    Text("Import Custom Brush")
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("brushPanel.importCustomBrush")
            .onChange(of: customBrushPickerItem) { _, newItem in
                Task { await importCustomBrush(newItem) }
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
    }

    /// Turns the picked image into a tip and registers a `Brush` that stamps it, then selects it —
    /// so the artist's next stroke is drawn with what they just imported and there is no second step
    /// to discover. `CanvasManager.addCustomBrush` keeps this in memory and `ProjectStore` writes it
    /// into the project manifest on the next save.
    ///
    /// **The normalisation is `BrushTipImport`'s, not this view's.** What a tip file has to be — a
    /// square straight-alpha mask, bordered, and read by luminance when the picture carries no alpha
    /// of its own — is a fact about the renderer, and a copy of it here would be a second definition
    /// to keep in step. All that is left is the three failures the artist can act on.
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
