import SwiftUI

// MARK: - MASK-TUNE — temporary scaffolding, LAYER_COMPOSITING.md §10 item 1
//
// Nobody has looked at `AlphaMask.threshold`/`.antialiasHalfWidth` since §6.3 picked 0.5/0.05, and
// the judgement has to be made by eye against a soft brush. This overlay is the only writer of those
// two `static var`s (see the MASK-TUNE comments on them in AlphaMask.swift) and is the whole harness.
//
// **Cache invalidation is not this file's job, on purpose.** A `ResolvedMask` is cached per distinct
// mask (§6.1) in `MaskResolver`, keyed on `AlphaMask`'s stored properties plus content versions — this
// overlay writes two statics that aren't stored properties, so the cache can't see the write on its
// own. Rather than have every writer (this file today, anything else tomorrow) remember to call
// `MaskResolver.clearCache()`, `AlphaMask.threshold`/`.antialiasHalfWidth` bump a `tuningGeneration`
// counter on `didSet` that's folded straight into `MaskResolver.CacheKey` — so simply assigning below
// is enough; see `AlphaMask.tuningGeneration`'s doc comment and
// `MaskParityLogicTests.testMutatingTheTuningThresholdInvalidatesTheMaskCache`, which pins it.
// What this does *not* do is force *already-drawn, already-lifted* content to repaint on its own — the
// live canvas's sandwich rebuild is keyed off model content versions (`CanvasView.SandwichKey`), which
// these statics deliberately don't touch, so the way to see a change is the same way §6.4 already
// works: drum a new soft-brush stroke over the masked area after moving a slider.
//
// DELETE TO REVERT: this file, the two-line call site in `DrawingView.swift`, and put
// `AlphaMask.threshold`/`.antialiasHalfWidth` back to `let` in `AlphaMask.swift`.
struct MaskTuningOverlay: View {
    @Binding var isVisible: Bool
    @State private var threshold: Float = AlphaMask.threshold
    @State private var antialiasHalfWidth: Float = AlphaMask.antialiasHalfWidth

    private static let shippingThreshold: Float = 0.5
    private static let shippingAntialiasHalfWidth: Float = 0.05

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Spacer()
                toggleButton
            }
            if isVisible {
                panel
            }
        }
    }

    private var toggleButton: some View {
        Button(action: { isVisible.toggle() }) {
            Image(systemName: "wand.and.rays")
                .font(.footnote)
                .foregroundColor(isVisible ? .orange : .white.opacity(0.5))
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityIdentifier("maskTuning.toggle")
        .accessibilityLabel(isVisible ? "Mask tuning: on" : "Mask tuning: off")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MASK TUNE — TEMPORARY, DELETE BEFORE SHIP")
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundColor(.orange)
            Text("Draw a soft-brush stroke into a masked layer, then scrub.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            row(label: "threshold", value: $threshold, range: 0.1...0.9,
               shippingDefault: Self.shippingThreshold,
               identifier: "maskTuning.threshold") { newValue in
                AlphaMask.threshold = newValue
            }
            row(label: "antialiasHalfWidth", value: $antialiasHalfWidth, range: 0.0...0.25,
               shippingDefault: Self.shippingAntialiasHalfWidth,
               identifier: "maskTuning.antialiasHalfWidth") { newValue in
                AlphaMask.antialiasHalfWidth = newValue
            }

            Button("Reset to shipping defaults") {
                threshold = Self.shippingThreshold
                antialiasHalfWidth = Self.shippingAntialiasHalfWidth
                AlphaMask.threshold = Self.shippingThreshold
                AlphaMask.antialiasHalfWidth = Self.shippingAntialiasHalfWidth
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.orange)
            .accessibilityIdentifier("maskTuning.reset")
        }
        .padding(10)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.6), lineWidth: 1))
        .frame(width: 260)
        .accessibilityIdentifier("maskTuning.panel")
    }

    private func row(label: String, value: Binding<Float>, range: ClosedRange<Float>,
                     shippingDefault: Float, identifier: String,
                     onChange: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: "%.3f", value.wrappedValue))
                    .font(.system(.caption2, design: .monospaced).bold())
                    .foregroundColor(.white)
            }
            Slider(value: Binding(get: { value.wrappedValue }, set: { newValue in
                value.wrappedValue = newValue
                onChange(newValue)
            }), in: range)
            .accessibilityIdentifier(identifier)
            Text("shipping default: \(String(format: "%.2f", shippingDefault))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
    }
}
