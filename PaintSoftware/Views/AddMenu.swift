import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Combine   // objectWillChange.send()

/// TODO (103) — the owner: *"The add button (+) is located under actions. Make it a seperate
/// independant icon on the top bar. Additionally, put other things under the add like add
/// square/rectangle, circle/ellipse, add linear gradient."* TODO (100) had already pulled these four
/// rows into a submenu inside `ActionsMenu`; this promotes that submenu to a toolbar icon of its own
/// and adds the three new rows after it. The three are objects the artist places, not marks they
/// make: a solid rectangle, a solid ellipse and a gradient, each of the fill tool's own kind
/// (`CanvasManager+FillObjects.swift`).
///
/// **Every object row here primes rather than places** (TODO (149), `CanvasManager+Placement.swift`):
/// a tap arms the placement tool with that object, and the artist's next pen-down on the canvas puts
/// it down and drags it to size. The photo and video rows pick first and prime with what was picked.
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
                Task { await primePhoto(newItem) }
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
                Task { await primeVideo(newItem) }
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

    /// **The three objects with no file behind them — TODO (129), (128), (149).** Tapping one *primes* it:
    /// the next pen-down on the canvas places it and dragging sizes it (`CanvasManager.primeObject`),
    /// which is why the menu closes — the canvas is what the artist reaches for next. Tapping the row
    /// that is already primed puts it down again, and the row says which one that is.
    private func primeRow(_ object: PrimedObject, icon: String, title: String, identifier: String) -> some View {
        let primed = canvasManager.primedObject == object
        return Button {
            canvasManager.togglePrimedObject(object)
            activePanel = .none
        } label: {
            row(icon: icon, title: title, enabled: canvasManager.canvasSize != nil, primed: primed)
        }
        .disabled(canvasManager.canvasSize == nil)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(primed ? [.isSelected] : [])
    }

    private var rectangleRow: some View {
        primeRow(.rectangle, icon: "rectangle", title: "Rectangle", identifier: "add.rectangleRow")
    }

    private var ellipseRow: some View {
        primeRow(.ellipse, icon: "circle", title: "Ellipse", identifier: "add.ellipseRow")
    }

    /// TODO (128) — a gradient is an object in a vector layer, not a layer of its own. Its panel (the
    /// two colours and the direction) opens once it has been dragged out.
    private var linearGradientRow: some View {
        primeRow(.gradient, icon: "square.lefthalf.filled", title: "Linear Gradient", identifier: "add.linearGradientRow")
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
    ///
    /// `primed` tints the row blue: it is the object the next pen-down will place.
    private func row(icon: String, title: String, enabled: Bool = true, primed: Bool = false) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24)
            Text(title)
            Spacer()
        }
        .foregroundColor(primed ? .blue : (enabled ? .white : Color.white.opacity(0.35)))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// **A picked photo primes the placement tool rather than landing** (TODO (149)): the artist drags it
    /// out where they want it. The picker's selection is cleared once it is read, so choosing the same
    /// photo a second time — after putting the first priming down, say — still fires.
    private func primePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let image = (try? await item.loadTransferable(type: Data.self)).flatMap(UIImage.init(data:))
        await MainActor.run {
            photoPickerItem = nil
            guard let image, canvasManager.primeImage(image) else { return }
            activePanel = .none
        }
    }

    /// **A clip is loaded as a file, never as `Data`** — which is the one respect this path cannot
    /// copy the photo one above it. A photo is a few megabytes and a `UIImage` is where it has to end
    /// up anyway; a video is unbounded, its payload stays a file for its whole life (VIDEO.md §4.1),
    /// and `loadTransferable(type: Data.self)` on a half-gigabyte clip is a half-gigabyte of resident
    /// memory on the device this app's `Compositor` header already documents jetsam killing.
    ///
    /// The primed object owns the file from here (`CanvasManager.primeVideo`): the placement *moves* it
    /// into the document, and a priming that ends first deletes it. The system deletes its own export the
    /// moment the transfer closure returns, so the copy `PickedMovie` made is the only one.
    private func primeVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
            return await MainActor.run { notice = "That video could not be read." }
        }
        await MainActor.run {
            videoPickerItem = nil
            if canvasManager.primeVideo(at: movie.url) {
                activePanel = .none
            } else {
                try? FileManager.default.removeItem(at: movie.url)
                notice = "That video could not be read."
            }
        }
    }
}

/// **A picked movie, as a file rather than as bytes** — the `Transferable` the video picker loads.
///
/// `PhotosPickerItem` will hand a clip over as `Data`, and doing that is what this type exists to
/// avoid: see `AddMenu.primeVideo`. The import closure has to copy, because the file it is
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
