import SwiftUI

/// The Select tool's bottom-docked bar (Procreate reference: mode tabs across the top of the bar,
/// action icons across the bottom), shown whenever the Select tool is engaged — see `DrawingView`,
/// which docks this near the bottom the same way `MoveTransformBottomBar` docks for Move. The action
/// row (Duplicate/Fill/Clear/Deselect) is disabled until a selection actually exists; the mode
/// tabs and the outside-interaction toggle are available immediately so a mode can be picked before
/// the first selection is drawn.
struct SelectPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    private var hasSelection: Bool { canvasManager.selection != nil }

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

            if !hasSelection {
                Text("Draw a selection on the canvas with the mode above, or tap Move to transform the whole layer.")
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

    private func actionTab(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(hasSelection ? .white : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .disabled(!hasSelection)
    }
}
