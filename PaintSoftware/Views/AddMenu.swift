import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Combine   // objectWillChange.send()

/// TODO (103) — the owner: *"The add button (+) is located under actions. Make it a seperate
/// independant icon on the top bar. Additionally, put other things under the add like add
/// square/rectangle, circle/ellipse, add linear gradient."* TODO (100) had already pulled these four
/// rows into a submenu inside `ActionsMenu`; this promotes that submenu to a toolbar icon of its own
/// and adds the three new rows after it.
///
/// **The one panel besides `ActionsMenu` that needs the `activePanel` binding**, and for the same
/// reason `ActionsMenu` first grew it: "Add Text" is a mode change, not a direct action, and entering
/// it swaps this menu for the text tool's own settings panel.
struct AddMenu: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var activePanel: ActivePanel
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var notice: String?
    @State private var showingStreamConnect = false

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
        .sheet(isPresented: $showingStreamConnect) {
            StreamConnectSheet(canvasManager: canvasManager)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Add")
                .font(.headline)
                .foregroundColor(.white)
                .padding([.horizontal, .top])
                .padding(.bottom, 4)

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                row(icon: "photo.on.rectangle", title: canvasManager.activeLayerIsVector ? "Insert Photo (onto vector layer)" : "Insert Photo")
            }
            .accessibilityIdentifier("add.insertPhotoRow")
            .onChange(of: photoPickerItem) { _, newItem in
                Task { await insertPhoto(newItem) }
            }

            // **VIDEO.md stage 4, and it is deliberately the picker beside the photo one rather than
            // a row inside it.** §2.1 gives a video its own vector layer whatever the active layer
            // is, so the two verbs differ in more than the file they take — the photo row's title
            // even changes to say which layer it will land on, and this one never can.
            PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                row(icon: "film", title: "Insert Video (new layer)")
            }
            .accessibilityIdentifier("add.insertVideoRow")
            .onChange(of: videoPickerItem) { _, newItem in
                Task { await insertVideo(newItem) }
            }

            streamScreenRow
            addTextRow

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

            rectangleRow
            ellipseRow
            linearGradientRow

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
            .accessibilityIdentifier("add.addTextRow")

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

    /// **STREAM.md §5.7.** After Insert Video because it is the same verb with a different source: a
    /// picture of the computer's screen, live, in its own vector layer, movable like a video. The
    /// sheet takes the laptop's address and connects; the layer appears on the laptop's first answer.
    ///
    /// Disabled with no canvas, as Rectangle/Ellipse/Linear Gradient are, since there is nothing to
    /// put the layer in.
    private var streamScreenRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingStreamConnect = true
            } label: {
                row(icon: "display", title: "Stream Screen (new layer)",
                    enabled: canvasManager.canvasSize != nil)
            }
            .disabled(canvasManager.canvasSize == nil)
            .accessibilityIdentifier("add.streamScreenRow")

            Text("Shows a computer's screen live, as a layer. Needs the PaintApp streamer running "
                 + "on the computer and both on the same Tailscale network.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.leading, 24)   // clears the row's icon column, as "Add Text" does
                .padding(.bottom, 6)
        }
    }

    /// TODO (103) — the owner's *"add square/rectangle, circle/ellipse"*. **There is no dedicated
    /// shape tool**: today a rectangle or oval only ever arrives from holding a pen/pencil stroke
    /// still, which `ShapeDetector` reads and `CanvasManager.beginInteractiveShape` turns into an
    /// adjustable shape with on-canvas handles (`ShapeOverlayView`), committed by lifting the pencil
    /// or cancelled by tapping away. That machinery does not care where the geometry came from, so
    /// this inserts a **default rectangle the artist then sizes** — the same adjustable state a held
    /// stroke would have produced, with empty `samples` (which `ShapeDetector.collapseSamplesToShape`
    /// already treats as a uniform half-pressure outline, since a recognized shape gesture with no
    /// pressure profile of its own answers exactly the same way).
    private var rectangleRow: some View {
        Button {
            insertDefaultShape(kind: .rectangle)
        } label: {
            row(icon: "rectangle", title: "Rectangle", enabled: canvasManager.canvasSize != nil)
        }
        .disabled(canvasManager.canvasSize == nil)
        .accessibilityIdentifier("add.rectangleRow")
    }

    /// `ShapeGeometry.Kind` calls this case `.oval`, not `.ellipse` — see `rectangleRow`'s comment
    /// for the mechanism; this is the same call with the other kind.
    private var ellipseRow: some View {
        Button {
            insertDefaultShape(kind: .oval)
        } label: {
            row(icon: "circle", title: "Ellipse", enabled: canvasManager.canvasSize != nil)
        }
        .disabled(canvasManager.canvasSize == nil)
        .accessibilityIdentifier("add.ellipseRow")
    }

    /// Centred inside the artwork rect (or the canvas, on a document with no padding) at 60% of the
    /// shorter side — big enough to grab a handle on immediately, small enough that every handle
    /// starts on screen whatever the canvas's aspect ratio.
    private func insertDefaultShape(kind: ShapeGeometry.Kind) {
        guard let bounds = canvasManager.artworkSize.map({ CGRect(origin: .zero, size: $0) })
                        ?? canvasManager.canvasSize.map({ CGRect(origin: .zero, size: $0) }) else { return }
        let side = min(bounds.width, bounds.height) * 0.6
        let origin = CGPoint(x: bounds.midX - side / 2, y: bounds.midY - side / 2)
        let shape = ShapeGeometry(kind: kind, startPoint: origin,
                                  endPoint: CGPoint(x: origin.x + side, y: origin.y + side))
        canvasManager.beginInteractiveShape(shape)
        // `beginInteractiveShape` does not publish on its own — its only other caller
        // (`CanvasView.Coordinator`'s hold-timer) follows it with a direct, synchronous
        // `updateShapeOverlay()` on the UIKit side, which this button has no coordinator to reach.
        // Publishing here is the SwiftUI-side equivalent: it is what gets `CanvasView.updateUIView`
        // to run and call that same method, so the shape's preview actually appears instead of
        // sitting in the model with nothing on screen to show for it.
        canvasManager.objectWillChange.send()
        // Close the menu so the artist sees the handles they are meant to drag — the same reason
        // `addTextRow` above hands off to a settings panel instead of leaving this one open.
        activePanel = .none
    }

    /// TODO (103) — the owner's *"add linear gradient"*. §4.5's value layer is flat colour only;
    /// `ValueFill.gradient` (Layer.swift) is the linear-gradient case this row adds a layer with,
    /// rather than a new `LayerKind` — the artist edits its two stops and its direction from the
    /// same settings bar the flat-colour swatch already lives in (`LayerOptionsPanel`).
    private var linearGradientRow: some View {
        Button {
            canvasManager.addValueLayer(gradient: .default)
            activePanel = .none
        } label: {
            row(icon: "square.lefthalf.filled", title: "Linear Gradient", enabled: canvasManager.canvasSize != nil)
        }
        .disabled(canvasManager.canvasSize == nil)
        .accessibilityIdentifier("add.linearGradientRow")
    }

    /// Nil when "Add Text" is usable on the layer the artist is standing on. Recomputed per render
    /// off `activeLayerKind`, so selecting another layer enables or disables the row with no state
    /// of its own to keep in step.
    private var textUnavailableReason: String? {
        Tool.textUnavailableReason(onLayerOfKind: canvasManager.activeLayerKind)
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

    /// **A clip is loaded as a file, never as `Data`** — which is the one respect this path cannot
    /// copy the photo one above it. A photo is a few megabytes and a `UIImage` is where it has to end
    /// up anyway; a video is unbounded, its payload stays a file for its whole life (VIDEO.md §4.1),
    /// and `loadTransferable(type: Data.self)` on a half-gigabyte clip is a half-gigabyte of resident
    /// memory on the device this app's `Compositor` header already documents jetsam killing.
    ///
    /// `consumingSource: true` because the file handed back here is `PickedMovie`'s own copy: the
    /// system deletes its export the moment the transfer closure returns, so that copy is ours to
    /// move rather than copy again.
    private func insertVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
            return await MainActor.run { notice = "That video could not be read." }
        }
        await MainActor.run {
            if !canvasManager.insertVideo(at: movie.url, consumingSource: true) {
                try? FileManager.default.removeItem(at: movie.url)
                notice = "That video could not be read."
            }
        }
    }
}

/// **A picked movie, as a file rather than as bytes** — the `Transferable` the video picker loads.
///
/// `PhotosPickerItem` will hand a clip over as `Data`, and doing that is what this type exists to
/// avoid: see `AddMenu.insertVideo`. The import closure has to copy, because the file it is
/// given is deleted as soon as it returns; `CanvasManager.insertVideo` then *moves* that copy into
/// `VideoImportStore`, so the picked clip is written twice on its way in and not three times.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let suffix = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString).\(suffix)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
