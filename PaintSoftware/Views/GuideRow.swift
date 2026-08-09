import SwiftUI

/// The guides on the frame under the playhead, and the two ways to fetch one from elsewhere —
/// Phase 7 item 7, `PLAN.md` §6.4, requirement 7.
///
/// **A list rather than a menu command, and that is the design call this item required.** "Fetch a
/// guide from another frame" is one line at the model layer (a recipe has named guides by id since
/// Phase 2), so the work here is entirely about what the artist can see. Three separate problems all
/// wanted the same widget and it was worth designing once rather than three times:
///
/// - **Requirement 7 itself** needs somewhere to offer link and duplicate, and somewhere to say
///   which guides a frame ended up with.
/// - **A second guide averages with the first** (`GuideSet.trajectories`), which is the least
///   surprising rule for two but is invisible: the artist draws a second arc and the motion moves
///   half as far as it looks like it should. Two rows on screen is what makes that legible.
/// - **A linked guide is shared**, so editing its handles moves every frame that uses it. That is
///   the *point* of a link and a nasty surprise if you thought you had a copy, so the chip says so.
///
/// It sits under `MotionGroupRow` and hides itself when there is nothing to show, so a bar with no
/// guides is exactly the one Phase 4.6 settled.
struct GuideRow: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        let chips = canvasManager.guideChips
        let linkable = canvasManager.linkableGuideStrokes
        if !chips.isEmpty || !linkable.isEmpty {
            HStack(spacing: 8) {
                Text("Guides")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                if chips.isEmpty {
                    Text("none on this frame")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(chips) { chip(for: $0) } }
                            .padding(.vertical, 1)
                    }
                }
                Spacer(minLength: 0)
                if chips.count > 1 { averagingNote }
                if !linkable.isEmpty { fetchMenu(from: linkable) }
            }
        }
    }

    /// Number, whether it is shared, and which of the two signals it carries.
    ///
    /// Not a button: there is nothing to select. Item 2's handles act on whichever guide the finger
    /// lands on, so a selection model here would be a second way to say the same thing and the two
    /// could disagree.
    private func chip(for chip: CanvasManager.GuideChip) -> some View {
        HStack(spacing: 5) {
            Image(systemName: chip.isShared ? "link" : "scribble")
                .font(.caption2)
                .foregroundColor(chip.isShared ? .teal : .white.opacity(0.7))
            Text("Guide \(chip.number)")
                .font(.caption)
            if chip.guide.role != .both {
                Text(chip.guide.role == .timing ? "timing" : "path")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
        .foregroundColor(.white)
        .accessibilityIdentifier("interpolate.guideChip.\(chip.number)")
    }

    /// Two trajectory guides average rather than sum (`GuideSet.trajectories`), which is the least
    /// surprising rule and is still not something anyone would guess from watching the frame move
    /// half as far as the second arc suggests.
    private var averagingNote: some View {
        Text("averaged")
            .font(.caption2)
            .foregroundColor(.orange.opacity(0.9))
            .accessibilityIdentifier("interpolate.guideAveragedNote")
    }

    /// **Link and duplicate, offered as two commands per guide and never as one.**
    ///
    /// `PLAN.md` §6.4 recommends both and they answer different intents: link for a repeating cycle,
    /// where fixing the arc once should fix every frame of the walk; duplicate for a one-off, where
    /// the copy is a starting point to pull about. Collapsing them into a single "Use" would make the
    /// artist find out which one they got by editing it — the same reason Generate and Reproject are
    /// two buttons (`PLAN.md` §10 decision 3).
    private func fetchMenu(from linkable: [GuideStroke]) -> some View {
        Menu {
            ForEach(Array(linkable.enumerated()), id: \.element.id) { index, guide in
                Menu("Guide from elsewhere \(index + 1)") {
                    Button("Link — edits propagate") {
                        canvasManager.linkGuideStroke(id: guide.id)
                    }
                    Button("Duplicate — independent copy") {
                        canvasManager.duplicateGuideStroke(id: guide.id)
                    }
                }
            }
        } label: {
            Label("Fetch", systemImage: "plus.circle")
                .font(.caption)
        }
        .accessibilityIdentifier("interpolate.guideFetch")
    }
}
