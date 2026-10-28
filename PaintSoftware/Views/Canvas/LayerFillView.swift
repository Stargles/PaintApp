import UIKit

/// The live fill picture in one layer's posed plane, independent of its stroke input owner.
final class LayerFillView: UIView {
    /// The adjustable fill's picture (`showFill`) — made with the fill's first render, and let go with
    /// the fill.
    private var fillSurface: WindowSurfaceView?
    /// The render and clip `fillSurface` was last asked to show, so the passes that change nothing are
    /// two identity checks.
    private var shownFill: (render: CanvasManager.FillRenderResult, clip: CGPath?)?
    /// Fences a refusal for an older A request after a reentrant A→B→A replacement.
    private var fillAttempt: UInt64 = 0
    /// Where every host's fill pictures are drawn — one fill is live at a time.
    private static let fillDrawQueue = DispatchQueue(label: "com.paintapp.LayerFillView.fill",
                                                     qos: .userInteractive)
    private let drawQueue: DispatchQueue
    private let surfaceFactory: WindowSurfaceView.SurfaceFactory


    convenience init() { self.init(queue: Self.fillDrawQueue) }

    init(queue: DispatchQueue,
         surfaceFactory: @escaping WindowSurfaceView.SurfaceFactory = WindowSurfaceView.makeSurface) {
        drawQueue = queue
        self.surfaceFactory = surfaceFactory
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// **Shows the adjustable fill's render over this layer's own pixels, or nothing**, and answers
    /// whether that changed anything — TODO (179). The bytes are drawn into a surface off the main
    /// thread (`WindowSurfaceView`) through the same `FillRenderResult.preview(clippedTo:)` the commit
    /// flattens, so a render reaches the screen with no image built on the main thread and none handed
    /// to Core Animation, and the picture does not change when the pencil lifts.
    ///
    /// The surface is the render's window at the window's working size, stretched over the window's
    /// rect — 1:1 at scale 1, and below it the resample the fill already accepted. The host's points
    /// are canvas pixels (the stack is magnified by a transform on the container), so the rect is
    /// placed in them directly, through the layer's pose (`fillPlane`).
    @discardableResult
    func showFill(_ render: CanvasManager.FillRenderResult?, clip: CGPath?) -> Bool {
        guard let render else {
            guard shownFill != nil || fillSurface != nil || !subviews.isEmpty else { return false }
            fillAttempt &+= 1
            shownFill = nil
            fillSurface = nil
            for surface in subviews { surface.removeFromSuperview() }
            return true
        }
        guard shownFill?.render !== render || shownFill?.clip !== clip else { return false }
        fillAttempt &+= 1
        let attempt = fillAttempt
        shownFill = (render, clip)
        let window = CGRect(x: 0, y: 0, width: render.window.workingWidth, height: render.window.workingHeight)
        if fillSurface == nil {
            let surface = WindowSurfaceView(queue: drawQueue, surfaceFactory: surfaceFactory)
            addSubview(surface)
            fillSurface = surface
        }
        fillSurface?.present(window: window, placement: render.window.transform.inverted(), draw: { _ in
            guard let preview = render.preview(clippedTo: clip) else { return nil }
            preview.image.draw(in: window)
            return window
        }, finished: { [weak self] shown in
            guard !shown, let self, self.fillAttempt == attempt,
                  self.shownFill?.render === render, self.shownFill?.clip === clip else { return }
            self.shownFill = nil
        })
        return true
    }

}
