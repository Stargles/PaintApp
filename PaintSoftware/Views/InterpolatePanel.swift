import SwiftUI

/// Interpolate mode's toolbar panel: turning the mode on, and the settings that are set once.
///
/// The commands themselves — Set as Reference, Generate, Reproject, and the timing bar — are not
/// here. They live in `InterpolateBar`, pinned above the animation timeline, because every one of
/// them is judged against the blocks underneath it. What is left here is what an artist reaches for
/// deliberately rather than mid-flow.
///
/// The panel is deliberately thin: every decision it can make is made in
/// `CanvasManager+Interpolation`, so the same workflow is testable without a view.
struct InterpolatePanel: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if canvasManager.isInterpolateMode {
                Divider().overlay(Color.white.opacity(0.2))
                options
                if !canvasManager.interpolationReferences.isEmpty {
                    Button("Clear References") { canvasManager.interpolationReferences.removeAll() }
                        .font(.caption)
                        .accessibilityIdentifier("interpolate.clearReferences")
                }
                if activeRecipe != nil {
                    Button("Remove Interpolation", role: .destructive) {
                        guard let at = targetIndices else { return }
                        canvasManager.removeInterpolation(layerIndex: at.layer, celIndex: at.cel)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("interpolate.remove")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private var header: some View {
        Toggle(isOn: Binding(
            get: { canvasManager.isInterpolateMode },
            set: { on in
                if on { canvasManager.enterInterpolateMode() } else { canvasManager.exitInterpolateMode() }
            })) {
            Text("Interpolate Mode")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
        .toggleStyle(.switch)
        .accessibilityIdentifier("interpolate.modeToggle")
    }

    /// Thickness cross-fade, exposed as a toggle rather than shipped on or off.
    ///
    /// `IMPLEMENTATION.md` Phase 4 item 5 and the product owner's steer of 2026-07-31: the mechanism
    /// works, the default is `.none`, and which is better is a judgement to make on real drawings.
    /// Deliberately view-level and not persisted per recipe — where it eventually lives (global
    /// preference, per recipe, per group) is a decision to take *after* looking at it.
    private var options: some View {
        Toggle(isOn: $canvasManager.interpolationThicknessFade) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Thickness Fade").font(.caption).foregroundColor(.white)
                Text("Fading content thins instead of ghosting")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .toggleStyle(.switch)
        .accessibilityIdentifier("interpolate.thicknessFadeToggle")
    }

    // MARK: - Derived state

    /// The cel Remove Interpolation acts on: the one under the playhead on the current layer, the
    /// same target `InterpolateBar`'s commands use.
    private var targetIndices: (layer: Int, cel: Int)? {
        let layerIndex = canvasManager.currentLayerIndex
        guard canvasManager.layers.indices.contains(layerIndex),
              let celIndex = canvasManager.activeCelIndex(inLayer: layerIndex,
                                                          atFrame: canvasManager.currentFrame)
        else { return nil }
        return (layerIndex, celIndex)
    }

    private var activeRecipe: InterpolationRecipe? {
        targetIndices.flatMap { canvasManager.layers[$0.layer].cels[$0.cel].interpolation }
    }
}
