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
    /// TODO.md item (13) raised this 8192 -> 16383; item (31) lowered it again, to 4096, because
    /// 16383 crashes on a brushstroke on a 3 GB device. `CanvasManager.maxCanvasExtent` is the single
    /// named home for this bound — see its doc comment and PERFORMANCE.md §15 for why 4096.
    private let maxDimension = Int(CanvasManager.maxCanvasExtent)

    private var width: Int? { Int(widthText) }
    private var height: Int? { Int(heightText) }

    private var isValid: Bool {
        guard let width, let height else { return false }
        return (minDimension...maxDimension).contains(width) && (minDimension...maxDimension).contains(height)
    }

    /// Whether the *reason* the fields are invalid is specifically "too large" — as opposed to
    /// empty, non-numeric, or below `minDimension` — so the refusal can say why rather than just
    /// restating the range. TODO.md item (31): a size above `maxDimension` is refused because it
    /// crashes the app on a brushstroke on some devices, not for an arbitrary reason, and a refusal
    /// is never silent in this codebase.
    private var exceedsMaximum: Bool {
        if let width, width > maxDimension { return true }
        if let height, height > maxDimension { return true }
        return false
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
                    if exceedsMaximum {
                        // Says *why*, not just *what*: PERFORMANCE.md §15 is the arithmetic behind
                        // this number — a canvas this large needs several buffers this size at once
                        // (the compositor's sandwich, plus the layer's own storage), and on a 3 GB
                        // iPad that alone exceeds what the app is measured to have before a crash.
                        Text("Canvases above \(maxDimension) can run out of memory and crash while "
                             + "drawing, so this size isn't offered.")
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("sizePicker.tooLargeMessage")
                    } else {
                        Text("Enter values between \(minDimension) and \(maxDimension)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("sizePicker.validationMessage")
                    }
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
        // Inert unless an XCUITest passed `-uiTestSeedVideo` — see `UITestSeeds` for why a video
        // has to land here rather than through the picker every real import uses.
        UITestSeeds.seedVideoIfRequested(into: canvasManager)
        // Inert unless an XCUITest passed `-uiTestSeedKeyframedMove` — TODO (53)'s document, which
        // takes a dozen gestures across three panels to author and one call to state.
        UITestSeeds.seedKeyframedMoveIfRequested(into: canvasManager)
        onCreated()
    }
}
