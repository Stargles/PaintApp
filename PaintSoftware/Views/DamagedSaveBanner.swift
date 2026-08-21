import SwiftUI

/// The one question this app asks before it overwrites something: **this project opened with marks
/// it could not read — may the save write over them?**
///
/// The owner's ruling, 2026-08-21: "a banner naming what couldn't be read, with Save Anyway /
/// Cancel. Safest, and the only option that can't silently destroy work."
///
/// **A sibling of `CanvasNoticeBanner`, not an instance of it, and the difference is the point.** A
/// `CanvasNotice` is a 2.6-second self-dismissing strip whose own documentation says it "does not
/// take a tap to get rid of" — exactly right for telling an artist something, and exactly wrong for
/// asking them something. This one stays until it is answered, because a question that vanishes while
/// you are reading it has been answered for you.
///
/// **It still does not block.** No `.alert`, no `.sheet`, no scrim: the canvas keeps its gestures
/// while this is up, which is the house rule and is also useful here — an artist can go and look at
/// the layer it names before deciding. What it does *not* have is a dismiss-on-tap, since there is no
/// safe default answer to fall through to.
struct DamagedSaveBanner: View {
    let damage: ProjectLoadDamage
    var onSaveAnyway: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.yellow.opacity(0.9))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // The identifier rides the `Text` rather than the pill, for `CanvasNoticeBanner`'s
                // reason: a SwiftUI `.accessibilityIdentifier` on a container propagates to its
                // descendants and beats their own, which would leave both buttons below unnamed.
                Text(damage.summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("damagedSaveBanner")
                    // A count rather than the sentence: a test that reads the visible wording breaks
                    // the day someone rephrases it, and the phrasing is the half most likely to be
                    // revised.
                    .accessibilityValue("\(damage.itemCount)")

                Text(ProjectLoadDamage.consequence)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 18) {
                    // Cancel is first and Save Anyway second, so the safe answer is the one the eye
                    // reaches before the irreversible one. Neither is styled as a default: this is a
                    // decision about the artist's own work, and the app does not have an opinion.
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.42, green: 0.72, blue: 1))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("damagedSaveBanner.cancel")

                    Button("Save Anyway", action: onSaveAnyway)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 1, green: 0.66, blue: 0.35))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("damagedSaveBanner.saveAnyway")
                }
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.yellow.opacity(0.35), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
        .accessibilityElement(children: .contain)
    }
}
