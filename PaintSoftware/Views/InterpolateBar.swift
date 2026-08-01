import SwiftUI

/// Interpolate mode's command bar, pinned directly above the animation timeline.
///
/// Everything the workflow *does* lives here — pick references, Generate/Reproject, scrub the
/// result — because all three are judged against the blocks sitting underneath them. Reaching up
/// to a toolbar panel to press Generate and back down to see what it did is the wrong shape for a
/// workflow whose whole subject is the timeline. The mode's *settings* (thickness fade, clear
/// references, remove) stay in the toolbar panel: they are set once, not reached for mid-flow.
///
/// Setting a reference is a button here rather than a press-and-hold on the block. Press-and-hold
/// was the first attempt and it was wrong — that gesture already means drag-reorder, so
/// mode-switching it cost the artist the ability to re-time blocks without leaving the mode, and
/// bought nothing over a button that is on screen the whole time anyway.
struct InterpolateBar: View {
    @ObservedObject var canvasManager: CanvasManager

    /// The refusal from the last Generate/Reproject attempt, shown until the artist changes
    /// something. `interpolationRefusal` is also consulted live to disable the buttons, so this is
    /// only reached when a button was enabled and the attempt still failed.
    @State private var refusal: CanvasManager.InterpolationRefusal?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                referenceButton
                command(title: "Generate", mode: .generate, emphasised: targetCelIsEmpty)
                command(title: "Reproject", mode: .reproject, emphasised: !targetCelIsEmpty)

                if canvasManager.isRegisteringInterpolation {
                    ProgressView().controlSize(.small)
                    Text("Registering…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer(minLength: 8)
                status
            }
            if activeRecipe != nil { timing }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
        }
        // No identifier on this container on purpose: an accessibility modifier on a SwiftUI
        // container can promote it to a single element and take its children out of the tree, which
        // is exactly what made the bar's own buttons unreachable from XCUITest.
    }

    // MARK: - Commands

    /// Flags or unflags the block under the playhead on the current layer. A selection, not a
    /// document edit — `toggleInterpolationReference` deliberately records no undo step.
    private var referenceButton: some View {
        Button(targetIsReference ? "Unset Reference" : "Set as Reference") {
            guard let at = targetIndices else { return }
            refusal = nil
            let cel = canvasManager.layers[at.layer].cels[at.cel]
            canvasManager.toggleInterpolationReference(celID: cel.id,
                                                       inLayer: canvasManager.layers[at.layer].id)
        }
        .buttonStyle(.bordered)
        .tint(targetIsReference ? .yellow : .accentColor)
        .disabled(targetIndices == nil)
        .accessibilityIdentifier("interpolate.setReference")
    }

    /// Generate and Reproject are two buttons and never one, per `PLAN.md` §10 decision 3: they
    /// answer different intents ("make me an in-between" vs "nudge this drawing's timing") and
    /// conflating them is how the feature gets confusing. The likely one is emphasised from whether
    /// the cel already has a drawing, and the other stays available.
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

    @ViewBuilder
    private var status: some View {
        if let refusal {
            Text(refusal.message)
                .font(.caption)
                .foregroundColor(.orange)
                .lineLimit(2)
                .accessibilityIdentifier("interpolate.refusal")
        } else {
            Text(referenceSummary)
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(2)
                .accessibilityIdentifier("interpolate.referenceSummary")
        }
    }

    /// The `t` slider — the timing bar.
    ///
    /// `onEditingChanged` is the whole drag/release boundary: touch-down opens one undo step and
    /// selects `.preview` render quality, release closes the step and re-renders at `.full`. Both
    /// halves matter — a step per tick makes undo useless, and `.full` per tick makes the slider
    /// unusable on real art (`HANDOFF.md` §5.9).
    private var timing: some View {
        HStack(spacing: 10) {
            Text("Timing")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
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
            Text(String(format: "%.2f", activeRecipe?.t ?? 0))
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Derived state

    /// The cel every command acts on: the one under the playhead on the current layer.
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

    private var targetIsReference: Bool {
        guard let at = targetIndices else { return false }
        return canvasManager.isInterpolationReference(
            celID: canvasManager.layers[at.layer].cels[at.cel].id,
            inLayer: canvasManager.layers[at.layer].id)
    }

    private var referenceSummary: String {
        let keyframes = canvasManager.interpolationKeyframes
        guard !keyframes.isEmpty else {
            return "Go to a keyframe and press Set as Reference."
        }
        let cels = canvasManager.interpolationReferences.count
        let spread = cels > keyframes.count ? " (\(cels) cels across layers)" : ""
        return "\(keyframes.count) reference\(keyframes.count == 1 ? "" : "s")\(spread)."
    }
}
