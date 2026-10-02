import SwiftUI

/// "Export" — RENDER.md §3.9, the artist-facing half of stage 6.
///
/// Two products and one wait. The video is every frame playback would show, as H.264 in `.mp4`; the
/// image is one frame as PNG. **Neither composites anything** (§2.1) — both read the frames the
/// background baker has already written, and the progress bar below is literally the baker catching
/// up on the frames the artist has not visited yet.
///
/// ## Why a sheet and not four rows in the menu
///
/// Because the wait is the thing that needs somewhere to live. §3.9 asks for *visible progress*, and
/// an export of a cold three-hundred-frame document is a real wait — one that must be cancellable,
/// must say which frame it is on, and must end somewhere the artist can pick the file up from. That
/// is a modal, and it is the same argument `CanvasResizeSheet` makes two rows above it.
///
/// ## Where a finished export goes
///
/// **"Save to Photos" is the primary action** (TODO (126)) and `ShareLink` (§3.9's *"system share
/// sheet"*) stays beside it. Photos is the one the owner reaches for — an export lands in the camera
/// roll, and in whatever syncs it, in one tap — and it needs the app's only Photos permission, which
/// is add-only. The share sheet is kept because it is the way to Files, AirDrop and Mail, and "Send to
/// Computer" is a third, independent destination; none of the three replaces another.
struct ExportSheet: View {

    @ObservedObject var canvasManager: CanvasManager
    @StateObject private var session: FrameExportSession
    /// STREAM.md §5.8 — reused rather than duplicated: `StreamBar` already observes this same
    /// object for its own connected/not word, and `connectionStates` is `@Published` there.
    @ObservedObject private var streamCoordinator: ScreenStreamCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(canvasManager: CanvasManager) {
        self.canvasManager = canvasManager
        _session = StateObject(wrappedValue: FrameExportSession(manager: canvasManager))
        _streamCoordinator = ObservedObject(wrappedValue: canvasManager.streamCoordinator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Export")
                .font(.title2).fontWeight(.bold)

            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("export.caption")

            switch session.phase {
            case .idle:
                choices
            case .baking, .writing:
                running
            case .finished(let url):
                finished(url)
            case .failed(let sentence):
                failed(sentence)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A running export holds the baker's virtual playhead; leaving without releasing it would
        // leave the loop baking the export's range for an artist who has gone back to drawing.
        .onDisappear { session.cancel() }
    }

    // MARK: - The three states

    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            includePaddingOption

            Button {
                session.exportVideo()
            } label: {
                row(icon: "film", title: "Export Video", detail: videoDetail)
            }
            .accessibilityIdentifier("export.videoButton")

            Button {
                session.exportFrame()
            } label: {
                row(icon: "photo", title: "Export This Frame",
                    detail: "Frame \(canvasManager.currentFrame + 1) as a PNG, with transparency where "
                          + "the paper is hidden.")
            }
            .accessibilityIdentifier("export.frameButton")

            Button("Cancel") { dismiss() }
                .padding(.top, 6)
                .accessibilityIdentifier("export.closeButton")
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(statusLine)
                .font(.callout)
                .accessibilityIdentifier("export.status")

            ProgressView(value: session.phase.fraction ?? 0)
                .accessibilityIdentifier("export.progress")
                .accessibilityValue(String(Int((session.phase.fraction ?? 0) * 100)))

            Text("Frames that have not been rendered yet are being rendered now. You can leave this "
                 + "open — nothing is lost if you cancel.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Cancel") { session.cancel() }
                .accessibilityIdentifier("export.cancelButton")
        }
    }

    private func finished(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Export ready", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .accessibilityIdentifier("export.status")

            Text(url.lastPathComponent)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            Button {
                session.saveToPhotos(using: PhotoLibraryDestination())
            } label: {
                Label(saveToPhotosTitle, systemImage: saveToPhotosIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSaveToPhotos)
            .accessibilityIdentifier("export.saveToPhotos")

            photosNotice

            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("export.share")

            // STREAM.md §5.8. Beside Share rather than replacing it: the two destinations are
            // independent, and an artist mid-session on the laptop may want both.
            Button {
                session.sendToComputer()
            } label: {
                Label(sendToComputerTitle, systemImage: "laptopcomputer")
            }
            .disabled(!canSendToComputer)
            .accessibilityIdentifier("export.sendToComputer")

            if let sendResultText {
                Text(sendResultText)
                    .font(.caption)
                    .foregroundColor(sendResultIsFailure ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("export.sendResult")
            }

            HStack(spacing: 18) {
                Button("Export Something Else") { session.reset() }
                    .accessibilityIdentifier("export.againButton")
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("export.doneButton")
            }
        }
    }

    /// Enabled only while some laptop is connected, and not while a send is already running — a
    /// second tap is ignored rather than queued (STREAM.md §5.8).
    private var canSendToComputer: Bool {
        guard streamCoordinator.connectedEndpointForSending != nil else { return false }
        if case .sending = session.sendState { return false }
        return true
    }

    private var sendToComputerTitle: String {
        if case .sending(let sent, let total) = session.sendState, total > 0 {
            return "Sending… \(Self.byteCount(sent)) of \(Self.byteCount(total))"
        }
        return "Send to Computer"
    }

    private var sendResultText: String? {
        switch session.sendState {
        case .idle, .sending: return nil
        case .succeeded(let name): return "Saved on \(name)"
        case .failed(let reason): return reason
        }
    }

    private var sendResultIsFailure: Bool {
        if case .failed = session.sendState { return true }
        return false
    }

    /// TODO (127). Shown on a canvas with no padding too, saying so — a hidden option is a feature with
    /// no signpost, and the artist who adds padding later finds it waiting.
    private var includePaddingOption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle("Include Padding", isOn: $session.includePadding)
                .accessibilityIdentifier("export.includePaddingToggle")
            Text(canvasManager.canvasPadding > 0
                 ? "Off: the file is the artwork alone. On: the whole canvas, with the padding around it "
                   + "empty — transparent in an image, black in a video."
                 : "This canvas has no padding, so the file is the whole canvas either way.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// TODO (126). One tap on a saved file again would add it to the library twice, so a save that
    /// worked leaves the button done rather than armed.
    private var canSaveToPhotos: Bool {
        switch session.photosState {
        case .saving, .saved: return false
        case .idle, .denied, .failed: return true
        }
    }

    private var saveToPhotosTitle: String {
        switch session.photosState {
        case .saving: return "Saving to Photos…"
        case .saved: return "Saved to Photos"
        case .idle, .denied, .failed: return "Save to Photos"
        }
    }

    private var saveToPhotosIcon: String {
        session.photosState == .saved ? "checkmark.circle.fill" : "photo.on.rectangle.angled"
    }

    /// What to do when Photos did not take the file. The denial names the way back — the system asks
    /// only once, so after a "Don't Allow" the only door is Settings, and the artist should not have
    /// to know that.
    @ViewBuilder
    private var photosNotice: some View {
        switch session.photosState {
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text("PaintSoftware is not allowed to add to Photos. Open Settings, choose Photos, "
                     + "and allow adding photos, then come back and try again.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("export.photosNotice")
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(settings) }
                        .accessibilityIdentifier("export.openSettings")
                }
            }
        case .failed(let sentence):
            Text(sentence)
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("export.photosNotice")
        case .idle, .saving, .saved:
            EmptyView()
        }
    }

    private static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func failed(_ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(sentence, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("export.status")

            HStack(spacing: 18) {
                Button("Try Again") { session.reset() }
                    .accessibilityIdentifier("export.againButton")
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("export.closeButton")
            }
        }
    }

    // MARK: - Copy

    /// **The sentence that makes §2.8 visible.** The export's pixel size is the Render Resolution
    /// knob's, and an artist who has left it on Half is entitled to know that before they hand the
    /// file to somebody — which is exactly the promise the knob's own subtitle used to make in the
    /// opposite direction, and which this change corrects there too.
    private var caption: String {
        var parts: [String] = []
        if let size = exportSize {
            parts.append("\(Int(size.width)) × \(Int(size.height)) px "
                         + "(Render Resolution: \(canvasManager.renderResolution.title))")
        }
        parts.append("\(canvasManager.fps) fps")
        if let range = videoRange {
            // 1-based, like every other frame number the artist reads (2026-09-11) — `range` itself
            // stays the model's 0-based `ClosedRange` for `videoDetail`'s count and `exportVideo`'s
            // own use; only this sentence adds 1 to each bound.
            parts.append(range.count == 1 ? "1 frame"
                         : "frames \(range.lowerBound + 1)–\(range.upperBound + 1)")
        }
        return parts.joined(separator: " · ")
    }

    private var videoDetail: String {
        guard let range = videoRange else { return "H.264 video." }
        let seconds = Double(range.count) / Double(max(canvasManager.fps, 1))
        return String(format: "%d frames, about %.1f seconds of H.264 video (.mp4).",
                      range.count, seconds)
    }

    private var videoRange: ClosedRange<Int>? {
        FrameExport.frameRange(playbackStart: canvasManager.playbackStartFrame,
                               playbackEnd: canvasManager.playbackEndFrame,
                               contentEndFrame: canvasManager.contentEndFrame)
    }

    /// The size the export will actually be, read the way the baker reads it rather than
    /// recomputed — `liveCompositeSize` is where the knob is applied and there is one of it — and cut
    /// the way the driver cuts it: `exportRect` is the one answer to what the padding option leaves.
    private var exportSize: CGSize? {
        guard let canvasSize = canvasManager.canvasSize else { return nil }
        let tree = canvasManager.renderTree(atFrame: canvasManager.currentFrame)
        let rendered = canvasManager.liveCompositeSize(of: tree, canvasSize: canvasSize)
        return canvasManager.exportRect(renderedInto: rendered, includingPadding: session.includePadding).size
    }

    private var statusLine: String {
        switch session.phase {
        case .baking(let done, let total):
            return total == 1 ? "Rendering the frame…" : "Rendering frames — \(done) of \(total)"
        case .writing(let done, let total):
            return total == 1 ? "Writing the image…" : "Writing the video — \(done) of \(total)"
        case .idle, .finished, .failed:
            return ""
        }
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
