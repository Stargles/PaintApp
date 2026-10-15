import SwiftUI

struct LiquifySettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    let onEditBrush: () -> Void
    static let spec = StrokeSettingsSpec(title: "Liquify", idPrefix: "liquifyPanel", tool: .liquify)
    var body: some View {
        StrokeSettingsPanel(canvasManager: canvasManager, library: canvasManager.brushLibrary,
                            spec: Self.spec, onEditBrush: onEditBrush,
                            accessory: {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Liquify mode", selection: Binding(
                    get: { canvasManager.liquifyMode == .expand ? .pinch : canvasManager.liquifyMode },
                    set: { canvasManager.liquifyMode = $0 }
                )) {
                    Text("Push").tag(LiquifyMode.push)
                    Text(canvasManager.liquifyMode == .expand ? "Expand" : "Pinch").tag(LiquifyMode.pinch)
                    Text("Twirl").tag(LiquifyMode.twirl)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("liquifyPanel.modePicker")
                if canvasManager.liquifyMode == .pinch || canvasManager.liquifyMode == .expand {
                    Toggle("Expand", isOn: Binding(
                        get: { canvasManager.liquifyMode == .expand },
                        set: { canvasManager.liquifyMode = $0 ? .expand : .pinch }
                    ))
                    .foregroundColor(.white)
                    .accessibilityIdentifier("liquifyPanel.expandToggle")
                }
                Text("Move ink on this layer. A selection limits where it can move.")
                    .font(.caption).foregroundColor(.gray)
            }.padding(8)
        }, addMenuItems: { EmptyView() })
    }
}
