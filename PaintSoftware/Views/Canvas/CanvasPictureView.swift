import UIKit

/// **A whole-canvas picture on screen, handed to the render server as the window and never as the
/// canvas** — every layer host's ink (`StrokeCanvasView`'s base) and the onion skin.
///
/// A layer's picture is the size of the canvas: 95 MiB at the owner's 5000². Shown as a bitmap on a
/// `UIImageView`, every picture is a fresh copy for `backboardd`, and on a five-layer scene that was
/// one per layer on entering the document, five more on every frame step that settled and one more
/// on every edit — 6.8 GiB handed over a five-minute routine on the iPad 9 simulator (`LayerContentsCensus`,
/// 2026-11-19), and the iPad's server was killed at its 1,850 MiB limit opening that scene
/// (2026-11-18 23:33), as it was killed by the bake's own canvas-sized pictures during playback
/// before `BakedFrameWindow`.
///
/// So the picture stays in the app's memory, and what the server sees is a pair of surfaces the size
/// of the window (`WindowSurfaceView`), into which the visible part of the picture is drawn off the
/// main thread at the screen's own resolution. The server maps each surface once; a new picture, a
/// pan or a zoom is a redraw into a surface it already has. **This view is canvas-sized and carries no
/// contents of its own**, so the pose transform and the base hole mask a caller puts on its layer keep
/// meaning what they meant on the image view it replaces.
///
/// A new picture reaches the screen one draw after it is shown — `landed` runs in the main-thread
/// turn it does, which is where a caller retires whatever was drawn over the old picture meanwhile.
final class CanvasPictureView: UIView {

    /// The picture, in this view's own space (its bounds are the canvas); nil when nothing is shown.
    private(set) var image: UIImage?
    /// An alpha cut drawn with the picture, over the same canvas — the onion skin's.
    private(set) var clip: CGImage?
    /// True once `image` is the picture on screen — false while its first draw is in flight.
    private(set) var isShowingImage = true
    /// **The presenter a layer's pictures go up through** (`WindowSurfaceView.presenter`): while it
    /// holds, this view's new picture waits, drawn, for the rest of its set.
    var presenter: CanvasPresenter? {
        get { surface.presenter }
        set { surface.presenter = newValue }
    }
    /// Whether the picture asked for last is on screen, or drawn and waiting for its set.
    var hasPictureReady: Bool { isShowingImage || (presenter?.hasCurrentPicture(surface) ?? false) }
    /// The onion skin's ghost is magnified bilinear; a layer's ink stays crisp (`LayerHostView.init`).
    var smoothWhenMagnified = false

    private let surface = WindowSurfaceView(queue: CanvasPictureView.drawQueue)
    /// What each shown picture asked to run when it reaches the screen, in the order shown.
    private var landings: [() -> Void] = []

    /// Concurrent, so the layers' draws after a pan run side by side; each view keeps one in flight.
    private static let drawQueue = DispatchQueue(label: "com.paintapp.CanvasPictureView.draw",
                                                 qos: .userInitiated, attributes: .concurrent)

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        surface.layer.magnificationFilter = .linear
        addSubview(surface)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows `image` — the whole canvas, at any resolution with the canvas's aspect — cut by `clip`'s
    /// alpha, or takes the picture down. `landed` runs when it is on screen: at once for nil or for
    /// the picture already up.
    func show(_ image: UIImage?, clip: CGImage? = nil, landed: (() -> Void)? = nil) {
        if image === self.image, clip === self.clip {
            if let landed { isShowingImage ? landed() : landings.append(landed) }
            return
        }
        self.image = image
        self.clip = image == nil ? nil : clip
        guard image != nil else {
            surface.takeDown()
            isShowingImage = true
            let waiting = landings
            landings = []
            waiting.forEach { $0() }
            landed?()
            return
        }
        isShowingImage = false
        if let landed { landings.append(landed) }
        redraw()
    }

    /// The canvas moved under the window (a pan, a zoom, a turn, a pose): draw what is now visible.
    func windowMoved() {
        guard image != nil else { return }
        redraw()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowMoved()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        windowMoved()
    }

    private func redraw() {
        surface.present { [weak self] in self?.mint() }
    }

    /// The draw of the picture and window as they are now, minted when the surface is free.
    private func mint() -> WindowSurfaceView.Frame? {
        guard let picture = image, let cgImage = picture.cgImage, let geometry = currentWindow() else { return nil }
        let canvasSize = bounds.size
        let smooth = smoothWhenMagnified, clip = clip
        let owed = landings.count
        return WindowSurfaceView.Frame(window: geometry.window, placement: geometry.placement, draw: { cg in
            geometry.draw(cgImage, canvasSize: canvasSize, backdrop: nil, smoothWhenMagnified: smooth, clip: clip, in: cg)
            return geometry.window
        }, canPresent: { [weak self] in self?.image === picture && self?.clip === clip }, finished: { [weak self] shown in
            guard shown, let self else { return }
            self.isShowingImage = true
            let due = Array(self.landings.prefix(owed))
            self.landings.removeFirst(min(owed, self.landings.count))
            due.forEach { $0() }
        })
    }

    /// The window's pixels in this view's points, now — through every transform above it.
    private func currentWindow() -> BakedFrameWindow? {
        guard let window, bounds.width > 0, bounds.height > 0 else { return nil }
        let origin = convert(CGPoint.zero, from: window)
        let x = convert(CGPoint(x: 1, y: 0), from: window)
        let y = convert(CGPoint(x: 0, y: 1), from: window)
        let windowToView = CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y,
                                             c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
        return BakedFrameWindow(hostSize: window.bounds.size, screenScale: window.traitCollection.displayScale,
                                hostToCanvas: windowToView)
    }
}
