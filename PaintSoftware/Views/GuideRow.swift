import SwiftUI

/// The guides on the frame under the playhead, and the two ways to fetch one from elsewhere.
///
/// **A list rather than a menu command, and that is the design call this required.** "Fetch a guide
/// from another frame" is one line at the model layer (a recipe has named guides by id), so the
/// work here is entirely about what the artist can see. Three separate problems all wanted the same
/// widget and it was worth designing once rather than three times:
///
/// - **Fetching itself** needs somewhere to offer link and duplicate, and somewhere to say which
///   guides a frame ended up with.
/// - **A second guide averages with the first** (`GuideSet.trajectories`), the least surprising rule
///   for two but invisible: the artist draws a second arc and the motion moves half as far as it
///   looks like it should. Two rows on screen is what makes that legible.
/// - **A linked guide is shared**, so editing its handles moves every frame that uses it. That's the
///   *point* of a link and a nasty surprise if you thought you had a copy, so the chip says so.
///
/// **The two toggles live here rather than on the command row, and that is not tidiness.** They
/// were on it, beside Commit and Remove; the trailing cluster grew from two buttons to four and
/// overran the centred Set-as-Reference/Generate/Reproject group, which the command row's `ZStack`
/// draws last — so on a portrait iPad the Guide button sat *underneath* Reproject and could not be
/// pressed at all (`isHittable == false`, found by the e2e). Moving them puts every guide control on
/// the row that lists the guides.
///
/// It sits under `MotionGroupRow` and appears only when there is a recipe, which is exactly when a
/// guide can exist — so a bar outside interpolate mode is unchanged.
struct GuideRow: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        let chips = canvasManager.guideChips
        let linkable = canvasManager.linkableGuideStrokes
        if hasRecipe {
            HStack(spacing: 8) {
                guideButton
                spacingButton
                if chips.isEmpty {
                    Text("no guides on this frame")
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

    /// Arms guide drawing. A toggle rather than a command, because the artist draws the guide on the
    /// *canvas* and the button only says which thing the next drag is.
    ///
    /// The same arm-and-draw shape as `MotionGroupRow`'s chips, and a button rather than a timeline
    /// gesture: press-and-hold already means drag-reorder, in every mode.
    ///
    /// Gated on `guideRefusal`, which is cheap — a guide needs a recipe to attach to, and offering
    /// the toggle without one would let the artist draw an arc that had nowhere to go.
    private var guideButton: some View {
        Button(canvasManager.isDrawingGuide ? "Drawing Guide…" : "Guide") {
            guard canvasManager.guideRefusal == nil else { return }
            canvasManager.isDrawingGuide.toggle()
        }
        .buttonStyle(.bordered)
        .tint(canvasManager.isDrawingGuide ? .teal : .gray)
        .accessibilityIdentifier("interpolate.guide")
    }

    /// Swaps the guide overlay between its two editors: "timing adjustment" against "geometric
    /// adjustment".
    ///
    /// A toggle and not a third arming state: shape handles and spacing dots sit on the same
    /// polyline, so both at once would put two meanings under one touch. Off means handles, which is
    /// the state an artist who has never pressed this button is in.
    ///
    /// Shown only when there is a guide on the frame *and* a chart to draw — keyframes one frame
    /// apart have no in-betweens to space, and a button that reveals nothing is worse than no button.
    @ViewBuilder
    private var spacingButton: some View {
        if hasASpacingChart {
            Button(canvasManager.isEditingGuideSpacing ? "Spacing" : "Shape") {
                canvasManager.isEditingGuideSpacing.toggle()
            }
            .buttonStyle(.bordered)
            .tint(canvasManager.isEditingGuideSpacing ? .orange : .gray)
            .accessibilityIdentifier("interpolate.guideSpacing")
        }
    }

    private var hasRecipe: Bool {
        canvasManager.interpolationTarget.flatMap {
            canvasManager.layers[$0.layer].cels[$0.cel].interpolation
        } != nil
    }

    /// Whether any visible guide has in-between frames to space. Cheap — it resolves a frame span and
    /// samples a curve; no evaluation, so it is safe in a `body`.
    private var hasASpacingChart: Bool {
        !canvasManager.isDrawingGuide
            && canvasManager.visibleGuideStrokes.contains { canvasManager.spacingChart(forGuide: $0.id) != nil }
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
        // `.combine` is what makes the chip an element at all. An identifier on a bare `HStack` binds
        // to nothing queryable — SwiftUI only promotes a non-interactive container to an
        // accessibility element when asked, so the chip was invisible to XCUITest and to VoiceOver
        // alike. `MotionGroupRow`'s chips are `Button`s and get this for free; these are not, because
        // there is nothing to select. The identifier is also the e2e's proof that a drag with Guide
        // armed became a guide rather than ink.
        .accessibilityElement(children: .combine)
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
    /// They answer different intents: link for a repeating cycle, where fixing the arc once should
    /// fix every frame of the walk; duplicate for a one-off, where the copy is a starting point to
    /// pull about. Collapsing them into a single "Use" would make the artist find out which one they
    /// got by editing it — the same reason Generate and Reproject are two buttons.
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
