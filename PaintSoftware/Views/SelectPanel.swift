import SwiftUI

/// The Select tool's bottom-docked bar (Procreate reference: mode tabs across the top of the bar,
/// action icons across the bottom), shown whenever the Select tool is engaged — see `DrawingView`,
/// which docks this near the bottom the same way `MoveTransformBottomBar` docks for Move. The action
/// row (Duplicate/Fill/Recolour/Clear/Deselect) is disabled until a selection actually exists; the
/// mode tabs and the outside-interaction toggle are available immediately so a mode can be picked
/// before the first selection is drawn.
///
/// **Recolour sits beside Fill** rather than at the end of the row, because the two are the pair
/// that apply the currently picked colour and reading them together is what tells them apart. It is
/// captioned in one word for a plain layout reason: five tabs share a 360 pt bar, so 72 pt each, and
/// "Duplicate" was already the longest caption `.caption2` had to fit.
///
/// **It is the one action here that can refuse**, and it says why rather than going quietly grey —
/// `CanvasManager.recolorUnavailableReason`, the rule and the voice `MoveTransformBottomBar` states
/// for Mirror. At most one caption is ever on screen: the refusal replaces the "draw a selection"
/// hint rather than stacking under it.
struct SelectPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    private var hasSelection: Bool { canvasManager.selection != nil }

    /// Why Change Colour is off, or nil. Read once per body pass and used twice — to gate the button
    /// and to caption it — so the two can never disagree.
    private var recolorReason: String? { canvasManager.recolorUnavailableReason }

    var body: some View {
        VStack(spacing: 0) {
            if canvasManager.selectionMode == .automatic {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tolerance: \(Int(canvasManager.magicWandTolerance * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                    Slider(value: $canvasManager.magicWandTolerance, in: 0.02...1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            HStack(spacing: 6) {
                ForEach(SelectionMode.allCases) { mode in
                    modeTab(mode)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)

            divider

            HStack(spacing: 0) {
                actionTab(icon: "plus.square.on.square", title: "Duplicate") { canvasManager.beginDuplicate() }
                    .accessibilityIdentifier("selectPanel.duplicateButton")
                actionTab(icon: "paintbrush.fill", title: "Fill") { canvasManager.fillSelection() }
                    .accessibilityIdentifier("selectPanel.fillButton")
                actionTab(icon: "paintpalette.fill", title: "Recolour",
                          enabled: recolorReason == nil) { canvasManager.recolorSelection() }
                    .accessibilityIdentifier("selectPanel.recolorButton")
                actionTab(icon: "xmark.square", title: "Clear") { canvasManager.clearSelectionPixels() }
                    .accessibilityIdentifier("selectPanel.clearButton")
                actionTab(icon: "rectangle.badge.xmark", title: "Deselect") { canvasManager.deselect() }
                    .accessibilityIdentifier("selectPanel.deselectButton")
            }
            .padding(.vertical, 10)

            divider

            // A plain Button driving the switch look (rather than SwiftUI's native `Toggle`) so tapping
            // is a single reliable gesture end to end — a native Toggle bound through a custom
            // Binding(get:set:) intermittently didn't flip when activated via accessibility (VoiceOver/
            // XCUITest), while every other control in this bar is a Button and taps it consistently.
            Button {
                canvasManager.allowsPaintingOutsideSelection.toggle()
            } label: {
                HStack {
                    Text("Paint Outside Selection")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    switchIndicator
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("selectPanel.allowOutsideToggle")
            .accessibilityAddTraits(canvasManager.allowsPaintingOutsideSelection ? [.isSelected] : [])

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 360)
        .background(Color.black.opacity(0.95))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    /// A plain iOS-switch look-alike (capsule track + circular knob) purely for display — the
    /// enclosing Button owns the actual tap handling, see the comment above its call site.
    private var switchIndicator: some View {
        let isOn = canvasManager.allowsPaintingOutsideSelection
        return ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Color.blue : Color.white.opacity(0.25))
            Circle().fill(Color.white).padding(2)
        }
        .frame(width: 51, height: 31)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }

    private func modeTab(_ mode: SelectionMode) -> some View {
        let isActive = canvasManager.selectionMode == mode
        return Button {
            canvasManager.beginSelection(mode: mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.body)
                Text(mode.displayName)
                    .font(.caption2)
            }
            .foregroundColor(isActive ? .blue : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isActive ? Color.white.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .accessibilityIdentifier("selectPanel.mode.\(mode.rawValue)")
    }

    /// The one line under the bar, or none. Ordered by what the artist is most likely to have just
    /// pressed against: without a selection nothing in the row does anything, so that hint comes
    /// first; with one, a refusal is about the button they can now see is dim.
    private var caption: String? {
        if !hasSelection {
            return "Draw a selection on the canvas with the mode above, or tap Move to transform the whole layer."
        }
        return recolorReason
    }

    /// `enabled` is *additional* to `hasSelection`, never instead of it — every tab in this row is
    /// selection-scoped, and an action that is also unavailable for a reason of its own says so in
    /// the caption above.
    private func actionTab(icon: String, title: String, enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        let live = hasSelection && enabled
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(live ? .white : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .disabled(!live)
    }
}
