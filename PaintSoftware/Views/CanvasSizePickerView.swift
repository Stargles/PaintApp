import SwiftUI

struct CanvasSizePickerView: View {
    @ObservedObject var canvasManager: CanvasManager
    var onCreated: () -> Void

    @State private var widthText: String = "2048"
    @State private var heightText: String = "2048"
    @FocusState private var focusedField: Field?

    private enum Field {
        case width, height
    }

    private let minDimension = 1
    /// TODO.md item (13): raised 8192 -> 16383. `CanvasManager.maxCanvasExtent` is the single named
    /// home for this bound — see its doc comment for why 16383 and not 16384.
    private let maxDimension = Int(CanvasManager.maxCanvasExtent)

    private var width: Int? { Int(widthText) }
    private var height: Int? { Int(heightText) }

    private var isValid: Bool {
        guard let width, let height else { return false }
        return (minDimension...maxDimension).contains(width) && (minDimension...maxDimension).contains(height)
    }

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

                HStack(spacing: 12) {
                    dimensionField("Width", text: $widthText, field: .width)
                    Text("x")
                        .foregroundColor(.gray)
                    dimensionField("Height", text: $heightText, field: .height)
                }
                .padding(.horizontal, 50)

                if !isValid {
                    Text("Enter values between \(minDimension) and \(maxDimension)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Button(action: createCanvas) {
                Text("Create Canvas")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValid ? Color.blue : Color.blue.opacity(0.4))
                    .cornerRadius(10)
            }
            .disabled(!isValid)
            .accessibilityIdentifier("sizePicker.createButton")
            .padding(.horizontal, 50)
        }
        .padding()
        .onAppear { focusedField = .width }
    }

    private func dimensionField(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: field)
            .accessibilityIdentifier(field == .width ? "sizePicker.widthField" : "sizePicker.heightField")
    }

    private func createCanvas() {
        guard let width, let height, isValid else { return }
        canvasManager.canvasSize = CGSize(width: width, height: height)
        canvasManager.addVectorLayer()
        onCreated()
    }
}
