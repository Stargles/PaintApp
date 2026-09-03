import SwiftUI

/// `CanvasNotice`, drawn: a pill across the top of the canvas that dismisses itself.
///
/// Sized and placed to be readable without being in the way — it sits just under the top toolbar,
/// centred, and is only as wide as its text. It never covers the layer panel's rail, which matters
/// because two of the three notices are telling the artist to go and use it.
///
/// **Nothing about it blocks.** No `.alert`, no `.sheet`, no scrim: the canvas keeps its gestures
/// while this is up, so the stroke that raised the message can be retried on another layer without
/// dismissing anything first. Tapping it dismisses early; ignoring it dismisses on its own.
struct CanvasNoticeBanner: View {
    let notice: CanvasNotice
    /// Runs the notice's one-tap fix. Nil when the notice offers none.
    var onAction: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            // The identifier rides the `Text` rather than the pill, and the reason is the trap
            // recorded in CLAUDE.md: a SwiftUI `.accessibilityIdentifier` on a *container*
            // propagates to its descendants and beats their own, so putting it on the `HStack`
            // would hand this name to the action button too and leave the button's own name
            // resolving to nothing. Same rule `LayerPanel.maskRow` follows for `maskSummary`.
            Text(notice.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("canvasNotice")
                // The case code, not the wording: a test that reads the visible sentence breaks the
                // day someone rephrases it, and the phrasing is the half most likely to be revised.
                .accessibilityValue(notice.code)

            if let title = notice.actionTitle, let onAction {
                Button(title, action: onAction)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.42, green: 0.72, blue: 1))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("canvasNotice.action")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.86))
                .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
        // The pill itself dismisses on tap — an early out for an artist who has read it, without
        // making that the only way it can go. The action button above sits *inside* this tappable
        // area and still wins, because SwiftUI delivers a tap to the innermost view that wants it.
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch notice.kind {
        case .noLayers:         return "square.stack.3d.up.slash"
        case .hiddenLayer:      return "eye.slash"
        case .noDrawingSurface: return "nosign"
        case .historyUndo:      return "arrow.uturn.backward"
        case .historyRedo:      return "arrow.uturn.forward"
        case .nothingToPick:    return "eyedropper"
        // The lasso's own glyph rather than a warning triangle: the artist's loop is the thing the
        // message is about, and nothing has gone wrong with the app.
        case .nothingEnclosed:  return "lasso"
        // The same glyph for the same reason: the artist's loop, and the rule they picked for it, are
        // what the message is about.
        case .nothingWhollyInside: return "lasso"
        // The timeline's own glyph: the message is about which frame the artist is standing on, and
        // the fix is a scrub rather than anything on the canvas.
        case .cannotMoveDerivedFrame: return "film"
        // The two cases in this switch where something genuinely has gone wrong — a save that did not
        // land, and a resize that found an element it could not read — so they get the warning
        // triangle none of the others use.
        case .saveFailed, .resizeRefused: return "exclamationmark.triangle"
        // Not a warning: the resize did what was asked and this is the honest footnote about what
        // undoing it will and will not give back. The canvas glyph, because that is what changed.
        case .resizeResampled:  return "square.resize"
        }
    }
}
