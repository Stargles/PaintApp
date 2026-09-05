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
/// ## The four behaviours §7.2 asked for, and what "zoomed" had to mean
///
/// The owner asked for four after the brief that built this: open showing a sample stroke with a
/// pressure taper, be zoomed in by default, carry a toggle to real size, and clear. The first is
/// `BrushPreview.stampSample` — **the same fixed S-curve and the same seed a menu row walks**, so a
/// brush's row and its pad cannot disagree about what it looks like.
///
/// **Zoom scales the *view* of a canvas-space render, never the brush.** A brush drawn at 3× size is
/// a different brush, not a magnified one, and a pad that showed one would lie about the single thing
/// it exists to tell the truth about. So `zoom` moves the context's *scale factor* and shrinks the
/// canvas extent the pad shows; `brushSize` reaching the stamper is untouched, in canvas points, at
/// every zoom.
///
/// **And the strokes are re-walked on a zoom change rather than magnified as pixels.** Scaling the
/// bitmap up would be a picture of the brush at a resolution it was never drawn at — the same lie by
/// a different route — so each stroke keeps its samples in canvas points and the walk runs again.
/// It keeps `brush` per stroke as well, so re-walking cannot retroactively redraw yesterday's ink
/// with today's edit, which is BRUSH.md §2.10 falling out of the same store.
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
    /// **How magnified the view of the canvas is** — 1 is real size. See the type's note.
    let zoom: CGFloat

    func makeUIView(context: Context) -> BrushScratchPad {
        let pad = BrushScratchPad()
        pad.accessibilityIdentifier = identifier
        pad.zoom = zoom
        pad.brush = brush
        pad.color = color
        pad.strokeSize = strokeSize
        pad.strokeOpacity = strokeOpacity
        return pad
    }

    func updateUIView(_ pad: BrushScratchPad, context: Context) {
        // The order matters: the zoom change rebuilds the bitmap, and it must rebuild it against the
        // brush the artist has *now* — otherwise a toggle to real size would redraw the resting
        // sample with whatever the brush was before the slider they just moved.
        let brushChanged = pad.brush != brush || pad.strokeSize != strokeSize
            || pad.strokeOpacity != strokeOpacity || pad.color != color
        pad.brush = brush
        pad.color = color
        pad.strokeSize = strokeSize
        pad.strokeOpacity = strokeOpacity
        pad.zoom = zoom
        if brushChanged { pad.refreshRestingSample() }
        if pad.clearToken != clearToken {
            pad.clearToken = clearToken
            pad.clear()
        }
    }
}

/// The pad itself. UIKit rather than SwiftUI because pressure lives on `UITouch` and there is no
/// SwiftUI gesture that reports it.
final class BrushScratchPad: UIView {

    var brush: Brush = BrushLibrary.roundSoft
    var color: UIColor = .black
    var strokeSize: CGFloat = 18
    var strokeOpacity: Double = 1
    var clearToken = 0

    /// See `BrushScratchPadView.zoom`. A change rebuilds the bitmap and re-walks what is on it.
    var zoom: CGFloat = BrushPadZoom.standard {
        didSet {
            guard zoom != oldValue else { return }
            rebuild()
        }
    }

    /// Everything drawn so far, at screen scale and at `zoom`'s magnification.
    ///
    /// **Its user space is canvas points, not view points**, which is the whole of what zoom is here:
    /// the CTM carries `screenScale · zoom`, so the extent this bitmap covers is `bounds / zoom`
    /// canvas points while its pixel dimensions stay `bounds · screenScale`. A dab handed
    /// `brushSize` in canvas points therefore lands at the same canvas width at every zoom and is
    /// merely resolved more finely — which is what a canvas zoom is, and what a scaled brush is not.
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

    /// **One stroke the artist finished, in canvas points, with the brush it was drawn with.**
    ///
    /// Kept so a zoom change (or a layout change) can re-walk rather than magnify. Carrying the brush
    /// is what stops a re-walk from being a retroactive edit: BRUSH.md §2.10 rules that a brush edit
    /// does not change ink already drawn, and a pad that re-rendered its history with the current
    /// brush would break that in the one place an artist is watching for it.
    private struct FinishedStroke {
        let samples: [VectorSample]
        let brush: Brush
        let color: UIColor
        let size: CGFloat
        let opacity: Double
    }
    private var finished: [FinishedStroke] = []

    /// **True while the only thing on the pad is the opening sample stroke.**
    ///
    /// It is what makes the sample a *resting state* rather than a one-shot: while it holds, moving a
    /// slider re-renders the sample so the brush's character stays visible before the first touch.
    /// The first touch clears it — the artist judging their own stroke should not be judging it on
    /// top of one they did not draw — and so does Clear, because Clear must clear.
    private(set) var isShowingRestingSample = false

    /// **Counted on demand rather than held**, and that is a cost decision with a measurement behind
    /// the shape of it. A count is one linear pass over the whole bitmap — about 1.4 million pixels on
    /// this pad — and the resting sample is re-stamped on *every tick* of a slider drag, so caching it
    /// would put that pass in the drag loop for a number only an accessibility client ever reads.
    /// `finishStroke` and `touchesBegan` take it twice per stroke, which is what `lastStrokeInk` needs
    /// and all it needs.
    var inkedPixels: Int { countInk() }
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

    /// The canvas extent the pad is showing, in canvas points. `bounds` divided by the magnification
    /// — the one arithmetic statement of what zoom means here.
    var canvasSize: CGSize { BrushPadZoom.canvasSize(of: bounds.size, at: zoom) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0 else { return }
        if let committed, committed.width == width, committed.height == height { return }
        rebuild()
    }

    /// Makes the bitmap afresh and puts back what belongs on it.
    ///
    /// **A rebuild keeps what is on the pad, and that is a fix rather than a nicety.** MEASURED on the
    /// simulator: opening the second-input picker raised the software keyboard, which shortened this
    /// view, and a rebuild that dropped the strokes wiped the one the artist had just drawn to see
    /// what their edit did. Re-walking rather than redrawing old pixels is what makes the same
    /// mechanism serve the zoom toggle: the strokes are canvas-space facts and the bitmap is a view
    /// of them.
    private func rebuild() {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0 else { return }
        committed = BrushPadZoom.makeContext(viewSize: bounds.size, screenScale: scale, zoom: zoom)
        redrawContents()
    }

    /// Clears the bitmap and puts back what belongs on it — the resting sample, or every stroke the
    /// artist has finished, re-walked in canvas points.
    ///
    /// Separate from `rebuild` so a brush edit while the sample is up costs a clear and a walk rather
    /// than a fresh 6 MB context per tick of the slider.
    private func redrawContents() {
        guard committed != nil else { return }
        strokeBase = nil
        inDevicePixels { context, rect in context.clear(rect) }
        if finished.isEmpty && isShowingRestingSample {
            stampRestingSample()
        } else {
            for stroke in finished { stamp(stroke) }
        }
        // `lastStrokeInk` is a fact about a *stroke* rather than about this buffer, and this draws no
        // stroke — so it survives, exactly as it survives the keyboard-driven resize `rebuild` was
        // first written for. A reader that needs a number at the current magnification takes one by
        // drawing.
        setNeedsDisplay()
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

    /// **Clear** — the fourth of §7.2's four behaviours, and the one that was already built.
    ///
    /// It takes the resting sample with it. Redrawing the sample here would make the button look
    /// inert on a pad the artist had not yet drawn on, which is the "refusal with no notice" shape
    /// CLAUDE.md records, reached through a button that did exactly what it said.
    func clear() {
        finished = []
        samples = []
        strokeBase = nil
        isShowingRestingSample = false
        inDevicePixels { context, rect in context.clear(rect) }
        lastStrokeInk = 0
        setNeedsDisplay()
    }

    // MARK: - §7.2's opening sample stroke

    /// Puts the sample stroke up if the pad is empty and nothing has been drawn on it.
    ///
    /// Called on `didMoveToWindow` rather than on `init` because the sample's extent is the pad's own
    /// and a view with no bounds has none.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, finished.isEmpty, !isShowingRestingSample, inkedPixels == 0 else { return }
        isShowingRestingSample = true
        redrawContents()
    }

    /// Re-renders the resting sample after a brush edit, so *"a brush's character is visible before
    /// the artist touches it"* keeps being true while they are moving sliders.
    func refreshRestingSample() {
        guard isShowingRestingSample, finished.isEmpty else { return }
        redrawContents()
    }

    /// **The sample is drawn into a band of the curve's own proportions, centred, not into the whole
    /// pad.** `BrushPreview.samples(in:)` fits the S to whatever extent it is handed — a menu row is
    /// 156 × 26 and the curve is authored against that. MEASURED on the simulator: handed the whole
    /// pad, which is about 330 × 1100 canvas points at real size, the same call produced an S with
    /// 522 points of amplitude over 264 of travel — a vertical zigzag rather than a stroke, and a
    /// picture of the pad's aspect ratio rather than of the brush.
    private func stampRestingSample() {
        guard let committed else { return }
        let extent = canvasSize
        guard extent.width > 1, extent.height > 1 else { return }
        let band = CGSize(width: extent.width, height: min(extent.height, extent.width * 0.5))
        BrushPreview.stampSample(into: CGContextDabTarget(committed), over: band,
                                 offsetBy: CGPoint(x: 0, y: (extent.height - band.height) / 2),
                                 brush: brush, color: color, strokeWidth: strokeSize,
                                 opacity: strokeOpacity)
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
        guard let touch = touches.first else { return }
        // The sample has done its job the moment the artist draws: judging your own stroke on top of
        // one you did not make is the confusion the pad exists to remove.
        if isShowingRestingSample {
            isShowingRestingSample = false
            inDevicePixels { context, rect in context.clear(rect) }
        }
        guard let committed else { return }
        strokeBase = committed.makeImage()
        inkedBefore = countInk()
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
    ///
    /// **The position is divided by the zoom**, because the samples are canvas points and the touch
    /// is in view points. Getting this backwards would draw a stroke a third of the way to where the
    /// finger was, which looks like a broken hit test rather than like a wrong transform.
    private func sample(from touch: UITouch) -> VectorSample {
        let point = BrushPadZoom.canvasPoint(touch.location(in: self), at: zoom)
        let pressure: CGFloat
        if touch.maximumPossibleForce > 0 {
            pressure = min(max(touch.force / touch.maximumPossibleForce, 0.01), 1)
        } else {
            pressure = BrushInput.pressure.neutral
        }
        return VectorSample(point: point, pressure: pressure)
    }

    private func stampCurrentStroke() {
        guard !samples.isEmpty else { return }
        inDevicePixels { context, rect in
            context.clear(rect)
            if let strokeBase { context.draw(strokeBase, in: rect) }
        }
        stamp(FinishedStroke(samples: samples, brush: brush, color: color,
                             size: strokeSize, opacity: strokeOpacity))
        setNeedsDisplay()
    }

    private func stamp(_ stroke: FinishedStroke) {
        guard let committed, !stroke.samples.isEmpty else { return }
        BrushStamper.stampStroke(into: CGContextDabTarget(committed),
                                 samples: StrokeSamples(stroke.samples, channels: .pressureOnly),
                                 brush: stroke.brush,
                                 color: stroke.color,
                                 brushSize: stroke.size,
                                 brushOpacity: stroke.opacity,
                                 isEraser: false,
                                 random: DabRandom(seed: Self.padSeed))
    }

    private func finishStroke() {
        guard !samples.isEmpty else { return }
        finished.append(FinishedStroke(samples: samples, brush: brush, color: color,
                                       size: strokeSize, opacity: strokeOpacity))
        samples = []
        strokeBase = nil
        lastStrokeInk = max(countInk() - inkedBefore, 0)
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
