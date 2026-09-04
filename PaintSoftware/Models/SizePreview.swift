import Combine
import CoreGraphics
import UIKit

/// The real-size stamp preview that appears beside a size slider while it is held.
///
/// **Everything here is outside a `View` file on purpose.** `PaintSoftwareUITests` compiles a second
/// copy of a hand-picked list of app sources (see the project file's Sources build phase) and none of
/// `SideToolbar.swift` / `StrokeSettingsPanel.swift` / `DrawingView.swift` is on it — so any
/// arithmetic that lives in one of those is arithmetic no fast-tier test can reach. That is the same
/// reason `ObjectTransformFrame` exists next door, and the split is the same: the model owns the
/// geometry and the state machine, the view owns layers and touches.
///
/// The one number this feature exists to get right is **the size the stamp lands on screen**, which
/// is canvas points times the *current* canvas zoom — not slider units. A 40-point brush on a canvas
/// displayed at 0.3× makes a 12-point mark, and drawing 40 would be a confident lie of exactly the
/// kind `ADD_TEXT.md` §1 records: `TransformHandleView`'s fixed 24×24 inside a transformed container
/// made the Move handles unfindable at low zoom for the mirror-image reason.

// MARK: - What is being previewed

/// Which of the two tools' size the preview is showing. The paint brush and the eraser keep entirely
/// separate size/opacity/preset state on `CanvasManager` (`brushSize`/`selectedBrush` vs
/// `eraserSize`/`selectedEraserBrush`), so the preview has to be told which set to read.
enum SizePreviewTool: String, Equatable {
    case brush
    case eraser
}

/// Which side of the slider the window sits on — chosen per surface so the artist's own hand is not
/// on top of the thing they asked to see.
///
/// - `above`: for the left rail's **vertical** slider. A hand on a vertical slider covers the track
///   and everything below-and-beside the contact point, and the contact point travels the whole
///   track, so there is no clear spot level with it. Above the track is clear for every value.
/// - `leading`: for the settings panel's **horizontal** slider. That panel is a 300-point dropdown
///   pinned to the trailing edge and the hand is inside its bounds, so anything past its leading
///   edge is uncovered whatever the thumb is doing.
enum SizePreviewSide: Equatable {
    case above
    case leading
}

/// Which size slider raised the preview, and what it is showing.
///
/// `sliderID` is the slider's own accessibility identifier. It is what makes a lift *specific*: the
/// brush panel's Size slider and the rail's Size slider drive the same `brushSize` and would
/// otherwise be indistinguishable, so a stale "editing ended" from one could dismiss a preview the
/// other had just raised.
struct SizePreviewRequest: Equatable {
    let sliderID: String
    let tool: SizePreviewTool
    let side: SizePreviewSide

    init(sliderID: String, tool: SizePreviewTool, side: SizePreviewSide) {
        self.sliderID = sliderID
        self.tool = tool
        self.side = side
    }

    /// The tool's live diameter in canvas points, picked from the two parallel sets of state
    /// `CanvasManager` keeps. The same pick `CanvasView` makes when it pushes settings at the stroke
    /// view — written here rather than in the window's `body` so a test can prove the eraser reads
    /// `eraserSize` and not `brushSize`, which a `View` file could never be asked.
    func toolSize(brushSize: CGFloat, eraserSize: CGFloat) -> CGFloat {
        tool == .eraser ? eraserSize : brushSize
    }

    /// Its twin for opacity — `eraserOpacity` is separate from `brushOpacity` for the same reason.
    func opacity(brushOpacity: Double, eraserOpacity: Double) -> Double {
        tool == .eraser ? eraserOpacity : brushOpacity
    }
}

// MARK: - Visibility

/// Down shows, lift hides, and a value change in between is not an event at all.
///
/// Two things drive it, and it takes both. A `DragGesture(minimumDistance: 0)` attached alongside
/// the slider reports the **touch-down**, which is what the owner asked for and which
/// `Slider.onEditingChanged` does *not* give: measured 2026-08-22, a press on the thumb that never
/// moves produces no editing event at all, because SwiftUI only calls it once a drag begins. The
/// slider's own `onEditingChanged` stays wired up as the second reporter of the **lift**, so a
/// cancelled drag still lowers the window. See `View.sizePreviewSlider`.
///
/// Value changes arrive on the value binding instead and never reach here, so dragging the slider
/// cannot dismiss the preview it just raised. A repeated `true` (both reporters can emit one)
/// re-asserts the same request rather than toggling it off.
struct SizePreviewVisibility: Equatable {
    private(set) var active: SizePreviewRequest?

    init() {}

    var isVisible: Bool { active != nil }
    var tool: SizePreviewTool? { active?.tool }

    /// `isEditing` is "a finger is on this slider": true from the drag gesture's first touch or from
    /// `Slider.onEditingChanged(true)`, false from either one's end. Both reporters are idempotent
    /// here, so it does not matter which of them arrives first or whether both do.
    ///
    /// The end branch is guarded on the slider's identity, not merely on "something ended": see
    /// `SizePreviewRequest.sliderID`.
    mutating func editingChanged(_ isEditing: Bool, for request: SizePreviewRequest) {
        if isEditing {
            active = request
            return
        }
        guard active?.sliderID == request.sliderID else { return }
        active = nil
    }

    /// Anything that takes the slider out from under the finger without an `onEditingChanged(false)`
    /// — the panel closing, the tool changing. Cheap insurance against a preview stranded on screen.
    mutating func dismiss() { active = nil }
}

// MARK: - Geometry

/// Where the window goes and how big the stamp inside it is.
///
/// Pure arithmetic over two numbers: the tool's size in **canvas points** (what the slider sets) and
/// the canvas's current **screen points per canvas point** (what the pinch/fit transform makes of
/// it). Their product is the only honest answer to "how big will this mark be", and it is what
/// `stampDiameter` returns.
struct SizePreviewGeometry: Equatable {
    /// The window never grows past this, whatever the brush is set to. Sized to sit comfortably
    /// beside a 64-point rail on the narrowest iPad the app runs on without covering the artwork.
    static let maximumWindowSide: CGFloat = 176
    /// …and never shrinks below this, so a 1-point brush at 0.125× is still a window the artist can
    /// see rather than a 0.125-point speck.
    static let minimumWindowSide: CGFloat = 56
    /// Breathing room between the stamp and the window's edge, so a stamp that *does* fit visibly
    /// fits rather than touching the border and reading as clipped.
    static let margin: CGFloat = 14
    /// Distance between the slider and the window.
    static let gap: CGFloat = 10
    /// Keeps the window off the screen edges when the clamp has to move it.
    static let screenInset: CGFloat = 8

    /// The tool's size as the slider sets it — canvas points.
    var toolSize: CGFloat
    /// Screen points per canvas point, live, from the canvas's own transform.
    var canvasScale: CGFloat

    init(toolSize: CGFloat, canvasScale: CGFloat) {
        self.toolSize = toolSize
        self.canvasScale = canvasScale
    }

    /// **The number the whole feature is about.** The diameter, in screen points, of the mark this
    /// tool will leave on the artwork as the artist is currently looking at it.
    ///
    /// Matches `StrokeGeometry.stampRadius(forPressure: 1, brush:, size:)` doubled — at full
    /// pressure every `BrushDynamics.sizeFraction` is exactly 1, so the stamp is the brush's own
    /// `size`, which `Brush.size` documents as "base stamp diameter, in canvas points, at full
    /// pressure". Multiplying by the canvas scale converts that to what the eye sees.
    var stampDiameter: CGFloat { max(toolSize, 0) * max(canvasScale, 0) }

    /// The side of the square window.
    var windowSide: CGFloat {
        min(max(stampDiameter + 2 * Self.margin, Self.minimumWindowSide), Self.maximumWindowSide)
    }

    /// True when the stamp is larger than the window can ever be, so it is drawn at real size and cut
    /// off by the window's edge.
    ///
    /// **Never scaled down to fit**, by ruling: scaling to fit destroys the only thing the preview
    /// exists to communicate. The view makes the crop obviously deliberate (a dashed border and a
    /// caption) so it does not read as a rendering fault.
    var isClipped: Bool { stampDiameter > Self.maximumWindowSide }

    /// Top-left of the window, given the slider's frame and the surrounding bounds, both in the same
    /// coordinate space.
    ///
    /// Clamped into `bounds` so a slider near an edge does not push the window off screen; the clamp
    /// is written low-bound-last so a bounds smaller than the window degrades to "flush with the
    /// leading/top edge" rather than to a negative-width nonsense.
    static func windowOrigin(sliderFrame: CGRect, side: SizePreviewSide,
                             windowSide: CGFloat, within bounds: CGRect) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch side {
        case .above:
            x = sliderFrame.midX - windowSide / 2
            y = sliderFrame.minY - gap - windowSide
        case .leading:
            x = sliderFrame.minX - gap - windowSide
            y = sliderFrame.midY - windowSide / 2
        }
        return CGPoint(x: clamp(x, low: bounds.minX + screenInset, high: bounds.maxX - screenInset - windowSide),
                       y: clamp(y, low: bounds.minY + screenInset, high: bounds.maxY - screenInset - windowSide))
    }

    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        max(low, min(value, high))
    }
}

// MARK: - The canvas's live scale

/// Screen points per canvas point, pushed from `CanvasView.Coordinator` and read by the preview.
///
/// **Its own `ObservableObject`, deliberately not a `@Published` on `CanvasManager`.** The scale
/// changes on every frame of a pinch, and `CanvasManager` is observed by essentially every view in
/// the app — republishing it 60 times a second would re-evaluate the whole SwiftUI tree for the sake
/// of one small window. Here, only the preview subscribes.
///
/// It also stays *silent* unless a preview is actually on screen. `record` is called from
/// `applyTransform`, which runs inside `updateUIView` on some passes, and publishing from inside a
/// view update is both a SwiftUI warning and pointless when nothing is listening. `latest` keeps the
/// value anyway so `beginPublishing` can hand the preview an up-to-date number the instant it opens.
final class CanvasDisplayScale: ObservableObject {
    /// What the preview reads. Only moves while a preview is up.
    @Published private(set) var scale: CGFloat = 1
    /// What the canvas last reported, listening or not.
    private(set) var latest: CGFloat = 1
    private var isPublishing = false

    init() {}

    /// One canvas point in screen points, from `fitScale * committedScale * liveScale`.
    func record(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        latest = value
        guard isPublishing, value != scale else { return }
        scale = value
    }

    /// Called on slider touch-down: catch up to the canvas, then track it live so a pinch with the
    /// other hand resizes the stamp under the artist's eye.
    func beginPublishing() {
        isPublishing = true
        if scale != latest { scale = latest }
    }

    /// Called on lift.
    func endPublishing() { isPublishing = false }
}

// MARK: - Rendering the stamp

/// Draws one dab of the real brush, at real size, into an image the preview window shows.
///
/// **This is `BrushStamper.stampDab` itself, not an approximation of it** — the same call the canvas
/// makes, through the same `CGContextDabTarget` `VectorCanvas.renderLocalContent` renders strokes
/// with. Shape, hardness, flow, opacity, colour, scatter and the square brush's dab lattice
/// therefore all come out right for free, and stay right when the brush engine changes.
enum SizePreviewStampRenderer {

    /// The ink an eraser preview punches its hole out of.
    ///
    /// **Fixed, not the artist's colour.** An eraser dab does not paint, it removes, so "eraser
    /// coloured ink" would be a picture of something the tool never does — `EraserSettingsPanel`'s
    /// own preview already records that the eraser's colour is irrelevant. What the artist is judging
    /// is the size and the softness of the removal, and a fixed mid-tone against the checkerboard
    /// guarantees both read whatever the palette is set to; the artist's own colour would vanish into
    /// the checker the day they picked white.
    static let eraserInk = UIColor(red: 0.31, green: 0.34, blue: 0.40, alpha: 1)

    /// A square image `geometry.windowSide` points on a side with one dab centred in it.
    ///
    /// For the brush that is the dab alone, over transparency (the window puts white paper behind
    /// it). For the eraser the square is filled with `eraserInk` first and the dab is composited
    /// `.destinationOut`, so the image comes back with a hole in it and the window's checkerboard
    /// shows through — the removal drawn as a removal.
    ///
    /// The dab is stamped at pressure 1 because that is what the slider's number means (see
    /// `SizePreviewGeometry.stampDiameter`), and from a field keyed to the **brush's** own id so a
    /// scattering brush does not jitter its preview on every SwiftUI pass — the same reason stored
    /// vector strokes are replayed from a stored seed rather than re-rolled. A brush is not a stroke
    /// and has no seed of its own; its id is the stable identity to hand `DabRandom.seed(for:)`, and
    /// it is what makes two previews of one brush agree.
    ///
    /// A stamp larger than the window is not scaled: Core Graphics clips it to the context, which is
    /// exactly the real-size crop that was asked for.
    static func stampImage(geometry: SizePreviewGeometry, brush: Brush, tool: SizePreviewTool,
                           color: UIColor, opacity: Double) -> UIImage {
        let side = max(geometry.windowSide, 1)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let isEraser = tool == .eraser
            if isEraser {
                eraserInk.setFill()
                cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }
            let target = CGContextDabTarget(cg)
            BrushStamper.stampDab(into: target,
                                  at: CGPoint(x: side / 2, y: side / 2),
                                  pressure: 1,
                                  brush: brush,
                                  color: color,
                                  brushSize: geometry.stampDiameter,
                                  brushOpacity: opacity,
                                  isEraser: isEraser,
                                  random: DabRandom(seed: DabRandom.seed(for: brush.id)),
                                  arcWidths: 0)
        }
    }
}
