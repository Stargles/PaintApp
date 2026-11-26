import IOSurface
import UIKit

/// **Where a live picture of part of a layer reaches the screen** — STREAM.md §5.3, TODO (97), and
/// the display of a live element edit, TODO (173).
///
/// One per live picture a layer host is showing, sized to the picture's window and frame-positioned
/// over `StrokeCanvasView.imageView` in canvas points, the way the scratch is positioned at a
/// stroke's window. Its layer's contents is an `IOSurface` — one of two this view owns and
/// alternates between. A picture is drawn into the back surface off the main thread and presenting
/// it is one `contents` assignment of an object the render server already has mapped: **nothing is
/// copied per picture, and nothing new is handed to Core Animation per picture.**
///
/// That is the property the alternative lacks. A picture presented by invalidating the layer's memo
/// and re-rasterizing the canvas costs a canvas-sized allocation, a canvas-sized blit and a fresh
/// canvas-sized `CGImage` on `imageView` for Core Animation to copy to the render server — per
/// frame of a live stream (thirty a second), per tick of a live edit (ten or more a second, at 64 MB
/// a time on a 4096² canvas). On the owner's iPad the render server reached its limit and was killed
/// both ways, which is a black screen and a respring: the four `backboardd` jetsam events of
/// 2026-09-14/15 behind TODO (97), and the two of 2026-10-12 behind TODO (173).
///
/// **Two surfaces, not one**, so the render server never samples the pixels being written: the
/// front surface is what is on screen while the back one is drawn, and they swap at the present.
/// **The draws go through a `LatestWins`** (TODO (179)): one in flight, and a picture asked for
/// during it waits — replaced by any newer one — and is drawn when it lands, so the newest picture
/// asked for is always the one left on screen, a burst's last stream frame and an edit's last tick
/// alike, with no caller drawing again to catch up. The back surface is free whenever a draw is
/// minted, because only one is in flight. The window is cleared before each draw because the
/// picture's shape can change between frames (a nudge in the Move box) and the pixels outside the
/// new shape must be transparent, not last frame's.
final class WindowSurfaceView: UIView {
    /// A reference frame can wait for Core Animation to release its back surface. Keep that
    /// wait off the edit queue, with one worker shared by all On Top stream windows.
    static let onTopStreamQueue = DispatchQueue(label: "com.paintapp.WindowSurfaceView.onTopStream",
                                                qos: .userInitiated)

    typealias SurfaceFactory = (_ width: Int, _ height: Int) -> IOSurface?

    static func makeSurface(width: Int, height: Int) -> IOSurface? {
        IOSurface(properties: [
            .width: width, .height: height, .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ])
    }


    /// Counts an allocation for its actual lifetime, including a draw finishing after cancellation
    /// or a finished picture waiting for the base. Moving ownership never changes the byte count.
    fileprivate final class Surface {
        let surface: IOSurface
        let context: CGContext

        init(surface: IOSurface, context: CGContext) {
            self.surface = surface
            self.context = context
            WindowSurfaceView.adjustResidentBytes(by: surface.allocationSize)
        }

        deinit { WindowSurfaceView.adjustResidentBytes(by: -surface.allocationSize) }
    }

    /// The exact picture already shown, with no bitmap copy. Its surface is removed from the view's
    /// writable pair before it escapes; retaining this value keeps that allocation accounted for.
    struct FrozenWindow {
        fileprivate let storage: Surface
        let window: CGRect
        let placement: CGAffineTransform
        var surface: IOSurface { storage.surface }

        func makeView() -> UIView {
            let view = UIView()
            view.layer.anchorPoint = .zero
            WindowSurfaceView.placeLayer(view.layer, in: window, by: placement)
            view.layer.contents = surface
            view.layer.contentsScale = 1
            view.layer.contentsGravity = .resize
            view.layer.magnificationFilter = .nearest
            view.layer.minificationFilter = .trilinear
            view.isUserInteractionEnabled = false
            return view
        }
    }

    /// Both surfaces, once `size(for:)` has made them; empty before the first present.
    private var surfaces: [Surface] = []
    private var back = 0
    /// The actual front, including its old placement while a resized window is still drawing.
    private var presented: FrozenWindow?
    /// The draws, on the queue the view was made with — see the class comment.
    private let draws: LatestWins
    private let surfaceFactory: SurfaceFactory

    /// **How long every draw waits after its clear, on the view's queue** — zero on every ordinary
    /// launch, and set only by `UITestSeeds.applyWindowDrawDelayIfRequested`
    /// (`-uiTestSlowWindowDrawMillis`, simulator only), so a test can stage the iPad's draw time. Read
    /// at the mint, with the rest of the frame's values.
    static var drawDelay: TimeInterval = 0

    fileprivate static func placeLayer(_ layer: CALayer, in window: CGRect,
                                       by placement: CGAffineTransform) {
        layer.bounds = CGRect(origin: .zero, size: window.size)
        layer.position = window.origin.applying(placement)
        layer.setAffineTransform(CGAffineTransform(a: placement.a, b: placement.b,
            c: placement.c, d: placement.d, tx: 0, ty: 0))
    }

    /// **The bytes every view's surfaces hold, process-wide** — what a live picture costs in memory
    /// while it is up (two canvas-sized surfaces for a held frame, PERFORMANCE.md §30), including
    /// frozen pictures and cancelled draws still using their allocation. `PlaybackProbe` reports its peak.
    private static let residentLock = NSLock()
    private static var residentTotal = 0
    static var residentBytes: Int {
        residentLock.lock()
        defer { residentLock.unlock() }
        return residentTotal
    }

    /// A cancelled worker can release its last allocation off main.
    private static func adjustResidentBytes(by delta: Int) {
        residentLock.lock()
        defer { residentLock.unlock() }
        residentTotal += delta
    }

    /// **The presenter this surface's pictures go up through** (SCHEDULER.md rule 10): while it holds, a
    /// finished draw is parked with it rather than swapped, and goes up with the rest of its set. Nil
    /// for a surface that is a set of its own — the baked frame, a stream window.
    weak var presenter: CanvasPresenter?
    /// A finished draw is parked with the presenter: no new draw starts into the back surface it holds.
    var hasParkedPicture: Bool { parked != nil }
    /// Which park is outstanding, so an older park's drop cannot clear a newer one.
    private var parked: Int?
    private var parks = 0
    /// Moved by `takeDown` and `freezePresented`, so a parked swap from before either never shows.
    private var parkGeneration = 0
    /// The newest frame asked for while a picture was parked, drawn once it goes up or is dropped.
    private var askedWhileParked: (() -> Frame?)?

    /// How many frames have been presented — for tests, which spin the run loop until it moves.
    private(set) var presentedCount = 0
    /// Every view's presents, process-wide, main thread only — `draws:` on `canvas.host`, what an Undo
    /// storm's pictures cost the render server is read off this.
    nonisolated(unsafe) static var presentedTotal = 0
    /// The window the surfaces are sized to, in canvas points; `.null` before the first present.
    private(set) var surfaceWindow = CGRect.null
    /// The window whose pixels reached the front, including an older front during a resize.
    var presentedWindow: CGRect? { isHidden ? nil : presented?.window }

    /// `queue` is where every picture is drawn. Views sharing a serial queue take turns.
    convenience init(queue: DispatchQueue, surfaceFactory: @escaping SurfaceFactory = WindowSurfaceView.makeSurface) {
        self.init(draws: LatestWins(queue: queue), surfaceFactory: surfaceFactory)
    }

    /// `draws` is where every picture is drawn — a `LatestWins` on the scheduler, shared by views that
    /// are to take turns.
    init(draws: LatestWins, surfaceFactory: @escaping SurfaceFactory = WindowSurfaceView.makeSurface) {
        self.draws = draws
        self.surfaceFactory = surfaceFactory
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isHidden = true
        // One canvas point is one surface pixel, exactly as `imageView` shows a canvas-sized bitmap
        // in a canvas-sized frame; the same sample filters as its siblings, for the same crispness
        // contract (`StrokeCanvasView.init`).
        layer.contentsScale = 1
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .trilinear
        // Placed by `position` at the window's own origin, so a canvas `transform` can be applied
        // about the canvas origin rather than about the view's centre — see `present`.
        layer.anchorPoint = .zero
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Transfers the last picture actually shown. Cancelling prevents an older landing or waiting
    /// request from changing it; clearing the writable pair prevents future draws from reusing it.
    /// An in-flight draw owns only the other surface and may finish safely in the background.
    func freezePresented() -> FrozenWindow? {
        draws.cancel()
        dropParked()
        let frozen = presented
        presented = nil
        layer.contents = nil
        isHidden = true
        surfaces.removeAll()
        surfaceWindow = .null
        back = 0
        return frozen
    }

    /// **One frame, as the main thread mints it**: where it goes and how it is drawn.
    ///
    /// `window` is the picture's rectangle in the parent's points before `placement`; `placement` is
    /// the affine this layer applies after drawing, such as the stretch of a reduced composite
    /// over the canvas. `draw` runs
    /// on the view's queue with a UIKit context whose origin is the window's top-left corner and
    /// returns the rectangle it actually drew — `VectorCanvas.drawStreamWindow`'s answer — or nil to
    /// abandon; a rectangle other than `window` means the element moved between the two reads, and the
    /// frame is dropped rather than shown in the wrong place. The next present sizes again.
    ///
    /// `canPresent` checks the frame's owner on the main queue immediately before the swap.
    /// A refusal keeps the previous front. `finished` runs on the main queue when the draw is over
    /// and reports whether it became the layer's contents, so a caller waiting for it may stop
    /// waiting (a base hole punched before it would show the pixels under it for a frame).
    /// **Takes the picture down and keeps the two surfaces**, so the next picture is presented into
    /// surfaces the render server has already been handed — a host blanked for playback and shown
    /// again hands it nothing new (`CanvasPictureView`).
    func takeDown() {
        draws.cancel()
        dropParked()
        presented = nil
        layer.contents = nil
        isHidden = true
    }

    struct Frame {
        let window: CGRect
        let placement: CGAffineTransform
        let draw: (CGContext) -> CGRect?
        var canPresent: (@MainActor () -> Bool)? = nil
        var finished: ((_ shown: Bool) -> Void)? = nil
    }

    /// **Asks for one frame, minted when no draw is in flight** — now if the surface is free, or when
    /// the draw in flight lands, unless a newer frame is asked for first. `mint` runs on the main
    /// thread against whatever it reads *then*, so a caller whose frame is expensive to describe (a
    /// whole-frame recipe) describes it once per draw rather than once per request; nil skips. A frame
    /// replaced before it was minted is never drawn, and its `finished` never runs.
    func present(_ mint: @escaping () -> Frame?) {
        draws.request { [weak self] in
            guard let self else { return nil }
            guard !self.hasParkedPicture else {
                self.askedWhileParked = mint
                return nil
            }
            guard let frame = mint() else { return nil }
            guard let work = self.drawing(frame) else {
                frame.finished?(false)
                return nil
            }
            return work
        }
    }

    /// **The first picture, drawn and shown in the turn that asks for it** — for a view that appears
    /// in place of a picture already on screen, where the turns a first draw off the main thread takes
    /// would show neither: a freehand stroke the moment it becomes a smart shape (`ShapeOverlayView`).
    /// Only while the view shows nothing and no draw is in flight — past the first picture, a draw on
    /// the main thread is what `present` exists to keep off it, and it would wait here on the render
    /// server letting the back surface go. Otherwise it is `present`.
    func presentFirst(_ frame: Frame) {
        guard layer.contents == nil, !draws.isBusy, let draw = drawing(frame) else {
            present { frame }
            return
        }
        draw()()
    }

    /// **One frame's draw and landing**, minted on the main thread while no draw is in flight — so the
    /// surfaces may be remade here and the back one is not being written. Nil when there is no surface
    /// to draw into.
    private func drawing(_ frame: Frame) -> LatestWins.Work? {
        let window = frame.window, placement = frame.placement
        let draw = frame.draw, canPresent = frame.canPresent, finished = frame.finished
        size(for: window)
        guard surfaces.count == 2 else { return nil }
        let target = surfaces[back]
        let delay = Self.drawDelay
        return { [weak self] in
            // **The back surface may still be on screen.** It was the contents until the swap that
            // put the other one up, and that swap reaches the render server only when the main
            // thread's transaction commits — while this draw is minted *in* the landing's turn
            // (`LatestWins` mints as the last draw lands). Cleared now, the server would show one
            // frame of whatever is under the view. So the draw waits, here off the main thread,
            // until the server has let the surface go — bounded at half a second, past the
            // longest busy turn the owner's iPad 9 recorded (182 ms), so a server that never says
            // so costs one wait rather than the picture.
            let released = DispatchTime.now() + .milliseconds(500)
            while target.surface.isInUse, DispatchTime.now() < released { usleep(500) }
            _ = target.surface.lock(options: [], seed: nil)
            let cg = target.context
            cg.clear(CGRect(origin: .zero, size: window.size))
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            UIGraphicsPushContext(cg)
            let drawn = draw(cg)
            UIGraphicsPopContext()
            _ = target.surface.unlock(options: [], seed: nil)
            return { [weak self] in
                guard let self else { return }
                let generation = self.parkGeneration
                let isCurrent = { [weak self] () -> Bool in
                    guard let self else { return false }
                    return generation == self.parkGeneration && drawn == window && self.surfaces.count == 2
                        && self.surfaceWindow == window && canPresent?() != false
                }
                let swap = { [weak self] in
                    guard let self else { return }
                    guard isCurrent() else {
                        finished?(false)
                        return
                    }
                    self.layer.contents = target.surface
                    self.presented = FrozenWindow(storage: target, window: window, placement: placement)
                    Self.placeLayer(self.layer, in: window, by: placement)
                    self.isHidden = false
                    self.back = 1 - self.back
                    self.presentedCount += 1
                    Self.presentedTotal += 1
                    finished?(true)
                }
                guard let presenter = self.presenter, presenter.isHolding, isCurrent() else { return swap() }
                // Drawn, and waiting for its set: the back surface holds it until the set goes up.
                self.parks += 1
                let token = self.parks
                self.parked = token
                let settle = { [weak self] in
                    guard let self, self.parked == token else { return }
                    self.parked = nil
                    self.drawAskedWhileParked()
                }
                presenter.park(self, isCurrent: isCurrent, swap: {
                    swap()
                    settle()
                }, drop: {
                    finished?(false)
                    settle()
                })
            }
        }
    }

    /// A parked picture will never go up — the view was taken down or frozen. The presenter's entry
    /// for it fails `isCurrent` from now on.
    private func dropParked() {
        parkGeneration += 1
        parked = nil
        askedWhileParked = nil
    }

    private func drawAskedWhileParked() {
        guard let mint = askedWhileParked else { return }
        askedWhileParked = nil
        present(mint)
    }

    /// `present(_:)` for a frame whose description is already in hand — a stream element's newest
    /// frame, an element edit's newest tick.
    func present(window: CGRect, placement: CGAffineTransform,
                 draw: @escaping (CGContext) -> CGRect?,
                 finished: ((_ shown: Bool) -> Void)? = nil) {
        present { Frame(window: window, placement: placement, draw: draw, finished: finished) }
    }

    /// Makes the two surfaces for `window`, or keeps the ones already that size. A window of a
    /// different size retires the previous front only when the new first picture lands. The old
    /// layer bounds stay put meanwhile; at most one extra front is held across a resize.
    private func size(for window: CGRect) {
        guard surfaceWindow.size != window.size || surfaces.count != 2 else {
            surfaceWindow = window
            return
        }
        surfaces = []
        surfaceWindow = window
        let width = Int(window.width), height = Int(window.height)
        guard width > 0, height > 0 else { return }
        for _ in 0..<2 {
            guard let surface = surfaceFactory(width, height) else { return }
            // The same 8-bit premultiplied BGRA every raster tier renders as; the context is made
            // once over the surface's own memory, flipped so it is the UIKit context
            // `VectorCanvas.drawStreamWindow` expects (`UIImage.draw(in:)` in the placed arms).
            guard let context = CGContext(data: surface.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            surfaces.append(Surface(surface: surface, context: context))
        }
    }
}
