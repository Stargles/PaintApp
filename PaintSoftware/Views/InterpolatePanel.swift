import SwiftUI

/// Interpolate mode's panel: pick references on the timeline, turn them into an in-between, and
/// scrub it.
///
/// The panel is the whole of `PLAN.md` §5.0 steps 1–4 in one place, and it is deliberately thin —
/// every decision it can make is made in `CanvasManager+Interpolation`, so the same workflow is
/// testable without a view. What lives here is only what a view owns: what the buttons say, when
/// they are disabled, and the drag/release boundary of the slider.
struct InterpolatePanel: View {
    @ObservedObject var canvasManager: CanvasManager

    /// The refusal from the last Generate/Reproject attempt, shown until the artist changes
    /// something. `interpolationRefusal` is also consulted live to disable the buttons, so this is
    /// only reached when a button was enabled and the attempt still failed.
    @State private var refusal: CanvasManager.InterpolationRefusal?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if canvasManager.isInterpolateMode {
                references
                Divider().overlay(Color.white.opacity(0.2))
                commands
                if activeRecipe != nil {
                    Divider().overlay(Color.white.opacity(0.2))
                    timing
                }
                options
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(Color.black.opacity(0.9))
        .cornerRadius(10)
    }

    // MARK: - Sections

    private var header: some View {
        Toggle(isOn: Binding(
            get: { canvasManager.isInterpolateMode },
            set: { on in
                refusal = nil
                if on { canvasManager.enterInterpolateMode() } else { canvasManager.exitInterpolateMode() }
            })) {
            Text("Interpolate Mode")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
        .toggleStyle(.switch)
        .accessibilityIdentifier("interpolate.modeToggle")
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("References")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
            Text(referenceSummary)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("interpolate.referenceSummary")
            if !canvasManager.interpolationReferences.isEmpty {
                Button("Clear References") { canvasManager.interpolationReferences.removeAll() }
                    .font(.caption)
                    .accessibilityIdentifier("interpolate.clearReferences")
            }
        }
    }

    /// Generate and Reproject are two buttons and never one, per `PLAN.md` §10 decision 3: they
    /// answer different intents ("make me an in-between" vs "nudge this drawing's timing") and
    /// conflating them is how the feature gets confusing. The likely one is emphasised from whether
    /// the cel already has a drawing, and the other stays available.
    private var commands: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canvasManager.isRegisteringInterpolation {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Registering…").font(.caption).foregroundColor(.white.opacity(0.8))
                }
            }
            HStack(spacing: 8) {
                command(title: "Generate", mode: .generate, emphasised: targetCelIsEmpty)
                command(title: "Reproject", mode: .reproject, emphasised: !targetCelIsEmpty)
            }
            if let refusal {
                Text(refusal.message)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("interpolate.refusal")
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

    private func command(title: String, mode: InterpolationMode, emphasised: Bool) -> some View {
        Button(title) {
            guard let at = targetIndices else { return }
            refusal = canvasManager.interpolate(mode: mode, layerIndex: at.layer, celIndex: at.cel)
        }
        .buttonStyle(.borderedProminent)
        .tint(emphasised ? .accentColor : .gray)
        .disabled(targetIndices.map {
            canvasManager.interpolationRefusal(mode: mode, layerIndex: $0.layer, celIndex: $0.cel) != nil
        } ?? true)
        .accessibilityIdentifier("interpolate.\(mode == .generate ? "generate" : "reproject")")
    }

    /// The `t` slider.
    ///
    /// `onEditingChanged` is the whole drag/release boundary: touch-down opens one undo step and
    /// selects `.preview` render quality, release closes the step and re-renders at `.full`. Both
    /// halves matter — a step per tick makes undo useless, and `.full` per tick makes the slider
    /// unusable on real art (`HANDOFF.md` §5.9).
    private var timing: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Timing").font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(String(format: "%.2f", activeRecipe?.t ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
            }
            Slider(
                value: Binding(
                    get: { Double(activeRecipe?.t ?? 0) },
                    set: { value in
                        guard let at = targetIndices else { return }
                        let cel = canvasManager.layers[at.layer].cels[at.cel]
                        canvasManager.setInterpolationT(CGFloat(value), forCel: cel.id,
                                                        inLayer: canvasManager.layers[at.layer].id)
                    }),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing { canvasManager.beginInterpolationDrag() }
                    else { canvasManager.commitInterpolationDrag() }
                })
            .accessibilityIdentifier("interpolate.tSlider")
            Text(spacingSummary)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
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

    /// The cel the commands act on: the one under the playhead on the current layer.
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

    private var targetCelIsEmpty: Bool {
        guard let at = targetIndices else { return true }
        return canvasManager.layers[at.layer].cels[at.cel].vector?.elements.isEmpty ?? true
    }

    private var referenceSummary: String {
        let keyframes = canvasManager.interpolationKeyframes
        guard !keyframes.isEmpty else {
            return "Press and hold a block on the timeline to set it as a reference."
        }
        let cels = canvasManager.interpolationReferences.count
        let spread = cels > keyframes.count ? " (\(cels) cels across layers)" : ""
        return "\(keyframes.count) keyframe\(keyframes.count == 1 ? "" : "s")\(spread)."
    }

    private var spacingSummary: String {
        guard let recipe = activeRecipe, recipe.references.count >= 2 else { return "" }
        return "0 = first reference, 1 = last."
    }
}
