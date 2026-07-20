import SwiftUI

struct LayerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    
    var body: some View {
        VStack {
            HStack {
                Text("Layers")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    canvasManager.addLayer()
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
            }
            .padding()
            
            List {
                ForEach(Array(canvasManager.layers.enumerated().reversed()), id: \.element.id) { index, layer in
                    LayerRow(layer: layer, 
                             index: canvasManager.layers.count - 1 - index,
                             canvasManager: canvasManager)
                }
                .onDelete(perform: deleteLayer)
            }
            .listStyle(PlainListStyle())
            .background(Color.gray.opacity(0.2))
        }
        .background(Color.black)
    }
    
    private func deleteLayer(at offsets: IndexSet) {
        for offset in offsets {
            let actualIndex = canvasManager.layers.count - 1 - offset
            canvasManager.deleteLayer(at: actualIndex)
        }
    }
}

struct LayerRow: View {
    let layer: Layer
    let index: Int
    @ObservedObject var canvasManager: CanvasManager
    
    var body: some View {
        HStack {
            // Visibility toggle
            Button(action: {
                canvasManager.layers[index].isVisible.toggle()
            }) {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(layer.isVisible ? .white : .gray)
            }
            
            // Layer thumbnail (placeholder)
            Rectangle()
                .fill(Color.white)
                .frame(width: 50, height: 50)
                .cornerRadius(4)
                .opacity(layer.opacity)
            
            // Layer name
            Text(layer.name)
                .foregroundColor(.white)
            
            Spacer()
            
            // Opacity slider
            Slider(value: Binding(
                get: { canvasManager.layers[index].opacity },
                set: { canvasManager.layers[index].opacity = $0 }
            ), in: 0...1)
            .frame(width: 80)
            
            // Selection indicator
            if canvasManager.currentLayerIndex == index {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            canvasManager.currentLayerIndex = index
        }
    }
}
