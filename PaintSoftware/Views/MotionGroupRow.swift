import SwiftUI

/// The motion-group controls — `InterpolateBar`'s third row, and the whole of `IMPLEMENTATION.md`
/// Phase 5 items 2 and 3 that the artist can touch.
///
/// **A row on the bar rather than a timeline gesture**, per `HANDOFF.md` §5.10: press-and-hold on a
/// block already means drag-reorder in every mode, and Phase 4 learned the hard way that
/// mode-switching it costs the artist re-timing exactly while they are working on timing. Two long
/// presses of equal duration competing for one touch have no stable winner and `require(toFail:)`
/// does not help.
///
/// **Third row rather than folded into the second.** The two rows above are settled (Phase 4.6) and
/// their positions are load-bearing — the timing slider is the control that gets touched over and
/// over and wants the edge nearest the eye, and the commands are centred on Generate so it sits under
/// the thumb. Adding a row underneath leaves both exactly where they were. The row hides itself when
/// there is nothing to say, so a single-part drawing's bar is unchanged from Phase 4.6's.
///
/// **The chip is the whole gesture.** Tap it to arm, tap the canvas to assign, tap the chip again to
/// disarm. Everything rarer — mode, solo, mute, delete — is in its context menu, so the common path
/// is one tap and the row stays legible on an iPad's bar.
struct MotionGroupRow: View {
    @ObservedObject var canvasManager: CanvasManager

    /// The result of the last Tag by Stroke Colour, shown until something else is pressed. It refuses
    /// silently at the model layer (one colour is not a grouping), and a button that appears to do
    /// nothing is worse than one that says why.
    @State private var note: String?

    var body: some View {
        let chips = canvasManager.motionGroupChips
        if !chips.isEmpty || canvasManager.hasAnonymousWholeFrameGroup {
            HStack(spacing: 8) {
                colourBakeButton
                if chips.isEmpty {
                    wholeFrameNote
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(chips) { chip(for: $0) }
                        }
                        .padding(.vertical, 1)
                    }
                }
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .accessibilityIdentifier("interpolate.groupNote")
                }
            }
        }
    }

    // MARK: - Chips

    /// Swatch, name, ink count, and the mode badge when the mode is not the default.
    ///
    /// The count is over the flagged keyframes, so it answers "how much of what I am looking at is in
    /// this group" — which is the question an artist correcting a grouping actually has. Zero is shown
    /// rather than hidden: a group with nothing in it is one to tag into or delete, and hiding it
    /// would make it unreachable rather than tidy.
    private func chip(for chip: CanvasManager.MotionGroupChip) -> some View {
        Button {
            note = nil
            canvasManager.toggleArmedMotionGroup(chip.id)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(chip.group.tagColor.uiColor))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                Text(chip.group.displayName)
                    .font(.caption.weight(chip.isArmed ? .semibold : .regular))
                Text("\(chip.strokeCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.55))
                if chip.isHidden {
                    Image(systemName: "eye.slash").font(.caption2)
                }
                badge(for: chip.group.mode)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(chip.isArmed ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(chip.isArmed ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .opacity(chip.isHidden ? 0.45 : 1)
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: chip) }
        .accessibilityIdentifier("interpolate.group.\(chip.id.uuidString)")
    }

    /// **Phase 5 item 3, and the part of it that matters: `.clean` never degrades silently.**
    ///
    /// The matcher `.clean` needs is engine D work and is explicitly deferred
    /// (`IMPLEMENTATION.md`), so a group set to `.clean` renders as a cross-fade today — every time,
    /// not occasionally. Showing the mode the artist chose with no hint of that would be the silent
    /// degradation the plan forbids, so `.clean` carries a warning glyph and says what it is actually
    /// doing. `.auto` is the default and gets no badge, because a badge on everything is a badge on
    /// nothing.
    @ViewBuilder
    private func badge(for mode: GroupInterpolation) -> some View {
        switch mode {
        case .auto:
            EmptyView()
        case .crossFade:
            Text("fade")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        case .clean:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("fade")
            }
            .font(.caption2)
            .foregroundColor(.orange)
            .accessibilityLabel("Clean matching is not available yet; this group cross-fades.")
        }
    }

    @ViewBuilder
    private func menu(for chip: CanvasManager.MotionGroupChip) -> some View {
        Button(chip.isHidden ? "Show" : "Hide") {
            canvasManager.toggleMotionGroupHidden(chip.id)
        }
        Button("Solo") { canvasManager.soloMotionGroup(chip.id) }
        Divider()
        // The mode is per group (`PLAN.md` §10 decision 1: rough *and* clean, chosen per group), so
        // it belongs on the chip and nowhere else.
        Picker("Interpolation", selection: Binding(
            get: { chip.group.mode },
            set: { canvasManager.setMotionGroupMode($0, forGroup: chip.id) })) {
                Text("Auto").tag(GroupInterpolation.auto)
                Text("Clean (falls back to cross-fade)").tag(GroupInterpolation.clean)
                Text("Cross-fade").tag(GroupInterpolation.crossFade)
            }
        Divider()
        Button("Delete Group", role: .destructive) {
            canvasManager.removeMotionGroup(chip.id)
        }
    }

    // MARK: - The rest of the row

    /// `PLAN.md` §5.1.1's one-shot populate, and the mitigation the product owner named for the
    /// attached-limb limitation (`HANDOFF.md` §8 item 1): art that already encodes structure in its
    /// colours does not need tagging by hand.
    ///
    /// A *populate*, never a live binding — recolouring a stroke afterwards does not move it to
    /// another motion group — which is why the button says "Tag by Colour" rather than anything that
    /// sounds continuous.
    private var colourBakeButton: some View {
        Button("Tag by Colour") {
            let created = canvasManager.tagMotionGroupsByStrokeColour(
                in: canvasManager.interpolationReferences)
            note = created.isEmpty
                ? "The references are all one colour."
                : "Made \(created.count) groups from the colours."
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(canvasManager.interpolationReferences.isEmpty)
        .accessibilityIdentifier("interpolate.tagByColour")
    }

    /// Phase 4's whole-frame binding is not an artist-facing object and gets no chip
    /// (`HANDOFF.md` §5.10). Saying so in a sentence is better than an empty row that looks broken —
    /// and it names the two ways out, which is the actual help.
    private var wholeFrameNote: some View {
        Text("Moving as one group. Tag by colour, or Generate on a drawing with parts that move differently.")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.6))
            .lineLimit(2)
            .accessibilityIdentifier("interpolate.wholeFrameNote")
    }
}
