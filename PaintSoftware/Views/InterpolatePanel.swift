import SwiftUI

/// Interpolate mode's options popover, hung off the timeline's own interpolate button.
///
/// There is no "Interpolate Mode" switch in here, and that is the point. The button behaves like
/// every other tool in the app: the first tap turns the mode *on*, and a second tap — once it is
/// already on — opens this. A panel whose first control was a switch that turned on the mode you had
/// to already be in to see it was redundant, and the product owner called it (2026-08-01).
///
/// What is left is what an artist reaches for deliberately rather than mid-flow: the thickness-fade
/// setting, dropping the reference selection, and leaving the mode. Everything the workflow *does*
/// is `InterpolateBar`, above the timeline.
///
/// The panel is deliberately thin: every decision it can make is made in
/// `CanvasManager+Interpolation`, so the same workflow is testable without a view.
struct InterpolatePanel: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            options
            groupOverlayOption

            if !canvasManager.interpolationReferences.isEmpty {
                Button("Clear References") { canvasManager.interpolationReferences.removeAll() }
                    .font(.caption)
                    .accessibilityIdentifier("interpolate.clearReferences")
            }

            Divider().overlay(Color.white.opacity(0.2))

            Button("Exit Interpolate Mode", role: .destructive) {
                canvasManager.exitInterpolateMode()
            }
            .font(.caption)
            .accessibilityIdentifier("interpolate.exitMode")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The tinted per-group overlay — `IMPLEMENTATION.md` Phase 5 item 4.
    ///
    /// On by default, because "what did it decide?" is the question the phase exists to answer and an
    /// overlay nobody switches on answers nothing. The switch is here rather than on the bar because
    /// it is set once and not reached for mid-flow, which is this popover's whole remit — and because
    /// a drawing with one motion group is not tinted at all, so most artists will never need it.
    private var groupOverlayOption: some View {
        Toggle(isOn: $canvasManager.showMotionGroupOverlay) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Colour by Motion Group").font(.caption).foregroundColor(.white)
                Text("Keyframe strokes take their group's tag colour")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .toggleStyle(.switch)
        .accessibilityIdentifier("interpolate.groupOverlayToggle")
    }
}
