import SwiftUI

/// **Animate mode's always-on strip**, pinned directly above the animation timeline — KEYFRAMES.md
/// §2.1, stage 3a.
///
/// **It exists because a mode reached by holding a button is invisible otherwise, and this app has
/// already paid for that once.** `Views/LayerPanel.swift`'s add-button `primaryAction` was the one
/// previous tap-versus-hold split here and the owner reverted it as undiscoverable. So the mode gets
/// two loud signals and not one: the keyframe button's own filled-and-blue icon, and this — a strip
/// that is on screen for as long as the mode is, saying what the mode is about to do and offering the
/// way out.
///
/// **Placed *outside* the height-constrained `timelinePanel`, exactly as `InterpolateBar` is**, so
/// turning the mode on adds a strip above the panel rather than eating track rows out of it. That is
/// `AnimationTimeline.body`'s existing shape and the second mode simply joins the first there.
struct AnimateBar: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                Text("ANIMATE")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.blue))

            Text(summary)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
                .accessibilityIdentifier("animate.summary")

            Spacer(minLength: 8)

            Button("Exit Animate Mode") { canvasManager.isAnimateMode = false }
                .buttonStyle(.bordered)
                .tint(.blue)
                .accessibilityIdentifier("animate.exit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(white: 0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
        }
        // No accessibility identifier on this container, for `InterpolateBar`'s reason: an
        // accessibility modifier on a SwiftUI container can promote it to a single element and take
        // its children out of the tree, which is what once made that bar's own buttons unreachable
        // from XCUITest.
    }

    /// What the mode will do, in the artist's terms: which layer it writes onto, at which frame, and
    /// how much is already animated there.
    ///
    /// **It names the layer because the target is not obvious from the button's position.** The
    /// keyframe button writes onto the *current* layer (`keyframeTarget`), which is the highlighted
    /// row rather than whichever grade happens to have its settings bar open. A folder's grade
    /// animates too (§2.21) and Animate mode keys it through the settings bar; what it has no answer
    /// for is which folder the *button* would mean, since a folder has no row to sit beside.
    private var summary: String {
        guard let target = canvasManager.keyframeTarget else {
            return "No layer selected — nothing to key."
        }
        let name = canvasManager.displayName(of: target)
        let count = canvasManager.animatedEffectChannelIDs(of: target).count
        let frame = canvasManager.currentFrame + 1
        guard count > 0 else {
            return "\(name) · frame \(frame) — move an effect slider to start a channel."
        }
        return "\(name) · frame \(frame) — \(count) channel\(count == 1 ? "" : "s") animated."
    }
}
