import SwiftUI
import UIKit

/// **A pad the artist can draw on, live, with the brush as edited** — BRUSH.md §7.2's third column,
/// and the owner's own stated reason for wanting the editor at all: *"i can edit aspects of it myself
/// to see which settings are good."*
///
/// ## It is not a `StrokeCanvasView`, and that is a refutation rather than a shortcut
///
/// §7.2 says *"It is a `StrokeCanvasView` over a scratch bitmap with no document behind it."* That
/// view cannot be one: it holds a `weak var canvasManager`, resolves a `layerID` and a cel through
/// it, records undo through `CanvasManager.recordUndo`, asks `isInterpolateMode`, and writes into the
/// document's `RasterLayerTexture`. Handing it a nil manager gives a view that swallows every touch
/// and draws nothing; giving it a real one puts the artist's doodles into their drawing.
///
/// **What actually has to be shared is the *stamper*, and it is.** Every dab here goes through
/// `BrushStamper.stampStroke` — the one call every tier funnels into — over a `CGContextDabTarget`,
/// which is exactly what `BrushPreview.render` does for a menu row. So the pad's ink is the app's
/// ink by construction, and a brush that renders differently here than on the canvas is a bug in the
/// stamper rather than a difference between two drawing paths.
///
/// ## What it reports, and why
///
/// `accessibilityValue` is `"ink=<total>,last=<n>"` — inked pixels in the whole pad, and how many the
/// last finished stroke added. That is the operand BRUSH.md §12 stage 10's fifth test needs: a pad
/// that drew with the brush **as saved** rather than as edited would look perfectly right and be
/// wrong, and only a number taken off its own pixels can tell the two apart.
struct BrushScratchPadView: UIViewRepresentable {
    /// **The brush by value, live.** Not a `BrushRef` and not a snapshot taken on appear: the whole
    /// point is that a slider moved now changes the next stroke, and `Brush` being `Hashable` over
    /// its whole value is what makes "has it changed?" one comparison.
    let brush: Brush
    let color: UIColor
    /// The stroke's own diameter and opacity — the artist's two numbers (§2.20), which the editor
    /// carries beside the brush's own.
    let strokeSize: CGFloat
    let strokeOpacity: Double
    let identifier: String
    /// Bumped by the Clear button. A token rather than a closure because `UIViewRepresentable` has no
    /// other way to say "an event happened" from SwiftUI.
    let clearToken: Int

    func makeUIView(context: Context) -> BrushScratchPad {
        let pad = BrushScratchPad()
        pad.accessibilityIdentifier = identifier
        return pad
    }

    func updateUIView(_ pad: BrushScratchPad, context: Context) {
        pad.brush = brush
        pad.color = color
        pad.strokeSize = strokeSize
        pad.strokeOpacity = strokeOpacity
        if pad.clearToken != clearToken {
            pad.clearToken = clearToken
            pad.clear()
        }
    }
}

/// The pad itself. UIKit rather than SwiftUI because pressure lives on `UITouch` and there is no
/// SwiftUI gesture that reports it.
final class BrushScratchPad: UIView {

    var brush: Brush = BrushLibrary.softRound
    var color: UIColor = .black
    var strokeSize: CGFloat = 18
    var strokeOpacity: Double = 1
    var clearToken = 0

    /// Everything drawn so far, at screen scale. Rebuilt when the pad is resized — a scratch pad has
    /// nothing worth preserving across a layout change, and scaling a bitmap of dabs would be a
    /// picture of a brush at a size it was never drawn at.
    private var committed: CGContext?
    /// The pad as it was when the current stroke began, so the stroke can be re-stamped whole on
    /// every touch move.
    ///
    /// **Re-stamping rather than appending, and the reason is §4.** A dab's randomness is hashed by
    /// **arc length**, and the arc length of a sample depends on the samples before *and after* it
    /// once the path is fitted — so appending only the newest segment would draw a different lattice
    /// from the one the finished stroke has, and the ink would visibly re-roll at lift. A pad is a
    /// few hundred dabs; re-walking it costs less than the divergence would.
    private var strokeBase: CGImage?
    private var samples: [VectorSample] = []
    private var inkedBefore = 0

    private(set) var inkedPixels = 0
    private(set) var lastStrokeInk = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isMultipleTouchEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var accessibilityValue: String? {
        get { "ink=\(inkedPixels),last=\(lastStrokeInk)" }
        set { }
    }

    // MARK: - The bitmap

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0 else { return }
        if let committed, committed.width == width, committed.height == height { return }
        committed = Self.makeContext(width: width, height: height, scale: scale)
        inkedPixels = 0
        lastStrokeInk = 0
        setNeedsDisplay()
    }

    /// **Flipped to UIKit's orientation**, because the samples are `touch.location(in: self)` and a
    /// bare `CGBitmapContext` is y-up from the bottom left. `BrushPreview` does not need this — a
    /// `UIGraphicsImageRenderer` hands out a context that is already flipped — and getting it wrong
    /// here would draw every stroke as its own vertical mirror.
    private static func makeContext(width: Int, height: Int, scale: CGFloat) -> CGContext? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        return context
    }

    /// Runs `body` with the context's transform undone, so the argument is in **device pixels** and
    /// the flip above is not applied twice. Both callers need it for the same reason: a whole-bitmap
    /// clear and an image redrawn into itself are operations on the buffer rather than on the
    /// drawing, and the flip is a property of the drawing.
    private func inDevicePixels(_ body: (CGContext, CGRect) -> Void) {
        guard let committed else { return }
        committed.saveGState()
        committed.concatenate(committed.ctm.inverted())
        body(committed, CGRect(x: 0, y: 0, width: committed.width, height: committed.height))
        committed.restoreGState()
    }

    func clear() {
        inDevicePixels { context, rect in context.clear(rect) }
        inkedPixels = 0
        lastStrokeInk = 0
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let committed, let image = committed.makeImage() else { return }
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let committed else { return }
        strokeBase = committed.makeImage()
        inkedBefore = inkedPixels
        samples = [sample(from: touch)]
        stampCurrentStroke()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !samples.isEmpty else { return }
        // Coalesced touches, so a fast drag is a curve rather than four straight chords — the same
        // reason `StrokeGestureRecognizer` collects them.
        for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
            samples.append(sample(from: coalesced))
        }
        stampCurrentStroke()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    /// **A finger reports no force at all, so it reads the neutral rather than zero.** §5.5: a
    /// pressure of 0 would take a `size ← pressure` brush to its floor for the whole stroke, which is
    /// the wrong picture of the brush and is also what every XCUITest gesture would produce.
    private func sample(from touch: UITouch) -> VectorSample {
        let point = touch.location(in: self)
        let pressure: CGFloat
        if touch.maximumPossibleForce > 0 {
            pressure = min(max(touch.force / touch.maximumPossibleForce, 0.01), 1)
        } else {
            pressure = BrushInput.pressure.neutral
        }
        return VectorSample(point: point, pressure: pressure)
    }

    private func stampCurrentStroke() {
        guard let committed, !samples.isEmpty else { return }
        inDevicePixels { context, rect in
            context.clear(rect)
            if let strokeBase { context.draw(strokeBase, in: rect) }
        }

        BrushStamper.stampStroke(into: CGContextDabTarget(committed),
                                 samples: StrokeSamples(samples, channels: .pressureOnly),
                                 brush: brush,
                                 color: color,
                                 brushSize: strokeSize,
                                 brushOpacity: strokeOpacity,
                                 isEraser: false,
                                 random: DabRandom(seed: Self.padSeed))
        setNeedsDisplay()
    }

    private func finishStroke() {
        guard !samples.isEmpty else { return }
        samples = []
        strokeBase = nil
        inkedPixels = countInk()
        lastStrokeInk = max(inkedPixels - inkedBefore, 0)
        setNeedsDisplay()
    }

    /// How many pixels carry ink. Taken on touch-up only — a pad is at most a megapixel and this is
    /// one linear pass, but it is not something to do sixty times a second.
    private func countInk() -> Int {
        guard let committed, let data = committed.data else { return 0 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: committed.bytesPerRow * committed.height)
        var count = 0
        for row in 0..<committed.height {
            let base = row * committed.bytesPerRow
            for column in 0..<committed.width where bytes[base + column * 4 + 3] > 8 {
                count += 1
            }
        }
        return count
    }

    /// Fixed, so the pad is a function of the brush exactly as `BrushPreview` is: two strokes of the
    /// same brush over the same path scatter the same way, and a difference between them is a
    /// difference in the brush.
    private static let padSeed: UInt64 = 0x8B7A_5E11_0000_00AD
}
