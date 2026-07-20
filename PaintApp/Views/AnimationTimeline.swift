import SwiftUI

struct AnimationTimeline: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?
    
    var body: some View {
        VStack {
            // Timeline controls
            HStack(spacing: 15) {
                // Play/Pause button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                // Previous frame
                Button(action: previousFrame) {
                    Image(systemName: "backward.frame")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                
                // Next frame
                Button(action: nextFrame) {
                    Image(systemName: "forward.frame")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                
                Spacer()
                
                // Add frame
                Button(action: {
                    canvasManager.addFrame()
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                
                // Duplicate frame
                Button(action: {
                    canvasManager.duplicateFrame()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                
                // Delete frame
                Button(action: {
                    canvasManager.deleteFrame(at: canvasManager.currentFrameIndex)
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                
                Spacer()
                
                // Onion skin toggle
                Button(action: {
                    canvasManager.isOnionSkinEnabled.toggle()
                }) {
                    Image(systemName: canvasManager.isOnionSkinEnabled ? "eye.fill" : "eye.slash")
                        .font(.title2)
                        .foregroundColor(canvasManager.isOnionSkinEnabled ? .blue : .white)
                        .frame(width: 44, height: 44)
                        .background(canvasManager.isOnionSkinEnabled ? Color.white.opacity(0.2) : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                
                // Onion skin opacity slider
                if canvasManager.isOnionSkinEnabled {
                    VStack {
                        Text("Onion Skin")
                            .font(.caption)
                            .foregroundColor(.white)
                        Slider(value: $canvasManager.onionSkinOpacity, in: 0...1)
                            .frame(width: 80)
                    }
                }
            }
            .padding(.horizontal)
            
            // Frame thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(canvasManager.frames.enumerated()), id: \.element.id) { index, frame in
                        FrameThumbnail(frame: frame, 
                                       index: index,
                                       currentIndex: canvasManager.currentFrameIndex,
                                       canvasManager: canvasManager)
                            .onTapGesture {
                                loadFrame(index)
                            }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 80)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(8)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        
        if isPlaying {
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                nextFrame()
            }
        } else {
            playbackTimer?.invalidate()
            playbackTimer = nil
        }
    }
    
    private func previousFrame() {
        if canvasManager.currentFrameIndex > 0 {
            canvasManager.currentFrameIndex -= 1
            loadFrame(canvasManager.currentFrameIndex)
        }
    }
    
    private func nextFrame() {
        if canvasManager.currentFrameIndex < canvasManager.frames.count - 1 {
            canvasManager.currentFrameIndex += 1
            loadFrame(canvasManager.currentFrameIndex)
        } else {
            // Loop back to start
            canvasManager.currentFrameIndex = 0
            loadFrame(0)
        }
    }
    
    private func loadFrame(_ index: Int) {
        // Save current frame before switching
        if canvasManager.currentLayerIndex < canvasManager.layers.count {
            canvasManager.frames[canvasManager.currentFrameIndex].layers = canvasManager.layers.map { layer in
                FrameLayer(
                    id: UUID(),
                    drawing: layer.drawing,
                    opacity: layer.opacity,
                    isVisible: layer.isVisible
                )
            }
        }
        
        // Load new frame
        canvasManager.loadFrame(index)
    }
}

struct FrameThumbnail: View {
    let frame: AnimationFrame
    let index: Int
    let currentIndex: Int
    @ObservedObject var canvasManager: CanvasManager
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail placeholder
            Rectangle()
                .fill(Color.white)
                .frame(width: 60, height: 60)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(index == currentIndex ? Color.blue : Color.clear, lineWidth: 3)
                )
            
            // Frame number
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .padding(4)
                .background(Color.white.opacity(0.8))
                .cornerRadius(4)
        }
    }
}
