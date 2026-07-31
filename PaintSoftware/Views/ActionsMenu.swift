import SwiftUI
import PhotosUI

struct ActionsMenu: View {
    @ObservedObject var canvasManager: CanvasManager
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
                in: Double(CanvasManager.canvasPaddingRange.lowerBound)...Double(CanvasManager.canvasPaddingRange.upperBound),
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

    private func row(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24)
            Text(title)
            Spacer()
        }
        .foregroundColor(.white)
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
