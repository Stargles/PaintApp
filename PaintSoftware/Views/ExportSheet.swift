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
/// Delivery is `ShareLink` (§3.9's *"system share sheet"*), which is what `ActionRecorderControls`
/// already uses to get a file off the device: AirDrop, Files, Photos, Mail, all without this app
/// asking for a single permission.
struct ExportSheet: View {

    @ObservedObject var canvasManager: CanvasManager
    @StateObject private var session: FrameExportSession
    @Environment(\.dismiss) private var dismiss

    init(canvasManager: CanvasManager) {
        self.canvasManager = canvasManager
        _session = StateObject(wrappedValue: FrameExportSession(manager: canvasManager))
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
                    detail: "Frame \(canvasManager.currentFrame) as a PNG, with transparency where "
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
            Label("Ready to share", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .accessibilityIdentifier("export.status")

            Text(url.lastPathComponent)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("export.share")

            HStack(spacing: 18) {
                Button("Export Something Else") { session.reset() }
                    .accessibilityIdentifier("export.againButton")
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("export.doneButton")
            }
        }
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
            parts.append(range.count == 1 ? "1 frame" : "frames \(range.lowerBound)–\(range.upperBound)")
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
                               sceneFrameCount: canvasManager.sceneFrameCount)
    }

    /// The size the export will actually be, read the way the baker reads it rather than
    /// recomputed — `liveCompositeSize` is where the knob is applied and there is one of it.
    private var exportSize: CGSize? {
        guard let canvasSize = canvasManager.canvasSize else { return nil }
        let tree = canvasManager.renderTree(atFrame: canvasManager.currentFrame)
        return canvasManager.liveCompositeSize(of: tree, canvasSize: canvasSize)
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
