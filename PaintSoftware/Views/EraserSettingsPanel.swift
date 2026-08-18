import SwiftUI

/// Eraser settings — the shared `StrokeSettingsPanel` driven by `CanvasManager`'s separate
/// `selectedEraserBrush`/`eraserSize`/`eraserOpacity` state instead of the paint brush's, so
/// adjusting the eraser never disturbs whatever brush you paint with (see `BrushStamper.stampDab`:
/// an eraser dab is the same stamp, just composited with `.destinationOut` instead of painting
/// color). No custom-texture import here — that's a paint-brush-only feature; the eraser spends the
/// shared panel's accessory slot on its vector-mode picker instead.
struct EraserSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    private static let spec = StrokeSettingsSpec(
        title: "Eraser",
        idPrefix: "eraserPanel",
        presets: \.availableEraserBrushes,
        selectedBrush: \.selectedEraserBrush,
        size: \.eraserSize,
        opacity: \.eraserOpacity,
        selectPreset: { manager, preset in manager.selectEraserBrush(preset) }
    )

    var body: some View {
        StrokeSettingsPanel(
            canvasManager: canvasManager,
            spec: Self.spec,
            accessory: { vectorModePicker },
            preview: { preview }
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
        }
    }

    // MARK: - Preview

    /// Shows the erase shape's hardness/size as a punched-out hole over a checkerboard, standing in
    /// for the transparency an eraser leaves — a solid color swatch (like the brush preview) wouldn't
    /// mean anything here since the eraser's own color is irrelevant (see `BrushStamper.stampDab`).
    ///
    /// The circle is `eraserSize` **panel** points and does not track the canvas zoom, so read it as
    /// "this shape, this hardness", not as "this is how big it will be on the artwork". That matters
    /// more since 2026-08-18, when the size became Mode 3's selection radius rather than only its
    /// reach: `StrokeCanvasView.updateEraserFootprint(at:)` draws the canvas-accurate circle, on the
    /// canvas, under the finger, and that is the one to trust.
    private var preview: some View {
        VStack(alignment: .leading) {
            Text("Preview")
                .foregroundColor(.white)
                .padding(.horizontal)

            ZStack {
                CheckerboardPattern()
                Circle()
                    .fill(Color.black.opacity(canvasManager.eraserOpacity))
                    .frame(width: canvasManager.eraserSize, height: canvasManager.eraserSize)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(height: 100)
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}

/// Small grey/white checker backdrop the eraser preview punches a hole out of, standing in for
/// canvas transparency.
///
/// Not `private` any more: `OnionSkinPanel`'s tint bar needs exactly the same backdrop for exactly
/// the same reason — a gradient whose *alpha* is the thing being read cannot be read over an opaque
/// background. Shared rather than copied, since a second checker at a different square size would
/// make the two panels quietly disagree about what transparency looks like.
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
