import SwiftUI

// MARK: - MASK-TUNE — the mask's two tunables, behind the Mask row
//
// The product owner used this to judge `AlphaMask.threshold`/`.antialiasHalfWidth` by eye against a
// soft brush on the iPad, in Release, and picked 0.1/0.01 over §6.3's original 0.5/0.05 guess. It was
// scaffolding then and is a shipped control now: the owner asked for the Mask row to open a "mask
// tune menu in place of the edit menu", so this section is what that menu is made of, and it is the
// only writer of those two `static var`s (see the MASK-TUNE comments on them in AlphaMask.swift).
//
// **It sits in the layer options menu, beside the mask controls, and not over the canvas.** As a
// floating corner panel it was declared last in `DrawingView`'s ZStack, so it drew and hit-tested
// above the layer rail and every trailing dropdown, and it swallowed the taps that landed in the top
// ~190pt of that edge — sixteen tests' worth. A menu that is only on screen while the artist opened
// it cannot do that, and it needs no opacity/hit-testing guard to make it safe.
//
// **The model clamps, not the widget.** `AlphaMask.setTuning` keeps `antialiasHalfWidth` strictly
// below `threshold` (a mask whose ramp reaches alpha 0 hides nothing — see its doc), so both sliders
// write and then *re-read*: what the row shows is what the model accepted, never what the finger
// asked for. That is why the ranges below can stay the artist-facing ones rather than being narrowed
// into each other.
//
// **Cache invalidation is not this file's job, on purpose.** A `ResolvedMask` is cached per distinct
// mask (§6.1) in `MaskResolver`, keyed on `AlphaMask`'s stored properties plus content versions — this
// section writes two statics that aren't stored properties, so the cache can't see the write on its
// own. Rather than have every writer (this file today, anything else tomorrow) remember to call
// `MaskResolver.clearCache()`, `AlphaMask.setTuning` bumps a `tuningGeneration` counter that's folded
// straight into `MaskResolver.CacheKey` — so simply assigning below is enough; see
// `AlphaMask.tuningGeneration`'s doc comment and
// `MaskParityLogicTests.testMutatingTheTuningThresholdInvalidatesTheMaskCache`, which pins it.
// What this does *not* do is force *already-drawn, already-lifted* content to repaint on its own — the
// live canvas's sandwich rebuild is keyed off model content versions (`CanvasView.SandwichKey`), which
// these statics deliberately don't touch, so the way to see a change is the same way §6.4 already
// works: draw a new soft-brush stroke over the masked area after moving a slider.
struct MaskTuningSection: View {
    @State private var threshold: Float = AlphaMask.threshold
    @State private var antialiasHalfWidth: Float = AlphaMask.antialiasHalfWidth

    private static let shippingThreshold: Float = 0.1
    private static let shippingAntialiasHalfWidth: Float = 0.01

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draw a soft-brush stroke into a masked layer, then scrub.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

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

            Button("Reset to defaults") {
                AlphaMask.setTuning(threshold: Self.shippingThreshold,
                                    antialiasHalfWidth: Self.shippingAntialiasHalfWidth)
                syncFromModel()
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.blue)
            .accessibilityIdentifier("maskTuning.reset")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // **No identifier on this stack.** It used to carry `maskTuning.panel`, and an accessibility
        // identifier on a container propagates to its descendants and *wins* over theirs: both
        // sliders surfaced to XCUITest as `maskTuning.panel`, so the two identifiers below named
        // nothing. Nothing queried them while this was a harness, which is how it went unnoticed.
    }

    /// The two mirrors, re-read from the model — the model is the authority on what a write became
    /// (`AlphaMask.setTuning` clamps), so a slider that asked for a value the guard refused snaps to
    /// the value it actually got instead of showing a number nothing is rendering with.
    private func syncFromModel() {
        threshold = AlphaMask.threshold
        antialiasHalfWidth = AlphaMask.antialiasHalfWidth
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
                syncFromModel()
            }), in: range)
            .accessibilityIdentifier(identifier)
            Text("default: \(String(format: "%.2f", shippingDefault))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
    }
}
