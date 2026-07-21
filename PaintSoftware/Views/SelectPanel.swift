import SwiftUI

struct SelectPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Select")
                .font(.headline)
                .foregroundColor(.white)
                .padding([.horizontal, .top])

            Picker("Mode", selection: Binding(
                get: { canvasManager.selectionMode },
                set: { canvasManager.beginSelection(mode: $0) }
            )) {
                ForEach(SelectionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if canvasManager.selectionMode == .automatic {
                VStack(alignment: .leading) {
                    Text("Tolerance: \(Int(canvasManager.magicWandTolerance * 100))%")
                        .foregroundColor(.white)
                    Slider(value: $canvasManager.magicWandTolerance, in: 0.02...1)
                }
                .padding(.horizontal)
            }

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 2) {
                actionRow(icon: "plus.square.on.square", title: "Duplicate") { canvasManager.beginDuplicate() }
                    .accessibilityIdentifier("selectPanel.duplicateButton")
                actionRow(icon: "paintbrush.fill", title: "Fill") { canvasManager.fillSelection() }
                    .accessibilityIdentifier("selectPanel.fillButton")
                actionRow(icon: "xmark.square", title: "Clear") { canvasManager.clearSelectionPixels() }
                    .accessibilityIdentifier("selectPanel.clearButton")
                actionRow(icon: "rectangle.badge.xmark", title: "Deselect") { canvasManager.deselect() }
                    .accessibilityIdentifier("selectPanel.deselectButton")
            }

            if !hasSelection {
                Text("Draw a selection on the canvas with the mode above, or tap Move to transform the whole layer.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
    }

    private var hasSelection: Bool { canvasManager.selection != nil }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 24)
                Text(title)
                Spacer()
            }
            .foregroundColor(hasSelection ? .white : .white.opacity(0.3))
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .disabled(!hasSelection)
    }
}
