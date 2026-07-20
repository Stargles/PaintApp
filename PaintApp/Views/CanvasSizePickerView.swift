import SwiftUI

struct CanvasSizePickerView: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var selectedPreset: String = "iPad Pro 12.9"
    
    let presets: [String: CGSize] = [
        "iPad Pro 12.9": CGSize(width: 2732, height: 2048),
        "iPad Pro 11": CGSize(width: 2388, height: 1668),
        "iPad Air": CGSize(width: 2360, height: 1640),
        "iPad Mini": CGSize(width: 2240, height: 1480),
        "1080p": CGSize(width: 1920, height: 1080),
        "4K": CGSize(width: 3840, height: 2160),
        "Custom": CGSize(width: 2048, height: 2048)
    ]
    
    @State private var customWidth: String = "2048"
    @State private var customHeight: String = "2048"
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Create New Canvas")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 15) {
                Text("Canvas Size")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                Picker("Preset", selection: $selectedPreset) {
                    ForEach(presets.keys.sorted(), id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                
                if selectedPreset == "Custom" {
                    HStack {
                        TextField("Width", text: $customWidth)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                        
                        Text("x")
                            .foregroundColor(.gray)
                        
                        TextField("Height", text: $customHeight)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }
                    .padding()
                }
                
                if let size = presets[selectedPreset] {
                    Text("\(Int(size.width)) x \(Int(size.height))")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Button(action: {
                if selectedPreset == "Custom", let width = Int(customWidth), let height = Int(customHeight) {
                    canvasManager.canvasSize = CGSize(width: width, height: height)
                } else if let size = presets[selectedPreset] {
                    canvasManager.canvasSize = size
                }
                canvasManager.addLayer()
                canvasManager.addFrame()
            }) {
                Text("Create Canvas")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 50)
        }
        .padding()
    }
}
