import SwiftUI
import PhotosUI
import UIKit

/// Procreate-style brush settings: a horizontally-scrolling preset picker (5 built-ins plus any
/// custom imports) and sliders for every `Brush` setting that's expected to be user-tunable day to
/// day (size, opacity, pressure dynamics, stabilization, spacing, and — only for the Pencil preset —
/// grain depth). Replaces the earlier pen/pencil segmented-control placeholder now that `Brush`/
/// `BrushLibrary` (Engine/Brush.swift, Engine/BrushLibrary.swift) and `CanvasManager.selectedBrush`
/// exist to back it.
struct BrushSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var customBrushPickerItem: PhotosPickerItem?
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Brush")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding([.horizontal, .top])

                brushPicker

                sliderRow(
                    title: "Size",
                    valueText: "\(Int(canvasManager.brushSize))",
                    value: sizeBinding,
                    range: 1...200,
                    accessibilityID: "brushPanel.sizeSlider"
                )
                sliderRow(
                    title: "Opacity",
                    valueText: "\(Int(canvasManager.brushOpacity * 100))%",
                    value: opacityBinding,
                    range: 0...1,
                    accessibilityID: "brushPanel.opacitySlider"
                )
                sliderRow(
                    title: "Pressure → Size",
                    valueText: "\(Int(canvasManager.selectedBrush.dynamics.sizePressure * 100))%",
                    value: sizePressureBinding,
                    range: 0...1,
                    accessibilityID: "brushPanel.pressureSizeSlider"
                )
                sliderRow(
                    title: "Pressure → Opacity",
                    valueText: "\(Int(canvasManager.selectedBrush.dynamics.opacityPressure * 100))%",
                    value: opacityPressureBinding,
                    range: 0...1,
                    accessibilityID: "brushPanel.pressureOpacitySlider"
                )
                sliderRow(
                    title: "Stabilization",
                    valueText: "\(Int(canvasManager.selectedBrush.stabilization * 100))%",
                    value: stabilizationBinding,
                    range: 0...1,
                    accessibilityID: "brushPanel.stabilizationSlider"
                )
                sliderRow(
                    title: "Spacing",
                    valueText: "\(Int(canvasManager.selectedBrush.spacingFraction * 100))%",
                    value: spacingBinding,
                    range: 0.02...0.5,
                    accessibilityID: "brushPanel.spacingSlider"
                )

                if canvasManager.selectedBrush.shape == .pencil {
                    sliderRow(
                        title: "Grain Depth",
                        valueText: "\(Int(canvasManager.selectedBrush.grain.depth * 100))%",
                        value: grainDepthBinding,
                        range: 0...1,
                        accessibilityID: "brushPanel.grainDepthSlider"
                    )
                }

                importCustomBrushRow

                preview

                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
    }

    // MARK: - Preset picker

    private var brushPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(canvasManager.availableBrushes) { preset in
                    presetButton(preset)
                }
            }
            .padding(.horizontal)
        }
    }

    private func presetButton(_ preset: Brush) -> some View {
        let isSelected = preset.id == canvasManager.selectedBrush.id
        return Button {
            canvasManager.selectBrush(preset)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon(for: preset.shape))
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .white)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                Text(preset.name)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .accessibilityIdentifier("brushPanel.preset.\(preset.name)")
    }

    private func icon(for shape: BrushShape) -> String {
        switch shape {
        case .softRound: return "circle"
        case .hardRound: return "circle.fill"
        case .pencil: return "pencil"
        case .pen: return "pencil.tip"
        case .square: return "square.fill"
        case .custom: return "photo"
        }
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

    // MARK: - Slider row helper

    private func sliderRow(title: String, valueText: String, value: Binding<Double>, range: ClosedRange<Double>, accessibilityID: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(valueText)")
                .foregroundColor(.white)
            Slider(value: value, in: range)
                .accessibilityIdentifier(accessibilityID)
        }
        .padding(.horizontal)
    }

    // MARK: - Bindings

    /// Drives both the live `brushSize` (what `SideToolbar`'s own size slider and `stampOne` read)
    /// and `selectedBrush.size`, so this slider and `SideToolbar`'s stay in lockstep no matter which
    /// one the user last touched. Note this only tweaks the *active* brush in place — tapping away
    /// to another preset and back re-copies that preset's original values from `BrushLibrary`/
    /// `customBrushes` rather than remembering the tweak; persisting per-preset edits is real
    /// follow-up work, not implemented here.
    private var sizeBinding: Binding<Double> {
        Binding(
            get: { Double(canvasManager.brushSize) },
            set: { newValue in
                canvasManager.brushSize = CGFloat(newValue)
                canvasManager.selectedBrush.size = CGFloat(newValue)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { canvasManager.brushOpacity },
            set: { newValue in
                canvasManager.brushOpacity = newValue
                canvasManager.selectedBrush.opacity = newValue
            }
        )
    }

    private var sizePressureBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedBrush.dynamics.sizePressure },
            set: { canvasManager.selectedBrush.dynamics.sizePressure = $0 }
        )
    }

    private var opacityPressureBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedBrush.dynamics.opacityPressure },
            set: { canvasManager.selectedBrush.dynamics.opacityPressure = $0 }
        )
    }

    private var stabilizationBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedBrush.stabilization },
            set: { canvasManager.selectedBrush.stabilization = $0 }
        )
    }

    private var spacingBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedBrush.spacingFraction },
            set: { canvasManager.selectedBrush.spacingFraction = $0 }
        )
    }

    private var grainDepthBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedBrush.grain.depth },
            set: {
                canvasManager.selectedBrush.grain.depth = $0
                canvasManager.selectedBrush.grain.isEnabled = $0 > 0
            }
        )
    }
}
