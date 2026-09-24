import SwiftUI
import UIKit

/// TODO (104) — the owner: *"In actions should be cut, copy, paste, flip horizontal, flip vertical,
/// export in that order."* Everything that used to live here besides those six rows has moved out:
/// Resize Canvas, Canvas Padding, Bake Precise Strokes, Fingers Can Paint, Render Resolution and the
/// recorder section are `SettingsMenu` now, and Insert Photo/Video, Stream Screen, Add Text and the
/// three shape/gradient rows TODO (103) added are `AddMenu`. This is what is left, and nothing in it
/// opens another panel any more, so — unlike `AddMenu` — it needs no `activePanel` binding.
struct ActionsMenu: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var notice: String?
    @State private var showingExport = false

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
        .sheet(isPresented: $showingExport) {
            ExportSheet(canvasManager: canvasManager)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Actions")
                .font(.headline)
                .foregroundColor(.white)
                .padding([.horizontal, .top])
                .padding(.bottom, 4)

            cutRow
            copyRow
            pasteRow

            Button {
                canvasManager.flipCanvas(horizontal: true)
            } label: {
                row(icon: "arrow.left.and.right", title: "Flip Horizontal")
            }
            .accessibilityIdentifier("actions.flipHorizontalRow")

            Button {
                canvasManager.flipCanvas(horizontal: false)
            } label: {
                row(icon: "arrow.up.and.down", title: "Flip Vertical")
            }
            .accessibilityIdentifier("actions.flipVerticalRow")

            exportRow

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Cut / Copy / Paste (TODO (104))
    //
    // These three did not exist before — every row here used to raise "Cut isn't available yet" and
    // its two siblings. The orchestrating brief's instruction was to find what the app already has
    // for a selection's copy/paste and wire it rather than invent a second clipboard; a repo-wide
    // search turned up nothing shaped like "copy the pixels under a selection" (the timeline's own
    // Copy/Paste, `CanvasManager.copyCel`/`pasteCel`, is a single-slot clipboard for a whole *cel*
    // block and requires an empty target slot — the wrong shape for "copy this drawing, paste it
    // somewhere with something already on it"). So this wires the one clipboard that already exists
    // system-wide, `UIPasteboard`, onto the primitives the Select panel's own Fill/Clear rows already
    // use to answer "what are this cel's pixels" and "remove what is inside the loop":
    // `PixelOps.rasterize` (the exact flatten `fillSelection`/`clearSelectionPixels` call "the cel's
    // pixels", vector or raster alike) and `clearSelectionPixels()` itself for Cut's second half.

    /// Requires an active selection, the same gate `SelectPanel`'s Fill/Clear rows already dim behind
    /// with no built-in disabled look of its own (`row(enabled:)` mirrors it here).
    private var cutRow: some View {
        Button {
            guard copySelectionToPasteboard() else { return }
            canvasManager.clearSelectionPixels()
        } label: {
            row(icon: "scissors", title: "Cut", enabled: canvasManager.selection != nil)
        }
        .disabled(canvasManager.selection == nil)
        .accessibilityIdentifier("actions.cutRow")
    }

    private var copyRow: some View {
        Button {
            if !copySelectionToPasteboard() {
                notice = "Nothing selected to copy."
            }
        } label: {
            row(icon: "doc.on.doc", title: "Copy", enabled: canvasManager.selection != nil)
        }
        .disabled(canvasManager.selection == nil)
        .accessibilityIdentifier("actions.copyRow")
    }

    private var pasteRow: some View {
        Button {
            guard let image = UIPasteboard.general.image else {
                notice = "Nothing to paste — copy or cut a selection first."
                return
            }
            canvasManager.insertImage(image)
        } label: {
            row(icon: "doc.on.clipboard", title: "Paste", enabled: canvasManager.canvasSize != nil)
        }
        .disabled(canvasManager.canvasSize == nil)
        .accessibilityIdentifier("actions.pasteRow")
    }

    /// Renders the current selection's bounding box out of the active cel's flattened pixels and sets
    /// it on the system pasteboard. False when there is no selection, no active cel to read, or the
    /// crop is degenerate — the three guards `fillSelection`/`clearSelectionPixels` already state for
    /// "the same cel this selection was drawn on".
    @discardableResult
    private func copySelectionToPasteboard() -> Bool {
        guard let selection = canvasManager.selection, let canvasSize = canvasManager.canvasSize,
              canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
              canvasManager.layers[canvasManager.currentLayerIndex].id == selection.layerID,
              let celIndex = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex,
                                                          atFrame: canvasManager.currentFrame),
              canvasManager.layers[canvasManager.currentLayerIndex].cels[celIndex].id == selection.celID
        else { return false }
        let cel = canvasManager.layers[canvasManager.currentLayerIndex].cels[celIndex]
        let flattened = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        guard let cropped = PixelOps.copiedSubimage(of: flattened, in: selection.path.boundingBoxOfPath)
        else { return false }
        UIPasteboard.general.image = cropped
        return true
    }

    /// TODO item (29) — RENDER.md §3.9. The animation as video, or one frame as an image.
    ///
    /// **The last row, because it is the last thing you do to a document.**
    ///
    /// A sheet rather than a plain action, for the wait §3.9 asks visible progress for: it has to be
    /// cancellable and has to end somewhere the file can be picked up from.
    private var exportRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingExport = true
            } label: {
                row(icon: "square.and.arrow.up", title: "Export",
                    enabled: canvasManager.canvasSize != nil)
            }
            .disabled(canvasManager.canvasSize == nil)
            .accessibilityIdentifier("actions.exportRow")

            Text("Saves the animation as a video, or the frame you are on as an image, at the "
                 + "Render Resolution in Settings.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.leading, 24)
                .padding(.bottom, 6)
        }
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
}
