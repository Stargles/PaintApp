import SwiftUI

struct AnimationTimeline: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var timelineHeight: CGFloat = 250

    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?

    private let rowHeight: CGFloat = 34
    private let rulerHeight: CGFloat = 18
    private let collapsedHeight: CGFloat = 48
    private let minExpandedHeight: CGFloat = 130
    private let dragHandleHeight: CGFloat = 12

    private var isCollapsed: Bool {
        timelineHeight <= collapsedHeight + 2
    }

    // Tapping a frame that's already the current playhead position opens the block's options menu
    // (ToonSquid-style: first tap moves the cursor there, a second tap on the same spot opens it).
    // Set by TimelineTrackView via onRequestBlockMenu.
    @State private var showBlockMenu = false
    @State private var menuLayerIndex: Int?
    @State private var menuCelIndex: Int?

    // Press-and-hold reorder state for the pinned name column.
    @State private var draggingRowID: UUID?
    @State private var dragOffsetRows: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            if isCollapsed {
                collapsedBar
            } else {
                miniToolbar
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        layerNameColumn
                        TimelineTrackView(
                            canvasManager: canvasManager,
                            rowHeight: rowHeight,
                            rulerHeight: rulerHeight,
                            onRequestBlockMenu: { layerIndex, celIndex in
                                menuLayerIndex = layerIndex
                                menuCelIndex = celIndex
                                showBlockMenu = true
                            }
                        )
                    }
                    .frame(height: contentHeight)
                }
                .frame(height: max(0, timelineHeight - toolbarHeight - dragHandleHeight))
            }
        }
        .frame(height: timelineHeight)
        .background(Color.black)
        .onDisappear { playbackTimer?.invalidate() }
        .confirmationDialog("Block Options", isPresented: $showBlockMenu, titleVisibility: .hidden) {
            if let layerIndex = menuLayerIndex, let celIndex = menuCelIndex {
                Button("Copy") { canvasManager.duplicateCel(layerIndex: layerIndex, celIndex: celIndex) }
                Button("Select Multiple") { }.disabled(true)
                Button("Extend to End") { canvasManager.extendCelToEnd(layerIndex: layerIndex, celIndex: celIndex) }
                Button("Clear") { canvasManager.clearCel(layerIndex: layerIndex, celIndex: celIndex) }
                Button("Delete", role: .destructive) { canvasManager.deleteCel(layerIndex: layerIndex, celIndex: celIndex) }
                    .disabled(canvasManager.layers[layerIndex].cels.count <= 1)
            }
        }
    }

    private var toolbarHeight: CGFloat {
        38
    }

    private var contentHeight: CGFloat {
        rulerHeight + CGFloat(max(canvasManager.layerStackRows.count, 1)) * (rowHeight + 2) + 8
    }

    // MARK: - Drag handle

    private var dragHandle: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 32, height: 4)
                .padding(.top, 4)
        }
        .frame(height: dragHandleHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let newHeight = timelineHeight - value.translation.height
                    timelineHeight = min(max(newHeight, collapsedHeight), maxTimelineHeight)
                }
                .onEnded { _ in }
        )
    }

    private var maxTimelineHeight: CGFloat {
        UIScreen.main.bounds.height * 0.55
    }

    // MARK: - Collapsed

    private var collapsedBar: some View {
        HStack(spacing: 16) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: { canvasManager.stepFrame(by: -1) }) {
                Image(systemName: "backward.frame.fill")
            }
            Button(action: { canvasManager.stepFrame(by: 1) }) {
                Image(systemName: "forward.frame.fill")
            }
            Button(action: { canvasManager.goToFrame(0) }) {
                Image(systemName: "backward.end.fill")
            }
            Button(action: { canvasManager.goToFrame(canvasManager.sceneFrameCount - 1) }) {
                Image(systemName: "forward.end.fill")
            }
            Button(action: { canvasManager.isOnionSkinEnabled.toggle() }) {
                Image(systemName: canvasManager.isOnionSkinEnabled ? "square.stack.3d.forward.dottedline.fill" : "square.stack.3d.forward.dottedline")
            }
            .foregroundColor(canvasManager.isOnionSkinEnabled ? .blue : .white)

            Spacer()

            Text("Frame \(canvasManager.currentFrame + 1)/\(canvasManager.sceneFrameCount)")
                .font(.caption)
                .foregroundColor(.gray)
                .accessibilityIdentifier("timeline.frameLabel")

            Button(action: { timelineHeight = max(minExpandedHeight, contentHeight.rounded()) }) {
                Image(systemName: "chevron.up")
            }
        }
        .foregroundColor(.white)
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Expanded mini toolbar

    private var miniToolbar: some View {
        HStack(spacing: 14) {
            Button(action: { canvasManager.goToFrame(0) }) {
                Image(systemName: "backward.end.fill")
            }
            Button(action: { canvasManager.isOnionSkinEnabled.toggle() }) {
                Image(systemName: canvasManager.isOnionSkinEnabled ? "square.stack.3d.forward.dottedline.fill" : "square.stack.3d.forward.dottedline")
            }
            .foregroundColor(canvasManager.isOnionSkinEnabled ? .blue : .white)

            Button(action: { canvasManager.isLoopEnabled.toggle() }) {
                Image(systemName: "repeat")
            }
            .foregroundColor(canvasManager.isLoopEnabled ? .blue : .white)

            Button(action: { canvasManager.stepFrame(by: -1) }) {
                Image(systemName: "backward.fill")
            }
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: { canvasManager.stepFrame(by: 1) }) {
                Image(systemName: "forward.fill")
            }
            Button(action: { canvasManager.goToFrame(canvasManager.sceneFrameCount - 1) }) {
                Image(systemName: "forward.end.fill")
            }

            Spacer()

            TextField("Scene", text: $canvasManager.projectName)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .frame(width: 110)

            Text("Frame \(canvasManager.currentFrame + 1)/\(canvasManager.sceneFrameCount)")
                .font(.caption)
                .foregroundColor(.gray)
                .accessibilityIdentifier("timeline.frameLabel")

            Text("\(canvasManager.fps) fps")
                .font(.caption)
                .foregroundColor(.gray)

            Button(action: { timelineHeight = collapsedHeight }) {
                Image(systemName: "chevron.down")
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Layer names (pinned, non-scrolling column)

    /// Mirrors the layer panel's row order exactly — same folder headers, same nesting, same
    /// collapse state — so the names line up with the track rows `TimelineTrackView` lays out from
    /// the same source. Rows reorder here too: press and hold one, then drag it up or down.
    private var layerNameColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: rulerHeight)
            ForEach(canvasManager.layerStackRows) { row in
                nameRow(row)
                    .frame(height: rowHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(draggingRowID == row.id ? 0.4 : 1)
                    .gesture(reorderGesture(for: row))
            }
        }
        .frame(width: 110)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func nameRow(_ row: LayerStackRow) -> some View {
        switch row {
        case .folder(let folderID, let depth):
            if let folder = canvasManager.folders.first(where: { $0.id == folderID }) {
                HStack(spacing: 3) {
                    Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .onTapGesture { canvasManager.toggleFolderExpanded(folderID) }
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                    Text(folder.name)
                        .font(.caption)
                        .foregroundColor(folder.isVisible ? .white : .gray)
                        .lineLimit(1)
                        .accessibilityIdentifier("timeline.folderName.\(folder.name)")
                }
                .padding(.leading, 6 + CGFloat(depth) * 10)
            }

        case .layer(_, let index, let depth) where canvasManager.layers.indices.contains(index):
            Text(canvasManager.layers[index].name)
                .font(.caption)
                .foregroundColor(index == canvasManager.currentLayerIndex ? .blue : .white)
                .lineLimit(1)
                .padding(.leading, 8 + CGFloat(depth) * 10)
                .accessibilityIdentifier("timeline.layerName.\(index)")

        default:
            EmptyView()
        }
    }

    /// Press and hold for half a second, then drag: the same reorder gesture the layer panel uses,
    /// resolved here by counting how many fixed-height rows the finger travelled.
    private func reorderGesture(for row: LayerStackRow) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in draggingRowID = row.id }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(_, let drag?) = value, draggingRowID == row.id else { return }
                dragOffsetRows = Int((drag.translation.height / (rowHeight + 2)).rounded())
            }
            .onEnded { _ in
                defer { draggingRowID = nil; dragOffsetRows = 0 }
                guard draggingRowID == row.id, dragOffsetRows != 0 else { return }
                commitReorder(of: row, byRows: dragOffsetRows)
            }
    }

    /// Applies a drag of `delta` rows (positive = downward on screen = lower in the stack) by
    /// resolving what the moved row would come to rest between, then handing that to the same
    /// restack calls the layer panel uses.
    private func commitReorder(of row: LayerStackRow, byRows delta: Int) {
        let rows = canvasManager.layerStackRows
        guard let from = rows.firstIndex(where: { $0.id == row.id }) else { return }
        var reordered = rows
        let moved = reordered.remove(at: from)
        let target = min(max(from + delta, 0), reordered.count)
        reordered.insert(moved, at: target)
        guard let newIndex = reordered.firstIndex(where: { $0.id == moved.id }) else { return }

        var parentFolderID: UUID?
        if newIndex > 0 {
            let above = reordered[newIndex - 1]
            parentFolderID = above.isFolder ? above.id : canvasManager.layers.first { $0.id == above.id }?.parentFolderID
        }

        func anchor(_ below: LayerStackRow?) -> CanvasManager.StackAnchor {
            guard let below else { return .bottom }
            return below.isFolder ? .folder(below.id) : .layer(below.id)
        }

        if moved.isFolder {
            var contents = canvasManager.folderSubtree(moved.id)
            for index in canvasManager.descendantLayerIndices(ofFolder: moved.id) {
                contents.insert(canvasManager.layers[index].id)
            }
            let below = reordered[(newIndex + 1)...].first { !contents.contains($0.id) }
            canvasManager.restackFolder(moved.id, above: anchor(below), parentFolderID: parentFolderID)
        } else {
            let below = reordered.indices.contains(newIndex + 1) ? reordered[newIndex + 1] : nil
            canvasManager.restackLayer(moved.id, above: anchor(below), parentFolderID: parentFolderID)
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            let interval = 1.0 / Double(max(canvasManager.fps, 1))
            playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                DispatchQueue.main.async {
                    canvasManager.stepFrame(by: 1)
                }
            }
        } else {
            playbackTimer?.invalidate()
            playbackTimer = nil
        }
    }
}
