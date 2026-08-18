import SwiftUI

/// The text tool's settings panel — **a placeholder, deliberately**.
///
/// This commit is `ADD_TEXT.md`'s "it lands first and alone": `Tool.text`, `ActivePanel.text`, the
/// `activePanel` binding into `ActionsMenu`, and the row that enters the mode. That is a change to
/// plumbing every panel in the app shares, so it ships with nothing else in it and can be bisected
/// to on its own. What goes here — the grouped font `Menu`, `sliderRow`s for size/tracking/line
/// height/line and paragraph spacing, the segmented alignment `Picker`, the colour swatch, all in
/// `StrokeSettingsPanel`'s shape inside the same 300×420 card — is the next branch's, alongside the
/// `UITextView` overlay and the bake.
///
/// Its being empty is the honest report of what the mode does today: it can be entered and left, and
/// a canvas touch made in it does nothing (`Tool.text.paintsOnCanvas` is false and there is no
/// overlay yet to take the touch instead).
///
/// Takes the manager it does not yet read so the call site in `DrawingView.panelView` is already the
/// one the next branch needs.
struct TextSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text")
                .font(.headline)
                .foregroundColor(.white)

            Text("Text mode is on. Its font, size and alignment controls arrive in the next update — "
                 + "for now there is nothing here to set.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("panel.textSettings")
    }
}
