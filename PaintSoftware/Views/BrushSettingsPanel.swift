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

    /// Saves the picked image under `BrushLibrary.customBrushesDirectory` and registers a new
    /// `.custom`-shaped `Brush` pointing at it. `CanvasManager.addCustomBrush` keeps this in memory
    /// only for now — persisting custom brushes across launches (writing them into the project
    /// manifest) is handled elsewhere, not by this import flow.
    private func importCustomBrush(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            await MainActor.run { importError = "Couldn't read that image" }
            return
        }
        let fileName = "custom-\(UUID().uuidString).png"
        let destination = BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName)
        guard let pngData = image.pngData() else {
            await MainActor.run { importError = "Couldn't convert that image to a brush texture" }
            return
        }
        do {
            try pngData.write(to: destination)
        } catch {
            await MainActor.run { importError = "Couldn't save the brush texture: \(error.localizedDescription)" }
            return
        }
        let brush = Brush(
            name: "Custom \(canvasManager.customBrushes.count + 1)",
            shape: .custom,
            customTextureFileName: fileName,
            size: 24,
            spacingFraction: 0.12,
            hardness: 0.8
        )
        await MainActor.run {
            importError = nil
            canvasManager.addCustomBrush(brush)
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
