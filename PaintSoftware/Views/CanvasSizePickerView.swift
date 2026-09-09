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
    /// TODO.md item (13) raised this 8192 -> 16383; item (31) lowered it again, to 6000, because
    /// 16383 crashes on a brushstroke on a 3 GB device — MEASURED on the owner's own iPad 9, where a
    /// fresh document dies between 12000 and 13000 and 6000 is half of that. `CanvasManager.maxCanvasExtent`
    /// is the single named home for this bound — see its doc comment and PERFORMANCE.md §15 for the run.
    private let maxDimension = Int(CanvasManager.maxCanvasExtent)

    private var width: Int? { Int(widthText) }
    private var height: Int? { Int(heightText) }

    private var isValid: Bool {
        guard let width, let height else { return false }
        return (minDimension...maxDimension).contains(width) && (minDimension...maxDimension).contains(height)
    }

    /// Whether the *reason* the fields are invalid is specifically "too large" — as opposed to
    /// empty, non-numeric, or below `minDimension` — so the refusal can say why rather than just
    /// restating the range. TODO.md item (31): a size above `maxDimension` is refused because a
    /// canvas that big has been *watched* running the app out of memory on a 3 GB iPad, not for an
    /// arbitrary reason, and a refusal is never silent in this codebase.
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
                        // Says *why*, not just *what*, and says it as something seen rather than
                        // calculated: PERFORMANCE.md §15 is the device run behind this number — one
                        // brushstroke on a canvas past roughly twice this size was watched killing
                        // the app on the 3 GB iPad this bound is set for.
                        Text("Canvases above \(maxDimension) have been measured running this iPad out "
                             + "of memory mid-brushstroke, so this size isn't offered.")
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
        // Inert unless an XCUITest passed `-uiTestSeedHoldAfterMove` — TODO (54)'s document, the same
        // shape with its last pose key at frame 4, so the tail of the scene is a hold.
        UITestSeeds.seedHoldAfterMoveIfRequested(into: canvasManager)
        // Inert unless an XCUITest passed `-uiTestSeedPlainAnimation` — the owner's `Test1`, and the
        // one seed here whose whole point is that Core Animation *can* draw it.
        UITestSeeds.seedPlainAnimationIfRequested(into: canvasManager)
        onCreated()
    }
}
