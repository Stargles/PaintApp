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
}
