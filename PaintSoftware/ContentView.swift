import SwiftUI

struct ContentView: View {
    @StateObject private var canvasManager = CanvasManager()
    @State private var showingCanvasSizePicker = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if canvasManager.canvasSize == nil {
                CanvasSizePickerView(canvasManager: canvasManager)
            } else {
                DrawingView(canvasManager: canvasManager)
            }
        }
        .statusBar(hidden: true)
    }
}
