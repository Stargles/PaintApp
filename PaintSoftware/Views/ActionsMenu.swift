import SwiftUI
import PhotosUI

struct ActionsMenu: View {
    @ObservedObject var canvasManager: CanvasManager
    /// **The one panel that can open another panel.** Every other row here is a direct action, a
    /// `PhotosPicker` or an inert stub, so this view needed nothing but the manager until "Add Text"
    /// arrived — text is a *mode*, and entering it means swapping this menu for the text tool's own
    /// settings panel. `ADD_TEXT.md` §1 calls threading this binding through the change that "lands
    /// first and alone", because `ActionsMenu` is shared by every panel in the app and a change here
    /// wants to be bisectable on its own.
    @Binding var activePanel: ActivePanel
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var notice: String?
    /// Live slider position for the padding control. The (buffer-resizing) commit happens only on
    /// release, in `onEditingChanged`, so dragging the thumb doesn't re-render every layer per tick;
    /// this just tracks the thumb + the px readout meanwhile.
    @State private var paddingDraft: Double = 0

    var body: some View {
        // Scrolled, not just stacked: the panel that hosts this is capped at a fixed height, and a
        // plain VStack taller than that cap doesn't clip — it overflows symmetrically, pushing the
        // title off the top and leaving rows drawn outside the panel's own rounded bounds.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Actions")
                .font(.headline)
                .foregroundColor(.white)
                .padding([.horizontal, .top])
                .padding(.bottom, 4)

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                row(icon: "photo.on.rectangle", title: canvasManager.activeLayerIsVector ? "Insert Photo (onto vector layer)" : "Insert Photo")
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task { await insertPhoto(newItem) }
            }

            addTextRow

            Button {
                canvasManager.flipCanvas(horizontal: true)
            } label: {
                row(icon: "arrow.left.and.right", title: "Flip Horizontal")
            }

            Button {
                canvasManager.flipCanvas(horizontal: false)
            } label: {
                row(icon: "arrow.up.and.down", title: "Flip Vertical")
            }

            paddingControl

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

            pencilOnlyToggle

            renderResolutionControl

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

            // Debug capture: record what the artist actually did, hand us the file. Default OFF and
            // inert while off — see `ActionRecorder.isCapturing`.
            ActionRecorderSection(canvasManager: canvasManager)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

            Button { notice = "Cut isn't available yet" } label: {
                row(icon: "scissors", title: "Cut")
            }
            Button { notice = "Copy isn't available yet" } label: {
                row(icon: "doc.on.doc", title: "Copy")
            }
            Button { notice = "Paste isn't available yet" } label: {
                row(icon: "doc.on.clipboard", title: "Paste")
            }
            Button { notice = "Drawing guides aren't available yet" } label: {
                row(icon: "grid", title: "Drawing Guide")
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Enters the text tool and swaps this menu for the text tool's settings panel — the only way
    /// into `Tool.text`, since the top toolbar has no text icon.
    ///
    /// **Disabled rather than hidden where text cannot go, with the reason underneath it.** The row
    /// is the feature's only signpost: hidden, "can this app do text" has no answer on the layer the
    /// artist happens to be standing on, and they conclude it cannot.
    ///
    /// As of `ADD_TEXT.md` stage 3 the only kind that still refuses is `.value`, and that one is not
    /// a "yet": a layer holding no pixels has nothing for text to mean. Raster bakes the glyphs;
    /// vector keeps the object editable. The row was disabled on vector through stage 1 precisely so
    /// that nothing had to be un-shipped when this arrived.
    ///
    /// `Tool.textUnavailableReason` is where the answer lives, keyed off the layer's *kind*: the
    /// caption and the disabled state read one value, so they cannot disagree about whether the row
    /// works, and a fourth `LayerKind` cannot quietly inherit "text is fine here".
    private var addTextRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // No `commitAllInteractiveState()`, and its absence is the point — see
                // `CanvasManager.enterTextMode`, and `Binding.toggleSettingsPanel` for the rule it
                // is following. Both statements are that rule: enter the mode, open its panel, bake
                // nothing on the way.
                canvasManager.enterTextMode()
                $activePanel.toggleSettingsPanel(.text)
            } label: {
                row(icon: "textformat", title: "Add Text", enabled: textUnavailableReason == nil)
            }
            .disabled(textUnavailableReason != nil)
            .accessibilityIdentifier("actions.addTextRow")

            if let textUnavailableReason {
                Text(textUnavailableReason)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.leading, 24)   // clears the row's icon column, so it reads as the row's own note
                    .padding(.bottom, 6)
            }
        }
    }

    /// Nil when "Add Text" is usable on the layer the artist is standing on. Recomputed per render
    /// off `activeLayerKind`, so selecting another layer enables or disables the row with no state
    /// of its own to keep in step.
    private var textUnavailableReason: String? {
        Tool.textUnavailableReason(onLayerOfKind: canvasManager.activeLayerKind)
    }

    /// Whether a finger may draw, or only an Apple Pencil. Phrased as "fingers can paint" — the
    /// state the user is actually choosing between — rather than as the `pencilOnlyDrawing` flag it
    /// sets, which is inverted and reads backwards on a toggle. Persists across launches.
    private var pencilOnlyToggle: some View {
        Toggle(isOn: Binding(get: { !canvasManager.pencilOnlyDrawing },
                             set: { canvasManager.pencilOnlyDrawing = !$0 })) {
            HStack {
                Image(systemName: "hand.draw").frame(width: 24)
                Text("Fingers Can Paint")
            }
            .foregroundColor(.white)
        }
        .tint(.blue)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityIdentifier("actions.fingersCanPaintToggle")
    }

    /// How large the live canvas's composites are rendered (see `RenderResolution`). Persists across
    /// launches, like the toggle above it and unlike `Compositor.backend`, which is a development
    /// seam and deliberately not a user choice.
    ///
    /// **Sits directly under "Fingers Can Paint" rather than in its own section**, because the two are
    /// the same kind of thing: a preference about this iPad and this artist's hands, rather than a
    /// command that does something to the drawing. Everything above the divider acts on the document;
    /// everything below it is a setting.
    ///
    /// A segmented picker, not a slider: there are three values and the artist should be able to see
    /// all of them and land on one exactly. The subtitle says what the trade *is*, because "50%" on
    /// its own does not tell anybody that the export is unaffected — which is the fact that makes the
    /// setting safe to leave on.
    private var renderResolutionControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "square.resize").frame(width: 24)
                Text("Render Resolution")
                Spacer()
            }
            .foregroundColor(.white)

            Picker("Render Resolution", selection: $canvasManager.renderResolution) {
                ForEach(RenderResolution.allCases) { resolution in
                    Text(resolution.title).tag(resolution)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("actions.renderResolutionPicker")

            Text("Lower settings redraw layered artwork faster and look softer while you work. "
                 + "Your artwork, exports and thumbnails are always saved at full size.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Adjustable light-grey drawable margin around the canvas (see `CanvasManager.setCanvasPadding`).
    /// The px readout follows the thumb live; the actual resize commits on release.
    private var paddingControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "square.dashed").frame(width: 24)
                Text("Canvas Padding")
                Spacer()
                Text("\(Int(paddingDraft.rounded())) px").foregroundColor(.gray)
            }
            .foregroundColor(.white)

            Slider(
                value: $paddingDraft,
                in: Double(canvasManager.canvasPaddingRange.lowerBound)...Double(canvasManager.canvasPaddingRange.upperBound),
                onEditingChanged: { editing in
                    if !editing { canvasManager.setCanvasPadding(CGFloat(paddingDraft)) }
                }
            )
            .accessibilityIdentifier("actions.paddingSlider")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear { paddingDraft = Double(canvasManager.canvasPadding) }
    }

    /// `enabled` greys the row itself rather than leaning on `.disabled`'s own dimming, which this
    /// row never gets: the explicit `.foregroundColor(.white)` below wins over it, so a disabled row
    /// left to SwiftUI would look exactly like a working one and simply ignore taps.
    private func row(icon: String, title: String, enabled: Bool = true) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24)
            Text(title)
            Spacer()
        }
        .foregroundColor(enabled ? .white : Color.white.opacity(0.35))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func insertPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        await MainActor.run {
            canvasManager.insertImage(image)
        }
    }
}
