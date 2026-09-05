import SwiftUI

/// Eraser settings — the shared brushes menu (`StrokeSettingsPanel`) driven by `CanvasManager`'s
/// separate `selectedEraserBrush`/`eraserSize`/`eraserOpacity` state instead of the paint brush's, so
/// adjusting the eraser never disturbs whatever brush you paint with (see `BrushStamper.stampDab`:
/// an eraser dab is the same stamp, just composited with `.destinationOut` instead of painting
/// color).
///
/// **It lists the same library the brush does, and that is BRUSH.md §11 rather than a convenience.**
/// The eraser used to be offered `availableEraserBrushes` — the five built-ins with imports excluded,
/// on the grounds that a custom texture was *"a paint-brush-only feature"*. §11 rules the opposite:
/// *the eraser is a stroke*, so an imported brush erases with no eraser work at all. One library, two
/// selections. The `+` still offers no importer here — importing is one verb in one place, on the
/// brush side — and the accessory slot is spent on the vector-mode picker instead.
struct EraserSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    /// BRUSH.md §2.20's second tap — see `BrushSettingsPanel`.
    let onEditBrush: () -> Void

    static let spec = StrokeSettingsSpec(
        title: "Eraser",
        idPrefix: "eraserPanel",
        selectedBrush: \.selectedEraserBrush,
        size: \.eraserSize,
        opacity: \.eraserOpacity,
        selectPreset: { manager, preset in manager.selectEraserBrush(preset) },
        previewTool: .eraser
    )

    var body: some View {
        StrokeSettingsPanel(
            canvasManager: canvasManager,
            library: canvasManager.brushLibrary,
            spec: Self.spec,
            onEditBrush: onEditBrush,
            accessory: { vectorModePicker },
            addMenuItems: { EmptyView() }
        )
    }

    // MARK: - Vector mode

    /// The three-way vector-eraser mode control, occupying the accessory slot the brush panel uses
    /// for custom-texture import.
    ///
    /// Shown only on a `.vector` layer: on a raster layer the eraser is a plain `.destinationOut`
    /// brush with no modes to pick between, and the panel stays exactly as it was before this
    /// existed. The layer kind comes from `CanvasManager.activeLayerKind`, which returns nil when
    /// `currentLayerIndex` points at nothing (it legitimately does mid-edit — see `deleteLayer`), so
    /// nil correctly falls through to hiding the control.
    @ViewBuilder
    private var vectorModePicker: some View {
        if canvasManager.activeLayerKind == .vector {
            VStack(alignment: .leading) {
                Text("Vector Eraser")
                    .foregroundColor(.white)

                Picker("Vector Eraser Mode", selection: $canvasManager.vectorEraserMode) {
                    ForEach(VectorEraserMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("\(Self.spec.idPrefix).vectorModePicker")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

}

/// Small grey/white checker backdrop, standing in for canvas transparency.
///
/// It used to be behind this panel's own eraser swatch — a circle punched out of it with
/// `.destinationOut`. That swatch is gone: BRUSH.md §7.2's editor draws a real stroke of the brush
/// and gives the artist a pad to try it on, which is a better answer to "what does this eraser do"
/// than a static hole. `OnionSkinPanel`'s tint bar still needs the backdrop for its own reason — a
/// gradient whose *alpha* is the thing being read cannot be read over an opaque background — so this
/// stays here rather than being deleted with the swatch it was drawn for.
struct CheckerboardPattern: View {
    var body: some View {
        GeometryReader { geo in
            let squareSize: CGFloat = 10
            let columns = Int(geo.size.width / squareSize) + 1
            let rows = Int(geo.size.height / squareSize) + 1
            Canvas { context, _ in
                for row in 0..<rows {
                    for column in 0..<columns {
                        guard (row + column) % 2 == 0 else { continue }
                        let rect = CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize, width: squareSize, height: squareSize)
                        context.fill(Path(rect), with: .color(Color.white.opacity(0.5)))
                    }
                }
            }
            .background(Color.gray.opacity(0.3))
        }
    }
}
