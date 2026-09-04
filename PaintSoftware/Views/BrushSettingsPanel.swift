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

    /// Hands the picked image to `CanvasManager.importCustomBrush` and says what came back.
    ///
    /// **Everything except the photo picker is on the other side of that call, deliberately.** What a
    /// tip file has to be is `BrushTipImport`'s rule, and which brush stamps it and whether it becomes
    /// the active one is the manager's; a copy of either here would be a second definition to keep in
    /// step, and — the reason that matters — nothing in a `View` is reachable from the logic tier, so
    /// a rule written here is a rule no test can drive. All that is left is the four failures the
    /// artist can act on.
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
