import SwiftUI

// MARK: - MASK-TUNE — temporary scaffolding, LAYER_COMPOSITING.md §10 item 1
//
// The product owner used this to judge `AlphaMask.threshold`/`.antialiasHalfWidth` by eye against a
// soft brush on the iPad, in Release, and picked 0.1/0.01 over §6.3's original 0.5/0.05 guess. This
// section is the only writer of those two `static var`s (see the MASK-TUNE comments on them in
// AlphaMask.swift) and is the whole harness — kept rather than deleted in case that judgement needs
// re-checking once the live-stroke bug it currently competes with is fixed.
//
// **It sits in the layer options menu, beside the mask controls, and not over the canvas.** As a
// floating corner panel it was declared last in `DrawingView`'s ZStack, so it drew and hit-tested
// above the layer rail and every trailing dropdown, and it swallowed the taps that landed in the top
// ~190pt of that edge — sixteen tests' worth. A menu that is only on screen while the artist opened
// it cannot do that, and it needs no opacity/hit-testing guard to make it safe.
//
// **Cache invalidation is not this file's job, on purpose.** A `ResolvedMask` is cached per distinct
// mask (§6.1) in `MaskResolver`, keyed on `AlphaMask`'s stored properties plus content versions — this
// harness writes two statics that aren't stored properties, so the cache can't see the write on its
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
// DELETE TO REVERT: this file, the one-line call site in `LayerPanel.maskSection`, and put
// `AlphaMask.threshold`/`.antialiasHalfWidth` back to `let` in `AlphaMask.swift`.
struct MaskTuningSection: View {
    @State private var threshold: Float = AlphaMask.threshold
    @State private var antialiasHalfWidth: Float = AlphaMask.antialiasHalfWidth

    private static let shippingThreshold: Float = 0.1
    private static let shippingAntialiasHalfWidth: Float = 0.01

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MASK TUNE — TEMPORARY, DELETE BEFORE SHIP")
                .font(.system(size: 9, design: .monospaced).bold())
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
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.orange)
            .accessibilityIdentifier("maskTuning.reset")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityIdentifier("maskTuning.panel")
    }

    private func row(label: String, value: Binding<Float>, range: ClosedRange<Float>,
                     shippingDefault: Float, identifier: String,
                     onChange: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: "%.3f", value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced).bold())
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
