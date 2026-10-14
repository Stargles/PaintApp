import SwiftUI

/// Per-mask values. Only this small section observes the held state; the scene stays still during a drag.
struct MaskTuningSection: View {
    @ObservedObject var canvasManager: CanvasManager
    @ObservedObject var liveState: LiveEditState
    let target: MaskSource
    private var mask: AlphaMask { canvasManager.maskAsShown(for: target) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(mask.colours.isEmpty ? "Uses the ink on the checked layers." : "Uses these colours on the checked layers.")
                        .font(.caption2).foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    if mask.colours.isEmpty {
                        row("Threshold", value: mask.threshold, range: 0.1...0.9, identifier: "maskTuning.threshold") { value in
                            var updated = mask
                            updated.setTuning(threshold: value, antialiasHalfWidth: updated.antialiasHalfWidth)
                            canvasManager.holdMask(updated, for: target)
                        }
                        row("Antialias", value: mask.antialiasHalfWidth, range: 0...0.25, identifier: "maskTuning.antialiasHalfWidth") { value in
                            var updated = mask
                            updated.setTuning(threshold: updated.threshold, antialiasHalfWidth: value)
                            canvasManager.holdMask(updated, for: target)
                        }
                        Button("Reset to defaults") {
                            var updated = mask
                            updated.setTuning(threshold: 0.1, antialiasHalfWidth: 0.01)
                            canvasManager.holdMask(updated, for: target)
                            canvasManager.commitHeldMask()
                        }
                        .accessibilityIdentifier("maskTuning.reset")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                RecolorEntriesEditor(entries: mask.colours.map { key in
                    var entry = RecolorEntry.blank
                    entry.key = key
                    return entry
                }, canvasManager: canvasManager, pickTarget: nil, onChange: { entries in
                    var updated = mask
                    updated.colours = entries.map(\.key)
                    canvasManager.holdMask(updated, for: target)
                }, onEditEnded: { canvasManager.commitHeldMask() }, maskTarget: target)
            }
        }
        .frame(maxHeight: 360)
    }

    private func row(_ label: String, value: Float, range: ClosedRange<Float>, identifier: String,
                     write: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundColor(.white)
                Spacer()
                Text(String(format: "%.3f", value)).font(.caption.monospaced()).foregroundColor(.white)
            }
            Slider(value: Binding(get: { value }, set: write), in: range) { editing in
                if !editing { canvasManager.commitHeldMask() }
            }
            .accessibilityIdentifier(identifier)
            .accessibilityValue(String(format: "%.4f", value))
        }
    }
}
