import SwiftUI

/// Interpolate mode's command bar, pinned directly above the animation timeline.
///
/// Everything the workflow *does* lives here — pick references, Generate/Reproject, scrub the
/// result, drop the recipe — because all of it is judged against the blocks sitting underneath.
/// Reaching up to a toolbar panel to press Generate and back down to see what it did is the wrong
/// shape for a workflow whose whole subject is the timeline. The mode's *settings* (thickness fade,
/// clear references, leaving the mode) are the timeline's own interpolate button's popover: set once,
/// not reached for mid-flow.
///
/// The layout is fixed by the product owner (2026-08-01) and the reasons are worth keeping. The
/// timing bar is the **top** row because it is the control that gets touched over and over, so it
/// wants the edge nearest the artist's eye rather than to be buried under the buttons. The three
/// commands are **centred on Generate** — it is the one that gets pressed, and a centred group sits
/// under the thumb of a hand holding the iPad, the same reasoning the timeline's transport controls
/// already use. The reference counter goes far left and Remove Interpolation far right, so the two
/// things that are read rather than pressed frame the group without crowding it.
///
/// Setting a reference is a button here rather than a press-and-hold on the block. Press-and-hold
/// was the first attempt and it was wrong — that gesture already means drag-reorder, so
/// mode-switching it cost the artist the ability to re-time blocks without leaving the mode, and
/// bought nothing over a button that is on screen the whole time anyway.
struct InterpolateBar: View {
    @ObservedObject var canvasManager: CanvasManager

    /// The refusal from the last Generate/Reproject attempt, shown until the artist changes
    /// something. `interpolationRefusalAtPlayhead` is also consulted live to disable the buttons, so
    /// this is only reached when a button was enabled and the attempt still failed.
    @State private var refusal: CanvasManager.InterpolationRefusal?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if activeRecipe != nil { timing }
            commandRow
            // Phase 5's group controls hang off the bar rather than off a timeline gesture
            // (`HANDOFF.md` §5.10), and go *under* the settled two rows so neither moves. The row
            // hides itself when there is nothing to show, so a single-part drawing's bar is exactly
            // Phase 4.6's.
            MotionGroupRow(canvasManager: canvasManager)
            // Everything about guides — both toggles and item 7's list — on its own row under the
            // groups. **They were on the command row and had to move**: the trailing cluster grew
            // from {Commit, Remove} to {Guide, Shape, Commit, Remove} and overran the centred
            // command group, which the `ZStack` draws last, so on a portrait iPad the Guide button
            // ended up underneath Reproject and `isHittable` was false. Restoring the command row to
            // exactly what Phase 4.6 settled is the point; grouping the guide controls with the guide
            // list is the bonus.
            GuideRow(canvasManager: canvasManager)
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

    /// Status on the left, commands centred over the top of it, Remove on the right.
    ///
    /// A `ZStack` rather than `Spacer`-padded thirds because only a `ZStack` centres the command
    /// group on the *bar*: with spacers it centres on whatever room the side content leaves, so
    /// Generate would slide sideways every time the reference count changed its own width.
    private var commandRow: some View {
        ZStack {
            HStack(spacing: 10) {
                status
                if canvasManager.isRegisteringInterpolation {
                    ProgressView().controlSize(.small)
                    Text("Registering…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer(minLength: 12)
                commitButton
                removeButton
            }
            commands
        }
    }

    // MARK: - Commands

    private var commands: some View {
        HStack(spacing: 10) {
            referenceButton
            command(title: "Generate", mode: .generate, emphasised: targetCelIsEmpty)
            command(title: "Reproject", mode: .reproject, emphasised: !targetCelIsEmpty)
        }
    }

    /// Flags or unflags the block under the playhead on the current layer. A selection, not a
    /// document edit — `toggleInterpolationReference` deliberately records no undo step.
    ///
    /// Unlike Generate this genuinely needs a block to exist: there is nothing to flag on an empty
    /// slot, and inventing a blank keyframe to hold the flag would quietly change the drawing.
    private var referenceButton: some View {
        Button(targetIsReference ? "Unset Reference" : "Set as Reference") {
            guard let at = canvasManager.interpolationTarget else { return }
            refusal = nil
            let cel = canvasManager.layers[at.layer].cels[at.cel]
            canvasManager.toggleInterpolationReference(celID: cel.id,
                                                       inLayer: canvasManager.layers[at.layer].id)
        }
        .buttonStyle(.bordered)
        .tint(targetIsReference ? .yellow : .accentColor)
        .disabled(canvasManager.interpolationTarget == nil)
        .accessibilityIdentifier("interpolate.setReference")
    }

    /// Generate and Reproject are two buttons and never one, per `PLAN.md` §10 decision 3: they
    /// answer different intents ("make me an in-between" vs "nudge this drawing's timing") and
    /// conflating them is how the feature gets confusing. The likely one is emphasised from whether
    /// the cel already has a drawing, and the other stays available.
    ///
    /// Both act on the playhead rather than on a cel index, which is what lets Generate work from an
    /// empty slot — it creates the block first (`interpolateAtPlayhead`).
    private func command(title: String, mode: InterpolationMode, emphasised: Bool) -> some View {
        let refused = canvasManager.interpolationRefusalAtPlayhead(mode: mode)
        return Button(title) {
            refusal = canvasManager.interpolateAtPlayhead(mode: mode)
        }
        .buttonStyle(.borderedProminent)
        .tint(emphasised ? .accentColor : .gray)
        .disabled(refused != nil)
        .accessibilityIdentifier("interpolate.\(mode == .generate ? "generate" : "reproject")")
    }

    /// Bakes the frame into the cel and drops the recipe — `PLAN.md` §4's Commit.
    ///
    /// **Beside Remove rather than in the centred group**, and both halves of that matter. It is not
    /// in the group because a fourth button there would push Generate off the bar's centre, which is
    /// the one thing the `ZStack` above exists to prevent. It is *next to Remove* because they are
    /// the two ways a recipe ends and the artist is choosing between them: Commit keeps the drawing
    /// and lets go of the link, Remove lets go of both. Remove stays furthest right, where it was.
    ///
    /// Shown only while there is a recipe, which is the same condition Remove uses and is deliberately
    /// the *cheap* one. `commitRefusal` would be the more precise gate, but it evaluates the recipe —
    /// an ARAP solve per motion group — and this body runs on every SwiftUI pass. So the button is
    /// offered whenever a recipe exists and reports its refusal on tap instead, exactly as `refusal`'s
    /// own comment describes.
    @ViewBuilder
    private var commitButton: some View {
        if activeRecipe != nil {
            Button("Commit") {
                refusal = canvasManager.commitInterpolationAtPlayhead()
            }
            .buttonStyle(.bordered)
            // Not destructive — nothing is lost that undo cannot return — but one-way in the sense
            // that matters to the artist: the frame stops being derived, so editing a keyframe will
            // no longer update it. Warm rather than red says "a decision" without saying "danger".
            .tint(.orange)
            .accessibilityIdentifier("interpolate.commit")
        }
    }

    /// Drops the recipe, leaving whatever content the cel already had — which for a derived
    /// in-between is nothing, so this reads as "undo the interpolation" without being undo.
    @ViewBuilder
    private var removeButton: some View {
        if activeRecipe != nil {
            Button("Remove Interpolation", role: .destructive) {
                guard let at = canvasManager.interpolationTarget else { return }
                refusal = nil
                canvasManager.removeInterpolation(layerIndex: at.layer, celIndex: at.cel)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier("interpolate.remove")
        }
    }

    @ViewBuilder
    private var status: some View {
        if let refusal {
            Text(refusal.message)
                .font(.caption)
                .foregroundColor(.orange)
                .lineLimit(2)
                .frame(maxWidth: 180, alignment: .leading)
                .accessibilityIdentifier("interpolate.refusal")
        } else {
            Text(referenceSummary)
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(2)
                .frame(maxWidth: 180, alignment: .leading)
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
                        guard let at = canvasManager.interpolationTarget else { return }
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

    private var activeRecipe: InterpolationRecipe? {
        canvasManager.interpolationTarget.flatMap {
            canvasManager.layers[$0.layer].cels[$0.cel].interpolation
        }
    }

    /// True when there is nothing on the target frame — including when there is no block there at
    /// all, which is the case Generate is emphasised for.
    private var targetCelIsEmpty: Bool {
        guard let at = canvasManager.interpolationTarget else { return true }
        return canvasManager.layers[at.layer].cels[at.cel].vector?.elements.isEmpty ?? true
    }

    private var targetIsReference: Bool {
        guard let at = canvasManager.interpolationTarget else { return false }
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
