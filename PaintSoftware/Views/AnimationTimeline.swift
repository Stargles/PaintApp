import SwiftUI

struct AnimationTimeline: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var isExpanded: Bool

    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?

    @State private var committedZoom: CGFloat = 1.0
    @State private var liveZoomDelta: CGFloat = 1.0

    private let basePixelsPerFrame: CGFloat = 30
    private let zoomRange: ClosedRange<CGFloat> = 0.35...4.0
    private var pixelsPerFrame: CGFloat {
        basePixelsPerFrame * min(max(committedZoom * liveZoomDelta, zoomRange.lowerBound), zoomRange.upperBound)
    }
    private let rowHeight: CGFloat = 34
    private let rulerHeight: CGFloat = 18

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in liveZoomDelta = value }
            .onEnded { value in
                committedZoom = min(max(committedZoom * value, zoomRange.lowerBound), zoomRange.upperBound)
                liveZoomDelta = 1.0
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                miniToolbar
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                HStack(alignment: .top, spacing: 0) {
                    layerNameColumn
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 2) {
                                rulerRow
                                ForEach(Array(canvasManager.layers.enumerated().reversed()), id: \.element.id) { index, layer in
                                    celRow(layerIndex: index, layer: layer)
                                }
                            }
                            playheadColumn
                        }
                        .contentShape(Rectangle())
                        .gesture(zoomGesture)
                    }
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

    // MARK: - Ruler

    private var rulerRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<canvasManager.sceneFrameCount, id: \.self) { frame in
                Text("\(frame + 1)")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                    .frame(width: pixelsPerFrame, height: rulerHeight, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("timeline.ruler")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    canvasManager.goToFrame(Int(value.location.x / pixelsPerFrame))
                }
        )
    }

    private var playheadColumn: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.35))
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.accentColor).frame(width: 1.5)
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.accentColor).frame(width: 1.5)
            }
            .frame(width: pixelsPerFrame, height: contentHeight - 8)
            .offset(x: CGFloat(canvasManager.currentFrame) * pixelsPerFrame)
            .allowsHitTesting(false)
    }

    // MARK: - Cel rows

    private struct TimelineSegment: Identifiable {
        let id = UUID()
        enum Kind {
            case cel(celIndex: Int, cel: Cel)
            case gap(start: Int, length: Int)
        }
        let kind: Kind
    }

    private func segments(for layer: Layer) -> [TimelineSegment] {
        var result: [TimelineSegment] = []
        var cursor = 0
        let ordered = layer.cels.enumerated().sorted { $0.element.startFrame < $1.element.startFrame }
        for (celIndex, cel) in ordered {
            if cel.startFrame > cursor {
                result.append(TimelineSegment(kind: .gap(start: cursor, length: cel.startFrame - cursor)))
            }
            result.append(TimelineSegment(kind: .cel(celIndex: celIndex, cel: cel)))
            cursor = max(cursor, cel.endFrame)
        }
        if cursor < canvasManager.sceneFrameCount {
            result.append(TimelineSegment(kind: .gap(start: cursor, length: canvasManager.sceneFrameCount - cursor)))
        }
        return result
    }

    private func celRow(layerIndex: Int, layer: Layer) -> some View {
        HStack(spacing: 0) {
            ForEach(segments(for: layer)) { segment in
                switch segment.kind {
                case .cel(let celIndex, let cel):
                    celBlock(layerIndex: layerIndex, celIndex: celIndex, cel: cel)
                        .frame(width: CGFloat(cel.frameCount) * pixelsPerFrame, height: rowHeight)
                case .gap(let start, let length):
                    Color.clear
                        .frame(width: CGFloat(length) * pixelsPerFrame, height: rowHeight)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .local)
                                .onEnded { value in
                                    let tapped = start + Int(value.location.x / pixelsPerFrame)
                                    canvasManager.currentLayerIndex = layerIndex
                                    canvasManager.addCel(layerIndex: layerIndex, startFrame: tapped, frameCount: max(length - (tapped - start), 1))
                                    canvasManager.goToFrame(tapped)
                                }
                        )
                }
            }
        }
    }

    // Frame-domain baselines captured at the start of a drag (edge-resize or reorder), keyed by
    // cel id, so translation deltas are always measured against a fixed starting point rather than
    // the live (and, mid-drag, constantly-mutating) cel value — otherwise each SwiftUI re-render
    // triggered by our own model edits would re-apply the *cumulative* drag translation on top of an
    // already-updated value, compounding into runaway resizing/movement.
    @State private var dragBaselines: [UUID: Cel] = [:]

    private enum DragZone { case leftHandle, rightHandle, body }
    // The zone a drag is acting on is decided once, from where the touch *started*, and then held
    // for the rest of that gesture. A block has three logical regions (left handle / body / right
    // handle) sitting directly adjacent to each other; as a resize drag shrinks or grows the block,
    // those regions move under the still-moving finger, so a naive "which region is the touch over
    // right now" re-check on every event would hand the gesture off mid-drag. Deciding once from
    // startLocation and sticking with it for the gesture's lifetime avoids that entirely.
    @State private var dragZones: [UUID: DragZone] = [:]

    // Tapping a frame that's already the current playhead position opens the block's options menu
    // (ToonSquid-style: first tap moves the cursor there, a second tap on the same spot opens it).
    @State private var showBlockMenu = false
    @State private var menuLayerIndex: Int?
    @State private var menuCelIndex: Int?

    private func handleBlockTap(layerIndex: Int, celIndex: Int, cel: Cel, tappedFrame: Int) {
        let clamped = max(cel.startFrame, min(tappedFrame, cel.endFrame - 1))
        if layerIndex == canvasManager.currentLayerIndex, clamped == canvasManager.currentFrame {
            menuLayerIndex = layerIndex
            menuCelIndex = celIndex
            showBlockMenu = true
        } else {
            canvasManager.currentLayerIndex = layerIndex
            canvasManager.goToFrame(clamped)
        }
    }

    private func celBlock(layerIndex: Int, celIndex: Int, cel: Cel) -> some View {
        let width = CGFloat(cel.frameCount) * pixelsPerFrame
        let rawHandle = max(10, width * 0.35)
        let handleWidth = min(rawHandle, max(width / 2 - 2, 4))
        let isCurrent = layerIndex == canvasManager.currentLayerIndex

        func zone(forStartX x: CGFloat) -> DragZone {
            if x < handleWidth { return .leftHandle }
            if x > width - handleWidth { return .rightHandle }
            return .body
        }

        // minimumDistance: 8, same threshold the old body-only drag used, so a plain tap falls
        // through to `tap` below instead of being swallowed as a zero-length drag.
        let drag = DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let z = dragZones[cel.id] ?? { let z = zone(forStartX: value.startLocation.x); dragZones[cel.id] = z; return z }()
                let baseline = dragBaselines[cel.id] ?? { dragBaselines[cel.id] = cel; return cel }()
                let frameDelta = Int((value.translation.width / pixelsPerFrame).rounded())
                switch z {
                case .leftHandle:
                    canvasManager.resizeCelLeftEdge(layerIndex: layerIndex, celIndex: celIndex, newStartFrame: baseline.startFrame + frameDelta)
                case .rightHandle:
                    canvasManager.resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex, newEndFrame: baseline.endFrame + frameDelta)
                case .body:
                    canvasManager.currentLayerIndex = layerIndex
                    canvasManager.moveCel(layerIndex: layerIndex, celIndex: celIndex, newStartFrame: baseline.startFrame + frameDelta)
                }
            }
            .onEnded { _ in
                dragBaselines[cel.id] = nil
                dragZones[cel.id] = nil
            }

        let tap = SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                let tappedFrame = cel.startFrame + Int(value.location.x / pixelsPerFrame)
                handleBlockTap(layerIndex: layerIndex, celIndex: celIndex, cel: cel, tappedFrame: tappedFrame)
            }

        let combined = drag.exclusively(before: tap)

        return HStack(spacing: 0) {
            edgeHandleVisual
                .frame(width: handleWidth)
                .accessibilityIdentifier("timeline.cel.\(layerIndex).\(celIndex).leftHandle")

            Color.clear
                .frame(maxWidth: .infinity)

            edgeHandleVisual
                .frame(width: handleWidth)
                .accessibilityIdentifier("timeline.cel.\(layerIndex).\(celIndex).rightHandle")
        }
        .frame(width: width, height: rowHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.4))
                if let thumbnail = cel.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(isCurrent ? Color.blue : Color.white.opacity(0.15), lineWidth: 1.5))
        .padding(2)
        .contentShape(Rectangle())
        .gesture(combined)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.cel.\(layerIndex).\(celIndex)")
        .accessibilityValue("\(cel.startFrame),\(cel.frameCount)")
    }

    private var edgeHandleVisual: some View {
        Color.clear
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 3)
                    .padding(.vertical, 6)
            )
            .accessibilityElement(children: .ignore)
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
