import SwiftUI
import PencilKit

struct DrawingView: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var showingLayers = false
    @State private var showingBrushSettings = false
    @State private var showingColorPicker = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main canvas area
                CanvasView(canvasManager: canvasManager)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    canvasManager.zoomScale = value
                                }
                                .onEnded { _ in
                                    // Keep the final zoom scale
                                },
                            RotationGesture()
                                .onChanged { angle in
                                    canvasManager.rotationAngle = angle
                                }
                        )
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                canvasManager.offset = value.translation
                            }
                    )
                
                // Top toolbar
                VStack {
                    TopToolbar(canvasManager: canvasManager, 
                              showingLayers: $showingLayers,
                              showingBrushSettings: $showingBrushSettings,
                              showingColorPicker: $showingColorPicker)
                        .padding()
                    
                    Spacer()
                    
                    // Animation timeline
                    AnimationTimeline(canvasManager: canvasManager)
                        .padding()
                }
                
                // Side panel for layers (when shown)
                if showingLayers {
                    HStack {
                        LayerPanel(canvasManager: canvasManager)
                            .frame(width: 300)
                            .transition(.move(edge: .leading))
                        
                        Spacer()
                    }
                }
                
                // Brush settings panel (when shown)
                if showingBrushSettings {
                    BrushSettingsPanel(canvasManager: canvasManager)
                        .frame(maxWidth: 300)
                        .transition(.move(edge: .trailing))
                        .offset(x: showingLayers ? 300 : 0)
                }
                
                // Color picker (when shown)
                if showingColorPicker {
                    ColorPickerPanel(canvasManager: canvasManager)
                        .frame(maxWidth: 300)
                        .transition(.move(edge: .trailing))
                        .offset(x: (showingBrushSettings ? 300 : 0) + (showingLayers ? 300 : 0))
                }
            }
        }
    }
}
