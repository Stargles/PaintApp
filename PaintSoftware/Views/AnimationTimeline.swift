import SwiftUI

struct AnimationTimeline: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var isExpanded: Bool

    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?

    private let rowHeight: CGFloat = 34
    private let rulerHeight: CGFloat = 18

    // Tapping a frame that's already the current playhead position opens the block's options menu
    // (ToonSquid-style: first tap moves the cursor there, a second tap on the same spot opens it).
    // Set by TimelineTrackView via onRequestBlockMenu.
    @State private var showBlockMenu = false
    @State private var menuLayerIndex: Int?
    @State private var menuCelIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                miniToolbar
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
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
            } else {
                collapsedBar
            }
        }
        .background(Color.black)
        .onDisappear { playbackTimer?.invalidate() }
        .confirmationDialog("Block Options", isPresented: $showBlockMenu, titleVisibility: .hidden) {
            if let layerIndex = menuLayerIndex, let celIndex = menuCelIndex {
                Button("Copy") { canvasManager.duplicateCel(layerIndex: layerIndex, celIndex: celIndex) }
                Button("Select Multiple") { }.disabled(true)
                Button("Extend to End") { canvasManager.extendCelToEnd(layerIndex: layerIndex, celIndex: celIndex) }
                Button("Clear") { canvasManager.clearCel(layerIndex: layerIndex, celIndex: celIndex) }
                Button("Delete", role: .destructive) { canvasManager.deleteCel(layerIndex: layerIndex, celIndex: celIndex) }
            }
        }
    }

    private var contentHeight: CGFloat {
        rulerHeight + CGFloat(max(canvasManager.layers.count, 1)) * (rowHeight + 2) + 8
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

            Button(action: { isExpanded = true }) {
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

            Button(action: { isExpanded = false }) {
                Image(systemName: "chevron.down")
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Layer names (pinned, non-scrolling column)

    private var layerNameColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: rulerHeight)
            ForEach(Array(canvasManager.layers.enumerated().reversed()), id: \.element.id) { index, layer in
                Text(layer.name)
                    .font(.caption)
                    .foregroundColor(index == canvasManager.currentLayerIndex ? .blue : .white)
                    .lineLimit(1)
                    .frame(height: rowHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { canvasManager.currentLayerIndex = index }
            }
        }
        .frame(width: 90)
        .padding(.vertical, 4)
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
